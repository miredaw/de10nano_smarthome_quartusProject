----------------------------------------------------------------------------------
-- BME280 Sensor Controller
-- Reads Temperature, Pressure, Humidity from BME280 via I2C
-- Address: 0x76 (SDO tied low) or 0x77 (SDO tied high)
----------------------------------------------------------------------------------

library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned() for arithmetic on std_logic_vector

entity bme280_controller is
    Generic (
        BME280_ADDR : std_logic_vector(6 downto 0) := "1110110"  -- I2C slave address 0x76 (SDO tied to GND)
    );
    Port (
        clk         : in    std_logic;   -- 50 MHz system clock
        reset       : in    std_logic;   -- Active-high synchronous reset

        enable      : in    std_logic;   -- '1' to run controller; '0' to halt after current cycle

        -- Sensor outputs (raw ADC values, held valid between readings)
        temp_raw    : out   std_logic_vector(19 downto 0);   -- 20-bit raw temperature ADC: msb[7:0] | lsb[7:0] | xlsb[7:4]
        press_raw   : out   std_logic_vector(19 downto 0);   -- 20-bit raw pressure ADC (same packing)
        humid_raw   : out   std_logic_vector(15 downto 0);   -- 16-bit raw humidity ADC: msb[7:0] | lsb[7:0]
        data_valid  : out   std_logic;   -- FIX: held high once first reading done (latched, not a pulse)
        error       : out   std_logic;   -- '1' when last I2C transaction returned a NACK / bus error

        -- I2C interface (open-drain; SCL inout for clock-stretch support)
        sda         : inout std_logic;   -- I2C data line: open-drain, pulled up externally (Waveshare 4.7k)
        scl         : inout std_logic    -- FIX: was 'out'; inout needed so sensor can stretch the clock
    );
end bme280_controller;

