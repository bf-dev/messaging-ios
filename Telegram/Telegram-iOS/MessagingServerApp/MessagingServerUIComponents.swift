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
        layer.cornerRadius = 16.0
        layer.borderWidth = 1.0
        contentEdgeInsets = UIEdgeInsets(top: 8.0, left: 12.0, bottom: 8.0, right: 12.0)
    }

    func applySelectedStyle(_ selected: Bool) {
        backgroundColor = selected ? tintColor.withAlphaComponent(0.14) : .secondarySystemBackground
        layer.borderColor = (selected ? tintColor : UIColor.separator).cgColor
        setTitleColor(selected ? tintColor : .label, for: .normal)
    }
}

struct MessagingServerBubbleConfiguration {
    let title: String?
    let body: String
    let attachments: String?
    let footer: String
    let isOutgoing: Bool
    let isPending: Bool
    let isFailed: Bool
}

final class MessagingServerBubbleCell: UITableViewCell {
    private let bubbleView = UIView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let attachmentsLabel = UILabel()
    private let footerLabel = UILabel()
    private let contentStack = UIStackView()
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        bubbleView.layer.cornerRadius = 18.0
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)

        titleLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        titleLabel.numberOfLines = 2

        bodyLabel.font = UIFont.systemFont(ofSize: 16.0)
        bodyLabel.numberOfLines = 0

        attachmentsLabel.font = UIFont.systemFont(ofSize: 13.0)
        attachmentsLabel.numberOfLines = 0

        footerLabel.font = UIFont.systemFont(ofSize: 11.0, weight: .medium)
        footerLabel.numberOfLines = 2

        contentStack.axis = .vertical
        contentStack.spacing = 6.0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(contentStack)

        [titleLabel, bodyLabel, attachmentsLabel, footerLabel].forEach(contentStack.addArrangedSubview)

        let maxWidthConstraint = bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.78)
        maxWidthConstraint.priority = .required

        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16.0)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16.0)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6.0),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6.0),
            maxWidthConstraint,
            contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10.0),
            contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12.0),
            contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12.0),
            contentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10.0),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        leadingConstraint?.isActive = false
        trailingConstraint?.isActive = false
    }

    func configure(_ configuration: MessagingServerBubbleConfiguration) {
        titleLabel.text = configuration.title
        titleLabel.isHidden = configuration.title?.isEmpty ?? true
        bodyLabel.text = configuration.body
        attachmentsLabel.text = configuration.attachments
        attachmentsLabel.isHidden = configuration.attachments?.isEmpty ?? true
        footerLabel.text = configuration.footer

        let isOutgoing = configuration.isOutgoing
        leadingConstraint?.isActive = !isOutgoing
        trailingConstraint?.isActive = isOutgoing

        if isOutgoing {
            bubbleView.backgroundColor = configuration.isFailed ? UIColor.systemRed.withAlphaComponent(0.18) : UIColor.systemBlue
            titleLabel.textColor = .white
            bodyLabel.textColor = .white
            attachmentsLabel.textColor = UIColor.white.withAlphaComponent(0.92)
            footerLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        } else {
            bubbleView.backgroundColor = UIColor.secondarySystemBackground
            titleLabel.textColor = .secondaryLabel
            bodyLabel.textColor = .label
            attachmentsLabel.textColor = .secondaryLabel
            footerLabel.textColor = .tertiaryLabel
        }

        bubbleView.alpha = configuration.isPending ? 0.6 : 1.0
        if configuration.isFailed {
            bubbleView.layer.borderWidth = 1.0
            bubbleView.layer.borderColor = UIColor.systemRed.withAlphaComponent(0.5).cgColor
        } else {
            bubbleView.layer.borderWidth = 0.0
            bubbleView.layer.borderColor = nil
        }
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
