import Display
import TelegramPresentationData

enum MessagingServerTelegramPresentation {
    static let presentationData = defaultPresentationData()
    static let navigationControllerTheme = NavigationControllerTheme(presentationTheme: presentationData.theme)

    static func navigationBarPresentationData() -> NavigationBarPresentationData {
        NavigationBarPresentationData(presentationData: presentationData)
    }
}
