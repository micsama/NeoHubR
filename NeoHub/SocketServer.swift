import Foundation
import NeoHubLib
import Network

final class SocketServer: @unchecked Sendable {
    let store: EditorStore

    private let queue = DispatchQueue(label: "neohub.ipc.server")
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
                        FailedToLaunchServerNotification(error: report).send()
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
                FailedToLaunchServerNotification(error: error).send()
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
    private var didHandle = false
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
                log.trace("IPC connection ready")
                self.receiveNext()
            case .failed(let error):
                log.error("IPC connection failed: \(error)")
                self.connection.cancel()
                self.onFinish?()
            case .cancelled:
                log.trace("IPC connection cancelled")
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
                log.trace("Incoming data from the CLI")
                self.buffer.append(data)
            }

            if let error {
                log.error("IPC receive error: \(error)")
                self.connection.cancel()
                self.onFinish?()
                return
            }

            while let frame = self.nextFrame() {
                self.handleRequest(frame: frame)
                if self.didHandle {
                    return
                }
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
            guard buffer.count >= 4 else { return nil }
            let length = readLength(from: buffer.prefix(4))
            expectedLength = length
            buffer.removeFirst(4)
        }

        guard let length = expectedLength, buffer.count >= length else { return nil }
        let frame = buffer.prefix(length)
        buffer.removeFirst(length)
        expectedLength = nil
        return Data(frame)
    }

    private func readLength(from data: Data) -> Int {
        var length: UInt32 = 0
        for byte in data {
            length = (length << 8) | UInt32(byte)
        }
        return Int(length)
    }

    private func handleRequest(frame: Data) {
        do {
            log.trace("Decoding incoming JSON...")

            let decoder = JSONDecoder()
            let req = try decoder.decode(RunRequest.self, from: frame)

            log.debug(
                """

                ====================== INCOMING REQUEST ======================
                wd: \(req.wd)
                bin: \(req.bin)
                name: \(req.name ?? "-")
                path: \(req.path ?? "-")
                opts: \(req.opts)
                """
            )
            log.trace("env: \(req.env)")
            log.debug(
                """

                ================== END OF INCOMING REQUEST ===================
                """
            )

            Task {
                await self.store.runEditor(request: req)
            }
        } catch {
            let report = ReportableError("Failed to decode request from the CLI", error: error)
            log.error("\(report)")
            FailedToHandleRequestFromCLINotification(error: report).send()
        }

        didHandle = true
        sendResponse("OK")
    }

    private func sendResponse(_ response: String) {
        let data = Data(response.utf8)
        connection.send(
            content: data,
            completion: .contentProcessed { [weak self] error in
                if let error {
                    log.error("IPC send error: \(error)")
                } else {
                    log.trace("Response sent")
                }
                self?.connection.cancel()
                self?.onFinish?()
            })
    }
}
