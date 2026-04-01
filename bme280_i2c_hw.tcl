# -------------------------------------------------------------------------
# bme280_i2c_hw.tcl
# Platform Designer (Qsys) Hardware Component Description
# Component: bme280_i2c  version 1.0
#
# This file registers the bme280_avalon_wrapper.vhd as a Platform Designer
# component named "bme280_i2c".  It must be placed in the same directory
# as bme280_avalon_wrapper.vhd (i.e. your Quartus project folder) and the
# project directory must be listed in Platform Designer's IP search path.
#
# Interfaces exposed:
#   clk          - clock_sink
#   reset        - reset_sink
#   s0           - avalon_slave  (HPS lightweight bridge slave)
#   i2c          - conduit_end   (SDA bidir, SCL inout)
#   sensor_data  - conduit_end   (temp_raw[19:0] output)
# -------------------------------------------------------------------------

package require -exact qsys 16.0

# ---- Component metadata ----
set_module_property NAME            bme280_i2c
set_module_property VERSION         1.0
set_module_property DISPLAY_NAME    "BME280 I2C Temperature/Pressure/Humidity Controller"
set_module_property DESCRIPTION     "Reads BME280 sensor via I2C and exposes raw ADC values over Avalon-MM"
set_module_property AUTHOR          "Custom"
set_module_property GROUP           "Custom Peripherals"
set_module_property EDITABLE        true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property INTERNAL        false

# ---- Embedded software / DTS assignments ----
set_module_assignment embeddedsw.dts.compatible  "custom,bme280-i2c"
set_module_assignment embeddedsw.dts.group       "sensors"
set_module_assignment embeddedsw.dts.vendor      "custom"

# ---- HDL files ----
add_fileset            QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property   QUARTUS_SYNTH TOP_LEVEL bme280_avalon_wrapper
add_fileset_file       i2c_master.vhd            VHDL PATH ip/smart_home/i2c_master.vhd
add_fileset_file       bme280_controller.vhd     VHDL PATH ip/smart_home/bme280_controller.vhd
add_fileset_file       bme280_avalon_wrapper.vhd VHDL PATH ip/smart_home/bme280_avalon_wrapper.vhd TOP_LEVEL_FILE

add_fileset            SIM_VHDL SIM_VHDL "" ""
set_fileset_property   SIM_VHDL TOP_LEVEL bme280_avalon_wrapper
add_fileset_file       i2c_master.vhd            VHDL PATH ip/smart_home/i2c_master.vhd
add_fileset_file       bme280_controller.vhd     VHDL PATH ip/smart_home/bme280_controller.vhd
add_fileset_file       bme280_avalon_wrapper.vhd VHDL PATH ip/smart_home/bme280_avalon_wrapper.vhd TOP_LEVEL_FILE

# -------------------------------------------------------------------------
# Interface: clk  (clock sink)
# -------------------------------------------------------------------------
add_interface          clk clock end
set_interface_property clk clockRate 0
add_interface_port     clk clk clk Input 1

# -------------------------------------------------------------------------
# Interface: reset  (reset sink, synchronous de-assert)
# -------------------------------------------------------------------------
add_interface          reset reset end
set_interface_property reset associatedClock clk
set_interface_property reset synchronousEdges DEASSERT
add_interface_port     reset reset reset Input 1

# -------------------------------------------------------------------------
# Interface: s0  (Avalon-MM slave)
# 5 word-addressable registers -> addressSpan = 5 words = 20 bytes
# -------------------------------------------------------------------------
add_interface          s0 avalon end
set_interface_property s0 associatedClock   clk
set_interface_property s0 associatedReset   reset
set_interface_property s0 readLatency       1
set_interface_property s0 writeWaitTime     0
set_interface_property s0 readWaitTime      1
set_interface_property s0 addressUnits      WORDS
set_interface_property s0 burstOnBurstBoundariesOnly false

add_interface_port s0 address     address     Input   3
add_interface_port s0 write       write       Input   1
add_interface_port s0 writedata   writedata   Input   32
add_interface_port s0 read        read        Input   1
add_interface_port s0 readdata    readdata    Output  32
add_interface_port s0 waitrequest waitrequest Output  1

# -------------------------------------------------------------------------
# Interface: i2c  (conduit - physical I2C pins)
#   sda : role=new_signal   direction=Bidir  width=1
#   scl : role=new_signal_1 direction=Bidir  width=1  (open-drain inout)
# -------------------------------------------------------------------------
add_interface          i2c conduit end
set_interface_property i2c associatedClock clk
set_interface_property i2c associatedReset ""
set_interface_property i2c EXPORT_OF ""

add_interface_port i2c sda new_signal   Bidir 1
add_interface_port i2c scl new_signal_1 Bidir 1

# -------------------------------------------------------------------------
# Interface: sensor_data  (conduit - routes temp_raw to alarm_logic)
#   temp_raw : role=new_signal  direction=Output  width=20
# -------------------------------------------------------------------------
add_interface          sensor_data conduit end
set_interface_property sensor_data associatedClock clk
set_interface_property sensor_data associatedReset ""
set_interface_property sensor_data EXPORT_OF ""

add_interface_port sensor_data temp_raw new_signal Output 20
