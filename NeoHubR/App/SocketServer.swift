import Foundation
import NeoHubRLib
import Network

final class SocketServer: @unchecked Sendable {
    let store: EditorStore

    private let queue = DispatchQueue(label: "neohubr.ipc.server")
    private var listener: NWListener?
    private var handlers: [ObjectIdentifier: ConnectionHandler] = [:]

    init(store: EditorStore) {
        self.store = store
    }

    func start() {
        queue.async {
            do {
                if FileManager.default.fileExists(atPath: Socket.addr) {
                    log.warning("Socket \(Socket.addr) exists. Removing it.")
                    try? FileManager.default.removeItem(atPath: Socket.addr)
                }

                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                parameters.requiredLocalEndpoint = .unix(path: Socket.addr)
                let listener = try NWListener(using: parameters)

                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        log.info("Bound to the \(Socket.addr) socket")
                    case .failed(let error):
                        let report = ReportableError("Failed to start the socket server", error: error)
                        log.critical("\(report)")
                        NotificationManager.send(kind: .failedToLaunchServer, error: report)
                    default:
                        break
                    }
                }

                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { return }
                    let handler = ConnectionHandler(store: self.store, connection: connection, queue: self.queue)
                    let id = ObjectIdentifier(handler)
                    self.handlers[id] = handler
                    handler.onFinish = { [weak self] in
                        self?.handlers.removeValue(forKey: id)
                    }
                    handler.start()
                }

                self.listener = listener
                listener.start(queue: self.queue)
            } catch {
                let error = ReportableError("Failed to start the socket server", error: error)
                log.critical("\(error)")
                NotificationManager.send(kind: .failedToLaunchServer, error: error)
            }
        }
    }

    func stop() {
        queue.async {
            log.info("Stopping the socket server...")
            self.listener?.cancel()
            self.listener = nil
            self.handlers.removeAll()
            log.info("Socket server successfully stopped")
            if FileManager.default.fileExists(atPath: Socket.addr) {
                log.warning("The socket at \(Socket.addr) still exists. Removing it.")
                try? FileManager.default.removeItem(atPath: Socket.addr)
                log.info("Socket at \(Socket.addr) is removed")
            }
        }
    }
}

private final class ConnectionHandler: @unchecked Sendable {
    private let store: EditorStore
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private var expectedLength: Int?
    var onFinish: (() -> Void)?

    init(store: EditorStore, connection: NWConnection, queue: DispatchQueue) {
        self.store = store
        self.connection = connection
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.receiveNext()
            case .failed(let error):
                log.error("IPC connection failed: \(error)")
                self.connection.cancel()
                self.onFinish?()
            case .cancelled:
                self.onFinish?()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.buffer.append(data)
            }

            if let error {
                log.error("IPC receive error: \(error)")
                self.connection.cancel()
                self.onFinish?()
                return
            }

            // Single-frame per connection: process first frame, then reply+close.
            if let frame = self.nextFrame() {
                self.handleRequest(frame: frame)
                return
            }

            if isComplete {
                self.connection.cancel()
                self.onFinish?()
                return
            }

            self.receiveNext()
        }
    }

    private func nextFrame() -> Data? {
        if expectedLength == nil {
            guard buffer.count >= IPCFrame.headerSize else { return nil }
            let header = Data(buffer.prefix(IPCFrame.headerSize))
            let length = IPCFrame.readLength(from: header)
            expectedLength = length
            buffer.removeFirst(IPCFrame.headerSize)
        }

        guard let length = expectedLength, buffer.count >= length else { return nil }
        let frame = buffer.prefix(length)
        buffer.removeFirst(length)
        expectedLength = nil
        return Data(frame)
    }

    private func handleRequest(frame: Data) {
        do {
            let message = try IPCCodec.decoder().decode(IPCMessage.self, from: frame)
            switch message.type {
            case .run:
                if let req = message.run {
                    self.handleRunRequest(req)
                } else {
                    throw ReportableError("Missing run payload in IPC message")
                }
            case .cliError:
                if let report = message.cliError {
                    NotificationManager.sendCLIError(report)
                } else {
                    throw ReportableError("Missing cliError payload in IPC message")
                }
            }
        } catch {
            let report = ReportableError("Failed to decode request from the CLI", error: error)
            log.error("\(report)")
            NotificationManager.send(kind: .failedToHandleRequestFromCLI, error: report)
        }

        sendResponse("OK")
    }

    private func handleRunRequest(_ req: RunRequest) {
        MainThread.run { [store] in
            store.runEditor(request: req)
        }
    }

    private func sendResponse(_ response: String) {
        let data = Data(response.utf8)
        connection.send(
            content: data,
            completion: .contentProcessed { [weak self] error in
                if let error {
                    log.error("IPC send error: \(error)")
                }
                self?.connection.cancel()
                self?.onFinish?()
            })
    }
}
