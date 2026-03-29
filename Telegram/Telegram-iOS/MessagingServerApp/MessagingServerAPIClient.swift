import Foundation

final class MessagingServerTaskHandle {
    private let lock = NSLock()
    private var onCancel: (() -> Void)?

    init(onCancel: (() -> Void)? = nil) {
        self.onCancel = onCancel
    }

    func cancel() {
        lock.lock()
        let action = onCancel
        onCancel = nil
        lock.unlock()
        action?()
    }
}

enum MessagingServerAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)
    case httpStatus(Int, String)
    case emptyEnvelope
    case transport(Error)
    case timeout(TimeInterval)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL."
        case .invalidResponse:
            return "Unexpected server response."
        case let .server(message):
            return message
        case let .httpStatus(code, message):
            return message.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(message)"
        case .emptyEnvelope:
            return "The server returned no payload."
        case let .transport(error):
            return error.localizedDescription
        case let .timeout(seconds):
            return "Connection timed out after \(Int(seconds)) seconds."
        case .cancelled:
            return "Request cancelled."
        }
    }
}

final class MessagingServerAPIClient {
    private struct Envelope<T: Decodable>: Decodable {
        let success: Bool
        let data: T?
        let error: String?
    }

    private struct ErrorEnvelope: Decodable {
        let success: Bool?
        let error: String?
    }

    private final class CompletionGate {
        private let lock = NSLock()
        private var isFinished = false

        func run(_ block: () -> Void) {
            lock.lock()
            guard !isFinished else {
                lock.unlock()
                return
            }
            isFinished = true
            lock.unlock()
            block()
        }
    }

