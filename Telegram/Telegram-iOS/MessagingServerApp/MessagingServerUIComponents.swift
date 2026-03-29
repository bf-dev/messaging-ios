import UIKit

final class MessagingServerPillButton: UIButton {
    var rawValue: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    private func configureAppearance() {
        titleLabel?.font = UIFont.systemFont(ofSize: 13.0, weight: .medium)
        titleLabel?.adjustsFontForContentSizeCategory = true
        layer.cornerRadius = 16.0
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.0
        contentEdgeInsets = UIEdgeInsets(top: 8.0, left: 12.0, bottom: 8.0, right: 12.0)
    }

    func applySelectedStyle(_ selected: Bool) {
        backgroundColor = selected ? tintColor.withAlphaComponent(0.14) : .secondarySystemBackground
        layer.borderColor = (selected ? tintColor : UIColor.separator).cgColor
        setTitleColor(selected ? tintColor : .label, for: .normal)
    }
}

final class MessagingServerPrimaryButton: UIButton {
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    override var isEnabled: Bool {
        didSet {
            updateAppearance(animated: false)
        }
    }

    override var isHighlighted: Bool {
        didSet {
            updateAppearance(animated: true)
        }
    }

    private func configureAppearance() {
        layer.cornerRadius = 14.0
        layer.cornerCurve = .continuous
        titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel?.adjustsFontForContentSizeCategory = true
        contentEdgeInsets = UIEdgeInsets(top: 14.0, left: 18.0, bottom: 14.0, right: 18.0)
        setTitleColor(.white, for: .normal)
        setTitleColor(UIColor.white.withAlphaComponent(0.92), for: .disabled)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 16.0
        layer.shadowOffset = CGSize(width: 0.0, height: 8.0)

        spinner.hidesWhenStopped = true
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16.0),
        ])

        updateAppearance(animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateAppearance(animated: false)
    }

    private func updateAppearance(animated: Bool) {
        let apply = {
            let fillColor = self.window?.tintColor ?? self.superview?.tintColor ?? .systemBlue
            self.backgroundColor = self.isEnabled
                ? fillColor.withAlphaComponent(self.isHighlighted ? 0.84 : 1.0)
                : fillColor.withAlphaComponent(0.55)
            self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.99, y: 0.99) : .identity
            let baseShadowOpacity: Float = self.traitCollection.userInterfaceStyle == .dark ? 0.18 : 0.12
            self.layer.shadowOpacity = self.isEnabled ? baseShadowOpacity : 0.0
        }

        guard animated else {
            apply()
            return
        }

        UIView.animate(withDuration: 0.14, delay: 0.0, options: [.beginFromCurrentState, .curveEaseOut], animations: {
            apply()
        })
    }

    func setLoading(_ loading: Bool) {
        isEnabled = !loading
        if loading {
            spinner.startAnimating()
            alpha = 0.96
        } else {
            spinner.stopAnimating()
            alpha = 1.0
        }
    }
}

final class MessagingServerInputField: UITextField {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    override var placeholder: String? {
        didSet {
            updatePlaceholderAppearance()
        }
    }

    private func configureAppearance() {
        borderStyle = .none
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14.0
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.0 / UIScreen.main.scale
        clearButtonMode = .whileEditing
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        font = UIFont.systemFont(ofSize: 16.0)
        adjustsFontForContentSizeCategory = true
        textColor = .label
        tintColor = .systemBlue
        leftView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 16.0, height: 10.0))
        leftViewMode = .always
        heightAnchor.constraint(equalToConstant: 52.0).isActive = true
        updatePlaceholderAppearance()
        updateBorderAppearance()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updatePlaceholderAppearance()
        updateBorderAppearance()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        updateBorderAppearance()
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        updateBorderAppearance()
        return didResign
    }

    private func updatePlaceholderAppearance() {
        attributedPlaceholder = placeholder.map {
            NSAttributedString(
                string: $0,
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            )
        }
    }

    private func updateBorderAppearance() {
        layer.borderColor = (isFirstResponder ? tintColor : UIColor.separator.withAlphaComponent(0.55)).cgColor
        backgroundColor = isFirstResponder ? .systemBackground : .secondarySystemBackground
    }
}

