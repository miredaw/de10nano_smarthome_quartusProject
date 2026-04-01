----------------------------------------------------------------------------------
-- GPIO Controller for Digital I/O
-- Inputs: 2x PIR Motion Sensors, 4x Buttons
-- Outputs: RGB LEDs (Red, Green, Yellow), Buzzer
----------------------------------------------------------------------------------

library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned/signed arithmetic

entity gpio_controller is
    Generic (
        DEBOUNCE_TIME : integer := 2_500_000  -- Debounce window = 50 ms @ 50 MHz (prevents glitch latching)
    );
    Port (
        clk             : in  std_logic;   -- 50 MHz system clock
        reset           : in  std_logic;   -- Active-high synchronous reset

        -- Raw input sensors (connected to JP1 GPIO header pins)
        pir1_in         : in  std_logic;                        -- PIR sensor 1 raw output (active-high motion)
        pir2_in         : in  std_logic;                        -- PIR sensor 2 raw output (active-high motion)
        button_in       : in  std_logic_vector(3 downto 0);     -- 4 push-buttons (active-low, to be inverted)

        -- Debounced and registered outputs
        pir1_detect     : out std_logic;                        -- Stable PIR1 state after debounce
        pir2_detect     : out std_logic;                        -- Stable PIR2 state after debounce
        button_pressed  : out std_logic_vector(3 downto 0);     -- Inverted stable button states (active-high)
        button_event    : out std_logic;                        -- One-cycle pulse when any button is newly pressed

        -- Physical hardware output pins (wired to LEDs and buzzer via top-level)
        led_red         : out std_logic;   -- Red    LED drive output
        led_green       : out std_logic;   -- Green  LED drive output
        led_yellow      : out std_logic;   -- Yellow LED drive output
        buzzer          : out std_logic;   -- Buzzer drive output

        -- Combined (HPS OR alarm) control inputs from gpio_avalon_wrapper
        led_red_ctrl    : in  std_logic;   -- '1' to illuminate red    LED
        led_green_ctrl  : in  std_logic;   -- '1' to illuminate green  LED
        led_yellow_ctrl : in  std_logic;   -- '1' to illuminate yellow LED
        buzzer_ctrl     : in  std_logic    -- '1' to activate buzzer
    );
end gpio_controller;

architecture Behavioral of gpio_controller is

    -- 3-stage synchroniser shift registers for PIR inputs (prevents metastability)
    -- Three flip-flops: [0]=newest sample, [2]=oldest (synchronised) sample
    signal pir1_sync : std_logic_vector(2 downto 0) := (others => '0');   -- PIR1 synchroniser chain
    signal pir2_sync : std_logic_vector(2 downto 0) := (others => '0');   -- PIR2 synchroniser chain

    -- Debounce counters for PIR sensors: count cycles until input is stable for DEBOUNCE_TIME
    signal pir1_counter : integer range 0 to DEBOUNCE_TIME := 0;   -- Counts consecutive identical PIR1 samples
    signal pir2_counter : integer range 0 to DEBOUNCE_TIME := 0;   -- Counts consecutive identical PIR2 samples

    -- Stable (debounced) values for PIR sensors
    signal pir1_stable : std_logic := '0';   -- Last confirmed stable state of PIR1
    signal pir2_stable : std_logic := '0';   -- Last confirmed stable state of PIR2

    -- 3-stage synchroniser arrays for each button (active-low inputs, initialised high = not pressed)
    type button_sync_array is array (0 to 3) of std_logic_vector(2 downto 0);
    signal button_sync : button_sync_array := (others => (others => '1'));  -- Init high (active low = unpressed)

    -- Per-button debounce counters
    type button_counter_array is array (0 to 3) of integer range 0 to DEBOUNCE_TIME;
    signal button_counter : button_counter_array := (others => 0);   -- Each entry counts stable cycles for one button

    signal button_stable : std_logic_vector(3 downto 0) := (others => '1');  -- Stable button state (active-low, '1'=not pressed)
    signal button_prev   : std_logic_vector(3 downto 0) := (others => '1');  -- Previous stable state for edge detection

