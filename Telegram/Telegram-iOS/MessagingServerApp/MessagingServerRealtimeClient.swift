import Foundation

struct MessagingServerRealtimeEvent {
    let eventType: String
    let topic: String
    let payload: MessagingServerJSONObject
    let createdAt: String
    let id: String
}

final class MessagingServerRealtimeClient {
    private struct WebSocketFrame: Decodable {
        let type: String
        let eventType: String?
        let topic: String?
        let payload: MessagingServerJSONObject?
        let createdAt: String?
        let id: String?
        let error: String?
        let message: String?
    }

    private let session: MessagingServerSession
    private let urlSession: URLSession
    private let decoder = JSONDecoder()
    private var task: URLSessionWebSocketTask?
    private var shouldReconnect = false

    var onEvent: ((MessagingServerRealtimeEvent) -> Void)?
    var onError: ((Error) -> Void)?

    init(session: MessagingServerSession) {
        self.session = session
        self.urlSession = URLSession(configuration: .default)
    }

    func connect() {
        guard task == nil, let url = webSocketURL() else {
            return
        }
        shouldReconnect = true
        let task = urlSession.webSocketTask(with: url)
        self.task = task
        task.resume()
        sendAuth()
        receiveNextMessage()
    }

    func disconnect() {
        shouldReconnect = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func webSocketURL() -> URL? {
        guard var components = URLComponents(url: session.baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if components.scheme == "https" {
            components.scheme = "wss"
        } else if components.scheme == "http" {
            components.scheme = "ws"
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + "/v1/ws"
        return components.url
    }

    private func sendAuth() {
        let payload = ["type": "auth", "apiKey": session.apiKey]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []), let text = String(data: data, encoding: .utf8) else {
            return
        }
        task?.send(.string(text)) { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.onError?(error)
                }
            }
        }
    }

    private func receiveNextMessage() {
        task?.receive { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .failure(error):
                DispatchQueue.main.async {
                    self.onError?(error)
                }
                self.handleDisconnect()
            case let .success(message):
                self.handle(message)
                self.receiveNextMessage()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String?
        switch message {
        case let .string(value):
            text = value
        case let .data(data):
            text = String(data: data, encoding: .utf8)
        @unknown default:
            text = nil
        }
        guard let text, let data = text.data(using: .utf8) else {
            return
        }

        do {
            let frame = try decoder.decode(WebSocketFrame.self, from: data)
            if frame.type == "auth.error" {
                let error = MessagingServerAPIError.server(frame.error ?? "WebSocket auth failed.")
                DispatchQueue.main.async {
                    self.onError?(error)
                }
                handleDisconnect()
                return
            }
            guard frame.type == "event", let eventType = frame.eventType, let topic = frame.topic, let payload = frame.payload, let createdAt = frame.createdAt, let id = frame.id else {
                return
            }
            let event = MessagingServerRealtimeEvent(eventType: eventType, topic: topic, payload: payload, createdAt: createdAt, id: id)
            DispatchQueue.main.async {
                self.onEvent?(event)
            }
        } catch {
            DispatchQueue.main.async {
                self.onError?(error)
            }
        }
    }

    private func handleDisconnect() {
        task = nil
        guard shouldReconnect else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.connect()
        }
    }
}
