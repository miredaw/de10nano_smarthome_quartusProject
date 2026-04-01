----------------------------------------------------------------------------------
-- UART Transceiver
-- Generic UART for both ESP32 (115200 baud) and SIM800L (9600 baud)
-- 8N1 format: 8 data bits, no parity, 1 stop bit
----------------------------------------------------------------------------------

library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned/signed arithmetic

entity uart_transceiver is
    Generic (
        CLK_FREQ    : integer := 50_000_000;  -- Input clock frequency in Hz (50 MHz on DE10-Nano)
        BAUD_RATE   : integer := 115200       -- UART baud rate; default matches ESP32 AT interface
    );
    Port (
        clk         : in  std_logic;   -- 50 MHz system clock
        reset       : in  std_logic;   -- Active-high synchronous reset

        -- TX interface (caller provides byte to send)
        tx_data     : in  std_logic_vector(7 downto 0);  -- Byte to transmit (8N1)
        tx_start    : in  std_logic;                      -- One-cycle pulse: latch tx_data and start transmission
        tx_busy     : out std_logic;                      -- '1' while transmitter is active (start/data/stop)
        tx_done     : out std_logic;                      -- One-cycle pulse when stop bit finishes

        -- RX interface (delivers received byte)
        rx_data     : out std_logic_vector(7 downto 0);  -- Last received byte (valid when rx_valid pulses)
        rx_valid    : out std_logic;                      -- One-cycle pulse when a valid frame has been received
        rx_error    : out std_logic;                      -- One-cycle pulse when framing error detected

        -- Physical UART lines
        uart_tx     : out std_logic;   -- UART TX output pin (idle high)
        uart_rx     : in  std_logic    -- UART RX input pin from external device
    );
end uart_transceiver;

architecture Behavioral of uart_transceiver is

    -- Baud rate divisor: number of 50 MHz clock cycles per bit period
    constant BAUD_DIV : integer := CLK_FREQ / BAUD_RATE;   -- e.g. 50_000_000/115200 = 434 cycles/bit

    -- TX baud generator counter and tick signal
    signal tx_baud_counter : integer range 0 to BAUD_DIV := 0;   -- Counts cycles since last TX tick
    signal tx_baud_tick    : std_logic := '0';                    -- One-cycle pulse every BAUD_DIV cycles

    -- RX baud generator counter and tick signal (separate so it can be pre-loaded for centering)
    signal rx_baud_counter : integer range 0 to BAUD_DIV := 0;   -- Counts cycles since last RX tick
    signal rx_baud_tick    : std_logic := '0';                    -- One-cycle pulse when RX sampling point reached

    -- TX Finite State Machine states (8N1 frame: start bit -> 8 data bits -> stop bit)
    type tx_state_type is (TX_IDLE, TX_STARTBIT, TX_DATABIT, TX_STOPBIT);
    signal tx_state     : tx_state_type := TX_IDLE;   -- Current TX state
    signal tx_bit_index : integer range 0 to 7 := 0;  -- Which data bit (0=LSB) is being sent
    signal tx_shift_reg : std_logic_vector(7 downto 0) := (others => '0');  -- Shift register holding byte to send

    -- RX Finite State Machine states
    type rx_state_type is (RX_IDLE, RX_STARTBIT, RX_DATABIT, RX_STOPBIT);
    signal rx_state     : rx_state_type := RX_IDLE;   -- Current RX state
    signal rx_bit_index : integer range 0 to 7 := 0;  -- Which data bit is being received
    signal rx_shift_reg : std_logic_vector(7 downto 0) := (others => '0');  -- Accumulates received bits

    -- RX input synchroniser and sampling control
    -- 3-stage synchroniser prevents metastability on the async UART_RX input
    signal rx_sync      : std_logic_vector(2 downto 0) := (others => '1');  -- [0]=newest, [2]=synchronised
    signal rx_baud_load : std_logic := '0';  -- One-cycle pulse that pre-loads RX counter for bit-centre sampling