begin

    -- PIR1 Debouncing process
    process(clk, reset)
    begin
        if reset = '1' then
            pir1_sync    <= (others => '0');   -- Clear synchroniser chain
            pir1_counter <= 0;                 -- Reset debounce counter
            pir1_stable  <= '0';               -- Assume no motion at reset
        elsif rising_edge(clk) then
            -- Shift new PIR1 sample into the 3-stage synchroniser (prevents metastability)
            pir1_sync <= pir1_sync(1 downto 0) & pir1_in;   -- [2]=stable, [1]=mid, [0]=newest sample

            -- Debounce logic: only update stable output when input has been constant for DEBOUNCE_TIME cycles
            if pir1_sync(2) = pir1_stable then
                -- Synchronised value matches current stable output: no change pending, reset counter
                pir1_counter <= 0;
            else
                -- Synchronised value differs from stable output: count stable cycles toward threshold
                if pir1_counter < DEBOUNCE_TIME then
                    pir1_counter <= pir1_counter + 1;   -- Increment; keep counting until threshold reached
                else
                    -- Counter saturated: input has been stable long enough; latch new value
                    pir1_stable  <= pir1_sync(2);   -- Update stable output to the new confirmed state
                    pir1_counter <= 0;              -- Reset counter for next transition
                end if;
            end if;
        end if;
    end process;

    pir1_detect <= pir1_stable;   -- Drive debounced PIR1 output to Avalon wrapper and alarm_logic

    -- PIR2 Debouncing process (identical structure to PIR1)
    process(clk, reset)
    begin
        if reset = '1' then
            pir2_sync    <= (others => '0');   -- Clear synchroniser chain
            pir2_counter <= 0;                 -- Reset debounce counter
            pir2_stable  <= '0';               -- Assume no motion at reset
        elsif rising_edge(clk) then
            -- Shift new PIR2 sample through 3-stage synchroniser
            pir2_sync <= pir2_sync(1 downto 0) & pir2_in;

            if pir2_sync(2) = pir2_stable then
                pir2_counter <= 0;              -- No transition in progress; reset counter
            else
                if pir2_counter < DEBOUNCE_TIME then
                    pir2_counter <= pir2_counter + 1;   -- Continue counting toward debounce threshold
                else
                    pir2_stable  <= pir2_sync(2);   -- Latch new stable value
                    pir2_counter <= 0;
                end if;
            end if;
        end if;
    end process;

    pir2_detect <= pir2_stable;   -- Drive debounced PIR2 output to Avalon wrapper and alarm_logic

    -- Button Debouncing: generate one process per button using a for-generate loop
    gen_button_debounce: for i in 0 to 3 generate
        process(clk, reset)
        begin
            if reset = '1' then
                button_sync(i)    <= (others => '1');   -- Init high (active-low buttons are unpressed)
                button_counter(i) <= 0;                  -- Reset debounce counter for this button
                button_stable(i)  <= '1';                -- Buttons unpressed at reset
            elsif rising_edge(clk) then
                -- Shift button i through its own 3-stage synchroniser (prevents metastability)
                button_sync(i) <= button_sync(i)(1 downto 0) & button_in(i);

                -- Debounce: only update stable when input is consistently different for DEBOUNCE_TIME
                if button_sync(i)(2) = button_stable(i) then
                    button_counter(i) <= 0;   -- Input matches stable: no change, reset counter
                else
                    if button_counter(i) < DEBOUNCE_TIME then
                        button_counter(i) <= button_counter(i) + 1;   -- Count stable differing cycles
                    else
                        button_stable(i)  <= button_sync(i)(2);   -- Latch new confirmed button state
                        button_counter(i) <= 0;
                    end if;
                end if;
            end if;
        end process;
    end generate;

    -- Invert button_stable: physical buttons are active-low; expose as active-high to Avalon wrapper
    button_pressed <= not button_stable;  -- '1' in output means button is currently pressed

    -- Button edge detection: generate a one-cycle pulse when any button transitions pressed
    process(clk, reset)
    begin
        if reset = '1' then
            button_prev  <= (others => '1');   -- Previous state = all released at reset
            button_event <= '0';               -- No event at reset
        elsif rising_edge(clk) then
            button_prev <= button_stable;   -- Save current stable state for next cycle comparison

            -- Detect falling edge on any button (active-low: falling = button just pressed)
            if (button_stable(0) = '0' and button_prev(0) = '1') or
               (button_stable(1) = '0' and button_prev(1) = '1') or
               (button_stable(2) = '0' and button_prev(2) = '1') or
               (button_stable(3) = '0' and button_prev(3) = '1') then
                button_event <= '1';   -- Assert event pulse for exactly one clock cycle
            else
                button_event <= '0';   -- No new press transition this cycle
            end if;
        end if;
    end process;

    -- Output control: directly connect combined control signals to physical pins
    -- The OR of HPS software and alarm engine was computed in gpio_avalon_wrapper
    led_red    <= led_red_ctrl;     -- Drive red    LED: '1' turns it on
    led_green  <= led_green_ctrl;   -- Drive green  LED: '1' turns it on
    led_yellow <= led_yellow_ctrl;  -- Drive yellow LED: '1' turns it on
    buzzer     <= buzzer_ctrl;      -- Drive buzzer:     '1' activates it

end Behavioral;
