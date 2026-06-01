# Tcl/Tk Sprite Sheet Editor
# Allows opening an image, selecting a sprite area, previewing animation,
# and saving the selected slice.

package require Tk

# --- Application State Namespace ---
# Using a namespace to keep variables organized and avoid global conflicts.
namespace eval app_state {
    # File handling
    variable filepath ""
    variable image_data ""

    # Selection coordinates
    variable select_x1 0
    variable select_y1 0
    variable select_x2 0
    variable select_y2 0
    variable is_selecting 0

    # Animation state
    variable is_animating 0
    variable current_frame 0
    variable animation_id ""
    variable preview_image ""
}

# --- UI Setup ---
proc setup_ui {} {
    wm title . "Tcl/Tk Sprite Sheet Editor"
    wm minsize . 600 400

    # --- Main layout frames ---
    # Using the grid geometry manager for a structured layout.
    set controls_frame [ttk::frame .controls]
    set main_frame [ttk::frame .main]
    set status_frame [ttk::frame .status -padding 2]

    grid .controls -row 0 -column 0 -sticky "ew"
    grid .main -row 1 -column 0 -sticky "nsew"
    grid .status -row 2 -column 0 -sticky "ew"

    # Allow the main content area to expand when the window is resized.
    grid rowconfigure . 1 -weight 1
    grid columnconfigure . 0 -weight 1

    # --- Controls Frame Content ---
    ttk::button $controls_frame.open -text "Open Image" -command open_image
    ttk::separator $controls_frame.sep1 -orient vertical
    ttk::label $controls_frame.frames_label -text "Frames (Cols):"
    ttk::entry $controls_frame.frames_entry -width 5 -textvariable ::FRAMES
    set ::FRAMES 4
    ttk::label $controls_frame.rows_label -text "Rows:"
    ttk::entry $controls_frame.rows_entry -width 5 -textvariable ::ROWS
    set ::ROWS 1
    ttk::separator $controls_frame.sep2 -orient vertical
    ttk::button $controls_frame.play -text "▶ Play" -command toggle_animation
    ttk::button $controls_frame.save -text "Save Slice" -command save_slice

    pack $controls_frame.open -side left -padx 5 -pady 5
    pack $controls_frame.sep1 -side left -fill y -padx 5 -pady 5
    pack $controls_frame.frames_label -side left -pady 5
    pack $controls_frame.frames_entry -side left -pady 5 -padx {0 5}
    pack $controls_frame.rows_label -side left -pady 5
    pack $controls_frame.rows_entry -side left -pady 5 -padx {0 5}
    pack $controls_frame.sep2 -side left -fill y -padx 5 -pady 5
    pack $controls_frame.play -side left -pady 5
    pack $controls_frame.save -side left -padx 5 -pady 5


    # --- Main Frame Content ---
    # This frame holds the image canvas and the preview canvas.
    set ::main_canvas [canvas $main_frame.canvas -background "#cccccc"]
    set ::preview_canvas [canvas $main_frame.preview -background "#f0f0f0" -width 200 -height 200]

    grid $main_frame.canvas -row 0 -column 0 -sticky "nsew"
    grid $main_frame.preview -row 0 -column 1 -sticky "ns"
    grid rowconfigure $main_frame 0 -weight 1
    grid columnconfigure $main_frame 0 -weight 1

    # Bind mouse events for drawing the selection rectangle.
    bind $::main_canvas <ButtonPress-1> {start_selection %x %y}
    bind $::main_canvas <B1-Motion> {update_selection %x %y}
    bind $::main_canvas <ButtonRelease-1> {end_selection}

    # --- Status Bar ---
    set ::status_label [ttk::label $status_frame.label -text "Open an image to begin." -anchor w]
    pack $::status_label -side left -fill x -expand true -padx 5
}

# --- Core Functionality ---

