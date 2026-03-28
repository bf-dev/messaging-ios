import UIKit

@objc(MessagingServerAppDelegate)
final class MessagingServerAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    private let context = MessagingServerAppContext.shared

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        installRoot(animated: false)
        window.makeKeyAndVisible()
        return true
    }

    private func installRoot(animated: Bool) {
        let rootViewController: UIViewController
        if let session = context.currentSession, let client = context.makeAPIClient() {
            rootViewController = MessagingServerMainTabBarController(
                session: session,
                client: client,
                sessionStore: context.sessionStore,
                onLogout: { [weak self] in
                    self?.context.sessionStore.clear()
                    self?.installRoot(animated: true)
                }
            )
        } else {
            let loginViewController = MessagingServerLoginViewController(sessionStore: context.sessionStore) { [weak self] _ in
                self?.installRoot(animated: true)
            }
            rootViewController = UINavigationController(rootViewController: loginViewController)
        }

        guard let window else {
            return
        }

        if animated, let snapshot = window.snapshotView(afterScreenUpdates: true) {
            rootViewController.view.addSubview(snapshot)
            window.rootViewController = rootViewController
            UIView.animate(withDuration: 0.25, animations: {
                snapshot.alpha = 0.0
            }, completion: { _ in
                snapshot.removeFromSuperview()
            })
        } else {
            window.rootViewController = rootViewController
        }
    }
}

final class MessagingServerMainTabBarController: UITabBarController {
    init(
        session: MessagingServerSession,
        client: MessagingServerAPIClient,
        sessionStore: MessagingServerSessionStore,
        onLogout: @escaping () -> Void
    ) {
        super.init(nibName: nil, bundle: nil)

        let inboxes = MessagingServerInboxListViewController(session: session, client: client)
        inboxes.title = "Chats"
        let inboxNavigation = UINavigationController(rootViewController: inboxes)
        inboxNavigation.tabBarItem = UITabBarItem(title: "Chats", image: UIImage(systemName: "bubble.left.and.bubble.right"), selectedImage: UIImage(systemName: "bubble.left.and.bubble.right.fill"))
        inboxNavigation.navigationBar.prefersLargeTitles = true

        let settings = MessagingServerSettingsViewController(session: session, client: client, sessionStore: sessionStore, onLogout: onLogout)
        settings.title = "Settings"
        let settingsNavigation = UINavigationController(rootViewController: settings)
        settingsNavigation.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape"), selectedImage: UIImage(systemName: "gearshape.fill"))
        settingsNavigation.navigationBar.prefersLargeTitles = true

        viewControllers = [inboxNavigation, settingsNavigation]
        tabBar.isTranslucent = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
