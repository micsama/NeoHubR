import Foundation
import Network

enum NeovideIPCError: Error {
    case timeout
    case invalidResponse
    case serverError(String)
}

enum NeovideIPCClient {
    enum Config {
        static let listTimeout: TimeInterval = 0.05
        static let createTimeout: TimeInterval = 0.4
        static let activateTimeout: TimeInterval = 1.0
        static let waitPollInterval: TimeInterval = 0.05
        static let waitPollTimeout: TimeInterval = 1.0
        static let waitInitialDelayNanos: UInt64 = 500_000_000
    }

    static let socketPath = "/tmp/neovide.sock"
    fileprivate static let queue = DispatchQueue(label: "neohubr.neovide.ipc")
    private static let inFlightStore = InFlightStore()

    static func listWindows() async throws -> [String] {
        try await listWindows(timeout: Config.listTimeout)
    }

    static func listWindows(timeout: TimeInterval) async throws -> [String] {
        let response = try await sendRequest(
            method: "ListWindows",
            params: nil,
            timeout: timeout
        )
        return try parseWindowIDs(from: response)
    }

    static func activateWindow(id: String) async throws {
        try await activateWindow(id: id, timeout: Config.activateTimeout)
    }

    static func activateWindow(id: String, timeout: TimeInterval) async throws {
        _ = try await sendRequest(
            method: "ActivateWindow",
            params: ["window_id": id],
            timeout: timeout
        )
    }

    static func createWindow(nvimArgs: [String]) async throws -> String? {
        try await createWindow(nvimArgs: nvimArgs, timeout: Config.createTimeout)
    }

    static func createWindow(nvimArgs: [String], timeout: TimeInterval) async throws -> String? {
        let response = try await sendRequest(
            method: "CreateWindow",
            params: ["nvim_args": nvimArgs],
            timeout: timeout
        )
        return try parseSingleWindowID(from: response)
    }

    static func waitForNewWindowID(existingIDs: Set<String>) async throws -> String? {
        try await waitForNewWindowID(
            existingIDs: existingIDs,
            timeout: Config.waitPollTimeout,
            pollInterval: Config.waitPollInterval
        )
    }

    static func waitForNewWindowID(
        existingIDs: Set<String>,
        timeout: TimeInterval,
        pollInterval: TimeInterval
    ) async throws -> String? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            do {
                let ids = try await listWindows(timeout: pollInterval)
                if let newID = ids.first(where: { !existingIDs.contains($0) }) {
                    return newID
                }
            } catch let error as NeovideIPCError {
                if case .timeout = error {
                    // IPC may not be ready yet; keep polling until deadline.
                } else {
                    throw error
                }
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        return nil
    }

    private static func sendRequest(
        method: String,
        params: [String: Any]?,
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": params ?? [:],
        ]

        let payload = try JSONSerialization.data(withJSONObject: request, options: [])
        let data = try await sendRequest(payload: payload, timeout: timeout)
        return try parseResponse(data)
    }

    private static func sendRequest(payload: Data, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
            let handler = ResponseHandler(connection: connection, continuation: continuation, timeout: timeout)
            register(handler)
            handler.start(payload: payload)
        }
    }

    private static func parseResponse(_ data: Data) throws -> [String: Any] {
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = object as? [String: Any] else {
                throw NeovideIPCError.invalidResponse
            }
            if let error = dict["error"] as? [String: Any] {
                let message = (error["message"] as? String) ?? "Unknown IPC error"
                throw NeovideIPCError.serverError(message)
            }
            return dict
        } catch {
            throw error
        }
    }

    private static func parseWindowIDs(from response: [String: Any]) throws -> [String] {
        guard let result = response["result"] else {
            throw NeovideIPCError.invalidResponse
        }
        guard let ids = extractWindowIDs(from: result) else {
            throw NeovideIPCError.invalidResponse
        }
        return ids
    }

    private static func parseSingleWindowID(from response: [String: Any]) throws -> String? {
        guard let result = response["result"] else {
            throw NeovideIPCError.invalidResponse
        }
        return extractWindowIDs(from: result)?.first
    }

    private static func extractWindowIDs(from result: Any) -> [String]? {
        if let ids = result as? [String] {
            return ids
        }
        if let array = result as? [Any] {
            let ids = array.compactMap { extractWindowID(from: $0) }
            return ids
        }
        if let dict = result as? [String: Any] {
            if let windows = dict["windows"] {
                return extractWindowIDs(from: windows)
            }
            if let id = extractWindowID(from: dict) {
                return [id]
            }
        }
        return nil
    }

    private static func extractWindowID(from value: Any) -> String? {
        if let id = value as? String { return id }
        if let dict = value as? [String: Any] {
            if let id = dict["window_id"] as? String { return id }
            if let id = dict["id"] as? String { return id }
            if let id = dict["windowId"] as? String { return id }
        }
        return nil
    }

    fileprivate static func register(_ handler: ResponseHandler) {
        Task { await inFlightStore.register(handler) }
    }

    fileprivate static func unregister(_ handler: ResponseHandler) {
        Task { await inFlightStore.unregister(handler) }
    }
}

// MARK: - In-Flight Store

private actor InFlightStore {
    private var items: [UUID: ResponseHandler] = [:]

    func register(_ handler: ResponseHandler) {
        items[handler.id] = handler
    }

    func unregister(_ handler: ResponseHandler) {
        items.removeValue(forKey: handler.id)
    }
}

// MARK: - Internal Response Handler

private final class ResponseHandler: @unchecked Sendable {
    let id = UUID()
    private let connection: NWConnection
    private let continuation: CheckedContinuation<Data, Error>
    private let timeout: TimeInterval
    private var buffer = Data()
    private var didFinish = false
    private var timeoutTimer: DispatchSourceTimer?

    init(
        connection: NWConnection,
        continuation: CheckedContinuation<Data, Error>,
        timeout: TimeInterval
    ) {
        self.connection = connection
        self.continuation = continuation
        self.timeout = timeout
    }

    func start(payload: Data) {
        scheduleTimeout()
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleState(state, payload: payload)
        }
        connection.start(queue: NeovideIPCClient.queue)
    }

    private func handleState(_ state: NWConnection.State, payload: Data) {
        switch state {
        case .ready:
            var framed = payload
            framed.append(0x0A)
            connection.send(content: framed, completion: .contentProcessed { [weak self] error in
                if let error {
                    log.warning("IPC send error: \(error)")
                    self?.finish(.failure(error))
                    return
                }
                self?.receive()
            })
        case .failed(let error):
            log.warning("IPC connection failed: \(error)")
            finish(.failure(error))
        case .cancelled:
            finish(.failure(NeovideIPCError.invalidResponse))
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                log.warning("IPC receive error: \(error)")
                self.finish(.failure(error))
                return
            }

            if let data { self.buffer.append(data) }

            if let newlineRange = self.buffer.firstRange(of: Data([0x0A])) {
                let frame = self.buffer.prefix(upTo: newlineRange.lowerBound)
                self.finish(.success(Data(frame)))
                return
            }

            if isComplete {
                self.finish(.success(self.buffer))
                return
            }

            self.receive()
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard !didFinish else { return }
        didFinish = true
        timeoutTimer?.cancel()
        timeoutTimer = nil
        connection.cancel()
        NeovideIPCClient.unregister(self)
        continuation.resume(with: result)
    }

    private func scheduleTimeout() {
        guard timeout > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: NeovideIPCClient.queue)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in
            self?.finish(.failure(NeovideIPCError.timeout))
        }
        timer.resume()
        timeoutTimer = timer
    }
}
