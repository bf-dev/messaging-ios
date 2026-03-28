import Foundation

enum MessagingServerAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)
    case httpStatus(Int, String)
    case emptyEnvelope
    case transport(Error)

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

    private let session: MessagingServerSession
    private let urlSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: MessagingServerSession, urlSession: URLSession = .shared) {
        self.session = session
        self.urlSession = urlSession
    }

    func validateSession(completion: @escaping (Result<[MessagingServerPlatformStatus], Error>) -> Void) {
        listPlatformStatus(completion: completion)
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
            completion(.failure(MessagingServerAPIError.invalidURL))
            return
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        rawBody: Data? = nil,
        contentType: String? = nil,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        guard let url = makeURL(path: path, queryItems: queryItems) else {
            completion(.failure(MessagingServerAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(session.apiKey, forHTTPHeaderField: "X-Messaging-Api-Key")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = rawBody

        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            self?.handleResult(data: data, response: response, error: error, completion: completion)
        }
        task.resume()
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
            completion(.failure(error))
        }
    }

    private func handleResult<T: Decodable>(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
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
        return value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
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
