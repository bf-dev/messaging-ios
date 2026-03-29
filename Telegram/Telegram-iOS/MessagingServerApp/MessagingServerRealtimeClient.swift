import Foundation

struct MessagingServerRealtimeEvent {
    let eventType: String
    let topic: String
    let payload: MessagingServerJSONObject
    let createdAt: String
    let id: String
}

enum MessagingServerRealtimeState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
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
    private var reconnectDelay: TimeInterval = 2.0

    var onEvent: ((MessagingServerRealtimeEvent) -> Void)?
    var onError: ((Error) -> Void)?
    var onStateChange: ((MessagingServerRealtimeState) -> Void)?

    init(session: MessagingServerSession) {
        self.session = session

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15.0
        configuration.timeoutIntervalForResource = 30.0
        configuration.waitsForConnectivity = false
        self.urlSession = URLSession(configuration: configuration)
    }

    func connect() {
        guard task == nil, let url = webSocketURL() else {
            return
        }
        shouldReconnect = true
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(.connecting)
        }

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
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(.disconnected)
        }
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
            case .failure:
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
            switch frame.type {
            case "hello":
                DispatchQueue.main.async {
                    self.onStateChange?(.connecting)
                }
            case "auth.ok":
                reconnectDelay = 2.0
                DispatchQueue.main.async {
                    self.onStateChange?(.connected)
                }
            case "auth.error":
                shouldReconnect = false
                let error = MessagingServerAPIError.server(frame.error ?? "WebSocket auth failed.")
                DispatchQueue.main.async {
                    self.onError?(error)
                    self.onStateChange?(.disconnected)
                }
                task?.cancel(with: .policyViolation, reason: nil)
                task = nil
            case "event":
                guard let eventType = frame.eventType, let topic = frame.topic, let payload = frame.payload, let createdAt = frame.createdAt, let id = frame.id else {
                    return
                }
                let event = MessagingServerRealtimeEvent(eventType: eventType, topic: topic, payload: payload, createdAt: createdAt, id: id)
                DispatchQueue.main.async {
                    self.onEvent?(event)
                }
            default:
                if let error = frame.error ?? frame.message {
                    DispatchQueue.main.async {
                        self.onError?(MessagingServerAPIError.server(error))
                    }
                }
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
            DispatchQueue.main.async {
                self.onStateChange?(.disconnected)
            }
            return
        }
        DispatchQueue.main.async {
            self.onStateChange?(.reconnecting)
        }
        let nextDelay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 1.5, 8.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + nextDelay) { [weak self] in
            self?.connect()
        }
    }
}
