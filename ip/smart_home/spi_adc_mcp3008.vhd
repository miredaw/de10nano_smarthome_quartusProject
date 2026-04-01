----------------------------------------------------------------------------------
-- SPI Master for MCP3008 ADC
-- 8-Channel 10-bit ADC with SPI Interface
-- Mode 0: CPOL=0, CPHA=0
--
-- CLK_DIV CORRECTED:
--  The clock enable fires every CLK_DIV cycles.  The state machine toggles
--  spi_clk_int on EVERY enable tick, so the actual SPI clock period is:
--      T_SPI = 2 * CLK_DIV * T_CLK  =>  f_SPI = CLK_FREQ / (2 * CLK_DIV)
--  With the original CLK_DIV = CLK_FREQ/(SPI_FREQ*2) the real frequency was
--  Corrected: CLK_DIV = CLK_FREQ/(SPI_FREQ*2) so each enable tick = half period
--  => actual f_SPI = CLK_FREQ / (2 * CLK_DIV) = SPI_FREQ  (correct)
--
--  FIX v3:
--  IDLE state moved OUTSIDE the spi_clk_en gate so a single-cycle start
--  pulse from multi_channel_adc is never missed (previously had ~1/25 chance).
----------------------------------------------------------------------------------

library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned/signed arithmetic

entity spi_adc_mcp3008 is
    Generic (
        CLK_FREQ    : integer := 50_000_000;  -- System clock frequency in Hz
        SPI_FREQ    : integer := 1_000_000    -- Desired SPI SCK frequency in Hz (max 3.6 MHz @ 3.3V)
    );
    Port (
        clk         : in  std_logic;   -- 50 MHz system clock
        reset       : in  std_logic;   -- Active-high synchronous reset

        -- Control interface (driven by multi_channel_adc FSM)
        start       : in  std_logic;                         -- One-cycle pulse: latch channel and begin transfer
        channel     : in  std_logic_vector(2 downto 0);      -- MCP3008 channel to sample (0–7)
        adc_data    : out std_logic_vector(9 downto 0);       -- 10-bit conversion result (valid when done='1')
        busy        : out std_logic;                          -- '1' from CS_LOW until DONE_STATE
        done        : out std_logic;                          -- One-cycle pulse when adc_data is valid

        -- SPI interface (Mode 0: CPOL=0, CPHA=0 – data valid on rising edge)
        spi_clk     : out std_logic;   -- SPI clock to MCP3008 CLK pin
        spi_mosi    : out std_logic;   -- SPI MOSI to MCP3008 DIN pin
        spi_miso    : in  std_logic;   -- SPI MISO from MCP3008 DOUT pin
        spi_cs_n    : out std_logic    -- SPI chip select active-low to MCP3008 CS/SHDN pin
    );
end spi_adc_mcp3008;

