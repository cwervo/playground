import Foundation
import CoreGraphics

public struct Homography {
    public let m: [Double] // 3x3 matrix in row-major order
    
    public init(m: [Double]) {
        self.m = m
    }
    
    public func project(point: CGPoint) -> CGPoint {
        let x = Double(point.x)
        let y = Double(point.y)
        let w = m[6] * x + m[7] * y + m[8]
        guard abs(w) > 1e-10 else { return .zero }
        let px = (m[0] * x + m[1] * y + m[2]) / w
        let py = (m[3] * x + m[4] * y + m[5]) / w
        return CGPoint(x: px, y: py)
    }
    
    /// Solves for the 3x3 homography matrix mapping src to dest.
    /// Uses Gaussian elimination to find the null space of a 8x9 matrix.
    public static func solve(src: [CGPoint], dest: [CGPoint]) -> Homography? {
        guard src.count == 4 && dest.count == 4 else { return nil }
        
        // We set up a system of 8 linear equations Ah = 0 where A is 8x9
        var A = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let x = Double(src[i].x)
            let y = Double(src[i].y)
            let u = Double(dest[i].x)
            let v = Double(dest[i].y)
            
            A[i*2]   = [-x, -y, -1, 0, 0, 0, x * u, y * u, u]
            A[i*2+1] = [0, 0, 0, -x, -y, -1, x * v, y * v, v]
        }
        
        // Perform Gaussian elimination with pivoting to solve for h.
        // We want to find a non-trivial solution to Ah = 0.
        // We can solve it by adding a constraint h[8] = 1, converting it to a 8x8 system,
        // or doing full row reduction on the 8x9 matrix.
        // Let's do row reduction on A to row echelon form:
        for i in 0..<8 {
            // Find pivot row
            var pivotRow = i
            var maxVal = abs(A[i][i])
            for r in (i + 1)..<8 {
                let val = abs(A[r][i])
                if val > maxVal {
                    maxVal = val
                    pivotRow = r
                }
            }
            
            // Swap rows if needed
            if pivotRow != i {
                let temp = A[i]
                A[i] = A[pivotRow]
                A[pivotRow] = temp
            }
            
            // Eliminate columns
            let pivot = A[i][i]
            if abs(pivot) < 1e-10 { continue }
            
            for r in (i + 1)..<8 {
                let factor = A[r][i] / pivot
                for c in i..<9 {
                    A[r][c] -= factor * A[i][c]
                }
            }
        }
        
        // Back substitution assuming h[8] = 1.0
        var h = [Double](repeating: 0, count: 9)
        h[8] = 1.0
        
        for i in stride(from: 7, through: 0, by: -1) {
            var sum = 0.0
            for c in (i + 1)..<8 {
                sum += A[i][c] * h[c]
            }
            // Add the h[8] term
            sum += A[i][8] * h[8]
            
            let diag = A[i][i]
            if abs(diag) < 1e-10 {
                h[i] = 0.0
            } else {
                h[i] = -sum / diag
            }
        }
        
        return Homography(m: h)
    }
}
