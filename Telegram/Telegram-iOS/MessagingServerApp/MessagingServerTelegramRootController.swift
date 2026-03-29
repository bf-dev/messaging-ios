import AccountContext
import Display
import SwiftSignalKit
import TelegramCore
import UIKit

final class MessagingServerTelegramRootController: NavigationController, TelegramRootControllerInterface {
    weak var mainTabController: MessagingServerTelegramMainTabController?
    weak var chatsController: ViewController?
    weak var settingsController: ViewController?

    init(theme: NavigationControllerTheme) {
        super.init(mode: .automaticMasterDetail, theme: theme)
    }

    @discardableResult
    func openStoryCamera(
        mode: StoryCameraMode,
        customTarget: Stories.PendingTarget?,
        resumeLiveStream: Bool,
        transitionIn: StoryCameraTransitionIn?,
        transitionedIn: @escaping () -> Void,
        transitionOut: @escaping (Stories.PendingTarget?, Bool) -> StoryCameraTransitionOut?
    ) -> StoryCameraTransitionInCoordinator? {
        return nil
    }

    func proceedWithStoryUpload(
        target: Stories.PendingTarget,
        results: [MediaEditorScreenResult],
        existingMedia: EngineMedia?,
        forwardInfo: Stories.PendingForwardInfo?,
        externalState: MediaEditorTransitionOutExternalState,
        commit: @escaping (@escaping () -> Void) -> Void
    ) {
    }

    func getContactsController() -> ViewController? {
        return nil
    }

    func getChatsController() -> ViewController? {
        return chatsController
    }

    func getSettingsController() -> ViewController? {
        return settingsController
    }

    func getPrivacySettings() -> Promise<AccountPrivacySettings?>? {
        return nil
    }

    func getTwoStepAuthData() -> Promise<TwoStepAuthData?>? {
        return nil
    }

    func openContacts() {
    }

    func openSettings(edit: Bool) {
        if let settingsController,
           let index = mainTabController?.controllers.firstIndex(where: { $0 === settingsController }) {
            mainTabController?.selectedIndex = index
        }
    }

    func openBirthdaySetup() {
    }

    func openPhotoSetup(completedWithUploadingImage: @escaping (UIImage, Signal<PeerInfoAvatarUploadStatus, NoError>) -> UIView?) {
    }

    func openAvatars() {
    }

    func startNewCall() {
    }
}
