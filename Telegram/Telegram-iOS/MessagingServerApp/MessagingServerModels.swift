import Foundation

enum MessagingServerJSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case object([String: MessagingServerJSONValue])
    case array([MessagingServerJSONValue])
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: MessagingServerJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([MessagingServerJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        case .null:
            return nil
        case .object, .array:
            return nil
        }
    }
}

typealias MessagingServerJSONObject = [String: MessagingServerJSONValue]

enum MessagingServerPlatform: String, Codable, CaseIterable, Hashable {
    case instagram
    case telegram
    case kakaotalk
    case kmong
    case whatsapp
    case discord

    var displayName: String {
        switch self {
        case .kakaotalk:
            return "KakaoTalk"
        default:
            return rawValue.capitalized
        }
    }
}

enum MessagingServerInboxKind: String, Codable, Hashable {
    case dm
    case group
    case channel
    case order
    case unknown
}

enum MessagingServerAttachmentKind: String, Codable, Hashable {
    case image
    case video
    case audio
    case file
    case link
    case sticker
    case avatar
    case unknown
}

enum MessagingServerOperationType: String, Codable, Hashable {
    case sendMessage = "send_message"
    case editMessage = "edit_message"
    case deleteMessage = "delete_message"
    case reactMessage = "react_message"
}

enum MessagingServerApprovalStatus: String, Codable, Hashable {
    case pending
    case approved
    case rejected
    case expired
}

enum MessagingServerApprovalExecutionStatus: String, Codable, Hashable {
    case pending
    case running
    case succeeded
    case failed
}

enum MessagingServerOperationStatus: String, Codable, Hashable {
    case approvalRequested = "approval_requested"
    case approved
    case denied
    case canceled
    case expired
    case executing
    case executed
    case failed
}

struct MessagingServerPlatformCapabilities: Codable, Equatable {
    let supportsTextSend: Bool
    let supportsMediaSend: Bool
    let supportsRead: Bool
    let supportsAttachmentFetch: Bool
    let supportsRealtime: Bool
    let supportsDirectMessages: Bool
    let supportsGroups: Bool
    let supportsSuggestedReplies: Bool
    let supportsMessageEdit: Bool
    let supportsMessageDelete: Bool
    let supportsMessageReactions: Bool
    let supportsStickers: Bool
    let supportsProfileImages: Bool
}

struct MessagingServerPlatformStatus: Codable, Equatable {
    let platform: MessagingServerPlatform
    let accountKey: String
    let accountName: String
    let configured: Bool
    let authenticated: Bool
    let canRead: Bool
    let canSend: Bool
    let lastSyncAt: String?
    let lastError: String?
    let capabilities: MessagingServerPlatformCapabilities

    var statusSummary: String {
        if let lastError, !lastError.isEmpty {
            return lastError
        }
        if authenticated && canRead {
            return "Ready"
        }
        if configured {
            return "Configured"
        }
        return "Needs setup"
    }

    var displayAccountName: String {
        if !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return accountName
        }
        return accountKey
    }
}

struct MessagingServerCachedAsset: Codable, Equatable {
    let assetId: String
    let kind: String
    let filename: String?
    let mimeType: String?
    let sizeBytes: Int?
    let previewUrl: String?
    let contentUrl: String?
    let remoteUrl: String?
    let sha256: String?
}

struct MessagingServerInboxParticipant: Codable, Equatable {
    let participantId: String
    let participantName: String?
    let username: String?
    let isSelf: Bool
    let profileAsset: MessagingServerCachedAsset?
    let meta: MessagingServerJSONObject

    var displayName: String {
        if let participantName, !participantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return participantName
        }
        if let username, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return username
        }
        return participantId
    }
}

struct MessagingServerInboxSummary: Codable, Equatable {
    let platform: MessagingServerPlatform
    let accountKey: String
    let inboxId: String
    let inboxName: String
    let kind: MessagingServerInboxKind
    let unreadCount: Int
    let lastMessagePreview: String?
    let lastMessageAt: String?
    let participantCount: Int
    let avatarAsset: MessagingServerCachedAsset?
    let participants: [MessagingServerInboxParticipant]

