import UIKit

@objc(MessagingServerAppDelegate)
final class MessagingServerAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    private let context = MessagingServerAppContext.shared

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAppearance()

        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        installRoot(animated: false)
        window.makeKeyAndVisible()
        return true
    }

    private func configureAppearance() {
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = .systemBackground
        navigationAppearance.shadowColor = .separator

        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().tintColor = .systemBlue

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = .systemBackground
        UITabBar.appearance().standardAppearance = tabAppearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        }
    }

    private func installRoot(animated: Bool) {
        let rootViewController: UIViewController
        if let session = context.currentSession {
            rootViewController = makeAuthenticatedRoot(session: session)
        } else {
            rootViewController = makeOnboardingRoot()
        }

        guard let window else {
            return
        }

        if animated, let snapshot = window.snapshotView(afterScreenUpdates: true) {
            rootViewController.view.addSubview(snapshot)
            window.rootViewController = rootViewController
            UIView.animate(withDuration: 0.28, animations: {
                snapshot.alpha = 0.0
            }, completion: { _ in
                snapshot.removeFromSuperview()
            })
        } else {
            window.rootViewController = rootViewController
        }
    }

    private func makeOnboardingRoot() -> UIViewController {
        let welcome = MessagingServerWelcomeViewController(sessionStore: context.sessionStore) { [weak self] viewController in
            guard let self, let navigationController = viewController.navigationController else {
                return
            }
            let credentials = MessagingServerLoginViewController(mode: .onboarding, sessionStore: self.context.sessionStore) { [weak self] _ in
                self?.installRoot(animated: true)
            }
            navigationController.pushViewController(credentials, animated: true)
        }

        let navigationController = UINavigationController(rootViewController: welcome)
        navigationController.navigationBar.prefersLargeTitles = true
        return navigationController
    }

    private func makeAuthenticatedRoot(session: MessagingServerSession) -> UIViewController {
        let client = MessagingServerAPIClient(session: session)
        return MessagingServerMainTabBarController(
            session: session,
            client: client,
            sessionStore: context.sessionStore,
            onSessionUpdated: { [weak self] _ in
                self?.installRoot(animated: true)
            },
            onLogout: { [weak self] in
                self?.context.sessionStore.clear()
                self?.installRoot(animated: true)
            }
        )
    }
}

final class MessagingServerMainTabBarController: UITabBarController {
    init(
        session: MessagingServerSession,
        client: MessagingServerAPIClient,
        sessionStore: MessagingServerSessionStore,
        onSessionUpdated: @escaping (MessagingServerSession) -> Void,
        onLogout: @escaping () -> Void
    ) {
        super.init(nibName: nil, bundle: nil)

        let inboxes = MessagingServerInboxListViewController(session: session, client: client)
        inboxes.title = "Chats"
        let inboxNavigation = UINavigationController(rootViewController: inboxes)
        inboxNavigation.navigationBar.prefersLargeTitles = true
        inboxNavigation.tabBarItem = UITabBarItem(
            title: "Chats",
            image: UIImage(systemName: "bubble.left.and.bubble.right"),
            selectedImage: UIImage(systemName: "bubble.left.and.bubble.right.fill")
        )

        let settings = MessagingServerSettingsViewController(
            session: session,
            client: client,
            sessionStore: sessionStore,
            onSessionUpdated: onSessionUpdated,
            onLogout: onLogout
        )
        settings.title = "Settings"
        let settingsNavigation = UINavigationController(rootViewController: settings)
        settingsNavigation.navigationBar.prefersLargeTitles = true
        settingsNavigation.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )

        viewControllers = [inboxNavigation, settingsNavigation]
        tabBar.isTranslucent = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
