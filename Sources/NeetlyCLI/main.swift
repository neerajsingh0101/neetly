import Foundation

// neetly CLI — companion tool for neetly1
//
// Usage:
//   neetly visit <url>       — open a browser tab in the current pane
//   neetly run <command>     — open a terminal tab running <command>

let env = ProcessInfo.processInfo.environment

guard let socketPath = env["NEETLY_SOCKET"] else {
    fputs("Error: NEETLY_SOCKET not set. Are you running inside neetly1?\n", stderr)
    exit(1)
}

let paneId = env["NEETLY_PANE_ID"] ?? ""
let args = CommandLine.arguments

guard args.count >= 3 else {
    fputs("Usage: neetly <visit|run> <url|command>\n", stderr)
    fputs("\nCommands:\n", stderr)
    fputs("  visit <url>       Open a browser tab with the given URL\n", stderr)
    fputs("  run <command>     Open a terminal tab running the command\n", stderr)
    exit(1)
}

let action = args[1]
let target = args[2...].joined(separator: " ")

var payload: [String: Any] = ["paneId": paneId]

switch action {
case "visit":
    payload["action"] = "browser.open"
    payload["url"] = target
case "run":
    payload["action"] = "terminal.run"
    payload["command"] = target
default:
    fputs("Unknown action: \(action). Use 'visit' or 'run'.\n", stderr)
    exit(1)
}

// Serialize to JSON
guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
    fputs("Error: failed to serialize command\n", stderr)
    exit(1)
}

// Connect to Unix domain socket
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else {
    fputs("Error: could not create socket\n", stderr)
    exit(1)
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

let connectResult = withUnsafePointer(to: &addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}

guard connectResult == 0 else {
    fputs("Error: could not connect to neetly1 at \(socketPath)\n", stderr)
    fputs("       \(String(cString: strerror(errno)))\n", stderr)
    close(fd)
    exit(1)
}

data.withUnsafeBytes { bytes in
    _ = write(fd, bytes.baseAddress!, data.count)
}
close(fd)
