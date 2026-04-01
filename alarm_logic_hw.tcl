# -------------------------------------------------------------------------
# alarm_logic_hw.tcl
# Platform Designer (Qsys) Hardware Component Description
# Component: alarm_logic  version 1.0
#
# Registers alarm_avalon_wrapper.vhd as a Platform Designer component.
#
# Interfaces exposed:
#   clk            - clock_sink
#   reset          - reset_sink
#   sensor_inputs  - conduit_end  (temperature[15:0], light_level[9:0], motion)
#   alarm_outputs  - conduit_end  (5 alarm flag outputs to top-level / HPS IRQ)
#   hw_outputs     - conduit_end  (4 hardware drive signals to gpio_controller)
#   s0             - avalon_slave (threshold configuration registers)
# -------------------------------------------------------------------------

package require -exact qsys 16.0

# ---- Component metadata ----
set_module_property NAME            alarm_logic
set_module_property VERSION         1.0
set_module_property DISPLAY_NAME    "Alarm Logic & Threshold Comparator"
set_module_property DESCRIPTION     "Compares sensor values against HPS-configurable thresholds; drives LEDs and buzzer"
set_module_property AUTHOR          "Custom"
set_module_property GROUP           "Custom Peripherals"
set_module_property EDITABLE        true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property INTERNAL        false

# ---- Embedded software / DTS assignments ----
set_module_assignment embeddedsw.dts.compatible  "custom,alarm-logic"
set_module_assignment embeddedsw.dts.group       "alarm"
set_module_assignment embeddedsw.dts.vendor      "custom"

# ---- HDL files ----
add_fileset            QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property   QUARTUS_SYNTH TOP_LEVEL alarm_avalon_wrapper
add_fileset_file       alarm_logic.vhd          VHDL PATH ip/smart_home/alarm_logic.vhd
add_fileset_file       alarm_avalon_wrapper.vhd VHDL PATH ip/smart_home/alarm_avalon_wrapper.vhd TOP_LEVEL_FILE

add_fileset            SIM_VHDL SIM_VHDL "" ""
set_fileset_property   SIM_VHDL TOP_LEVEL alarm_avalon_wrapper
add_fileset_file       alarm_logic.vhd          VHDL PATH ip/smart_home/alarm_logic.vhd
add_fileset_file       alarm_avalon_wrapper.vhd VHDL PATH ip/smart_home/alarm_avalon_wrapper.vhd TOP_LEVEL_FILE

# -------------------------------------------------------------------------
# Interface: clk
# -------------------------------------------------------------------------
add_interface          clk clock end
set_interface_property clk clockRate 0
add_interface_port     clk clk clk Input 1

# -------------------------------------------------------------------------
# Interface: reset
# -------------------------------------------------------------------------
add_interface          reset reset end
set_interface_property reset associatedClock clk
set_interface_property reset synchronousEdges DEASSERT
add_interface_port     reset reset reset Input 1

# -------------------------------------------------------------------------
# Interface: sensor_inputs  (conduit - sensor data from bme280 / mcp3008)
#   temperature     : role=new_signal   direction=Input  width=16
#   light_level     : role=new_signal_1 direction=Input  width=10
#   motion_detected : role=new_signal_2 direction=Input  width=1
# -------------------------------------------------------------------------
add_interface          sensor_inputs conduit end
set_interface_property sensor_inputs associatedClock clk
set_interface_property sensor_inputs associatedReset ""
set_interface_property sensor_inputs EXPORT_OF ""

add_interface_port sensor_inputs temperature     new_signal   Input 16
add_interface_port sensor_inputs light_level     new_signal_1 Input 10
add_interface_port sensor_inputs motion_detected new_signal_2 Input 1

# -------------------------------------------------------------------------
# Interface: alarm_outputs  (conduit - exported alarm flags)
#   alarm_temp_high : role=new_signal   direction=Output  width=1
#   alarm_temp_low  : role=new_signal_1 direction=Output  width=1
#   alarm_light_low : role=new_signal_2 direction=Output  width=1
#   alarm_motion    : role=new_signal_3 direction=Output  width=1
#   alarm_critical  : role=new_signal_4 direction=Output  width=1
# -------------------------------------------------------------------------
add_interface          alarm_outputs conduit end
set_interface_property alarm_outputs associatedClock clk
set_interface_property alarm_outputs associatedReset ""
set_interface_property alarm_outputs EXPORT_OF ""

add_interface_port alarm_outputs alarm_temp_high new_signal   Output 1
add_interface_port alarm_outputs alarm_temp_low  new_signal_1 Output 1
add_interface_port alarm_outputs alarm_light_low new_signal_2 Output 1
add_interface_port alarm_outputs alarm_motion    new_signal_3 Output 1
add_interface_port alarm_outputs alarm_critical  new_signal_4 Output 1

# -------------------------------------------------------------------------
# Interface: hw_outputs  (conduit - drives gpio_controller alarm_override)
#   led_red_out    : role=new_signal   direction=Output  width=1
#   led_yellow_out : role=new_signal_1 direction=Output  width=1
#   led_green_out  : role=new_signal_2 direction=Output  width=1
#   buzzer_out     : role=new_signal_3 direction=Output  width=1
# -------------------------------------------------------------------------
add_interface          hw_outputs conduit end
set_interface_property hw_outputs associatedClock clk
set_interface_property hw_outputs associatedReset ""
set_interface_property hw_outputs EXPORT_OF ""

add_interface_port hw_outputs led_red_out    new_signal   Output 1
add_interface_port hw_outputs led_yellow_out new_signal_1 Output 1
add_interface_port hw_outputs led_green_out  new_signal_2 Output 1
add_interface_port hw_outputs buzzer_out     new_signal_3 Output 1

# -------------------------------------------------------------------------
# Interface: s0  (Avalon-MM slave - threshold configuration)
# 5 word-addressable registers
# -------------------------------------------------------------------------
add_interface          s0 avalon end
set_interface_property s0 associatedClock  clk
set_interface_property s0 associatedReset  reset
set_interface_property s0 readLatency      1
set_interface_property s0 writeWaitTime    0
set_interface_property s0 readWaitTime     1
set_interface_property s0 addressUnits     WORDS
set_interface_property s0 burstOnBurstBoundariesOnly false

add_interface_port s0 address     address     Input  3
add_interface_port s0 write       write       Input  1
add_interface_port s0 writedata   writedata   Input  32
add_interface_port s0 read        read        Input  1
add_interface_port s0 readdata    readdata    Output 32
add_interface_port s0 waitrequest waitrequest Output 1
