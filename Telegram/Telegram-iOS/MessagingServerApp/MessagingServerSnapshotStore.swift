import Foundation

struct MessagingServerConversationSnapshot: Codable, Equatable {
    let messages: [MessagingServerMessage]
    let operations: [MessagingServerOperationView]
    let suggestedReplies: [MessagingServerSuggestedReply]
    let updatedAt: String
}

final class MessagingServerSnapshotStore {
    static let shared = MessagingServerSnapshotStore()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Key {
        static let inboxesPrefix = "MessagingServerSnapshot.inboxes."
        static let conversationPrefix = "MessagingServerSnapshot.conversation."
    }

    func loadInboxes(for session: MessagingServerSession) -> [MessagingServerInboxSummary] {
        loadValue(forKey: inboxesKey(for: session), as: [MessagingServerInboxSummary].self) ?? []
    }

    func saveInboxes(_ inboxes: [MessagingServerInboxSummary], for session: MessagingServerSession) {
        saveValue(inboxes, forKey: inboxesKey(for: session))
    }

    func loadConversation(inboxId: String, for session: MessagingServerSession) -> MessagingServerConversationSnapshot? {
        loadValue(forKey: conversationKey(for: inboxId, session: session), as: MessagingServerConversationSnapshot.self)
    }

    func saveConversation(_ snapshot: MessagingServerConversationSnapshot, inboxId: String, for session: MessagingServerSession) {
        saveValue(snapshot, forKey: conversationKey(for: inboxId, session: session))
    }

    private func saveValue<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    private func loadValue<T: Decodable>(forKey key: String, as type: T.Type) -> T? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? decoder.decode(type, from: data)
    }

    private func inboxesKey(for session: MessagingServerSession) -> String {
        Key.inboxesPrefix + sessionScope(for: session)
    }

    private func conversationKey(for inboxId: String, session: MessagingServerSession) -> String {
        Key.conversationPrefix + sessionScope(for: session) + "." + stableHash(inboxId)
    }

    private func sessionScope(for session: MessagingServerSession) -> String {
        stableHash("\(session.baseURL.absoluteString)|\(session.apiKey)")
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16, uppercase: false)
    }
}
