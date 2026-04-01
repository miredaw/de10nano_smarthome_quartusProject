----------------------------------------------------------------------------------
-- Alarm Logic and Threshold Comparators
-- Autonomous real-time decision engine in FPGA
-- Compares sensor data against configurable thresholds
----------------------------------------------------------------------------------

library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned() cast for comparisons

entity alarm_logic is
    Port (
        clk                 : in  std_logic;   -- 50 MHz system clock
        reset               : in  std_logic;   -- Active-high synchronous reset

        -- Sensor inputs (updated every sensor cycle by their respective controllers)
        temperature         : in  std_logic_vector(15 downto 0);  -- BME280 raw temp bits[19:4], fixed-point format
        light_level         : in  std_logic_vector(9 downto 0);   -- MCP3008 CH0 filtered 10-bit ADC value
        motion_detected     : in  std_logic;                       -- '1' for one cycle when PIR detects motion

        -- Threshold registers (written by HPS via alarm_avalon_wrapper Avalon interface)
        temp_low_threshold  : in  std_logic_vector(15 downto 0);  -- Temperature below this triggers low-temp alarm
        temp_high_threshold : in  std_logic_vector(15 downto 0);  -- Temperature above this triggers high-temp alarm
        light_threshold     : in  std_logic_vector(9 downto 0);   -- Light below this triggers darkness alarm

        -- Alarm flag outputs (combinational, updated every clock)
        alarm_temp_high     : out std_logic;   -- '1' when temperature > high threshold
        alarm_temp_low      : out std_logic;   -- '1' when temperature < low threshold
        alarm_light_low     : out std_logic;   -- '1' when light_level < light_threshold
        alarm_motion        : out std_logic;   -- '1' for 5 seconds after last motion pulse
        alarm_critical      : out std_logic;   -- '1' when any single alarm is active (OR of all)

        -- Hardware response outputs (drive LEDs and buzzer directly without HPS involvement)
        led_red_out         : out std_logic;   -- Active when temperature alarm fires
        led_yellow_out      : out std_logic;   -- Active when motion alarm fires
        led_green_out       : out std_logic;   -- Active only when ALL alarms are clear (system OK)
        buzzer_out          : out std_logic    -- Pulsed 250 ms ON / 250 ms OFF during critical alarm
    );
end alarm_logic;

architecture Behavioral of alarm_logic is

    -- Internal registered alarm flags (registered to avoid glitches on combinational paths)
    signal temp_high_alarm : std_logic := '0';   -- Registered copy of temperature-high comparator result
    signal temp_low_alarm  : std_logic := '0';   -- Registered copy of temperature-low  comparator result
    signal light_alarm     : std_logic := '0';   -- Registered copy of light-low comparator result
    signal motion_alarm    : std_logic := '0';   -- Motion alarm latch (held for 5 seconds after last trigger)

    -- Buzzer pulse generator state
    signal buzzer_counter : integer range 0 to 25_000_000 := 0;  -- Counts 50 MHz cycles; period = 500 ms (25M * 2 phases)
    signal buzzer_state   : std_logic := '0';                     -- Current ON/OFF phase of buzzer square wave

    -- Motion latch countdown timer
    -- Loaded to 5 s worth of 50 MHz ticks each time motion_detected pulses
    signal motion_timer : integer range 0 to 250_000_000 := 0;  -- 250_000_000 cycles = 5 s @ 50 MHz

