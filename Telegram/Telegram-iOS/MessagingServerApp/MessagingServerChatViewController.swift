import MobileCoreServices
import UIKit

final class MessagingServerChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
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

    private let session: MessagingServerSession
    private let client: MessagingServerAPIClient
    private let inbox: MessagingServerInboxSummary

    private let tableView = UITableView(frame: .zero, style: .plain)
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

    private var messages: [MessagingServerMessage] = []
    private var serverOperations: [MessagingServerOperationView] = []
    private var optimisticOperations: [MessagingServerOperationView] = []
    private var suggestedReplies: [MessagingServerSuggestedReply] = []
    private var rows: [Row] = []
    private var selectedAttachments: [MessagingServerUploadDraft] = []
    private var realtimeClient: MessagingServerRealtimeClient?
    private var scheduledRefresh: DispatchWorkItem?
    private var isSending = false
    private var hasWarnedAboutOperations = false
    private var hasWarnedAboutSuggestedReplies = false

    init(session: MessagingServerSession, client: MessagingServerAPIClient, inbox: MessagingServerInboxSummary) {
        self.session = session
        self.client = client
        self.inbox = inbox
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        realtimeClient?.disconnect()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = inbox.inboxName.isEmpty ? inbox.inboxId : inbox.inboxName
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Status", style: .plain, target: self, action: #selector(statusPressed))

        configureTableView()
        configureComposer()
        configureKeyboardHandling()
        updateAttachmentPills()
        updateSuggestedReplyPills()
        updatePlaceholderVisibility()

        loadConversation(showSpinner: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startRealtime()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        realtimeClient?.disconnect()
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(MessagingServerBubbleCell.self, forCellReuseIdentifier: "BubbleCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemGroupedBackground
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80.0
        view.addSubview(tableView)
    }

    private func configureComposer() {
        composerContainer.axis = .vertical
        composerContainer.spacing = 8.0
        composerContainer.translatesAutoresizingMaskIntoConstraints = false
        composerContainer.layoutMargins = UIEdgeInsets(top: 10.0, left: 12.0, bottom: 10.0, right: 12.0)
        composerContainer.isLayoutMarginsRelativeArrangement = true
        composerContainer.backgroundColor = .secondarySystemBackground

        configureHorizontalScroll(attachmentScrollView, stackView: attachmentStack)
        configureHorizontalScroll(suggestedScrollView, stackView: suggestedStack)
        attachmentScrollView.isHidden = true
        suggestedScrollView.isHidden = false

        composerRow.axis = .horizontal
        composerRow.alignment = .center
        composerRow.spacing = 10.0

        attachButton.setImage(UIImage(systemName: "paperclip.circle.fill"), for: .normal)
        attachButton.tintColor = view.tintColor
        attachButton.addTarget(self, action: #selector(attachPressed(_:)), for: .touchUpInside)

        textView.delegate = self
        textView.font = UIFont.systemFont(ofSize: 16.0)
        textView.layer.cornerRadius = 18.0
        textView.layer.borderWidth = 1.0
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.backgroundColor = .systemBackground
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 9.0, left: 10.0, bottom: 9.0, right: 10.0)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        placeholderLabel.text = "Message"
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.font = UIFont.systemFont(ofSize: 16.0)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 16.0),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 9.0),
        ])

        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        sendButton.tintColor = view.tintColor
        sendButton.addTarget(self, action: #selector(sendPressed), for: .touchUpInside)

        composerSpinner.hidesWhenStopped = true
        composerSpinner.setContentHuggingPriority(.required, for: .horizontal)
        composerSpinner.setContentCompressionResistancePriority(.required, for: .horizontal)

        composerRow.addArrangedSubview(attachButton)
        composerRow.addArrangedSubview(textView)
        composerRow.addArrangedSubview(sendButton)
        composerRow.addArrangedSubview(composerSpinner)
        textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40.0).isActive = true
        textView.widthAnchor.constraint(greaterThanOrEqualToConstant: 120.0).isActive = true

        composerContainer.addArrangedSubview(attachmentScrollView)
        composerContainer.addArrangedSubview(suggestedScrollView)
        composerContainer.addArrangedSubview(composerRow)
        view.addSubview(composerContainer)

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
        view.layoutIfNeeded()
    }

    private func startRealtime() {
        realtimeClient?.disconnect()
        let realtimeClient = MessagingServerRealtimeClient(session: session)
        realtimeClient.onEvent = { [weak self] event in
            guard let self else {
                return
            }
            guard event.topic == "inbox:\(self.inbox.inboxId)" else {
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
        if showSpinner {
            composerSpinner.startAnimating()
        }

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
            if showSpinner {
                self.composerSpinner.stopAnimating()
            }

            switch messagesResult {
            case let .success(messages):
                self.messages = messages.filter { $0.deletedAt == nil }
            case let .failure(error):
                if showSpinner {
                    self.presentMessagingServerError(error, title: "Unable to Load Messages")
                } else {
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
                self.suggestedReplies = replies.sorted { lhs, rhs in
                    if lhs.orderIndex == rhs.orderIndex {
                        return lhs.createdAt < rhs.createdAt
                    }
                    return lhs.orderIndex < rhs.orderIndex
                }
            case let .failure(error):
                if !self.hasWarnedAboutSuggestedReplies {
                    self.hasWarnedAboutSuggestedReplies = true
                    self.showMessagingServerToast("Suggested replies unavailable: \(error.localizedDescription)")
                }
            case .none:
                break
            }

            self.rebuildRows(scrollToBottom: true)
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
        updatePlaceholderVisibility()
        if scrollToBottom {
            scrollToBottom(animated: false)
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
        attachmentScrollView.isHidden = selectedAttachments.isEmpty
        for attachment in selectedAttachments {
            let button = MessagingServerPillButton(frame: .zero)
            button.rawValue = attachment.id.uuidString
            button.setTitle("\(attachment.filename) ×", for: .normal)
            button.applySelectedStyle(true)
            button.addTarget(self, action: #selector(removeAttachmentPressed(_:)), for: .touchUpInside)
            attachmentStack.addArrangedSubview(button)
        }
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

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func statusPressed() {
        let pendingCount = serverOperations.filter { $0.isPendingBubble }.count + optimisticOperations.filter { $0.isPendingBubble }.count
        let backgroundActionCount = serverOperations.filter { !$0.isPendingBubble }.count
        let message = [
            "Inbox ID: \(inbox.inboxId)",
            "Platform: \(inbox.platform.displayName)",
            "Account: \(inbox.accountKey)",
            "Messages loaded: \(messages.count)",
            "Pending outgoing bubbles: \(pendingCount)",
            "Other pending actions: \(backgroundActionCount)",
            "Suggested replies: \(suggestedReplies.count)",
            "Server: \(session.displayBaseURL)",
        ].joined(separator: "\n")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
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
        let trimmedText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !selectedAttachments.isEmpty else {
            return
        }
        setSending(true)
        uploadAttachments(selectedAttachments, collectedAssetIds: []) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .success(assetIds):
                let requestBody = MessagingServerSendMessageRequest(
                    text: trimmedText.isEmpty ? nil : trimmedText,
                    media: [],
                    uploadIds: assetIds.isEmpty ? nil : assetIds,
                    replyToMessageId: nil
                )
                self.client.sendMessage(inboxId: self.inbox.inboxId, requestBody: requestBody) { sendResult in
                    self.setSending(false)
                    switch sendResult {
                    case let .success(approval):
                        self.handleSendSuccess(approval: approval, text: trimmedText, uploadAssetIds: assetIds)
                    case let .failure(error):
                        self.presentMessagingServerError(error, title: "Send Failed")
                    }
                }
            case let .failure(error):
                self.setSending(false)
                self.presentMessagingServerError(error, title: "Upload Failed")
            }
        }
    }

    private func handleSendSuccess(approval: MessagingServerApprovalResult, text: String, uploadAssetIds: [String]) {
        let fallbackPreview = !text.isEmpty ? text : (selectedAttachments.first?.filename ?? "Attachment")
        let fallbackOperation = MessagingServerOperationView(
            operationId: approval.operationId,
            approvalId: approval.approvalId,
            operationType: approval.operationType,
            platform: inbox.platform,
            accountKey: inbox.accountKey,
            inboxId: inbox.inboxId,
            messageId: nil,
            preview: fallbackPreview,
            payload: text.isEmpty ? [:] : ["text": .string(text)],
            requestedAt: MessagingServerDate.nowString(),
            executedAt: nil,
            localStatus: .approvalRequested,
            approvalStatus: .pending,
            executionStatus: .pending,
            error: nil,
            platformMessageIds: [],
            uploadAssetIds: uploadAssetIds,
            uploadAssets: [],
            replacementOperationId: nil
        )
        upsertOptimisticOperation(fallbackOperation)
        textView.text = ""
        selectedAttachments.removeAll()
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
        attachButton.isEnabled = !sending
        sendButton.isEnabled = !sending
        textView.isEditable = !sending
        if sending {
            composerSpinner.startAnimating()
        } else {
            composerSpinner.stopAnimating()
        }
    }

    private func uploadAttachments(
        _ attachments: [MessagingServerUploadDraft],
        collectedAssetIds: [String],
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard let first = attachments.first else {
            completion(.success(collectedAssetIds))
            return
        }
        client.uploadAttachment(first) { [weak self] result in
            guard self != nil else {
                return
            }
            switch result {
            case let .success(asset):
                var nextCollected = collectedAssetIds
                nextCollected.append(asset.assetId)
                var remaining = attachments
                remaining.removeFirst()
                self?.uploadAttachments(remaining, collectedAssetIds: nextCollected, completion: completion)
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
    }

    @objc private func suggestedReplyPressed(_ sender: MessagingServerPillButton) {
        guard let rawValue = sender.rawValue, let reply = suggestedReplies.first(where: { $0.id == rawValue }) else {
            return
        }
        textView.text = reply.text
        updatePlaceholderVisibility()
        textView.becomeFirstResponder()
    }

    @objc private func addSuggestedReplyPressed() {
        let alert = UIAlertController(title: "New Suggested Reply", message: "Create a reusable reply chip for this inbox.", preferredStyle: .alert)
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
        updatePlaceholderVisibility()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(rows.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !rows.isEmpty else {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "Empty")
            cell.selectionStyle = .none
            cell.textLabel?.text = "No messages yet"
            cell.detailTextLabel?.text = "Send a message or create a suggested reply to get started."
            cell.detailTextLabel?.numberOfLines = 0
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(withIdentifier: "BubbleCell", for: indexPath) as? MessagingServerBubbleCell else {
            return UITableViewCell()
        }

        let row = rows[indexPath.row]
        switch row {
        case let .message(message):
            let footerComponents = [
                MessagingServerDate.short(message.sentAt),
                message.editedAt != nil ? "Edited" : nil,
            ].compactMap { $0 }.filter { !$0.isEmpty }
            let title: String?
            switch message.direction {
            case .incoming:
                title = message.senderName
            case .outgoing, .system:
                title = nil
            }
            let configuration = MessagingServerBubbleConfiguration(
                title: title,
                body: message.displayText,
                attachments: message.attachmentSummary,
                footer: footerComponents.joined(separator: " · "),
                isOutgoing: message.direction == .outgoing,
                isPending: false,
                isFailed: false
            )
            cell.configure(configuration)
        case let .pending(operation):
            let footer = [operation.statusSummary, MessagingServerDate.short(operation.requestedAt)].filter { !$0.isEmpty }.joined(separator: " · ")
            let configuration = MessagingServerBubbleConfiguration(
                title: operation.approvalStatus == .pending ? "Pending approval" : "Pending message",
                body: operation.preview,
                attachments: operation.attachmentSummary,
                footer: footer,
                isOutgoing: true,
                isPending: true,
                isFailed: operation.localStatus == .failed
            )
            cell.configure(configuration)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard rows.indices.contains(indexPath.row) else {
            return nil
        }
        switch rows[indexPath.row] {
        case let .pending(operation):
            return UIContextMenuConfiguration(identifier: operation.operationId as NSString, previewProvider: nil) { [weak self] _ in
                guard let self else {
                    return nil
                }
                let edit = UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { _ in
                    self.presentEditOperationPrompt(operation)
                }
                let approve = UIAction(title: "Approve", image: UIImage(systemName: "checkmark.circle")) { _ in
                    self.approveOperation(operation)
                }
                let deny = UIAction(title: "Deny", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { _ in
                    self.denyOperation(operation)
                }
                let details = UIAction(title: "Details", image: UIImage(systemName: "info.circle")) { _ in
                    self.showOperationDetails(operation)
                }
                return UIMenu(title: "Pending Message", children: [edit, approve, deny, details])
            }
        case let .message(message):
            return UIContextMenuConfiguration(identifier: message.messageId as NSString, previewProvider: nil) { [weak self] _ in
                guard let self else {
                    return nil
                }
                let edit = UIAction(title: "Edit Message", image: UIImage(systemName: "square.and.pencil")) { _ in
                    self.presentMessageEditPrompt(message)
                }
                let react = UIMenu(title: "React", children: [
                    UIAction(title: "👍") { _ in self.submitReaction(for: message, emoji: "👍", remove: false) },
                    UIAction(title: "❤️") { _ in self.submitReaction(for: message, emoji: "❤️", remove: false) },
                    UIAction(title: "Custom…") { _ in self.presentReactionPrompt(for: message, remove: false) },
                ])
                let removeReaction = UIAction(title: "Remove Reaction…", image: UIImage(systemName: "minus.circle")) { _ in
                    self.presentReactionPrompt(for: message, remove: true)
                }
                let delete = UIAction(title: "Delete Message", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self.presentDeleteConfirmation(for: message)
                }
                return UIMenu(title: "Message", children: [edit, react, removeReaction, delete])
            }
        }
    }

    private func presentEditOperationPrompt(_ operation: MessagingServerOperationView) {
        let alert = UIAlertController(title: "Edit Pending Message", message: "This uses the pending-operation replacement endpoint.", preferredStyle: .alert)
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

    private func scrollToBottom(animated: Bool) {
        guard !rows.isEmpty else {
            return
        }
        let indexPath = IndexPath(row: rows.count - 1, section: 0)
        guard tableView.numberOfRows(inSection: 0) > indexPath.row else {
            return
        }
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
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
            return
        }

        if let mediaURL = info[.mediaURL] as? URL, let data = try? Data(contentsOf: mediaURL) {
            let filename = mediaURL.lastPathComponent
            let mimeType = mimeType(for: mediaURL)
            selectedAttachments.append(MessagingServerUploadDraft(filename: filename, mimeType: mimeType, data: data))
            updateAttachmentPills()
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
