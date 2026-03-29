import AccountContext
import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

final class MessagingServerTelegramChatContents: ChatCustomContentsProtocol {
    private enum TimelineReference {
        case message(serverMessageId: String)
        case operation(operationId: String)
    }

    private enum TimelineEntry {
        case message(MessagingServerMessage)
        case operation(MessagingServerOperationView)

        var date: Date {
            switch self {
            case let .message(message):
                return MessagingServerDate.parse(message.sentAt) ?? .distantPast
            case let .operation(operation):
                return MessagingServerDate.parse(operation.requestedAt) ?? .distantPast
            }
        }

        var stableKey: String {
            switch self {
            case let .message(message):
                return "message:\(message.messageId)"
            case let .operation(operation):
                return "operation:\(operation.operationId)"
            }
        }
    }

    let kind: ChatCustomContentsKind = .messagingServerChat

    var historyView: Signal<(MessageHistoryView, ViewUpdateType), NoError> {
        return Signal { [weak self] subscriber in
            guard let self else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            if let currentHistoryView = self.currentHistoryView {
                subscriber.putNext((currentHistoryView, .Initial))
            }
            return self.historyViewPipe.signal().start(next: subscriber.putNext)
        }
    }

    var messageLimit: Int? {
        return nil
    }

    var hashtagSearchResultsUpdate: ((SearchMessagesResult, SearchMessagesState)) -> Void = { _ in
    }

    private let context: AccountContext
    private let session: MessagingServerSession
    private let client: MessagingServerAPIClient
    private let inbox: MessagingServerInboxSummary
    private let peer: Peer
    private let snapshotStore = MessagingServerSnapshotStore.shared
    private let historyViewPipe = ValuePipe<(MessageHistoryView, ViewUpdateType)>()

    private var currentHistoryView: MessageHistoryView?
    private var messages: [MessagingServerMessage] = []
    private var serverOperations: [MessagingServerOperationView] = []
    private var optimisticOperations: [MessagingServerOperationView] = []
    private var referenceMap: [MessageId: TimelineReference] = [:]
    private var realtimeClient: MessagingServerRealtimeClient?
    private var scheduledRefresh: DispatchWorkItem?
    private var lastMarkedReadMessageId: String?

    init(
        context: AccountContext,
        session: MessagingServerSession,
        client: MessagingServerAPIClient,
        inbox: MessagingServerInboxSummary,
        peer: Peer
    ) {
        self.context = context
        self.session = session
        self.client = client
        self.inbox = inbox
        self.peer = peer

        self.loadCachedSnapshot()
        self.startRealtime()
        self.refreshFromServer(updateType: .Generic)
    }

    deinit {
        scheduledRefresh?.cancel()
        realtimeClient?.disconnect()
    }

    func enqueueMessages(messages: [EnqueueMessage]) {
        for message in messages {
            switch message {
            case let .message(text, _, _, mediaReference, _, replyToMessageId, _, _, _, _):
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if mediaReference != nil {
                    let operation = self.makeOptimisticOperation(
                        preview: trimmedText.isEmpty ? "Media messages aren’t supported yet." : trimmedText,
                        status: .failed,
                        error: "Media messages aren’t supported yet."
                    )
                    self.upsertOptimisticOperation(operation)
                    continue
                }
                if trimmedText.isEmpty {
                    continue
                }

                let operation = self.makeOptimisticOperation(preview: trimmedText, status: .approvalRequested, error: nil)
                self.upsertOptimisticOperation(operation)

                let requestBody = MessagingServerSendMessageRequest(
                    text: trimmedText,
                    media: [],
                    uploadIds: nil,
                    replyToMessageId: replyToMessageId.flatMap(self.resolveServerMessageId(for:))
                )
                self.client.sendMessage(inboxId: self.inbox.inboxId, requestBody: requestBody) { [weak self] result in
                    guard let self else {
                        return
                    }
                    switch result {
                    case let .success(approval):
                        self.upsertOptimisticOperation(
                            self.makeOptimisticOperation(
                                operationId: approval.operationId,
                                preview: trimmedText,
                                status: .approvalRequested,
                                error: nil
                            ),
                            replacing: operation.operationId
                        )
                        self.refreshFromServer(updateType: .Generic)
                    case let .failure(error):
                        self.upsertOptimisticOperation(
                            self.makeOptimisticOperation(
                                operationId: operation.operationId,
                                preview: trimmedText,
                                status: .failed,
                                error: error.localizedDescription
                            ),
                            replacing: operation.operationId
                        )
                    }
                }
            case .forward:
                let operation = self.makeOptimisticOperation(
                    preview: "Forwarded messages aren’t supported yet.",
                    status: .failed,
                    error: "Forwarded messages aren’t supported yet."
                )
                self.upsertOptimisticOperation(operation)
            }
        }
    }

