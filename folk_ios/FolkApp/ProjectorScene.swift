import SpriteKit

public final class ProjectorScene: SKScene {
    
    private var outlineNodes: [Int: (node: SKShapeNode, color: UIColor)] = [:]
    private var labelNodes: [Int: SKLabelNode] = [:]
    private var homography: Homography?
    
    public override func didMove(to view: SKView) {
        self.backgroundColor = .black
        // Load homography if saved
        if let saved = UserDefaults.standard.array(forKey: "homography_matrix") as? [Double], saved.count == 9 {
            self.homography = Homography(m: saved)
        }
    }
    
    public func setHomography(_ h: Homography) {
        self.homography = h
        UserDefaults.standard.set(h.m, forKey: "homography_matrix")
    }
    
    public func registerOutline(for tagId: Int, color: UIColor) -> SKShapeNode {
        if let existing = outlineNodes[tagId] {
            return existing.node
        }
        
        let node = SKShapeNode()
        node.lineWidth = 6
        node.strokeColor = color
        node.fillColor = .clear
        addChild(node)
        
        // Add label inside the tag
        let label = SKLabelNode(fontNamed: "Outfit-Bold")
        label.fontSize = 24
        label.fontColor = color
        label.text = "Program \(tagId)"
        addChild(label)
        
        outlineNodes[tagId] = (node, color)
        labelNodes[tagId] = label
        return node
    }
    
    public func unregisterOutline(for tagId: Int) {
        if let data = outlineNodes.removeValue(forKey: tagId) {
            data.node.removeFromParent()
        }
        if let label = labelNodes.removeValue(forKey: tagId) {
            label.removeFromParent()
        }
    }
    
    public override func update(_ currentTime: TimeInterval) {
        // Frame-by-frame update: update paths based on current tag coordinates
        for (tagId, data) in outlineNodes {
            guard let cameraQuad = GeometryStore.shared.getQuad(for: tagId) else {
                data.node.path = nil
                labelNodes[tagId]?.isHidden = true
                continue
            }
            
            // Transform coordinates to projector space
            var projectorPoints: [CGPoint] = []
            if let h = homography {
                projectorPoints = cameraQuad.map { h.project(point: $0) }
            } else {
                // If not calibrated, just scale to screen size for fallback demo
                projectorPoints = cameraQuad.map { pt in
                    CGPoint(x: pt.x * self.size.width, y: (1 - pt.y) * self.size.height)
                }
            }
            
            // Draw path
            let path = CGMutablePath()
            if !projectorPoints.isEmpty {
                path.addLines(between: projectorPoints)
                path.closeSubpath()
            }
            data.node.path = path
            
            // Update label position to the center of the quad
            if let label = labelNodes[tagId], projectorPoints.count == 4 {
                label.isHidden = false
                let centerX = (projectorPoints[0].x + projectorPoints[1].x + projectorPoints[2].x + projectorPoints[3].x) / 4
                let centerY = (projectorPoints[0].y + projectorPoints[1].y + projectorPoints[2].y + projectorPoints[3].y) / 4
                label.position = CGPoint(x: centerX, y: centerY)
            }
        }
    }
}