    var displayTitle: String {
        if !inboxName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inboxName
        }
        if let counterpart = participants.first(where: { !$0.isSelf }) {
            return counterpart.displayName
        }
        return inboxId
    }

    var avatarTitle: String {
        if let counterpart = participants.first(where: { !$0.isSelf }) {
            return counterpart.displayName
        }
        return displayTitle
    }

    var lastPreviewText: String {
        let preview = lastMessagePreview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preview.isEmpty {
            return preview
        }
        return "No messages yet"
    }

    var subtitleText: String {
        var parts: [String] = [platform.displayName, accountKey]
        let preview = lastMessagePreview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preview.isEmpty {
            parts.append(preview)
        }
        return parts.joined(separator: " · ")
    }
}

struct MessagingServerInboxReadState: Codable, Equatable {
    let inboxId: String
    let lastReadMessageSeq: String?
    let lastReadAt: String?
    let updatedAt: String?
}

struct MessagingServerAttachment: Codable, Equatable {
    let attachmentId: String
    let kind: MessagingServerAttachmentKind
    let filename: String?
    let mimeType: String?
    let sizeBytes: Int?
    let previewUrl: String?
    let contentUrl: String?
    let asset: MessagingServerCachedAsset?

    var displayName: String {
        if let filename, !filename.isEmpty {
            return filename
        }
        if let mimeType, !mimeType.isEmpty {
            return mimeType
        }
        return kind.rawValue.capitalized
    }
}

struct MessagingServerMessageSticker: Codable, Equatable {
    let stickerId: String
    let label: String?
    let asset: MessagingServerCachedAsset?
    let meta: MessagingServerJSONObject
}

struct MessagingServerMessageReaction: Codable, Equatable {
    let reactionKey: String
    let userId: String
    let userName: String?
    let emoji: String
    let createdAt: String?
    let meta: MessagingServerJSONObject
}

struct MessagingServerMessage: Codable, Equatable {
    let platform: MessagingServerPlatform
    let accountKey: String
    let inboxId: String
    let messageId: String
    let direction: Direction
    let senderName: String?
    let senderId: String?
    let senderProfileAsset: MessagingServerCachedAsset?
    let text: String
    let attachments: [MessagingServerAttachment]
    let stickers: [MessagingServerMessageSticker]
    let reactions: [MessagingServerMessageReaction]
    let sentAt: String?
    let rawType: String?
    let replyToMessageId: String?
    let editedAt: String?
    let deletedAt: String?
    let meta: MessagingServerJSONObject

    enum Direction: String, Codable, Hashable {
        case incoming
        case outgoing
        case system
    }

    var senderDisplayName: String {
        if let senderName, !senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return senderName
        }
        if let senderId, !senderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return senderId
        }
        return direction == .system ? "System" : "Unknown"
    }

    var displayText: String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            return trimmedText
        }
        if let firstAttachment = attachments.first {
            return firstAttachment.kind == .image ? "Photo" : "Attachment: \(firstAttachment.displayName)"
        }
        if let firstSticker = stickers.first {
            return firstSticker.label ?? "Sticker"
        }
        return "(empty message)"
    }

    var attachmentSummary: String? {
        guard !attachments.isEmpty else {
            return nil
        }
        return attachments.map(\.displayName).joined(separator: "\n")
    }

    var previewAssets: [MessagingServerCachedAsset] {
        attachments.compactMap(\.asset) + stickers.compactMap(\.asset)
    }

    var reactionsSummary: String? {
        guard !reactions.isEmpty else {
            return nil
        }
        var counts: [String: Int] = [:]
        var order: [String] = []
        for reaction in reactions {
            if counts[reaction.emoji] == nil {
                order.append(reaction.emoji)
            }
            counts[reaction.emoji, default: 0] += 1
        }
        let tokens = order.map { emoji in
            let count = counts[emoji] ?? 0
            return count > 1 ? "\(emoji) \(count)" : emoji
        }
        return tokens.joined(separator: "  ")
    }
}

struct MessagingServerApprovalResult: Codable, Equatable {
    let status: String
    let approvalId: String
    let operationId: String
    let operationType: MessagingServerOperationType
}

struct MessagingServerOperationView: Codable, Equatable {
    let operationId: String
    let approvalId: String?
    let operationType: MessagingServerOperationType
    let platform: MessagingServerPlatform
    let accountKey: String
    let inboxId: String
    let messageId: String?
    let preview: String
    let payload: MessagingServerJSONObject
    let requestedAt: String
    let executedAt: String?
    let localStatus: MessagingServerOperationStatus
    let approvalStatus: MessagingServerApprovalStatus?
    let executionStatus: MessagingServerApprovalExecutionStatus?
    let error: String?
    let platformMessageIds: [String]
    let uploadAssetIds: [String]
    let uploadAssets: [MessagingServerCachedAsset]
    let replacementOperationId: String?
    let localAttachmentNames: [String]? = nil

