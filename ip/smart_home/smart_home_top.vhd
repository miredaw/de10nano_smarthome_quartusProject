----------------------------------------------------------------------------------
-- Top-Level Smart Home Monitor (FPGA Fabric)


----     IT IS NOT BEING USED IN THIS PROJECT.


-- Integrates all peripherals and provides memory-mapped interface to ARM HPS
-- Target: DE10-Nano (Cyclone V SoC)
--
-- NOTE: This file is a standalone top-level for the FPGA fabric only.
--       In the actual project, DE10_NANO_SoC_GHRD.vhd is the true top level,
--       and this file is NOT used directly (the Platform Designer soc_system
--       component instantiates each Avalon wrapper individually).
--       Kept for reference and standalone simulation/testing.
----------------------------------------------------------------------------------

library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned/signed arithmetic

entity smart_home_top is
    Port (
        -- Clock and Reset
        CLOCK_50        : in  std_logic;                        -- 50 MHz board oscillator
        KEY             : in  std_logic_vector(1 downto 0);     -- Active-low push buttons: KEY(0) = reset

        -- I2C (BME280 temperature/humidity/pressure sensor)
        I2C_SDA         : inout std_logic;   -- BME280 I2C data line (open-drain)
        I2C_SCL         : out std_logic;     -- BME280 I2C clock (NOTE: should be inout for stretch; simplified here)

        -- SPI (MCP3008 ADC)
        SPI_CLK         : out std_logic;     -- SPI clock to MCP3008
        SPI_MOSI        : out std_logic;     -- SPI MOSI to MCP3008 DIN
        SPI_MISO        : in  std_logic;     -- SPI MISO from MCP3008 DOUT
        SPI_CS_N        : out std_logic;     -- SPI CS_N to MCP3008

        -- GPIO Inputs
        PIR1_IN         : in  std_logic;                        -- PIR motion sensor 1 (active-high)
        PIR2_IN         : in  std_logic;                        -- PIR motion sensor 2 (active-high)
        BUTTON_IN       : in  std_logic_vector(3 downto 0);     -- External push-buttons (active-low)

        -- GPIO Outputs
        LED_RED         : out std_logic;     -- Red    LED output
        LED_GREEN       : out std_logic;     -- Green  LED output
        LED_YELLOW      : out std_logic;     -- Yellow LED output
        BUZZER          : out std_logic;     -- Buzzer output

        -- UARTs (connected to HPS-side UART controllers for pass-through)
        UART1_TX        : out std_logic;     -- FPGA TX -> ESP32 RX (AT commands)
        UART1_RX        : in  std_logic;     -- ESP32 TX -> FPGA RX
        UART2_TX        : out std_logic;     -- FPGA TX -> SIM800L RX (GSM AT commands)
        UART2_RX        : in  std_logic;     -- SIM800L TX -> FPGA RX

        -- HPS Interface (Avalon Memory-Mapped, driven by HPS Lightweight AXI Bridge)
        hps_address     : in  std_logic_vector(7 downto 0);     -- 8-bit word address from HPS
        hps_write       : in  std_logic;                        -- HPS write strobe
        hps_writedata   : in  std_logic_vector(31 downto 0);    -- 32-bit data from HPS
        hps_read        : in  std_logic;                        -- HPS read strobe
        hps_readdata    : out std_logic_vector(31 downto 0);    -- 32-bit data returned to HPS
        hps_waitrequest : out std_logic                         -- Stall signal (always '0' here)
    );
end smart_home_top;

