import Foundation
import NeoHubLib
import Network

enum SendError: Error {
    case appIsNotRunning
    case failedToSendRequest(Error)
}

extension SendError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .appIsNotRunning:
            return "NeoHub app is not running. Start the app and retry."
        case .failedToSendRequest(let error):
            return error.localizedDescription
        }
    }
}

class SocketClient {
    private let queue = DispatchQueue(label: "neohub.ipc.client")
    private let timeoutSeconds: TimeInterval = 1.5
    private let maxAttempts = 2
    private static let timeoutDomain = "NeoHubIPC"

    func send(_ request: Codable) -> Result<String?, SendError> {
        if !FileManager.default.fileExists(atPath: Socket.addr) {
            return .failure(.appIsNotRunning)
        }

        do {
            let encoder = JSONEncoder()
            let json = try encoder.encode(request)
            let payload = encodeFrame(json)

            for attempt in 0..<maxAttempts {
                let result = sendOnce(payload: payload, timeout: timeoutSeconds)
                switch result {
                case .success(let response):
                    return .success(response)
                case .failure(let error):
                    if attempt == maxAttempts - 1 {
                        return .failure(.failedToSendRequest(error))
                    }
                }
            }

            return .failure(.failedToSendRequest(Self.timeoutError()))
        } catch {
            return .failure(.failedToSendRequest(error))
        }
    }

    private func sendOnce(payload: Data, timeout: TimeInterval) -> Result<String?, Error> {
        let connection = NWConnection(to: .unix(path: Socket.addr), using: .tcp)
        let context = SendContext(connection: connection)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(
                    content: payload,
                    completion: .contentProcessed { error in
                        if let error {
                            context.finish(.failure(error))
                            return
                        }
                        Self.receiveResponse(context: context)
                    })
            case .failed(let error):
                context.finish(.failure(error))
            case .cancelled:
                if !context.hasResult {
                    context.finish(.failure(Self.timeoutError()))
                }
            default:
                break
            }
        }

        connection.start(queue: queue)
        let waitResult = context.semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            if !context.hasResult {
                context.setResultIfNil(.failure(Self.timeoutError()))
            }
            connection.cancel()
        }
        return context.result ?? .failure(Self.timeoutError())
    }

    private static func receiveResponse(context: SendContext) {
        @Sendable func receiveNext() {
            context.connection.receive(minimumIncompleteLength: 1, maximumLength: 4 * 1024) {
                data, _, isComplete, error in
                if let data {
                    context.appendResponse(data)
                }

                if let error {
                    context.finish(.failure(error))
                    return
                }

                if isComplete || context.hasResponseData {
                    let response = context.responseString
                    context.finish(.success(response))
                    return
                }

                receiveNext()
            }
        }

        receiveNext()
    }

    private func encodeFrame(_ json: Data) -> Data {
        let length = UInt32(json.count)
        var header = Data(capacity: 4)
        for shift in stride(from: 24, through: 0, by: -8) {
            header.append(UInt8((length >> UInt32(shift)) & 0xFF))
        }
        var payload = Data()
        payload.append(header)
        payload.append(json)
        return payload
    }

    private static func timeoutError() -> NSError {
        NSError(
            domain: timeoutDomain, code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Timed out waiting for IPC response."
            ])
    }
}

private final class SendContext: @unchecked Sendable {
    let connection: NWConnection
    let semaphore = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var _result: Result<String?, Error>?
    private var responseData = Data()

    init(connection: NWConnection) {
        self.connection = connection
    }

    var result: Result<String?, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return _result
    }

    var hasResult: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _result != nil
    }

    var hasResponseData: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !responseData.isEmpty
    }

    var responseString: String? {
        lock.lock()
        defer { lock.unlock() }
        return responseData.isEmpty ? nil : String(data: responseData, encoding: .utf8)
    }

    func setResultIfNil(_ value: Result<String?, Error>) {
        lock.lock()
        if _result == nil {
            _result = value
        }
        lock.unlock()
    }

    func finish(_ value: Result<String?, Error>) {
        lock.lock()
        if _result != nil {
            lock.unlock()
            return
        }
        _result = value
        lock.unlock()
        connection.cancel()
        semaphore.signal()
    }

    func appendResponse(_ data: Data) {
        lock.lock()
        responseData.append(data)
        lock.unlock()
    }
}
