----------------------------------------------------------------------------------
-- Multi-Channel ADC Controller with Digital Filtering
-- Sequentially reads channels and applies moving average filter
-- Channels: CH0=Light Sensor, CH1=Potentiometer1 (Heating), CH2=Potentiometer2 (Sound)
----------------------------------------------------------------------------------

library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned arithmetic (resize, shift)

entity multi_channel_adc is
    Generic (
        FILTER_DEPTH : integer := 8   -- Moving average window size; MUST be a power of 2
    );
    Port (
        clk             : in  std_logic;   -- 50 MHz system clock
        reset           : in  std_logic;   -- Active-high synchronous reset
        enable          : in  std_logic;   -- '1' to run scanning; '0' to stop after current scan

        -- Filtered 10-bit outputs (held valid between scan cycles)
        light_level     : out std_logic_vector(9 downto 0);   -- CH0: light sensor average (lower = darker)
        heating_level   : out std_logic_vector(9 downto 0);   -- CH1: heating potentiometer average
        sound_level     : out std_logic_vector(9 downto 0);   -- CH2: sound potentiometer average
        data_valid      : out std_logic;                       -- '1' once first complete scan finishes; stays '1'

        -- SPI interface to MCP3008 ADC chip
        spi_clk         : out std_logic;   -- SPI clock output (1 MHz)
        spi_mosi        : out std_logic;   -- SPI MOSI: channel selection command bits
        spi_miso        : in  std_logic;   -- SPI MISO: 10-bit ADC result shifted out
        spi_cs_n        : out std_logic    -- SPI chip select active-low
    );
end multi_channel_adc;

architecture Behavioral of multi_channel_adc is

    -- Declare the SPI ADC driver as a component to allow instantiation
    component spi_adc_mcp3008 is
        Generic (
            CLK_FREQ : integer := 50_000_000;  -- System clock frequency
            SPI_FREQ : integer := 1_000_000    -- SPI clock frequency (max 3.6 MHz for MCP3008 @ 3.3V)
        );
        Port (
            clk         : in  std_logic;
            reset       : in  std_logic;
            start       : in  std_logic;                         -- One-cycle pulse to begin a channel conversion
            channel     : in  std_logic_vector(2 downto 0);      -- Channel number 0-7
            adc_data    : out std_logic_vector(9 downto 0);       -- 10-bit conversion result
            busy        : out std_logic;                          -- '1' while SPI transfer in progress
            done        : out std_logic;                          -- One-cycle pulse when result is ready
            spi_clk     : out std_logic;
            spi_mosi    : out std_logic;
            spi_miso    : in  std_logic;
            spi_cs_n    : out std_logic
        );
    end component;

    -- FIX: sum width is 20 bits, safe for FILTER_DEPTH up to 1024
    -- LOG2_DEPTH is the right-shift needed to divide the sum (power-of-2 division)
    -- For FILTER_DEPTH=8:  LOG2_DEPTH=3,  average = sum(12 downto 3)
    -- For FILTER_DEPTH=16: LOG2_DEPTH=4,  average = sum(13 downto 4)
    -- For FILTER_DEPTH=32: LOG2_DEPTH=5,  average = sum(14 downto 5)
    -- FIX v3: compute LOG2_DEPTH from the generic so changing FILTER_DEPTH
    -- is safe without manual updates.  FILTER_DEPTH must be a power of two.
    function log2_nat(n : positive) return natural is
    begin
        if n <= 1 then return 0;              -- log2(1) = 0 (shift by 0 = no division)
        else return 1 + log2_nat(n / 2);      -- Recursive: log2(n) = 1 + log2(n/2)
        end if;
    end function;

    -- Compute the shift amount at elaboration time from the FILTER_DEPTH generic
    constant LOG2_DEPTH : natural := log2_nat(FILTER_DEPTH);
    -- Example: FILTER_DEPTH=8 -> LOG2_DEPTH=3; dividing sum by 8 = right-shift by 3

    -- FSM states: IDLE, then cycle through CH0->CH1->CH2, update outputs, delay, repeat
    type state_type is (
        IDLE,           -- Waiting for enable='1'
        START_CH0,      -- Assert start pulse for CH0 (light sensor)
        WAIT_CH0,       -- Wait for CH0 SPI transaction to complete
        START_CH1,      -- Assert start pulse for CH1 (heating potentiometer)
        WAIT_CH1,       -- Wait for CH1 SPI transaction to complete
        START_CH2,      -- Assert start pulse for CH2 (sound potentiometer)
        WAIT_CH2,       -- Wait for CH2 SPI transaction to complete
        UPDATE_OUTPUTS, -- Compute moving averages and drive output ports
        DELAY           -- 100 ms inter-scan delay before next scan cycle
    );
    signal state : state_type := IDLE;

    -- SPI ADC interface signals
    signal adc_start    : std_logic := '0';                        -- One-cycle start pulse to spi_adc_mcp3008
    signal adc_channel  : std_logic_vector(2 downto 0) := (others => '0');  -- Channel number (0, 1, or 2)
    signal adc_data     : std_logic_vector(9 downto 0);            -- 10-bit conversion result from SPI driver
    signal adc_busy     : std_logic;                               -- High while SPI transfer active
    signal adc_done     : std_logic;                               -- One-cycle pulse: result captured in adc_data

    -- Moving average filter buffers: circular history of FILTER_DEPTH samples per channel
    -- FIX: 20-bit accumulators safe for FILTER_DEPTH up to 1024 (10 data bits + 10 guard bits)
    type filter_array is array (0 to FILTER_DEPTH-1) of unsigned(9 downto 0);
    signal ch0_buffer   : filter_array := (others => (others => '0'));  -- Circular sample history for CH0
    signal ch1_buffer   : filter_array := (others => (others => '0'));  -- Circular sample history for CH1
    signal ch2_buffer   : filter_array := (others => (others => '0'));  -- Circular sample history for CH2

    -- Running sums: subtract oldest sample, add newest sample each cycle (sliding-window algorithm)
    signal ch0_sum      : unsigned(19 downto 0) := (others => '0');  -- Sum of all CH0 samples in window
    signal ch1_sum      : unsigned(19 downto 0) := (others => '0');  -- Sum of all CH1 samples in window
    signal ch2_sum      : unsigned(19 downto 0) := (others => '0');  -- Sum of all CH2 samples in window

    -- Circular buffer write index: advances after each complete 3-channel scan
    signal filter_index : integer range 0 to FILTER_DEPTH-1 := 0;  -- Points to oldest sample slot (next to overwrite)

    -- Inter-scan delay counter: 100 ms pause between full scan cycles
    signal delay_counter : integer range 0 to 5_000_000 := 0;  -- 5_000_000 cycles = 100 ms @ 50 MHz

    -- FIX: latched data_valid stays high after first complete scan so the HPS
    -- Avalon read always sees a valid status.  Previously data_valid was driven
    -- directly from the clocked process with a default '0', making it a 1-cycle
    -- pulse that the HPS could never reliably catch (~20 ns out of every 100 ms).
    signal data_valid_i  : std_logic := '0';  -- Sticky: once '1', stays '1' until reset

