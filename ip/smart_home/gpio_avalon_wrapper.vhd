----------------------------------------------------------------------------------
-- Avalon MM Wrapper for GPIO Controller
-- FIXED: Added alarm_led/buzzer inputs so alarm_logic can drive outputs directly
--        when HPS hasn't overridden them. OR-logic between HPS control and alarm.
--
-- Register Map (word-addressed):
--   0x00 (addr "000") : REG_PIR_STATUS    - [1]=pir2_detect, [0]=pir1_detect (R)
--   0x04 (addr "001") : REG_BUTTON_STATUS - [7]=button_event, [3:0]=button_pressed (R)
--   0x08 (addr "010") : REG_LED_CONTROL   - [2]=yellow, [1]=green, [0]=red (R/W)
--   0x0C (addr "011") : REG_BUZZER_CTRL   - [0]=buzzer (R/W)
--
-- LW Bridge address: 0xFF200000 + 0x40 = 0xFF200040
----------------------------------------------------------------------------------

library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned/signed arithmetic

entity gpio_avalon_wrapper is
    Port (
        -- Avalon MM Slave Interface (connected to HPS via Lightweight AXI bridge)
        clk         : in  std_logic;                        -- 50 MHz system clock
        reset       : in  std_logic;                        -- Active-high synchronous reset
        address     : in  std_logic_vector(2 downto 0);     -- 3-bit word address: selects one of 4 registers
        write       : in  std_logic;                        -- HPS write strobe (one cycle)
        writedata   : in  std_logic_vector(31 downto 0);    -- 32-bit data from HPS
        read        : in  std_logic;                        -- HPS read strobe (one cycle)
        readdata    : out std_logic_vector(31 downto 0);    -- 32-bit response to HPS read
        waitrequest : out std_logic;                        -- Always '0': this peripheral never stalls

        -- GPIO Conduit (exported to top-level board pins via Platform Designer)
        pir1_in    : in  std_logic;                        -- PIR sensor 1 raw input (JP1 pin 7)
        pir2_in    : in  std_logic;                        -- PIR sensor 2 raw input (JP1 pin 8)
        button_in  : in  std_logic_vector(3 downto 0);     -- Four external push-buttons (active-low)
        led_red    : out std_logic;                        -- Physical red    LED output pin
        led_green  : out std_logic;                        -- Physical green  LED output pin
        led_yellow : out std_logic;                        -- Physical yellow LED output pin
        buzzer     : out std_logic;                        -- Physical buzzer output pin

        -- Alarm override inputs (from alarm_avalon_wrapper / alarm_logic)
        -- These OR with the HPS software control so alarms work autonomously
        -- even when the HPS supervisor is sleeping or has not responded yet
        alarm_led_red    : in  std_logic;   -- Alarm engine requests red    LED on (temp alarm)
        alarm_led_yellow : in  std_logic;   -- Alarm engine requests yellow LED on (motion alarm)
        alarm_led_green  : in  std_logic;   -- Alarm engine requests green  LED on (system OK)
        alarm_buzzer     : in  std_logic    -- Alarm engine requests buzzer activation
    );
end gpio_avalon_wrapper;

architecture Behavioral of gpio_avalon_wrapper is

    -- Declare gpio_controller as a component to allow instantiation
    component gpio_controller is
        Generic (DEBOUNCE_TIME : integer := 2_500_000);   -- Debounce window in clock cycles (50 ms @ 50 MHz)
        Port (
            clk             : in  std_logic;
            reset           : in  std_logic;
            pir1_in         : in  std_logic;
            pir2_in         : in  std_logic;
            button_in       : in  std_logic_vector(3 downto 0);
            pir1_detect     : out std_logic;
            pir2_detect     : out std_logic;
            button_pressed  : out std_logic_vector(3 downto 0);
            button_event    : out std_logic;
            led_red         : out std_logic;
            led_green       : out std_logic;
            led_yellow      : out std_logic;
            buzzer          : out std_logic;
            led_red_ctrl    : in  std_logic;   -- Combined (HPS OR alarm) red    LED drive
            led_green_ctrl  : in  std_logic;   -- Combined (HPS OR alarm) green  LED drive
            led_yellow_ctrl : in  std_logic;   -- Combined (HPS OR alarm) yellow LED drive
            buzzer_ctrl     : in  std_logic    -- Combined (HPS OR alarm) buzzer drive
        );
    end component;

    -- Outputs from the gpio_controller after debouncing
    signal pir1_detect    : std_logic;                        -- Debounced PIR1 output
    signal pir2_detect    : std_logic;                        -- Debounced PIR2 output
    signal button_pressed : std_logic_vector(3 downto 0);    -- Debounced button states (active-high)
    signal button_event   : std_logic;                        -- One-cycle pulse on any button press

    -- HPS software control registers (set by HPS writes; default all off)
    signal sw_led_red    : std_logic := '0';   -- HPS-controlled red    LED state
    signal sw_led_green  : std_logic := '0';   -- HPS-controlled green  LED state
    signal sw_led_yellow : std_logic := '0';   -- HPS-controlled yellow LED state
    signal sw_buzzer     : std_logic := '0';   -- HPS-controlled buzzer state

    -- Register address constants (3-bit word address)
    constant REG_PIR_STATUS    : std_logic_vector(2 downto 0) := "000";  -- Addr 0x00: debounced PIR states
    constant REG_BUTTON_STATUS : std_logic_vector(2 downto 0) := "001";  -- Addr 0x04: button states + event flag
    constant REG_LED_CONTROL   : std_logic_vector(2 downto 0) := "010";  -- Addr 0x08: R/W LED control bits
    constant REG_BUZZER_CTRL   : std_logic_vector(2 downto 0) := "011";  -- Addr 0x0C: R/W buzzer control bit

