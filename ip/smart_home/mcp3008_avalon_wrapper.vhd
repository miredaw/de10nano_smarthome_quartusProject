----------------------------------------------------------------------------------
-- Avalon MM Wrapper for MCP3008 Multi-Channel ADC
--
-- The sensor_data conduit port MUST be named "light_level" because the generated
-- soc_system.v from Platform Designer instantiates this wrapper and connects
-- the port by that exact name: .light_level(mcp3008_sensor_data_new_signal)
-- Do NOT rename this port - Platform Designer derives the name from the
-- role="new_signal" entry AND the VHDL signal name in the sopcinfo <n> tag.
--
-- Register Map (word-addressed):
--   0x00 (addr "000") : REG_LIGHT   - [9:0]  filtered light ADC value
--   0x04 (addr "001") : REG_HEATING - [9:0]  filtered heating potentiometer value
--   0x08 (addr "010") : REG_SOUND   - [9:0]  filtered sound potentiometer value
--   0x0C (addr "011") : REG_STATUS  - [0]=data_valid
--   0x10 (addr "100") : REG_CONTROL - [0]=enable (R/W)
--
-- LW Bridge base: 0xFF200000 + 0x20 = 0xFF200020
----------------------------------------------------------------------------------

library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned/signed arithmetic

entity mcp3008_avalon_wrapper is
    Port (
        -- Avalon MM Slave Interface (connected to HPS via Lightweight AXI bridge)
        clk         : in  std_logic;                        -- 50 MHz system clock
        reset       : in  std_logic;                        -- Active-high synchronous reset
        address     : in  std_logic_vector(2 downto 0);     -- 3-bit word address: selects one of 5 registers
        write       : in  std_logic;                        -- HPS write strobe (one cycle)
        writedata   : in  std_logic_vector(31 downto 0);    -- 32-bit data from HPS (only bit 0 used for enable)
        read        : in  std_logic;                        -- HPS read strobe (one cycle)
        readdata    : out std_logic_vector(31 downto 0);    -- 32-bit response to HPS read
        waitrequest : out std_logic;                        -- Always '0': this peripheral never stalls

        -- SPI Conduit (physical board pins connected to MCP3008 via JP1)
        spi_clk     : out std_logic;   -- SPI clock output: JP1 pin 3 (PIN_W12)
        spi_mosi    : out std_logic;   -- SPI MOSI (master out, slave in): JP1 pin 4 (PIN_D11)
        spi_miso    : in  std_logic;   -- SPI MISO (master in, slave out): JP1 pin 5 (PIN_D8)
        spi_cs_n    : out std_logic;   -- SPI chip select active-low: JP1 pin 6 (PIN_AH13)

        -- Sensor data conduit: port name MUST match sopcinfo <n>light_level</n>
        -- Platform Designer generates: .light_level(mcp3008_sensor_data_new_signal)
        light_level : out std_logic_vector(9 downto 0)    -- 10-bit filtered CH0 value routed to alarm_logic
    );
end mcp3008_avalon_wrapper;

architecture Behavioral of mcp3008_avalon_wrapper is

    -- Declare multi_channel_adc as a component to allow instantiation
    component multi_channel_adc is
        Generic (FILTER_DEPTH : integer := 8);   -- Moving average window depth (must be power of 2)
        Port (
            clk           : in  std_logic;
            reset         : in  std_logic;
            enable        : in  std_logic;
            light_level   : out std_logic_vector(9 downto 0);
            heating_level : out std_logic_vector(9 downto 0);
            sound_level   : out std_logic_vector(9 downto 0);
            data_valid    : out std_logic;
            spi_clk       : out std_logic;
            spi_mosi      : out std_logic;
            spi_miso      : in  std_logic;
            spi_cs_n      : out std_logic
        );
    end component;

    signal enable          : std_logic := '1';                         -- ADC enable register; starts enabled
    signal light_level_i   : std_logic_vector(9 downto 0);            -- CH0 (light sensor) filtered reading
    signal heating_level_i : std_logic_vector(9 downto 0);            -- CH1 (heating potentiometer) filtered reading
    signal sound_level_i   : std_logic_vector(9 downto 0);            -- CH2 (sound potentiometer) filtered reading
    signal data_valid_i    : std_logic;                                -- '1' when multi_channel_adc has completed a scan
    -- Explicit latch: once data_valid_i goes '1' we capture it into a local
    -- register so the Avalon readdata mux never sees a transient '0'.
    -- Also avoids Quartus synthesis issues with (31 downto 1 => '0') aggregates.
    signal adc_ready       : std_logic := '0';   -- Sticky version of data_valid_i; stays '1' permanently after first scan

    -- Register address constants (3-bit word address)
    constant REG_LIGHT   : std_logic_vector(2 downto 0) := "000";  -- Addr 0x00: filtered CH0 light reading
    constant REG_HEATING : std_logic_vector(2 downto 0) := "001";  -- Addr 0x04: filtered CH1 heating reading
    constant REG_SOUND   : std_logic_vector(2 downto 0) := "010";  -- Addr 0x08: filtered CH2 sound reading
    constant REG_STATUS  : std_logic_vector(2 downto 0) := "011";  -- Addr 0x0C: [0]=adc_ready (data available)
    constant REG_CONTROL : std_logic_vector(2 downto 0) := "100";  -- Addr 0x10: [0]=enable (R/W)

