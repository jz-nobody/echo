import Foundation
#if canImport(Darwin)
import Darwin
#endif

protocol IPCServerDelegate: AnyObject, Sendable {
    func ipcServer(_ server: IPCServer, didReceive message: HookMessage, clientPID: pid_t?, clientID: UUID, respond: @escaping @Sendable (HookResponse) -> Void)
    func ipcServer(_ server: IPCServer, clientDidDisconnect clientID: UUID)
}

final class IPCServer: @unchecked Sendable {
    let tag: String
    private let socketPath: String
    private let queue = DispatchQueue(label: "com.agentisland.ipc", qos: .userInitiated)
    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [UUID: ClientConnection] = [:]
    private var disconnectTimer: DispatchSourceTimer?
    weak var delegate: IPCServerDelegate?

    private struct ClientConnection {
        let id: UUID
        let fileDescriptor: Int32
        let peerPID: pid_t?
        var readSource: DispatchSourceRead?
        var buffer: Data
        var messageDelivered: Bool = false
        var responseCompleted: Bool = false
    }

    init(socketPath: String = IPCProtocol.socketPath, tag: String = "") throws {
        self.socketPath = socketPath
        self.tag = tag
    }

    func start() {
        queue.async { [self] in
            do {
                try setupServer()
            } catch {
                NSLog("[IPCServer] Failed to start: \(error)")
            }
        }
    }

    func stop() {
        queue.async { [self] in
            disconnectTimer?.cancel()
            disconnectTimer = nil
            acceptSource?.cancel()
            acceptSource = nil
            let clientIDs = Array(clients.keys)
            for id in clientIDs {
                removeClient(id)
            }
            if serverFD >= 0 {
                close(serverFD)
                serverFD = -1
            }
            unlink(socketPath)
        }
    }

    private func setupServer() throws {
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IPCError.socketCreationFailed(errno)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathSize = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            let buf = UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self)
            _ = socketPath.withCString { src in
                strncpy(buf, src, pathSize - 1)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw IPCError.bindFailed(errno)
        }

        guard listen(fd, 16) == 0 else {
            close(fd)
            throw IPCError.listenFailed(errno)
        }

        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        serverFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptClient()
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        source.resume()
        acceptSource = source

