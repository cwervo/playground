#!/usr/bin/env tclsh8.6

# This Tcl script lists all keyboard devices in the /dev/input/ directory.

puts "Working ..."

proc udevadmProperties {device} {
    return [exec udevadm info --query=property --name=$device]
}

# Function to check if the device is a keyboard
proc isKeyboard {device} {
    set properties [udevadmProperties $device]
    if {$properties eq ""} {
    return false
    }
    # Check if device is a keyboard and not a mouse
    set isKeyboard [string match *ID_INPUT_KEYBOARD=1* $properties]
    set isMouse [string match *ID_INPUT_MOUSE=1* $properties]
    return [expr {$isKeyboard && !$isMouse}]
}

# Iterate over all event devices and check if they are keyboards
set allDevices [glob -nocomplain /dev/input/by-path/*]

foreach device $eventInputs {
    if {[is_keyboard $device]} {
        puts "-- Keyboard found: $device | [devpath $device]\n-------\n"
    }
}

puts "Done listing keyboards."