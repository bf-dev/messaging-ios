import UIKit

final class MessagingServerLoginViewController: UIViewController, UITextFieldDelegate {
    enum Mode {
        case onboarding
        case edit(currentSession: MessagingServerSession)
    }

    private let mode: Mode
    private let sessionStore: MessagingServerSessionStore
    private let onLogin: (MessagingServerSession) -> Void

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()

    private let symbolContainer = UIView()
    private let symbolImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private let apiKeyCaptionLabel = UILabel()
    private let apiKeyField = MessagingServerInputField()
    private let baseURLSummaryLabel = PaddingLabel()
    private let advancedButton = UIButton(type: .system)
    private let serverCaptionLabel = UILabel()
    private let baseURLField = MessagingServerInputField()
    private let serverContainer = UIStackView()
    private let timeoutLabel = UILabel()
    private let footerNoteLabel = UILabel()
    private let connectButton = MessagingServerPrimaryButton(frame: .zero)

    private var validationHandle: MessagingServerTaskHandle?
    private var isConnecting = false
    private var isServerFieldVisible = false

    init(mode: Mode, sessionStore: MessagingServerSessionStore, onLogin: @escaping (MessagingServerSession) -> Void) {
        self.mode = mode
        self.sessionStore = sessionStore
        self.onLogin = onLogin
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        validationHandle?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        configureFields()
        configureLayout()
        configureCopy()
        configureNotifications()
        updateServerFieldVisibility(animated: false)
        updateConnectButtonState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if (apiKeyField.text ?? "").isEmpty {
            apiKeyField.becomeFirstResponder()
        }
    }

