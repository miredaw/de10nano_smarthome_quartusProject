----------------------------------------------------------------------------------
-- I2C Master Controller for BME280 Sensor
-- Supports: Temperature, Pressure, Humidity reading
-- Clock: 50MHz input, generates ~100kHz I2C SCL
--
-- FIX v2:
--  1. SCL changed from 'out' to 'inout' and driven open-drain ('0' or 'Z')
--     so that the BME280 can perform clock stretching without bus contention.
--  2. 4-phase counter retained for correct SDA setup/hold timing.
--     Phase 0: SCL low  - drive SDA
--     Phase 1: SCL high - slave samples SDA (rising edge)
--     Phase 2: SCL high - hold
--     Phase 3: SCL low  - falling edge, advance state
--  3. ACK states sample SDA on phase 1 (SCL high) for correct timing.
--
-- FIX v3:
--  4. IDLE state moved OUTSIDE the phase_tick gate so that a single-cycle
--     start pulse from bme280_controller is never missed.  All other states
--     remain gated by phase_tick for correct I2C timing.
--
-- NOTE: Top-level must declare BME280_SCL as 'inout' and the
--       bme280_avalon_wrapper / bme280_controller must also use 'inout'.
----------------------------------------------------------------------------------

library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned/signed arithmetic

entity i2c_master is
    Generic (
        INPUT_CLK_FREQ  : integer := 50_000_000;  -- Input clock frequency (50 MHz on DE10-Nano)
        I2C_CLK_FREQ    : integer := 100_000      -- Desired I2C SCL frequency (default 100 kHz standard mode)
    );
    Port (
        clk             : in    std_logic;   -- System clock (INPUT_CLK_FREQ Hz)
        reset           : in    std_logic;   -- Active-high synchronous reset

        -- Control signals (driven by bme280_controller FSM)
        start           : in    std_logic;          -- Assert to launch a transaction; held until busy='1'
        rw              : in    std_logic;           -- '0' = write register, '1' = read register
        slave_addr      : in    std_logic_vector(6 downto 0);  -- 7-bit I2C slave address
        reg_addr        : in    std_logic_vector(7 downto 0);  -- 8-bit register address inside slave
        data_in         : in    std_logic_vector(7 downto 0);  -- Byte to write (used when rw='0')
        data_out        : out   std_logic_vector(7 downto 0);  -- Byte read from slave (valid after done='1')
        busy            : out   std_logic;   -- '1' from transaction start until STOP condition sent
        done            : out   std_logic;   -- One-cycle pulse when transaction finishes
        error           : out   std_logic;   -- '1' when NACK received (slave not responding)

        -- I2C bus (open-drain: drive '0' or release 'Z')
        sda             : inout std_logic;   -- I2C SDA: driven low or released to pull-up
        scl             : inout std_logic    -- FIX: changed from 'out' to 'inout' (needed for clock stretching)
    );
end i2c_master;