    func deleteMessages(ids: [EngineMessage.Id]) {
        for id in ids {
            guard let reference = self.referenceMap[id] else {
                continue
            }
            switch reference {
            case let .message(serverMessageId):
                self.messages.removeAll(where: { $0.messageId == serverMessageId })
                self.rebuildHistoryView(updateType: .Generic)
                self.client.deleteMessage(messageId: serverMessageId) { [weak self] result in
                    guard let self else {
                        return
                    }
                    if case .failure = result {
                        self.refreshFromServer(updateType: .Generic)
                    } else {
                        self.refreshFromServer(updateType: .Generic)
                    }
                }
            case let .operation(operationId):
                self.removeOptimisticOperation(operationId: operationId)
                self.serverOperations.removeAll(where: { $0.operationId == operationId })
                self.rebuildHistoryView(updateType: .Generic)

                if operationId.hasPrefix("local:") {
                    continue
                }

                self.client.cancelOperation(operationId: operationId) { [weak self] _ in
                    self?.refreshFromServer(updateType: .Generic)
                }
            }
        }
    }

    func editMessage(
        id: EngineMessage.Id,
        text: String,
        media: RequestEditMessageMedia,
        entities: TextEntitiesMessageAttribute?,
        webpagePreviewAttribute: WebpagePreviewMessageAttribute?,
        disableUrlPreview: Bool
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reference = self.referenceMap[id] else {
            return
        }

        switch reference {
        case let .message(serverMessageId):
            if let index = self.messages.firstIndex(where: { $0.messageId == serverMessageId }) {
                let original = self.messages[index]
                self.messages[index] = MessagingServerMessage(
                    platform: original.platform,
                    accountKey: original.accountKey,
                    inboxId: original.inboxId,
                    messageId: original.messageId,
                    direction: original.direction,
                    senderName: original.senderName,
                    senderId: original.senderId,
                    senderProfileAsset: original.senderProfileAsset,
                    text: trimmedText,
                    attachments: original.attachments,
                    stickers: original.stickers,
                    reactions: original.reactions,
                    sentAt: original.sentAt,
                    rawType: original.rawType,
                    replyToMessageId: original.replyToMessageId,
                    editedAt: MessagingServerDate.nowString(),
                    deletedAt: original.deletedAt,
                    meta: original.meta
                )
                self.rebuildHistoryView(updateType: .Generic)
            }

            self.client.editMessage(messageId: serverMessageId, requestBody: MessagingServerEditMessageRequest(text: trimmedText)) { [weak self] _ in
                self?.refreshFromServer(updateType: .Generic)
            }
        case let .operation(operationId):
            let updatedOperation = self.makeOptimisticOperation(
                operationId: operationId,
                preview: trimmedText,
                status: .approvalRequested,
                error: nil
            )
            self.upsertOptimisticOperation(updatedOperation, replacing: operationId)

            if operationId.hasPrefix("local:") {
                self.rebuildHistoryView(updateType: .Generic)
                return
            }

            let requestBody = MessagingServerSendMessageRequest(text: trimmedText, media: [], uploadIds: nil, replyToMessageId: nil)
            self.client.replacePendingOperation(operationId: operationId, requestBody: requestBody) { [weak self] result in
                guard let self else {
                    return
                }
                switch result {
                case .success:
                    self.refreshFromServer(updateType: .Generic)
                case let .failure(error):
                    self.upsertOptimisticOperation(
                        self.makeOptimisticOperation(
                            operationId: operationId,
                            preview: trimmedText,
                            status: .failed,
                            error: error.localizedDescription
                        ),
                        replacing: operationId
                    )
                }
            }
        }
    }