    var isPendingBubble: Bool {
        guard operationType == .sendMessage else {
            return false
        }
        switch localStatus {
        case .approvalRequested, .approved, .executing, .failed:
            return true
        case .denied, .canceled, .expired, .executed:
            return false
        }
    }

    var isLocalOnly: Bool {
        approvalId == nil && operationId.hasPrefix("local:")
    }

    var suggestedEditText: String {
        if let payloadText = payload["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !payloadText.isEmpty {
            return payloadText
        }
        return preview
    }

    var attachmentSummary: String? {
        if let localAttachmentNames, !localAttachmentNames.isEmpty {
            return localAttachmentNames.joined(separator: "\n")
        }
        guard !uploadAssets.isEmpty else {
            return nil
        }
        return uploadAssets.compactMap { asset in
            if let filename = asset.filename, !filename.isEmpty {
                return filename
            }
            return asset.mimeType
        }.joined(separator: "\n")
    }

    var previewAssets: [MessagingServerCachedAsset] {
        uploadAssets
    }

    var statusSummary: String {
        switch localStatus {
        case .approvalRequested:
            return approvalStatus == .pending ? "Awaiting approval" : "Queued"
        case .approved:
            return "Approved"
        case .denied:
            return "Denied"
        case .canceled:
            return "Canceled"
        case .expired:
            return "Expired"
        case .executing:
            return "Sending"
        case .executed:
            return "Sent"
        case .failed:
            return error ?? "Failed"
        }
    }
}

struct MessagingServerExecutionProof: Codable, Equatable {
    let approvalId: String
    let operationId: String?
    let operationType: MessagingServerOperationType
    let status: MessagingServerOperationStatus
    let approvalStatus: MessagingServerApprovalStatus?
    let executionStatus: MessagingServerApprovalExecutionStatus?
    let executedAt: String?
    let platformMessageIds: [String]
    let responseSnippet: String?
    let error: String?
}

struct MessagingServerSuggestedReply: Codable, Equatable {
    let id: String
    let inboxId: String
    let text: String
    let orderIndex: Int
    let createdAt: String
    let updatedAt: String
}

struct MessagingServerSendMessageRequest: Encodable {
    let text: String?
    let media: [String]
    let uploadIds: [String]?
    let replyToMessageId: String?

    init(text: String?, media: [String] = [], uploadIds: [String]? = nil, replyToMessageId: String? = nil) {
        self.text = text
        self.media = media
        self.uploadIds = uploadIds
        self.replyToMessageId = replyToMessageId
    }
}

struct MessagingServerEditMessageRequest: Encodable {
    let text: String
}

struct MessagingServerDeleteMessageRequest: Encodable {
    let hardDelete: Bool?
}

struct MessagingServerMessageReactionRequest: Encodable {
    let emoji: String
    let reactionKey: String?
    let remove: Bool?
}

struct MessagingServerCreateSuggestedReplyRequest: Encodable {
    let text: String
    let orderIndex: Int?
}

struct MessagingServerUpdateInboxReadStateRequest: Encodable {
    let lastReadMessageSeq: String
}

struct MessagingServerUploadDraft: Equatable {
    let id: UUID
    let filename: String
    let mimeType: String
    let data: Data

    init(id: UUID = UUID(), filename: String, mimeType: String, data: Data) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

enum MessagingServerDate {
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let listTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let listWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let listDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    private static let chatTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return iso8601WithFractional.date(from: value) ?? iso8601.date(from: value)
    }

    static func short(_ value: String?) -> String {
        guard let date = parse(value) else {
            return ""
        }
        return shortFormatter.string(from: date)
    }

    static func listTimestamp(_ value: String?) -> String {
        guard let date = parse(value) else {
            return ""
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return listTimeFormatter.string(from: date)
        }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return listWeekdayFormatter.string(from: date)
        }
        return listDateFormatter.string(from: date)
    }

    static func conversationTimestamp(_ value: String?) -> String {
        guard let date = parse(value) else {
            return ""
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return chatTimeFormatter.string(from: date)
        }
        return shortFormatter.string(from: date)
    }

    static func nowString() -> String {
        iso8601WithFractional.string(from: Date())
    }
}

extension Array where Element == MessagingServerPlatformStatus {
    func accountName(for accountKey: String) -> String? {
        first(where: { $0.accountKey == accountKey })?.displayAccountName
    }
}
