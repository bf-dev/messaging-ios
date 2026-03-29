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

// Adapted from the original Telegram iOS client:
// submodules/TelegramUI/Components/Utils/RoundedRectWithTailPath/Sources/RoundedRectWithTailPath.swift
private func messagingServerTelegramRoundedRectWithTailPath(
    rectSize: CGSize,
    cornerRadius: CGFloat? = nil,
    tailSize: CGSize = CGSize(width: 20.0, height: 9.0),
    tailRadius: CGFloat = 4.0,
    tailPosition: CGFloat? = 0.5,
    transformTail: Bool = true
) -> UIBezierPath {
    let cornerRadius: CGFloat = cornerRadius ?? rectSize.height / 2.0
    let tailWidth: CGFloat = tailSize.width
    let tailHeight: CGFloat = tailSize.height

    let rect = CGRect(origin: CGPoint(x: 0.0, y: tailHeight), size: rectSize)

    guard let tailPosition else {
        return UIBezierPath(cgPath: CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    }

    let cutoff: CGFloat = 0.27

    let path = UIBezierPath()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))

    var leftArcEndAngle: CGFloat = .pi / 2.0
    var leftConnectionArcRadius = tailRadius
    var tailLeftHalfWidth: CGFloat = tailWidth / 2.0
    var tailLeftArcStartAngle: CGFloat = -.pi / 4.0
    var tailLeftHalfRadius = tailRadius

    var rightArcStartAngle: CGFloat = -.pi / 2.0
    var rightConnectionArcRadius = tailRadius
    var tailRightHalfWidth: CGFloat = tailWidth / 2.0
    var tailRightArcStartAngle: CGFloat = .pi / 4.0
    var tailRightHalfRadius = tailRadius

    if transformTail {
        if tailPosition < 0.5 {
            let fraction = max(0.0, tailPosition - 0.15) / 0.35
            leftArcEndAngle *= fraction

            let connectionFraction = max(0.0, tailPosition - 0.35) / 0.15
            leftConnectionArcRadius *= connectionFraction

            if tailPosition < cutoff {
                let fraction = tailPosition / cutoff
                tailLeftHalfWidth *= fraction
                tailLeftArcStartAngle *= fraction
                tailLeftHalfRadius *= fraction
            }
        } else if tailPosition > 0.5 {
            let mirroredTailPosition = 1.0 - tailPosition
            let fraction = max(0.0, mirroredTailPosition - 0.15) / 0.35
            rightArcStartAngle *= fraction

            let connectionFraction = max(0.0, mirroredTailPosition - 0.35) / 0.15
            rightConnectionArcRadius *= connectionFraction

            if mirroredTailPosition < cutoff {
                let fraction = mirroredTailPosition / cutoff
                tailRightHalfWidth *= fraction
                tailRightArcStartAngle *= fraction
                tailRightHalfRadius *= fraction
            }
        }
    }

    path.addArc(
        withCenter: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
        radius: cornerRadius,
        startAngle: .pi,
        endAngle: .pi + max(0.0001, leftArcEndAngle),
        clockwise: true
    )

    let leftArrowStart = max(rect.minX, rect.minX + rectSize.width * tailPosition - tailLeftHalfWidth - leftConnectionArcRadius)
    path.addArc(
        withCenter: CGPoint(x: leftArrowStart, y: rect.minY - leftConnectionArcRadius),
        radius: leftConnectionArcRadius,
        startAngle: .pi / 2.0,
        endAngle: .pi / 4.0,
        clockwise: false
    )

    path.addLine(to: CGPoint(x: max(rect.minX, rect.minX + rectSize.width * tailPosition - tailLeftHalfRadius), y: rect.minY - tailHeight))

    path.addArc(
        withCenter: CGPoint(x: rect.minX + rectSize.width * tailPosition, y: rect.minY - tailHeight + tailRadius / 2.0),
        radius: tailRadius,
        startAngle: -.pi / 2.0 + tailLeftArcStartAngle,
        endAngle: -.pi / 2.0 + tailRightArcStartAngle,
        clockwise: true
    )

    path.addLine(to: CGPoint(x: min(rect.maxX, rect.minX + rectSize.width * tailPosition + tailRightHalfRadius), y: rect.minY - tailHeight))

    let rightArrowStart = min(rect.maxX, rect.minX + rectSize.width * tailPosition + tailRightHalfWidth + rightConnectionArcRadius)
    path.addArc(
        withCenter: CGPoint(x: rightArrowStart, y: rect.minY - rightConnectionArcRadius),
        radius: rightConnectionArcRadius,
        startAngle: .pi - .pi / 4.0,
        endAngle: .pi / 2.0,
        clockwise: false
    )

    path.addArc(
        withCenter: CGPoint(x: rect.minX + rectSize.width - cornerRadius, y: rect.minY + cornerRadius),
        radius: cornerRadius,
        startAngle: min(-0.0001, rightArcStartAngle),
        endAngle: 0.0,
        clockwise: true
    )

    path.addLine(to: CGPoint(x: rect.minX + rectSize.width, y: rect.minY + rectSize.height - cornerRadius))

    path.addArc(
        withCenter: CGPoint(x: rect.minX + rectSize.width - cornerRadius, y: rect.minY + rectSize.height - cornerRadius),
        radius: cornerRadius,
        startAngle: 0.0,
        endAngle: .pi / 2.0,
        clockwise: true
    )

    path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + rectSize.height))

    path.addArc(
        withCenter: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + rectSize.height - cornerRadius),
        radius: cornerRadius,
        startAngle: .pi / 2.0,
        endAngle: .pi,
        clockwise: true
    )

    return path
}