architecture Behavioral of i2c_master is

    -- Quarter-period divider:
    -- The I2C bit period is divided into 4 equal phases (0-3).
    -- Each phase_tick advances one phase; 4 ticks = 1 complete SCL period.
    -- QUARTER_DIV = number of system clock cycles per I2C quarter-period.
    constant QUARTER_DIV : integer := INPUT_CLK_FREQ / (I2C_CLK_FREQ * 4);
    -- e.g. for 50 MHz input and 10 kHz I2C: QUARTER_DIV = 50_000_000 / (10_000 * 4) = 1250 cycles

    signal clk_counter   : integer range 0 to QUARTER_DIV - 1 := 0;  -- Counts system clock cycles per quarter period
    signal phase_tick    : std_logic := '0';                           -- One-cycle pulse every QUARTER_DIV cycles
    signal phase         : integer range 0 to 3 := 0;                 -- Current quarter-phase within an SCL period (0..3)

    signal bit_counter   : integer range 0 to 7 := 0;  -- Counts which bit (7 downto 0) is being sent/received

    -- FSM state encoding for the I2C protocol sequence
    type state_type is (
        IDLE,           -- Waiting for start pulse; SCL and SDA held high (released)
        START_COND,     -- Generate START condition: SDA falls while SCL is high
        SEND_ADDR_W,    -- Send 8-bit slave address with R/W='0' (write direction)
        ACK_ADDR_W,     -- Receive ACK from slave after address (write direction)
        SEND_REG,       -- Send 8-bit register address byte
        ACK_REG,        -- Receive ACK from slave after register address
        RESTART_COND,   -- Generate REPEATED START (for read transactions)
        SEND_ADDR_R,    -- Send 8-bit slave address with R/W='1' (read direction)
        ACK_ADDR_R,     -- Receive ACK from slave after address (read direction)
        READ_DATA,      -- Receive 8 data bits from slave (SCL driven by master, SDA by slave)
        SEND_NACK,      -- Send NACK to slave after receiving last byte (signals end of read)
        STOP_COND,      -- Generate STOP condition: SDA rises while SCL is high
        WRITE_DATA,     -- Send 8 data bits to slave
        ACK_DATA        -- Receive ACK from slave after data write
    );
    signal state : state_type := IDLE;

    -- FIX: internal signals drive open-drain outputs
    -- Never assign SDA/SCL directly; use the concurrent assignments at the bottom
    signal sda_internal : std_logic := '1';                          -- Desired SDA value: '1'=release, '0'=pull low
    signal scl_internal : std_logic := '1';                          -- Desired SCL value: '1'=release, '0'=pull low
    signal data_shift   : std_logic_vector(7 downto 0) := (others => '0');  -- Shift register for TX and RX data
    signal addr_shift   : std_logic_vector(7 downto 0) := (others => '0');  -- Shift register for address byte
    signal ack_ok       : std_logic := '0';                          -- '1' when slave sent ACK (SDA='0' on phase 1)