final class MessagingServerRemoteMediaLoader {
    static let shared = MessagingServerRemoteMediaLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let urlSession: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15.0
        configuration.timeoutIntervalForResource = 30.0
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        self.urlSession = URLSession(configuration: configuration)
    }

    func loadImage(
        asset: MessagingServerCachedAsset?,
        session: MessagingServerSession,
        completion: @escaping (UIImage?) -> Void
    ) {
        guard let url = Self.bestImageURL(for: asset, baseURL: session.baseURL) else {
            completion(nil)
            return
        }
        let cacheKey = NSString(string: "\(session.apiKey)|\(url.absoluteString)")
        if let cached = cache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        var request = URLRequest(url: url)
        request.setValue(session.apiKey, forHTTPHeaderField: "X-Messaging-Api-Key")
        let task = urlSession.dataTask(with: request) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            self?.cache.setObject(image, forKey: cacheKey)
            DispatchQueue.main.async {
                completion(image)
            }
        }
        task.resume()
    }

    static func bestImageURL(for asset: MessagingServerCachedAsset?, baseURL: URL) -> URL? {
        guard let asset else {
            return nil
        }
        return resolveURL(asset.previewUrl, baseURL: baseURL)
            ?? resolveURL(asset.contentUrl, baseURL: baseURL)
            ?? resolveURL(asset.remoteUrl, baseURL: baseURL)
    }

    static func resolveURL(_ rawValue: String?, baseURL: URL) -> URL? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }
        if let absolute = URL(string: rawValue), absolute.scheme != nil {
            return absolute
        }
        if rawValue.hasPrefix("/") {
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                return nil
            }
            components.path = rawValue
            components.query = nil
            return components.url
        }
        return URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }
}

final class MessagingServerAvatarView: UIView {
    private let imageView = UIImageView()
    private let fallbackLabel = UILabel()
    private var currentAssetKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        addSubview(imageView)

        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        fallbackLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        fallbackLabel.textAlignment = .center
        fallbackLabel.textColor = .white
        addSubview(fallbackLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fallbackLabel.topAnchor.constraint(equalTo: topAnchor),
            fallbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            fallbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            fallbackLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2.0
        layer.cornerCurve = .continuous
    }

    func prepareForReuse() {
        currentAssetKey = nil
        imageView.image = nil
        fallbackLabel.text = nil
    }

    func configure(session: MessagingServerSession, asset: MessagingServerCachedAsset?, title: String) {
        fallbackLabel.text = title.messagingServerInitials
        fallbackLabel.backgroundColor = title.messagingServerAccentColor
        imageView.image = nil

        let assetKey = asset?.assetId ?? title
        currentAssetKey = assetKey
        MessagingServerRemoteMediaLoader.shared.loadImage(asset: asset, session: session) { [weak self] image in
            guard let self, self.currentAssetKey == assetKey else {
                return
            }
            self.imageView.image = image
        }
    }
}

final class MessagingServerRemotePreviewView: UIView {
    private let imageView = UIImageView()
    private let fallbackImageView = UIImageView()
    private var currentAssetKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 14.0
        layer.cornerCurve = .continuous
        clipsToBounds = true
        backgroundColor = .tertiarySystemFill

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        addSubview(imageView)

        fallbackImageView.translatesAutoresizingMaskIntoConstraints = false
        fallbackImageView.contentMode = .scaleAspectFit
        fallbackImageView.tintColor = .secondaryLabel
        fallbackImageView.image = UIImage(systemName: "photo")
        addSubview(fallbackImageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fallbackImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            fallbackImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            fallbackImageView.widthAnchor.constraint(equalToConstant: 24.0),
            fallbackImageView.heightAnchor.constraint(equalToConstant: 24.0),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForReuse() {
        currentAssetKey = nil
        imageView.image = nil
        fallbackImageView.isHidden = false
    }

    func configure(session: MessagingServerSession, asset: MessagingServerCachedAsset?) {
        prepareForReuse()
        let assetKey = asset?.assetId ?? UUID().uuidString
        currentAssetKey = assetKey
        MessagingServerRemoteMediaLoader.shared.loadImage(asset: asset, session: session) { [weak self] image in
            guard let self, self.currentAssetKey == assetKey else {
                return
            }
            self.imageView.image = image
            self.fallbackImageView.isHidden = image != nil
        }
    }
}

struct MessagingServerChatListItemConfiguration {
    let title: String
    let subtitle: String
    let detail: String?
    let unreadCount: Int
    let timestamp: String
    let avatarAsset: MessagingServerCachedAsset?
    let avatarTitle: String
}

final class MessagingServerChatListCell: UITableViewCell {
    private let avatarView = MessagingServerAvatarView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailLabel = UILabel()
    private let timestampLabel = UILabel()
    private let unreadBadgeLabel = PaddingLabel()
    private let textStack = UIStackView()
    private let trailingStack = UIStackView()
    private let rowStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        accessoryType = .none
        separatorInset = UIEdgeInsets(top: 0.0, left: 72.0, bottom: 0.0, right: 16.0)
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground
        let selectedView = UIView()
        selectedView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.08)
        selectedBackgroundView = selectedView

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.widthAnchor.constraint(equalToConstant: 52.0).isActive = true
        avatarView.heightAnchor.constraint(equalToConstant: 52.0).isActive = true

        titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = UIFont.systemFont(ofSize: 15.0)
        subtitleLabel.textColor = .label
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true

        detailLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .medium)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 1
        detailLabel.adjustsFontForContentSizeCategory = true

        timestampLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
        timestampLabel.textColor = .secondaryLabel
        timestampLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timestampLabel.adjustsFontForContentSizeCategory = true

        unreadBadgeLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .bold)
        unreadBadgeLabel.textColor = .white
        unreadBadgeLabel.backgroundColor = .systemBlue
        unreadBadgeLabel.layer.cornerRadius = 11.0
        unreadBadgeLabel.layer.cornerCurve = .continuous
        unreadBadgeLabel.layer.masksToBounds = true
        unreadBadgeLabel.textInsets = UIEdgeInsets(top: 4.0, left: 8.0, bottom: 4.0, right: 8.0)
        unreadBadgeLabel.textAlignment = .center
        unreadBadgeLabel.adjustsFontForContentSizeCategory = true

        trailingStack.axis = .vertical
        trailingStack.alignment = .trailing
        trailingStack.spacing = 8.0
        trailingStack.addArrangedSubview(timestampLabel)
        trailingStack.addArrangedSubview(unreadBadgeLabel)
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)
        trailingStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        textStack.axis = .vertical
        textStack.spacing = 4.0
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        textStack.addArrangedSubview(detailLabel)

        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 12.0
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.addArrangedSubview(avatarView)
        rowStack.addArrangedSubview(textStack)
        rowStack.addArrangedSubview(trailingStack)

        contentView.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10.0),
            rowStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.0),
            rowStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16.0),
            rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10.0),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
    }

    func configure(_ configuration: MessagingServerChatListItemConfiguration, session: MessagingServerSession) {
        let isUnread = configuration.unreadCount > 0
        titleLabel.text = configuration.title
        titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: isUnread ? .semibold : .medium)
        subtitleLabel.text = configuration.subtitle
        subtitleLabel.textColor = isUnread ? .label : .secondaryLabel
        detailLabel.text = configuration.detail
        detailLabel.isHidden = configuration.detail?.isEmpty ?? true
        timestampLabel.text = configuration.timestamp
        timestampLabel.isHidden = configuration.timestamp.isEmpty
        timestampLabel.textColor = isUnread ? tintColor : .secondaryLabel
        unreadBadgeLabel.isHidden = configuration.unreadCount == 0
        unreadBadgeLabel.text = configuration.unreadCount > 0 ? "\(min(configuration.unreadCount, 99))\(configuration.unreadCount > 99 ? "+" : "")" : nil
        avatarView.configure(session: session, asset: configuration.avatarAsset, title: configuration.avatarTitle)
    }
}

struct MessagingServerBubbleConfiguration {
    let title: String?
    let replyText: String?
    let body: String
    let attachments: String?
    let footer: String
    let status: String?
    let reactions: String?
    let previewAssets: [MessagingServerCachedAsset]
    let isOutgoing: Bool
    let isPending: Bool
    let isFailed: Bool
    let avatarAsset: MessagingServerCachedAsset?
    let avatarTitle: String
}

