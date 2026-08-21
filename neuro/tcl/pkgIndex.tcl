# pkgIndex.tcl — lets `package require nvm` work when tcl/ is on auto_path.
package ifneeded nvm 1.0 [list source [file join $dir nvm.tcl]]