architecture Behavioral of bme280_controller is

    -- Declare the I2C master as a component to be instantiated
    component i2c_master is
        Generic (
            INPUT_CLK_FREQ  : integer := 50_000_000;   -- Master clock frequency
            I2C_CLK_FREQ    : integer := 100_000       -- Desired I2C SCL frequency
        );
        Port (
            clk         : in    std_logic;
            reset       : in    std_logic;
            start       : in    std_logic;              -- Assert to begin a transaction
            rw          : in    std_logic;              -- '0'=write, '1'=read
            slave_addr  : in    std_logic_vector(6 downto 0);
            reg_addr    : in    std_logic_vector(7 downto 0);
            data_in     : in    std_logic_vector(7 downto 0);
            data_out    : out   std_logic_vector(7 downto 0);
            busy        : out   std_logic;              -- '1' while transaction in progress
            done        : out   std_logic;              -- One-cycle pulse on transaction completion
            error       : out   std_logic;              -- '1' on NACK or bus error
            sda         : inout std_logic;
            scl         : inout std_logic   -- FIX: inout
        );
    end component;

    -- BME280 register addresses (from BME280 datasheet section 5.3)
    constant REG_CTRL_HUM   : std_logic_vector(7 downto 0) := x"F2";  -- Humidity oversampling control register
    constant REG_CTRL_MEAS  : std_logic_vector(7 downto 0) := x"F4";  -- Temp/pressure oversampling and mode register
    constant REG_PRESS_MSB  : std_logic_vector(7 downto 0) := x"F7";  -- Pressure data MSB (3-byte burst: F7, F8, F9)
    constant REG_TEMP_MSB   : std_logic_vector(7 downto 0) := x"FA";  -- Temperature data MSB (3-byte burst: FA, FB, FC)
    constant REG_HUM_MSB    : std_logic_vector(7 downto 0) := x"FD";  -- Humidity data MSB (2-byte burst: FD, FE)

    -- FSM states: IDLE -> init -> configure humidity -> trigger forced mode ->
    --             wait for measurement -> read 8 bytes -> assemble -> delay -> repeat
    type state_type is (
        IDLE,               -- Waiting for enable='1' before starting
        INIT_WAIT,          -- 1-second power-on delay before first I2C transaction
        WRITE_HUM_CFG,      -- Write 0x01 to ctrl_hum: humidity oversampling x1
        WAIT_HUM_CFG,       -- Wait for I2C write to complete
        TRIGGER_MEASURE,    -- Write 0x25 to ctrl_meas: temp/press x1, forced mode
        WAIT_TRIGGER,       -- Wait for I2C write to complete
        WAIT_CONVERSION,    -- Wait 10 ms for BME280 measurement to finish
        READ_PRESS_MSB,  WAIT_PRESS_MSB,      -- Read pressure byte 0xF7
        READ_PRESS_LSB,  WAIT_PRESS_LSB,      -- Read pressure byte 0xF8
        READ_PRESS_XLSB, WAIT_PRESS_XLSB,    -- Read pressure byte 0xF9
        READ_TEMP_MSB,   WAIT_TEMP_MSB,       -- Read temperature byte 0xFA
        READ_TEMP_LSB,   WAIT_TEMP_LSB,       -- Read temperature byte 0xFB
        READ_TEMP_XLSB,  WAIT_TEMP_XLSB,     -- Read temperature byte 0xFC
        READ_HUM_MSB,    WAIT_HUM_MSB,        -- Read humidity byte 0xFD
        READ_HUM_LSB,    WAIT_HUM_LSB,        -- Read humidity byte 0xFE
        DATA_READY,             -- Assemble 20-bit raw values, latch data_valid
        INTER_READING_DELAY,    -- 500 ms pause between forced-mode measurements (~2 Hz update rate)
        ERROR_STATE             -- I2C error: auto-retry after 5 s timeout
    );
    signal state : state_type := IDLE;   -- Current FSM state

    -- I2C master control signals
    signal i2c_start    : std_logic := '0';                        -- Start pulse (held until i2c_busy rises)
    signal i2c_rw       : std_logic := '0';                        -- '0'=write, '1'=read
    signal i2c_reg_addr : std_logic_vector(7 downto 0) := (others => '0');  -- BME280 register to access
    signal i2c_data_in  : std_logic_vector(7 downto 0) := (others => '0');  -- Byte to write (write transactions)
    signal i2c_data_out : std_logic_vector(7 downto 0);            -- Byte read back from sensor
    signal i2c_busy     : std_logic;                               -- High while i2c_master is transferring
    signal i2c_done     : std_logic;                               -- One-cycle pulse when transaction finishes
    signal i2c_error    : std_logic;                               -- '1' if NACK received

    -- Byte-level storage for the 8 raw measurement registers
    signal temp_msb,  temp_lsb,  temp_xlsb   : std_logic_vector(7 downto 0);  -- Temperature bytes
    signal press_msb, press_lsb, press_xlsb  : std_logic_vector(7 downto 0);  -- Pressure bytes
    signal hum_msb,   hum_lsb                : std_logic_vector(7 downto 0);  -- Humidity bytes

    -- FIX: data_valid latched internally so it stays high between reads
    -- Driven to the output port via the concurrent assignment below
    signal data_valid_i : std_logic := '0';

    -- Timing counter (reused for all waits).
    -- Range extended to 250 000 000 (5 s @ 50 MHz) to support the ERROR_STATE
    -- auto-retry timeout without a separate counter.
    signal wait_counter : integer range 0 to 250_000_000 := 0;

    -- FIX: tracks first cycle inside ERROR_STATE so we can arm wait_counter
    -- exactly once per error episode without touching all 9 entry sites.
    signal in_error_state : std_logic := '0';   -- '0'=just entered ERROR_STATE this cycle, '1'=already armed

