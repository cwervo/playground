Claim $this has a demo {
	# Make a synthetic region
	# TODO: Make `proc region::new {x y width height} {...}
	Claim $circleMark has region [region new 350 500 100 100]
	Claim $r1 has region [region new 500 500 100 100]
	Claim $r2 has region [region new 500 500 100 100]
	# "circle" will be whatever mark is drawn in the circleMark region
	Claim $circleMark detects mark circle
	
	# TODO: Make `proc region::new {regionOne regionTwo} {...}`
	#       It should make a region out of the most distance pairs of points
	Claim $recognizerRegion has region [region new $r1 $r2]
	Wish $recognizerRegion recognizes mark circle
}