begin

    -- Instantiate the multi-channel ADC sequencer and moving-average filter
    adc_inst : multi_channel_adc
        generic map (FILTER_DEPTH => 8)   -- 8-sample moving average (LOG2=3, shift by 3 to divide)
        port map (
            clk           => clk,              -- System clock
            reset         => reset,            -- System reset
            enable        => enable,           -- Software enable from HPS register
            light_level   => light_level_i,    -- CH0 filtered output: light sensor
            heating_level => heating_level_i,  -- CH1 filtered output: heating potentiometer
            sound_level   => sound_level_i,    -- CH2 filtered output: sound potentiometer
            data_valid    => data_valid_i,      -- Pulses '1' when UPDATE_OUTPUTS state completes a scan
            spi_clk       => spi_clk,          -- Connect to physical MCP3008 CLK pin
            spi_mosi      => spi_mosi,         -- Connect to physical MCP3008 DIN (MOSI) pin
            spi_miso      => spi_miso,         -- Connect from physical MCP3008 DOUT (MISO) pin
            spi_cs_n      => spi_cs_n          -- Connect to physical MCP3008 CS/SHDN pin
        );

    -- Drive conduit output (connected by Platform Designer to alarm_logic_0)
    light_level <= light_level_i;   -- Export CH0 light reading to Platform Designer conduit -> alarm_logic

    waitrequest <= '0';   -- Always ready; HPS never stalled by this peripheral

    -- Avalon MM register process
    process(clk, reset)
    begin
        if reset = '1' then
            readdata  <= (others => '0');   -- Clear read-data register
            enable    <= '1';              -- Re-enable ADC automatically after reset
            adc_ready <= '0';             -- No valid data yet after reset

        elsif rising_edge(clk) then
            -- Latch data_valid permanently once seen (survives IDLE/DELAY gaps between scans)
            -- Without this latch, data_valid is only a ~1-cycle pulse every 100 ms,
            -- which the HPS could easily miss during polling
            if data_valid_i = '1' then
                adc_ready <= '1';   -- Sticky: stays '1' once first complete scan finishes
            end if;

            -- Write path: only REG_CONTROL is writable (bit 0 = enable/disable ADC)
            if write = '1' then
                case address is
                    when REG_CONTROL => enable <= writedata(0);   -- HPS sets bit 0 to enable/disable sequencer
                    when others => null;                           -- All other registers are read-only
                end case;
            end if;

            -- Read path: return ADC channel readings and status to HPS
            if read = '1' then
                case address is
                    when REG_LIGHT =>
                        readdata <= x"00000" & "00" & light_level_i;    -- Pad 10-bit CH0 to 32 bits
                    when REG_HEATING =>
                        readdata <= x"00000" & "00" & heating_level_i;  -- Pad 10-bit CH1 to 32 bits
                    when REG_SOUND =>
                        readdata <= x"00000" & "00" & sound_level_i;    -- Pad 10-bit CH2 to 32 bits
                    when REG_STATUS =>
                        -- [0]=adc_ready (sticky valid); all other bits zero
                        readdata <= (0 => adc_ready, others => '0');
                    when REG_CONTROL =>
                        readdata <= (0 => enable, others => '0');   -- Return current enable state
                    when others =>
                        readdata <= (others => '0');   -- Unmapped address returns zero
                end case;
            end if;
        end if;
    end process;

end Behavioral;
