import Foundation

protocol GeminiSocket: Sendable {
    func open(_ url: URL) async throws
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close()
}

/// Apple uses the platform WebSocket and its system TLS trust evaluation.
final class URLSessionGeminiSocket: GeminiSocket, @unchecked Sendable {
    private let lock = NSLock()
    private let session = URLSession(configuration: .ephemeral)
    private var task: URLSessionWebSocketTask?
    private var closed = false

    func open(_ url: URL) async throws {
        let socket = session.webSocketTask(with: url)
        socket.maximumMessageSize = 1024 * 1024
        guard store(socket) else { socket.cancel(); throw ConversationError.closed }
        socket.resume()
    }
    func send(_ text: String) async throws {
        guard let socket = current() else { throw ConversationError.closed }
        do { try await withTaskCancellationHandler { try await socket.send(.string(text)) } onCancel: { self.close() } }
        catch { throw ConversationError.connection } // Do not expose authenticated URLs in NSError messages.
    }
    func receive() async throws -> String {
        guard let socket = current() else { throw ConversationError.closed }
        let message: URLSessionWebSocketTask.Message
        do { message = try await withTaskCancellationHandler { try await socket.receive() } onCancel: { self.close() } }
        catch { throw ConversationError.connection }
        switch message {
        case .string(let text): return text
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else { throw ConversationError.protocolMessage }
            return text
        @unknown default: throw ConversationError.protocolMessage
        }
    }
    func close() {
        lock.lock()
        closed = true
        let socket = task
        task = nil
        lock.unlock()
        socket?.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
    private func store(_ socket: URLSessionWebSocketTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed && task == nil else { return false }
        task = socket
        return true
    }
    private func current() -> URLSessionWebSocketTask? {
        lock.lock(); defer { lock.unlock() }
        return task
    }
    deinit { close() }
}