# Procedure to open an image file.
proc open_image {} {
    set types {
        {"Image Files" {".png" ".gif" ".jpg" ".jpeg"}}
        {"All Files" {"*"}}
    }
    set filename [tk_getOpenFile -parent . -title "Select an image" -filetypes $types]

    if {$filename eq ""} { return }

    set ::app_state::filepath $filename
    # If an image is already loaded, delete it to free memory.
    if {[lsearch -exact [image names] "::app_state::image_data"] != -1} {
        image delete ::app_state::image_data
    }
    set ::app_state::image_data [image create photo]
    $::app_state::image_data configure -file $filename

    # Clear the canvas and display the new image.
    $::main_canvas delete all
    $::main_canvas create image 0 0 -anchor nw -image $::app_state::image_data
    $::main_canvas configure -scrollregion [$::main_canvas bbox all]

    set img_w [image width $::app_state::image_data]
    set img_h [image height $::app_state::image_data]
    update_status "Loaded '$filename' (${img_w}x${img_h}). Drag on the image to select a sprite area."
}

# Procedure to save the selected image slice.
proc save_slice {} {
    if {$::app_state::filepath eq "" || $::app_state::select_x2 == 0} {
        update_status "Error: No image loaded or no selection made."
        return
    }

    # Create a temporary photo image for the slice.
    set slice_image [image create photo]
    # Copy the selected region from the main image to the temporary one.
    $slice_image copy $::app_state::image_data -from $::app_state::select_x1 $::app_state::select_y1 $::app_state::select_x2 $::app_state::select_y2

    # Construct the output filename.
    set original_filename [file tail $::app_state::filepath]
    set ext [file extension $original_filename]
    set name [file rootname $original_filename]
    set timestamp [clock milliseconds]
    set downloads_dir [file join ~ "Downloads"]
    if {![file isdirectory $downloads_dir]} {
        # Fallback to home directory if Downloads doesn't exist
        set downloads_dir ~
    }
    set outpath [file join $downloads_dir "${name}-${timestamp}${ext}"]
    
    # Attempt to save in the original format, fallback to PNG.
    set format [string toupper [string range $ext 1 end]]
    if {$format ne "PNG" && $format ne "GIF"} {
        set outpath [file join $downloads_dir "${name}-${timestamp}.png"]
        set format "PNG"
    }

    $slice_image write $outpath -format $format
    image delete $slice_image

    update_status "Saved slice to '$outpath'"
}


# --- Selection Handling ---

# Called on mouse button press.
proc start_selection {x y} {
    if {$::app_state::filepath eq ""} { return }
    set ::app_state::is_selecting 1
    # Convert window coordinates to canvas coordinates
    set ::app_state::select_x1 [$::main_canvas canvasx $x]
    set ::app_state::select_y1 [$::main_canvas canvasy $y]
    # Delete any old selection rectangle
    $::main_canvas delete selection_rect
    # Create a new one
    $::main_canvas create rectangle $::app_state::select_x1 $::app_state::select_y1 $::app_state::select_x1 $::app_state::select_y1 \
        -outline "#ff4500" -width 2 -tags selection_rect
}

# Called when dragging the mouse.
proc update_selection {x y} {
    if {!$::app_state::is_selecting} { return }
    set cur_x [$::main_canvas canvasx $x]
    set cur_y [$::main_canvas canvasy $y]
    $::main_canvas coords selection_rect $::app_state::select_x1 $::app_state::select_y1 $cur_x $cur_y
}

# Called on mouse button release.
proc end_selection {} {
    if {!$::app_state::is_selecting} { return }
    set ::app_state::is_selecting 0
    # Get final coordinates, ensuring x1,y1 is top-left.
    lassign [$::main_canvas coords selection_rect] x1 y1 x2 y2
    set ::app_state::select_x1 [expr {min($x1, $x2)}]
    set ::app_state::select_y1 [expr {min($y1, $y2)}]
    set ::app_state::select_x2 [expr {max($x1, $x2)}]
    set ::app_state::select_y2 [expr {max($y1, $y2)}]
    
    set sel_w [expr {$::app_state::select_x2 - $::app_state::select_x1}]
    set sel_h [expr {$::app_state::select_y2 - $::app_state::select_y1}]
    update_status "Selection made: ${sel_w}x${sel_h}px. Press Play to preview animation."
    
    # Trigger one frame of the animation to show the first frame in the preview.
    set ::app_state::current_frame 0
    animate_frame
}


