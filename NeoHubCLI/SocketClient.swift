import Foundation
import Network
import NeoHubLib

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

            return .failure(.failedToSendRequest(timeoutError()))
        } catch {
            return .failure(.failedToSendRequest(error))
        }
    }

    private func sendOnce(payload: Data, timeout: TimeInterval) -> Result<String?, Error> {
        let connection = NWConnection(to: .unix(path: Socket.addr), using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<String?, Error>?

        func finish(_ value: Result<String?, Error>) {
            if result != nil {
                return
            }
            result = value
            connection.cancel()
            semaphore.signal()
        }

        connection.stateUpdateHandler = { state in
            switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(error))
                            return
                        }
                        self.receiveResponse(connection: connection, finish: finish)
                    })
                case .failed(let error):
                    finish(.failure(error))
                case .cancelled:
                    if result == nil {
                        finish(.failure(self.timeoutError()))
                    }
                default:
                    break
            }
        }

        connection.start(queue: queue)
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            if result == nil {
                result = .failure(timeoutError())
            }
            connection.cancel()
        }
        return result ?? .failure(timeoutError())
    }

    private func receiveResponse(
        connection: NWConnection,
        finish: @escaping (Result<String?, Error>) -> Void
    ) {
        var responseData = Data()

        func receiveNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4 * 1024) { data, _, isComplete, error in
                if let data {
                    responseData.append(data)
                }

                if let error {
                    finish(.failure(error))
                    return
                }

                if isComplete || !responseData.isEmpty {
                    let response = responseData.isEmpty ? nil : String(data: responseData, encoding: .utf8)
                    finish(.success(response))
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

    private func timeoutError() -> NSError {
        NSError(domain: "NeoHubIPC", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Timed out waiting for IPC response."
        ])
    }
}