begin

    -- Instantiate i2c_master at a safe 10 kHz SCL
    -- Reduced from 100 kHz because FPGA GPIO pull-ups (~25 kΩ) with ~100 pF PCB trace
    -- give RC time constant tau=2.5 µs; 5-tau=12.5 µs needed for clean rising edges.
    -- At 10 kHz, SCL high time = 50 µs >> 12.5 µs, so the bus reliably rises.
    i2c_inst : i2c_master
        generic map (
            INPUT_CLK_FREQ => 50_000_000,   -- 50 MHz FPGA clock
            I2C_CLK_FREQ   => 10_000        -- 10 kHz I2C: safe with FPGA GPIO weak pull-ups
        )
        port map (
            clk        => clk,           -- System clock
            reset      => reset,         -- System reset
            start      => i2c_start,     -- Handshake: held high until busy rises
            rw         => i2c_rw,        -- Transaction direction
            slave_addr => BME280_ADDR,   -- Always target BME280 at 0x76
            reg_addr   => i2c_reg_addr,  -- Register address to read/write
            data_in    => i2c_data_in,   -- Byte to write (write transactions)
            data_out   => i2c_data_out,  -- Byte received (read transactions)
            busy       => i2c_busy,      -- Monitored by FSM for start handshake
            done       => i2c_done,      -- Monitored by WAIT states to detect completion
            error      => i2c_error,     -- Triggers transition to ERROR_STATE
            sda        => sda,           -- Physical I2C SDA pin
            scl        => scl            -- Physical I2C SCL pin (inout for clock stretch)
        );

    -- FIX: drive output from internal latch so it stays '1' between sensor readings
    data_valid <= data_valid_i;

    -- Main FSM: sequences through BME280 initialisation and repeated forced-mode reads
    process(clk, reset)
    begin
        if reset = '1' then
            state          <= IDLE;
            data_valid_i   <= '0';      -- Invalidate data on reset
            error          <= '0';      -- Clear error flag
            i2c_start      <= '0';      -- No pending I2C start
            wait_counter   <= 0;        -- Clear timing counter
            in_error_state <= '0';      -- Not in error state

        elsif rising_edge(clk) then
            -- FIX v3: i2c_start default stays '1' while in a READ_*/WRITE_* state
            -- until i2c_busy rises (i2c_master latched the request).
            -- The explicit assignment below keeps it '0' in all other states.
            i2c_start <= '0';  -- Default: de-assert start; overridden in issue states below

            case state is

                -- IDLE: wait for enable signal from Avalon wrapper
                when IDLE =>
                    error        <= '0';   -- Clear any previous error
                    data_valid_i <= '0';   -- Data not yet valid after (re-)enable
                    if enable = '1' then
                        state        <= INIT_WAIT;
                        wait_counter <= 50_000_000;  -- Wait 1 second after power-on before first I2C access
                    end if;

                -- INIT_WAIT: count down 1 s startup delay to allow BME280 to complete POR
                when INIT_WAIT =>
                    if wait_counter > 0 then
                        wait_counter <= wait_counter - 1;  -- Decrement each cycle
                    else
                        state <= WRITE_HUM_CFG;  -- Delay elapsed; begin configuration
                    end if;

                -- WRITE_HUM_CFG: write 0x01 to ctrl_hum register
                -- osrs_h = 001b -> humidity oversampling x1 (enables humidity measurement)
                -- FIX: hold i2c_start='1' until i2c_busy rises, then move to WAIT state.
                when WRITE_HUM_CFG =>
                    i2c_rw       <= '0';          -- Write transaction
                    i2c_reg_addr <= REG_CTRL_HUM; -- Target humidity control register
                    i2c_data_in  <= x"01";         -- osrs_h = 001 (oversampling x1)
                    i2c_start    <= '1';           -- Assert start; hold until i2c_busy rises
                    if i2c_busy = '1' then
                        i2c_start <= '0';          -- i2c_master accepted the request; de-assert
                        state     <= WAIT_HUM_CFG; -- Wait for completion
                    end if;

                -- WAIT_HUM_CFG: block until i2c_master signals done (or error)
                when WAIT_HUM_CFG =>
                    if i2c_done = '1' then
                        if i2c_error = '1' then
                            state <= ERROR_STATE;      -- NACK received: go to error handler
                        else
                            state <= TRIGGER_MEASURE;  -- Configuration written: trigger measurement
                        end if;
                    end if;

                -- TRIGGER_MEASURE: write 0x25 to ctrl_meas
                -- osrs_t=001 (temp x1), osrs_p=001 (press x1), mode=01 (forced mode)
                -- NOTE: BME280 forced mode is a one-shot; must be re-triggered each measurement cycle
                -- FIX: hold i2c_start until i2c_busy
                when TRIGGER_MEASURE =>
                    i2c_rw       <= '0';             -- Write transaction
                    i2c_reg_addr <= REG_CTRL_MEAS;   -- Target measurement control register
                    i2c_data_in  <= x"25";            -- 0b00100101: osrs_t=001, osrs_p=001, mode=01 (forced)
                    i2c_start    <= '1';              -- Assert start
                    if i2c_busy = '1' then
                        i2c_start <= '0';             -- i2c_master accepted; de-assert
                        state     <= WAIT_TRIGGER;    -- Wait for completion
                    end if;

                -- WAIT_TRIGGER: wait for ctrl_meas write to complete
                when WAIT_TRIGGER =>
                    if i2c_done = '1' then
                        if i2c_error = '1' then
                            state        <= ERROR_STATE;
                        else
                            -- BME280 forced-mode measurement takes ~8 ms (typ)
                            -- Wait 10 ms (500 000 cycles @ 50 MHz) to be safe before reading results
                            wait_counter <= 500_000;
                            state        <= WAIT_CONVERSION;
                        end if;
                    end if;

                -- WAIT_CONVERSION: 10 ms delay for BME280 to complete measurement
                when WAIT_CONVERSION =>
                    if wait_counter > 0 then
                        wait_counter <= wait_counter - 1;   -- Count down 10 ms
                    else
                        state <= READ_PRESS_MSB;  -- Measurement done; start reading results
                    end if;

                -- ---- Pressure reading (3 bytes at addresses 0xF7, 0xF8, 0xF9) ----
                -- FIX: all READ_* states hold i2c_start until i2c_busy to prevent missing a single-cycle start
                when READ_PRESS_MSB =>
                    i2c_rw <= '1';                  -- Read transaction
                    i2c_reg_addr <= REG_PRESS_MSB;  -- Address 0xF7 (pressure MSB)
                    i2c_start <= '1';               -- Assert start
                    if i2c_busy = '1' then i2c_start <= '0'; state <= WAIT_PRESS_MSB; end if;
                when WAIT_PRESS_MSB =>
                    if i2c_done = '1' then
                        if i2c_error = '1' then state <= ERROR_STATE;
                        else press_msb <= i2c_data_out; state <= READ_PRESS_LSB; end if;  -- Save byte, read next
                    end if;

                when READ_PRESS_LSB =>
                    i2c_rw <= '1';
                    -- Address 0xF8: MSB+1
                    i2c_reg_addr <= std_logic_vector(unsigned(REG_PRESS_MSB) + 1);
                    i2c_start <= '1';
                    if i2c_busy = '1' then i2c_start <= '0'; state <= WAIT_PRESS_LSB; end if;
                when WAIT_PRESS_LSB =>
                    if i2c_done = '1' then
                        if i2c_error = '1' then state <= ERROR_STATE;
                        else press_lsb <= i2c_data_out; state <= READ_PRESS_XLSB; end if;
                    end if;

                when READ_PRESS_XLSB =>
                    i2c_rw <= '1';
                    -- Address 0xF9: MSB+2 (XLSB contains bits [7:4] only; [3:0] are padding zeros)
                    i2c_reg_addr <= std_logic_vector(unsigned(REG_PRESS_MSB) + 2);
                    i2c_start <= '1';
                    if i2c_busy = '1' then i2c_start <= '0'; state <= WAIT_PRESS_XLSB; end if;
                when WAIT_PRESS_XLSB =>
                    if i2c_done = '1' then
                        if i2c_error = '1' then state <= ERROR_STATE;
                        else press_xlsb <= i2c_data_out; state <= READ_TEMP_MSB; end if;
                    end if;

                -- ---- Temperature reading (3 bytes at addresses 0xFA, 0xFB, 0xFC) ----
                when READ_TEMP_MSB =>
                    i2c_rw <= '1'; i2c_reg_addr <= REG_TEMP_MSB; i2c_start <= '1';  -- Address 0xFA
                    if i2c_busy = '1' then i2c_start <= '0'; state <= WAIT_TEMP_MSB; end if;
                when WAIT_TEMP_MSB =>
                    if i2c_done = '1' then
                        if i2c_error = '1' then state <= ERROR_STATE;
                        else temp_msb <= i2c_data_out; state <= READ_TEMP_LSB; end if;
                    end if;

                when READ_TEMP_LSB =>
                    i2c_rw <= '1';
                    -- Address 0xFB: temp MSB+1
                    i2c_reg_addr <= std_logic_vector(unsigned(REG_TEMP_MSB) + 1);
                    i2c_start <= '1';
                    if i2c_busy = '1' then i2c_start <= '0'; state <= WAIT_TEMP_LSB; end if;
                when WAIT_TEMP_LSB =>
                    if i2c_done = '1' then
                        if i2c_error = '1' then state <= ERROR_STATE;
                        else temp_lsb <= i2c_data_out; state <= READ_TEMP_XLSB; end if;
                    end if;

                when READ_TEMP_XLSB =>
                    i2c_rw <= '1';
                    -- Address 0xFC: temp MSB+2 (bits [7:4] only; [3:0] are padding zeros)
                    i2c_reg_addr <= std_logic_vector(unsigned(REG_TEMP_MSB) + 2);
                    i2c_start <= '1';
                    if i2c_busy = '1' then i2c_start <= '0'; state <= WAIT_TEMP_XLSB; end if;
                when WAIT_TEMP_XLSB =>
                    if i2c_done = '1' then
                        if i2c_error = '1' then state <= ERROR_STATE;
                        else temp_xlsb <= i2c_data_out; state <= READ_HUM_MSB; end if;
                    end if;

                -- ---- Humidity reading (2 bytes at addresses 0xFD, 0xFE) ----
                when READ_HUM_MSB =>
                    i2c_rw <= '1'; i2c_reg_addr <= REG_HUM_MSB; i2c_start <= '1';  -- Address 0xFD
                    if i2c_busy = '1' then i2c_start <= '0'; state <= WAIT_HUM_MSB; end if;
                when WAIT_HUM_MSB =>
                    if i2c_done = '1' then
                        if i2c_error = '1' then state <= ERROR_STATE;
                        else hum_msb <= i2c_data_out; state <= READ_HUM_LSB; end if;
                    end if;

                when READ_HUM_LSB =>
                    i2c_rw <= '1';
                    -- Address 0xFE: humidity MSB+1
                    i2c_reg_addr <= std_logic_vector(unsigned(REG_HUM_MSB) + 1);
                    i2c_start <= '1';
                    if i2c_busy = '1' then i2c_start <= '0'; state <= WAIT_HUM_LSB; end if;
                when WAIT_HUM_LSB =>
                    if i2c_done = '1' then
                        if i2c_error = '1' then state <= ERROR_STATE;
                        else hum_lsb <= i2c_data_out; state <= DATA_READY; end if;
                    end if;

                -- DATA_READY: assemble 20-bit raw values from the three bytes per measurement
                -- Packing: msb[7:0] | lsb[7:0] | xlsb[7:4] -> 20-bit ADC value (BME280 datasheet format)
                when DATA_READY =>
                    -- Combine temperature bytes: msb is bits[19:12], lsb is bits[11:4], xlsb[7:4]=bits[3:0]
                    temp_raw  <= temp_msb  & temp_lsb  & temp_xlsb(7 downto 4);
                    -- Combine pressure bytes same way
                    press_raw <= press_msb & press_lsb & press_xlsb(7 downto 4);
                    -- Humidity is 16-bit: msb[7:0] | lsb[7:0]
                    humid_raw <= hum_msb   & hum_lsb;
                    -- FIX: latch data_valid HIGH so HPS can read any time between scan cycles
                    -- (it was previously a pulse; now stays '1' permanently once first read completes)
                    data_valid_i <= '1';
                    -- 500 ms inter-reading delay then re-trigger forced mode for continuous ~2 Hz readings
                    wait_counter <= 25_000_000;    -- 25 M cycles = 500 ms @ 50 MHz
                    state        <= INTER_READING_DELAY;

                -- INTER_READING_DELAY: 500 ms pause between consecutive forced-mode measurements
                when INTER_READING_DELAY =>
                    if wait_counter > 0 then
                        wait_counter <= wait_counter - 1;   -- Count down inter-reading gap
                    else
                        if enable = '1' then
                            state <= TRIGGER_MEASURE;  -- Re-trigger next forced-mode measurement
                        else
                            state <= IDLE;             -- Enable dropped: stop and wait
                        end if;
                    end if;

                -- ERROR_STATE: I2C bus error recovery
                -- FIX: auto-recovery so the controller is not permanently
                -- stuck waiting for an external enable=0 pulse.
                -- The HPS supervisor writes enable=0 only once (calibration
                -- attempt); without this timeout BME280 valid stays '0' for
                -- the entire system lifetime after a boot-time I2C failure.
                --
                -- in_error_state detects the first cycle here so wait_counter
                -- is armed exactly once per error episode without touching
                -- any of the 9 state <= ERROR_STATE transition sites.
                when ERROR_STATE =>
                    error <= '1';   -- Expose error flag to Avalon wrapper (HPS can read REG_STATUS)
                    if in_error_state = '0' then
                        -- First cycle in ERROR_STATE: arm the 5-second retry countdown
                        wait_counter   <= 250_000_000;   -- 250 M cycles = 5 s @ 50 MHz
                        in_error_state <= '1';           -- Mark as armed so we don't re-arm next cycle
                    elsif enable = '0' then
                        -- Immediate recovery path: HPS explicitly disabled the sensor
                        wait_counter   <= 0;             -- Clear countdown
                        in_error_state <= '0';           -- Reset arm flag
                        state          <= IDLE;          -- Go to IDLE; will restart when enable='1' again
                    elsif wait_counter > 0 then
                        wait_counter <= wait_counter - 1;  -- Count down 5-second timeout
                    else
                        -- Timeout expired: automatically retry without HPS intervention
                        error          <= '0';            -- Clear error flag for retry
                        in_error_state <= '0';            -- Reset arm flag
                        wait_counter   <= 50_000_000;     -- 1 s startup delay before re-init
                        state          <= INIT_WAIT;      -- Restart from INIT_WAIT (fresh init)
                    end if;

            end case;
        end if;
    end process;

end Behavioral;
