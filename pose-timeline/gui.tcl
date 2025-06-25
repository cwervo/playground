#!/usr/bin/env tclsh
package require Tk

# --- Global Variables ---
set video_file_path ""
set status_message "Idle"
set app_dir [file dirname [info script]]
set processor_executable [file join $app_dir "build" "PoseTimeline"]

# --- UI Elements ---
wm title . "Pose Timeline Processor"
wm geometry . 400x200

# Frame for video selection
labelframe .video_frame -text "Video Input"
pack .video_frame -fill x -padx 5 -pady 5

label .video_frame.path_label_desc -text "Selected Video:"
entry .video_frame.path_entry -textvariable video_file_path -state readonly -width 40
button .video_frame.browse_button -text "Browse..." -command select_video_file

grid .video_frame.path_label_desc -row 0 -column 0 -sticky w -padx 5 -pady 2
grid .video_frame.path_entry     -row 1 -column 0 -sticky ew -padx 5 -pady 2
grid .video_frame.browse_button  -row 1 -column 1 -sticky e -padx 5 -pady 2
grid columnconfigure .video_frame 0 -weight 1

# Frame for controls and status
labelframe .controls_frame -text "Controls"
pack .controls_frame -fill x -padx 5 -pady 5

button .controls_frame.process_button -text "Process Video" -command process_video
label .controls_frame.status_label -textvariable status_message -relief sunken -anchor w

pack .controls_frame.process_button -pady 5
pack .controls_frame.status_label -fill x -pady 5 -padx 2

# --- Procedures ---

# Procedure to select a video file
proc select_video_file {} {
    global video_file_path
    set types {
        {"Video Files" {".mp4" ".avi" ".mov" ".mkv"}}
        {"All Files" {"*"}}
    }
    set filename [tk_getOpenFile -filetypes $types -title "Select Video File"]
    if {$filename ne ""} {
        set video_file_path $filename
    }
}

# Procedure to run the C++ video processor
proc process_video {} {
    global video_file_path status_message processor_executable

    if {$video_file_path eq ""} {
        tk_messageBox -icon warning -type ok -title "No Video Selected" -message "Please select a video file first."
        return
    }

    if {![file exists $processor_executable]} {
        tk_messageBox -icon error -type ok -title "Processor Not Found" -message "Error: The processor executable was not found at:\n$processor_executable\nPlease build the C++ project first."
        return
    }

    # Update status and disable button
    set status_message "Processing: [file tail $video_file_path]..."
    .controls_frame.process_button configure -state disabled
    update idletasks

    # Ensure output directories are relative to where the script is run or a fixed location
    # The C++ app already handles creating subdirs in processed-videos based on video name
    set base_output_dir "processed-videos"
    if {![file isdirectory $base_output_dir]} {
        file mkdir $base_output_dir
    }

    # Asynchronously execute the C++ backend
    # Using 'catch' to get output and error code
    set cmd [list $processor_executable $video_file_path]
    puts "Executing: $cmd"

    # Open a pipe to capture stdout and stderr
    set pipe [open "| $cmd" r]
    fconfigure $pipe -blocking 0 -buffering line

    # Setup a file event to read from the pipe without blocking the GUI
    fileevent $pipe readable [list read_pipe_output $pipe]
}

proc read_pipe_output {pipe} {
    global status_message video_file_path

    if {[eof $pipe]} {
        # Command finished
        catch {close $pipe} result
        if {[lindex $result 0] == 0} { ;# Check if close was successful (exit code 0 from child implies success)
            set status_message "Done processing: [file tail $video_file_path]."
            tk_messageBox -icon info -type ok -title "Processing Complete" -message "Video processing finished for\n[file tail $video_file_path]"
        } else {
            set status_message "Error processing: [file tail $video_file_path]. Check console."
            tk_messageBox -icon error -type ok -title "Processing Error" -message "An error occurred while processing the video. See console for details."
            puts "Error Output:\n$result"
        }
        .controls_frame.process_button configure -state normal
    } else {
        # Read available output
        set line [gets $pipe]
        if {$line ne ""} {
            puts "Processor: $line" ; # Print processor output to console
            # Optionally update GUI with specific progress if processor provides it
            # For now, just keep the "Processing..." message
        }
    }
}


# --- Initial State ---
# Check if processor exists on startup (optional, for user feedback)
if {![file exists $processor_executable]} {
    set status_message "Processor not found. Please build C++ project."
}

# Start the Tk event loop
tkwait visibility .
puts "Pose Timeline GUI started."
puts "Processor executable expected at: $processor_executable"
puts "Ensure the C++ project is built (cd pose-timeline/build && cmake .. && make)"
focus .
