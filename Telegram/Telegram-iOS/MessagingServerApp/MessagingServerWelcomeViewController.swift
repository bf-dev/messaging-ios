import UIKit

final class MessagingServerWelcomeViewController: UIViewController {
    private let sessionStore: MessagingServerSessionStore
    private let onContinue: (UIViewController) -> Void

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private let symbolContainer = UIView()
    private let symbolImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let serverLabel = PaddingLabel()
    private let featureStack = UIStackView()
    private let continueButton = MessagingServerPrimaryButton(frame: .zero)

    init(sessionStore: MessagingServerSessionStore, onContinue: @escaping (UIViewController) -> Void) {
        self.sessionStore = sessionStore
        self.onContinue = onContinue
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.title = "Messaging Server"

        configureLayout()
        configureContent()
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 20.0

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)
        scrollView.keyboardDismissMode = .interactive

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28.0),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24.0),
        ])
    }

    private func configureContent() {
        symbolContainer.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        symbolContainer.layer.cornerRadius = 44.0
        symbolContainer.layer.cornerCurve = .continuous
        symbolContainer.translatesAutoresizingMaskIntoConstraints = false
        symbolContainer.widthAnchor.constraint(equalToConstant: 88.0).isActive = true
        symbolContainer.heightAnchor.constraint(equalToConstant: 88.0).isActive = true

        symbolImageView.translatesAutoresizingMaskIntoConstraints = false
        symbolImageView.image = UIImage(systemName: "paperplane.circle.fill")
        symbolImageView.tintColor = .systemBlue
        symbolImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 50.0, weight: .regular)
        symbolContainer.addSubview(symbolImageView)
        NSLayoutConstraint.activate([
            symbolImageView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolImageView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor),
        ])

        let symbolRow = UIStackView(arrangedSubviews: [symbolContainer])
        symbolRow.axis = .horizontal
        symbolRow.alignment = .center
        symbolRow.distribution = .equalCentering
        symbolRow.isLayoutMarginsRelativeArrangement = true
        symbolRow.layoutMargins = .zero

        titleLabel.text = "Your chats, in a Telegram-style flow"
        titleLabel.font = UIFont.systemFont(ofSize: 33.0, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        subtitleLabel.text = "Connect with your messaging-server API key, browse chats faster, and approve outgoing actions inline without the app getting stuck on connect."
        subtitleLabel.font = UIFont.systemFont(ofSize: 16.0)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center

        let serverText: String
        let defaultURL = sessionStore.lastBaseURLString()
        if defaultURL == MessagingServerSessionStore.defaultBaseURL {
            serverText = "Default server: \(defaultURL)"
        } else {
            serverText = "Saved server: \(defaultURL)"
        }
        serverLabel.text = serverText
        serverLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
        serverLabel.textColor = .secondaryLabel
        serverLabel.numberOfLines = 0
        serverLabel.textAlignment = .center
        serverLabel.textInsets = UIEdgeInsets(top: 12.0, left: 14.0, bottom: 12.0, right: 14.0)
        serverLabel.backgroundColor = .secondarySystemBackground
        serverLabel.layer.cornerRadius = 16.0
        serverLabel.layer.cornerCurve = .continuous
        serverLabel.layer.borderWidth = 1.0 / UIScreen.main.scale
        serverLabel.layer.borderColor = UIColor.separator.withAlphaComponent(0.3).cgColor
        serverLabel.layer.masksToBounds = true

        featureStack.axis = .vertical
        featureStack.spacing = 12.0
        [
            ("bolt.horizontal.circle.fill", "Fast connection checks with a 10-second timeout and duplicate-tap protection."),
            ("bubble.left.and.bubble.right.fill", "Telegram-like chat list and conversation layout with avatars, timestamps, and unread badges."),
            ("checkmark.bubble.fill", "Pending approvals stay inside the chat so approve, deny, and edit actions are easy to reach."),
        ].forEach { iconName, text in
            featureStack.addArrangedSubview(makeFeatureRow(iconName: iconName, text: text))
        }

        continueButton.setTitle("Get Started", for: .normal)
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        continueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54.0).isActive = true

        stackView.addArrangedSubview(symbolRow)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(serverLabel)
        stackView.addArrangedSubview(featureStack)
        stackView.addArrangedSubview(continueButton)
        stackView.setCustomSpacing(14.0, after: subtitleLabel)
        stackView.setCustomSpacing(24.0, after: serverLabel)
        stackView.setCustomSpacing(28.0, after: featureStack)
    }

    private func makeFeatureRow(iconName: String, text: String) -> UIView {
        let iconView = UIImageView(image: UIImage(systemName: iconName))
        iconView.tintColor = .systemBlue
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold)
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 15.0)
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.spacing = 12.0
        stack.alignment = .top

        let container = UIView()
        container.applyMessagingServerCardStyle(backgroundColor: .secondarySystemBackground)
        container.translatesAutoresizingMaskIntoConstraints = false

        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14.0),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14.0),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14.0),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14.0),
        ])

        return container
    }

    @objc private func continuePressed() {
        onContinue(self)
    }
}
