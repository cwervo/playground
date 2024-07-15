# Vector Math Namespace
#
# This namespace provides basic vector math functionalities such as
# addition, subtraction, dot product, and magnitude calculation for 2D vectors.
namespace eval VectorMath {

    # Adds two vectors
    #
    # Parameters:
    #   v1 - First vector, a list with two elements [x1, y1]
    #   v2 - Second vector, a list with two elements [x2, y2]
    #
    # Returns:
    #   A list representing the resulting vector after addition
    proc add {v1 v2} {
        set x1 [lindex $v1 0]
        set y1 [lindex $v1 1]
        set x2 [lindex $v2 0]
        set y2 [lindex $v2 1]

        set xr [expr {$x1 + $x2}]
        set yr [expr {$y1 + $y2}]

        return [list $xr $yr]
    }

    # Subtracts one vector from another
    #
    # Parameters:
    #   v1 - First vector, a list with two elements [x1, y1]
    #   v2 - Second vector, a list with two elements [x2, y2]
    #
    # Returns:
    #   A list representing the resulting vector after subtraction
    proc subtract {v1 v2} {
        set x1 [lindex $v1 0]
        set y1 [lindex $v1 1]
        set x2 [lindex $v2 0]
        set y2 [lindex $v2 1]

        set xr [expr {$x1 - $x2}]
        set yr [expr {$y1 - $y2}]

        return [list $xr $yr]
    }

    # Calculates the dot product of two vectors
    #
    # Parameters:
    #   v1 - First vector, a list with two elements [x1, y1]
    #   v2 - Second vector, a list with two elements [x2, y2]
    #
    # Returns:
    #   The dot product of the two vectors
    proc dotProduct {v1 v2} {
        set x1 [lindex $v1 0]
        set y1 [lindex $v1 1]
        set x2 [lindex $v2 0]
        set y2 [lindex $v2 1]

        return [expr {$x1*$x2 + $y1*$y2}]
    }

    # Calculates the magnitude of a vector
    #
    # Parameters:
    #   v - A vector, a list with two elements [x, y]
    #
    # Returns:
    #   The magnitude of the vector
    proc magnitude {v} {
        set x [lindex $v 0]
        set y [lindex $v 1]

        return [expr {sqrt($x*$x + $y*$y)}]
    }
}

# Example usage of the namespace
set vec1 [list 3 4]
set vec2 [list 1 2]

puts "Vector 1: $vec1"
puts "Vector 2: $vec2"

puts "Addition: [VectorMath::add $vec1 $vec2]"
puts "Subtraction: [VectorMath::subtract $vec1 $vec2]"
puts "Dot Product: [VectorMath::dotProduct $vec1 $vec2]"
puts "Magnitude of Vector 1: [VectorMath::magnitude $vec1]"