import Foundation
import Network

protocol IPCServerDelegate: AnyObject, Sendable {
    func ipcServer(_ server: IPCServer, didReceive message: HookMessage, respond: @escaping @Sendable (HookResponse) -> Void)
}

final class IPCServer: Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.agentisland.ipc", qos: .userInitiated)
    nonisolated(unsafe) weak var delegate: IPCServerDelegate?

    init(socketPath: String = IPCProtocol.socketPath) throws {
        try? FileManager.default.removeItem(atPath: socketPath)
        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)
        listener = try NWListener(using: params)
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                NSLog("[IPCServer] Listener failed: \(error)")
                self?.listener.cancel()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveMessage(on: connection)
    }

    private func receiveMessage(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, let data, !data.isEmpty else {
                if isComplete || error != nil {
                    connection.cancel()
                }
                return
            }

            guard let message = try? IPCProtocol.decodeHookMessage(from: data) else {
                let fallback = HookResponse(decision: "ask", reason: "Failed to parse message")
                self.sendResponse(fallback, on: connection)
                return
            }

            self.delegate?.ipcServer(self, didReceive: message) { response in
                self.sendResponse(response, on: connection)
            }
        }
    }

    private func sendResponse(_ response: HookResponse, on connection: NWConnection) {
        guard let data = try? IPCProtocol.encode(response) else {
            connection.cancel()
            return
        }
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
