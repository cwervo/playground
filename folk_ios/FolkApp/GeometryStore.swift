import Foundation
import CoreGraphics

public final class GeometryStore {
    public static let shared = GeometryStore()
    
    private let queue = DispatchQueue(label: "org.folk.geometryStore", attributes: .concurrent)
    private var quads: [Int: [CGPoint]] = [:] // TagID -> 4 corners
    
    public init() {}
    
    public func setQuad(for id: Int, corners: [CGPoint]) {
        queue.async(flags: .barrier) {
            self.quads[id] = corners
        }
    }
    
    public func removeQuad(for id: Int) {
        queue.async(flags: .barrier) {
            self.quads.removeValue(forKey: id)
        }
    }
    
    public func getQuad(for id: Int) -> [CGPoint]? {
        queue.sync {
            self.quads[id]
        }
    }
}
