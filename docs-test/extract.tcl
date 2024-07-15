# Enhanced Documentation Generator Script
#
# This script scans Tcl files in the current directory, extracts documentation comments,
# and generates HTML documentation files in a new 'docs' directory.

# Import necessary packages
package require fileutil

# Create 'docs' directory if it doesn't exist
if {![file exists docs]} {
    file mkdir docs
}

# Function to convert comments to HTML with appropriate headers
proc convertCommentsToHTML {comment depth} {
    set html ""
    foreach line [split $comment \n] {
        # Clean the line by removing leading '#' and trimming spaces
        set cleaned [string trim [string map {"#" ""} $line]]
        if {$cleaned ne ""} {
            # Determine the header level based on depth
            set headerTag "h[expr {$depth + 1}]"
            append html "<$headerTag>$cleaned</$headerTag>\n"
        }
    }
    return $html
}

# Function to process documentation comments in a file
proc processComments {filedata depth} {
    set htmlContent ""
    set comments [regexp -all -inline {#[# \t]*\n(#[^\n]*\n)+} $filedata]

    foreach {commentBlock} $comments {
        set htmlComment [convertCommentsToHTML $commentBlock $depth]
        append htmlContent "<p>$htmlComment</p>\n"
    }
    return $htmlContent
}

# Function to process a Tcl file
proc processFile {filename} {
    set basename [file rootname [file tail $filename]]
    set htmlfile "docs/${basename}.html"
    set filedata [read [open $filename]]

    set htmlContent "<html>\n<head><title>Documentation for $basename</title></head>\n<body>\n"
    set htmlContent [concat $htmlContent [processComments $filedata 0]]
    append htmlContent "</body>\n</html>"

    set fd [open $htmlfile w]
    puts $fd $htmlContent
    close $fd
}

# Main script
foreach file [glob *.tcl] {
    processFile $file
}
