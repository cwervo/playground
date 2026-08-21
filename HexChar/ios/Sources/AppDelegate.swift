import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var keyboard: KeyboardViewController?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions
                     launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Theme.registerBundledFonts()

        guard let url = Bundle.main.url(forResource: "hexchar-data", withExtension: "json"),
              let data = try? HexData.load(from: url) else {
            print("HEXCHAR_RESULT: FAIL (hexchar-data.json missing or invalid)")
            fflush(stdout)
            exit(1)
        }

        let controller = KeyboardViewController(data: data)
        keyboard = controller
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window

        SelfTest.runIfRequested(controller: controller)
        return true
    }
}
