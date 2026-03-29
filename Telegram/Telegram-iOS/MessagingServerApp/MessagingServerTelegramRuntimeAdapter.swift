import AccountContext
import AppLock
import BuildConfig
import ChatListUI
import Display
import OpenSSLEncryptionProvider
import Postbox
import Security
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUI
import UIKit

enum MessagingServerTelegramRuntimeError: LocalizedError {
    case missingAccountContext

    var errorDescription: String? {
        switch self {
        case .missingAccountContext:
            return "Telegram runtime account context was not created."
        }
    }
}

private struct MessagingServerTelegramConversationSeed {
    let inbox: MessagingServerInboxSummary
    let messages: [MessagingServerMessage]
}

final class MessagingServerTelegramRuntimeAdapter {
    private let session: MessagingServerSession
    private let client: MessagingServerAPIClient
    private let snapshotStore = MessagingServerSnapshotStore.shared
    private let rootPath: String
    private let sharedPath: String
    private let buildConfig: BuildConfig
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let encryptionParameters: ValueBoxEncryptionParameters
    private let networkArguments: NetworkInitializationArguments
    private let applicationBindings: TelegramApplicationBindings
    private let appLockContext: AppLockContextImpl
    private let windowStyle: WindowUserInterfaceStyle

    private var accountRecordId: AccountRecordId?
    private var accountContext: AccountContext?
    private var bootstrapDisposable: Disposable?
    private var accountRecordDisposable: Disposable?
    private var refreshDisposable: Disposable?

