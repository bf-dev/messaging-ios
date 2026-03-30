import MobileCoreServices
import Display
import UIKit

final class MessagingServerChatViewController: ViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
    private enum Row {
        case message(MessagingServerMessage)
        case pending(MessagingServerOperationView)

        var stableId: String {
            switch self {
            case let .message(message):
                return "message:\(message.messageId)"
            case let .pending(operation):
                return "operation:\(operation.operationId)"
            }
        }

        var sortDate: Date {
            switch self {
            case let .message(message):
                return MessagingServerDate.parse(message.sentAt) ?? Date.distantPast
            case let .pending(operation):
                return MessagingServerDate.parse(operation.requestedAt) ?? Date.distantPast
            }
        }
    }

    private struct UploadedAssetBatch {
        let assetIds: [String]
        let assets: [MessagingServerCachedAsset]
    }

    private let session: MessagingServerSession
    private let client: MessagingServerAPIClient
    private let inbox: MessagingServerInboxSummary
    private let snapshotStore = MessagingServerSnapshotStore.shared

    private let chatBackgroundView = MessagingServerChatBackgroundView()
    private let titleContainer = UIStackView()
    private let titleAvatarView = MessagingServerAvatarView()
    private let titleStack = UIStackView()
    private let titleTextLabel = UILabel()
    private let subtitleTextLabel = UILabel()

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let emptyStateView = UIStackView()
    private let emptyStateIconView = UIImageView()
    private let emptyStateTitleLabel = UILabel()
    private let emptyStateSubtitleLabel = UILabel()

    private let composerContainer = UIStackView()
    private let attachmentScrollView = UIScrollView()
    private let attachmentStack = UIStackView()
    private let suggestedScrollView = UIScrollView()
    private let suggestedStack = UIStackView()
    private let composerRow = UIStackView()
    private let attachButton = UIButton(type: .system)
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let composerSpinner = UIActivityIndicatorView(style: .medium)

    private var composerBottomConstraint: NSLayoutConstraint?
    private var textViewHeightConstraint: NSLayoutConstraint?

    private var messages: [MessagingServerMessage] = []
    private var serverOperations: [MessagingServerOperationView] = []
    private var optimisticOperations: [MessagingServerOperationView] = []
    private var suggestedReplies: [MessagingServerSuggestedReply] = []
    private var rows: [Row] = []
    private var selectedAttachments: [MessagingServerUploadDraft] = []
    private var realtimeClient: MessagingServerRealtimeClient?
    private var scheduledRefresh: DispatchWorkItem?
    private var connectionState: MessagingServerRealtimeState = .disconnected
    private var lastMarkedReadMessageId: String?
    private var isSending = false
    private var isRefreshingFromServer = false
    private var hasCompletedInitialLoad = false
    private var hasPerformedInitialScroll = false
    private var loadFailureMessage: String?
    private var hasWarnedAboutOperations = false
    private var hasWarnedAboutSuggestedReplies = false

    init(session: MessagingServerSession, client: MessagingServerAPIClient, inbox: MessagingServerInboxSummary) {
        self.session = session
        self.client = client
        self.inbox = inbox
        super.init(navigationBarPresentationData: MessagingServerTelegramPresentation.navigationBarPresentationData())
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        realtimeClient?.disconnect()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "messaging.chat.screen"
        configureBackgroundView()
        configureTitleView()
        configureTableView()
        configureComposer()
        configureKeyboardHandling()
        updateAttachmentPills()
        updateSuggestedReplyPills()
        updateComposerState()
        updateNavigationSubtitle()
        loadCachedConversationIfAvailable()
        loadConversation(showSpinner: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startRealtime()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        performInitialScrollIfNeeded(animated: false)
        markVisibleMessagesReadIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        realtimeClient?.disconnect()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTextViewHeight()
        composerContainer.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.18 : 0.08
    }

    private func configureBackgroundView() {
        chatBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chatBackgroundView)
        NSLayoutConstraint.activate([
            chatBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            chatBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureTitleView() {
        titleContainer.axis = .horizontal
        titleContainer.alignment = .center
        titleContainer.spacing = 8.0

        titleAvatarView.translatesAutoresizingMaskIntoConstraints = false
        titleAvatarView.widthAnchor.constraint(equalToConstant: 32.0).isActive = true
        titleAvatarView.heightAnchor.constraint(equalToConstant: 32.0).isActive = true
        titleAvatarView.configure(session: session, asset: inbox.avatarAsset, title: inbox.avatarTitle)

        titleStack.axis = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1.0

        titleTextLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        titleTextLabel.text = inbox.displayTitle
        titleTextLabel.textAlignment = .left
        titleTextLabel.adjustsFontForContentSizeCategory = true

        subtitleTextLabel.font = UIFont.systemFont(ofSize: 12.0)
        subtitleTextLabel.textColor = .secondaryLabel
        subtitleTextLabel.textAlignment = .left
        subtitleTextLabel.adjustsFontForContentSizeCategory = true

        titleStack.addArrangedSubview(titleTextLabel)
        titleStack.addArrangedSubview(subtitleTextLabel)
        titleContainer.addArrangedSubview(titleAvatarView)
        titleContainer.addArrangedSubview(titleStack)
        navigationItem.titleView = titleContainer
        let infoItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain, target: self, action: #selector(showConversationInfo))
        infoItem.accessibilityIdentifier = "messaging.chat.info"
        infoItem.accessibilityLabel = "Conversation info"
        navigationItem.rightBarButtonItem = infoItem
    }

    private func updateNavigationSubtitle() {
        let stateText: String
        switch connectionState {
        case .connected:
            stateText = "Live updates"
        case .connecting:
            stateText = "Connecting"
        case .reconnecting:
            stateText = "Reconnecting"
        case .disconnected:
            stateText = "Offline"
        }
        let conversationText: String
        switch inbox.kind {
        case .group, .channel:
            conversationText = "\(max(inbox.participantCount, 1)) participants"
        case .order:
            conversationText = "Order chat"
        case .dm, .unknown:
            conversationText = "Conversation"
        }
        subtitleTextLabel.text = "\(conversationText) · \(stateText)"
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(MessagingServerBubbleCell.self, forCellReuseIdentifier: "BubbleCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 96.0
        tableView.contentInset = UIEdgeInsets(top: 8.0, left: 0.0, bottom: 8.0, right: 0.0)
        tableView.accessibilityIdentifier = "messaging.chat.table"

        refreshControl.addTarget(self, action: #selector(refreshConversation), for: .valueChanged)
        tableView.refreshControl = refreshControl

        emptyStateView.axis = .vertical
        emptyStateView.spacing = 10.0
        emptyStateView.alignment = .center
        emptyStateView.layoutMargins = UIEdgeInsets(top: 24.0, left: 24.0, bottom: 24.0, right: 24.0)
        emptyStateView.isLayoutMarginsRelativeArrangement = true
        emptyStateView.accessibilityIdentifier = "messaging.chat.emptyState"

        emptyStateIconView.image = UIImage(systemName: "bubble.left.and.bubble.right")
        emptyStateIconView.tintColor = .secondaryLabel
        emptyStateIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26.0, weight: .regular)

        emptyStateTitleLabel.font = UIFont.systemFont(ofSize: 18.0, weight: .semibold)
        emptyStateTitleLabel.textAlignment = .center
        emptyStateTitleLabel.adjustsFontForContentSizeCategory = true

        emptyStateSubtitleLabel.font = UIFont.systemFont(ofSize: 14.0)
        emptyStateSubtitleLabel.textColor = .secondaryLabel
        emptyStateSubtitleLabel.numberOfLines = 0
        emptyStateSubtitleLabel.textAlignment = .center
        emptyStateSubtitleLabel.adjustsFontForContentSizeCategory = true

        emptyStateView.addArrangedSubview(emptyStateIconView)
        emptyStateView.addArrangedSubview(emptyStateTitleLabel)
        emptyStateView.addArrangedSubview(emptyStateSubtitleLabel)
        tableView.backgroundView = emptyStateView
        tableView.backgroundView?.isHidden = true

        view.addSubview(tableView)
    }

    private func configureComposer() {
        composerContainer.axis = .vertical
        composerContainer.spacing = 8.0
        composerContainer.translatesAutoresizingMaskIntoConstraints = false
        composerContainer.layoutMargins = UIEdgeInsets(top: 10.0, left: 12.0, bottom: 10.0, right: 12.0)
        composerContainer.isLayoutMarginsRelativeArrangement = true
        composerContainer.backgroundColor = UIColor.systemBackground.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.94 : 0.9)
        composerContainer.layer.cornerRadius = 20.0
        composerContainer.layer.cornerCurve = .continuous
        composerContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        composerContainer.layer.borderWidth = 1.0 / UIScreen.main.scale
        composerContainer.layer.borderColor = UIColor.separator.withAlphaComponent(0.24).cgColor
        composerContainer.layer.shadowColor = UIColor.black.cgColor
        composerContainer.layer.shadowRadius = 18.0
        composerContainer.layer.shadowOffset = CGSize(width: 0.0, height: -4.0)

        configureHorizontalScroll(attachmentScrollView, stackView: attachmentStack)
        configureHorizontalScroll(suggestedScrollView, stackView: suggestedStack)

        composerRow.axis = .horizontal
        composerRow.alignment = .bottom
        composerRow.spacing = 10.0

        let attachImage = UIImage(systemName: "paperclip.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28.0, weight: .regular))
        attachButton.setImage(attachImage, for: .normal)
        attachButton.tintColor = view.tintColor
        attachButton.addTarget(self, action: #selector(attachPressed(_:)), for: .touchUpInside)
        attachButton.accessibilityIdentifier = "messaging.chat.attach"
        attachButton.accessibilityLabel = "Add attachment"

        textView.delegate = self
        textView.font = UIFont.systemFont(ofSize: 16.0)
        textView.adjustsFontForContentSizeCategory = true
        textView.layer.cornerRadius = 18.0
        textView.layer.cornerCurve = .continuous
        textView.layer.borderWidth = 1.0
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.backgroundColor = .systemBackground
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 10.0, left: 11.0, bottom: 10.0, right: 11.0)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: 40.0)
        textViewHeightConstraint?.isActive = true
        textView.widthAnchor.constraint(greaterThanOrEqualToConstant: 120.0).isActive = true
        textView.accessibilityIdentifier = "messaging.chat.input"
        textView.accessibilityLabel = "Message"

        placeholderLabel.text = "Message"
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.font = UIFont.systemFont(ofSize: 16.0)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 16.0),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 10.0),
        ])

        let sendImage = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30.0, weight: .regular))
        sendButton.setImage(sendImage, for: .normal)
        sendButton.tintColor = view.tintColor
        sendButton.addTarget(self, action: #selector(sendPressed), for: .touchUpInside)
        sendButton.accessibilityIdentifier = "messaging.chat.send"
        sendButton.accessibilityLabel = "Send message"

        composerSpinner.hidesWhenStopped = true
        composerSpinner.setContentHuggingPriority(.required, for: .horizontal)
        composerSpinner.setContentCompressionResistancePriority(.required, for: .horizontal)

        composerRow.addArrangedSubview(attachButton)
        composerRow.addArrangedSubview(textView)
        composerRow.addArrangedSubview(sendButton)
        composerRow.addArrangedSubview(composerSpinner)

        composerContainer.addArrangedSubview(attachmentScrollView)
        composerContainer.addArrangedSubview(suggestedScrollView)
        composerContainer.addArrangedSubview(composerRow)
        view.addSubview(composerContainer)
        attachmentScrollView.accessibilityIdentifier = "messaging.chat.attachments"
        suggestedScrollView.accessibilityIdentifier = "messaging.chat.suggestions"

        composerBottomConstraint = composerContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        composerBottomConstraint?.isActive = true

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: composerContainer.topAnchor),
            composerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            attachmentScrollView.heightAnchor.constraint(equalToConstant: 34.0),
            suggestedScrollView.heightAnchor.constraint(equalToConstant: 34.0),
        ])
    }

    private func configureHorizontalScroll(_ scrollView: UIScrollView, stackView: UIStackView) {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 8.0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
        ])
    }

    private func configureKeyboardHandling() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let frame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
            let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else {
            return
        }

        let convertedFrame = view.convert(frame, from: view.window)
        let overlap = max(0.0, view.bounds.maxY - convertedFrame.origin.y - view.safeAreaInsets.bottom)
        composerBottomConstraint?.constant = -overlap
        UIView.animate(withDuration: duration, delay: 0.0, options: UIView.AnimationOptions(rawValue: curveValue << 16), animations: {
            self.view.layoutIfNeeded()
        }, completion: nil)
        if overlap > 0.0 {
            scrollToBottom(animated: true)
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        composerBottomConstraint?.constant = 0.0
        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func refreshConversation() {
        loadConversation(showSpinner: true)
    }

    private func loadCachedConversationIfAvailable() {
        guard let snapshot = snapshotStore.loadConversation(inboxId: inbox.inboxId, for: session) else {
            return
        }

        messages = snapshot.messages.filter { $0.deletedAt == nil }
        serverOperations = snapshot.operations
        suggestedReplies = sortedSuggestedReplies(snapshot.suggestedReplies)
        rebuildRows(scrollToBottom: false)
    }

    private func startRealtime() {
        realtimeClient?.disconnect()
        let realtimeClient = MessagingServerRealtimeClient(session: session)
        realtimeClient.onStateChange = { [weak self] state in
            self?.connectionState = state
            self?.updateNavigationSubtitle()
        }
        realtimeClient.onEvent = { [weak self] event in
            guard let self, event.topic == "inbox:\(self.inbox.inboxId)" else {
                return
            }
            self.scheduleConversationRefresh()
        }
        realtimeClient.onError = { [weak self] error in
            self?.showMessagingServerToast(error.localizedDescription)
        }
        self.realtimeClient = realtimeClient
        realtimeClient.connect()
    }

    private func scheduleConversationRefresh() {
        scheduledRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.loadConversation(showSpinner: false)
        }
        scheduledRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func loadConversation(showSpinner: Bool) {
        guard !isRefreshingFromServer else {
            if showSpinner {
                refreshControl.endRefreshing()
            }
            return
        }

        isRefreshingFromServer = true
        loadFailureMessage = nil
        updateEmptyState()

        let shouldScrollToBottom = rows.isEmpty || isNearBottom()

        let group = DispatchGroup()
        var messagesResult: Result<[MessagingServerMessage], Error>?
        var operationsResult: Result<[MessagingServerOperationView], Error>?
        var repliesResult: Result<[MessagingServerSuggestedReply], Error>?

        group.enter()
        client.listMessages(inboxId: inbox.inboxId) { result in
            messagesResult = result
            group.leave()
        }

        group.enter()
        client.listInboxOperations(inboxId: inbox.inboxId, pendingOnly: false) { result in
            operationsResult = result
            group.leave()
        }

        group.enter()
        client.listSuggestedReplies(inboxId: inbox.inboxId) { result in
            repliesResult = result
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else {
                return
            }
            self.isRefreshingFromServer = false
            self.hasCompletedInitialLoad = true
            self.refreshControl.endRefreshing()
            var shouldPersistSnapshot = false

            switch messagesResult {
            case let .success(messages):
                self.messages = messages.filter { $0.deletedAt == nil }
                self.loadFailureMessage = nil
                shouldPersistSnapshot = true
            case let .failure(error):
                self.loadFailureMessage = error.localizedDescription
                if showSpinner || self.rows.isEmpty {
                    self.showMessagingServerToast(error.localizedDescription)
                }
            case .none:
                break
            }

            switch operationsResult {
            case let .success(operations):
                self.serverOperations = operations
                self.optimisticOperations.removeAll { local in
                    operations.contains(where: { $0.operationId == local.operationId }) || !local.isPendingBubble
                }
                shouldPersistSnapshot = true
            case let .failure(error):
                if !self.hasWarnedAboutOperations {
                    self.hasWarnedAboutOperations = true
                    self.showMessagingServerToast("Pending operations unavailable: \(error.localizedDescription)")
                }
            case .none:
                break
            }

            switch repliesResult {
            case let .success(replies):
                self.suggestedReplies = self.sortedSuggestedReplies(replies)
                shouldPersistSnapshot = true
            case let .failure(error):
                if !self.hasWarnedAboutSuggestedReplies {
                    self.hasWarnedAboutSuggestedReplies = true
                    self.showMessagingServerToast("Suggested replies unavailable: \(error.localizedDescription)")
                }
            case .none:
                break
            }

            if shouldPersistSnapshot {
                self.snapshotStore.saveConversation(
                    MessagingServerConversationSnapshot(
                        messages: self.messages,
                        operations: self.serverOperations,
                        suggestedReplies: self.suggestedReplies,
                        updatedAt: MessagingServerDate.nowString()
                    ),
                    inboxId: self.inbox.inboxId,
                    for: self.session
                )
            }

            self.rebuildRows(scrollToBottom: shouldScrollToBottom)
            self.markVisibleMessagesReadIfNeeded()
        }
    }

    private func sortedSuggestedReplies(_ replies: [MessagingServerSuggestedReply]) -> [MessagingServerSuggestedReply] {
        replies.sorted { lhs, rhs in
            if lhs.orderIndex == rhs.orderIndex {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.orderIndex < rhs.orderIndex
        }
    }

    private func rebuildRows(scrollToBottom: Bool) {
        var pendingById = Dictionary(uniqueKeysWithValues: serverOperations.map { ($0.operationId, $0) })
        optimisticOperations.forEach { operation in
            if pendingById[operation.operationId] == nil {
                pendingById[operation.operationId] = operation
            }
        }

        let visibleOperations = Array(pendingById.values).filter { $0.isPendingBubble }
        rows = messages.map(Row.message) + visibleOperations.map(Row.pending)
        rows.sort { lhs, rhs in
            if lhs.sortDate == rhs.sortDate {
                return lhs.stableId < rhs.stableId
            }
            return lhs.sortDate < rhs.sortDate
        }

        tableView.reloadData()
        updateAttachmentPills()
        updateSuggestedReplyPills()
        updateComposerState()
        updateEmptyState()
        updateNavigationSubtitle()

        if scrollToBottom {
            self.scrollToBottom(animated: false)
        }
    }

    private func upsertOptimisticOperation(_ operation: MessagingServerOperationView) {
        if let index = optimisticOperations.firstIndex(where: { $0.operationId == operation.operationId }) {
            optimisticOperations[index] = operation
        } else {
            optimisticOperations.append(operation)
        }
    }

    private func removeOperation(operationId: String) {
        optimisticOperations.removeAll { $0.operationId == operationId }
        serverOperations.removeAll { $0.operationId == operationId }
    }

    private func updateAttachmentPills() {
        attachmentStack.arrangedSubviews.forEach { view in
            attachmentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for attachment in selectedAttachments {
            let button = MessagingServerPillButton(frame: .zero)
            button.rawValue = attachment.id.uuidString
            button.setTitle("\(attachment.filename) ×", for: .normal)
            button.applySelectedStyle(true)
            button.addTarget(self, action: #selector(removeAttachmentPressed(_:)), for: .touchUpInside)
            attachmentStack.addArrangedSubview(button)
        }
        attachmentScrollView.isHidden = selectedAttachments.isEmpty
    }

    private func updateSuggestedReplyPills() {
        suggestedStack.arrangedSubviews.forEach { view in
            suggestedStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let addButton = MessagingServerPillButton(frame: .zero)
        addButton.setTitle("+ Suggestion", for: .normal)
        addButton.applySelectedStyle(false)
        addButton.addTarget(self, action: #selector(addSuggestedReplyPressed), for: .touchUpInside)
        suggestedStack.addArrangedSubview(addButton)

        for reply in suggestedReplies {
            let button = MessagingServerPillButton(frame: .zero)
            button.rawValue = reply.id
            button.setTitle(reply.text, for: .normal)
            button.applySelectedStyle(false)
            button.addTarget(self, action: #selector(suggestedReplyPressed(_:)), for: .touchUpInside)
            suggestedStack.addArrangedSubview(button)
        }
        suggestedScrollView.isHidden = false
    }

    private func updateComposerState() {
        placeholderLabel.isHidden = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasContent = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedAttachments.isEmpty
        sendButton.isEnabled = hasContent && !isSending
        sendButton.alpha = sendButton.isEnabled ? 1.0 : 0.45
        sendButton.tintColor = sendButton.isEnabled ? view.tintColor : .tertiaryLabel
        attachButton.isEnabled = !isSending
        textView.isEditable = !isSending
    }

    private func updateEmptyState() {
        if rows.isEmpty {
            if isRefreshingFromServer && messages.isEmpty && optimisticOperations.isEmpty {
                emptyStateTitleLabel.text = "Loading conversation"
                emptyStateSubtitleLabel.text = "Recent messages will appear here as soon as the server responds."
            } else if let loadFailureMessage, messages.isEmpty && optimisticOperations.isEmpty, hasCompletedInitialLoad {
                emptyStateTitleLabel.text = "Unable to load conversation"
                emptyStateSubtitleLabel.text = "\(loadFailureMessage)\n\nPull down to try again."
            } else {
                emptyStateTitleLabel.text = "No messages yet"
                emptyStateSubtitleLabel.text = "Send a message, attach a file, or use a suggested reply to start the conversation."
            }
            tableView.backgroundView?.isHidden = false
        } else {
            tableView.backgroundView?.isHidden = true
        }
    }

    private func updateTextViewHeight() {
        let targetWidth = max(textView.bounds.width, view.bounds.width - 140.0)
        let fittingSize = CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
        let height = min(max(textView.sizeThatFits(fittingSize).height, 40.0), 120.0)
        textViewHeightConstraint?.constant = height
    }

    @objc private func showConversationInfo() {
        let pendingCount = rows.compactMap { row -> MessagingServerOperationView? in
            if case let .pending(operation) = row {
                return operation
            }
            return nil
        }.count

        let message = [
            "Inbox ID: \(inbox.inboxId)",
            "Messages loaded: \(messages.count)",
            "Pending outgoing bubbles: \(pendingCount)",
            "Suggested replies: \(suggestedReplies.count)",
            "Server: \(session.displayBaseURL)",
        ].joined(separator: "\n")

        let alert = UIAlertController(title: inbox.displayTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func attachPressed(_ sender: UIButton) {
        let alert = UIAlertController(title: "Attach", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Photo Library", style: .default, handler: { [weak self] _ in
            self?.presentPhotoPicker()
        }))
        alert.addAction(UIAlertAction(title: "Files", style: .default, handler: { [weak self] _ in
            self?.presentDocumentPicker()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        present(alert, animated: true)
    }

    private func presentPhotoPicker() {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            showMessagingServerToast("Photo library is unavailable.")
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = [kUTTypeImage as String, kUTTypeMovie as String]
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(documentTypes: [kUTTypeData as String], in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    @objc private func sendPressed() {
        guard !isSending else {
            return
        }

        let trimmedText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = selectedAttachments
        guard !trimmedText.isEmpty || !attachments.isEmpty else {
            return
        }

        let requestedAt = MessagingServerDate.nowString()
        let tempOperationId = "local:\(UUID().uuidString)"
        let attachmentNames = attachments.map(\.filename)
        let localPending = localSendOperation(
            operationId: tempOperationId,
            approvalId: nil,
            text: trimmedText,
            requestedAt: requestedAt,
            localStatus: .approvalRequested,
            approvalStatus: .pending,
            executionStatus: .pending,
            error: nil,
            uploadAssetIds: [],
            uploadAssets: [],
            localAttachmentNames: attachmentNames
        )
        upsertOptimisticOperation(localPending)
        clearComposerDraft()
        rebuildRows(scrollToBottom: true)
        setSending(true)

        uploadAttachments(attachments) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .success(batch):
                let uploadedLocal = self.localSendOperation(
                    operationId: tempOperationId,
                    approvalId: nil,
                    text: trimmedText,
                    requestedAt: requestedAt,
                    localStatus: .approvalRequested,
                    approvalStatus: .pending,
                    executionStatus: .pending,
                    error: nil,
                    uploadAssetIds: batch.assetIds,
                    uploadAssets: batch.assets,
                    localAttachmentNames: attachmentNames
                )
                self.upsertOptimisticOperation(uploadedLocal)
                self.rebuildRows(scrollToBottom: true)

                let requestBody = MessagingServerSendMessageRequest(
                    text: trimmedText.isEmpty ? nil : trimmedText,
                    media: [],
                    uploadIds: batch.assetIds.isEmpty ? nil : batch.assetIds,
                    replyToMessageId: nil
                )
                self.client.sendMessage(inboxId: self.inbox.inboxId, requestBody: requestBody) { sendResult in
                    self.setSending(false)
                    switch sendResult {
                    case let .success(approval):
                        self.handleSendSuccess(
                            approval: approval,
                            text: trimmedText,
                            requestedAt: requestedAt,
                            tempOperationId: tempOperationId,
                            assetIds: batch.assetIds,
                            uploadAssets: batch.assets,
                            localAttachmentNames: attachmentNames
                        )
                    case let .failure(error):
                        let failedOperation = self.localSendOperation(
                            operationId: tempOperationId,
                            approvalId: nil,
                            text: trimmedText,
                            requestedAt: requestedAt,
                            localStatus: .failed,
                            approvalStatus: nil,
                            executionStatus: .failed,
                            error: error.localizedDescription,
                            uploadAssetIds: batch.assetIds,
                            uploadAssets: batch.assets,
                            localAttachmentNames: attachmentNames
                        )
                        self.upsertOptimisticOperation(failedOperation)
                        self.rebuildRows(scrollToBottom: true)
                        self.presentMessagingServerError(error, title: "Send Failed")
                    }
                }
            case let .failure(error):
                self.setSending(false)
                let failedOperation = self.localSendOperation(
                    operationId: tempOperationId,
                    approvalId: nil,
                    text: trimmedText,
                    requestedAt: requestedAt,
                    localStatus: .failed,
                    approvalStatus: nil,
                    executionStatus: .failed,
                    error: error.localizedDescription,
                    uploadAssetIds: [],
                    uploadAssets: [],
                    localAttachmentNames: attachmentNames
                )
                self.upsertOptimisticOperation(failedOperation)
                self.rebuildRows(scrollToBottom: true)
                self.presentMessagingServerError(error, title: "Upload Failed")
            }
        }
    }

    private func localSendOperation(
        operationId: String,
        approvalId: String?,
        text: String,
        requestedAt: String,
        localStatus: MessagingServerOperationStatus,
        approvalStatus: MessagingServerApprovalStatus?,
        executionStatus: MessagingServerApprovalExecutionStatus?,
        error: String?,
        uploadAssetIds: [String],
        uploadAssets: [MessagingServerCachedAsset],
        localAttachmentNames: [String]
    ) -> MessagingServerOperationView {
        let preview: String
        if !text.isEmpty {
            preview = text
        } else if let firstAttachmentName = localAttachmentNames.first {
            preview = firstAttachmentName
        } else {
            preview = "Attachment"
        }

        return MessagingServerOperationView(
            operationId: operationId,
            approvalId: approvalId,
            operationType: .sendMessage,
            platform: inbox.platform,
            accountKey: inbox.accountKey,
            inboxId: inbox.inboxId,
            messageId: nil,
            preview: preview,
            payload: text.isEmpty ? [:] : ["text": .string(text)],
            requestedAt: requestedAt,
            executedAt: nil,
            localStatus: localStatus,
            approvalStatus: approvalStatus,
            executionStatus: executionStatus,
            error: error,
            platformMessageIds: [],
            uploadAssetIds: uploadAssetIds,
            uploadAssets: uploadAssets,
            replacementOperationId: nil,
            localAttachmentNames: localAttachmentNames
        )
    }

    private func clearComposerDraft() {
        textView.text = ""
        selectedAttachments.removeAll()
        updateTextViewHeight()
        updateAttachmentPills()
        updateComposerState()
    }

    private func handleSendSuccess(
        approval: MessagingServerApprovalResult,
        text: String,
        requestedAt: String,
        tempOperationId: String,
        assetIds: [String],
        uploadAssets: [MessagingServerCachedAsset],
        localAttachmentNames: [String]
    ) {
        removeOperation(operationId: tempOperationId)

        let fallbackOperation = localSendOperation(
            operationId: approval.operationId,
            approvalId: approval.approvalId,
            text: text,
            requestedAt: requestedAt,
            localStatus: .approvalRequested,
            approvalStatus: .pending,
            executionStatus: .pending,
            error: nil,
            uploadAssetIds: assetIds,
            uploadAssets: uploadAssets,
            localAttachmentNames: localAttachmentNames
        )
        upsertOptimisticOperation(fallbackOperation)
        rebuildRows(scrollToBottom: true)
        showMessagingServerToast("Message queued for approval.")

        client.getOperation(operationId: approval.operationId) { [weak self] result in
            guard let self else {
                return
            }
            if case let .success(operation) = result {
                self.upsertOptimisticOperation(operation)
                self.rebuildRows(scrollToBottom: true)
            }
            self.loadConversation(showSpinner: false)
        }
    }

    private func setSending(_ sending: Bool) {
        isSending = sending
        if sending {
            composerSpinner.startAnimating()
        } else {
            composerSpinner.stopAnimating()
        }
        updateComposerState()
    }

    private func uploadAttachments(
        _ attachments: [MessagingServerUploadDraft],
        collectedIds: [String] = [],
        collectedAssets: [MessagingServerCachedAsset] = [],
        completion: @escaping (Result<UploadedAssetBatch, Error>) -> Void
    ) {
        guard let first = attachments.first else {
            completion(.success(UploadedAssetBatch(assetIds: collectedIds, assets: collectedAssets)))
            return
        }

        client.uploadAttachment(first) { [weak self] result in
            guard self != nil else {
                return
            }
            switch result {
            case let .success(asset):
                var remaining = attachments
                remaining.removeFirst()
                self?.uploadAttachments(
                    remaining,
                    collectedIds: collectedIds + [asset.assetId],
                    collectedAssets: collectedAssets + [asset],
                    completion: completion
                )
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    @objc private func removeAttachmentPressed(_ sender: MessagingServerPillButton) {
        guard let rawValue = sender.rawValue, let identifier = UUID(uuidString: rawValue) else {
            return
        }
        selectedAttachments.removeAll { $0.id == identifier }
        updateAttachmentPills()
        updateComposerState()
    }

    @objc private func suggestedReplyPressed(_ sender: MessagingServerPillButton) {
        guard let rawValue = sender.rawValue, let reply = suggestedReplies.first(where: { $0.id == rawValue }) else {
            return
        }
        textView.text = reply.text
        updateTextViewHeight()
        updateComposerState()
        _ = textView.becomeFirstResponder()
    }

    @objc private func addSuggestedReplyPressed() {
        let alert = UIAlertController(title: "New Suggested Reply", message: "Create a reusable reply chip for this chat.", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Reply text"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return
            }
            self.client.createSuggestedReply(inboxId: self.inbox.inboxId, text: text) { result in
                switch result {
                case let .success(reply):
                    self.suggestedReplies.append(reply)
                    self.suggestedReplies.sort { lhs, rhs in
                        if lhs.orderIndex == rhs.orderIndex {
                            return lhs.createdAt < rhs.createdAt
                        }
                        return lhs.orderIndex < rhs.orderIndex
                    }
                    self.updateSuggestedReplyPills()
                    self.showMessagingServerToast("Suggested reply added.")
                case let .failure(error):
                    self.presentMessagingServerError(error, title: "Unable to Save")
                }
            }
        }))
        present(alert, animated: true)
    }

    func textViewDidChange(_ textView: UITextView) {
        updateTextViewHeight()
        updateComposerState()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === tableView else {
            return
        }
        markVisibleMessagesReadIfNeeded()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === tableView, !decelerate else {
            return
        }
        markVisibleMessagesReadIfNeeded()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "BubbleCell", for: indexPath) as? MessagingServerBubbleCell else {
            return UITableViewCell()
        }

        switch rows[indexPath.row] {
        case let .message(message):
            cell.configure(bubbleConfiguration(for: message), session: session)
            cell.accessibilityIdentifier = "messaging.chat.message.\(message.messageId)"
        case let .pending(operation):
            cell.configure(bubbleConfiguration(for: operation), session: session)
            cell.accessibilityIdentifier = "messaging.chat.pending.\(operation.operationId)"
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard rows.indices.contains(indexPath.row) else {
            return
        }
        if case let .pending(operation) = rows[indexPath.row] {
            let sourceCell = tableView.cellForRow(at: indexPath)
            presentPendingActionSheet(for: operation, sourceView: sourceCell)
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard rows.indices.contains(indexPath.row) else {
            return nil
        }
        switch rows[indexPath.row] {
        case let .pending(operation):
            return UIContextMenuConfiguration(identifier: operation.operationId as NSString, previewProvider: nil) { [weak self] _ in
                self?.pendingMenu(for: operation)
            }
        case let .message(message):
            return UIContextMenuConfiguration(identifier: message.messageId as NSString, previewProvider: nil) { [weak self] _ in
                self?.messageMenu(for: message)
            }
        }
    }

    private func bubbleConfiguration(for message: MessagingServerMessage) -> MessagingServerBubbleConfiguration {
        let showsSenderIdentity = inbox.kind == .group || inbox.kind == .channel
        let title: String?
        switch message.direction {
        case .incoming:
            title = showsSenderIdentity ? message.senderDisplayName : nil
        case .system:
            title = "System"
        case .outgoing:
            title = nil
        }

        let footer = MessagingServerDate.conversationTimestamp(message.sentAt)
        let attachmentSummary: String?
        if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !message.previewAssets.isEmpty {
            attachmentSummary = nil
        } else {
            attachmentSummary = message.attachmentSummary
        }

        return MessagingServerBubbleConfiguration(
            title: title,
            replyText: replyText(for: message),
            body: message.displayText,
            attachments: attachmentSummary,
            footer: footer,
            status: message.editedAt != nil ? "Edited" : nil,
            reactions: message.reactionsSummary,
            previewAssets: message.previewAssets,
            isOutgoing: message.direction == .outgoing,
            isPending: false,
            isFailed: false,
            showsAvatar: message.direction == .incoming && showsSenderIdentity,
            avatarAsset: message.senderProfileAsset,
            avatarTitle: message.senderDisplayName
        )
    }

    private func bubbleConfiguration(for operation: MessagingServerOperationView) -> MessagingServerBubbleConfiguration {
        MessagingServerBubbleConfiguration(
            title: nil,
            replyText: nil,
            body: operation.suggestedEditText,
            attachments: operation.attachmentSummary,
            footer: MessagingServerDate.conversationTimestamp(operation.requestedAt),
            status: operation.statusSummary,
            reactions: nil,
            previewAssets: operation.previewAssets,
            isOutgoing: true,
            isPending: operation.localStatus != .failed,
            isFailed: operation.localStatus == .failed,
            showsAvatar: false,
            avatarAsset: nil,
            avatarTitle: "You"
        )
    }

    private func replyText(for message: MessagingServerMessage) -> String? {
        guard let replyId = message.replyToMessageId, let repliedMessage = messages.first(where: { $0.messageId == replyId }) else {
            return nil
        }
        let prefix = repliedMessage.direction == .outgoing ? "You" : repliedMessage.senderDisplayName
        let summary = repliedMessage.displayText.replacingOccurrences(of: "\n", with: " ")
        return "\(prefix): \(String(summary.prefix(90)))"
    }

    private func pendingMenu(for operation: MessagingServerOperationView) -> UIMenu {
        var actions: [UIMenuElement] = []

        if !operation.isLocalOnly {
            actions.append(UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.presentEditOperationPrompt(operation)
            })
            if operation.approvalStatus == .pending || operation.localStatus == .approvalRequested {
                actions.append(UIAction(title: "Approve", image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                    self?.approveOperation(operation)
                })
                actions.append(UIAction(title: "Deny", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { [weak self] _ in
                    self?.denyOperation(operation)
                })
            }
            if operation.localStatus == .approved || operation.localStatus == .executing {
                actions.append(UIAction(title: "Cancel", image: UIImage(systemName: "slash.circle")) { [weak self] _ in
                    self?.cancelOperation(operation)
                })
            }
        }

        actions.append(UIAction(title: "Details", image: UIImage(systemName: "info.circle")) { [weak self] _ in
            self?.showOperationDetails(operation)
        })

        if operation.isLocalOnly {
            actions.append(UIAction(title: "Dismiss Bubble", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.removeOperation(operationId: operation.operationId)
                self?.rebuildRows(scrollToBottom: false)
            })
        }

        return UIMenu(title: "Pending Message", children: actions)
    }

    private func messageMenu(for message: MessagingServerMessage) -> UIMenu {
        let reactMenu = UIMenu(title: "React", children: [
            UIAction(title: "👍") { [weak self] _ in self?.submitReaction(for: message, emoji: "👍", remove: false) },
            UIAction(title: "❤️") { [weak self] _ in self?.submitReaction(for: message, emoji: "❤️", remove: false) },
            UIAction(title: "Custom…") { [weak self] _ in self?.presentReactionPrompt(for: message, remove: false) },
        ])

        var actions: [UIMenuElement] = [
            reactMenu,
            UIAction(title: "Remove Reaction…", image: UIImage(systemName: "minus.circle")) { [weak self] _ in
                self?.presentReactionPrompt(for: message, remove: true)
            },
        ]

        if message.direction == .outgoing {
            actions.insert(UIAction(title: "Edit Message", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
                self?.presentMessageEditPrompt(message)
            }, at: 0)
            actions.append(UIAction(title: "Delete Message", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.presentDeleteConfirmation(for: message)
            })
        }

        return UIMenu(title: "Message", children: actions)
    }

    private func presentPendingActionSheet(for operation: MessagingServerOperationView, sourceView: UIView?) {
        let alert = UIAlertController(title: "Pending Message", message: operation.statusSummary, preferredStyle: .actionSheet)

        if !operation.isLocalOnly {
            alert.addAction(UIAlertAction(title: "Edit", style: .default, handler: { [weak self] _ in
                self?.presentEditOperationPrompt(operation)
            }))
            if operation.approvalStatus == .pending || operation.localStatus == .approvalRequested {
                alert.addAction(UIAlertAction(title: "Approve", style: .default, handler: { [weak self] _ in
                    self?.approveOperation(operation)
                }))
                alert.addAction(UIAlertAction(title: "Deny", style: .destructive, handler: { [weak self] _ in
                    self?.denyOperation(operation)
                }))
            }
            if operation.localStatus == .approved || operation.localStatus == .executing {
                alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { [weak self] _ in
                    self?.cancelOperation(operation)
                }))
            }
        }

        alert.addAction(UIAlertAction(title: "Details", style: .default, handler: { [weak self] _ in
            self?.showOperationDetails(operation)
        }))

        if operation.isLocalOnly {
            alert.addAction(UIAlertAction(title: "Dismiss Bubble", style: .destructive, handler: { [weak self] _ in
                self?.removeOperation(operationId: operation.operationId)
                self?.rebuildRows(scrollToBottom: false)
            }))
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sourceView ?? view
            popover.sourceRect = sourceView?.bounds ?? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        present(alert, animated: true)
    }

    private func presentEditOperationPrompt(_ operation: MessagingServerOperationView) {
        let alert = UIAlertController(title: "Edit Pending Message", message: "This updates the pending approval request.", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = operation.suggestedEditText
            textField.placeholder = "Message text"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self, weak alert] _ in
            guard let self else {
                return
            }
            let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let requestBody = MessagingServerSendMessageRequest(
                text: text?.isEmpty == true ? nil : text,
                media: [],
                uploadIds: operation.uploadAssetIds.isEmpty ? nil : operation.uploadAssetIds,
                replyToMessageId: nil
            )
            self.client.replacePendingOperation(operationId: operation.operationId, requestBody: requestBody) { result in
                switch result {
                case let .success(updatedOperation):
                    self.removeOperation(operationId: operation.operationId)
                    self.upsertOptimisticOperation(updatedOperation)
                    self.rebuildRows(scrollToBottom: true)
                    self.showMessagingServerToast("Pending message updated.")
                    self.loadConversation(showSpinner: false)
                case let .failure(error):
                    self.presentMessagingServerError(error, title: "Edit Failed")
                }
            }
        }))
        present(alert, animated: true)
    }

    private func approveOperation(_ operation: MessagingServerOperationView) {
        client.approveOperation(operationId: operation.operationId) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .success(updatedOperation):
                self.upsertOptimisticOperation(updatedOperation)
                self.rebuildRows(scrollToBottom: true)
                self.showMessagingServerToast("Pending message approved.")
                self.loadConversation(showSpinner: false)
            case let .failure(error):
                self.presentMessagingServerError(error, title: "Approve Failed")
            }
        }
    }

    private func denyOperation(_ operation: MessagingServerOperationView) {
        client.denyOperation(operationId: operation.operationId) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .success(updatedOperation):
                self.removeOperation(operationId: operation.operationId)
                if updatedOperation.isPendingBubble {
                    self.upsertOptimisticOperation(updatedOperation)
                }
                self.rebuildRows(scrollToBottom: true)
                self.showMessagingServerToast("Pending message denied.")
                self.loadConversation(showSpinner: false)
            case let .failure(error):
                self.presentMessagingServerError(error, title: "Deny Failed")
            }
        }
    }

    private func cancelOperation(_ operation: MessagingServerOperationView) {
        client.cancelOperation(operationId: operation.operationId) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .success(updatedOperation):
                self.removeOperation(operationId: operation.operationId)
                if updatedOperation.isPendingBubble {
                    self.upsertOptimisticOperation(updatedOperation)
                }
                self.rebuildRows(scrollToBottom: true)
                self.showMessagingServerToast("Pending message cancelled.")
                self.loadConversation(showSpinner: false)
            case let .failure(error):
                self.presentMessagingServerError(error, title: "Cancel Failed")
            }
        }
    }

    private func presentMessageEditPrompt(_ message: MessagingServerMessage) {
        let alert = UIAlertController(title: "Edit Message", message: "Create an approval-backed edit request.", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = message.text
            textField.placeholder = "Message text"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return
            }
            self.client.editMessage(messageId: message.messageId, requestBody: MessagingServerEditMessageRequest(text: text)) { result in
                self.handleApprovalResult(result, successMessage: "Edit queued for approval.")
            }
        }))
        present(alert, animated: true)
    }

    private func presentDeleteConfirmation(for message: MessagingServerMessage) {
        let alert = UIAlertController(title: "Delete Message", message: "Create an approval-backed delete request for this message?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { [weak self] _ in
            guard let self else {
                return
            }
            self.client.deleteMessage(messageId: message.messageId) { result in
                self.handleApprovalResult(result, successMessage: "Delete queued for approval.")
            }
        }))
        present(alert, animated: true)
    }

    private func presentReactionPrompt(for message: MessagingServerMessage, remove: Bool) {
        let alert = UIAlertController(title: remove ? "Remove Reaction" : "Add Reaction", message: "Enter the emoji to \(remove ? "remove" : "add").", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "👍"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: remove ? "Remove" : "Add", style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let emoji = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !emoji.isEmpty else {
                return
            }
            self.submitReaction(for: message, emoji: emoji, remove: remove)
        }))
        present(alert, animated: true)
    }

    private func submitReaction(for message: MessagingServerMessage, emoji: String, remove: Bool) {
        let request = MessagingServerMessageReactionRequest(emoji: emoji, reactionKey: nil, remove: remove ? true : nil)
        client.reactToMessage(messageId: message.messageId, requestBody: request) { [weak self] result in
            self?.handleApprovalResult(result, successMessage: remove ? "Reaction removal queued for approval." : "Reaction queued for approval.")
        }
    }

    private func handleApprovalResult(_ result: Result<MessagingServerApprovalResult, Error>, successMessage: String) {
        switch result {
        case .success:
            showMessagingServerToast(successMessage)
            loadConversation(showSpinner: false)
        case let .failure(error):
            presentMessagingServerError(error, title: "Request Failed")
        }
    }

    private func showOperationDetails(_ operation: MessagingServerOperationView) {
        let baseDetails = [
            "Operation ID: \(operation.operationId)",
            operation.approvalId.map { "Approval ID: \($0)" },
            "Status: \(operation.localStatus.rawValue)",
            operation.approvalStatus.map { "Approval: \($0.rawValue)" },
            operation.executionStatus.map { "Execution: \($0.rawValue)" },
            "Requested: \(MessagingServerDate.short(operation.requestedAt))",
            operation.error.map { "Error: \($0)" },
            operation.preview.isEmpty ? nil : "Preview: \(operation.preview)",
        ].compactMap { $0 }.joined(separator: "\n")

        guard let approvalId = operation.approvalId else {
            let alert = UIAlertController(title: "Operation Details", message: baseDetails, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        client.getProof(approvalId: approvalId) { [weak self] result in
            guard let self else {
                return
            }
            let proofText: String
            switch result {
            case let .success(proof):
                proofText = [
                    baseDetails,
                    "Proof Status: \(proof.status.rawValue)",
                    proof.executedAt.map { "Executed: \(MessagingServerDate.short($0))" },
                    proof.error.map { "Proof Error: \($0)" },
                    proof.responseSnippet.map { "Response: \($0)" },
                ].compactMap { $0 }.joined(separator: "\n\n")
            case let .failure(error):
                proofText = baseDetails + "\n\nProof lookup failed: \(error.localizedDescription)"
            }
            let alert = UIAlertController(title: "Operation Details", message: proofText, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }

    private func isNearBottom() -> Bool {
        let offsetY = tableView.contentOffset.y
        let visibleHeight = tableView.bounds.height - tableView.adjustedContentInset.top - tableView.adjustedContentInset.bottom
        let threshold = max(80.0, tableView.contentSize.height - visibleHeight - 60.0)
        return offsetY >= threshold
    }

    private func scrollToBottom(animated: Bool) {
        guard !rows.isEmpty else {
            return
        }
        let indexPath = IndexPath(row: rows.count - 1, section: 0)
        DispatchQueue.main.async {
            guard self.tableView.numberOfRows(inSection: 0) > indexPath.row else {
                return
            }
            self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
            self.markVisibleMessagesReadIfNeeded()
        }
    }

    private func performInitialScrollIfNeeded(animated: Bool) {
        guard !hasPerformedInitialScroll, view.window != nil, !rows.isEmpty else {
            return
        }
        hasPerformedInitialScroll = true
        scrollToBottom(animated: animated)
    }

    private func visibleMessageIdForReadState() -> String? {
        let visibleRows = (tableView.indexPathsForVisibleRows ?? []).sorted()
        for indexPath in visibleRows.reversed() {
            guard rows.indices.contains(indexPath.row) else {
                continue
            }
            if case let .message(message) = rows[indexPath.row] {
                return message.messageId
            }
        }
        return messages.last?.messageId
    }

    private func markVisibleMessagesReadIfNeeded() {
        guard view.window != nil, let messageId = visibleMessageIdForReadState(), messageId != lastMarkedReadMessageId else {
            return
        }
        lastMarkedReadMessageId = messageId
        client.updateInboxReadState(inboxId: inbox.inboxId, lastReadMessageSeq: messageId) { [weak self] result in
            guard let self else {
                return
            }
            if case .failure = result, self.lastMarkedReadMessageId == messageId {
                self.lastMarkedReadMessageId = nil
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        defer { picker.dismiss(animated: true) }

        if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) {
            let sourceURL = info[.imageURL] as? URL
            let filename = sourceURL?.lastPathComponent ?? "photo-\(Int(Date().timeIntervalSince1970)).jpg"
            selectedAttachments.append(MessagingServerUploadDraft(filename: filename, mimeType: "image/jpeg", data: data))
            updateAttachmentPills()
            updateComposerState()
            return
        }

        if let mediaURL = info[.mediaURL] as? URL, let data = try? Data(contentsOf: mediaURL) {
            let filename = mediaURL.lastPathComponent
            let mimeType = mimeType(for: mediaURL)
            selectedAttachments.append(MessagingServerUploadDraft(filename: filename, mimeType: mimeType, data: data))
            updateAttachmentPills()
            updateComposerState()
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            if let data = try? Data(contentsOf: url) {
                let filename = url.lastPathComponent.isEmpty ? "file-\(Int(Date().timeIntervalSince1970))" : url.lastPathComponent
                selectedAttachments.append(MessagingServerUploadDraft(filename: filename, mimeType: mimeType(for: url), data: data))
            }
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        updateAttachmentPills()
        updateComposerState()
    }

    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "heic":
            return "image/heic"
        case "mov":
            return "video/quicktime"
        case "mp4":
            return "video/mp4"
        case "pdf":
            return "application/pdf"
        case "txt":
            return "text/plain"
        case "zip":
            return "application/zip"
        default:
            return "application/octet-stream"
        }
    }
}
