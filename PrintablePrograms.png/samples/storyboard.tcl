# storyboard.tcl -- a folk-flavored sample: fake 6DOF frame descriptions
# (echoes the sketch: barcodes encoding 6DOF position + scale per frame)
proc frame {id pos rot scale} {
    puts "frame $id @ pos=$pos rot=$rot scale=$scale"
}

frame 1 {0.0 0.0 0.0}   {0 0 0}    1.0
frame 2 {0.1 0.0 0.25}  {0 15 0}   1.0
frame 3 {0.2 0.05 0.5}  {0 30 5}   0.8

puts "storyboard: 3 frames, src (PNG)"
