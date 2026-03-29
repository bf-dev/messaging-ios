import UIKit

final class MessagingServerInboxListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private let session: MessagingServerSession
    private let client: MessagingServerAPIClient
    private let snapshotStore = MessagingServerSnapshotStore.shared

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let searchController = UISearchController(searchResultsController: nil)
    private let emptyStateView = UIStackView()
    private let emptyStateIconView = UIImageView()
    private let emptyStateTitleLabel = UILabel()
    private let emptyStateSubtitleLabel = UILabel()

    private var inboxes: [MessagingServerInboxSummary] = []
    private var displayedInboxes: [MessagingServerInboxSummary] = []
    private var realtimeClient: MessagingServerRealtimeClient?
    private var scheduledRefresh: DispatchWorkItem?
    private var connectionState: MessagingServerRealtimeState = .disconnected
    private var isRefreshingFromServer = false
    private var hasCompletedInitialLoad = false
    private var loadFailureMessage: String?

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
        view.accessibilityIdentifier = "messaging.chats.screen"

        configureNavigation()
        configureTableView()
        configureEmptyState()
        loadCachedInboxes()
        applyFilteringAndReload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startRealtime()
        loadInboxes(showRefreshControl: false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        realtimeClient?.disconnect()
    }

    private func configureNavigation() {
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "Search"
        searchController.searchBar.searchTextField.accessibilityIdentifier = "messaging.chats.search"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItem = nil
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemBackground
        tableView.register(MessagingServerChatListCell.self, forCellReuseIdentifier: "ChatListCell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets(top: 0.0, left: 76.0, bottom: 0.0, right: 0.0)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 78.0
        tableView.keyboardDismissMode = .onDrag
        tableView.contentInset = UIEdgeInsets(top: 2.0, left: 0.0, bottom: 8.0, right: 0.0)
        tableView.accessibilityIdentifier = "messaging.chats.table"

        refreshControl.addTarget(self, action: #selector(refreshPressed), for: .valueChanged)
        tableView.refreshControl = refreshControl

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureEmptyState() {
        emptyStateView.axis = .vertical
        emptyStateView.spacing = 10.0
        emptyStateView.alignment = .center
        emptyStateView.layoutMargins = UIEdgeInsets(top: 32.0, left: 28.0, bottom: 32.0, right: 28.0)
        emptyStateView.isLayoutMarginsRelativeArrangement = true
        emptyStateView.accessibilityIdentifier = "messaging.chats.emptyState"

        emptyStateIconView.image = UIImage(systemName: "bubble.left.and.bubble.right.fill")
        emptyStateIconView.tintColor = .secondaryLabel
        emptyStateIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30.0, weight: .regular)

        emptyStateTitleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .semibold)
        emptyStateTitleLabel.textColor = .label
        emptyStateTitleLabel.textAlignment = .center
        emptyStateTitleLabel.adjustsFontForContentSizeCategory = true

        emptyStateSubtitleLabel.font = UIFont.systemFont(ofSize: 15.0)
        emptyStateSubtitleLabel.textColor = .secondaryLabel
        emptyStateSubtitleLabel.numberOfLines = 0
        emptyStateSubtitleLabel.textAlignment = .center
        emptyStateSubtitleLabel.adjustsFontForContentSizeCategory = true

        emptyStateView.addArrangedSubview(emptyStateIconView)
        emptyStateView.addArrangedSubview(emptyStateTitleLabel)
        emptyStateView.addArrangedSubview(emptyStateSubtitleLabel)
        tableView.backgroundView = emptyStateView
        tableView.backgroundView?.isHidden = true
    }

    @objc private func refreshPressed() {
        loadInboxes(showRefreshControl: true)
    }

    private func loadCachedInboxes() {
        let cachedInboxes = snapshotStore.loadInboxes(for: session)
        guard !cachedInboxes.isEmpty else {
            return
        }
        inboxes = cachedInboxes
    }

    private func loadInboxes(showRefreshControl: Bool) {
        guard !isRefreshingFromServer else {
            if showRefreshControl {
                refreshControl.endRefreshing()
            }
            return
        }

        isRefreshingFromServer = true
        loadFailureMessage = nil
        updateEmptyState()

        if showRefreshControl && !refreshControl.isRefreshing {
            refreshControl.beginRefreshing()
        }

        client.listInboxes { [weak self] result in
            guard let self else {
                return
            }
            self.isRefreshingFromServer = false
            self.hasCompletedInitialLoad = true
            self.refreshControl.endRefreshing()
            switch result {
            case let .success(inboxes):
                self.inboxes = inboxes
                self.snapshotStore.saveInboxes(inboxes, for: self.session)
                self.loadFailureMessage = nil
                self.applyFilteringAndReload()
            case let .failure(error):
                self.loadFailureMessage = error.localizedDescription
                self.updateEmptyState()
                if self.inboxes.isEmpty || showRefreshControl {
                    self.showMessagingServerToast(error.localizedDescription)
                }
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
        updateEmptyState()
    }

    private func applyFilteringAndReload() {
        let searchText = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        displayedInboxes = inboxes
            .filter { inbox in
                guard !searchText.isEmpty else {
                    return true
                }
                let haystacks = [
                    inbox.displayTitle,
                    inbox.lastPreviewText,
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
        updateEmptyState()
    }

    private func updateEmptyState() {
        let searchText = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if displayedInboxes.isEmpty {
            if (!hasCompletedInitialLoad || isRefreshingFromServer) && inboxes.isEmpty {
                emptyStateTitleLabel.text = "Loading chats"
                emptyStateSubtitleLabel.text = "Showing your chats as soon as the latest server snapshot arrives."
            } else if !searchText.isEmpty {
                emptyStateTitleLabel.text = "No chats found"
                emptyStateSubtitleLabel.text = "Try a different search term."
            } else if let loadFailureMessage, inboxes.isEmpty, hasCompletedInitialLoad {
                emptyStateTitleLabel.text = "Unable to load chats"
                emptyStateSubtitleLabel.text = "\(loadFailureMessage)\n\nPull down to try again."
            } else {
                let stateText: String
                switch connectionState {
                case .connected:
                    stateText = "Pull to refresh if you just connected a new account."
                case .connecting, .reconnecting:
                    stateText = "Live updates are reconnecting in the background."
                case .disconnected:
                    stateText = "Pull to refresh after connecting an account on the server."
                }
                emptyStateTitleLabel.text = "No chats yet"
                emptyStateSubtitleLabel.text = stateText
            }

            tableView.backgroundView?.isHidden = false
            tableView.separatorStyle = .none
        } else {
            tableView.backgroundView?.isHidden = true
            tableView.separatorStyle = .singleLine
        }
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
        cell.accessibilityIdentifier = "messaging.chats.cell.\(inbox.inboxId)"
        let configuration = MessagingServerChatListItemConfiguration(
            title: inbox.displayTitle,
            subtitle: inbox.lastPreviewText,
            detail: nil,
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