    init?(session: MessagingServerSession, client: MessagingServerAPIClient, windowStyle: WindowUserInterfaceStyle) {
        self.session = session
        self.client = client
        self.windowStyle = windowStyle

        let baseAppBundleId = Bundle.main.bundleIdentifier ?? "org.telegram.messenger"
        self.buildConfig = BuildConfig(baseAppBundleId: baseAppBundleId)

        let sessionHash = stableHash("\(session.baseURL.absoluteString)|\(session.apiKey)")
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let runtimeBaseURL = applicationSupport
            .appendingPathComponent("MessagingServerTelegramRuntime", isDirectory: true)
            .appendingPathComponent(sessionHash, isDirectory: true)
        let rootURL = runtimeBaseURL.appendingPathComponent("telegram-root", isDirectory: true)
        let sharedURL = runtimeBaseURL.appendingPathComponent("telegram-shared", isDirectory: true)
        let accountManagerURL = runtimeBaseURL.appendingPathComponent("telegram-account-manager", isDirectory: true)

        self.rootPath = rootURL.path
        self.sharedPath = sharedURL.path

        do {
            try FileManager.default.createDirectory(at: runtimeBaseURL, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(at: sharedURL, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(at: accountManagerURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return nil
        }

        let deviceEncryptionParameters = BuildConfig.deviceSpecificEncryptionParameters(rootPath, baseAppBundleId: baseAppBundleId)
        guard let key = ValueBoxEncryptionParameters.Key(data: deviceEncryptionParameters.key),
              let salt = ValueBoxEncryptionParameters.Salt(data: deviceEncryptionParameters.salt) else {
            return nil
        }
        self.encryptionParameters = ValueBoxEncryptionParameters(forceEncryptionIfNoSet: false, key: key, salt: salt)
        self.accountManager = AccountManager(basePath: accountManagerURL.path, isTemporary: false, isReadOnly: false, useCaches: true, removeDatabaseOnError: true)

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        self.networkArguments = NetworkInitializationArguments(
            apiId: buildConfig.apiId,
            apiHash: buildConfig.apiHash,
            languagesCategory: "ios",
            appVersion: appVersion,
            voipMaxLayer: 0,
            voipVersions: [],
            appData: .single(buildConfig.bundleData(withAppToken: nil, tokenType: nil, tokenEnvironment: nil, signatureDict: nil)),
            externalRequestVerificationStream: .never(),
            externalRecaptchaRequestVerification: { _, _ in .never() },
            autolockDeadine: .single(nil),
            encryptionProvider: OpenSSLEncryptionProvider(),
            deviceModelName: nil,
            useBetaFeatures: !buildConfig.isAppStoreBuild,
            isICloudEnabled: buildConfig.isICloudEnabled
        )

        self.applicationBindings = TelegramApplicationBindings(
            isMainApp: false,
            appBundleId: baseAppBundleId,
            appBuildType: buildConfig.isAppStoreBuild ? .public : .internal,
            containerPath: sharedPath,
            appSpecificScheme: buildConfig.appSpecificUrlScheme,
            openUrl: { _ in },
            openUniversalUrl: { _, completion in completion.completion(false) },
            canOpenUrl: { _ in false },
            getTopWindow: { nil },
            displayNotification: { _ in },
            applicationInForeground: .single(true),
            applicationIsActive: .single(true),
            clearMessageNotifications: { _ in },
            pushIdleTimerExtension: { EmptyDisposable },
            openSettings: { },
            openAppStorePage: { },
            openSubscriptions: { },
            registerForNotifications: { completion in completion(false) },
            requestSiriAuthorization: { completion in completion(false) },
            siriAuthorization: { .denied },
            getWindowHost: { nil },
            presentNativeController: { _ in },
            dismissNativeController: { },
            getAvailableAlternateIcons: { [] },
            getAlternateIconName: { nil },
            requestSetAlternateIconName: { _, completion in completion(false) },
            forceOrientation: { _ in }
        )

        let presentationSignal = currentPresentationDataAndSettings(
            accountManager: accountManager,
            systemUserInterfaceStyle: windowStyle
        )
        |> map { $0.presentationData }
        self.appLockContext = AppLockContextImpl(
            rootPath: runtimeBaseURL.appendingPathComponent("app-lock", isDirectory: true).path,
            window: nil,
            rootController: nil,
            applicationBindings: applicationBindings,
            accountManager: accountManager,
            presentationDataSignal: presentationSignal,
            lockIconInitialFrame: { nil }
        )
    }

    deinit {
        bootstrapDisposable?.dispose()
        accountRecordDisposable?.dispose()
        refreshDisposable?.dispose()
    }

    func bootstrap(completion: @escaping (Result<AccountContext, Error>) -> Void) {
        if let accountContext {
            completion(.success(accountContext))
            refreshFromServer()
            return
        }

        ensureAccountRecord { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(recordId):
                self.accountRecordId = recordId
                syncSeeds(cachedSeeds())
                bootstrapContext(completion: completion)
                refreshFromServer()
            }
        }
    }

    func refreshFromServer() {
        fetchServerSeeds { [weak self] result in
            guard let self, case let .success(seeds) = result else {
                return
            }
            self.syncSeeds(seeds)
        }
    }

    func makeChatListController(context: AccountContext) -> ChatListControllerImpl {
        let controller = ChatListControllerImpl(
            context: context,
            location: .chatList(groupId: .root),
            controlsHistoryPreload: false,
            hideNetworkActivityStatus: true,
            previewing: false,
            enableDebugActions: false
        )
        controller.title = "Chats"
        controller.navigationPresentation = .master
        controller.tabBarItem = UITabBarItem(
            title: "Chats",
            image: UIImage(systemName: "bubble.left.and.bubble.right"),
            selectedImage: UIImage(systemName: "bubble.left.and.bubble.right.fill")
        )
        return controller
    }

    private func bootstrapContext(completion: @escaping (Result<AccountContext, Error>) -> Void) {
        bootstrapDisposable?.dispose()
        var producedContext = false
        bootstrapDisposable = (
            currentPresentationDataAndSettings(accountManager: accountManager, systemUserInterfaceStyle: windowStyle)
            |> take(1)
            |> mapToSignal { [weak self] initialData -> Signal<AccountContext, NoError> in
                guard let self else {
                    return .complete()
                }
                return makeTempContext(
                    sharedContainerPath: self.sharedPath,
                    rootPath: self.rootPath,
                    appGroupPath: self.sharedPath,
                    accountManager: self.accountManager,
                    appLockContext: self.appLockContext,
                    encryptionParameters: self.encryptionParameters,
                    applicationBindings: self.applicationBindings,
                    initialPresentationDataAndSettings: initialData,
                    networkArguments: self.networkArguments,
                    buildConfig: self.buildConfig
                )
            }
            |> deliverOnMainQueue
        ).start(next: { [weak self] context in
            guard let self else {
                return
            }
            producedContext = true
            self.accountContext = context
            completion(.success(context))
        }, completed: {
            if !producedContext {
                completion(.failure(MessagingServerTelegramRuntimeError.missingAccountContext))
            }
        })
    }

    private func ensureAccountRecord(completion: @escaping (Result<AccountRecordId, Error>) -> Void) {
        if let accountRecordId {
            completion(.success(accountRecordId))
            return
        }

        let backupData = makeBackupData()
        accountRecordDisposable?.dispose()
        accountRecordDisposable = (
            accountManager.transaction { transaction -> AccountRecordId in
                let attributes: [TelegramAccountRecordAttribute] = [
                    .sortOrder(AccountSortOrderAttribute(order: 0)),
                    .backupData(AccountBackupDataAttribute(data: backupData)),
                ]
                if let current = transaction.getCurrent()?.0 {
                    transaction.updateRecord(current) { record in
                        AccountRecord(id: current, attributes: attributes, temporarySessionId: record?.temporarySessionId)
                    }
                    transaction.setCurrentId(current)
                    return current
                } else {
                    let id = transaction.createRecord(attributes)
                    transaction.setCurrentId(id)
                    return id
                }
            }
            |> deliverOnMainQueue
        ).start(next: { [weak self] id in
            self?.accountRecordId = id
            completion(.success(id))
        })
    }

    private func cachedSeeds() -> [MessagingServerTelegramConversationSeed] {
        let inboxes = snapshotStore.loadInboxes(for: session)
        return inboxes.map { inbox in
            let snapshot = snapshotStore.loadConversation(inboxId: inbox.inboxId, for: session)
            return MessagingServerTelegramConversationSeed(
                inbox: inbox,
                messages: snapshot?.messages ?? fallbackMessages(for: inbox)
            )
        }
    }

    private func fetchServerSeeds(completion: @escaping (Result<[MessagingServerTelegramConversationSeed], Error>) -> Void) {
        client.listInboxes(limit: 100) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(inboxes):
                self.snapshotStore.saveInboxes(inboxes, for: self.session)
                guard !inboxes.isEmpty else {
                    completion(.success([]))
                    return
                }

                var seeds = Array<MessagingServerTelegramConversationSeed?>(repeating: nil, count: inboxes.count)
                let group = DispatchGroup()
                let lock = NSLock()

                for (index, inbox) in inboxes.enumerated() {
                    group.enter()
                    self.client.listMessages(inboxId: inbox.inboxId, limit: 200) { [weak self] messagesResult in
                        defer { group.leave() }
                        guard let self else {
                            return
                        }

                        let messages: [MessagingServerMessage]
                        switch messagesResult {
                        case let .success(value):
                            messages = value
                            let existingSnapshot = self.snapshotStore.loadConversation(inboxId: inbox.inboxId, for: self.session)
                            self.snapshotStore.saveConversation(
                                MessagingServerConversationSnapshot(
                                    messages: value,
                                    operations: existingSnapshot?.operations ?? [],
                                    suggestedReplies: existingSnapshot?.suggestedReplies ?? [],
                                    updatedAt: ISO8601DateFormatter().string(from: Date())
                                ),
                                inboxId: inbox.inboxId,
                                for: self.session
                            )
                        case .failure:
                            messages = self.snapshotStore.loadConversation(inboxId: inbox.inboxId, for: self.session)?.messages
                                ?? self.fallbackMessages(for: inbox)
                        }

                        lock.lock()
                        seeds[index] = MessagingServerTelegramConversationSeed(inbox: inbox, messages: messages)
                        lock.unlock()
                    }
                }

                group.notify(queue: .main) {
                    completion(.success(seeds.compactMap { $0 }))
                }
            }
        }
    }

