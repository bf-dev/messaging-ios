import Display
import NavigationBarImpl
import TabBarUI
import UIKit

@objc(MessagingServerAppDelegate)
final class MessagingServerAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    private let context = MessagingServerAppContext.shared

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        defaultNavigationBarImpl = { presentationData in
            NavigationBarImpl(presentationData: presentationData)
        }
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

        let navigationController = NavigationController(mode: .single, theme: MessagingServerTelegramPresentation.navigationControllerTheme)
        navigationController.setViewControllers([welcome], animated: false)
        return navigationController
    }

    private func makeAuthenticatedRoot(session: MessagingServerSession) -> UIViewController {
        let client = MessagingServerAPIClient(session: session)
        let rootController = MessagingServerTelegramMainTabController(
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
        let navigationController = NavigationController(mode: .automaticMasterDetail, theme: MessagingServerTelegramPresentation.navigationControllerTheme)
        navigationController.setViewControllers([rootController], animated: false)
        return navigationController
    }
}

final class MessagingServerTelegramMainTabController: TabBarControllerImpl {
    init(
        session: MessagingServerSession,
        client: MessagingServerAPIClient,
        sessionStore: MessagingServerSessionStore,
        onSessionUpdated: @escaping (MessagingServerSession) -> Void,
        onLogout: @escaping () -> Void
    ) {
        let presentationData = MessagingServerTelegramPresentation.presentationData
        super.init(theme: presentationData.theme, strings: presentationData.strings)
        navigationPresentation = .master

        let inboxes = MessagingServerInboxListViewController(session: session, client: client)
        inboxes.title = "Chats"
        inboxes.navigationPresentation = .master
        inboxes.tabBarItem = UITabBarItem(
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
        settings.navigationPresentation = .master
        settings.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )

        setControllers([inboxes, settings], selectedIndex: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
