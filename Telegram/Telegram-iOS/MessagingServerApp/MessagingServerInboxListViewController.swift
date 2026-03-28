import UIKit

final class MessagingServerInboxListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let session: MessagingServerSession
    private let client: MessagingServerAPIClient

    private let statusSummaryLabel = UILabel()
    private let filterContainer = UIStackView()
    private let platformScrollView = UIScrollView()
    private let platformStack = UIStackView()
    private let accountScrollView = UIScrollView()
    private let accountStack = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()

    private var platformStatuses: [MessagingServerPlatformStatus] = []
    private var inboxes: [MessagingServerInboxSummary] = []
    private var selectedPlatform: MessagingServerPlatform?
    private var selectedAccount: String?
    private var hasLoadedOnce = false

    init(session: MessagingServerSession, client: MessagingServerAPIClient) {
        self.session = session
        self.client = client
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Chats"
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshPressed))

        statusSummaryLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .medium)
        statusSummaryLabel.textColor = .secondaryLabel
        statusSummaryLabel.numberOfLines = 0

        filterContainer.axis = .vertical
        filterContainer.spacing = 10.0
        filterContainer.translatesAutoresizingMaskIntoConstraints = false

        configureFilterScrollView(platformScrollView, stackView: platformStack)
        configureFilterScrollView(accountScrollView, stackView: accountStack)

        filterContainer.addArrangedSubview(statusSummaryLabel)
        filterContainer.addArrangedSubview(platformScrollView)
        filterContainer.addArrangedSubview(accountScrollView)
        view.addSubview(filterContainer)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72.0
        tableView.tableFooterView = UIView()
        refreshControl.addTarget(self, action: #selector(refreshPressed), for: .valueChanged)
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            filterContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10.0),
            filterContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.0),
            filterContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.0),
            platformScrollView.heightAnchor.constraint(equalToConstant: 40.0),
            accountScrollView.heightAnchor.constraint(equalToConstant: 40.0),
            tableView.topAnchor.constraint(equalTo: filterContainer.bottomAnchor, constant: 8.0),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        reloadFilterChips()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasLoadedOnce {
            hasLoadedOnce = true
            loadAllData(showRefreshControl: false)
        } else {
            loadInboxes(showRefreshControl: false)
        }
    }

    private func configureFilterScrollView(_ scrollView: UIScrollView, stackView: UIStackView) {
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
        client.listInboxes(platform: self.selectedPlatform, account: self.selectedAccount) { result in
            inboxesResult = result
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else {
                return
            }
            self.refreshControl.endRefreshing()
            if case let .success(statuses)? = statusesResult {
                self.platformStatuses = statuses
                self.reconcileSelectedAccount()
                self.reloadFilterChips()
            }
            if case let .success(inboxes)? = inboxesResult {
                self.inboxes = inboxes
                self.tableView.reloadData()
            }
            if case let .failure(error)? = statusesResult {
                self.presentMessagingServerError(error, title: "Status Refresh Failed")
            } else if case let .failure(error)? = inboxesResult {
                self.presentMessagingServerError(error, title: "Inbox Refresh Failed")
            }
            self.updateSummary()
        }
    }

    private func loadInboxes(showRefreshControl: Bool) {
        if showRefreshControl && !refreshControl.isRefreshing {
            refreshControl.beginRefreshing()
        }
        client.listInboxes(platform: selectedPlatform, account: selectedAccount) { [weak self] result in
            guard let self else {
                return
            }
            self.refreshControl.endRefreshing()
            switch result {
            case let .success(inboxes):
                self.inboxes = inboxes
                self.tableView.reloadData()
                self.updateSummary()
            case let .failure(error):
                self.presentMessagingServerError(error, title: "Inbox Refresh Failed")
            }
        }
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

    private func reloadFilterChips() {
        rebuild(stackView: platformStack, buttons: platformButtons(), action: #selector(platformChipPressed(_:)))
        rebuild(stackView: accountStack, buttons: accountButtons(), action: #selector(accountChipPressed(_:)))
        updateSummary()
    }

    private func rebuild(stackView: UIStackView, buttons: [(title: String, value: String?, selected: Bool)], action: Selector) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for item in buttons {
            let button = MessagingServerPillButton(frame: .zero)
            button.rawValue = item.value
            button.setTitle(item.title, for: .normal)
            button.applySelectedStyle(item.selected)
            button.addTarget(self, action: action, for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }
    }

    private func platformButtons() -> [(title: String, value: String?, selected: Bool)] {
        var items: [(String, String?, Bool)] = [("All Platforms", nil, selectedPlatform == nil)]
        let platforms = Array(Set(platformStatuses.map(\.platform))).sorted { $0.displayName < $1.displayName }
        items.append(contentsOf: platforms.map { platform in
            (platform.displayName, platform.rawValue, selectedPlatform == platform)
        })
        return items
    }

    private func accountButtons() -> [(title: String, value: String?, selected: Bool)] {
        var items: [(String, String?, Bool)] = [("All Accounts", nil, selectedAccount == nil)]
        items.append(contentsOf: availableAccountStatuses().map { status in
            (status.accountName.isEmpty ? status.accountKey : status.accountName, status.accountKey, selectedAccount == status.accountKey)
        })
        return items
    }

    private func availableAccountStatuses() -> [MessagingServerPlatformStatus] {
        return platformStatuses
            .filter { selectedPlatform == nil || $0.platform == selectedPlatform }
            .sorted { lhs, rhs in
                if lhs.platform.displayName == rhs.platform.displayName {
                    return lhs.accountName < rhs.accountName
                }
                return lhs.platform.displayName < rhs.platform.displayName
            }
    }

    private func updateSummary() {
        let activeStatuses = platformStatuses.filter { $0.authenticated }
        let platformText = selectedPlatform?.displayName ?? "All platforms"
        let accountText = selectedAccount ?? "all accounts"
        statusSummaryLabel.text = "\(activeStatuses.count) connected accounts · \(inboxes.count) inboxes · \(platformText) / \(accountText)\nServer: \(session.displayBaseURL)"
    }

    @objc private func platformChipPressed(_ sender: MessagingServerPillButton) {
        if let value = sender.rawValue {
            selectedPlatform = MessagingServerPlatform(rawValue: value)
        } else {
            selectedPlatform = nil
        }
        reconcileSelectedAccount()
        reloadFilterChips()
        loadInboxes(showRefreshControl: true)
    }

    @objc private func accountChipPressed(_ sender: MessagingServerPillButton) {
        selectedAccount = sender.rawValue
        reloadFilterChips()
        loadInboxes(showRefreshControl: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return max(inboxes.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if inboxes.isEmpty {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "EmptyCell")
            cell.selectionStyle = .none
            cell.textLabel?.text = "No inboxes found"
            cell.detailTextLabel?.text = "Pull to refresh or change the platform/account filters."
            cell.detailTextLabel?.numberOfLines = 0
            return cell
        }

        let identifier = "InboxCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let inbox = inboxes[indexPath.row]
        let accountName = platformStatuses.accountName(for: inbox.accountKey) ?? inbox.accountKey
        cell.textLabel?.text = inbox.inboxName.isEmpty ? inbox.inboxId : inbox.inboxName
        cell.textLabel?.numberOfLines = 1
        cell.detailTextLabel?.text = "\(inbox.platform.displayName) · \(accountName) · \(inbox.lastMessagePreview ?? "No messages yet")"
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .disclosureIndicator
        cell.imageView?.image = UIImage(systemName: iconName(for: inbox.kind))
        cell.imageView?.tintColor = .systemBlue

        if inbox.unreadCount > 0 {
            let badgeLabel = PaddingLabel()
            badgeLabel.text = String(inbox.unreadCount)
            badgeLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .bold)
            badgeLabel.textColor = .white
            badgeLabel.backgroundColor = .systemBlue
            badgeLabel.layer.cornerRadius = 11.0
            badgeLabel.layer.masksToBounds = true
            badgeLabel.textInsets = UIEdgeInsets(top: 4.0, left: 8.0, bottom: 4.0, right: 8.0)
            cell.accessoryView = badgeLabel
        } else {
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard inboxes.indices.contains(indexPath.row) else {
            return
        }
        let inbox = inboxes[indexPath.row]
        let viewController = MessagingServerChatViewController(session: session, client: client, inbox: inbox)
        navigationController?.pushViewController(viewController, animated: true)
    }

    private func iconName(for kind: MessagingServerInboxKind) -> String {
        switch kind {
        case .dm:
            return "person.crop.circle"
        case .group:
            return "person.3"
        case .channel:
            return "megaphone"
        case .order:
            return "bag"
        case .unknown:
            return "bubble.left"
        }
    }
}