architecture Behavioral of smart_home_top is

    -- Component declarations (simplified port lists matching actual entities)
    component bme280_controller is
        Generic (BME280_ADDR : std_logic_vector(6 downto 0) := "1110110");
        Port (
            clk, reset, enable : in std_logic;
            temp_raw   : out std_logic_vector(19 downto 0);   -- 20-bit raw temperature
            press_raw  : out std_logic_vector(19 downto 0);   -- 20-bit raw pressure
            humid_raw  : out std_logic_vector(15 downto 0);   -- 16-bit raw humidity
            data_valid, error : out std_logic;
            sda : inout std_logic;
            scl : out std_logic   -- Simplified (should be inout; see bme280_controller.vhd)
        );
    end component;

    component multi_channel_adc is
        Generic (FILTER_DEPTH : integer := 8);
        Port (
            clk, reset, enable : in std_logic;
            light_level, heating_level, sound_level : out std_logic_vector(9 downto 0);
            data_valid : out std_logic;
            spi_clk, spi_mosi : out std_logic;
            spi_miso : in std_logic;
            spi_cs_n : out std_logic
        );
    end component;

    component gpio_controller is
        Generic (DEBOUNCE_TIME : integer := 2_500_000);
        Port (
            clk, reset : in std_logic;
            pir1_in, pir2_in : in std_logic;
            button_in : in std_logic_vector(3 downto 0);
            pir1_detect, pir2_detect : out std_logic;
            button_pressed : out std_logic_vector(3 downto 0);
            button_event : out std_logic;
            led_red, led_green, led_yellow, buzzer : out std_logic;
            led_red_ctrl, led_green_ctrl, led_yellow_ctrl, buzzer_ctrl : in std_logic
        );
    end component;

    component alarm_logic is
        Port (
            clk, reset : in std_logic;
            temperature : in std_logic_vector(15 downto 0);
            light_level : in std_logic_vector(9 downto 0);
            motion_detected : in std_logic;
            temp_low_threshold, temp_high_threshold : in std_logic_vector(15 downto 0);
            light_threshold : in std_logic_vector(9 downto 0);
            alarm_temp_high, alarm_temp_low, alarm_light_low, alarm_motion, alarm_critical : out std_logic;
            led_red_out, led_yellow_out, led_green_out, buzzer_out : out std_logic
        );
    end component;

    -- Internal signals
    signal reset : std_logic;   -- Active-high reset derived from active-low KEY(0)

    -- BME280 sensor signals
    signal bme_enable   : std_logic := '1';                    -- Always enabled in standalone mode
    signal bme_temp_raw : std_logic_vector(19 downto 0);       -- 20-bit raw temperature output
    signal bme_press_raw: std_logic_vector(19 downto 0);       -- 20-bit raw pressure output
    signal bme_humid_raw: std_logic_vector(15 downto 0);       -- 16-bit raw humidity output
    signal bme_valid    : std_logic;                           -- '1' once sensor has completed first read
    signal bme_error    : std_logic;                           -- '1' on I2C bus error

    -- MCP3008 ADC signals
    signal adc_enable   : std_logic := '1';                    -- Always enabled in standalone mode
    signal adc_light    : std_logic_vector(9 downto 0);        -- Filtered CH0 light reading
    signal adc_heating  : std_logic_vector(9 downto 0);        -- Filtered CH1 heating potentiometer
    signal adc_sound    : std_logic_vector(9 downto 0);        -- Filtered CH2 sound potentiometer
    signal adc_valid    : std_logic;                           -- '1' once ADC has completed first scan

    -- GPIO debounced signals
    signal pir1_detect, pir2_detect : std_logic;               -- Debounced PIR outputs
    signal motion_any : std_logic;                             -- OR of PIR1 and PIR2 (any motion)
    signal button_pressed : std_logic_vector(3 downto 0);      -- Debounced button states
    signal button_event : std_logic;                           -- One-cycle pulse on button press

    -- Alarm system signals
    signal alarm_temp_high, alarm_temp_low : std_logic;        -- Temperature alarm flags
    signal alarm_light_low, alarm_motion : std_logic;          -- Light and motion alarm flags
    signal alarm_critical : std_logic;                         -- OR of all alarm flags
    signal alarm_led_red, alarm_led_yellow, alarm_led_green : std_logic;  -- Alarm-driven LED outputs
    signal alarm_buzzer : std_logic;                           -- Alarm-driven buzzer output

    -- HPS-writable alarm threshold registers
    signal temp_low_thresh  : std_logic_vector(15 downto 0) := x"1400";      -- Default: ~20 °C
    signal temp_high_thresh : std_logic_vector(15 downto 0) := x"1E00";      -- Default: ~30 °C
    signal light_thresh     : std_logic_vector(9 downto 0)  := "0001100100"; -- Default: 100/1023 ADC counts

    -- Status registers (assembled for HPS reads)
    signal status_reg  : std_logic_vector(31 downto 0);   -- BME280 status: error | valid
    signal temp_reg    : std_logic_vector(31 downto 0);   -- Raw temperature register
    signal sensor_reg  : std_logic_vector(31 downto 0);   -- Sensor status word

    -- Memory-mapped register addresses (HPS writes/reads these via hps_address)
    constant REG_STATUS      : std_logic_vector(7 downto 0) := x"00";  -- BME280 valid/error status
    constant REG_TEMP        : std_logic_vector(7 downto 0) := x"04";  -- Raw temperature ADC value
    constant REG_PRESSURE    : std_logic_vector(7 downto 0) := x"08";  -- Raw pressure ADC value
    constant REG_HUMIDITY    : std_logic_vector(7 downto 0) := x"0C";  -- Raw humidity ADC value
    constant REG_LIGHT       : std_logic_vector(7 downto 0) := x"10";  -- Filtered light ADC value
    constant REG_HEATING     : std_logic_vector(7 downto 0) := x"14";  -- Filtered heating ADC value
    constant REG_SOUND       : std_logic_vector(7 downto 0) := x"18";  -- Filtered sound ADC value
    constant REG_ALARMS      : std_logic_vector(7 downto 0) := x"1C";  -- Active alarm flags bitmask
    constant REG_TEMP_LOW    : std_logic_vector(7 downto 0) := x"20";  -- R/W: low  temperature threshold
    constant REG_TEMP_HIGH   : std_logic_vector(7 downto 0) := x"24";  -- R/W: high temperature threshold
    constant REG_LIGHT_THRES : std_logic_vector(7 downto 0) := x"28";  -- R/W: light threshold

