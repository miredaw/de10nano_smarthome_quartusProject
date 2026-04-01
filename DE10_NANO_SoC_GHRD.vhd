library IEEE;                          -- Standard IEEE library
use IEEE.STD_LOGIC_1164.ALL;           -- Provides std_logic and std_logic_vector types
use IEEE.NUMERIC_STD.ALL;              -- Provides unsigned arithmetic for the LED counter

-- Top-level entity: DE10_NANO_SoC_GHRD
-- All physical board pins are declared here; this is what Quartus uses for pin assignment.
entity DE10_NANO_SoC_GHRD is
    port (
        ------------ CLOCK ----------
        -- Three 50 MHz clock inputs from the board oscillator (all identical; use FPGA_CLK1_50)
        FPGA_CLK1_50    : in    std_logic;   -- Primary 50 MHz clock used by all logic
        FPGA_CLK2_50    : in    std_logic;   -- Secondary 50 MHz clock (unused in this design)
        FPGA_CLK3_50    : in    std_logic;   -- Tertiary  50 MHz clock (unused in this design)

        ------------ HDMI ----------
        -- HDMI ADV7513 transmitter I/O (not used in smart-home project; ports must still be declared)
        HDMI_I2C_SCL    : inout std_logic;   -- HDMI configuration I2C clock
        HDMI_I2C_SDA    : inout std_logic;   -- HDMI configuration I2C data
        HDMI_I2S        : inout std_logic;   -- HDMI audio I2S data
        HDMI_LRCLK      : inout std_logic;   -- HDMI audio left/right clock
        HDMI_MCLK       : inout std_logic;   -- HDMI audio master clock
        HDMI_SCLK       : inout std_logic;   -- HDMI audio serial clock
        HDMI_TX_CLK     : out   std_logic;   -- HDMI pixel clock output
        HDMI_TX_D       : out   std_logic_vector(23 downto 0);  -- 24-bit RGB pixel data
        HDMI_TX_DE      : out   std_logic;   -- HDMI data enable
        HDMI_TX_HS      : out   std_logic;   -- HDMI horizontal sync
        HDMI_TX_INT     : in    std_logic;   -- HDMI interrupt from ADV7513
        HDMI_TX_VS      : out   std_logic;   -- HDMI vertical sync

        ------------ HPS ----------
        -- Hard Processor System (ARM Cortex-A9) I/O; routed through DE10-Nano schematic
        HPS_CONV_USB_N      : inout std_logic;                       -- USB converter GPIO
        HPS_DDR3_ADDR       : out   std_logic_vector(14 downto 0);   -- DDR3 row/column address
        HPS_DDR3_BA         : out   std_logic_vector(2 downto 0);    -- DDR3 bank address
        HPS_DDR3_CAS_N      : out   std_logic;                       -- DDR3 column address strobe (active-low)
        HPS_DDR3_CK_N       : out   std_logic;                       -- DDR3 differential clock (negative)
        HPS_DDR3_CK_P       : out   std_logic;                       -- DDR3 differential clock (positive)
        HPS_DDR3_CKE        : out   std_logic;                       -- DDR3 clock enable
        HPS_DDR3_CS_N       : out   std_logic;                       -- DDR3 chip select (active-low)
        HPS_DDR3_DM         : out   std_logic_vector(3 downto 0);    -- DDR3 data mask (4 bytes)
        HPS_DDR3_DQ         : inout std_logic_vector(31 downto 0);   -- DDR3 data bus (32-bit)
        HPS_DDR3_DQS_N      : inout std_logic_vector(3 downto 0);    -- DDR3 data strobe (differential, negative)
        HPS_DDR3_DQS_P      : inout std_logic_vector(3 downto 0);    -- DDR3 data strobe (differential, positive)
        HPS_DDR3_ODT        : out   std_logic;                       -- DDR3 on-die termination control
        HPS_DDR3_RAS_N      : out   std_logic;                       -- DDR3 row address strobe (active-low)
        HPS_DDR3_RESET_N    : out   std_logic;                       -- DDR3 reset (active-low)
        HPS_DDR3_RZQ        : in    std_logic;                       -- DDR3 ZQ calibration reference
        HPS_DDR3_WE_N       : out   std_logic;                       -- DDR3 write enable (active-low)
        HPS_ENET_GTX_CLK    : out   std_logic;                       -- Ethernet RGMII transmit clock
        HPS_ENET_INT_N      : inout std_logic;                       -- Ethernet PHY interrupt (active-low)
        HPS_ENET_MDC        : out   std_logic;                       -- Ethernet MDIO management clock
        HPS_ENET_MDIO       : inout std_logic;                       -- Ethernet MDIO management data
        HPS_ENET_RX_CLK     : in    std_logic;                       -- Ethernet RGMII receive clock
        HPS_ENET_RX_DATA    : in    std_logic_vector(3 downto 0);    -- Ethernet RGMII receive data
        HPS_ENET_RX_DV      : in    std_logic;                       -- Ethernet RGMII receive data valid
        HPS_ENET_TX_DATA    : out   std_logic_vector(3 downto 0);    -- Ethernet RGMII transmit data
        HPS_ENET_TX_EN      : out   std_logic;                       -- Ethernet RGMII transmit enable
        HPS_GSENSOR_INT     : inout std_logic;                       -- Accelerometer interrupt
        HPS_I2C0_SCLK       : inout std_logic;                       -- HPS I2C0 clock (ADXL345 accelerometer)
        HPS_I2C0_SDAT       : inout std_logic;                       -- HPS I2C0 data
        HPS_I2C1_SCLK       : inout std_logic;                       -- HPS I2C1 clock (unused)
        HPS_I2C1_SDAT       : inout std_logic;                       -- HPS I2C1 data
        HPS_KEY             : inout std_logic;                       -- HPS-side push button
        HPS_LED             : inout std_logic;                       -- HPS-side LED
        HPS_LTC_GPIO        : inout std_logic;                       -- LTC connector GPIO
        HPS_SD_CLK          : out   std_logic;                       -- SD card clock
        HPS_SD_CMD          : inout std_logic;                       -- SD card command
        HPS_SD_DATA         : inout std_logic_vector(3 downto 0);    -- SD card data (4-bit)
        HPS_SPIM_CLK        : out   std_logic;                       -- HPS SPI master clock
        HPS_SPIM_MISO       : in    std_logic;                       -- HPS SPI master MISO
        HPS_SPIM_MOSI       : out   std_logic;                       -- HPS SPI master MOSI
        HPS_SPIM_SS         : inout std_logic;                       -- HPS SPI master slave select
        HPS_UART_RX         : in    std_logic;                       -- HPS UART0 RX (console: /dev/ttyS0)
        HPS_UART_TX         : out   std_logic;                       -- HPS UART0 TX (console)
        HPS_USB_CLKOUT      : in    std_logic;                       -- USB PHY clock output
        HPS_USB_DATA        : inout std_logic_vector(7 downto 0);    -- USB PHY 8-bit data bus
        HPS_USB_DIR         : in    std_logic;                       -- USB PHY data direction
        HPS_USB_NXT         : in    std_logic;                       -- USB PHY next token
        HPS_USB_STP         : out   std_logic;                       -- USB PHY stop

        ------------ KEY ----------
        -- Two active-low push-buttons on the FPGA side of the DE10-Nano board
        KEY                 : in    std_logic_vector(1 downto 0);    -- KEY(0)=reset request, KEY(1)=spare

        ------------ LED ----------
        -- 8 green LEDs on the DE10-Nano board (LED(0) = leftmost)
        LED                 : out   std_logic_vector(7 downto 0);    -- LED[0]=heartbeat, LED[7:3]=alarm debug

        ------------ SW ----------
        -- 4 slide switches on the board
        SW                  : in    std_logic_vector(3 downto 0);    -- SW[3:0] fed into stm_hw_events for HPS debug

        ------------ SMART HOME SENSORS (GPIO Header JP1) ----------
        -- BME280 I2C sensor (connected to JP1 pins 1/2)
        BME280_SDA          : inout std_logic;   -- I2C SDA: JP1 pin 1 (PIN_V12)
        BME280_SCL          : inout std_logic;   -- FIX: was 'out'; open-drain requires inout for clock stretching

        -- MCP3008 SPI ADC (connected to JP1 pins 3/4/5/6)
        MCP3008_CLK         : out   std_logic;   -- SPI CLK:  JP1 pin 3 (PIN_W12)
        MCP3008_MOSI        : out   std_logic;   -- SPI MOSI: JP1 pin 4 (PIN_D11)
        MCP3008_MISO        : in    std_logic;   -- SPI MISO: JP1 pin 5 (PIN_D8)
        MCP3008_CS_N        : out   std_logic;   -- SPI CS_N: JP1 pin 6 (PIN_AH13)

        -- PIR motion sensors (connected to JP1 pins 7/8)
        PIR1                : in    std_logic;   -- PIR sensor 1: JP1 pin 7 (PIN_AF7)
        PIR2                : in    std_logic;   -- PIR sensor 2: JP1 pin 8 (PIN_AH14)

        -- External push-buttons (not mapped to physical pins in this version; left for expansion)
        BUTTON_EXT          : in    std_logic_vector(3 downto 0);

        -- External LED outputs (driven by gpio_avalon_wrapper via alarm OR logic)
        LED_RED_EXT         : out   std_logic;   -- Red    LED output (temperature alarm)
        LED_GREEN_EXT       : out   std_logic;   -- Green  LED output (system OK)
        LED_YELLOW_EXT      : out   std_logic;   -- Yellow LED output (motion alarm)
        BUZZER_EXT          : out   std_logic;   -- Buzzer output (pulsed during critical alarm)

        ------------ SIM800L UART (Altera UART IP, JP1 pins 19/20) ----------
        -- The SIM800L is controlled by the HPS C supervisor via /dev/ttyS2 (or Altera UART IP)
        -- JP1 Pin 19 (GPIO_0[16] PIN_D12 ) -> UART_SIM800L_TX  (FPGA tx -> SIM800L rx)
        -- JP1 Pin 20 (GPIO_0[17] PIN_AD20) -> UART_SIM800L_RX  (SIM800L tx -> FPGA rx)
        UART_SIM800L_TX     : out   std_logic;   -- SIM800L serial data receive line (from FPGA)
        UART_SIM800L_RX     : in    std_logic;   -- SIM800L serial data transmit line (to FPGA)

        ------------ ESP32 UART (HPS UART1 via FPGA fabric, JP1 pins 21/22) ----------
        -- The ESP32 Wi-Fi module is controlled by HPS UART1 routed through FPGA fabric.
        -- Linux sees this as /dev/ttyS1 (8250 driver); used for Wi-Fi AT commands.
        -- JP1 Pin 21 (GPIO_0[18] PIN_C12 ) -> UART_ESP32_TX  (HPS tx -> ESP32 RX GPIO16)
        -- JP1 Pin 22 (GPIO_0[19] PIN_AD17) -> UART_ESP32_RX  (ESP32 TX GPIO17 -> HPS rx)
        UART_ESP32_TX       : out   std_logic;   -- HPS UART1 TX -> ESP32 RX
        UART_ESP32_RX       : in    std_logic    -- ESP32 TX -> HPS UART1 RX
    );
