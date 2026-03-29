import UIKit

final class MessagingServerInboxListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private let session: MessagingServerSession
    private let client: MessagingServerAPIClient

    private let summaryCard = UIView()
    private let summaryTitleLabel = UILabel()
    private let summarySubtitleLabel = UILabel()
    private let connectionBadgeLabel = PaddingLabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyStateView = UIStackView()
    private let emptyStateIconView = UIImageView()
    private let emptyStateTitleLabel = UILabel()
    private let emptyStateSubtitleLabel = UILabel()

    private var platformStatuses: [MessagingServerPlatformStatus] = []
    private var inboxes: [MessagingServerInboxSummary] = []
    private var displayedInboxes: [MessagingServerInboxSummary] = []
    private var selectedPlatform: MessagingServerPlatform?
    private var selectedAccount: String?
    private var realtimeClient: MessagingServerRealtimeClient?
    private var scheduledRefresh: DispatchWorkItem?
    private var connectionState: MessagingServerRealtimeState = .disconnected
    private var hasLoadedOnce = false

    init(session: MessagingServerSession, client: MessagingServerAPIClient) {
        self.session = session
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        realtimeClient?.disconnect()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Chats"
        navigationItem.largeTitleDisplayMode = .always
        configureNavigation()
        configureSummaryCard()
        configureTableView()
        configureEmptyState()
        updateConnectionState(.disconnected)
        applyFilteringAndReload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startRealtime()
        if !hasLoadedOnce {
            hasLoadedOnce = true
            loadAllData(showRefreshControl: false)
        } else {
            loadInboxes(showRefreshControl: false)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        realtimeClient?.disconnect()
    }

    private func configureNavigation() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "Search chats"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        let refreshItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshPressed))
        let filterItem = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"), style: .plain, target: self, action: #selector(showFilters(_:)))
        navigationItem.rightBarButtonItems = [refreshItem, filterItem]
    }

    private func configureSummaryCard() {
        summaryCard.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.applyMessagingServerCardStyle(backgroundColor: .secondarySystemBackground)

        let headerStack = UIStackView()
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.axis = .vertical
        headerStack.spacing = 8.0
        summaryCard.addSubview(headerStack)

        let titleRow = UIStackView()
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 8.0

        summaryTitleLabel.font = UIFont.systemFont(ofSize: 18.0, weight: .semibold)
        summaryTitleLabel.numberOfLines = 1

        connectionBadgeLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        connectionBadgeLabel.textInsets = UIEdgeInsets(top: 5.0, left: 8.0, bottom: 5.0, right: 8.0)
        connectionBadgeLabel.layer.cornerRadius = 12.0
        connectionBadgeLabel.layer.cornerCurve = .continuous
        connectionBadgeLabel.layer.masksToBounds = true

        titleRow.addArrangedSubview(summaryTitleLabel)
        titleRow.addArrangedSubview(UIView())
        titleRow.addArrangedSubview(connectionBadgeLabel)

        summarySubtitleLabel.font = UIFont.systemFont(ofSize: 14.0)
        summarySubtitleLabel.textColor = .secondaryLabel
        summarySubtitleLabel.numberOfLines = 0

        headerStack.addArrangedSubview(titleRow)
        headerStack.addArrangedSubview(summarySubtitleLabel)

        view.addSubview(summaryCard)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: 14.0),
            headerStack.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: 14.0),
            headerStack.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -14.0),
            headerStack.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: -14.0),

            summaryCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12.0),
            summaryCard.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            summaryCard.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemBackground
        tableView.register(MessagingServerChatListCell.self, forCellReuseIdentifier: "ChatListCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .singleLine
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 86.0
        tableView.keyboardDismissMode = .onDrag
        tableView.contentInset = UIEdgeInsets(top: 4.0, left: 0.0, bottom: 12.0, right: 0.0)

        refreshControl.addTarget(self, action: #selector(refreshPressed), for: .valueChanged)
        tableView.refreshControl = refreshControl

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: 10.0),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureEmptyState() {
        emptyStateView.axis = .vertical
        emptyStateView.spacing = 10.0
        emptyStateView.alignment = .center
        emptyStateView.layoutMargins = UIEdgeInsets(top: 24.0, left: 24.0, bottom: 24.0, right: 24.0)
        emptyStateView.isLayoutMarginsRelativeArrangement = true

        emptyStateIconView.image = UIImage(systemName: "bubble.left.and.bubble.right")
        emptyStateIconView.tintColor = .secondaryLabel
        emptyStateIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28.0, weight: .regular)

        emptyStateTitleLabel.font = UIFont.systemFont(ofSize: 19.0, weight: .semibold)
        emptyStateTitleLabel.textColor = .label

        emptyStateSubtitleLabel.font = UIFont.systemFont(ofSize: 14.0)
        emptyStateSubtitleLabel.textColor = .secondaryLabel
        emptyStateSubtitleLabel.numberOfLines = 0
        emptyStateSubtitleLabel.textAlignment = .center

        emptyStateView.addArrangedSubview(emptyStateIconView)
        emptyStateView.addArrangedSubview(emptyStateTitleLabel)
        emptyStateView.addArrangedSubview(emptyStateSubtitleLabel)
        tableView.backgroundView = emptyStateView
        tableView.backgroundView?.isHidden = true
    }

    @objc private func refreshPressed() {
        loadAllData(showRefreshControl: true)
    }

    private func loadAllData(showRefreshControl: Bool) {
        if showRefreshControl && !refreshControl.isRefreshing {
            refreshControl.beginRefreshing()
        }

        let group = DispatchGroup()
        var statusesResult: Result<[MessagingServerPlatformStatus], Error>?
        var inboxesResult: Result<[MessagingServerInboxSummary], Error>?

        group.enter()
        client.listPlatformStatus { result in
            statusesResult = result
            group.leave()
        }

        group.enter()
        client.listInboxes { result in
            inboxesResult = result
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else {
                return
            }
            self.refreshControl.endRefreshing()

            if case let .success(statuses)? = statusesResult {
                self.platformStatuses = statuses.sorted { lhs, rhs in
                    if lhs.platform.displayName == rhs.platform.displayName {
                        return lhs.displayAccountName < rhs.displayAccountName
                    }
                    return lhs.platform.displayName < rhs.platform.displayName
                }
            }

            switch inboxesResult {
            case let .success(inboxes):
                self.inboxes = inboxes
            case let .failure(error):
                self.presentMessagingServerError(error, title: "Inbox Refresh Failed")
            case .none:
                break
            }

            if case let .failure(error)? = statusesResult {
                self.presentMessagingServerError(error, title: "Status Refresh Failed")
            }

            self.reconcileSelectedAccount()
            self.applyFilteringAndReload()
        }
    }

    private func loadInboxes(showRefreshControl: Bool) {
        if showRefreshControl && !refreshControl.isRefreshing {
            refreshControl.beginRefreshing()
        }
        client.listInboxes { [weak self] result in
            guard let self else {
                return
            }
            self.refreshControl.endRefreshing()
            switch result {
            case let .success(inboxes):
                self.inboxes = inboxes
                self.applyFilteringAndReload()
            case let .failure(error):
                self.presentMessagingServerError(error, title: "Inbox Refresh Failed")
            }
        }
    }

    private func startRealtime() {
        realtimeClient?.disconnect()
        let realtimeClient = MessagingServerRealtimeClient(session: session)
        realtimeClient.onStateChange = { [weak self] state in
            self?.updateConnectionState(state)
        }
        realtimeClient.onEvent = { [weak self] event in
            guard event.topic.hasPrefix("inbox:") else {
                return
            }
            self?.scheduleRefresh()
        }
        realtimeClient.onError = { [weak self] error in
            self?.showMessagingServerToast(error.localizedDescription)
        }
        self.realtimeClient = realtimeClient
        realtimeClient.connect()
    }

    private func scheduleRefresh() {
        scheduledRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.loadInboxes(showRefreshControl: false)
        }
        scheduledRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func updateConnectionState(_ state: MessagingServerRealtimeState) {
        connectionState = state
        switch state {
        case .connected:
            connectionBadgeLabel.text = "Live"
            connectionBadgeLabel.textColor = .systemGreen
            connectionBadgeLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.14)
        case .connecting:
            connectionBadgeLabel.text = "Connecting"
            connectionBadgeLabel.textColor = .systemBlue
            connectionBadgeLabel.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.14)
        case .reconnecting:
            connectionBadgeLabel.text = "Reconnecting"
            connectionBadgeLabel.textColor = .systemOrange
            connectionBadgeLabel.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.16)
        case .disconnected:
            connectionBadgeLabel.text = "Offline"
            connectionBadgeLabel.textColor = .secondaryLabel
            connectionBadgeLabel.backgroundColor = UIColor.tertiarySystemFill
        }
        updateSummary()
    }

    private func reconcileSelectedAccount() {
        guard let selectedAccount else {
            return
        }
        let availableKeys = availableAccountStatuses().map(\.accountKey)
        if !availableKeys.contains(selectedAccount) {
            self.selectedAccount = nil
        }
    }

    private func availableAccountStatuses() -> [MessagingServerPlatformStatus] {
        platformStatuses.filter { selectedPlatform == nil || $0.platform == selectedPlatform }
    }

    private func applyFilteringAndReload() {
        let searchText = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        displayedInboxes = inboxes
            .filter { selectedPlatform == nil || $0.platform == selectedPlatform }
            .filter { selectedAccount == nil || $0.accountKey == selectedAccount }
            .filter { inbox in
                guard !searchText.isEmpty else {
                    return true
                }
                let haystacks = [
                    inbox.displayTitle,
                    inbox.lastPreviewText,
                    inbox.accountKey,
                    inbox.platform.displayName,
                    inbox.participants.map(\.displayName).joined(separator: " "),
                ]
                return haystacks.joined(separator: " ").lowercased().contains(searchText)
            }
            .sorted { lhs, rhs in
                let leftDate = MessagingServerDate.parse(lhs.lastMessageAt) ?? Date.distantPast
                let rightDate = MessagingServerDate.parse(rhs.lastMessageAt) ?? Date.distantPast
                if leftDate == rightDate {
                    return lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
                }
                return leftDate > rightDate
            }

        tableView.reloadData()
        updateSummary()
        updateEmptyState()
    }

    private func updateSummary() {
        let connectedCount = platformStatuses.filter(\.authenticated).count
        summaryTitleLabel.text = connectedCount == 0 ? "No connected accounts" : "\(connectedCount) connected account\(connectedCount == 1 ? "" : "s")"

        let selectedPlatformText = selectedPlatform?.displayName ?? "All platforms"
        let selectedAccountText = selectedAccount.flatMap { platformStatuses.accountName(for: $0) } ?? selectedAccount ?? "All accounts"
        let stateText: String
        switch connectionState {
        case .connected:
            stateText = "Live updates connected"
        case .connecting:
            stateText = "Connecting live updates"
        case .reconnecting:
            stateText = "Trying to reconnect live updates"
        case .disconnected:
            stateText = "Live updates disconnected"
        }

        summarySubtitleLabel.text = [
            "\(displayedInboxes.count) chats shown · \(selectedPlatformText) · \(selectedAccountText)",
            stateText,
            "Server: \(session.displayBaseURL)",
        ].joined(separator: "\n")
    }

    private func updateEmptyState() {
        let searchText = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasFilters = selectedPlatform != nil || selectedAccount != nil

        if displayedInboxes.isEmpty {
            if !hasLoadedOnce {
                emptyStateTitleLabel.text = "Loading chats"
                emptyStateSubtitleLabel.text = "Checking your connected accounts and recent conversations."
            } else if !searchText.isEmpty || hasFilters {
                emptyStateTitleLabel.text = "No chats match"
                emptyStateSubtitleLabel.text = "Try a different search term or clear the active filters."
            } else {
                emptyStateTitleLabel.text = "No chats yet"
                emptyStateSubtitleLabel.text = "Connect an account on the server, then pull to refresh this list."
            }

            tableView.backgroundView?.isHidden = false
            tableView.separatorStyle = .none
        } else {
            tableView.backgroundView?.isHidden = true
            tableView.separatorStyle = .singleLine
        }
    }

    @objc private func showFilters(_ sender: UIBarButtonItem) {
        let alert = UIAlertController(title: "Filters", message: nil, preferredStyle: .actionSheet)

        let selectedPlatformName = selectedPlatform?.displayName ?? "All"
        alert.addAction(UIAlertAction(title: "Platform: \(selectedPlatformName)", style: .default, handler: { [weak self] _ in
            self?.presentPlatformFilterSheet(sourceBarButtonItem: sender)
        }))

        let selectedAccountName = selectedAccount.flatMap { platformStatuses.accountName(for: $0) } ?? selectedAccount ?? "All Accounts"
        alert.addAction(UIAlertAction(title: "Account: \(selectedAccountName)", style: .default, handler: { [weak self] _ in
            self?.presentAccountFilterSheet(sourceBarButtonItem: sender)
        }))

        if selectedPlatform != nil || selectedAccount != nil {
            alert.addAction(UIAlertAction(title: "Clear Filters", style: .destructive, handler: { [weak self] _ in
                self?.selectedPlatform = nil
                self?.selectedAccount = nil
                self?.applyFilteringAndReload()
            }))
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = sender
        }
        present(alert, animated: true)
    }

    private func presentPlatformFilterSheet(sourceBarButtonItem: UIBarButtonItem) {
        let alert = UIAlertController(title: "Platform", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "All Platforms", style: .default, handler: { [weak self] _ in
            self?.selectedPlatform = nil
            self?.reconcileSelectedAccount()
            self?.applyFilteringAndReload()
        }))

        let platforms = Array(Set(platformStatuses.map(\.platform))).sorted { $0.displayName < $1.displayName }
        for platform in platforms {
            let title = selectedPlatform == platform ? "✓ \(platform.displayName)" : platform.displayName
            alert.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                self?.selectedPlatform = platform
                self?.reconcileSelectedAccount()
                self?.applyFilteringAndReload()
            }))
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = sourceBarButtonItem
        }
        present(alert, animated: true)
    }

    private func presentAccountFilterSheet(sourceBarButtonItem: UIBarButtonItem) {
        let alert = UIAlertController(title: "Account", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "All Accounts", style: .default, handler: { [weak self] _ in
            self?.selectedAccount = nil
            self?.applyFilteringAndReload()
        }))

        for status in availableAccountStatuses() {
            let title = selectedAccount == status.accountKey ? "✓ \(status.displayAccountName)" : status.displayAccountName
            alert.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                self?.selectedAccount = status.accountKey
                self?.applyFilteringAndReload()
            }))
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = sourceBarButtonItem
        }
        present(alert, animated: true)
    }

    func updateSearchResults(for searchController: UISearchController) {
        applyFilteringAndReload()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displayedInboxes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "ChatListCell", for: indexPath) as? MessagingServerChatListCell else {
            return UITableViewCell()
        }

        let inbox = displayedInboxes[indexPath.row]
        let accountName = platformStatuses.accountName(for: inbox.accountKey) ?? inbox.accountKey
        let configuration = MessagingServerChatListItemConfiguration(
            title: inbox.displayTitle,
            subtitle: inbox.lastPreviewText,
            detail: "\(inbox.platform.displayName) · \(accountName)",
            unreadCount: inbox.unreadCount,
            timestamp: MessagingServerDate.listTimestamp(inbox.lastMessageAt),
            avatarAsset: inbox.avatarAsset,
            avatarTitle: inbox.avatarTitle
        )
        cell.configure(configuration, session: session)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard displayedInboxes.indices.contains(indexPath.row) else {
            return
        }
        let inbox = displayedInboxes[indexPath.row]
        let viewController = MessagingServerChatViewController(session: session, client: client, inbox: inbox)
        viewController.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(viewController, animated: true)
    }
}
