namespace eval lorem {
  set a 1
  proc b {} {
    return "b"
  }
}

puts $lorem::a
puts [lorem::b]