begin

    -- Drive port from latch so it stays high between scan cycles
    data_valid <= data_valid_i;  -- Expose sticky data-valid to Avalon wrapper

    -- Instantiate the SPI driver for the MCP3008 ADC
    adc_inst : spi_adc_mcp3008
        generic map (
            CLK_FREQ => 50_000_000,   -- 50 MHz system clock
            SPI_FREQ => 1_000_000     -- 1 MHz SPI: safe and well within MCP3008 3.6 MHz limit
        )
        port map (
            clk      => clk,          -- System clock
            reset    => reset,        -- System reset
            start    => adc_start,    -- Start pulse from FSM
            channel  => adc_channel,  -- Channel selection (0=light, 1=heating, 2=sound)
            adc_data => adc_data,     -- 10-bit result captured by FSM on adc_done
            busy     => adc_busy,     -- Not used directly; adc_done indicates completion
            done     => adc_done,     -- One-cycle pulse: result in adc_data is valid
            spi_clk  => spi_clk,      -- SPI CLK to MCP3008 CLK pin
            spi_mosi => spi_mosi,     -- SPI MOSI to MCP3008 DIN pin
            spi_miso => spi_miso,     -- SPI MISO from MCP3008 DOUT pin
            spi_cs_n => spi_cs_n      -- SPI CS_N to MCP3008 CS/SHDN pin
        );

    ---------------------------------------------------------------------------
    -- Main FSM + moving-average filter
    -- Scans 3 ADC channels in sequence, applies sliding-window averaging,
    -- then waits 100 ms before the next scan to give ~10 Hz update rate.
    ---------------------------------------------------------------------------
    process(clk, reset)
        variable new_sample : unsigned(9 downto 0);  -- Temporary variable to hold the latest ADC reading
    begin
        if reset = '1' then
            state        <= IDLE;
            data_valid_i <= '0';                          -- No valid data after reset
            adc_start    <= '0';                          -- No pending start
            filter_index <= 0;                            -- Reset circular buffer pointer
            ch0_buffer   <= (others => (others => '0'));  -- Clear CH0 sample history
            ch1_buffer   <= (others => (others => '0'));  -- Clear CH1 sample history
            ch2_buffer   <= (others => (others => '0'));  -- Clear CH2 sample history
            ch0_sum      <= (others => '0');              -- Clear CH0 running sum
            ch1_sum      <= (others => '0');              -- Clear CH1 running sum
            ch2_sum      <= (others => '0');              -- Clear CH2 running sum

        elsif rising_edge(clk) then
            adc_start  <= '0';   -- Default: no start pulse (overridden in START_CH* states)
            -- data_valid_i intentionally NOT cleared here; it latches '1' after
            -- the first complete scan and stays high so the HPS can always read it.

            case state is

                -- IDLE: wait for enable='1' before beginning scan
                when IDLE =>
                    if enable = '1' then state <= START_CH0; end if;  -- Begin with CH0 when enabled

                -- Channel 0 (CH0) – Light Sensor
                when START_CH0 =>
                    adc_channel <= "000";   -- Select MCP3008 CH0 (light sensor)
                    adc_start   <= '1';     -- Pulse start to spi_adc_mcp3008
                    state       <= WAIT_CH0;

                when WAIT_CH0 =>
                    if adc_done = '1' then
                        -- Sliding-window update: subtract oldest sample, add new sample
                        new_sample := unsigned(adc_data);
                        ch0_sum    <= ch0_sum
                                      - resize(ch0_buffer(filter_index), 20)  -- Subtract oldest CH0 sample
                                      + resize(new_sample, 20);                -- Add new CH0 sample
                        ch0_buffer(filter_index) <= new_sample;  -- Overwrite oldest slot with new sample
                        state <= START_CH1;  -- Proceed to CH1
                    end if;

                -- Channel 1 (CH1) – Heating Potentiometer
                when START_CH1 =>
                    adc_channel <= "001";   -- Select MCP3008 CH1 (heating potentiometer)
                    adc_start   <= '1';
                    state       <= WAIT_CH1;

                when WAIT_CH1 =>
                    if adc_done = '1' then
                        new_sample := unsigned(adc_data);
                        ch1_sum    <= ch1_sum
                                      - resize(ch1_buffer(filter_index), 20)  -- Subtract oldest CH1 sample
                                      + resize(new_sample, 20);
                        ch1_buffer(filter_index) <= new_sample;
                        state <= START_CH2;  -- Proceed to CH2
                    end if;

                -- Channel 2 (CH2) – Sound Potentiometer
                when START_CH2 =>
                    adc_channel <= "010";   -- Select MCP3008 CH2 (sound potentiometer)
                    adc_start   <= '1';
                    state       <= WAIT_CH2;

                when WAIT_CH2 =>
                    if adc_done = '1' then
                        new_sample := unsigned(adc_data);
                        ch2_sum    <= ch2_sum
                                      - resize(ch2_buffer(filter_index), 20)  -- Subtract oldest CH2 sample
                                      + resize(new_sample, 20);
                        ch2_buffer(filter_index) <= new_sample;

                        -- Advance circular buffer write pointer; wrap around at FILTER_DEPTH
                        if filter_index = FILTER_DEPTH - 1 then
                            filter_index <= 0;                      -- Wrap pointer back to beginning
                        else
                            filter_index <= filter_index + 1;       -- Move to next slot
                        end if;

                        state <= UPDATE_OUTPUTS;  -- All 3 channels sampled; compute averages
                    end if;

                -- UPDATE_OUTPUTS: divide each sum by FILTER_DEPTH (right-shift by LOG2_DEPTH)
                -- and drive the output ports with the filtered values
                when UPDATE_OUTPUTS =>
                    -- FIX: divide by shifting right LOG2_DEPTH bits; take lower 10 bits of result
                    -- For FILTER_DEPTH=8 (LOG2_DEPTH=3): slice sum(12 downto 3) gives 10-bit average
                    light_level   <= std_logic_vector(ch0_sum(9 + LOG2_DEPTH downto LOG2_DEPTH));  -- CH0 average
                    heating_level <= std_logic_vector(ch1_sum(9 + LOG2_DEPTH downto LOG2_DEPTH));  -- CH1 average
                    sound_level   <= std_logic_vector(ch2_sum(9 + LOG2_DEPTH downto LOG2_DEPTH));  -- CH2 average
                    data_valid_i  <= '1';             -- FIX: latch '1' permanently; HPS can read at any time
                    delay_counter <= 5_000_000;       -- Load 100 ms delay counter (5M cycles @ 50 MHz)
                    state         <= DELAY;

                -- DELAY: 100 ms pause between scan cycles
                when DELAY =>
                    if delay_counter > 0 then
                        delay_counter <= delay_counter - 1;   -- Count down inter-scan gap
                    else
                        if enable = '1' then state <= START_CH0;  -- Enabled: start next scan cycle
                        else state <= IDLE; end if;               -- Disabled: wait in IDLE
                    end if;

            end case;
        end if;
    end process;

end Behavioral;