begin

    -- Instantiate the GPIO controller with debouncing and edge detection
    gpio_inst: gpio_controller
        generic map (DEBOUNCE_TIME => 2_500_000)   -- 50 ms debounce @ 50 MHz prevents PIR/button glitches
        port map (
            clk             => clk,         -- System clock
            reset           => reset,       -- System reset
            pir1_in         => pir1_in,     -- Raw PIR1 input from board pin
            pir2_in         => pir2_in,     -- Raw PIR2 input from board pin
            button_in       => button_in,   -- Raw button inputs (active-low)
            pir1_detect     => pir1_detect,     -- Debounced PIR1 (readable via REG_PIR_STATUS)
            pir2_detect     => pir2_detect,     -- Debounced PIR2 (readable via REG_PIR_STATUS)
            button_pressed  => button_pressed,  -- Debounced button states (readable via REG_BUTTON_STATUS)
            button_event    => button_event,    -- One-cycle press event pulse
            led_red         => led_red,         -- Physical red LED pin driven from combined control
            led_green       => led_green,       -- Physical green LED pin
            led_yellow      => led_yellow,      -- Physical yellow LED pin
            buzzer          => buzzer,          -- Physical buzzer pin
            -- OR: alarm logic can activate outputs even when HPS hasn't written them
            -- This guarantees autonomous operation: hardware alarm fires even if Linux is sleeping
            led_red_ctrl    => sw_led_red    or alarm_led_red,     -- HPS OR alarm drives red LED
            led_green_ctrl  => sw_led_green  or alarm_led_green,   -- HPS OR alarm drives green LED
            led_yellow_ctrl => sw_led_yellow or alarm_led_yellow,  -- HPS OR alarm drives yellow LED
            buzzer_ctrl     => sw_buzzer     or alarm_buzzer       -- HPS OR alarm drives buzzer
        );

    waitrequest <= '0';   -- Always ready; no wait states inserted

    -- Avalon MM register process
    process(clk, reset)
    begin
        if reset = '1' then
            readdata      <= (others => '0');   -- Clear read-data register
            sw_led_red    <= '0';               -- Red    LED off after reset
            sw_led_green  <= '0';               -- Green  LED off after reset
            sw_led_yellow <= '0';               -- Yellow LED off after reset
            sw_buzzer     <= '0';               -- Buzzer off after reset

        elsif rising_edge(clk) then
            -- Write path: HPS can set LED and buzzer states at any time
            if write = '1' then
                case address is
                    when REG_LED_CONTROL =>
                        sw_led_red    <= writedata(0);   -- Bit 0: red    LED software control
                        sw_led_green  <= writedata(1);   -- Bit 1: green  LED software control
                        sw_led_yellow <= writedata(2);   -- Bit 2: yellow LED software control
                    when REG_BUZZER_CTRL =>
                        sw_buzzer <= writedata(0);       -- Bit 0: buzzer software control
                    when others => null;                  -- REG_PIR_STATUS and REG_BUTTON_STATUS are read-only
                end case;
            end if;

            -- Read path: HPS polls sensors and current output states
            if read = '1' then
                case address is
                    when REG_PIR_STATUS =>
                        -- [1]=pir2_detect [0]=pir1_detect; upper bits zero
                        readdata <= (31 downto 2 => '0') & pir2_detect & pir1_detect;
                    when REG_BUTTON_STATUS =>
                        -- [7]=button_event (one-cycle pulse), [3:0]=debounced button states
                        readdata <= (31 downto 8 => '0') & button_event & "000" & button_pressed;
                    when REG_LED_CONTROL =>
                        -- Return the current software-written LED values (NOT the combined OR with alarm)
                        readdata <= (31 downto 3 => '0') & sw_led_yellow & sw_led_green & sw_led_red;
                    when REG_BUZZER_CTRL =>
                        readdata <= (31 downto 1 => '0') & sw_buzzer;   -- Return software buzzer state
                    when others =>
                        readdata <= (others => '0');   -- Unmapped address returns zero
                end case;
            end if;
        end if;
    end process;

end Behavioral;
