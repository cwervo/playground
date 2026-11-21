import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // This is called when the scene is connecting.
        // If this scene is for an external screen, ignore it here (handled by ProjectorDisplayManager)
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // We only initialize the main UI if it's the primary device screen
        if windowScene.screen == UIScreen.main {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: MainView())
            self.window = window
            window.makeKeyAndVisible()
        }
    }
}