final class MessagingServerChatBackgroundView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(gradientLayer)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        if traitCollection.userInterfaceStyle == .dark {
            gradientLayer.colors = [
                UIColor(red: 0.11, green: 0.14, blue: 0.18, alpha: 1.0).cgColor,
                UIColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 1.0).cgColor,
            ]
        } else {
            gradientLayer.colors = [
                UIColor(red: 0.91, green: 0.96, blue: 0.99, alpha: 1.0).cgColor,
                UIColor(red: 0.96, green: 0.98, blue: 1.0, alpha: 1.0).cgColor,
            ]
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        let dotColor = traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.04)
            : UIColor.systemBlue.withAlphaComponent(0.04)
        context.setFillColor(dotColor.cgColor)

        let spacing: CGFloat = 26.0
        let radius: CGFloat = 3.0
        let rowOffset = spacing / 2.0
        var rowIndex = 0
        var y: CGFloat = -spacing
        while y < rect.maxY + spacing {
            let startX: CGFloat = rowIndex.isMultiple(of: 2) ? -spacing : -spacing + rowOffset
            var x = startX
            while x < rect.maxX + spacing {
                context.fillEllipse(in: CGRect(x: x, y: y, width: radius * 2.0, height: radius * 2.0))
                x += spacing
            }
            y += spacing
            rowIndex += 1
        }
    }
}

final class MessagingServerBubbleBackgroundView: UIView {
    private let fillLayer = CAShapeLayer()
    private let strokeLayer = CAShapeLayer()

    var fillColor: UIColor = .white {
        didSet {
            fillLayer.fillColor = fillColor.cgColor
        }
    }

    var strokeColor: UIColor? {
        didSet {
            strokeLayer.strokeColor = strokeColor?.cgColor
            strokeLayer.lineWidth = strokeColor == nil ? 0.0 : 1.0 / UIScreen.main.scale
        }
    }

    var tailPosition: CGFloat = 0.16 {
        didSet {
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        layer.addSublayer(fillLayer)
        layer.addSublayer(strokeLayer)
        fillLayer.fillColor = fillColor.cgColor
        strokeLayer.fillColor = UIColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let tailHeight: CGFloat = 7.0
        let path = messagingServerTelegramRoundedRectWithTailPath(
            rectSize: CGSize(width: bounds.width, height: max(16.0, bounds.height - tailHeight)),
            cornerRadius: 18.0,
            tailSize: CGSize(width: 14.0, height: tailHeight),
            tailRadius: 3.5,
            tailPosition: tailPosition,
            transformTail: true
        )
        fillLayer.frame = bounds
        fillLayer.path = path.cgPath
        strokeLayer.frame = bounds
        strokeLayer.path = path.cgPath
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
        avatarView.widthAnchor.constraint(equalToConstant: 56.0).isActive = true
        avatarView.heightAnchor.constraint(equalToConstant: 56.0).isActive = true

        titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = UIFont.systemFont(ofSize: 15.0)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
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
        textStack.spacing = 2.0
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
        subtitleLabel.textColor = .secondaryLabel
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
    let showsAvatar: Bool
    let avatarAsset: MessagingServerCachedAsset?
    let avatarTitle: String
}

final class MessagingServerBubbleCell: UITableViewCell {
    private let avatarView = MessagingServerAvatarView()
    private let horizontalStack = UIStackView()
    private let leadingSpacer = UIView()
    private let trailingSpacer = UIView()
    private let bubbleView = MessagingServerBubbleBackgroundView()
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

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.76).isActive = true

        contentStack.axis = .vertical
        contentStack.spacing = 5.0
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
            contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 14.0),
            contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 13.0),
            contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -13.0),
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
            bubbleView.tailPosition = 0.88
        } else {
            if configuration.showsAvatar {
                avatarView.configure(session: session, asset: configuration.avatarAsset, title: configuration.avatarTitle)
                horizontalStack.addArrangedSubview(avatarView)
            }
            horizontalStack.addArrangedSubview(bubbleView)
            horizontalStack.addArrangedSubview(trailingSpacer)
            bubbleView.tailPosition = 0.14
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
            bubbleView.fillColor = configuration.isFailed
                ? UIColor.systemRed.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.28 : 0.18)
                : UIColor(red: 0.13, green: 0.58, blue: 0.95, alpha: 1.0)
            bubbleView.strokeColor = configuration.isFailed ? UIColor.systemRed.withAlphaComponent(0.45) : nil
            titleLabel.textColor = UIColor.white.withAlphaComponent(0.92)
            replyLabel.textColor = UIColor.white.withAlphaComponent(0.9)
            replyLabel.backgroundColor = UIColor.white.withAlphaComponent(0.12)
            replyLabel.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
            bodyLabel.textColor = .white
            attachmentsLabel.textColor = UIColor.white.withAlphaComponent(0.92)
            reactionsLabel.textColor = UIColor.white.withAlphaComponent(0.92)
            footerLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        } else {
            bubbleView.fillColor = traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.17, green: 0.19, blue: 0.22, alpha: 0.98)
                : UIColor.white.withAlphaComponent(0.98)
            bubbleView.strokeColor = UIColor.separator.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.18 : 0.22)
            titleLabel.textColor = .systemBlue
            replyLabel.textColor = .secondaryLabel
            replyLabel.backgroundColor = UIColor.systemBackground.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.36 : 0.72)
            replyLabel.layer.borderColor = UIColor.separator.cgColor
            bodyLabel.textColor = .label
            attachmentsLabel.textColor = .secondaryLabel
            reactionsLabel.textColor = .secondaryLabel
            footerLabel.textColor = .tertiaryLabel
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