architecture Behavioral of spi_adc_mcp3008 is

    -- CLK_DIV = CLK_FREQ/(SPI_FREQ*2):
    -- The FSM toggles spi_clk_int on every spi_clk_en tick, so one full SPI period
    -- requires 2 ticks -> f_SPI = CLK_FREQ / (2 * CLK_DIV) = SPI_FREQ (correct)
    constant CLK_DIV    : integer := CLK_FREQ / (SPI_FREQ * 2);  -- Half-period in system clock cycles
    signal clk_counter  : integer range 0 to CLK_DIV - 1 := 0;   -- Counts system cycles toward next half-period
    signal spi_clk_en   : std_logic := '0';                       -- One-cycle pulse every CLK_DIV cycles (half-period tick)

    -- FSM states corresponding to the MCP3008 SPI transaction sequence
    -- MCP3008 SPI frame (single-ended mode):
    --   MOSI: [CS_LOW] START(1) | SGL(1) | D2 | D1 | D0 | [don't care]
    --   MISO: [null bit] | B9 | B8 | B7 | B6 | B5 | B4 | B3 | B2 | B1 | B0
    type state_type is (
        IDLE,            -- Waiting for start pulse; CS_N held high
        CS_LOW,          -- Assert CS_N low; hold one half-period before sending
        SEND_START_BIT,  -- Send start bit (always '1')
        SEND_SGL_DIFF,   -- Send SGL/DIFF bit ('1' = single-ended, '0' = differential)
        SEND_CHANNEL_B2, -- Send channel bit 2 (MSB of 3-bit channel address)
        SEND_CHANNEL_B1, -- Send channel bit 1
        SEND_CHANNEL_B0, -- Send channel bit 0 (LSB)
        RECEIVE_NULL,    -- Clock through null bit (MCP3008 outputs '0' before B9)
        RECEIVE_B9,      -- Receive ADC result bit 9 (MSB)
        RECEIVE_B8,
        RECEIVE_B7,
        RECEIVE_B6,
        RECEIVE_B5,
        RECEIVE_B4,
        RECEIVE_B3,
        RECEIVE_B2,
        RECEIVE_B1,
        RECEIVE_B0,      -- Receive ADC result bit 0 (LSB)
        CS_HIGH,         -- De-assert CS_N; latch final adc_data
        DONE_STATE       -- Pulse done for one cycle then return to IDLE
    );
    signal state : state_type := IDLE;

    signal spi_clk_int  : std_logic := '0';                        -- Internal SPI clock register
    signal bit_data     : std_logic_vector(9 downto 0) := (others => '0');  -- Accumulates incoming MISO bits
    signal channel_reg  : std_logic_vector(2 downto 0) := (others => '0'); -- Latched channel from 'channel' input

begin

    ---------------------------------------------------------------------------
    -- SPI clock enable generator
    -- Fires every CLK_DIV cycles; state machine toggles spi_clk_int each time
    -- producing a SPI clock at exactly SPI_FREQ Hz.
    ---------------------------------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            clk_counter <= 0;      -- Reset half-period counter
            spi_clk_en  <= '0';    -- No tick pending
        elsif rising_edge(clk) then
            if clk_counter = CLK_DIV - 1 then
                clk_counter <= 0;       -- Wrap counter
                spi_clk_en  <= '1';     -- Assert half-period tick
            else
                clk_counter <= clk_counter + 1;  -- Keep counting
                spi_clk_en  <= '0';              -- No tick yet
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Main SPI FSM
    -- MCP3008 protocol (single-ended):
    --   TX: 1 (start) | 1 (SGL) | D2 | D1 | D0
    --   RX: null bit  | B9 .. B0 (10 data bits, MSB first)
    -- Each state represents one half-period of the SPI clock.
    -- MOSI is set on the falling SCL edge (phase 0: spi_clk_int=0).
    -- MISO is sampled on the rising SCL edge (phase 1: spi_clk_int transitions 0->1).
    ---------------------------------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            state       <= IDLE;
            busy        <= '0';
            done        <= '0';
            spi_cs_n    <= '1';              -- CS_N high: chip deselected
            spi_clk_int <= '0';              -- SCK idle low (Mode 0: CPOL=0)
            spi_mosi    <= '0';
            bit_data    <= (others => '0');  -- Clear receive buffer

        elsif rising_edge(clk) then
            done <= '0';  -- Default: clear done pulse (only asserted in DONE_STATE)

            -- FIX v3: IDLE checked every cycle (not gated by spi_clk_en) so
            -- a single-cycle start pulse from multi_channel_adc is never missed.
            -- Without this fix there was a ~1/CLK_DIV chance the pulse fell between ticks.
            if state = IDLE then
                busy        <= '0';    -- Available for new conversion
                spi_cs_n    <= '1';    -- CS_N deasserted between conversions
                spi_clk_int <= '0';    -- Hold SCK low (Mode 0 idle)
                if start = '1' then
                    channel_reg <= channel;  -- Latch channel number before it can change
                    busy        <= '1';      -- Claim busy immediately
                    state       <= CS_LOW;   -- Begin transaction
                end if;
            end if;

            -- All other states execute only on spi_clk_en ticks (half-period boundaries)
            if spi_clk_en = '1' then
                case state is

                    when IDLE =>
                        null;  -- handled above, outside spi_clk_en gate

                    -- CS_LOW: assert chip select one half-period before first MOSI bit
                    when CS_LOW =>
                        spi_cs_n <= '0';         -- Assert CS_N: MCP3008 begins listening
                        state    <= SEND_START_BIT;

                    -- ---- Transmit command bits (5 bits total: START, SGL, D2, D1, D0) ----
                    -- Each transmit state toggles spi_clk_int and drives MOSI on the falling edge.
                    -- MOSI is set while SCK is low (spi_clk_int='0') then SCK rises to latch it.

                    -- SEND_START_BIT: output the start bit (always '1')
                    when SEND_START_BIT =>
                        spi_clk_int <= not spi_clk_int;   -- Toggle SCK
                        if spi_clk_int = '0' then
                            spi_mosi <= '1';               -- Drive MOSI='1' (start bit) while SCK is low
                        else
                            state <= SEND_SGL_DIFF;        -- SCK rose: bit was latched; advance
                        end if;

                    -- SEND_SGL_DIFF: output the SGL/DIFF bit ('1' = single-ended mode)
                    when SEND_SGL_DIFF =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '0' then
                            spi_mosi <= '1';               -- SGL='1': single-ended (vs. differential)
                        else
                            state <= SEND_CHANNEL_B2;
                        end if;

                    -- SEND_CHANNEL_B2: output channel address bit 2 (MSB)
                    when SEND_CHANNEL_B2 =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '0' then
                            spi_mosi <= channel_reg(2);    -- Channel MSB (e.g. '0' for CH0-3, '1' for CH4-7)
                        else
                            state <= SEND_CHANNEL_B1;
                        end if;

                    -- SEND_CHANNEL_B1: output channel address bit 1
                    when SEND_CHANNEL_B1 =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '0' then
                            spi_mosi <= channel_reg(1);
                        else
                            state <= SEND_CHANNEL_B0;
                        end if;

                    -- SEND_CHANNEL_B0: output channel address bit 0 (LSB)
                    when SEND_CHANNEL_B0 =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '0' then
                            spi_mosi <= channel_reg(0);
                        else
                            state <= RECEIVE_NULL;
                        end if;

                    -- ---- Receive 10-bit result (MSB first) ----
                    -- MISO is sampled on the rising edge (spi_clk_int goes 0->1).
                    -- The null bit is the one MCP3008 uses to switch from receiving to sending.

                    -- RECEIVE_NULL: clock through the null bit; ignore MISO value
                    when RECEIVE_NULL =>
                        spi_clk_int <= not spi_clk_int;   -- Toggle SCK
                        -- Null bit: MCP3008 outputs '0' here; we do not capture it
                        if spi_clk_int = '1' then state <= RECEIVE_B9; end if;  -- On rising edge: move to data

                    -- RECEIVE_B9..B0: sample MISO into bit_data on the rising SCL edge
                    when RECEIVE_B9 =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '1' then bit_data(9) <= spi_miso; state <= RECEIVE_B8; end if;

                    when RECEIVE_B8 =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '1' then bit_data(8) <= spi_miso; state <= RECEIVE_B7; end if;

                    when RECEIVE_B7 =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '1' then bit_data(7) <= spi_miso; state <= RECEIVE_B6; end if;

                    when RECEIVE_B6 =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '1' then bit_data(6) <= spi_miso; state <= RECEIVE_B5; end if;

                    when RECEIVE_B5 =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '1' then bit_data(5) <= spi_miso; state <= RECEIVE_B4; end if;

                    when RECEIVE_B4 =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '1' then bit_data(4) <= spi_miso; state <= RECEIVE_B3; end if;

                    when RECEIVE_B3 =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '1' then bit_data(3) <= spi_miso; state <= RECEIVE_B2; end if;

                    when RECEIVE_B2 =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '1' then bit_data(2) <= spi_miso; state <= RECEIVE_B1; end if;

                    when RECEIVE_B1 =>
                        spi_clk_int <= not spi_clk_int;
                        if spi_clk_int = '1' then bit_data(1) <= spi_miso; state <= RECEIVE_B0; end if;

                    when RECEIVE_B0 =>
                        spi_clk_int <= not spi_clk_int;
                        -- LSB received on rising edge; all 10 bits captured; go to CS_HIGH
                        if spi_clk_int = '1' then bit_data(0) <= spi_miso; state <= CS_HIGH; end if;

                    -- CS_HIGH: de-assert CS_N and latch bit_data into adc_data output register
                    when CS_HIGH =>
                        spi_cs_n    <= '1';         -- Deselect MCP3008 chip
                        spi_clk_int <= '0';         -- Return SCK to idle low (Mode 0)
                        adc_data    <= bit_data;    -- Latch captured 10-bit result to output
                        state       <= DONE_STATE;

                    -- DONE_STATE: pulse done for one spi_clk_en tick, then return to IDLE
                    when DONE_STATE =>
                        done  <= '1';       -- Signal to multi_channel_adc that result is valid
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

    -- Drive SPI clock output from internal register
    spi_clk <= spi_clk_int;   -- Expose internal SCK to the physical MCP3008 CLK pin

end Behavioral;