    func quickReplyUpdateShortcut(value: String) {
    }

    func businessLinkUpdate(message: String, entities: [MessageTextEntity], title: String?) {
    }

    func loadMore() {
    }

    func hashtagSearchUpdate(query: String) {
    }

    private func loadCachedSnapshot() {
        guard let snapshot = self.snapshotStore.loadConversation(inboxId: self.inbox.inboxId, for: self.session) else {
            self.rebuildHistoryView(updateType: .Initial)
            return
        }

        self.messages = snapshot.messages.filter { $0.deletedAt == nil }
        self.serverOperations = snapshot.operations.filter(\.isPendingBubble)
        self.rebuildHistoryView(updateType: .Initial)
        self.markLatestReadIfNeeded()
    }

    private func startRealtime() {
        self.realtimeClient?.disconnect()

        let realtimeClient = MessagingServerRealtimeClient(session: self.session)
        realtimeClient.onEvent = { [weak self] event in
            guard let self, event.topic == "inbox:\(self.inbox.inboxId)" else {
                return
            }
            self.scheduleRefresh()
        }
        self.realtimeClient = realtimeClient
        realtimeClient.connect()
    }

    private func scheduleRefresh() {
        self.scheduledRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshFromServer(updateType: .Generic)
        }
        self.scheduledRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func refreshFromServer(updateType: ViewUpdateType) {
        let existingSnapshot = self.snapshotStore.loadConversation(inboxId: self.inbox.inboxId, for: self.session)
        let group = DispatchGroup()
        let lock = NSLock()

        var loadedMessages: [MessagingServerMessage]?
        var loadedOperations: [MessagingServerOperationView]?

        group.enter()
        self.client.listMessages(inboxId: self.inbox.inboxId, limit: 200) { result in
            defer { group.leave() }
            if case let .success(messages) = result {
                lock.lock()
                loadedMessages = messages.filter { $0.deletedAt == nil }
                lock.unlock()
            }
        }

        group.enter()
        self.client.listInboxOperations(inboxId: self.inbox.inboxId, pendingOnly: false, limit: 200) { result in
            defer { group.leave() }
            if case let .success(operations) = result {
                lock.lock()
                loadedOperations = operations.filter(\.isPendingBubble)
                lock.unlock()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else {
                return
            }

            if let loadedMessages {
                self.messages = loadedMessages
            } else if let existingSnapshot {
                self.messages = existingSnapshot.messages.filter { $0.deletedAt == nil }
            }

            if let loadedOperations {
                self.serverOperations = loadedOperations
            } else if let existingSnapshot {
                self.serverOperations = existingSnapshot.operations.filter(\.isPendingBubble)
            }

            let mergedOperations = self.mergedOperations()
            self.snapshotStore.saveConversation(
                MessagingServerConversationSnapshot(
                    messages: self.messages,
                    operations: mergedOperations,
                    suggestedReplies: existingSnapshot?.suggestedReplies ?? [],
                    updatedAt: MessagingServerDate.nowString()
                ),
                inboxId: self.inbox.inboxId,
                for: self.session
            )

            self.rebuildHistoryView(updateType: updateType)
            self.markLatestReadIfNeeded()
        }
    }

    private func mergedOperations() -> [MessagingServerOperationView] {
        var seen = Set<String>()
        var result: [MessagingServerOperationView] = []
        for operation in self.serverOperations + self.optimisticOperations {
            guard operation.isPendingBubble, seen.insert(operation.operationId).inserted else {
                continue
            }
            result.append(operation)
        }
        return result
    }

    private func rebuildHistoryView(updateType: ViewUpdateType) {
        var referenceMap: [MessageId: TimelineReference] = [:]
        let timeline = (self.messages.map(TimelineEntry.message) + self.mergedOperations().map(TimelineEntry.operation))
            .sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date < rhs.date
                }
                return lhs.stableKey < rhs.stableKey
            }

