# -------------------------------------------------------------------------
# gpio_controller_hw.tcl
# Platform Designer (Qsys) Hardware Component Description
# Component: gpio_controller  version 1.0
#
# Registers gpio_avalon_wrapper.vhd as a Platform Designer component.
#
# Interfaces exposed:
#   clk            - clock_sink
#   reset          - reset_sink
#   s0             - avalon_slave
#   gpio_in        - conduit_end  (pir1, pir2, button[3:0])
#   alarm_override - conduit_end  (alarm led/buzzer inputs from alarm_logic)
#   gpio_out       - conduit_end  (led_red, led_green, led_yellow, buzzer)
# -------------------------------------------------------------------------

package require -exact qsys 16.0

# ---- Component metadata ----
set_module_property NAME            gpio_controller
set_module_property VERSION         1.0
set_module_property DISPLAY_NAME    "GPIO Controller (PIR, Buttons, LEDs, Buzzer)"
set_module_property DESCRIPTION     "Debounces PIR sensors and buttons; drives LEDs and buzzer with alarm override"
set_module_property AUTHOR          "Custom"
set_module_property GROUP           "Custom Peripherals"
set_module_property EDITABLE        true
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property INTERNAL        false

# ---- Embedded software / DTS assignments ----
set_module_assignment embeddedsw.dts.compatible  "custom,gpio-controller"
set_module_assignment embeddedsw.dts.group       "gpio"
set_module_assignment embeddedsw.dts.vendor      "custom"

# ---- HDL files ----
add_fileset            QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property   QUARTUS_SYNTH TOP_LEVEL gpio_avalon_wrapper
add_fileset_file       gpio_controller.vhd     VHDL PATH ip/smart_home/gpio_controller.vhd
add_fileset_file       gpio_avalon_wrapper.vhd VHDL PATH ip/smart_home/gpio_avalon_wrapper.vhd TOP_LEVEL_FILE

add_fileset            SIM_VHDL SIM_VHDL "" ""
set_fileset_property   SIM_VHDL TOP_LEVEL gpio_avalon_wrapper
add_fileset_file       gpio_controller.vhd     VHDL PATH ip/smart_home/gpio_controller.vhd
add_fileset_file       gpio_avalon_wrapper.vhd VHDL PATH ip/smart_home/gpio_avalon_wrapper.vhd TOP_LEVEL_FILE

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
# Interface: s0  (Avalon-MM slave)
# 4 word-addressable registers
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

# -------------------------------------------------------------------------
# Interface: gpio_in  (conduit - sensor/button inputs)
#   pir1_in   : role=new_signal   direction=Input  width=1
#   pir2_in   : role=new_signal_1 direction=Input  width=1
#   button_in : role=new_signal_2 direction=Input  width=4
# -------------------------------------------------------------------------
add_interface          gpio_in conduit end
set_interface_property gpio_in associatedClock clk
set_interface_property gpio_in associatedReset ""
set_interface_property gpio_in EXPORT_OF ""

add_interface_port gpio_in pir1_in   new_signal   Input 1
add_interface_port gpio_in pir2_in   new_signal_1 Input 1
add_interface_port gpio_in button_in new_signal_2 Input 4

# -------------------------------------------------------------------------
# Interface: alarm_override  (conduit - alarm_logic drives outputs directly)
#   alarm_led_red    : role=new_signal   direction=Input  width=1
#   alarm_led_yellow : role=new_signal_1 direction=Input  width=1
#   alarm_led_green  : role=new_signal_2 direction=Input  width=1
#   alarm_buzzer     : role=new_signal_3 direction=Input  width=1
# -------------------------------------------------------------------------
add_interface          alarm_override conduit end
set_interface_property alarm_override associatedClock clk
set_interface_property alarm_override associatedReset ""
set_interface_property alarm_override EXPORT_OF ""

add_interface_port alarm_override alarm_led_red    new_signal   Input 1
add_interface_port alarm_override alarm_led_yellow new_signal_1 Input 1
add_interface_port alarm_override alarm_led_green  new_signal_2 Input 1
add_interface_port alarm_override alarm_buzzer     new_signal_3 Input 1

# -------------------------------------------------------------------------
# Interface: gpio_out  (conduit - LED and buzzer outputs)
#   led_red    : role=new_signal   direction=Output  width=1
#   led_green  : role=new_signal_1 direction=Output  width=1
#   led_yellow : role=new_signal_2 direction=Output  width=1
#   buzzer     : role=new_signal_3 direction=Output  width=1
# -------------------------------------------------------------------------
add_interface          gpio_out conduit end
set_interface_property gpio_out associatedClock clk
set_interface_property gpio_out associatedReset ""
set_interface_property gpio_out EXPORT_OF ""

add_interface_port gpio_out led_red    new_signal   Output 1
add_interface_port gpio_out led_green  new_signal_1 Output 1
add_interface_port gpio_out led_yellow new_signal_2 Output 1
add_interface_port gpio_out buzzer     new_signal_3 Output 1
