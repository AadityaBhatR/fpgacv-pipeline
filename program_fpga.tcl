open_hw_manager
connect_hw_server -allow_non_jtag
if {[llength [get_hw_targets]] == 0} {
    puts "NO_HARDWARE_TARGET_FOUND"
    close_hw_manager
    exit 1
}
open_hw_target
set hw_device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE {Camera.runs/impl_1/Top.bit} $hw_device
program_hw_devices $hw_device
refresh_hw_device $hw_device
puts "PROGRAMMING_COMPLETED_SUCCESSFULLY"
close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
