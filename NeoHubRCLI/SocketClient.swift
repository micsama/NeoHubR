import Foundation
import NeoHubRLib
import Network
import os

enum SendError: Error, LocalizedError {
    case appIsNotRunning
    case failedToSendRequest(Error)
    case timeout

    var errorDescription: String? {
        switch self {
        case .appIsNotRunning: "NeoHubR app is not running. Start the app and retry."
        case .failedToSendRequest(let e): e.localizedDescription
        case .timeout: "Timed out waiting for IPC response."
        }
    }
}

actor SocketClient {
    private let timeoutNanoseconds: UInt64 = 1_500_000_000 // 1.5s

    func send(_ request: Codable) async -> Result<String?, SendError> {
        guard FileManager.default.fileExists(atPath: Socket.addr) else {
            return .failure(.appIsNotRunning)
        }

        do {
            let json = try IPCCodec.encoder().encode(request)
            let payload = IPCFrame.encode(json)
            let response = try await sendWithTimeout(payload: payload)
            return .success(response)
        } catch {
            return .failure(.failedToSendRequest(error))
        }
    }

    private func sendWithTimeout(payload: Data) async throws -> String? {
        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                try await self.performSend(payload: payload)
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: self.timeoutNanoseconds)
                throw SendError.timeout
            }
            
            let result = try await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }

    private func performSend(payload: Data) async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(to: .unix(path: Socket.addr), using: .tcp)
            let state = OSAllocatedUnfairLock(initialState: false)
            
            @Sendable func resume(_ result: Result<String?, Error>) {
                state.withLock { hasResumed in
                    guard !hasResumed else { return }
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(with: result)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            resume(.failure(error))
                        } else {
                            // Start receiving response
                            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 4) { data, _, isComplete, error in
                                if let error {
                                    resume(.failure(error))
                                    return
                                }
                                if let data, let str = String(data: data, encoding: .utf8) {
                                    resume(.success(str))
                                } else if isComplete {
                                    resume(.success(nil))
                                }
                            }
                        }
                    })
                case .failed(let error):
                    resume(.failure(error))
                case .cancelled:
                    // Only resume if cancelled externally (not by us calling cancel())
                    // But we call cancel() in resume(), so we rely on hasResumed flag
                    break 
                default: break
                }
            }
            
            connection.start(queue: .global())
        }
    }
}