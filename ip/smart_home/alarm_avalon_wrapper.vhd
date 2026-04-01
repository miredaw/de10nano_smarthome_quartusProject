----------------------------------------------------------------------------------
-- Avalon MM Wrapper for Alarm Logic Controller
-- FIXED: Added led_red_out, led_yellow_out, led_green_out, buzzer_out as output
--        PORTS (not just internal signals) so they can be wired to gpio_avalon_wrapper
--        alarm override inputs in DE10_NANO_SoC_GHRD.
--
-- Register Map (word-addressed):
--   0x00 (addr "000") : REG_ALARM_STATUS  - [4]=critical,[3]=motion,[2]=light,[1]=temp_low,[0]=temp_high (R)
--   0x04 (addr "001") : REG_TEMP_LOW      - [15:0] low  temp threshold (R/W, default 0x1400)
--   0x08 (addr "010") : REG_TEMP_HIGH     - [15:0] high temp threshold (R/W, default 0x1E00)
--   0x0C (addr "011") : REG_LIGHT_THRESH  - [9:0]  light threshold (R/W, default 100)
--   0x10 (addr "100") : REG_OUTPUT_STATUS - [3]=buzzer,[2]=green,[1]=yellow,[0]=red (R)
--
-- LW Bridge address: 0xFF200000 + 0x60 = 0xFF200060
----------------------------------------------------------------------------------

library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned/signed arithmetic

entity alarm_avalon_wrapper is
    Port (
        -- Avalon MM Slave Interface (driven by HPS via Lightweight AXI Bridge)
        clk         : in  std_logic;                        -- 50 MHz system clock from HPS bridge
        reset       : in  std_logic;                        -- Active-high synchronous reset
        address     : in  std_logic_vector(2 downto 0);     -- 3-bit word address selects register (0-4)
        write       : in  std_logic;                        -- High for one cycle when HPS writes a register
        writedata   : in  std_logic_vector(31 downto 0);    -- 32-bit data word from HPS write
        read        : in  std_logic;                        -- High for one cycle when HPS reads a register
        readdata    : out std_logic_vector(31 downto 0);    -- 32-bit data returned to HPS on read
        waitrequest : out std_logic;                        -- Tied low: this peripheral never stalls the bus

        -- Sensor data inputs (from other peripherals, wired in top-level)
        temperature     : in  std_logic_vector(15 downto 0);  -- Upper 16 bits of BME280 temp_raw[19:4]
        light_level     : in  std_logic_vector(9 downto 0);   -- 10-bit filtered ADC value from MCP3008 CH0
        motion_detected : in  std_logic;                       -- '1' when PIR1 or PIR2 detects motion

        -- Alarm flag outputs (readable via register, also usable as interrupts)
        alarm_temp_high : out std_logic;   -- '1' when temperature exceeds high threshold
        alarm_temp_low  : out std_logic;   -- '1' when temperature drops below low threshold
        alarm_light_low : out std_logic;   -- '1' when light level is below the threshold
        alarm_motion    : out std_logic;   -- '1' when motion latched (5-second hold-off)
        alarm_critical  : out std_logic;   -- '1' when any of the above alarms is active

        -- Hardware output conduits - FIXED: now exported as ports so top-level
        -- can wire them to gpio_avalon_wrapper's alarm override inputs
        led_red_out    : out std_logic;    -- Drives red  LED when temp alarm is active
        led_yellow_out : out std_logic;    -- Drives yellow LED when motion alarm is active
        led_green_out  : out std_logic;    -- Drives green LED when system is fully OK
        buzzer_out     : out std_logic     -- Drives buzzer with 250 ms ON / 250 ms OFF pattern
    );
end alarm_avalon_wrapper;