    private func syncSeeds(_ seeds: [MessagingServerTelegramConversationSeed]) {
        guard let accountRecordId else {
            return
        }

        let accountPeer = makeAccountPeer()
        let signal = accountTransaction(
            rootPath: rootPath,
            id: accountRecordId,
            encryptionParameters: encryptionParameters,
            isReadOnly: false,
            transaction: { _, transaction -> Void in
                transaction.updatePeersInternal([accountPeer], update: { _, updated in updated })

                for seed in seeds {
                    let peer = makePeer(for: seed.inbox)
                    transaction.updatePeersInternal([peer], update: { _, updated in updated })
                    transaction.clearHistory(
                        peer.id,
                        threadId: nil,
                        minTimestamp: nil,
                        maxTimestamp: nil,
                        namespaces: .just(Set([Namespaces.Message.Cloud])),
                        forEachMedia: nil
                    )

                    let storeMessages = makeStoreMessages(messages: seed.messages, peerId: peer.id, accountPeerId: accountPeer.id)
                    if !storeMessages.isEmpty {
                        _ = transaction.addMessages(storeMessages, location: .Random)
                    }

                    let readState = makeReadState(messages: seed.messages, inbox: seed.inbox)
                    transaction.resetIncomingReadStates([peer.id: [Namespaces.Message.Cloud: readState]])
                }

                for hole in transaction.allChatListHoles(groupId: .root) {
                    transaction.replaceChatListHole(groupId: .root, index: hole.index, hole: nil)
                }
            }
        )
        refreshDisposable?.dispose()
        refreshDisposable = (signal |> deliverOnMainQueue).start()
    }