begin

    ---------------------------------------------------------------------------
    -- Quarter-period clock divider
    -- Generates a one-cycle pulse (phase_tick) every QUARTER_DIV system cycles.
    -- The main FSM uses these ticks to advance state on correct I2C timing boundaries.
    ---------------------------------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            clk_counter <= 0;      -- Reset cycle counter
            phase_tick  <= '0';    -- No tick pending
        elsif rising_edge(clk) then
            phase_tick <= '0';     -- Default: no tick this cycle
            if clk_counter = QUARTER_DIV - 1 then
                clk_counter <= 0;       -- Wrap counter back to zero
                phase_tick  <= '1';     -- Assert tick: quarter period elapsed
            else
                clk_counter <= clk_counter + 1;   -- Increment counter
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- Main I2C FSM
    -- Implements the complete I2C write and read (with repeated start) sequences.
    -- Write sequence: START | addr+W | ACK | reg_addr | ACK | data | ACK | STOP
    -- Read  sequence: START | addr+W | ACK | reg_addr | ACK | RESTART | addr+R | ACK | data | NACK | STOP
    ---------------------------------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            state        <= IDLE;
            busy         <= '0';
            done         <= '0';
            error        <= '0';
            scl_internal <= '1';         -- Release SCL (pulled up externally)
            sda_internal <= '1';         -- Release SDA (pulled up externally)
            bit_counter  <= 0;
            phase        <= 0;
            data_shift   <= (others => '0');
            addr_shift   <= (others => '0');
            ack_ok       <= '0';

        elsif rising_edge(clk) then
            done <= '0';   -- Clear done pulse (only valid for one cycle)

            -- FIX v3: IDLE checked every cycle so a single-cycle start pulse
            -- from bme280_controller is never missed regardless of phase_tick.
            -- All other states are inside the phase_tick gate below.
            if state = IDLE then
                busy         <= '0';        -- Available for new transaction
                scl_internal <= '1';        -- Hold SCL high (idle)
                sda_internal <= '1';        -- Hold SDA high (idle)
                error        <= '0';        -- Clear error from previous transaction
                phase        <= 0;          -- Reset phase counter
                if start = '1' then
                    busy       <= '1';                   -- Claim busy immediately (handshake with caller)
                    addr_shift <= slave_addr & '0';      -- Load address byte with R/W='0' (write first)
                    data_shift <= reg_addr;              -- Load register address for SEND_REG phase
                    state      <= START_COND;            -- Begin START condition
                end if;
            end if;

            -- All remaining states are gated by phase_tick for correct I2C timing
            if phase_tick = '1' then

                case state is

                    when IDLE =>
                        null;  -- handled above, outside phase_tick gate

                    -- START condition: SDA falls while SCL is high
                    -- Phase 0: ensure SDA=1, SCL=1 (bus free)
                    -- Phase 1: SDA=0 while SCL still high -> START event
                    when START_COND =>
                        scl_internal <= '1';   -- Keep SCL high during SDA transition
                        if phase = 0 then
                            sda_internal <= '1';   -- Ensure SDA is high before falling edge
                            phase        <= 1;
                        else
                            sda_internal <= '0';   -- SDA falls while SCL=1: this is the START condition
                            phase        <= 0;
                            bit_counter  <= 7;     -- Prepare to send address MSB first
                            state        <= SEND_ADDR_W;
                        end if;

                    -- Send address byte (write direction: R/W='0' appended in addr_shift)
                    -- Each bit uses 4 phases: low-SDA | SCL-rise | SCL-high-hold | SCL-fall
                    when SEND_ADDR_W =>
                        case phase is
                            when 0 =>
                                scl_internal <= '0';                          -- Pull SCL low: safe to change SDA
                                sda_internal <= addr_shift(bit_counter);      -- Drive current address bit
                                phase <= 1;
                            when 1 =>
                                scl_internal <= '1';   -- Raise SCL: slave latches SDA on this rising edge
                                phase <= 2;
                            when 2 =>
                                phase <= 3;            -- Hold SCL high: additional setup time
                            when others =>
                                scl_internal <= '0';   -- Lower SCL: prepare for next bit
                                phase <= 0;
                                if bit_counter = 0 then
                                    state <= ACK_ADDR_W;   -- All 8 bits sent; wait for ACK
                                else
                                    bit_counter <= bit_counter - 1;  -- Advance to next bit (MSB->LSB)
                                end if;
                        end case;

                    -- ACK after address (write direction): release SDA and sample on phase 1 (SCL high)
                    when ACK_ADDR_W =>
                        case phase is
                            when 0 =>
                                scl_internal <= '0';   -- SCL low: release SDA for slave to drive ACK
                                sda_internal <= '1';   -- Release SDA (slave will pull it low for ACK)
                                phase <= 1;
                            when 1 =>
                                scl_internal <= '1';   -- Raise SCL: sample SDA now
                                -- FIX: read back from bus (works with open-drain); slave pulls SDA='0' for ACK
                                if sda = '0' then ack_ok <= '1'; else ack_ok <= '0'; end if;
                                phase <= 2;
                            when 2 =>
                                phase <= 3;            -- Hold SCL high
                            when others =>
                                scl_internal <= '0';   -- Lower SCL
                                phase <= 0;
                                if ack_ok = '1' then
                                    bit_counter <= 7;       -- ACK received: send register address next
                                    state <= SEND_REG;
                                else
                                    error <= '1';           -- NACK: slave not responding
                                    state <= STOP_COND;     -- Generate STOP and abort
                                end if;
                        end case;

                    -- Send register address byte (8 bits, MSB first)
                    when SEND_REG =>
                        case phase is
                            when 0 =>
                                scl_internal <= '0';
                                sda_internal <= data_shift(bit_counter);  -- data_shift holds reg_addr loaded at START
                                phase <= 1;
                            when 1 =>
                                scl_internal <= '1';   -- SCL rises: slave latches SDA
                                phase <= 2;
                            when 2 =>
                                phase <= 3;
                            when others =>
                                scl_internal <= '0';
                                phase <= 0;
                                if bit_counter = 0 then
                                    state <= ACK_REG;          -- All 8 bits sent; wait for ACK
                                else
                                    bit_counter <= bit_counter - 1;
                                end if;
                        end case;

                    -- ACK after register address: decides whether to write data or generate RESTART for read
                    when ACK_REG =>
                        case phase is
                            when 0 =>
                                scl_internal <= '0';
                                sda_internal <= '1';   -- Release SDA for slave ACK
                                phase <= 1;
                            when 1 =>
                                scl_internal <= '1';
                                if sda = '0' then ack_ok <= '1'; else ack_ok <= '0'; end if;
                                phase <= 2;
                            when 2 =>
                                phase <= 3;
                            when others =>
                                scl_internal <= '0';
                                phase <= 0;
                                if ack_ok = '1' then
                                    if rw = '1' then
                                        state <= RESTART_COND;    -- Read: need REPEATED START to switch direction
                                    else
                                        data_shift  <= data_in;   -- Write: load data byte into shift register
                                        bit_counter <= 7;
                                        state <= WRITE_DATA;
                                    end if;
                                else
                                    error <= '1';          -- NACK: register address not acknowledged
                                    state <= STOP_COND;
                                end if;
                        end case;

                    -- Write data byte to slave (8 bits, MSB first)
                    when WRITE_DATA =>
                        case phase is
                            when 0 =>
                                scl_internal <= '0';
                                sda_internal <= data_shift(bit_counter);  -- Drive current data bit
                                phase <= 1;
                            when 1 =>
                                scl_internal <= '1';
                                phase <= 2;
                            when 2 =>
                                phase <= 3;
                            when others =>
                                scl_internal <= '0';
                                phase <= 0;
                                if bit_counter = 0 then
                                    state <= ACK_DATA;         -- All 8 bits sent; check ACK
                                else
                                    bit_counter <= bit_counter - 1;
                                end if;
                        end case;

                    -- ACK after data write: slave acknowledges receipt of the written byte
                    when ACK_DATA =>
                        case phase is
                            when 0 =>
                                scl_internal <= '0';
                                sda_internal <= '1';   -- Release SDA for slave ACK
                                phase <= 1;
                            when 1 =>
                                scl_internal <= '1';
                                if sda = '0' then ack_ok <= '1'; else ack_ok <= '0'; end if;  -- Sample ACK
                                phase <= 2;
                            when 2 =>
                                phase <= 3;
                            when others =>
                                scl_internal <= '0';
                                phase <= 0;
                                if ack_ok = '0' then error <= '1'; end if;  -- NACK after write: flag error
                                state <= STOP_COND;   -- Write complete (or failed): generate STOP
                        end case;

                    -- REPEATED START condition (for read transactions after writing register address)
                    -- Sequence: raise SDA while SCL is low, raise SCL, fall SDA while SCL is high
                    when RESTART_COND =>
                        case phase is
                            when 0 =>
                                scl_internal <= '0';
                                sda_internal <= '1';   -- Ensure SDA is high before raising SCL
                                phase <= 1;
                            when 1 =>
                                scl_internal <= '1';   -- Raise SCL: bus is now high-high (idle-like)
                                phase <= 2;
                            when 2 =>
                                sda_internal <= '0';   -- SDA falls while SCL is still high: REPEATED START event
                                phase <= 3;
                            when others =>
                                scl_internal <= '0';
                                addr_shift   <= slave_addr & '1';  -- Reload address with R/W='1' (read direction)
                                bit_counter  <= 7;
                                phase        <= 0;
                                state        <= SEND_ADDR_R;
                        end case;

                    -- Send address byte (read direction: R/W='1' in LSB of addr_shift)
                    when SEND_ADDR_R =>
                        case phase is
                            when 0 =>
                                scl_internal <= '0';
                                sda_internal <= addr_shift(bit_counter);  -- Drive current address bit
                                phase <= 1;
                            when 1 =>
                                scl_internal <= '1';   -- Slave latches address bit on rising SCL
                                phase <= 2;
                            when 2 =>
                                phase <= 3;
                            when others =>
                                scl_internal <= '0';
                                phase <= 0;
                                if bit_counter = 0 then
                                    state <= ACK_ADDR_R;   -- All 8 bits sent; wait for ACK
                                else
                                    bit_counter <= bit_counter - 1;
                                end if;
                        end case;

                    -- ACK after address (read direction)
                    when ACK_ADDR_R =>
                        case phase is
                            when 0 =>
                                scl_internal <= '0';
                                sda_internal <= '1';   -- Release SDA for slave ACK
                                phase <= 1;
                            when 1 =>
                                scl_internal <= '1';
                                if sda = '0' then ack_ok <= '1'; else ack_ok <= '0'; end if;  -- Sample slave ACK
                                phase <= 2;
                            when 2 =>
                                phase <= 3;
                            when others =>
                                scl_internal <= '0';
                                phase <= 0;
                                if ack_ok = '1' then
                                    bit_counter <= 7;
                                    state <= READ_DATA;    -- ACK OK: begin reading 8 data bits
                                else
                                    error <= '1';          -- NACK: slave not responding in read mode
                                    state <= STOP_COND;
                                end if;
                        end case;

                    -- Read 8 data bits: SDA is driven by slave; master clocks SCL and samples on phase 1
                    when READ_DATA =>
                        case phase is
                            when 0 =>
                                scl_internal <= '0';
                                sda_internal <= '1';  -- Release SDA: slave now drives it with the data bit
                                phase <= 1;
                            when 1 =>
                                scl_internal <= '1';                         -- Raise SCL: slave holds SDA valid
                                data_shift(bit_counter) <= sda;              -- Sample SDA into shift register at bit centre
                                phase <= 2;
                            when 2 =>
                                phase <= 3;
                            when others =>
                                scl_internal <= '0';
                                phase <= 0;
                                if bit_counter = 0 then
                                    state <= SEND_NACK;   -- All 8 bits received; send NACK to end burst
                                else
                                    bit_counter <= bit_counter - 1;  -- Advance to next bit
                                end if;
                        end case;

                    -- Send NACK then go to STOP:
                    -- Master drives SDA='1' (not pulled low) to tell slave "last byte, stop sending"
                    when SEND_NACK =>
                        case phase is
                            when 0 =>
                                scl_internal <= '0';
                                sda_internal <= '1';         -- NACK: master holds SDA high (does NOT pull low)
                                data_out     <= data_shift;  -- Latch all 8 received bits to output port
                                phase <= 1;
                            when 1 =>
                                scl_internal <= '1';   -- Slave sees NACK on this SCL rising edge
                                phase <= 2;
                            when 2 =>
                                phase <= 3;
                            when others =>
                                scl_internal <= '0';
                                phase <= 0;
                                state <= STOP_COND;    -- NACK sent; generate STOP condition
                        end case;

                    -- STOP condition: SDA rises while SCL is high
                    -- Phase 0: SCL low, SDA low (prepare)
                    -- Phase 1: SCL rises (while SDA still low)
                    -- Phase 2: SDA rises while SCL is high -> STOP event
                    -- Phase 3: hold idle; pulse done and return to IDLE
                    when STOP_COND =>
                        case phase is
                            when 0 =>
                                scl_internal <= '0';
                                sda_internal <= '0';   -- Ensure SDA is low before raising SCL
                                phase <= 1;
                            when 1 =>
                                scl_internal <= '1';   -- Raise SCL first
                                phase <= 2;
                            when 2 =>
                                sda_internal <= '1';   -- SDA rises while SCL is high: STOP condition
                                phase <= 3;
                            when others =>
                                done  <= '1';          -- One-cycle pulse: transaction fully complete
                                phase <= 0;
                                state <= IDLE;
                        end case;

                end case;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------------
    -- FIX: Open-drain outputs for both SDA and SCL
    -- Drive '0' (pull low) when needed; release to 'Z' (high-impedance) otherwise.
    -- External 4.7 kΩ pull-up resistors bring the bus back to logic '1' when released.
    -- This allows clock stretching and proper multi-master arbitration.
    ---------------------------------------------------------------------------
    sda <= '0' when sda_internal = '0' else 'Z';   -- Drive SDA low or release to pull-up
    scl <= '0' when scl_internal = '0' else 'Z';   -- FIX: was 'scl <= scl_internal'; now open-drain for clock stretch

end Behavioral;
