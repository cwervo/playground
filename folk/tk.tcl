# Title: Simple Tcl/Tk Script for an Empty Window
# Author: Andrés

# Required package for GUI
package require Tk

# Create the main application window
wm title . "Empty Window"
wm geometry . 400x300

# Start the Tk event loop
tkwait window .
