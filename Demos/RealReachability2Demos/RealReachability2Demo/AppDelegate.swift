import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let root = ReachabilityViewController()
        window.rootViewController = UINavigationController(rootViewController: root)
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
