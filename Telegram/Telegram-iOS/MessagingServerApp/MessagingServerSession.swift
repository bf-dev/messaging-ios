import Foundation
import Security

struct MessagingServerSession: Equatable {
    let baseURL: URL
    let apiKey: String

    var displayBaseURL: String {
        baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var maskedApiKey: String {
        guard apiKey.count > 8 else {
            return String(repeating: "•", count: max(apiKey.count, 4))
        }
        let suffix = apiKey.suffix(4)
        return "••••••••\(suffix)"
    }
}

enum MessagingServerSessionStoreError: LocalizedError {
    case invalidBaseURL
    case emptyAPIKey
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Enter a valid server URL."
        case .emptyAPIKey:
            return "Enter an API key."
        case let .keychainFailure(status):
            return "Keychain error (\(status))."
        }
    }
}

final class MessagingServerSessionStore {
    static let shared = MessagingServerSessionStore()
    static let defaultBaseURL = "https://messaging-server.insu.ng"

    private let defaults = UserDefaults.standard
    private let baseURLKey = "MessagingServer.baseURL"
    private let keychain = MessagingServerKeychain(service: "insu.messaging-server.ios", account: "default-api-key")

    func loadSession() -> MessagingServerSession? {
        guard let apiKey = currentAPIKey(), !apiKey.isEmpty else {
            return nil
        }
        let rawBaseURL = defaults.string(forKey: baseURLKey) ?? Self.defaultBaseURL
        guard let baseURL = Self.normalizeBaseURL(rawBaseURL) else {
            return nil
        }
        return MessagingServerSession(baseURL: baseURL, apiKey: apiKey)
    }

    func currentAPIKey() -> String? {
        guard let apiKey = try? keychain.read(), !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }

    func lastBaseURLString() -> String {
        defaults.string(forKey: baseURLKey) ?? Self.defaultBaseURL
    }

    func makeDraftSession(baseURLString: String, apiKey: String) throws -> MessagingServerSession {
        guard let baseURL = Self.normalizeBaseURL(baseURLString) else {
            throw MessagingServerSessionStoreError.invalidBaseURL
        }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw MessagingServerSessionStoreError.emptyAPIKey
        }
        return MessagingServerSession(baseURL: baseURL, apiKey: trimmedKey)
    }

    func persist(_ session: MessagingServerSession) throws {
        defaults.set(session.baseURL.absoluteString, forKey: baseURLKey)
        try keychain.write(session.apiKey)
    }

    @discardableResult
    func save(baseURLString: String, apiKey: String) throws -> MessagingServerSession {
        let session = try makeDraftSession(baseURLString: baseURLString, apiKey: apiKey)
        try persist(session)
        return session
    }

    func clear() {
        defaults.removeObject(forKey: baseURLKey)
        try? keychain.delete()
    }

    static func normalizeBaseURL(_ rawValue: String) -> URL? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        if !value.contains("://") {
            value = "https://\(value)"
        }
        guard var components = URLComponents(string: value), let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        components.scheme = scheme
        guard let url = components.url else {
            return nil
        }
        return url
    }
}

final class MessagingServerKeychain {
    private let service: String
    private let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    func read() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                return ""
            }
            return value
        case errSecItemNotFound:
            return ""
        default:
            throw MessagingServerSessionStoreError.keychainFailure(status)
        }
    }

    func write(_ value: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw MessagingServerSessionStoreError.keychainFailure(updateStatus)
        }

        var addQuery = baseQuery
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw MessagingServerSessionStoreError.keychainFailure(addStatus)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MessagingServerSessionStoreError.keychainFailure(status)
        }
    }
}

final class MessagingServerAppContext {
    static let shared = MessagingServerAppContext()

    let sessionStore: MessagingServerSessionStore

    init(sessionStore: MessagingServerSessionStore = .shared) {
        self.sessionStore = sessionStore
    }

    var currentSession: MessagingServerSession? {
        sessionStore.loadSession()
    }

    func makeAPIClient() -> MessagingServerAPIClient? {
        guard let session = currentSession else {
            return nil
        }
        return MessagingServerAPIClient(session: session)
    }

    func makeRealtimeClient() -> MessagingServerRealtimeClient? {
        guard let session = currentSession else {
            return nil
        }
        return MessagingServerRealtimeClient(session: session)
    }
}