architecture Behavioral of alarm_avalon_wrapper is

    -- Declare the inner alarm_logic entity as a component to instantiate below
    component alarm_logic is
        Port (
            clk                 : in  std_logic;
            reset               : in  std_logic;
            temperature         : in  std_logic_vector(15 downto 0);
            light_level         : in  std_logic_vector(9 downto 0);
            motion_detected     : in  std_logic;
            temp_low_threshold  : in  std_logic_vector(15 downto 0);
            temp_high_threshold : in  std_logic_vector(15 downto 0);
            light_threshold     : in  std_logic_vector(9 downto 0);
            alarm_temp_high     : out std_logic;
            alarm_temp_low      : out std_logic;
            alarm_light_low     : out std_logic;
            alarm_motion        : out std_logic;
            alarm_critical      : out std_logic;
            led_red_out         : out std_logic;
            led_yellow_out      : out std_logic;
            led_green_out       : out std_logic;
            buzzer_out          : out std_logic
        );
    end component;

    -- FIXED: defaults set to 0 so no false alarms fire when sensor inputs
    -- are still zero (placeholder) before Platform Designer conduit exports
    -- are added. The HPS must configure real thresholds at startup via AXI writes.
    signal temp_low_threshold  : std_logic_vector(15 downto 0) := x"0000";  -- Low  temp threshold register (HPS-writable)
    signal temp_high_threshold : std_logic_vector(15 downto 0) := x"FFFF";  -- High temp threshold register (HPS-writable); default=max prevents false alarm before HPS configures it
    signal light_threshold     : std_logic_vector(9 downto 0)  := "0000000000";  -- Light threshold register (HPS-writable); default=0 disables alarm until HPS sets a real value

    -- Internal copies of alarm_logic outputs; used for both port driving and readdata mux
    signal alarm_temp_high_i  : std_logic;   -- Internal temp-high alarm flag
    signal alarm_temp_low_i   : std_logic;   -- Internal temp-low  alarm flag
    signal alarm_light_low_i  : std_logic;   -- Internal light-low alarm flag
    signal alarm_motion_i     : std_logic;   -- Internal motion alarm flag (latched 5 s)
    signal alarm_critical_i   : std_logic;   -- Internal critical (OR of all alarms) flag
    signal led_red_i          : std_logic;   -- Internal red LED drive from alarm_logic
    signal led_yellow_i       : std_logic;   -- Internal yellow LED drive from alarm_logic
    signal led_green_i        : std_logic;   -- Internal green LED drive from alarm_logic
    signal buzzer_i           : std_logic;   -- Internal buzzer drive from alarm_logic

    -- Register address constants (3-bit word address from Avalon bus)
    constant REG_ALARM_STATUS  : std_logic_vector(2 downto 0) := "000";  -- addr 0x00: read alarm flags
    constant REG_TEMP_LOW      : std_logic_vector(2 downto 0) := "001";  -- addr 0x04: R/W low  temp threshold
    constant REG_TEMP_HIGH     : std_logic_vector(2 downto 0) := "010";  -- addr 0x08: R/W high temp threshold
    constant REG_LIGHT_THRESH  : std_logic_vector(2 downto 0) := "011";  -- addr 0x0C: R/W light threshold
    constant REG_OUTPUT_STATUS : std_logic_vector(2 downto 0) := "100";  -- addr 0x10: read LED/buzzer state