final class MessagingServerBubbleCell: UITableViewCell {
    private let avatarView = MessagingServerAvatarView()
    private let horizontalStack = UIStackView()
    private let leadingSpacer = UIView()
    private let trailingSpacer = UIView()
    private let bubbleView = UIView()
    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let replyLabel = PaddingLabel()
    private let bodyLabel = UILabel()
    private let previewStack = UIStackView()
    private let attachmentsLabel = UILabel()
    private let reactionsLabel = UILabel()
    private let footerLabel = UILabel()
    private var previewViews: [MessagingServerRemotePreviewView] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.widthAnchor.constraint(equalToConstant: 34.0).isActive = true
        avatarView.heightAnchor.constraint(equalToConstant: 34.0).isActive = true

        horizontalStack.axis = .horizontal
        horizontalStack.alignment = .bottom
        horizontalStack.spacing = 8.0
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(horizontalStack)

        bubbleView.layer.cornerRadius = 20.0
        bubbleView.layer.cornerCurve = .continuous
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.76).isActive = true

        contentStack.axis = .vertical
        contentStack.spacing = 6.0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(contentStack)

        titleLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        replyLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
        replyLabel.numberOfLines = 2
        replyLabel.layer.borderWidth = 1.0
        replyLabel.layer.cornerRadius = 10.0
        replyLabel.layer.cornerCurve = .continuous
        replyLabel.layer.masksToBounds = true
        replyLabel.textInsets = UIEdgeInsets(top: 6.0, left: 8.0, bottom: 6.0, right: 8.0)
        replyLabel.adjustsFontForContentSizeCategory = true

        bodyLabel.font = UIFont.systemFont(ofSize: 16.0)
        bodyLabel.numberOfLines = 0
        bodyLabel.adjustsFontForContentSizeCategory = true

        previewStack.axis = .horizontal
        previewStack.spacing = 6.0
        previewStack.distribution = .fillEqually

        attachmentsLabel.font = UIFont.systemFont(ofSize: 13.0)
        attachmentsLabel.numberOfLines = 0
        attachmentsLabel.adjustsFontForContentSizeCategory = true

        reactionsLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .medium)
        reactionsLabel.numberOfLines = 2
        reactionsLabel.adjustsFontForContentSizeCategory = true

        footerLabel.font = UIFont.systemFont(ofSize: 11.0, weight: .medium)
        footerLabel.numberOfLines = 2
        footerLabel.adjustsFontForContentSizeCategory = true

        [titleLabel, replyLabel, bodyLabel, previewStack, attachmentsLabel, reactionsLabel, footerLabel].forEach(contentStack.addArrangedSubview)

        NSLayoutConstraint.activate([
            horizontalStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4.0),
            horizontalStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8.0),
            horizontalStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8.0),
            horizontalStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4.0),
            contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10.0),
            contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12.0),
            contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12.0),
            contentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10.0),
        ])

        leadingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.prepareForReuse()
        previewViews.forEach { $0.prepareForReuse() }
    }

    func configure(_ configuration: MessagingServerBubbleConfiguration, session: MessagingServerSession) {
        horizontalStack.arrangedSubviews.forEach { view in
            horizontalStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if configuration.isOutgoing {
            horizontalStack.addArrangedSubview(leadingSpacer)
            horizontalStack.addArrangedSubview(bubbleView)
        } else {
            avatarView.configure(session: session, asset: configuration.avatarAsset, title: configuration.avatarTitle)
            horizontalStack.addArrangedSubview(avatarView)
            horizontalStack.addArrangedSubview(bubbleView)
            horizontalStack.addArrangedSubview(trailingSpacer)
        }

        titleLabel.text = configuration.title
        titleLabel.isHidden = configuration.title?.isEmpty ?? true

        replyLabel.text = configuration.replyText
        replyLabel.isHidden = configuration.replyText?.isEmpty ?? true

        bodyLabel.text = configuration.body
        bodyLabel.isHidden = configuration.body.isEmpty

        attachmentsLabel.text = configuration.attachments
        attachmentsLabel.isHidden = configuration.attachments?.isEmpty ?? true

        reactionsLabel.text = configuration.reactions
        reactionsLabel.isHidden = configuration.reactions?.isEmpty ?? true

        let footerParts = [configuration.status, configuration.footer]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        footerLabel.text = footerParts.joined(separator: " · ")
        footerLabel.isHidden = footerLabel.text?.isEmpty ?? true

        previewStack.arrangedSubviews.forEach { view in
            previewStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        previewViews.removeAll()
        for asset in configuration.previewAssets.prefix(3) {
            let previewView = MessagingServerRemotePreviewView()
            previewView.translatesAutoresizingMaskIntoConstraints = false
            previewView.heightAnchor.constraint(equalToConstant: 112.0).isActive = true
            previewView.configure(session: session, asset: asset)
            previewStack.addArrangedSubview(previewView)
            previewViews.append(previewView)
        }
        previewStack.isHidden = configuration.previewAssets.isEmpty

        if configuration.isOutgoing {
            bubbleView.backgroundColor = configuration.isFailed
                ? UIColor.systemRed.withAlphaComponent(0.18)
                : UIColor.systemBlue
            titleLabel.textColor = UIColor.white.withAlphaComponent(0.92)
            replyLabel.textColor = UIColor.white.withAlphaComponent(0.9)
            replyLabel.backgroundColor = UIColor.white.withAlphaComponent(0.12)
            replyLabel.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
            bodyLabel.textColor = .white
            attachmentsLabel.textColor = UIColor.white.withAlphaComponent(0.92)
            reactionsLabel.textColor = UIColor.white.withAlphaComponent(0.92)
            footerLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        } else {
            bubbleView.backgroundColor = UIColor.secondarySystemBackground
            titleLabel.textColor = .systemBlue
            replyLabel.textColor = .secondaryLabel
            replyLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.7)
            replyLabel.layer.borderColor = UIColor.separator.cgColor
            bodyLabel.textColor = .label
            attachmentsLabel.textColor = .secondaryLabel
            reactionsLabel.textColor = .secondaryLabel
            footerLabel.textColor = .tertiaryLabel
        }

        if configuration.isFailed {
            bubbleView.layer.borderWidth = 1.0
            bubbleView.layer.borderColor = UIColor.systemRed.withAlphaComponent(0.45).cgColor
        } else if configuration.isOutgoing {
            bubbleView.layer.borderWidth = 0.0
            bubbleView.layer.borderColor = nil
        } else {
            bubbleView.layer.borderWidth = 1.0 / UIScreen.main.scale
            bubbleView.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        }
        bubbleView.alpha = configuration.isPending ? 0.82 : 1.0
    }
}