end entity DE10_NANO_SoC_GHRD;

architecture rtl of DE10_NANO_SoC_GHRD is

    -- Declare the Platform Designer-generated system as a component.
    -- soc_system contains: HPS (ARM + DDR3 controller), Lightweight AXI Bridge,
    -- all Avalon MM peripherals (bme280, mcp3008, gpio, alarm_logic, Altera UART for SIM800L).
    component soc_system is
        port (
            -- Clock and active-low reset from HPS PLL
            clk_clk                                      : in    std_logic;   -- 50 MHz FPGA clock input to PD system
            reset_reset_n                                : in    std_logic;   -- Active-low reset from hps_fpga_reset_n

            -- DDR3 SDRAM interface (connects directly to DE10-Nano HPS_DDR3_* pins)
            memory_mem_a                                 : out   std_logic_vector(14 downto 0);   -- Row/column address
            memory_mem_ba                                : out   std_logic_vector(2 downto 0);    -- Bank address
            memory_mem_ck                                : out   std_logic;                       -- Diff clock (positive)
            memory_mem_ck_n                              : out   std_logic;                       -- Diff clock (negative)
            memory_mem_cke                               : out   std_logic;                       -- Clock enable
            memory_mem_cs_n                              : out   std_logic;                       -- Chip select
            memory_mem_ras_n                             : out   std_logic;                       -- Row address strobe
            memory_mem_cas_n                             : out   std_logic;                       -- Column address strobe
            memory_mem_we_n                              : out   std_logic;                       -- Write enable
            memory_mem_reset_n                           : out   std_logic;                       -- DDR3 reset
            memory_mem_dq                                : inout std_logic_vector(31 downto 0);   -- Data bus
            memory_mem_dqs                               : inout std_logic_vector(3 downto 0);    -- Data strobe (positive)
            memory_mem_dqs_n                             : inout std_logic_vector(3 downto 0);    -- Data strobe (negative)
            memory_mem_odt                               : out   std_logic;                       -- On-die termination
            memory_mem_dm                                : out   std_logic_vector(3 downto 0);    -- Data mask
            memory_oct_rzqin                             : in    std_logic;                       -- ZQ calibration

            -- HPS I/O: Gigabit Ethernet (RGMII)
            hps_0_hps_io_hps_io_emac1_inst_TX_CLK       : out   std_logic;
            hps_0_hps_io_hps_io_emac1_inst_TXD0         : out   std_logic;
            hps_0_hps_io_hps_io_emac1_inst_TXD1         : out   std_logic;
            hps_0_hps_io_hps_io_emac1_inst_TXD2         : out   std_logic;
            hps_0_hps_io_hps_io_emac1_inst_TXD3         : out   std_logic;
            hps_0_hps_io_hps_io_emac1_inst_RXD0         : in    std_logic;
            hps_0_hps_io_hps_io_emac1_inst_MDIO         : inout std_logic;   -- MDIO management data
            hps_0_hps_io_hps_io_emac1_inst_MDC          : out   std_logic;   -- MDIO management clock
            hps_0_hps_io_hps_io_emac1_inst_RX_CTL       : in    std_logic;
            hps_0_hps_io_hps_io_emac1_inst_TX_CTL       : out   std_logic;
            hps_0_hps_io_hps_io_emac1_inst_RX_CLK       : in    std_logic;
            hps_0_hps_io_hps_io_emac1_inst_RXD1         : in    std_logic;
            hps_0_hps_io_hps_io_emac1_inst_RXD2         : in    std_logic;
            hps_0_hps_io_hps_io_emac1_inst_RXD3         : in    std_logic;

            -- HPS I/O: SD card
            hps_0_hps_io_hps_io_sdio_inst_CMD           : inout std_logic;   -- SD command line
            hps_0_hps_io_hps_io_sdio_inst_D0            : inout std_logic;   -- SD data bit 0
            hps_0_hps_io_hps_io_sdio_inst_D1            : inout std_logic;   -- SD data bit 1
            hps_0_hps_io_hps_io_sdio_inst_CLK           : out   std_logic;   -- SD clock
            hps_0_hps_io_hps_io_sdio_inst_D2            : inout std_logic;   -- SD data bit 2
            hps_0_hps_io_hps_io_sdio_inst_D3            : inout std_logic;   -- SD data bit 3

            -- HPS I/O: USB (ULPI PHY)
            hps_0_hps_io_hps_io_usb1_inst_D0            : inout std_logic;   -- USB data D0
            hps_0_hps_io_hps_io_usb1_inst_D1            : inout std_logic;
            hps_0_hps_io_hps_io_usb1_inst_D2            : inout std_logic;
            hps_0_hps_io_hps_io_usb1_inst_D3            : inout std_logic;
            hps_0_hps_io_hps_io_usb1_inst_D4            : inout std_logic;
            hps_0_hps_io_hps_io_usb1_inst_D5            : inout std_logic;
            hps_0_hps_io_hps_io_usb1_inst_D6            : inout std_logic;
            hps_0_hps_io_hps_io_usb1_inst_D7            : inout std_logic;   -- USB data D7
            hps_0_hps_io_hps_io_usb1_inst_CLK           : in    std_logic;   -- USB PHY clock
            hps_0_hps_io_hps_io_usb1_inst_STP           : out   std_logic;   -- USB PHY stop
            hps_0_hps_io_hps_io_usb1_inst_DIR           : in    std_logic;   -- USB PHY direction
            hps_0_hps_io_hps_io_usb1_inst_NXT           : in    std_logic;   -- USB PHY next

            -- HPS I/O: SPI master 1 (used for accelerometer in default GHRD)
            hps_0_hps_io_hps_io_spim1_inst_CLK          : out   std_logic;
            hps_0_hps_io_hps_io_spim1_inst_MOSI         : out   std_logic;
            hps_0_hps_io_hps_io_spim1_inst_MISO         : in    std_logic;
            hps_0_hps_io_hps_io_spim1_inst_SS0          : inout std_logic;

            -- HPS I/O: UART0 (Linux console /dev/ttyS0)
            hps_0_hps_io_hps_io_uart0_inst_RX           : in    std_logic;
            hps_0_hps_io_hps_io_uart0_inst_TX           : out   std_logic;

            -- HPS I/O: I2C0 and I2C1 (accelerometer, HPS-side sensors)
            hps_0_hps_io_hps_io_i2c0_inst_SDA           : inout std_logic;
            hps_0_hps_io_hps_io_i2c0_inst_SCL           : inout std_logic;
            hps_0_hps_io_hps_io_i2c1_inst_SDA           : inout std_logic;
            hps_0_hps_io_hps_io_i2c1_inst_SCL           : inout std_logic;

            -- HPS GPIO (board-specific: USB converter, Ethernet INT, LTC, HPS LED/KEY, G-sensor)
            hps_0_hps_io_hps_io_gpio_inst_GPIO09        : inout std_logic;   -- USB converter control
            hps_0_hps_io_hps_io_gpio_inst_GPIO35        : inout std_logic;   -- Ethernet PHY INT
            hps_0_hps_io_hps_io_gpio_inst_GPIO40        : inout std_logic;   -- LTC connector
            hps_0_hps_io_hps_io_gpio_inst_GPIO53        : inout std_logic;   -- HPS LED
            hps_0_hps_io_hps_io_gpio_inst_GPIO54        : inout std_logic;   -- HPS KEY
            hps_0_hps_io_hps_io_gpio_inst_GPIO61        : inout std_logic;   -- G-sensor interrupt

            -- HPS Reset and Event ports (for FPGA-to-HPS reset requests and hardware events)
            hps_0_h2f_reset_reset_n                      : out   std_logic;   -- HPS drives this low on power-on; used as FPGA reset
            hps_0_f2h_cold_reset_req_reset_n             : in    std_logic;   -- FPGA requests HPS cold reset (active-low)
            hps_0_f2h_debug_reset_req_reset_n            : in    std_logic;   -- FPGA requests HPS debug reset
            hps_0_f2h_stm_hw_events_stm_hwevents         : in    std_logic_vector(27 downto 0);  -- HW event vector for STM trace
            hps_0_f2h_warm_reset_req_reset_n             : in    std_logic;   -- FPGA requests HPS warm reset

            -- BME280 I2C conduit (Platform Designer exports)
            bme280_i2c_new_signal                        : inout std_logic;   -- BME280 SDA (inout for open-drain)
            bme280_i2c_new_signal_1                      : inout std_logic;   -- FIX: BME280 SCL (inout, not 'out', for clock stretch)

            -- MCP3008 SPI conduit (Platform Designer exports)
            mcp3008_spi_new_signal                       : out   std_logic;   -- MCP3008 SPI CLK
            mcp3008_spi_new_signal_1                     : out   std_logic;   -- MCP3008 SPI MOSI
            mcp3008_spi_new_signal_2                     : in    std_logic;   -- MCP3008 SPI MISO
            mcp3008_spi_new_signal_3                     : out   std_logic;   -- MCP3008 SPI CS_N

            -- GPIO conduit (Platform Designer exports for PIR, buttons, LEDs, buzzer)
            gpio_inputs_new_signal                       : in    std_logic;                        -- PIR1 debounced input
            gpio_inputs_new_signal_1                     : in    std_logic;                        -- PIR2 debounced input
            gpio_inputs_new_signal_2                     : in    std_logic_vector(3 downto 0);     -- BUTTON_EXT[3:0] inputs
            gpio_outputs_new_signal                      : out   std_logic;                        -- LED_RED_EXT output
            gpio_outputs_new_signal_1                    : out   std_logic;                        -- LED_GREEN_EXT output
            gpio_outputs_new_signal_2                    : out   std_logic;                        -- LED_YELLOW_EXT output
            gpio_outputs_new_signal_3                    : out   std_logic;                        -- BUZZER_EXT output

            -- Alarm sensor inputs conduit (sensor data routed from BME280/MCP3008 to alarm_logic)
            alarm_sensor_inputs_new_signal               : in    std_logic_vector(15 downto 0);  -- Temperature [15:0] from BME280 temp_raw[19:4]
            alarm_sensor_inputs_new_signal_1             : in    std_logic_vector(9 downto 0);   -- Light level [9:0] from MCP3008 CH0
            alarm_sensor_inputs_new_signal_2             : in    std_logic;                       -- Motion: PIR1 OR PIR2 (combined)

            -- Alarm hardware output flags conduit (from alarm_logic to LED debug and optional interrupt)
            alarm_hw_outputs_new_signal                  : out   std_logic;   -- alarm_temp_high flag
            alarm_hw_outputs_new_signal_1                : out   std_logic;   -- alarm_temp_low  flag
            alarm_hw_outputs_new_signal_2                : out   std_logic;   -- alarm_light_low flag
            alarm_hw_outputs_new_signal_3                : out   std_logic;   -- alarm_motion    flag
            alarm_hw_outputs_new_signal_4                : out   std_logic;   -- alarm_critical  flag (OR of all)

            -- Sensor conduit exports (raw/filtered values looped back for wiring to alarm_logic inputs)
            bme280_sensor_data_new_signal                : out   std_logic_vector(19 downto 0);  -- 20-bit raw temperature from BME280
            mcp3008_sensor_data_new_signal               : out   std_logic_vector(9 downto 0);   -- 10-bit filtered CH0 from MCP3008

            -- Altera UART conduit for SIM800L (9600 baud GSM modem)
            uart_sim800l_txd                             : out   std_logic;   -- FPGA TX -> SIM800L RX (AT commands to GSM modem)
            uart_sim800l_rxd                             : in    std_logic;   -- SIM800L TX -> FPGA RX (GSM modem responses)

            -- HPS UART1 routed through FPGA fabric (for ESP32 AT commands -> /dev/ttyS1)
            -- "Full" mode: all modem-control signals exposed; unused ones tied to safe values
            hps_0_uart1_rxd                              : in    std_logic;   -- ESP32 TX GPIO17 -> FPGA JP1 pin 22
            hps_0_uart1_txd                              : out   std_logic;   -- FPGA JP1 pin 21 -> ESP32 RX GPIO16
            hps_0_uart1_cts                              : in    std_logic;   -- Clear-to-send; tied '1' (always clear)
            hps_0_uart1_dsr                              : in    std_logic;   -- Data-set-ready; tied '1'
            hps_0_uart1_dcd                              : in    std_logic;   -- Data-carrier-detect; tied '1'
            hps_0_uart1_ri                               : in    std_logic;   -- Ring indicator; tied '0'
            hps_0_uart1_dtr                              : out   std_logic;   -- Data-terminal-ready; not used (open)
            hps_0_uart1_rts                              : out   std_logic;   -- Request-to-send; not used (open)
            hps_0_uart1_out1_n                           : out   std_logic;   -- Modem output 1; not used (open)
            hps_0_uart1_out2_n                           : out   std_logic    -- Modem output 2; not used (open)
        );
    end component;

    -- Altera-provided debounce IP: removes glitches from KEY button inputs
    component debounce is
        generic (
            WIDTH         : integer;   -- Number of signals to debounce in parallel
            POLARITY      : string;    -- "LOW" = active-low inputs (buttons)
            TIMEOUT       : integer;   -- Debounce window in clock cycles
            TIMEOUT_WIDTH : integer    -- Bit width of the timeout counter
        );
        port (
            clk      : in  std_logic;
            reset_n  : in  std_logic;
            data_in  : in  std_logic_vector(WIDTH-1 downto 0);
            data_out : out std_logic_vector(WIDTH-1 downto 0)
        );
    end component;

    -- Altera-provided HPS reset sequencer: drives the 3-bit reset request vector
    component hps_reset is
        port (
            source_clk : in  std_logic;                        -- System clock
            source     : out std_logic_vector(2 downto 0)      -- [0]=cold, [1]=warm, [2]=debug reset requests
        );
    end component;

    -- Altera-provided edge detector: converts a level reset request into a pulse
    component altera_edge_detector is
        generic (
            PULSE_EXT             : integer;   -- Pulse extension width in clock cycles
            EDGE_TYPE             : integer;   -- 1 = rising edge detection
            IGNORE_RST_WHILE_BUSY : integer    -- 1 = ignore new edges while pulse is still active
        );
        port (
            clk        : in  std_logic;
            rst_n      : in  std_logic;
            signal_in  : in  std_logic;
            pulse_out  : out std_logic
        );
    end component;

    -------------------------------------------------------
    -- Internal signals
    -------------------------------------------------------
    signal hps_fpga_reset_n       : std_logic;                      -- '0' from HPS until POR complete; used as FPGA active-low reset
    signal fpga_debounced_buttons : std_logic_vector(1 downto 0);   -- Debounced KEY[1:0] outputs
    signal hps_reset_req          : std_logic_vector(2 downto 0);   -- Reset request levels from hps_reset IP
    signal hps_cold_reset         : std_logic;                      -- Pulsed cold reset request to HPS
    signal hps_warm_reset         : std_logic;                      -- Pulsed warm reset request to HPS
    signal hps_debug_reset        : std_logic;                      -- Pulsed debug reset request to HPS
    signal stm_hw_events          : std_logic_vector(27 downto 0);  -- Hardware event vector for HPS STM trace module
    signal fpga_clk_50            : std_logic;                      -- Alias for FPGA_CLK1_50 used throughout this file
    signal counter                : unsigned(25 downto 0);          -- 26-bit counter for LED[0] heartbeat (~1 Hz)
    signal led_level              : std_logic;                      -- Current LED[0] blink state

    -- Sensor data signals driven from Platform Designer conduit exports
    signal bme280_temp_raw        : std_logic_vector(19 downto 0);  -- 20-bit raw temperature from bme280_avalon_wrapper
    signal mcp3008_light          : std_logic_vector(9 downto 0);   -- 10-bit filtered light from mcp3008_avalon_wrapper

    -- Alarm status flag signals from alarm_logic (used to drive debug LEDs and optionally interrupts)
    signal alarm_temp_high_s      : std_logic;   -- Temperature-high alarm: goes to LED[3]
    signal alarm_temp_low_s       : std_logic;   -- Temperature-low  alarm: goes to LED[4]
    signal alarm_light_low_s      : std_logic;   -- Light-low alarm:        goes to LED[5]
    signal alarm_motion_s         : std_logic;   -- Motion alarm:           goes to LED[6]
    signal alarm_critical_s       : std_logic;   -- Critical (OR) alarm:    goes to LED[7]