        NSLog("[IPCServer] Listening on \(socketPath)")
        startDisconnectTimer()
    }

    private func acceptClient() {
        var clientAddr = sockaddr_un()
        var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                accept(serverFD, sa, &addrLen)
            }
        }
        guard clientFD >= 0 else { return }

        var noSigPipe: Int32 = 1
        setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var peerPID: pid_t = 0
        var pidLen = socklen_t(MemoryLayout<pid_t>.size)
        let pidResult = getsockopt(clientFD, SOL_LOCAL, LOCAL_PEERPID, &peerPID, &pidLen)
        let resolvedPID: pid_t? = (pidResult == 0 && peerPID > 0) ? peerPID : nil

        let flags = fcntl(clientFD, F_GETFL)
        _ = fcntl(clientFD, F_SETFL, flags | O_NONBLOCK)

        let clientID = UUID()
        let readSource = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)

        let client = ClientConnection(id: clientID, fileDescriptor: clientFD, peerPID: resolvedPID, readSource: readSource, buffer: Data())
        clients[clientID] = client

        readSource.setEventHandler { [weak self] in
            self?.handleClientData(clientID: clientID)
        }
        readSource.setCancelHandler { }
        readSource.resume()
    }

    private func handleClientData(clientID: UUID) {
        guard var client = clients[clientID] else { return }
        guard client.readSource != nil else { return }

        var buf = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(client.fileDescriptor, &buf, buf.count)

        if bytesRead > 0 {
            client.buffer.append(contentsOf: buf[0..<bytesRead])
            clients[clientID] = client

            if let message = try? IPCProtocol.decodeHookMessage(from: client.buffer) {
                NSLog("[IPCServer] Decoded \(message.type) from client \(clientID) fd=\(client.fileDescriptor)")
                let pid = client.peerPID
                client.readSource?.cancel()
                client.readSource = nil
                client.buffer = Data()
                client.messageDelivered = true
                clients[clientID] = client

                delegate?.ipcServer(self, didReceive: message, clientPID: pid, clientID: clientID) { [weak self] response in
                    NSLog("[IPCServer] Response callback invoked for client \(clientID)")
                    self?.sendResponse(response, toClient: clientID)
                }
            }
            return
        }

        if bytesRead == 0 {
            if !client.buffer.isEmpty, let message = try? IPCProtocol.decodeHookMessage(from: client.buffer) {
                NSLog("[IPCServer] Decoded \(message.type) from client \(clientID) on EOF fd=\(client.fileDescriptor)")
                let pid = client.peerPID
                client.readSource?.cancel()
                client.readSource = nil
                client.messageDelivered = true
                clients[clientID] = client

                delegate?.ipcServer(self, didReceive: message, clientPID: pid, clientID: clientID) { [weak self] response in
                    NSLog("[IPCServer] Response callback invoked for client \(clientID)")
                    self?.sendResponse(response, toClient: clientID)
                }
            } else {
                removeClient(clientID)
            }
            return
        }

        if errno != EAGAIN && errno != EWOULDBLOCK {
            removeClient(clientID)
        }
    }

    private func sendResponse(_ response: HookResponse, toClient clientID: UUID) {
        queue.async { [weak self] in
            guard let self, let client = self.clients[clientID] else {
                NSLog("[IPCServer] Client \(clientID) gone before response could be sent")
                return
            }

            let data: Data
            do {
                data = try IPCProtocol.encode(response)
            } catch {
                NSLog("[IPCServer] Failed to encode response: \(error)")
                self.removeClient(clientID)
                return
            }

            if let json = String(data: data, encoding: .utf8) {
                NSLog("[IPCServer] Response JSON: \(json.prefix(500))")
            }

            NSLog("[IPCServer] Writing \(data.count) bytes to client \(clientID) fd=\(client.fileDescriptor)")

            var writeError = false
            data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                var remaining = rawBuffer.count
                var offset = 0
                while remaining > 0 {
                    let written = write(client.fileDescriptor, base + offset, remaining)
                    if written > 0 {
                        offset += written
                        remaining -= written
                    } else if written == -1 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                        usleep(1_000)
                    } else {
                        NSLog("[IPCServer] Write failed: errno=\(errno)")
                        writeError = true
                        break
                    }
                }
            }

            if !writeError {
                NSLog("[IPCServer] Response sent successfully to client \(clientID)")
                self.clients[clientID]?.responseCompleted = true
            }

            self.removeClient(clientID)
        }
    }

    private func startDisconnectTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.checkForDisconnectedClients()
        }
        timer.resume()
        disconnectTimer = timer
    }

    private func checkForDisconnectedClients() {
        for (clientID, client) in clients where client.messageDelivered && !client.responseCompleted {
            var pfd = pollfd(fd: client.fileDescriptor, events: 0, revents: 0)
            let result = poll(&pfd, 1, 0)
            NSLog("[IPCServer] Poll client \(clientID) fd=\(client.fileDescriptor): result=\(result) revents=\(pfd.revents)")
            if result > 0 && (pfd.revents & Int16(POLLHUP | POLLERR)) != 0 {
                NSLog("[IPCServer] Peer disconnected for client \(clientID)")
                removeClient(clientID)
            }
        }
    }

    private func removeClient(_ clientID: UUID) {
        guard let client = clients.removeValue(forKey: clientID) else { return }
        client.readSource?.cancel()
        close(client.fileDescriptor)
        if client.messageDelivered && !client.responseCompleted {
            delegate?.ipcServer(self, clientDidDisconnect: clientID)
        }
    }

    enum IPCError: Error {
        case socketCreationFailed(Int32)
        case bindFailed(Int32)
        case listenFailed(Int32)
    }
}