extension UIView {
    func applyMessagingServerCardStyle(backgroundColor: UIColor = .secondarySystemBackground) {
        self.backgroundColor = backgroundColor
        layer.cornerRadius = 18.0
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.0 / UIScreen.main.scale
        layer.borderColor = UIColor.separator.withAlphaComponent(0.3).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 18.0
        layer.shadowOffset = CGSize(width: 0.0, height: 8.0)
    }
}

extension UIViewController {
    func showMessagingServerToast(_ message: String) {
        guard !message.isEmpty else {
            return
        }
        let label = PaddingLabel()
        label.text = message
        label.numberOfLines = 0
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        label.layer.cornerRadius = 14.0
        label.layer.cornerCurve = .continuous
        label.layer.masksToBounds = true
        label.alpha = 0.0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18.0),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20.0),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20.0),
        ])

        UIView.animate(withDuration: 0.2) {
            label.alpha = 1.0
        }

        UIView.animate(withDuration: 0.25, delay: 2.2, options: [.curveEaseInOut], animations: {
            label.alpha = 0.0
        }, completion: { _ in
            label.removeFromSuperview()
        })
    }

    func presentMessagingServerError(_ error: Error, title: String = "Error") {
        let alert = UIAlertController(title: title, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

final class PaddingLabel: UILabel {
    var textInsets = UIEdgeInsets(top: 10.0, left: 14.0, bottom: 10.0, right: 14.0)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + textInsets.left + textInsets.right, height: size.height + textInsets.top + textInsets.bottom)
    }
}

private extension String {
    var messagingServerInitials: String {
        let parts = self
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        if !parts.isEmpty {
            return parts.joined().uppercased()
        }
        return String(prefix(2)).uppercased()
    }

    var messagingServerAccentColor: UIColor {
        let palette: [UIColor] = [
            .systemBlue,
            .systemTeal,
            .systemIndigo,
            .systemPurple,
            .systemOrange,
            .systemGreen,
            .systemPink,
        ]
        let index = abs(self.hashValue) % palette.count
        return palette[index]
    }
}