# --- Animation Handling ---

# Toggles the animation state (play/pause).
proc toggle_animation {} {
    if {$::app_state::is_animating} {
        # --- Pause ---
        set ::app_state::is_animating 0
        .controls.play configure -text "▶ Play"
        if {$::app_state::animation_id ne ""} {
            after cancel $::app_state::animation_id
            set ::app_state::animation_id ""
        }
        update_status "Animation paused."
    } else {
        # --- Play ---
        if {$::app_state::filepath eq "" || $::app_state::select_x2 == 0} {
            update_status "Error: Cannot play. No image loaded or no selection made."
            return
        }
        set ::app_state::is_animating 1
        .controls.play configure -text "❚❚ Pause"
        set ::app_state::current_frame 0
        update_status "Playing animation..."
        animate_loop
    }
}

# The main animation loop, called repeatedly.
proc animate_loop {} {
    if {!$::app_state::is_animating} { return }
    
    animate_frame

    # Schedule the next frame
    set ::app_state::animation_id [after 100 animate_loop]
}

# Renders a single frame of the animation.
proc animate_frame {} {
    global FRAMES ROWS
    if {$FRAMES <= 0 || $ROWS <= 0} { return }

    # Calculate dimensions of the selection and a single frame.
    set sel_w [expr {round($::app_state::select_x2 - $::app_state::select_x1)}]
    set sel_h [expr {round($::app_state::select_y2 - $::app_state::select_y1)}]
    set frame_w [expr {$sel_w / $FRAMES}]
    set frame_h [expr {$sel_h / $ROWS}]

    if {$frame_w <= 0 || $frame_h <= 0} { return }

    # Calculate total frames and current row/column.
    set total_frames [expr {$FRAMES * $ROWS}]
    set ::app_state::current_frame [expr {($::app_state::current_frame + 1) % $total_frames}]
    
    set current_col [expr {$::app_state::current_frame % $FRAMES}]
    set current_row [expr {floor($::app_state::current_frame / $FRAMES)}]

    # Determine the top-left (x1, y1) and bottom-right (x2, y2) of the current frame.
    # We calculate start/end points and cast to int to avoid floating point errors.
    set x1 [expr {int($::app_state::select_x1 + $current_col * $frame_w)}]
    set y1 [expr {int($::app_state::select_y1 + $current_row * $frame_h)}]
    set x2 [expr {int($::app_state::select_x1 + ($current_col + 1) * $frame_w)}]
    set y2 [expr {int($::app_state::select_y1 + ($current_row + 1) * $frame_h)}]
    
    # Create or update the preview image.
    if {[lsearch -exact [image names] "::app_state::preview_image"] == -1} {
        set ::app_state::preview_image [image create photo]
    }
    
    # Copy the sub-region for the current frame.
    $::app_state::preview_image copy $::app_state::image_data -from $x1 $y1 $x2 $y2 -zoom 2 2

    # Display the frame in the preview canvas.
    $::preview_canvas delete all
    $::preview_canvas create image [expr {[winfo width $::preview_canvas]/2}] [expr {[winfo height $::preview_canvas]/2}] \
        -anchor center -image $::app_state::preview_image
    $::preview_canvas configure -width [image width $::app_state::preview_image] -height [image height $::app_state::preview_image]
}

# --- Utility ---

# Updates the text in the status bar.
proc update_status {message} {
    $::status_label configure -text $message
}


# --- Application Start ---
setup_ui



