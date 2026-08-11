import UIKit
import SpriteKit

public final class ProjectorDisplayManager: NSObject {
    public static let shared = ProjectorDisplayManager()
    
    public private(set) var externalWindow: UIWindow?
    public private(set) var projectorScene: ProjectorScene?
    
    public override init() {
        super.init()
    }
    
    public func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(screenDidConnect), name: UIScreen.didConnectNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenDidDisconnect), name: UIScreen.didDisconnectNotification, object: nil)
        
        // Check if screen is already connected
        if UIScreen.screens.count > 1 {
            setupExternalScreen(UIScreen.screens[1])
        }
    }
    
    @objc private func screenDidConnect(_ notification: Notification) {
        guard let screen = notification.object as? UIScreen else { return }
        setupExternalScreen(screen)
    }
    
    @objc private func screenDidDisconnect(_ notification: Notification) {
        externalWindow = nil
        projectorScene = nil
    }
    
    private func setupExternalScreen(_ screen: UIScreen) {
        // Create window on the external screen
        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        
        let skView = SKView(frame: window.bounds)
        skView.ignoresSiblingOrder = true
        skView.showsFPS = true
        skView.showsNodeCount = true
        
        let scene = ProjectorScene(size: window.bounds.size)
        scene.scaleMode = .aspectFill
        skView.presentScene(scene)
        
        let vc = UIViewController()
        vc.view = skView
        window.rootViewController = vc
        
        window.isHidden = false
        
        self.externalWindow = window
        self.projectorScene = scene
    }
}
