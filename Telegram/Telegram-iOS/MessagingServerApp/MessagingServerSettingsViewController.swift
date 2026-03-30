import Display
import UIKit

final class MessagingServerSettingsViewController: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let session: MessagingServerSession
    private let client: MessagingServerAPIClient
    private let sessionStore: MessagingServerSessionStore
    private let onSessionUpdated: (MessagingServerSession) -> Void
    private let onLogout: () -> Void

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let refreshControlView = UIRefreshControl()
    private let summaryHeaderView = UIView()
    private let summaryCard = UIView()
    private let summaryCaptionLabel = UILabel()
    private let summaryTitleLabel = UILabel()
    private let summarySubtitleLabel = UILabel()

    private var statuses: [MessagingServerPlatformStatus] = []
    private var isRefreshingStatus = false

    init(
        session: MessagingServerSession,
        client: MessagingServerAPIClient,
        sessionStore: MessagingServerSessionStore,
        onSessionUpdated: @escaping (MessagingServerSession) -> Void,
        onLogout: @escaping () -> Void
    ) {
        self.session = session
        self.client = client
        self.sessionStore = sessionStore
        self.onSessionUpdated = onSessionUpdated
        self.onLogout = onLogout
        super.init(navigationBarPresentationData: MessagingServerTelegramPresentation.navigationBarPresentationData())
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground
        view.accessibilityIdentifier = "messaging.settings.screen"

        configureTableView()
        configureHeaderView()

        let refreshItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshPressed))
        refreshItem.accessibilityIdentifier = "messaging.settings.refresh"
        navigationItem.rightBarButtonItem = refreshItem

        loadStatus(showSpinner: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeaderLayout()
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.accessibilityIdentifier = "messaging.settings.table"
        tableView.refreshControl = refreshControlView
        refreshControlView.addTarget(self, action: #selector(refreshPressed), for: .valueChanged)

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func refreshPressed() {
        loadStatus(showSpinner: true)
    }

    private func loadStatus(showSpinner: Bool) {
        guard !isRefreshingStatus else {
            return
        }
        isRefreshingStatus = true
        if showSpinner {
            refreshControlView.beginRefreshing()
        }
        client.listPlatformStatus { [weak self] result in
            guard let self else {
                return
            }
            self.isRefreshingStatus = false
            self.refreshControlView.endRefreshing()
            switch result {
            case let .success(statuses):
                self.statuses = statuses.sorted { lhs, rhs in
                    if lhs.platform.displayName == rhs.platform.displayName {
                        return lhs.displayAccountName < rhs.displayAccountName
                    }
                    return lhs.platform.displayName < rhs.platform.displayName
                }
                self.updateHeaderSummary()
                self.tableView.reloadData()
            case let .failure(error):
                self.updateHeaderSummary()
                self.presentMessagingServerError(error, title: "Status Refresh Failed")
            }
        }
    }

    private func configureHeaderView() {
        summaryHeaderView.frame = CGRect(x: 0.0, y: 0.0, width: view.bounds.width, height: 136.0)

        summaryCard.applyMessagingServerCardStyle(backgroundColor: .secondarySystemBackground)
        summaryCard.accessibilityIdentifier = "messaging.settings.summaryCard"
        summaryHeaderView.addSubview(summaryCard)

        summaryCaptionLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        summaryCaptionLabel.textColor = .secondaryLabel
        summaryCaptionLabel.text = "CONNECTED SERVER"
        summaryCaptionLabel.adjustsFontForContentSizeCategory = true

        summaryTitleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .bold)
        summaryTitleLabel.numberOfLines = 2
        summaryTitleLabel.adjustsFontForContentSizeCategory = true

        summarySubtitleLabel.font = UIFont.systemFont(ofSize: 14.0)
        summarySubtitleLabel.textColor = .secondaryLabel
        summarySubtitleLabel.numberOfLines = 0
        summarySubtitleLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [summaryCaptionLabel, summaryTitleLabel, summarySubtitleLabel])
        stack.axis = .vertical
        stack.spacing = 6.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: 16.0),
            stack.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: 16.0),
            stack.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -16.0),
            stack.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: -16.0),
        ])

        updateHeaderSummary()
        tableView.tableHeaderView = summaryHeaderView
        updateHeaderLayout()
    }

    private func updateHeaderLayout() {
        guard tableView.tableHeaderView === summaryHeaderView else {
            return
        }

        let width = tableView.bounds.width
        guard width > 0.0 else {
            return
        }

        let headerFrame = CGRect(x: 0.0, y: 0.0, width: width, height: 136.0)
        let cardFrame = CGRect(x: 16.0, y: 10.0, width: max(width - 32.0, 0.0), height: 116.0)
        guard summaryHeaderView.frame != headerFrame || summaryCard.frame != cardFrame else {
            return
        }

        summaryHeaderView.frame = headerFrame
        summaryCard.frame = cardFrame
        tableView.tableHeaderView = summaryHeaderView
    }

    private func updateHeaderSummary() {
        let authenticatedCount = statuses.filter(\.authenticated).count
        summaryTitleLabel.text = session.displayBaseURL
        summarySubtitleLabel.text = [
            authenticatedCount == 0
                ? "No authenticated accounts reported yet."
                : "\(authenticatedCount) authenticated account\(authenticatedCount == 1 ? "" : "s") ready.",
            "API key: \(session.maskedApiKey)",
        ].joined(separator: "\n")
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 3
        case 1:
            return max(statuses.count, 1)
        default:
            return 3
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Connection"
        case 1:
            return "Platform Status"
        default:
            return "Actions"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Credentials stay in the iOS keychain. Editing the connection validates first, then replaces the saved session only after success."
        case 1:
            return statuses.isEmpty ? "Configure adapters on the server, then refresh here." : "Tap a platform row to inspect sync, capability, and error details."
        default:
            return "Use Edit Connection to change the server URL or API key without losing the last known-good session on failure."
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.detailTextLabel?.numberOfLines = 0
        cell.selectionStyle = .none
        cell.accessoryType = .none
        cell.accessibilityIdentifier = "messaging.settings.section\(indexPath.section).row\(indexPath.row)"

        switch indexPath.section {
        case 0:
            let connectedCount = statuses.filter(\.authenticated).count
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Server"
                cell.detailTextLabel?.text = session.displayBaseURL
            case 1:
                cell.textLabel?.text = "API Key"
                cell.detailTextLabel?.text = session.maskedApiKey
            default:
                cell.textLabel?.text = "Connected Accounts"
                cell.detailTextLabel?.text = connectedCount == 0 ? "No authenticated accounts reported yet." : "\(connectedCount) authenticated account\(connectedCount == 1 ? "" : "s")"
            }
        case 1:
            if statuses.isEmpty {
                cell.textLabel?.text = "No platform accounts found"
                cell.detailTextLabel?.text = "Refresh after configuring adapters on the server."
            } else {
                let status = statuses[indexPath.row]
                cell.textLabel?.text = "\(status.platform.displayName) · \(status.displayAccountName)"
                cell.detailTextLabel?.text = "\(status.statusSummary)\nRead: \(status.canRead ? "Yes" : "No") · Send: \(status.canSend ? "Yes" : "No")"
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
            }
        default:
            cell.selectionStyle = .default
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Edit Connection"
                cell.textLabel?.textColor = view.tintColor
                cell.detailTextLabel?.text = "Change the server URL or API key."
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = "Refresh Server Status"
                cell.textLabel?.textColor = view.tintColor
                cell.detailTextLabel?.text = "Fetch the latest adapter state from the server."
            default:
                cell.textLabel?.text = "Log Out"
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = "Remove the saved credentials from this device."
            }
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.section {
        case 1:
            guard statuses.indices.contains(indexPath.row) else {
                return
            }
            showDetails(for: statuses[indexPath.row])
        case 2:
            switch indexPath.row {
            case 0:
                let viewController = MessagingServerLoginViewController(mode: .edit(currentSession: session), sessionStore: sessionStore) { [weak self] newSession in
                    self?.onSessionUpdated(newSession)
                }
                navigationController?.pushViewController(viewController, animated: true)
            case 1:
                loadStatus(showSpinner: true)
            default:
                let alert = UIAlertController(title: "Log Out", message: "Remove the saved server URL and API key from this device?", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: "Log Out", style: .destructive, handler: { [weak self] _ in
                    self?.sessionStore.clear()
                    self?.onLogout()
                }))
                present(alert, animated: true)
            }
        default:
            break
        }
    }

    private func showDetails(for status: MessagingServerPlatformStatus) {
        let capabilities = [
            ("Text send", status.capabilities.supportsTextSend),
            ("Media send", status.capabilities.supportsMediaSend),
            ("Read", status.capabilities.supportsRead),
            ("Attachment fetch", status.capabilities.supportsAttachmentFetch),
            ("Realtime", status.capabilities.supportsRealtime),
            ("Suggested replies", status.capabilities.supportsSuggestedReplies),
            ("Edit", status.capabilities.supportsMessageEdit),
            ("Delete", status.capabilities.supportsMessageDelete),
            ("Reactions", status.capabilities.supportsMessageReactions),
            ("Profile images", status.capabilities.supportsProfileImages),
        ]

        let capabilityText = capabilities
            .map { "\($0.0): \($0.1 ? "Yes" : "No")" }
            .joined(separator: "\n")

        let message = [
            "Account Key: \(status.accountKey)",
            "Configured: \(status.configured ? "Yes" : "No")",
            "Authenticated: \(status.authenticated ? "Yes" : "No")",
            "Last Sync: \(MessagingServerDate.short(status.lastSyncAt))",
            status.lastError.map { "Last Error: \($0)" },
            capabilityText,
        ].compactMap { $0 }.joined(separator: "\n\n")

        let alert = UIAlertController(title: "\(status.platform.displayName) · \(status.displayAccountName)", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
