#!/usr/bin/env tclsh

if {[llength $argv] < 1 || [llength $argv] > 3} {
    puts "Usage: [info script] <gif_path> [strip_length] [--local]"
    puts "  <gif_path>: Path to the input GIF file."
    puts "  [strip_length]: Optional. The desired length (number of frames) of the horizontal strip. Defaults to all frames."
    puts "  [--local]: Optional flag. If present, the output strip will be saved in the current working directory."
    puts "             Otherwise, it will be saved alongside the input GIF."
    exit 1
}

set gif_path [lindex $argv 0]
set strip_length "all"
set local_output 0

if {[llength $argv] >= 2} {
    if {[lindex $argv 1] eq "--local"} {
        set local_output 1
    } else {
        set strip_length [lindex $argv 1]
        if {[llength $argv] == 3 && [lindex $argv 2] eq "--local"} {
            set local_output 1
        } elseif {[llength $argv] == 3 && !([lindex $argv 2] eq "--local")} {
            puts "Error: Invalid argument '[lindex $argv 2]'."
            exit 1
        }
    }
}

set output_name_base [file rootname $gif_path]_strip.png
set output_path ""

if {$local_output} {
    set output_path "./$output_name_base"
} else {
    set output_path [file join [file dirname $gif_path] $output_name_base]
}

set frames_dir [file tempfile gif2strip_frames]
file mkdir $frames_dir

if {![file exists $gif_path]} {
    puts "Error: GIF file not found at '$gif_path'."
    file delete -force -recursive $frames_dir
    exit 1
}

# Get GIF frame count using ImageMagick's identify
set identify_result [catch {exec identify -format "%n" $gif_path} frame_count]
if {$identify_result != 0 || ![string is integer -strict $frame_count] || $frame_count < 1} {
    puts "Error: Could not determine frame count of GIF: $frame_count"
    file delete -force -recursive $frames_dir
    exit 1
}

puts "GIF Path: '$gif_path'"
puts "Strip Length: '$strip_length'"
puts "Output Path: '$output_path'"
puts "Frame Count: '$frame_count'"
puts "Temporary frames directory: '$frames_dir'"

set success 0

if {$strip_length eq "all"} {
    puts "Creating a horizontal strip of all $frame_count frames."
    set convert_result [catch {exec convert $gif_path [file join $frames_dir "frame-%03d.png"]} convert_output]
    if {$convert_result == 0} {
        set montage_result [catch {exec montage [file join $frames_dir "frame-*.png"] -tile x1 -geometry +0+0 $output_path} montage_output]
        if {$montage_result == 0} {
            set success 1
        } else {
            puts "Error during montage: $montage_output"
        }
    } else {
        puts "Error during frame extraction: $convert_output"
    }
} else {
    if {[string is integer -strict $strip_length] && $strip_length > 0} {
        if {$strip_length > $frame_count} {
            puts "Warning: Requested strip length ($strip_length) is greater than the number of frames in the GIF ($frame_count). Using all frames."
            set convert_result [catch {exec convert $gif_path [file join $frames_dir "frame-%03d.png"]} convert_output]
            if {$convert_result == 0} {
                set montage_result [catch {exec montage [file join $frames_dir "frame-*.png"] -tile x1 -geometry +0+0 $output_path} montage_output]
                if {$montage_result == 0} {
                    set success 1
                } else {
                    puts "Error during montage: $montage_output"
                }
            } else {
                puts "Error during frame extraction: $convert_output"
            }
        } else {
            puts "Creating a horizontal strip of the first $strip_length frames."
            set frame_range "[expr 0] - [expr $strip_length - 1]"
            set convert_result [catch {exec convert $gif_path"\[$frame_range\]" [file join $frames_dir "frame-%03d.png"]} convert_output]
            if {$convert_result == 0} {
                set montage_result [catch {exec montage [file join $frames_dir "frame-*.png"] -tile x1 -geometry +0+0 $output_path} montage_output]
                if {$montage_result == 0} {
                    set success 1
                } else {
                    puts "Error during montage: $montage_output"
                }
            } else {
                puts "Error during frame extraction: $convert_output"
            }
        }
    } else {
        puts "Error: Strip length must be a positive integer or 'all'."
    }
}

if {$success} {
    puts "Successfully created '$output_path'."
} else {
    puts "Error: Failed to create the horizontal strip."
}

file delete -force -recursive $frames_dir

exit 0
