set answers [list [list [list 0 0] [list 5 5]] [list [list 10 10]]]
# for {set x 0} {$x<10} {incr x} {
#     if {$x == 5} {
#         continue
#     }
#     puts "x is $x"
# }

set pm [list [list 0 0] [list 5 5]]

foreach answer $answers {
    set answerFound false
    foreach spot $answer {
      if {[lsearch $pm $spot] == -1} {
        puts "continuing from $spot"
        return
      }
      puts "$spot marked true"
      set answerFound true
    }
    if {$answerFound} {
        puts "found answer: $answer"
    }
}