    private func makeBackupData() -> AccountBackupData {
        let peerId = makeAccountPeer().id.toInt64()
        let key = randomData(length: 256)
        let keyId = Int64(bitPattern: stableUInt64("auth|\(session.baseURL.absoluteString)"))
        return AccountBackupData(
            masterDatacenterId: 1,
            peerId: peerId,
            masterDatacenterKey: key,
            masterDatacenterKeyId: keyId == 0 ? 1 : keyId,
            notificationEncryptionKeyId: nil,
            notificationEncryptionKey: nil,
            additionalDatacenterKeys: [:]
        )
    }

    private func makeAccountPeer() -> TelegramUser {
        let rawId = Int64(bitPattern: stableUInt64("account|\(session.baseURL.absoluteString)")) & 0x0000FFFFFFFFFFFF
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(max(1, rawId)))
        return TelegramUser(
            id: peerId,
            accessHash: nil,
            firstName: "You",
            lastName: nil,
            username: nil,
            phone: nil,
            photo: [],
            botInfo: nil,
            restrictionInfo: nil,
            flags: [],
            emojiStatus: nil,
            usernames: [],
            storiesHidden: nil,
            nameColor: nil,
            backgroundEmojiId: nil,
            profileColor: nil,
            profileBackgroundEmojiId: nil,
            subscriberCount: nil,
            verificationIconFileId: nil
        )
    }

    private func makePeer(for inbox: MessagingServerInboxSummary) -> TelegramUser {
        let rawId = Int64(bitPattern: stableUInt64("inbox|\(inbox.platform.rawValue)|\(inbox.accountKey)|\(inbox.inboxId)")) & 0x0000FFFFFFFFFFFF
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(max(1, rawId)))
        return TelegramUser(
            id: peerId,
            accessHash: nil,
            firstName: inbox.displayTitle,
            lastName: nil,
            username: nil,
            phone: nil,
            photo: [],
            botInfo: nil,
            restrictionInfo: nil,
            flags: [],
            emojiStatus: nil,
            usernames: [],
            storiesHidden: nil,
            nameColor: nil,
            backgroundEmojiId: nil,
            profileColor: nil,
            profileBackgroundEmojiId: nil,
            subscriberCount: nil,
            verificationIconFileId: nil
        )
    }

    private func fallbackMessages(for inbox: MessagingServerInboxSummary) -> [MessagingServerMessage] {
        guard let preview = inbox.lastMessagePreview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty else {
            return []
        }
        return [
            MessagingServerMessage(
                platform: inbox.platform,
                accountKey: inbox.accountKey,
                inboxId: inbox.inboxId,
                messageId: "summary:\(inbox.inboxId)",
                direction: .incoming,
                senderName: inbox.displayTitle,
                senderId: nil,
                senderProfileAsset: nil,
                text: preview,
                attachments: [],
                stickers: [],
                reactions: [],
                sentAt: inbox.lastMessageAt,
                rawType: nil,
                replyToMessageId: nil,
                editedAt: nil,
                deletedAt: nil,
                meta: [:]
            )
        ]
    }

    private func makeStoreMessages(messages: [MessagingServerMessage], peerId: PeerId, accountPeerId: PeerId) -> [StoreMessage] {
        let sortedMessages = messages
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                let lhsDate = MessagingServerDate.parse(lhs.sentAt) ?? .distantPast
                let rhsDate = MessagingServerDate.parse(rhs.sentAt) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhs.messageId < rhs.messageId
            }

        return sortedMessages.map { message in
            let timestamp = Int32((MessagingServerDate.parse(message.sentAt) ?? Date()).timeIntervalSince1970)
            var flags: StoreMessageFlags = [.TopIndexable, .ReactionsArePossible]
            if message.direction == .incoming || message.direction == .system {
                flags.insert(.Incoming)
                flags.insert(.CountedAsIncoming)
            }
            return StoreMessage(
                id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: stableMessageId("cloud|\(message.messageId)")),
                customStableId: nil,
                globallyUniqueId: nil,
                groupingKey: nil,
                threadId: nil,
                timestamp: timestamp,
                flags: flags,
                tags: [],
                globalTags: [],
                localTags: [],
                forwardInfo: nil,
                authorId: message.direction == .outgoing ? accountPeerId : peerId,
                text: message.displayText,
                attributes: [],
                media: []
            )
        }
    }

    private func makeReadState(messages: [MessagingServerMessage], inbox: MessagingServerInboxSummary) -> PeerReadState {
        let incomingMessages = messages.filter { $0.direction == .incoming || $0.direction == .system }
        let outgoingMessages = messages.filter { $0.direction == .outgoing }

        let maxIncomingReadId: Int32
        if inbox.unreadCount == 0, let lastIncoming = incomingMessages.last {
            maxIncomingReadId = stableMessageId("cloud|\(lastIncoming.messageId)")
        } else {
            maxIncomingReadId = 0
        }
        let maxOutgoingReadId = outgoingMessages.last.map { stableMessageId("cloud|\($0.messageId)") } ?? 0
        let lastKnownId = max(
            incomingMessages.last.map { stableMessageId("cloud|\($0.messageId)") } ?? 0,
            maxOutgoingReadId
        )
        return .idBased(
            maxIncomingReadId: maxIncomingReadId,
            maxOutgoingReadId: maxOutgoingReadId,
            maxKnownId: lastKnownId,
            count: Int32(max(0, inbox.unreadCount)),
            markedUnread: inbox.unreadCount > 0
        )
    }

    private func randomData(length: Int) -> Data {
        var data = Data(count: length)
        _ = data.withUnsafeMutableBytes { rawBytes in
            SecRandomCopyBytes(nil, length, rawBytes.baseAddress!)
        }
        return data
    }
}

private func stableMessageId(_ value: String) -> Int32 {
    let raw = stableUInt64(value) & 0x7fffffff
    return Int32(raw == 0 ? 1 : raw)
}

private func stableHash(_ value: String) -> String {
    return String(stableUInt64(value), radix: 16)
}

private func stableUInt64(_ value: String) -> UInt64 {
    var hash: UInt64 = 14695981039346656037
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1099511628211
    }
    return hash
}
