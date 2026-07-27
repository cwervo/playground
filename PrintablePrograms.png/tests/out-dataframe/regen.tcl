# hello.tcl -- PrintablePrograms sample program
proc greet {who} {
    return "Hello, $who!"
}
foreach name {world folk printable} {
    puts [greet $name]
}
# a multi-line command with braces, quotes, and "special" <chars> & stuff
set banner {
  +--------------------+
  |  printable demo    |
  +--------------------+
}
puts $banner