begin

    -- Reset logic: KEY(0) is active-low; invert to get active-high reset for all components
    reset <= not KEY(0);

    -- Combine PIR sensors: any motion on either sensor triggers the alarm logic
    motion_any <= pir1_detect or pir2_detect;

    --------------------------
    -- Instantiate Components
    --------------------------

    -- BME280 I2C sensor controller (temperature, pressure, humidity)
    bme_inst: bme280_controller
        generic map (BME280_ADDR => "1110110")   -- I2C address 0x76 (SDO tied to GND)
        port map (
            clk        => CLOCK_50,       -- 50 MHz clock
            reset      => reset,          -- Active-high reset
            enable     => bme_enable,     -- Always enabled
            temp_raw   => bme_temp_raw,   -- 20-bit temperature output
            press_raw  => bme_press_raw,  -- 20-bit pressure output
            humid_raw  => bme_humid_raw,  -- 16-bit humidity output
            data_valid => bme_valid,      -- Sensor data ready flag
            error      => bme_error,      -- I2C error flag
            sda        => I2C_SDA,        -- Physical SDA pin
            scl        => I2C_SCL         -- Physical SCL pin
        );

    -- MCP3008 SPI ADC controller (light, heating, sound channels)
    adc_inst: multi_channel_adc
        generic map (FILTER_DEPTH => 8)   -- 8-sample moving average
        port map (
            clk           => CLOCK_50,      -- 50 MHz clock
            reset         => reset,
            enable        => adc_enable,    -- Always enabled
            light_level   => adc_light,     -- CH0 filtered output
            heating_level => adc_heating,   -- CH1 filtered output
            sound_level   => adc_sound,     -- CH2 filtered output
            data_valid    => adc_valid,     -- ADC data ready flag
            spi_clk       => SPI_CLK,       -- Physical SPI CLK pin
            spi_mosi      => SPI_MOSI,      -- Physical SPI MOSI pin
            spi_miso      => SPI_MISO,      -- Physical SPI MISO pin
            spi_cs_n      => SPI_CS_N       -- Physical SPI CS_N pin
        );

    -- GPIO controller: debounces PIR sensors and buttons, drives LEDs and buzzer
    gpio_inst: gpio_controller
        generic map (DEBOUNCE_TIME => 2_500_000)   -- 50 ms debounce @ 50 MHz
        port map (
            clk             => CLOCK_50,
            reset           => reset,
            pir1_in         => PIR1_IN,           -- Raw PIR1 input
            pir2_in         => PIR2_IN,           -- Raw PIR2 input
            button_in       => BUTTON_IN,         -- Raw button inputs
            pir1_detect     => pir1_detect,       -- Debounced PIR1
            pir2_detect     => pir2_detect,       -- Debounced PIR2
            button_pressed  => button_pressed,    -- Debounced button states
            button_event    => button_event,      -- Button press event pulse
            led_red         => LED_RED,           -- Physical red    LED pin
            led_green       => LED_GREEN,         -- Physical green  LED pin
            led_yellow      => LED_YELLOW,        -- Physical yellow LED pin
            buzzer          => BUZZER,            -- Physical buzzer pin
            -- Alarm logic drives LEDs/buzzer autonomously (no HPS software needed)
            led_red_ctrl    => alarm_led_red,
            led_green_ctrl  => alarm_led_green,
            led_yellow_ctrl => alarm_led_yellow,
            buzzer_ctrl     => alarm_buzzer
        );

    -- Alarm logic: compares sensor readings to thresholds and drives outputs
    alarm_inst: alarm_logic
        port map (
            clk             => CLOCK_50,
            reset           => reset,
            -- Use upper 16 bits of 20-bit temp as the fixed-point temperature word
            temperature     => bme_temp_raw(19 downto 4),
            light_level     => adc_light,          -- Filtered light ADC value
            motion_detected => motion_any,          -- Motion from either PIR sensor
            temp_low_threshold  => temp_low_thresh,  -- HPS-configurable threshold
            temp_high_threshold => temp_high_thresh, -- HPS-configurable threshold
            light_threshold     => light_thresh,     -- HPS-configurable threshold
            alarm_temp_high => alarm_temp_high,
            alarm_temp_low  => alarm_temp_low,
            alarm_light_low => alarm_light_low,
            alarm_motion    => alarm_motion,
            alarm_critical  => alarm_critical,
            led_red_out     => alarm_led_red,    -- Drives gpio_controller led_red_ctrl
            led_yellow_out  => alarm_led_yellow,
            led_green_out   => alarm_led_green,
            buzzer_out      => alarm_buzzer
        );

    --------------------------
    -- HPS Memory-Mapped Interface
    -- Single Avalon MM slave covering all sensor read registers and threshold write registers
    --------------------------
    process(CLOCK_50, reset)
    begin
        if reset = '1' then
            hps_readdata    <= (others => '0');   -- Clear read data
            hps_waitrequest <= '0';              -- Never stall bus
            temp_low_thresh  <= x"1400";          -- Restore default thresholds
            temp_high_thresh <= x"1E00";
            light_thresh     <= "0001100100";

        elsif rising_edge(CLOCK_50) then
            hps_waitrequest <= '0';   -- Always ready; no wait state

            -- Write path: HPS writes alarm thresholds at startup
            if hps_write = '1' then
                case hps_address is
                    when REG_TEMP_LOW =>
                        temp_low_thresh <= hps_writedata(15 downto 0);    -- Set low  temp threshold
                    when REG_TEMP_HIGH =>
                        temp_high_thresh <= hps_writedata(15 downto 0);   -- Set high temp threshold
                    when REG_LIGHT_THRES =>
                        light_thresh <= hps_writedata(9 downto 0);        -- Set light threshold
                    when others =>
                        null;   -- All other addresses are read-only
                end case;
            end if;

            -- Read path: HPS polls sensor data and alarm states
            if hps_read = '1' then
                case hps_address is
                    when REG_STATUS =>
                        -- [1]=bme_error, [0]=bme_valid; upper bits zero
                        hps_readdata <= x"0000000" & "00" & bme_error & bme_valid;

                    when REG_TEMP =>
                        hps_readdata <= x"000" & bme_temp_raw;    -- 20-bit raw temperature, padded

                    when REG_PRESSURE =>
                        hps_readdata <= x"000" & bme_press_raw;   -- 20-bit raw pressure, padded

                    when REG_HUMIDITY =>
                        hps_readdata <= x"0000" & bme_humid_raw;  -- 16-bit raw humidity, padded

                    when REG_LIGHT =>
                        hps_readdata <= x"00000" & "00" & adc_light;    -- 10-bit light, padded

                    when REG_HEATING =>
                        hps_readdata <= x"00000" & "00" & adc_heating;  -- 10-bit heating, padded

                    when REG_SOUND =>
                        hps_readdata <= x"00000" & "00" & adc_sound;    -- 10-bit sound, padded

                    when REG_ALARMS =>
                        -- [4]=critical, [3]=motion, [2]=light, [1]=temp_low, [0]=temp_high
                        hps_readdata <= x"0000000" &
                                       alarm_critical & alarm_motion &
                                       alarm_light_low & alarm_temp_low & alarm_temp_high;

                    when REG_TEMP_LOW =>
                        hps_readdata <= x"0000" & temp_low_thresh;   -- Read back low  threshold

                    when REG_TEMP_HIGH =>
                        hps_readdata <= x"0000" & temp_high_thresh;  -- Read back high threshold

                    when REG_LIGHT_THRES =>
                        hps_readdata <= x"00000" & "00" & light_thresh;  -- Read back light threshold

                    when others =>
                        hps_readdata <= (others => '0');  -- Unmapped address returns zero
                end case;
            end if;
        end if;
    end process;

end Behavioral;
