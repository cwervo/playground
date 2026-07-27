# hello.tcl -- convertkit sample program
proc greet {who} {
    return "Hello, $who!"
}

foreach name {world folk convertkit} {
    puts [greet $name]
}

# a multi-line command with braces, quotes, and "special" <chars> & stuff
set banner {
  +--------------------+
  |  convertkit demo   |
  +--------------------+
}
puts $banner
