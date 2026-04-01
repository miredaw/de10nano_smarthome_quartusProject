----------------------------------------------------------------------------------
-- Avalon MM Wrapper for BME280 I2C Controller
--
-- FIX v2:
--  1. 'scl' port changed from 'out' to 'inout' to propagate the open-drain
--     fix all the way to the top-level board pin.
--
-- The sensor_data conduit port MUST be named "temp_raw" because the generated
-- soc_system.v from Platform Designer instantiates this wrapper and connects
-- the port by that exact name: .temp_raw(bme280_sensor_data_new_signal)
-- Do NOT rename this port.
--
-- Register Map (word-addressed, byte offset):
--   0x00 (addr "000") : REG_TEMP     - [19:0] raw temperature ADC value  (R)
--   0x04 (addr "001") : REG_PRESSURE - [19:0] raw pressure ADC value     (R)
--   0x08 (addr "010") : REG_HUMIDITY - [15:0] raw humidity ADC value     (R)
--   0x0C (addr "011") : REG_STATUS   - [1]=error, [0]=data_valid         (R)
--   0x10 (addr "100") : REG_CONTROL  - [0]=enable                       (R/W)
--
-- LW Bridge base: 0xFF200000 + 0x00 = 0xFF200000
----------------------------------------------------------------------------------

library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned/signed arithmetic

entity bme280_avalon_wrapper is
    Port (
        -- Avalon MM Slave Interface (connected to HPS via Lightweight AXI bridge)
        clk         : in    std_logic;                        -- 50 MHz system clock
        reset       : in    std_logic;                        -- Active-high synchronous reset
        address     : in    std_logic_vector(2 downto 0);     -- 3-bit word address: selects one of 5 registers
        write       : in    std_logic;                        -- HPS write strobe (one cycle)
        writedata   : in    std_logic_vector(31 downto 0);    -- 32-bit data from HPS (only bit 0 used for enable)
        read        : in    std_logic;                        -- HPS read strobe (one cycle)
        readdata    : out   std_logic_vector(31 downto 0);    -- 32-bit response to HPS read
        waitrequest : out   std_logic;                        -- Always '0': this peripheral never stalls the bus

        -- I2C Conduit (physical board pins, open-drain)
        -- Both SDA and SCL must be inout to support open-drain bus behaviour
        sda         : inout std_logic;   -- I2C data line (open-drain): JP1 pin 1 (PIN_V12)
        scl         : inout std_logic;   -- I2C clock line (inout for clock-stretch): JP1 pin 2 (PIN_E8)

        -- Sensor data conduit: name MUST match sopcinfo <n>temp_raw</n>
        -- Platform Designer generates: .temp_raw(bme280_sensor_data_new_signal)
        temp_raw    : out   std_logic_vector(19 downto 0)    -- 20-bit raw temperature passed to alarm_logic
    );
end bme280_avalon_wrapper;

