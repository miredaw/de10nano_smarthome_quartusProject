# -------------------------------------------------------------------------
# mcp3008_spi_adc_hw.tcl
# Platform Designer (Qsys) Hardware Component Description
# Component: mcp3008_spi_adc  version 1.0
#
# This file registers the mcp3008_avalon_wrapper.vhd as a Platform Designer
# component named "mcp3008_spi_adc".  Place in your Quartus project folder
# alongside the VHDL files.
#
# Interfaces exposed:
#   clk          - clock_sink
#   reset        - reset_sink
#   s0           - avalon_slave  (HPS lightweight bridge slave)
#   spi          - conduit_end   (CLK, MOSI out; MISO in; CS_N out)
#   sensor_data  - conduit_end   (light_level[9:0] output)
# -------------------------------------------------------------------------

package require -exact qsys 16.0

# ---- Component metadata ----
set_module_property NAME            mcp3008_spi_adc
set_module_property VERSION         1.0
set_module_property DISPLAY_NAME    "MCP3008 SPI ADC Controller (8-ch 10-bit)"
set_module_property DESCRIPTION     "Reads MCP3008 ADC channels via SPI with moving-average filter"
set_module_property AUTHOR          "Custom"
set_module_property GROUP           "Custom Peripherals"
set_module_property EDITABLE        true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property INTERNAL        false

# ---- Embedded software / DTS assignments ----
set_module_assignment embeddedsw.dts.compatible  "custom,mcp3008-spi-adc"
set_module_assignment embeddedsw.dts.group       "sensors"
set_module_assignment embeddedsw.dts.vendor      "custom"

# ---- HDL files ----
add_fileset            QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property   QUARTUS_SYNTH TOP_LEVEL mcp3008_avalon_wrapper
add_fileset_file       spi_adc_mcp3008.vhd      VHDL PATH ip/smart_home/spi_adc_mcp3008.vhd
add_fileset_file       multi_channel_adc.vhd    VHDL PATH ip/smart_home/multi_channel_adc.vhd
add_fileset_file       mcp3008_avalon_wrapper.vhd VHDL PATH ip/smart_home/mcp3008_avalon_wrapper.vhd TOP_LEVEL_FILE

add_fileset            SIM_VHDL SIM_VHDL "" ""
set_fileset_property   SIM_VHDL TOP_LEVEL mcp3008_avalon_wrapper
add_fileset_file       spi_adc_mcp3008.vhd      VHDL PATH ip/smart_home/spi_adc_mcp3008.vhd
add_fileset_file       multi_channel_adc.vhd    VHDL PATH ip/smart_home/multi_channel_adc.vhd
add_fileset_file       mcp3008_avalon_wrapper.vhd VHDL PATH ip/smart_home/mcp3008_avalon_wrapper.vhd TOP_LEVEL_FILE

# -------------------------------------------------------------------------
# Interface: clk  (clock sink)
# -------------------------------------------------------------------------
add_interface          clk clock end
set_interface_property clk clockRate 0
add_interface_port     clk clk clk Input 1

# -------------------------------------------------------------------------
# Interface: reset  (reset sink)
# -------------------------------------------------------------------------
add_interface          reset reset end
set_interface_property reset associatedClock clk
set_interface_property reset synchronousEdges DEASSERT
add_interface_port     reset reset reset Input 1

# -------------------------------------------------------------------------
# Interface: s0  (Avalon-MM slave)
# 5 word-addressable registers
# -------------------------------------------------------------------------
add_interface          s0 avalon end
set_interface_property s0 associatedClock   clk
set_interface_property s0 associatedReset   reset
set_interface_property s0 readLatency       1
set_interface_property s0 writeWaitTime     0
set_interface_property s0 readWaitTime      1
set_interface_property s0 addressUnits      WORDS
set_interface_property s0 burstOnBurstBoundariesOnly false

add_interface_port s0 address     address     Input  3
add_interface_port s0 write       write       Input  1
add_interface_port s0 writedata   writedata   Input  32
add_interface_port s0 read        read        Input  1
add_interface_port s0 readdata    readdata    Output 32
add_interface_port s0 waitrequest waitrequest Output 1

# -------------------------------------------------------------------------
# Interface: spi  (conduit - physical SPI pins)
#   spi_clk  : role=new_signal   direction=Output  width=1
#   spi_mosi : role=new_signal_1 direction=Output  width=1
#   spi_miso : role=new_signal_2 direction=Input   width=1
#   spi_cs_n : role=new_signal_3 direction=Output  width=1
# -------------------------------------------------------------------------
add_interface          spi conduit end
set_interface_property spi associatedClock clk
set_interface_property spi associatedReset ""
set_interface_property spi EXPORT_OF ""

add_interface_port spi spi_clk  new_signal   Output 1
add_interface_port spi spi_mosi new_signal_1 Output 1
add_interface_port spi spi_miso new_signal_2 Input  1
add_interface_port spi spi_cs_n new_signal_3 Output 1

# -------------------------------------------------------------------------
# Interface: sensor_data  (conduit - routes light_level to alarm_logic)
#   light_level : role=new_signal  direction=Output  width=10
# -------------------------------------------------------------------------
add_interface          sensor_data conduit end
set_interface_property sensor_data associatedClock clk
set_interface_property sensor_data associatedReset ""
set_interface_property sensor_data EXPORT_OF ""

add_interface_port sensor_data light_level new_signal Output 10