    private func configureFields() {
        let initialServer = currentServerString()
        baseURLField.text = initialServer
        baseURLField.placeholder = "Server URL"
        baseURLField.keyboardType = .URL
        baseURLField.returnKeyType = .next
        baseURLField.delegate = self
        baseURLField.textContentType = .URL

        apiKeyField.placeholder = "Paste your messaging-server API key"
        apiKeyField.keyboardType = .asciiCapable
        apiKeyField.isSecureTextEntry = true
        apiKeyField.returnKeyType = .go
        apiKeyField.delegate = self
        apiKeyField.textContentType = .password
        apiKeyField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)
        baseURLField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)

        let revealButton = UIButton(type: .system)
        revealButton.setTitle("Show", for: .normal)
        revealButton.titleLabel?.font = UIFont.systemFont(ofSize: 14.0, weight: .semibold)
        revealButton.addTarget(self, action: #selector(toggleAPIKeyVisibility(_:)), for: .touchUpInside)
        apiKeyField.rightView = revealButton
        apiKeyField.rightViewMode = .always

        if case let .edit(currentSession) = mode {
            apiKeyField.text = currentSession.apiKey
            isServerFieldVisible = true
        }

        symbolContainer.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        symbolContainer.layer.cornerRadius = 36.0
        symbolContainer.layer.cornerCurve = .continuous
        symbolContainer.translatesAutoresizingMaskIntoConstraints = false
        symbolContainer.widthAnchor.constraint(equalToConstant: 72.0).isActive = true
        symbolContainer.heightAnchor.constraint(equalToConstant: 72.0).isActive = true

        symbolImageView.translatesAutoresizingMaskIntoConstraints = false
        symbolImageView.image = UIImage(systemName: "lock.shield.fill")
        symbolImageView.tintColor = .systemBlue
        symbolImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 32.0, weight: .regular)
        symbolContainer.addSubview(symbolImageView)
        NSLayoutConstraint.activate([
            symbolImageView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolImageView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor),
        ])

        titleLabel.font = UIFont.systemFont(ofSize: 31.0, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        subtitleLabel.font = UIFont.systemFont(ofSize: 16.0)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center

        apiKeyCaptionLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        apiKeyCaptionLabel.textColor = .secondaryLabel
        apiKeyCaptionLabel.text = "API KEY"

        baseURLSummaryLabel.font = UIFont.systemFont(ofSize: 14.0)
        baseURLSummaryLabel.textColor = .secondaryLabel
        baseURLSummaryLabel.numberOfLines = 0
        baseURLSummaryLabel.textInsets = UIEdgeInsets(top: 12.0, left: 14.0, bottom: 12.0, right: 14.0)
        baseURLSummaryLabel.backgroundColor = .secondarySystemBackground
        baseURLSummaryLabel.layer.cornerRadius = 16.0
        baseURLSummaryLabel.layer.cornerCurve = .continuous
        baseURLSummaryLabel.layer.borderWidth = 1.0 / UIScreen.main.scale
        baseURLSummaryLabel.layer.borderColor = UIColor.separator.withAlphaComponent(0.3).cgColor
        baseURLSummaryLabel.layer.masksToBounds = true

        advancedButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        advancedButton.contentHorizontalAlignment = .leading
        advancedButton.contentEdgeInsets = UIEdgeInsets(top: 6.0, left: 2.0, bottom: 6.0, right: 2.0)
        advancedButton.addTarget(self, action: #selector(toggleServerField), for: .touchUpInside)

        serverCaptionLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        serverCaptionLabel.textColor = .secondaryLabel
        serverCaptionLabel.text = "SERVER"

        serverContainer.axis = .vertical
        serverContainer.spacing = 8.0
        serverContainer.addArrangedSubview(serverCaptionLabel)
        serverContainer.addArrangedSubview(baseURLField)

        timeoutLabel.font = UIFont.systemFont(ofSize: 14.0)
        timeoutLabel.textColor = .secondaryLabel
        timeoutLabel.numberOfLines = 0
        timeoutLabel.textAlignment = .center
        timeoutLabel.text = "We verify the connection before saving. Connect automatically times out after 10 seconds so the button never hangs."

        footerNoteLabel.font = UIFont.systemFont(ofSize: 13.0)
        footerNoteLabel.textColor = .tertiaryLabel
        footerNoteLabel.numberOfLines = 0
        footerNoteLabel.textAlignment = .center

        connectButton.addTarget(self, action: #selector(connectPressed), for: .touchUpInside)
        connectButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54.0).isActive = true
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 18.0

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)
        scrollView.keyboardDismissMode = .interactive

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28.0),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -28.0),
        ])

        let symbolRow = UIStackView(arrangedSubviews: [symbolContainer])
        symbolRow.axis = .horizontal
        symbolRow.alignment = .center
        symbolRow.distribution = .equalCentering

        stackView.addArrangedSubview(symbolRow)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(apiKeyCaptionLabel)
        stackView.addArrangedSubview(apiKeyField)
        stackView.addArrangedSubview(baseURLSummaryLabel)
        stackView.addArrangedSubview(advancedButton)
        stackView.addArrangedSubview(serverContainer)
        stackView.addArrangedSubview(timeoutLabel)
        stackView.addArrangedSubview(connectButton)
        stackView.addArrangedSubview(footerNoteLabel)
        stackView.setCustomSpacing(12.0, after: subtitleLabel)
        stackView.setCustomSpacing(10.0, after: apiKeyCaptionLabel)
        stackView.setCustomSpacing(10.0, after: apiKeyField)
        stackView.setCustomSpacing(10.0, after: baseURLSummaryLabel)
        stackView.setCustomSpacing(24.0, after: timeoutLabel)
    }

    private func configureCopy() {
        switch mode {
        case .onboarding:
            navigationItem.title = "Connect"
            titleLabel.text = "Sign in with your API key"
            subtitleLabel.text = "Same familiar Telegram-style onboarding, but connected directly to your messaging-server backend."
            connectButton.setTitle("Connect", for: .normal)
            footerNoteLabel.text = "You can change the server later from Settings after your first successful connection."
            if sessionStore.lastBaseURLString() != MessagingServerSessionStore.defaultBaseURL {
                isServerFieldVisible = true
            }
        case .edit:
            navigationItem.title = "Edit Connection"
            titleLabel.text = "Update your connection"
            subtitleLabel.text = "Your current saved session stays untouched until the new server URL and API key validate successfully."
            connectButton.setTitle("Save & Connect", for: .normal)
            footerNoteLabel.text = "Failed connection attempts leave the last known-good session in place."
            isServerFieldVisible = true
        }

        baseURLSummaryLabel.text = "Server: \(currentServerString())"
    }

    private func configureNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    private func currentServerString() -> String {
        switch mode {
        case let .edit(currentSession):
            return currentSession.displayBaseURL
        case .onboarding:
            return sessionStore.lastBaseURLString()
        }
    }

    private func setLoading(_ loading: Bool) {
        isConnecting = loading
        apiKeyField.isEnabled = !loading
        baseURLField.isEnabled = !loading
        advancedButton.isEnabled = !loading
        connectButton.setLoading(loading)
        updateConnectButtonState()
    }

    private func updateConnectButtonState() {
        let hasAPIKey = !(apiKeyField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        connectButton.isEnabled = !isConnecting && hasAPIKey
        connectButton.alpha = connectButton.isEnabled ? 1.0 : 0.72
    }

    private func updateServerFieldVisibility(animated: Bool) {
        serverContainer.isHidden = !isServerFieldVisible
        advancedButton.setTitle(isServerFieldVisible ? "Hide server settings" : "Use a different server", for: .normal)
        baseURLSummaryLabel.isHidden = isServerFieldVisible
        baseURLSummaryLabel.text = "Server: \((baseURLField.text ?? currentServerString()).trimmingCharacters(in: .whitespacesAndNewlines))"
        guard animated else {
            return
        }
        UIView.animate(withDuration: 0.22) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func textFieldEditingChanged() {
        baseURLSummaryLabel.text = "Server: \((baseURLField.text ?? currentServerString()).trimmingCharacters(in: .whitespacesAndNewlines))"
        updateConnectButtonState()
    }

    @objc private func toggleAPIKeyVisibility(_ sender: UIButton) {
        apiKeyField.isSecureTextEntry.toggle()
        sender.setTitle(apiKeyField.isSecureTextEntry ? "Show" : "Hide", for: .normal)
    }

    @objc private func toggleServerField() {
        isServerFieldVisible.toggle()
        updateServerFieldVisibility(animated: true)
    }

    @objc private func appDidEnterBackground() {
        cancelValidation(showToast: true)
    }

    private func cancelValidation(showToast: Bool) {
        guard isConnecting else {
            validationHandle = nil
            return
        }
        validationHandle?.cancel()
        validationHandle = nil
        setLoading(false)
        if showToast {
            showMessagingServerToast("Connection cancelled. Tap Connect to try again.")
        }
    }

    @objc private func connectPressed() {
        guard !isConnecting else {
            return
        }

        view.endEditing(true)

        let rawBaseURL = baseURLField.text ?? currentServerString()
        do {
            let draftSession = try sessionStore.makeDraftSession(baseURLString: rawBaseURL, apiKey: apiKeyField.text ?? "")
            let client = MessagingServerAPIClient(session: draftSession)
            setLoading(true)

            validationHandle = client.validateSession(timeout: 10.0) { [weak self] result in
                guard let self else {
                    return
                }
                self.validationHandle = nil
                self.setLoading(false)

                switch result {
                case .success:
                    do {
                        try self.sessionStore.persist(draftSession)
                        self.onLogin(draftSession)
                    } catch {
                        self.presentMessagingServerError(error, title: "Unable to Save Session")
                    }
                case let .failure(error):
                    if let apiError = error as? MessagingServerAPIError, apiError == .cancelled {
                        return
                    }
                    self.presentMessagingServerError(error, title: "Unable to Connect")
                }
            }
        } catch {
            presentMessagingServerError(error, title: "Invalid Login")
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === baseURLField {
            apiKeyField.becomeFirstResponder()
        } else {
            connectPressed()
        }
        return true
    }
}