    private let session: MessagingServerSession
    private let urlSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: MessagingServerSession, urlSession: URLSession? = nil) {
        self.session = session
        self.urlSession = urlSession ?? Self.makeDefaultURLSession()
    }

    func validateSession(
        timeout: TimeInterval = 10.0,
        completion: @escaping (Result<[MessagingServerPlatformStatus], Error>) -> Void
    ) -> MessagingServerTaskHandle {
        let gate = CompletionGate()
        var validationTask: URLSessionDataTask?

        let timeoutWorkItem = DispatchWorkItem {
            gate.run {
                validationTask?.cancel()
                completion(.failure(MessagingServerAPIError.timeout(timeout)))
            }
        }

        validationTask = requestTask(
            path: "/v1/platforms/status",
            queryItems: [],
            timeout: timeout,
            completion: { (result: Result<[MessagingServerPlatformStatus], Error>) in
                gate.run {
                    timeoutWorkItem.cancel()
                    switch result {
                    case let .failure(error as MessagingServerAPIError) where error == .cancelled:
                        break
                    case let .failure(error):
                        completion(.failure(error))
                    case let .success(statuses):
                        completion(.success(statuses))
                    }
                }
            }
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
        return MessagingServerTaskHandle {
            timeoutWorkItem.cancel()
            gate.run {
                validationTask?.cancel()
            }
        }
    }

    func listPlatformStatus(
        platform: MessagingServerPlatform? = nil,
        account: String? = nil,
        completion: @escaping (Result<[MessagingServerPlatformStatus], Error>) -> Void
    ) {
        request(
            path: "/v1/platforms/status",
            queryItems: [
                queryItem(name: "platform", value: platform?.rawValue),
                queryItem(name: "account", value: account),
            ].compactMap { $0 },
            completion: completion
        )
    }

    func listInboxes(
        platform: MessagingServerPlatform? = nil,
        account: String? = nil,
        limit: Int = 100,
        offset: Int = 0,
        completion: @escaping (Result<[MessagingServerInboxSummary], Error>) -> Void
    ) {
        request(
            path: "/v1/inboxes",
            queryItems: [
                queryItem(name: "platform", value: platform?.rawValue),
                queryItem(name: "account", value: account),
                queryItem(name: "limit", value: String(limit)),
                queryItem(name: "offset", value: String(offset)),
            ].compactMap { $0 },
            completion: completion
        )
    }

    func listMessages(
        inboxId: String,
        limit: Int = 200,
        offset: Int = 0,
        completion: @escaping (Result<[MessagingServerMessage], Error>) -> Void
    ) {
        request(
            path: "/v1/inboxes/\(encoded(inboxId))/messages",
            queryItems: [
                queryItem(name: "limit", value: String(limit)),
                queryItem(name: "offset", value: String(offset)),
            ].compactMap { $0 },
            completion: completion
        )
    }

    func listInboxOperations(
        inboxId: String,
        pendingOnly: Bool = true,
        limit: Int = 200,
        offset: Int = 0,
        completion: @escaping (Result<[MessagingServerOperationView], Error>) -> Void
    ) {
        request(
            path: "/v1/inboxes/\(encoded(inboxId))/operations",
            queryItems: [
                queryItem(name: "pendingOnly", value: pendingOnly ? "true" : "false"),
                queryItem(name: "limit", value: String(limit)),
                queryItem(name: "offset", value: String(offset)),
            ].compactMap { $0 },
            completion: completion
        )
    }

    func listSuggestedReplies(
        inboxId: String,
        completion: @escaping (Result<[MessagingServerSuggestedReply], Error>) -> Void
    ) {
        request(
            path: "/v1/inboxes/\(encoded(inboxId))/suggested-replies",
            completion: completion
        )
    }

    func createSuggestedReply(
        inboxId: String,
        text: String,
        orderIndex: Int? = nil,
        completion: @escaping (Result<MessagingServerSuggestedReply, Error>) -> Void
    ) {
        let payload = MessagingServerCreateSuggestedReplyRequest(text: text, orderIndex: orderIndex)
        request(
            path: "/v1/inboxes/\(encoded(inboxId))/suggested-replies",
            method: "POST",
            jsonBody: payload,
            completion: completion
        )
    }

    func getInboxReadState(
        inboxId: String,
        completion: @escaping (Result<MessagingServerInboxReadState, Error>) -> Void
    ) {
        request(
            path: "/v1/inboxes/\(encoded(inboxId))/read-state",
            completion: completion
        )
    }

    func updateInboxReadState(
        inboxId: String,
        lastReadMessageSeq: String,
        completion: @escaping (Result<MessagingServerInboxReadState, Error>) -> Void
    ) {
        request(
            path: "/v1/inboxes/\(encoded(inboxId))/read-state",
            method: "PUT",
            jsonBody: MessagingServerUpdateInboxReadStateRequest(lastReadMessageSeq: lastReadMessageSeq),
            completion: completion
        )
    }

    func sendMessage(
        inboxId: String,
        requestBody: MessagingServerSendMessageRequest,
        completion: @escaping (Result<MessagingServerApprovalResult, Error>) -> Void
    ) {
        request(
            path: "/v1/inboxes/\(encoded(inboxId))/messages",
            method: "POST",
            jsonBody: requestBody,
            completion: completion
        )
    }

    func editMessage(
        messageId: String,
        requestBody: MessagingServerEditMessageRequest,
        completion: @escaping (Result<MessagingServerApprovalResult, Error>) -> Void
    ) {
        request(
            path: "/v1/messages/\(encoded(messageId))",
            method: "PATCH",
            jsonBody: requestBody,
            completion: completion
        )
    }

    func deleteMessage(
        messageId: String,
        requestBody: MessagingServerDeleteMessageRequest = MessagingServerDeleteMessageRequest(hardDelete: nil),
        completion: @escaping (Result<MessagingServerApprovalResult, Error>) -> Void
    ) {
        request(
            path: "/v1/messages/\(encoded(messageId))",
            method: "DELETE",
            jsonBody: requestBody,
            completion: completion
        )
    }

    func reactToMessage(
        messageId: String,
        requestBody: MessagingServerMessageReactionRequest,
        completion: @escaping (Result<MessagingServerApprovalResult, Error>) -> Void
    ) {
        request(
            path: "/v1/messages/\(encoded(messageId))/reactions",
            method: "POST",
            jsonBody: requestBody,
            completion: completion
        )
    }

    func uploadAttachment(
        _ attachment: MessagingServerUploadDraft,
        completion: @escaping (Result<MessagingServerCachedAsset, Error>) -> Void
    ) {
        guard let url = makeURL(path: "/v1/uploads", queryItems: []) else {
            DispatchQueue.main.async {
                completion(.failure(MessagingServerAPIError.invalidURL))
            }
            return
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45.0
        request.setValue(session.apiKey, forHTTPHeaderField: "X-Messaging-Api-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, attachment: attachment)

        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            self?.handleResult(data: data, response: response, error: error, completion: completion)
        }
        task.resume()
    }

    func getOperation(
        operationId: String,
        completion: @escaping (Result<MessagingServerOperationView, Error>) -> Void
    ) {
        request(
            path: "/v1/operations/\(encoded(operationId))",
            completion: completion
        )
    }

    func approveOperation(
        operationId: String,
        completion: @escaping (Result<MessagingServerOperationView, Error>) -> Void
    ) {
        request(
            path: "/v1/operations/\(encoded(operationId))/approve",
            method: "POST",
            rawBody: Data("{}".utf8),
            contentType: "application/json",
            completion: completion
        )
    }

    func denyOperation(
        operationId: String,
        completion: @escaping (Result<MessagingServerOperationView, Error>) -> Void
    ) {
        request(
            path: "/v1/operations/\(encoded(operationId))/deny",
            method: "POST",
            rawBody: Data("{}".utf8),
            contentType: "application/json",
            completion: completion
        )
    }

    func cancelOperation(
        operationId: String,
        completion: @escaping (Result<MessagingServerOperationView, Error>) -> Void
    ) {
        request(
            path: "/v1/operations/\(encoded(operationId))/cancel",
            method: "POST",
            rawBody: Data("{}".utf8),
            contentType: "application/json",
            completion: completion
        )
    }

    func replacePendingOperation(
        operationId: String,
        requestBody: MessagingServerSendMessageRequest,
        completion: @escaping (Result<MessagingServerOperationView, Error>) -> Void
    ) {
        request(
            path: "/v1/operations/\(encoded(operationId))",
            method: "PATCH",
            jsonBody: requestBody,
            completion: completion
        )
    }

    func getProof(
        approvalId: String,
        completion: @escaping (Result<MessagingServerExecutionProof, Error>) -> Void
    ) {
        request(
            path: "/v1/proofs/\(encoded(approvalId))",
            completion: completion
        )
    }

    private static func makeDefaultURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15.0
        configuration.timeoutIntervalForResource = 30.0
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    @discardableResult
    private func requestTask<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        rawBody: Data? = nil,
        contentType: String? = nil,
        timeout: TimeInterval? = nil,
        completion: @escaping (Result<T, Error>) -> Void
    ) -> URLSessionDataTask? {
        guard let url = makeURL(path: path, queryItems: queryItems) else {
            DispatchQueue.main.async {
                completion(.failure(MessagingServerAPIError.invalidURL))
            }
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(session.apiKey, forHTTPHeaderField: "X-Messaging-Api-Key")
        request.timeoutInterval = timeout ?? 15.0
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = rawBody

        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            self?.handleResult(data: data, response: response, error: error, completion: completion)
        }
        task.resume()
        return task
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        rawBody: Data? = nil,
        contentType: String? = nil,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        _ = requestTask(
            path: path,
            method: method,
            queryItems: queryItems,
            rawBody: rawBody,
            contentType: contentType,
            completion: completion
        )
    }

    private func request<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        jsonBody: Body,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        do {
            let body = try encoder.encode(jsonBody)
            request(
                path: path,
                method: method,
                rawBody: body,
                contentType: "application/json",
                completion: completion
            )
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }

    private func handleResult<T: Decodable>(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        if let urlError = error as? URLError, urlError.code == .cancelled {
            DispatchQueue.main.async {
                completion(.failure(MessagingServerAPIError.cancelled))
            }
            return
        }
        if let urlError = error as? URLError, [.timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet].contains(urlError.code) {
            DispatchQueue.main.async {
                completion(.failure(MessagingServerAPIError.transport(urlError)))
            }
            return
        }
        if let error {
            DispatchQueue.main.async {
                completion(.failure(MessagingServerAPIError.transport(error)))
            }
            return
        }
        guard let httpResponse = response as? HTTPURLResponse, let data else {
            DispatchQueue.main.async {
                completion(.failure(MessagingServerAPIError.invalidResponse))
            }
            return
        }

        if !(200 ..< 300).contains(httpResponse.statusCode) {
            let errorMessage = decodedErrorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                completion(.failure(MessagingServerAPIError.httpStatus(httpResponse.statusCode, errorMessage)))
            }
            return
        }

        if let envelope = try? decoder.decode(Envelope<T>.self, from: data) {
            if envelope.success, let payload = envelope.data {
                DispatchQueue.main.async {
                    completion(.success(payload))
                }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(MessagingServerAPIError.server(envelope.error ?? MessagingServerAPIError.emptyEnvelope.localizedDescription)))
                }
            }
            return
        }

        if let direct = try? decoder.decode(T.self, from: data) {
            DispatchQueue.main.async {
                completion(.success(direct))
            }
            return
        }

        DispatchQueue.main.async {
            completion(.failure(MessagingServerAPIError.invalidResponse))
        }
    }

    private func decodedErrorMessage(from data: Data) -> String? {
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data), let error = envelope.error, !error.isEmpty {
            return error
        }
        return nil
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(url: session.baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }

    private func queryItem(name: String, value: String?) -> URLQueryItem? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return URLQueryItem(name: name, value: value)
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func multipartBody(boundary: String, attachment: MessagingServerUploadDraft) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(attachment.filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(attachment.mimeType)\r\n\r\n".utf8))
        body.append(attachment.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}

extension MessagingServerAPIError: Equatable {
    static func == (lhs: MessagingServerAPIError, rhs: MessagingServerAPIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL), (.invalidResponse, .invalidResponse), (.emptyEnvelope, .emptyEnvelope), (.cancelled, .cancelled):
            return true
        case let (.server(left), .server(right)):
            return left == right
        case let (.httpStatus(leftCode, leftMessage), .httpStatus(rightCode, rightMessage)):
            return leftCode == rightCode && leftMessage == rightMessage
        case let (.timeout(left), .timeout(right)):
            return left == right
        case let (.transport(left), .transport(right)):
            return left.localizedDescription == right.localizedDescription
        default:
            return false
        }
    }
}