begin

    -------------------------------------------------------
    -- Static assignments
    -------------------------------------------------------
    fpga_clk_50   <= FPGA_CLK1_50;   -- Use the first 50 MHz oscillator throughout

    -- FIX: replaced undriven fpga_led_internal with "0000000" to eliminate
    --      synthesis warning about undriven signals feeding stm_hw_events.
    -- stm_hw_events is the hardware events input to the HPS STM trace module.
    -- Bits: [27:13]=zeros | [12:9]=SW[3:0] | [8:2]="0000000" | [1:0]=debounced_buttons
    stm_hw_events <= (27 downto 13 => '0') & SW & "0000000" & fpga_debounced_buttons;

    -- Board LED assignments:
    -- LED[0]: FPGA heartbeat (1 Hz blink) - indicates FPGA fabric is alive
    -- LED[1:2]: unused, held low
    -- LED[3]: alarm_temp_high (temperature too high)
    -- LED[4]: alarm_temp_low  (temperature too low)
    -- LED[5]: alarm_light_low (ambient light too low)
    -- LED[6]: alarm_motion    (motion detected in last 5 seconds)
    -- LED[7]: alarm_critical  (any alarm active)
    LED(0)          <= led_level;           -- Heartbeat: toggles at ~1 Hz
    LED(2 downto 1) <= (others => '0');     -- Unused LED positions
    LED(3)          <= alarm_temp_high_s;   -- Temp-high alarm indicator
    LED(4)          <= alarm_temp_low_s;    -- Temp-low  alarm indicator
    LED(5)          <= alarm_light_low_s;   -- Light-low alarm indicator
    LED(6)          <= alarm_motion_s;      -- Motion alarm indicator
    LED(7)          <= alarm_critical_s;    -- Critical (any) alarm indicator

    -------------------------------------------------------
    -- Platform Designer system instantiation (u0)
    -- This is the heart of the design: contains HPS + all custom Avalon peripherals
    -------------------------------------------------------
    u0 : component soc_system
        port map (
            -- Clock: all logic in soc_system runs at 50 MHz
            clk_clk                                      => FPGA_CLK1_50,
            -- Active-low reset: HPS drives this low during power-on; goes high when HPS PLL is locked
            reset_reset_n                                => hps_fpga_reset_n,

            -- DDR3 memory: direct connection to HPS_DDR3_* board pins
            memory_mem_a                                 => HPS_DDR3_ADDR,       -- Row/column address
            memory_mem_ba                                => HPS_DDR3_BA,         -- Bank address
            memory_mem_ck                                => HPS_DDR3_CK_P,       -- Diff clock positive
            memory_mem_ck_n                              => HPS_DDR3_CK_N,       -- Diff clock negative
            memory_mem_cke                               => HPS_DDR3_CKE,        -- Clock enable
            memory_mem_cs_n                              => HPS_DDR3_CS_N,       -- Chip select
            memory_mem_ras_n                             => HPS_DDR3_RAS_N,      -- Row strobe
            memory_mem_cas_n                             => HPS_DDR3_CAS_N,      -- Column strobe
            memory_mem_we_n                              => HPS_DDR3_WE_N,       -- Write enable
            memory_mem_reset_n                           => HPS_DDR3_RESET_N,    -- DDR3 reset
            memory_mem_dq                                => HPS_DDR3_DQ,         -- 32-bit data bus
            memory_mem_dqs                               => HPS_DDR3_DQS_P,      -- Data strobe positive
            memory_mem_dqs_n                             => HPS_DDR3_DQS_N,      -- Data strobe negative
            memory_mem_odt                               => HPS_DDR3_ODT,        -- On-die termination
            memory_mem_dm                                => HPS_DDR3_DM,         -- Data mask
            memory_oct_rzqin                             => HPS_DDR3_RZQ,        -- ZQ calibration

            -- Ethernet: RGMII signals to Micrel KSZ9031 PHY
            hps_0_hps_io_hps_io_emac1_inst_TX_CLK       => HPS_ENET_GTX_CLK,
            hps_0_hps_io_hps_io_emac1_inst_TXD0         => HPS_ENET_TX_DATA(0),
            hps_0_hps_io_hps_io_emac1_inst_TXD1         => HPS_ENET_TX_DATA(1),
            hps_0_hps_io_hps_io_emac1_inst_TXD2         => HPS_ENET_TX_DATA(2),
            hps_0_hps_io_hps_io_emac1_inst_TXD3         => HPS_ENET_TX_DATA(3),
            hps_0_hps_io_hps_io_emac1_inst_RXD0         => HPS_ENET_RX_DATA(0),
            hps_0_hps_io_hps_io_emac1_inst_MDIO         => HPS_ENET_MDIO,
            hps_0_hps_io_hps_io_emac1_inst_MDC          => HPS_ENET_MDC,
            hps_0_hps_io_hps_io_emac1_inst_RX_CTL       => HPS_ENET_RX_DV,
            hps_0_hps_io_hps_io_emac1_inst_TX_CTL       => HPS_ENET_TX_EN,
            hps_0_hps_io_hps_io_emac1_inst_RX_CLK       => HPS_ENET_RX_CLK,
            hps_0_hps_io_hps_io_emac1_inst_RXD1         => HPS_ENET_RX_DATA(1),
            hps_0_hps_io_hps_io_emac1_inst_RXD2         => HPS_ENET_RX_DATA(2),
            hps_0_hps_io_hps_io_emac1_inst_RXD3         => HPS_ENET_RX_DATA(3),

            -- SD card: microSD connected to HPS SD controller
            hps_0_hps_io_hps_io_sdio_inst_CMD           => HPS_SD_CMD,
            hps_0_hps_io_hps_io_sdio_inst_D0            => HPS_SD_DATA(0),
            hps_0_hps_io_hps_io_sdio_inst_D1            => HPS_SD_DATA(1),
            hps_0_hps_io_hps_io_sdio_inst_CLK           => HPS_SD_CLK,
            hps_0_hps_io_hps_io_sdio_inst_D2            => HPS_SD_DATA(2),
            hps_0_hps_io_hps_io_sdio_inst_D3            => HPS_SD_DATA(3),

            -- USB PHY: ULPI interface to Cypress USB3300
            hps_0_hps_io_hps_io_usb1_inst_D0            => HPS_USB_DATA(0),
            hps_0_hps_io_hps_io_usb1_inst_D1            => HPS_USB_DATA(1),
            hps_0_hps_io_hps_io_usb1_inst_D2            => HPS_USB_DATA(2),
            hps_0_hps_io_hps_io_usb1_inst_D3            => HPS_USB_DATA(3),
            hps_0_hps_io_hps_io_usb1_inst_D4            => HPS_USB_DATA(4),
            hps_0_hps_io_hps_io_usb1_inst_D5            => HPS_USB_DATA(5),
            hps_0_hps_io_hps_io_usb1_inst_D6            => HPS_USB_DATA(6),
            hps_0_hps_io_hps_io_usb1_inst_D7            => HPS_USB_DATA(7),
            hps_0_hps_io_hps_io_usb1_inst_CLK           => HPS_USB_CLKOUT,
            hps_0_hps_io_hps_io_usb1_inst_STP           => HPS_USB_STP,
            hps_0_hps_io_hps_io_usb1_inst_DIR           => HPS_USB_DIR,
            hps_0_hps_io_hps_io_usb1_inst_NXT           => HPS_USB_NXT,

            -- SPI master 1 (default GHRD: ADXL345 accelerometer)
            hps_0_hps_io_hps_io_spim1_inst_CLK          => HPS_SPIM_CLK,
            hps_0_hps_io_hps_io_spim1_inst_MOSI         => HPS_SPIM_MOSI,
            hps_0_hps_io_hps_io_spim1_inst_MISO         => HPS_SPIM_MISO,
            hps_0_hps_io_hps_io_spim1_inst_SS0          => HPS_SPIM_SS,

            -- UART0: Linux serial console (/dev/ttyS0, 115200 8N1)
            hps_0_hps_io_hps_io_uart0_inst_RX           => HPS_UART_RX,
            hps_0_hps_io_hps_io_uart0_inst_TX           => HPS_UART_TX,

            -- I2C0: ADXL345 accelerometer and other HPS-side I2C devices
            hps_0_hps_io_hps_io_i2c0_inst_SDA           => HPS_I2C0_SDAT,
            hps_0_hps_io_hps_io_i2c0_inst_SCL           => HPS_I2C0_SCLK,
            hps_0_hps_io_hps_io_i2c1_inst_SDA           => HPS_I2C1_SDAT,
            hps_0_hps_io_hps_io_i2c1_inst_SCL           => HPS_I2C1_SCLK,

            -- HPS GPIO pins (board-specific peripherals)
            hps_0_hps_io_hps_io_gpio_inst_GPIO09        => HPS_CONV_USB_N,   -- USB converter
            hps_0_hps_io_hps_io_gpio_inst_GPIO35        => HPS_ENET_INT_N,   -- Ethernet PHY interrupt
            hps_0_hps_io_hps_io_gpio_inst_GPIO40        => HPS_LTC_GPIO,     -- LTC connector
            hps_0_hps_io_hps_io_gpio_inst_GPIO53        => HPS_LED,          -- HPS-side LED
            hps_0_hps_io_hps_io_gpio_inst_GPIO54        => HPS_KEY,          -- HPS-side button
            hps_0_hps_io_hps_io_gpio_inst_GPIO61        => HPS_GSENSOR_INT,  -- Accelerometer interrupt

            -- HPS reset handshake: hps_fpga_reset_n is the power-on reset from HPS to FPGA
            hps_0_h2f_reset_reset_n                      => hps_fpga_reset_n,
            -- Active-low pulse requests for HPS to perform cold/debug/warm resets
            hps_0_f2h_cold_reset_req_reset_n             => not hps_cold_reset,
            hps_0_f2h_debug_reset_req_reset_n            => not hps_debug_reset,
            hps_0_f2h_stm_hw_events_stm_hwevents         => stm_hw_events,    -- SW + buttons visible to HPS trace
            hps_0_f2h_warm_reset_req_reset_n             => not hps_warm_reset,

            -- BME280 I2C (FIX: SCL is now inout for open-drain clock stretching)
            bme280_i2c_new_signal                        => BME280_SDA,   -- JP1 pin 1
            bme280_i2c_new_signal_1                      => BME280_SCL,   -- JP1 pin 2 (inout)

            -- MCP3008 SPI: connect to JP1 pins 3-6
            mcp3008_spi_new_signal                       => MCP3008_CLK,   -- JP1 pin 3
            mcp3008_spi_new_signal_1                     => MCP3008_MOSI,  -- JP1 pin 4
            mcp3008_spi_new_signal_2                     => MCP3008_MISO,  -- JP1 pin 5
            mcp3008_spi_new_signal_3                     => MCP3008_CS_N,  -- JP1 pin 6

            -- GPIO conduit: PIR sensors, buttons, LEDs, buzzer
            gpio_inputs_new_signal                       => PIR1,          -- PIR1: JP1 pin 7
            gpio_inputs_new_signal_1                     => PIR2,          -- PIR2: JP1 pin 8
            gpio_inputs_new_signal_2                     => BUTTON_EXT,    -- External buttons
            gpio_outputs_new_signal                      => LED_RED_EXT,   -- Red    LED output
            gpio_outputs_new_signal_1                    => LED_GREEN_EXT, -- Green  LED output
            gpio_outputs_new_signal_2                    => LED_YELLOW_EXT,-- Yellow LED output
            gpio_outputs_new_signal_3                    => BUZZER_EXT,    -- Buzzer output

            -- Alarm sensor inputs: Platform Designer wires sensor conduit exports here
            -- These feed real-time values into alarm_logic_0 without HPS involvement
            alarm_sensor_inputs_new_signal               => bme280_temp_raw(19 downto 4),  -- Temperature bits[19:4] = 16-bit fixed-point word
            alarm_sensor_inputs_new_signal_1             => mcp3008_light,                  -- 10-bit filtered CH0 light level
            alarm_sensor_inputs_new_signal_2             => PIR1 or PIR2,                   -- Any motion on either PIR sensor

            -- Alarm status flag outputs: used to drive board LED[7:3] for visual debug
            alarm_hw_outputs_new_signal                  => alarm_temp_high_s,   -- Temp-high flag -> LED[3]
            alarm_hw_outputs_new_signal_1                => alarm_temp_low_s,    -- Temp-low  flag -> LED[4]
            alarm_hw_outputs_new_signal_2                => alarm_light_low_s,   -- Light-low flag -> LED[5]
            alarm_hw_outputs_new_signal_3                => alarm_motion_s,      -- Motion flag    -> LED[6]
            alarm_hw_outputs_new_signal_4                => alarm_critical_s,    -- Critical flag  -> LED[7]

            -- Sensor conduit exports: looped back to alarm_sensor_inputs above
            bme280_sensor_data_new_signal                => bme280_temp_raw,   -- 20-bit raw temperature from bme280_avalon_wrapper
            mcp3008_sensor_data_new_signal               => mcp3008_light,     -- 10-bit light from mcp3008_avalon_wrapper

            -- Altera UART for SIM800L (FIX v3: corrected port names to match soc_system.v)
            uart_sim800l_txd                             => UART_SIM800L_TX,   -- JP1 pin 19: FPGA -> SIM800L
            uart_sim800l_rxd                             => UART_SIM800L_RX,   -- JP1 pin 20: SIM800L -> FPGA

            -- HPS UART1 via FPGA fabric -> ESP32 Wi-Fi module (/dev/ttyS1, 115200 8N1)
            hps_0_uart1_txd                              => UART_ESP32_TX,    -- JP1 pin 21: FPGA -> ESP32 RX
            hps_0_uart1_rxd                              => UART_ESP32_RX,    -- JP1 pin 22: ESP32 TX -> FPGA
            -- Modem-control inputs: assert active-high so Linux 8250 driver is satisfied
            hps_0_uart1_cts                              => '1',   -- CTS='1': transmit always permitted
            hps_0_uart1_dsr                              => '1',   -- DSR='1': modem ready
            hps_0_uart1_dcd                              => '1',   -- DCD='1': carrier detected
            hps_0_uart1_ri                               => '0',   -- RI ='0': not ringing
            -- Modem-control outputs: leave unconnected (hardware flow-control not used)
            hps_0_uart1_dtr                              => open,  -- DTR: unused
            hps_0_uart1_rts                              => open,  -- RTS: unused
            hps_0_uart1_out1_n                           => open,  -- OUT1: unused
            hps_0_uart1_out2_n                           => open   -- OUT2: unused
        );

    -------------------------------------------------------
    -- Debounce (KEY buttons)
    -- Removes mechanical bounce glitches from the two FPGA-side push buttons.
    -- Both buttons are active-low; POLARITY="LOW" configures the IP accordingly.
    -- TIMEOUT=50000 cycles @ 50 MHz = 1 ms debounce window.
    -------------------------------------------------------
    debounce_inst : component debounce
        generic map (
            WIDTH         => 2,       -- Debounce both KEY[0] and KEY[1] simultaneously
            POLARITY      => "LOW",   -- Buttons are active-low
            TIMEOUT       => 50000,   -- 1 ms debounce window (50000 cycles @ 50 MHz)
            TIMEOUT_WIDTH => 16       -- 16-bit counter can hold up to 65535 cycles
        )
        port map (
            clk      => fpga_clk_50,           -- System clock
            reset_n  => hps_fpga_reset_n,       -- Active-low reset from HPS
            data_in  => KEY,                    -- Raw KEY[1:0] button inputs
            data_out => fpga_debounced_buttons  -- Debounced button outputs (fed into stm_hw_events)
        );

    -------------------------------------------------------
    -- HPS Reset logic
    -- hps_reset IP generates 3 reset request levels based on HPS state machine.
    -- altera_edge_detector IPs convert these levels into pulses required by the
    -- HPS reset request ports (f2h_cold_reset_req, etc.).
    -------------------------------------------------------
    hps_reset_inst : component hps_reset
        port map (
            source_clk => fpga_clk_50,   -- System clock
            source     => hps_reset_req  -- [0]=cold, [1]=warm, [2]=debug reset levels
        );

    -- Cold reset pulse generator: extends source[0] rising edge by 6 cycles
    -- Sent to hps_0_f2h_cold_reset_req_reset_n to request a full cold reset of HPS
    pulse_cold_reset : component altera_edge_detector
        generic map (PULSE_EXT => 6, EDGE_TYPE => 1, IGNORE_RST_WHILE_BUSY => 1)
        port map (
            clk       => fpga_clk_50,
            rst_n     => hps_fpga_reset_n,
            signal_in => hps_reset_req(0),   -- Cold reset request level from hps_reset IP
            pulse_out => hps_cold_reset       -- Pulse fed (inverted) into HPS cold reset port
        );

    -- Warm reset pulse generator: extends source[1] rising edge by 2 cycles
    -- Sent to hps_0_f2h_warm_reset_req_reset_n to request a warm (soft) HPS reset
    pulse_warm_reset : component altera_edge_detector
        generic map (PULSE_EXT => 2, EDGE_TYPE => 1, IGNORE_RST_WHILE_BUSY => 1)
        port map (
            clk       => fpga_clk_50,
            rst_n     => hps_fpga_reset_n,
            signal_in => hps_reset_req(1),   -- Warm reset request level
            pulse_out => hps_warm_reset
        );

    -- Debug reset pulse generator: extends source[2] rising edge by 32 cycles
    -- Sent to hps_0_f2h_debug_reset_req_reset_n to request an HPS debug reset
    pulse_debug_reset : component altera_edge_detector
        generic map (PULSE_EXT => 32, EDGE_TYPE => 1, IGNORE_RST_WHILE_BUSY => 1)
        port map (
            clk       => fpga_clk_50,
            rst_n     => hps_fpga_reset_n,
            signal_in => hps_reset_req(2),   -- Debug reset request level
            pulse_out => hps_debug_reset
        );

    -------------------------------------------------------
    -- LED[0] heartbeat: ~1 Hz on 50 MHz clock
    -- Counts to 24_999_999 (= 25M - 1 = 500 ms) then toggles led_level.
    -- This gives a 1 Hz blink (500 ms on, 500 ms off).
    -- Uses hps_fpga_reset_n as active-low reset so it starts only after HPS is ready.
    -------------------------------------------------------
    led_counter_process : process(fpga_clk_50, hps_fpga_reset_n)
    begin
        if hps_fpga_reset_n = '0' then
            counter   <= (others => '0');   -- Clear counter at reset
            led_level <= '0';               -- LED starts off
        elsif rising_edge(fpga_clk_50) then
            if counter = 24999999 then
                counter   <= (others => '0');    -- Reset counter after 500 ms
                led_level <= not led_level;       -- Toggle blink state: ON<->OFF at 1 Hz
            else
                counter <= counter + 1;   -- Increment 26-bit counter each clock cycle
            end if;
        end if;
    end process;

end architecture rtl;