begin

    -- Threshold comparator process: evaluates sensor readings every clock cycle
    process(clk, reset)
    begin
        if reset = '1' then
            -- On reset clear all alarm flags and the motion timer
            temp_high_alarm <= '0';   -- No temperature-high alarm
            temp_low_alarm  <= '0';   -- No temperature-low  alarm
            light_alarm     <= '0';   -- No light alarm
            motion_alarm    <= '0';   -- No motion alarm
            motion_timer    <= 0;     -- Motion latch timer cleared

        elsif rising_edge(clk) then

            -- Temperature high alarm: fire when reading exceeds high threshold
            if unsigned(temperature) > unsigned(temp_high_threshold) then
                temp_high_alarm <= '1';   -- Temperature is too hot
            else
                temp_high_alarm <= '0';   -- Temperature is within safe range
            end if;

            -- Temperature low alarm: fire when reading drops below low threshold
            if unsigned(temperature) < unsigned(temp_low_threshold) then
                temp_low_alarm <= '1';   -- Temperature is too cold
            else
                temp_low_alarm <= '0';   -- Temperature is within safe range
            end if;

            -- Light level alarm: fire when the room is too dark
            if unsigned(light_level) < unsigned(light_threshold) then
                light_alarm <= '1';   -- Insufficient ambient light detected
            else
                light_alarm <= '0';   -- Light level is acceptable
            end if;

            -- Motion detection with 5-second hold latch:
            -- Reload the timer every time motion_detected pulses to extend the active window.
            -- When the timer expires and no new pulse arrives, clear the alarm.
            if motion_detected = '1' then
                motion_alarm <= '1';               -- Immediately assert alarm
                motion_timer <= 250_000_000;       -- Restart 5-second hold-off timer
            elsif motion_timer > 0 then
                motion_timer <= motion_timer - 1;  -- Decrement countdown each clock cycle
                motion_alarm <= '1';               -- Keep alarm asserted while counting down
            else
                motion_alarm <= '0';               -- Timer expired and no new motion: clear alarm
            end if;

        end if;
    end process;

    -- Drive registered alarm flags to output ports
    alarm_temp_high <= temp_high_alarm;   -- Temperature-high alarm visible to Avalon wrapper and top-level
    alarm_temp_low  <= temp_low_alarm;    -- Temperature-low  alarm visible to Avalon wrapper and top-level
    alarm_light_low <= light_alarm;       -- Light-low alarm visible to Avalon wrapper and top-level
    alarm_motion    <= motion_alarm;      -- Motion alarm visible to Avalon wrapper and top-level

    -- Critical alarm flag: asserted whenever any individual alarm is active
    alarm_critical <= temp_high_alarm or temp_low_alarm or light_alarm or motion_alarm;

    -- LED control process: maps alarm conditions to specific LED outputs
    process(clk, reset)
    begin
        if reset = '1' then
            led_red_out    <= '0';   -- Red LED off at reset
            led_yellow_out <= '0';   -- Yellow LED off at reset
            led_green_out  <= '0';   -- Green LED off at reset
        elsif rising_edge(clk) then
            -- Red LED: indicates temperature out of range (too hot or too cold)
            if temp_high_alarm = '1' or temp_low_alarm = '1' then
                led_red_out <= '1';   -- Turn on red LED for any temperature alarm
            else
                led_red_out <= '0';   -- No temperature alarm: red LED off
            end if;

            -- Yellow LED: indicates motion has been detected within the last 5 seconds
            if motion_alarm = '1' then
                led_yellow_out <= '1';   -- Turn on yellow LED while motion latch is active
            else
                led_yellow_out <= '0';   -- No motion: yellow LED off
            end if;

            -- Green LED: system OK indicator; only on when all alarms are clear
            if temp_high_alarm = '0' and temp_low_alarm = '0' and
               light_alarm = '0' and motion_alarm = '0' then
                led_green_out <= '1';   -- All sensors within normal range
            else
                led_green_out <= '0';   -- At least one alarm is active; green LED off
            end if;
        end if;
    end process;

    -- Buzzer control process: generates a 500 ms period (250 ms ON / 250 ms OFF) tone
    -- while any critical alarm (temperature or motion) is active
    process(clk, reset)
    begin
        if reset = '1' then
            buzzer_counter <= 0;     -- Clear phase counter at reset
            buzzer_state   <= '0';   -- Buzzer off at reset

        elsif rising_edge(clk) then
            if temp_high_alarm = '1' or temp_low_alarm = '1' or motion_alarm = '1' then
                -- Generate 500ms pulse pattern (250ms ON, 250ms OFF)
                if buzzer_counter < 12_500_000 then  -- Count up to 250 ms (12.5M cycles @ 50 MHz)
                    buzzer_counter <= buzzer_counter + 1;   -- Continue counting current phase
                else
                    buzzer_counter <= 0;                          -- Phase complete: reset counter
                    buzzer_state   <= not buzzer_state;           -- Toggle ON/OFF phase
                end if;
            else
                -- No active alarm: silence buzzer and reset state machine
                buzzer_counter <= 0;      -- Reset phase counter so next alarm starts cleanly
                buzzer_state   <= '0';    -- Ensure buzzer is off
            end if;
        end if;
    end process;

    -- Drive buzzer output from the toggling state register
    buzzer_out <= buzzer_state;   -- Physical buzzer pin driven by 2 Hz square wave when alarm active

end Behavioral;
