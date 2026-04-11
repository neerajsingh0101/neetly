import Foundation

class SocketServer {
    let socketPath: String
    private var serverFd: Int32 = -1
    var onCommand: ((SocketCommand) -> Void)?

    init() {
        let pid = ProcessInfo.processInfo.processIdentifier
        socketPath = "/tmp/neetly1-\(pid).sock"
    }

    func start() {
        // Remove stale socket
        unlink(socketPath)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            NSLog("SocketServer: failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathSize = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                let buf = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                strncpy(buf, cstr, pathSize)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            NSLog("SocketServer: bind failed: \(String(cString: strerror(errno)))")
            return
        }

        guard listen(serverFd, 5) == 0 else {
            NSLog("SocketServer: listen failed")
            return
        }

        NSLog("SocketServer: listening on \(socketPath)")

        // Accept loop on background thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let self = self, self.serverFd >= 0 {
                let clientFd = accept(self.serverFd, nil, nil)
                guard clientFd >= 0 else { break }
                self.handleClient(clientFd)
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            data.append(contentsOf: buffer[0..<bytesRead])
            if bytesRead < buffer.count { break }
        }

        guard !data.isEmpty else { return }

        do {
            let command = try JSONDecoder().decode(SocketCommand.self, from: data)
            DispatchQueue.main.async { [weak self] in
                self?.onCommand?(command)
            }
        } catch {
            NSLog("SocketServer: failed to decode command: \(error)")
        }
    }

    func environmentForPane(_ paneId: UUID) -> [String: String] {
        [
            "NEETLY_SOCKET": socketPath,
            "NEETLY_PANE_ID": paneId.uuidString,
        ]
    }

    func stop() {
        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }
        unlink(socketPath)
    }

    deinit {
        stop()
    }
}