begin

    --------------------------
    -- TX Baud Rate Generator:
    -- Generates a tick every BAUD_DIV cycles while TX is active.
    -- Counter is held at 0 in TX_IDLE so it starts cleanly on the next TX.
    --------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            tx_baud_counter <= 0;      -- Reset cycle counter
            tx_baud_tick    <= '0';    -- No tick pending
        elsif rising_edge(clk) then
            tx_baud_tick <= '0';   -- Default: no tick this cycle

            if tx_state = TX_IDLE then
                tx_baud_counter <= 0;   -- Hold counter at 0 when idle so first bit starts at a full period
            else
                if tx_baud_counter = BAUD_DIV - 1 then
                    tx_baud_counter <= 0;         -- Reset on expiry
                    tx_baud_tick    <= '1';        -- Assert tick: time to advance to next bit
                else
                    tx_baud_counter <= tx_baud_counter + 1;  -- Keep counting
                end if;
            end if;
        end if;
    end process;

    --------------------------
    -- TX FSM: serialises the 8N1 frame onto uart_tx
    --------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            tx_state     <= TX_IDLE;              -- Start in idle
            uart_tx      <= '1';                  -- UART idle line is logic high
            tx_busy      <= '0';                  -- Not busy at reset
            tx_done      <= '0';                  -- No done event
            tx_bit_index <= 0;                    -- Reset bit counter
            tx_shift_reg <= (others => '0');      -- Clear shift register

        elsif rising_edge(clk) then
            tx_done <= '0';   -- Clear done pulse; only held for one cycle

            case tx_state is

                when TX_IDLE =>
                    uart_tx <= '1';   -- Keep TX high (idle level) between frames
                    tx_busy <= '0';   -- Signal that transmitter is available

                    if tx_start = '1' then
                        tx_shift_reg <= tx_data;     -- Latch the byte to transmit into shift register
                        tx_busy      <= '1';          -- Mark transmitter as busy immediately
                        tx_state     <= TX_STARTBIT;  -- Begin frame with start bit
                    end if;

                when TX_STARTBIT =>
                    uart_tx <= '0';   -- Start bit: drive TX low for one full bit period

                    if tx_baud_tick = '1' then
                        tx_state     <= TX_DATABIT;  -- Start bit complete; begin data bits
                        tx_bit_index <= 0;           -- Begin with LSB (bit 0)
                    end if;

                when TX_DATABIT =>
                    -- Drive current data bit; UART 8N1 sends LSB first
                    uart_tx <= tx_shift_reg(tx_bit_index);

                    if tx_baud_tick = '1' then
                        if tx_bit_index = 7 then
                            tx_state <= TX_STOPBIT;              -- All 8 bits sent; go to stop bit
                        else
                            tx_bit_index <= tx_bit_index + 1;   -- Advance to next data bit
                        end if;
                    end if;

                when TX_STOPBIT =>
                    uart_tx <= '1';   -- Stop bit: drive TX high for one full bit period

                    if tx_baud_tick = '1' then
                        tx_done  <= '1';       -- Pulse done for one cycle: caller can queue next byte
                        tx_state <= TX_IDLE;   -- Return to idle
                    end if;

            end case;
        end if;
    end process;

    --------------------------
    -- RX Synchronizer:
    -- Three flip-flop chain eliminates metastability on the asynchronous uart_rx input.
    -- rx_sync(2) is the safely synchronised value used by all downstream logic.
    --------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            rx_sync <= (others => '1');   -- Initialise to idle (high) state
        elsif rising_edge(clk) then
            rx_sync <= rx_sync(1 downto 0) & uart_rx;  -- Shift: [2]=oldest, [0]=newest sample
        end if;
    end process;

    --------------------------
    -- RX Baud Rate Generator (sample at middle of bit)
    -- Pre-load to BAUD_DIV/2 only when rx_baud_load pulses (start-bit edge).
    -- This aligns the first tick to the center of the start bit so that all
    -- subsequent samples also hit bit centers.
    --------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            rx_baud_counter <= 0;      -- Reset counter
            rx_baud_tick    <= '0';    -- No tick
        elsif rising_edge(clk) then
            rx_baud_tick <= '0';   -- Default: no tick

            if rx_baud_load = '1' then
                -- Pre-load: first tick fires after BAUD_DIV/2 cycles (bit center of start bit)
                -- This offsets all subsequent samples to the middle of each bit window
                rx_baud_counter <= BAUD_DIV / 2;
            elsif rx_state /= RX_IDLE then
                -- Only run counter while receiving a frame
                if rx_baud_counter = BAUD_DIV - 1 then
                    rx_baud_counter <= 0;          -- Wrap counter
                    rx_baud_tick    <= '1';         -- Sampling tick: time to read current bit
                else
                    rx_baud_counter <= rx_baud_counter + 1;  -- Keep counting toward next sample point
                end if;
            end if;
        end if;
    end process;

    --------------------------
    -- RX FSM: detects start bit, samples 8 data bits at centres, validates stop bit
    --------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            rx_state     <= RX_IDLE;              -- Start in idle
            rx_valid     <= '0';                  -- No data valid
            rx_error     <= '0';                  -- No error
            rx_bit_index <= 0;                    -- Reset bit index
            rx_shift_reg <= (others => '0');      -- Clear receive shift register
            rx_baud_load <= '0';                  -- No pre-load pending

        elsif rising_edge(clk) then
            rx_valid     <= '0';   -- Clear valid pulse (held one cycle only)
            rx_error     <= '0';   -- Clear error pulse
            rx_baud_load <= '0';   -- Default: no pre-load; only asserted on start-bit edge

            case rx_state is

                when RX_IDLE =>
                    -- Monitor synchronised RX for a falling edge (high -> low = start bit begins)
                    if rx_sync(2) = '0' then
                        rx_state     <= RX_STARTBIT;  -- Start bit detected
                        rx_baud_load <= '1';           -- Pre-load counter NOW to sample at bit centre
                    end if;

                when RX_STARTBIT =>
                    if rx_baud_tick = '1' then
                        -- At bit centre of start bit: verify it is still low (not a glitch)
                        if rx_sync(2) = '0' then
                            rx_state     <= RX_DATABIT;  -- Valid start bit confirmed; receive data bits
                            rx_bit_index <= 0;            -- Start from LSB
                        else
                            -- Start bit was a glitch; return to idle and wait for real frame
                            rx_error <= '1';       -- Flag framing error
                            rx_state <= RX_IDLE;
                        end if;
                    end if;

                when RX_DATABIT =>
                    if rx_baud_tick = '1' then
                        -- Sample the current bit at its centre and store into shift register
                        rx_shift_reg(rx_bit_index) <= rx_sync(2);  -- UART sends LSB first

                        if rx_bit_index = 7 then
                            rx_state <= RX_STOPBIT;              -- All 8 bits received; check stop bit
                        else
                            rx_bit_index <= rx_bit_index + 1;   -- Advance to next bit position
                        end if;
                    end if;

                when RX_STOPBIT =>
                    if rx_baud_tick = '1' then
                        if rx_sync(2) = '1' then
                            -- Stop bit is high: frame is valid; output received byte
                            rx_data  <= rx_shift_reg;  -- Latch received byte to output
                            rx_valid <= '1';            -- Pulse valid for one cycle
                        else
                            -- Stop bit is low: framing error (broken frame)
                            rx_error <= '1';
                        end if;
                        rx_state <= RX_IDLE;   -- Always return to idle after stop bit
                    end if;

            end case;
        end if;
    end process;

end Behavioral;
