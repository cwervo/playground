#!/usr/bin/env tclsh

set ::displayTime "render 7771 us (6565 us (peer 112 us, run 1797 us) (60 fps))"

set result [dict create \
    us [regsub {^render\s+(\d+)\s+us.*} $::displayTime {\1}] \
    fps [regsub {.*\((\d+)\s+fps\)} $::displayTime {\1}] \
]

puts "result: $result"