# 🔷 Smart Home Monitor — FPGA Design (Quartus / VHDL)

Part of the **IoT Smart Home Monitor** project built on a DE10-Nano (Intel Cyclone V SoC) for the *Electronics for Embedded Systems* course at Politecnico di Torino (A.Y. 2025–2026).

This component contains the full FPGA design: five custom VHDL IP blocks integrated via Intel Platform Designer (Qsys), all accessible by the HPS ARM processor through the Lightweight AXI Bridge.

---

## 📋 Table of Contents

- [System Architecture](#system-architecture)
- [Peripheral Address Map](#peripheral-address-map)
- [VHDL IP Blocks](#vhdl-ip-blocks)
- [JP1 Pin Assignments](#jp1-pin-assignments)
- [Build Instructions](#build-instructions)
- [Programming the FPGA](#programming-the-fpga)
- [Design Notes](#design-notes)

---

## 🏗️ System Architecture

```
🔌 JP1 / External Sensors
        │
   ┌────┴────────────────────────────────────────────┐
   │            ⚡ FPGA Fabric (50 MHz)               │
   │                                                  │
   │  ┌──────────────┐   ┌──────────────────────┐    │
   │  │🌡️ bme280_ctrl │   │📊 multi_channel_adc   │    │
   │  │  (I²C master)│   │   (SPI MCP3008)       │    │
   │  └──────┬───────┘   └──────────┬───────────┘    │
   │         │                      │                  │
   │  ┌──────▼──────────────────────▼───────────┐    │
   │  │         🚨 alarm_logic                   │    │
   │  │   (threshold comparator, LED/buzzer)     │    │
   │  └──────────────────────────────────────────┘    │
   │                                                  │
   │  ┌──────────────┐   ┌──────────────────────┐    │
   │  │🚶 gpio_ctrl   │   │📱 uart_transceiver    │    │
   │  │(PIR, buttons,│   │(SIM800L, 19200 baud)  │    │
   │  │ LEDs, buzzer)│   └──────────────────────┘    │
   │  └──────────────┘                                │
   │                                                  │
   │  ┌──────────────────────────────────────────┐    │
   │  │  🔗 Avalon-MM Interconnect (Qsys)         │    │
   │  └──────────────────────┬───────────────────┘    │
   └─────────────────────────┼────────────────────────┘
                             │ Lightweight AXI Bridge
                        🖥️ HPS ARM (0xFF200000)
```

---

## 🗺️ Peripheral Address Map

Base address: **`0xFF200000`** (Lightweight HPS-to-FPGA AXI Bridge)

| Offset | Span | Component | Description |
|--------|------|-----------|-------------|
| `0x000` | 32 B | `bme280_i2c_0` | 🌡️ BME280 temperature / pressure / humidity |
| `0x020` | 32 B | `mcp3008_spi_0` | 📊 MCP3008 ADC (light, heating, sound) |
| `0x040` | 32 B | `gpio_controller` | 🚶 PIR sensors, buttons, LEDs, buzzer |
| `0x060` | 32 B | `alarm_logic_0` | 🚨 Threshold comparator + alarm flags |
| `0x080` | 32 B | `uart_sim800l_0` | 📱 UART for SIM800L (GSM/SMS) |
| `0x2000` | 8 KB | `onchip_memory` | 💾 Event log (256 × 32-byte records) |

---

## 🔷 VHDL IP Blocks

All custom IP blocks are located in `ip/smart_home/`.

---

### 🌡️ `bme280_controller.vhd` + `i2c_master.vhd`

- Full I²C master to communicate with the Bosch BME280 environmental sensor
- Wired to FPGA GPIO pins (PIN_V12 = SDA, PIN_E8 = SCL) — **not HPS I²C**
- Reads 26 factory calibration registers on startup, then polls measurement registers continuously
- Outputs 20-bit raw ADC values for temperature, pressure, and humidity
- **🔁 Auto-recovery**: if the I²C bus enters an error state, automatically retries after a 5-second timeout (250,000,000 cycles @ 50 MHz)
- Status register exposed to HPS: `data_valid` bit and `error` bit

**Avalon-MM registers (offset `0x000`):**

| Word | Bits | Field |
|------|------|-------|
| 0 | [31:0] | Control (bit 0 = enable) |
| 1 | [19:0] | Raw temperature ADC |
| 2 | [19:0] | Raw pressure ADC |
| 3 | [19:0] | Raw humidity ADC |
| 4 | [1:0] | Status: bit0=data_valid, bit1=error |

---

### 📊 `multi_channel_adc.vhd` + `spi_adc_mcp3008.vhd`

- SPI master for MCP3008 (8-channel, 10-bit ADC) at up to 1 MHz SCK
- Reads three channels: CH0 = 💡 light, CH1 = 🔥 heating element, CH2 = 🔊 sound level
- Moving-average filter on each channel output
- `data_valid` signal is **latched** (not a one-cycle pulse) — safe for HPS polling at any rate

**Avalon-MM registers (offset `0x020`):**

| Word | Bits | Field |
|------|------|-------|
| 0 | [31:0] | Control (bit 0 = start conversion) |
| 1 | [9:0] | CH0 — 💡 light level (0–1023) |
| 2 | [9:0] | CH1 — 🔥 heating level (0–1023) |
| 3 | [9:0] | CH2 — 🔊 sound level (0–1023) |
| 4 | [0] | data_valid |

---

### 🚶 `gpio_controller.vhd`

- **Inputs**: 2 PIR motion sensors (active-high), 4 push-buttons (active-low with internal pull-up)
- **Outputs**: 🔴 Red LED, 🟢 Green LED, 🟡 Yellow LED, 🔔 Buzzer (driven by alarm_logic)
- 50 ms debouncing on button inputs

**Avalon-MM registers (offset `0x040`):**

| Word | Bits | Field |
|------|------|-------|
| 0 | [3:0] | Button states (1 = pressed) |
| 1 | [1:0] | PIR states (bit0=PIR1, bit1=PIR2) |
| 2 | [3:0] | LED/buzzer override (for HPS direct control) |

---

### 🚨 `alarm_logic.vhd`

The core real-time decision engine. Compares live sensor values against configurable thresholds **entirely in hardware** — zero HPS polling latency.

**Alarm conditions:**

| Alarm | Condition | Hardware Output |
|-------|-----------|-----------------|
| `TEMP_HIGH` | Temperature raw > `temp_high_thresh` | 🔴 Red LED on, 🔔 buzzer pulses |
| `TEMP_LOW` | Temperature raw < `temp_low_thresh` | 🔴 Red LED on, 🔔 buzzer pulses |
| `LIGHT_LOW` | Light ADC < `light_thresh` | (flag only) |
| `MOTION` | PIR1 or PIR2 high (5 s latch) | 🟡 Yellow LED on |
| `CRITICAL` | TEMP_HIGH or TEMP_LOW active | 🔔 Buzzer: 250 ms ON / 250 ms OFF |
| All clear | No alarms active | 🟢 Green LED on |

**Avalon-MM registers (offset `0x060`):**

| Word | Bits | Field |
|------|------|-------|
| 0 | [15:0] | ⬆️ Temperature high threshold (raw) — writable by HPS |
| 1 | [15:0] | ⬇️ Temperature low threshold (raw) — writable by HPS |
| 2 | [9:0] | 💡 Light low threshold (ADC counts) — writable by HPS |
| 3 | [4:0] | 🚨 Alarm flags (read-only): TEMP_HIGH, TEMP_LOW, LIGHT_LOW, MOTION, CRITICAL |

---

### 📱 `uart_transceiver.vhd`

- Altera/Intel UART compatible register interface
- Configured at **19200 baud** (SIM800L default)
- Direct MMIO TX/RX from HPS — no Linux `/dev/ttyS` driver needed
- Connected to JP1 pins 19–20 (3.3 V compatible levels)

---

## 🔌 JP1 Pin Assignments

All peripherals connect to **JP1 (GPIO_0)** on the DE10-Nano. All signals are **3.3 V logic**.

| JP1 Pins | Signal | FPGA Pin(s) | Device | Notes |
|----------|--------|-------------|--------|-------|
| 1 / 2 | 🌡️ BME280 SDA / SCL | PIN_V12 / PIN_E8 | Waveshare BME280 | Built-in 4.7 kΩ pull-ups on module |
| 3 / 4 / 5 / 6 | 📊 SPI CLK / MOSI / MISO / CS_N | PIN_W12 / D11 / D8 / AH13 | MCP3008 ADC | 3.3 V supply from pin 30 |
| 7 / 8 | 🚶 PIR1 / PIR2 | PIN_AF7 / AH14 | HC-SR501 PIR | Active-high; 5V powered from pin 11 |
| 9–14 | 🔘 BTN0–BTN3 | PIN_AF4, AH3, AD5, AG14 | Push-buttons | Active-low; internal pull-ups in FPGA |
| 15–18 | 💡 LED_R / LED_G / LED_Y / Buzzer | PIN_AE23, AE6, AD23, AE24 | LEDs + buzzer | 330 Ω series resistors on LEDs |
| 19 / 20 | 📱 SIM800L TX / RX | PIN_D12 / AD20 | SIM800L EVB | 19200 baud; onboard LDO on EVB |
| 21 / 22 | 📡 ESP32 TX / RX | PIN_C12 / AD17 | ESP32 module | HPS UART1, 115200 baud |
| 29 / 30 | ⚡ GND / 3.3 V | — | Power | Sensor supply |

---

## 🔨 Build Instructions

### Prerequisites

- Intel Quartus Prime 20.1 or later (Standard or Lite edition)
- Device support package: **Cyclone V**
- Platform Designer (Qsys) integrated in Quartus

### Compile

1. Open `DE10_NANO_SoC_GHRD.qpf` in Quartus Prime.
2. Verify the Qsys system is up to date: **Tools → Platform Designer**, then regenerate if prompted.
3. Run full compilation: **Processing → Start Compilation** (`Ctrl+L`).
4. Bitstream outputs:
   - `output_files/DE10_NANO_SoC_GHRD.sof` — JTAG programming file
   - `soc_system.rbf` — Linux boot-time raw binary format

---

## 📲 Programming the FPGA

### Via JTAG (development) 🛠️

```bash
quartus_pgm -c USB-Blaster -m JTAG -o "p;output_files/DE10_NANO_SoC_GHRD.sof"
```

Or use **Tools → Programmer** in the Quartus GUI.

### Via Linux at Boot (production) 🚀

Copy `soc_system.rbf` to the FAT partition of the DE10-Nano SD card. The HPS preloader / U-Boot will automatically configure the FPGA from the `.rbf` file on every boot.

```bash
# On DE10-Nano Linux:
cp soc_system.rbf /media/sdcard/
```

---

## 📝 Design Notes

- ⚡ **Clock**: All custom IP clocked from the 50 MHz system clock (`CLOCK_50`).
- 🔄 **Reset**: Active-low synchronous reset driven from HPS warm reset.
- 🔗 **Avalon-MM**: All IP blocks use 32-bit word-addressed Avalon-MM slave interfaces with 4-byte alignment.
- ✅ **data_valid pattern**: All sensor controllers latch `data_valid` as a persistent flag (not a one-cycle pulse), so the HPS can safely poll at its own rate without missing an update.
- 🏎️ **Alarm autonomy**: The alarm_logic block drives LED and buzzer outputs combinationally — no HPS intervention required for physical alerts. This guarantees deterministic response time regardless of Linux scheduling.
