import UIKit

final class MessagingServerLoginViewController: UIViewController, UITextFieldDelegate {
    private let sessionStore: MessagingServerSessionStore
    private let onLogin: (MessagingServerSession) -> Void

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let baseURLField = UITextField()
    private let apiKeyField = UITextField()
    private let loginButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let stackView = UIStackView()

    init(sessionStore: MessagingServerSessionStore, onLogin: @escaping (MessagingServerSession) -> Void) {
        self.sessionStore = sessionStore
        self.onLogin = onLogin
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true
        navigationItem.title = "Messaging Server"

        titleLabel.text = "Messaging Server"
        titleLabel.font = UIFont.systemFont(ofSize: 32.0, weight: .bold)
        titleLabel.textAlignment = .center

        subtitleLabel.text = "Sign in with a server URL and API key. Telegram backend code remains in the repo, but this app now talks directly to messaging-server."
        subtitleLabel.font = UIFont.systemFont(ofSize: 15.0)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center

        configureTextField(baseURLField, placeholder: "Server URL", keyboardType: .URL)
        baseURLField.text = sessionStore.lastBaseURLString()
        baseURLField.returnKeyType = .next

        configureTextField(apiKeyField, placeholder: "API key", keyboardType: .asciiCapable)
        apiKeyField.isSecureTextEntry = true
        apiKeyField.returnKeyType = .done

        loginButton.setTitle("Connect", for: .normal)
        loginButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        loginButton.backgroundColor = view.tintColor
        loginButton.tintColor = .white
        loginButton.layer.cornerRadius = 14.0
        loginButton.contentEdgeInsets = UIEdgeInsets(top: 14.0, left: 20.0, bottom: 14.0, right: 20.0)
        loginButton.addTarget(self, action: #selector(loginPressed), for: .touchUpInside)

        activityIndicator.hidesWhenStopped = true

        let buttonRow = UIView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        loginButton.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addSubview(loginButton)
        buttonRow.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            loginButton.topAnchor.constraint(equalTo: buttonRow.topAnchor),
            loginButton.leadingAnchor.constraint(equalTo: buttonRow.leadingAnchor),
            loginButton.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor),
            loginButton.bottomAnchor.constraint(equalTo: buttonRow.bottomAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: loginButton.centerYAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: loginButton.trailingAnchor, constant: -16.0),
        ])

        stackView.axis = .vertical
        stackView.spacing = 16.0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        [titleLabel, subtitleLabel, baseURLField, apiKeyField, buttonRow].forEach(stackView.addArrangedSubview)
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            baseURLField.heightAnchor.constraint(equalToConstant: 52.0),
            apiKeyField.heightAnchor.constraint(equalToConstant: 52.0),
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40.0),
        ])
    }

    private func configureTextField(_ textField: UITextField, placeholder: String, keyboardType: UIKeyboardType) {
        textField.delegate = self
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.borderStyle = .none
        textField.backgroundColor = .secondarySystemBackground
        textField.layer.cornerRadius = 14.0
        textField.clearButtonMode = .whileEditing
        textField.leftView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 14.0, height: 10.0))
        textField.leftViewMode = .always
    }

    @objc private func loginPressed() {
        view.endEditing(true)
        do {
            let provisionalSession = try sessionStore.save(baseURLString: baseURLField.text ?? MessagingServerSessionStore.defaultBaseURL, apiKey: apiKeyField.text ?? "")
            setLoading(true)
            let client = MessagingServerAPIClient(session: provisionalSession)
            client.validateSession { [weak self] result in
                guard let self else {
                    return
                }
                self.setLoading(false)
                switch result {
                case .success:
                    self.onLogin(provisionalSession)
                case let .failure(error):
                    self.sessionStore.clear()
                    self.presentMessagingServerError(error, title: "Unable to Connect")
                }
            }
        } catch {
            presentMessagingServerError(error, title: "Invalid Login")
        }
    }

    private func setLoading(_ loading: Bool) {
        loginButton.isEnabled = !loading
        baseURLField.isEnabled = !loading
        apiKeyField.isEnabled = !loading
        if loading {
            activityIndicator.startAnimating()
            loginButton.alpha = 0.8
        } else {
            activityIndicator.stopAnimating()
            loginButton.alpha = 1.0
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === baseURLField {
            apiKeyField.becomeFirstResponder()
        } else {
            loginPressed()
        }
        return true
    }
}