begin

    -- Instantiate the combinational/sequential alarm decision engine
    alarm_inst: alarm_logic
        port map (
            clk                 => clk,                   -- Connect system clock
            reset               => reset,                 -- Connect system reset
            temperature         => temperature,           -- Wire BME280 temp[15:0] in
            light_level         => light_level,           -- Wire ADC light channel in
            motion_detected     => motion_detected,       -- Wire PIR OR-result in
            temp_low_threshold  => temp_low_threshold,    -- Pass register to comparator
            temp_high_threshold => temp_high_threshold,   -- Pass register to comparator
            light_threshold     => light_threshold,       -- Pass register to comparator
            alarm_temp_high     => alarm_temp_high_i,     -- Capture alarm flag
            alarm_temp_low      => alarm_temp_low_i,      -- Capture alarm flag
            alarm_light_low     => alarm_light_low_i,     -- Capture alarm flag
            alarm_motion        => alarm_motion_i,        -- Capture alarm flag
            alarm_critical      => alarm_critical_i,      -- Capture OR of all flags
            led_red_out         => led_red_i,             -- Capture LED drive
            led_yellow_out      => led_yellow_i,          -- Capture LED drive
            led_green_out       => led_green_i,           -- Capture LED drive
            buzzer_out          => buzzer_i               -- Capture buzzer drive
        );

    -- Drive output ports from internal signals (needed so both port and readdata can use them)
    alarm_temp_high <= alarm_temp_high_i;   -- Expose temp-high alarm to top-level / conduit
    alarm_temp_low  <= alarm_temp_low_i;    -- Expose temp-low  alarm to top-level / conduit
    alarm_light_low <= alarm_light_low_i;   -- Expose light-low alarm to top-level / conduit
    alarm_motion    <= alarm_motion_i;      -- Expose motion    alarm to top-level / conduit
    alarm_critical  <= alarm_critical_i;    -- Expose critical  alarm to top-level / conduit
    led_red_out     <= led_red_i;           -- Expose red LED drive  -> gpio_avalon_wrapper alarm_led_red
    led_yellow_out  <= led_yellow_i;        -- Expose yellow LED drive -> gpio_avalon_wrapper alarm_led_yellow
    led_green_out   <= led_green_i;         -- Expose green LED drive  -> gpio_avalon_wrapper alarm_led_green
    buzzer_out      <= buzzer_i;            -- Expose buzzer drive     -> gpio_avalon_wrapper alarm_buzzer

    waitrequest <= '0';   -- This peripheral is always ready; never insert wait states

    -- Avalon MM register process: handles HPS read/write transactions
    process(clk, reset)
    begin
        if reset = '1' then
            -- Asynchronous reset: clear readdata and restore safe threshold defaults
            readdata            <= (others => '0');   -- Clear readdata register
            temp_low_threshold  <= x"0000";           -- Reset low  threshold (alarms disabled until HPS sets values)
            temp_high_threshold <= x"FFFF";           -- Reset high threshold (max = no high-temp alarm until HPS configures)
            light_threshold     <= "0000000000";      -- Reset light threshold (zero = no light alarm until HPS configures)

        elsif rising_edge(clk) then
            -- Write path: HPS can set alarm thresholds at any time
            if write = '1' then
                case address is
                    when REG_TEMP_LOW =>
                        temp_low_threshold <= writedata(15 downto 0);   -- Latch lower 16 bits as low temp threshold
                    when REG_TEMP_HIGH =>
                        temp_high_threshold <= writedata(15 downto 0);  -- Latch lower 16 bits as high temp threshold
                    when REG_LIGHT_THRESH =>
                        light_threshold <= writedata(9 downto 0);       -- Latch lower 10 bits as light threshold
                    when others => null;   -- All other addresses are read-only; ignore writes
                end case;
            end if;

            -- Read path: HPS polls these registers to check alarm state and thresholds
            if read = '1' then
                case address is
                    when REG_ALARM_STATUS =>
                        -- Pack five alarm flags into bits [4:0]; upper bits forced to 0
                        readdata <= (31 downto 5 => '0') &
                                    alarm_critical_i & alarm_motion_i &
                                    alarm_light_low_i & alarm_temp_low_i & alarm_temp_high_i;
                    when REG_TEMP_LOW =>
                        readdata <= x"0000" & temp_low_threshold;    -- Return current low  threshold padded to 32 bits
                    when REG_TEMP_HIGH =>
                        readdata <= x"0000" & temp_high_threshold;   -- Return current high threshold padded to 32 bits
                    when REG_LIGHT_THRESH =>
                        readdata <= x"00000" & "00" & light_threshold;   -- Return current light threshold padded to 32 bits
                    when REG_OUTPUT_STATUS =>
                        -- Pack four hardware output states into bits [3:0]: buzzer|green|yellow|red
                        readdata <= (31 downto 4 => '0') &
                                    buzzer_i & led_green_i & led_yellow_i & led_red_i;
                    when others =>
                        readdata <= (others => '0');   -- Unmapped addresses return zero
                end case;
            end if;
        end if;
    end process;

end Behavioral;