architecture Behavioral of bme280_avalon_wrapper is

    -- Declare bme280_controller as a component to allow instantiation
    component bme280_controller is
        Generic (BME280_ADDR : std_logic_vector(6 downto 0) := "1110110");  -- Default I2C address 0x76
        Port (
            clk        : in    std_logic;
            reset      : in    std_logic;
            enable     : in    std_logic;
            temp_raw   : out   std_logic_vector(19 downto 0);
            press_raw  : out   std_logic_vector(19 downto 0);
            humid_raw  : out   std_logic_vector(15 downto 0);
            data_valid : out   std_logic;
            error      : out   std_logic;
            sda        : inout std_logic;
            scl        : inout std_logic   -- FIX: inout for open-drain
        );
    end component;

    signal enable        : std_logic := '1';                       -- Enable register (HPS-writable); starts enabled
    signal temp_raw_i    : std_logic_vector(19 downto 0);          -- 20-bit raw temperature from sensor controller
    signal press_raw_i   : std_logic_vector(19 downto 0);          -- 20-bit raw pressure from sensor controller
    signal humid_raw_i   : std_logic_vector(15 downto 0);          -- 16-bit raw humidity from sensor controller
    signal data_valid_i  : std_logic;                              -- '1' when sensor has completed at least one reading
    signal bme_error_i   : std_logic;                              -- '1' when I2C transaction failed (error bit)

    -- Register address constants (3-bit word address)
    constant REG_TEMP     : std_logic_vector(2 downto 0) := "000";  -- Addr 0x00: raw temperature output
    constant REG_PRESSURE : std_logic_vector(2 downto 0) := "001";  -- Addr 0x04: raw pressure output
    constant REG_HUMIDITY : std_logic_vector(2 downto 0) := "010";  -- Addr 0x08: raw humidity output
    constant REG_STATUS   : std_logic_vector(2 downto 0) := "011";  -- Addr 0x0C: [1]=error [0]=data_valid
    constant REG_CONTROL  : std_logic_vector(2 downto 0) := "100";  -- Addr 0x10: [0]=enable (R/W)

begin

    -- Instantiate the BME280 FSM controller; fix: set I2C address to 0x76 (SDO tied to GND)
    bme_inst : bme280_controller
        generic map (BME280_ADDR => "1110110")  -- 0x76: SDO pin tied to GND on Waveshare module
        port map (
            clk        => clk,           -- System clock
            reset      => reset,         -- System reset
            enable     => enable,        -- Software enable controlled by HPS
            temp_raw   => temp_raw_i,    -- Temperature reading captured here
            press_raw  => press_raw_i,   -- Pressure reading captured here
            humid_raw  => humid_raw_i,   -- Humidity reading captured here
            data_valid => data_valid_i,  -- Stays '1' once first valid reading arrives
            error      => bme_error_i,   -- Goes '1' if I2C transaction fails
            sda        => sda,           -- Connect to physical JP1 SDA pin
            scl        => scl            -- Connect to physical JP1 SCL pin (inout for clock stretch)
        );

    -- Drive conduit output (routed by Platform Designer to alarm_logic_0)
    temp_raw <= temp_raw_i;   -- Export 20-bit raw temperature so Platform Designer can route to alarm_logic

    waitrequest <= '0';   -- Always ready; HPS never needs to wait on this peripheral

    -- Avalon MM register process
    process(clk, reset)
    begin
        if reset = '1' then
            readdata <= (others => '0');   -- Clear read data register
            enable   <= '1';              -- Re-enable sensor automatically after reset

        elsif rising_edge(clk) then
            -- Write path: only REG_CONTROL is writable (bit 0 = enable/disable sensor)
            if write = '1' then
                case address is
                    when REG_CONTROL => enable <= writedata(0);   -- HPS sets bit 0 to enable/disable controller
                    when others => null;                           -- All other addresses are read-only
                end case;
            end if;

            -- Read path: return sensor data and status to HPS
            if read = '1' then
                case address is
                    when REG_TEMP =>
                        readdata <= x"000" & temp_raw_i;     -- Pad 20-bit temperature to 32 bits; bits[31:20]=0
                    when REG_PRESSURE =>
                        readdata <= x"000" & press_raw_i;    -- Pad 20-bit pressure to 32 bits
                    when REG_HUMIDITY =>
                        readdata <= x"0000" & humid_raw_i;   -- Pad 16-bit humidity to 32 bits
                    when REG_STATUS =>
                        -- [1]=error bit, [0]=data_valid; upper 30 bits forced zero
                        readdata <= (31 downto 2 => '0') & bme_error_i & data_valid_i;
                    when REG_CONTROL =>
                        readdata <= (31 downto 1 => '0') & enable;   -- Return current enable state
                    when others =>
                        readdata <= (others => '0');   -- Unmapped address returns zero
                end case;
            end if;
        end if;
    end process;

end Behavioral;
