import Foundation
import Network

struct NeovideIPCWindow: Decodable, Equatable {
    let windowID: String
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case windowID = "window_id"
        case isActive = "is_active"
    }
}

enum NeovideIPCError: Error {
    case invalidResponse
    case serverError(code: Int, message: String)
    case connectionFailed
    case noWindowsAvailable
}

actor NeovideIPCClient {
    static let shared = NeovideIPCClient()

    private let queue = DispatchQueue(label: "neohubr.neovide.ipc")
    private var nextID: Int = 1

    func createWindow(nvimArgs: [String], socketPath: String) async throws -> String {
        struct Params: Encodable { let nvim_args: [String] }
        struct Result: Decodable { let window_id: String }
        let response: Result = try await send(method: "CreateWindow", params: Params(nvim_args: nvimArgs), socketPath: socketPath)
        return response.window_id
    }

    func listWindows(socketPath: String) async throws -> [NeovideIPCWindow] {
        struct Params: Encodable {}
        let response: [NeovideIPCWindow] = try await send(method: "ListWindows", params: Params(), socketPath: socketPath)
        return response
    }

    func activateWindow(_ windowID: String, socketPath: String) async throws -> Bool {
        struct Params: Encodable { let window_id: String }
        struct Result: Decodable { let ok: Bool }
        let response: Result = try await send(method: "ActivateWindow", params: Params(window_id: windowID), socketPath: socketPath)
        return response.ok
    }

    private func send<Params: Encodable, Result: Decodable>(
        method: String,
        params: Params,
        socketPath: String
    ) async throws -> Result {
        let id = nextID
        nextID += 1

        let request = JSONRPCRequest(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(request)
        let responseData = try await sendRaw(data, socketPath: socketPath)
        let response = try JSONDecoder().decode(JSONRPCResponse<Result>.self, from: responseData)

        if let error = response.error {
            throw NeovideIPCError.serverError(code: error.code, message: error.message)
        }

        guard let result = response.result else { throw NeovideIPCError.invalidResponse }
        return result
    }

    private func sendRaw(_ data: Data, socketPath: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let parameters = NWParameters.tcp
            let connection = NWConnection(to: .unix(path: socketPath), using: parameters)

            final class RequestState: @unchecked Sendable {
                let connection: NWConnection
                let continuation: CheckedContinuation<Data, Error>
                var received = Data()
                var finished = false

                init(connection: NWConnection, continuation: CheckedContinuation<Data, Error>) {
                    self.connection = connection
                    self.continuation = continuation
                }
            }

            let state = RequestState(connection: connection, continuation: continuation)

            let finish: @Sendable (Result<Data, Error>) -> Void = { result in
                guard !state.finished else { return }
                state.finished = true
                state.connection.cancel()
                switch result {
                case .success(let data):
                    state.continuation.resume(returning: data)
                case .failure(let error):
                    state.continuation.resume(throwing: error)
                }
            }

            var receiveNext: (@Sendable () -> Void)!
            receiveNext = {
                state.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                    data, _, isComplete, error in
                    if let data { state.received.append(data) }
                    if let error {
                        finish(.failure(error))
                        return
                    }

                    // Check for newline (Neovide sends \n terminated JSON)
                    if state.received.contains(0x0A) {
                        finish(.success(state.received))
                        return
                    }

                    if isComplete {
                        guard !state.received.isEmpty else {
                            finish(.failure(NeovideIPCError.invalidResponse))
                            return
                        }
                        finish(.success(state.received))
                        return
                    }
                    receiveNext()
                }
            }

            connection.stateUpdateHandler = { stateUpdate in
                switch stateUpdate {
                case .ready:
                    var payload = data
                    payload.append(0x0A)
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(error))
                            return
                        }
                        receiveNext()
                    })
                case .failed:
                    finish(.failure(NeovideIPCError.connectionFailed))
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }
}

private struct JSONRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: Params
}

private struct JSONRPCResponse<Result: Decodable>: Decodable {
    let jsonrpc: String
    let id: Int
    let result: Result?
    let error: JSONRPCError?
}

private struct JSONRPCError: Decodable {
    let code: Int
    let message: String
}
