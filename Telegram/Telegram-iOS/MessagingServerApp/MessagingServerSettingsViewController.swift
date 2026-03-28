import UIKit

final class MessagingServerSettingsViewController: UITableViewController {
    private let session: MessagingServerSession
    private let client: MessagingServerAPIClient
    private let sessionStore: MessagingServerSessionStore
    private let onLogout: () -> Void

    private var statuses: [MessagingServerPlatformStatus] = []
    private var isRefreshingStatus = false

    init(
        session: MessagingServerSession,
        client: MessagingServerAPIClient,
        sessionStore: MessagingServerSessionStore,
        onLogout: @escaping () -> Void
    ) {
        self.session = session
        self.client = client
        self.sessionStore = sessionStore
        self.onLogout = onLogout
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshPressed))
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshPressed), for: .valueChanged)
        loadStatus(showSpinner: false)
    }

    @objc private func refreshPressed() {
        loadStatus(showSpinner: true)
    }

    private func loadStatus(showSpinner: Bool) {
        if isRefreshingStatus {
            return
        }
        isRefreshingStatus = true
        if showSpinner {
            refreshControl?.beginRefreshing()
        }
        client.listPlatformStatus { [weak self] result in
            guard let self else {
                return
            }
            self.isRefreshingStatus = false
            self.refreshControl?.endRefreshing()
            switch result {
            case let .success(statuses):
                self.statuses = statuses.sorted { lhs, rhs in
                    if lhs.platform.displayName == rhs.platform.displayName {
                        return lhs.accountName < rhs.accountName
                    }
                    return lhs.platform.displayName < rhs.platform.displayName
                }
                self.tableView.reloadData()
            case let .failure(error):
                self.presentMessagingServerError(error, title: "Status Refresh Failed")
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 2
        case 1:
            return max(statuses.count, 1)
        default:
            return 2
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Session"
        case 1:
            return "Platform Status"
        default:
            return "Actions"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Credentials are stored in the iOS keychain. WebSocket auth uses the same API key."
        case 1:
            return "Tap a platform row to inspect capabilities and last error details."
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.accessoryType = .none
        cell.detailTextLabel?.numberOfLines = 0

        switch indexPath.section {
        case 0:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Server"
                cell.detailTextLabel?.text = session.displayBaseURL
            } else {
                cell.textLabel?.text = "API Key"
                cell.detailTextLabel?.text = session.maskedApiKey
            }
            cell.selectionStyle = .none
        case 1:
            if statuses.isEmpty {
                cell.textLabel?.text = "No platform accounts found"
                cell.detailTextLabel?.text = "Refresh after configuring adapters on the server."
                cell.selectionStyle = .none
            } else {
                let status = statuses[indexPath.row]
                cell.textLabel?.text = "\(status.platform.displayName) · \(status.accountName)"
                cell.detailTextLabel?.text = "\(status.statusSummary)\nRead: \(status.canRead ? "Yes" : "No") · Send: \(status.canSend ? "Yes" : "No")"
                cell.accessoryType = .disclosureIndicator
            }
        default:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Refresh Server Status"
                cell.textLabel?.textColor = view.tintColor
            } else {
                cell.textLabel?.text = "Log Out"
                cell.textLabel?.textColor = .systemRed
            }
            cell.detailTextLabel?.text = nil
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.section {
        case 1:
            guard statuses.indices.contains(indexPath.row) else {
                return
            }
            let status = statuses[indexPath.row]
            let capabilities = [
                ("Text send", status.capabilities.supportsTextSend),
                ("Media send", status.capabilities.supportsMediaSend),
                ("Realtime", status.capabilities.supportsRealtime),
                ("Suggested replies", status.capabilities.supportsSuggestedReplies),
                ("Edit", status.capabilities.supportsMessageEdit),
                ("Delete", status.capabilities.supportsMessageDelete),
                ("Reactions", status.capabilities.supportsMessageReactions),
            ]
            let capabilityText = capabilities.map { "\($0.0): \($0.1 ? "Yes" : "No")" }.joined(separator: "\n")
            let message = [
                "Account Key: \(status.accountKey)",
                "Configured: \(status.configured ? "Yes" : "No")",
                "Authenticated: \(status.authenticated ? "Yes" : "No")",
                "Last Sync: \(MessagingServerDate.short(status.lastSyncAt))",
                status.lastError.map { "Last Error: \($0)" } ?? nil,
                capabilityText,
            ].compactMap { $0 }.joined(separator: "\n\n")
            let alert = UIAlertController(title: "\(status.platform.displayName) · \(status.accountName)", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        case 2:
            if indexPath.row == 0 {
                loadStatus(showSpinner: true)
            } else {
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
}