        let entries: [MessageHistoryEntry] = timeline.map { entry in
            let message = self.makeRenderedMessage(for: entry)
            switch entry {
            case let .message(serverMessage):
                referenceMap[message.id] = .message(serverMessageId: serverMessage.messageId)
            case let .operation(operation):
                referenceMap[message.id] = .operation(operationId: operation.operationId)
            }
            return MessageHistoryEntry(
                message: message,
                isRead: true,
                location: nil,
                monthLocation: nil,
                attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false)
            )
        }

        self.referenceMap = referenceMap
        let historyView = MessageHistoryView(
            tag: nil,
            namespaces: .just(Set([Namespaces.Message.Cloud, Namespaces.Message.Local])),
            entries: entries,
            holeEarlier: false,
            holeLater: false,
            isLoading: false
        )
        self.currentHistoryView = historyView
        self.historyViewPipe.putNext((historyView, updateType))
    }

    private func makeRenderedMessage(for entry: TimelineEntry) -> Message {
        switch entry {
        case let .message(message):
            let timestamp = Int32((MessagingServerDate.parse(message.sentAt) ?? Date()).timeIntervalSince1970)
            let id = MessageId(
                peerId: self.peer.id,
                namespace: Namespaces.Message.Cloud,
                id: messagingServerStableMessageId("cloud|\(message.messageId)")
            )
            let author = self.authorPeer(for: message)
            let peers = self.messagePeers(author: author)
            let flags: MessageFlags = message.direction == .outgoing
                ? [.TopIndexable]
                : [.Incoming, .CountedAsIncoming, .TopIndexable]
            return Message(
                stableId: UInt32(truncatingIfNeeded: messagingServerStableUInt64("stable|\(message.messageId)")),
                stableVersion: 0,
                id: id,
                globallyUniqueId: nil,
                groupingKey: nil,
                groupInfo: nil,
                threadId: nil,
                timestamp: timestamp,
                flags: flags,
                tags: [],
                globalTags: [],
                localTags: [],
                customTags: [],
                forwardInfo: nil,
                author: author,
                text: message.displayText,
                attributes: [],
                media: [],
                peers: peers,
                associatedMessages: SimpleDictionary(),
                associatedMessageIds: [],
                associatedMedia: [:],
                associatedThreadInfo: nil,
                associatedStories: [:]
            )
        case let .operation(operation):
            let timestamp = Int32((MessagingServerDate.parse(operation.requestedAt) ?? Date()).timeIntervalSince1970)
            var flags: MessageFlags = [.TopIndexable, .Unsent]
            if operation.localStatus == .failed {
                flags.insert(.Failed)
            } else {
                flags.insert(.Sending)
            }
            let id = MessageId(
                peerId: self.peer.id,
                namespace: Namespaces.Message.Local,
                id: messagingServerStableMessageId("local|\(operation.operationId)")
            )
            let author = self.accountPeer()
            let peers = self.messagePeers(author: author)
            return Message(
                stableId: UInt32(truncatingIfNeeded: messagingServerStableUInt64("stable|\(operation.operationId)")),
                stableVersion: 0,
                id: id,
                globallyUniqueId: nil,
                groupingKey: nil,
                groupInfo: nil,
                threadId: nil,
                timestamp: timestamp,
                flags: flags,
                tags: [],
                globalTags: [],
                localTags: [],
                customTags: [],
                forwardInfo: nil,
                author: author,
                text: operation.suggestedEditText.isEmpty ? operation.statusSummary : operation.suggestedEditText,
                attributes: [],
                media: [],
                peers: peers,
                associatedMessages: SimpleDictionary(),
                associatedMessageIds: [],
                associatedMedia: [:],
                associatedThreadInfo: nil,
                associatedStories: [:]
            )
        }
    }

    private func authorPeer(for message: MessagingServerMessage) -> Peer? {
        switch message.direction {
        case .outgoing:
            return self.accountPeer()
        case .system:
            return nil
        case .incoming:
            switch self.inbox.kind {
            case .group, .channel:
                let senderKey = message.senderId ?? message.senderDisplayName
                let rawId = Int64(bitPattern: messagingServerStableUInt64("sender|\(self.inbox.inboxId)|\(senderKey)")) & 0x0000FFFFFFFFFFFF
                let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(max(1, rawId)))
                return TelegramUser(
                    id: peerId,
                    accessHash: nil,
                    firstName: message.senderDisplayName,
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
            case .dm, .order, .unknown:
                return self.peer
            }
        }
    }

    private func messagePeers(author: Peer?) -> SimpleDictionary<PeerId, Peer> {
        var peers = SimpleDictionary<PeerId, Peer>()
        peers[self.peer.id] = self.peer
        let accountPeer = self.accountPeer()
        peers[accountPeer.id] = accountPeer
        if let author {
            peers[author.id] = author
        }
        return peers
    }

    private func accountPeer() -> TelegramUser {
        return TelegramUser(
            id: self.context.account.peerId,
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

    private func resolveServerMessageId(for replySubject: EngineMessageReplySubject) -> String? {
        return self.referenceMap[replySubject.messageId].flatMap { reference in
            if case let .message(serverMessageId) = reference {
                return serverMessageId
            } else {
                return nil
            }
        }
    }

    private func markLatestReadIfNeeded() {
        guard let latestIncoming = self.messages.last(where: { $0.direction == .incoming || $0.direction == .system }) else {
            return
        }
        guard self.lastMarkedReadMessageId != latestIncoming.messageId else {
            return
        }
        self.lastMarkedReadMessageId = latestIncoming.messageId
        self.client.updateInboxReadState(inboxId: self.inbox.inboxId, lastReadMessageSeq: latestIncoming.messageId) { _ in
        }
    }

    private func makeOptimisticOperation(
        operationId: String = "local:\(UUID().uuidString)",
        preview: String,
        status: MessagingServerOperationStatus,
        error: String?
    ) -> MessagingServerOperationView {
        return MessagingServerOperationView(
            operationId: operationId,
            approvalId: nil,
            operationType: .sendMessage,
            platform: self.inbox.platform,
            accountKey: self.inbox.accountKey,
            inboxId: self.inbox.inboxId,
            messageId: nil,
            preview: preview,
            payload: preview.isEmpty ? [:] : ["text": .string(preview)],
            requestedAt: MessagingServerDate.nowString(),
            executedAt: nil,
            localStatus: status,
            approvalStatus: status == .failed ? nil : .pending,
            executionStatus: status == .failed ? .failed : .pending,
            error: error,
            platformMessageIds: [],
            uploadAssetIds: [],
            uploadAssets: [],
            replacementOperationId: nil,
            localAttachmentNames: nil
        )
    }

    private func upsertOptimisticOperation(_ operation: MessagingServerOperationView, replacing operationId: String? = nil) {
        if let operationId, let index = self.optimisticOperations.firstIndex(where: { $0.operationId == operationId }) {
            self.optimisticOperations[index] = operation
        } else if let index = self.optimisticOperations.firstIndex(where: { $0.operationId == operation.operationId }) {
            self.optimisticOperations[index] = operation
        } else {
            self.optimisticOperations.append(operation)
        }
        self.rebuildHistoryView(updateType: .Generic)
    }

    private func removeOptimisticOperation(operationId: String) {
        self.optimisticOperations.removeAll(where: { $0.operationId == operationId })
    }
}

private func messagingServerStableMessageId(_ value: String) -> Int32 {
    let raw = messagingServerStableUInt64(value) & 0x7fffffff
    return Int32(raw == 0 ? 1 : raw)
}

private func messagingServerStableUInt64(_ value: String) -> UInt64 {
    var hash: UInt64 = 14695981039346656037
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1099511628211
    }
    return hash
}
