import Foundation
#if canImport(Darwin)
import Darwin
#endif

let socketPath = "/tmp/agent-island.sock"
let fallback = #"{"decision":"ask"}"#

let inputData = FileHandle.standardInput.readDataToEndOfFile()

var recvTimeout: Int = 45
if let json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any],
   let hookType = json["hook_event_name"] as? String,
   hookType == "PermissionRequest" {
    recvTimeout = 86400
}

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else {
    print(fallback)
    exit(0)
}

var sendTv = timeval(tv_sec: 5, tv_usec: 0)
var recvTv = timeval(tv_sec: recvTimeout, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTv, socklen_t(MemoryLayout<timeval>.size))
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &recvTv, socklen_t(MemoryLayout<timeval>.size))

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
    let buf = UnsafeMutableRawPointer(pathPtr).assumingMemoryBound(to: CChar.self)
    _ = socketPath.withCString { src in
        strncpy(buf, src, MemoryLayout.size(ofValue: addr.sun_path) - 1)
    }
}

let connected = withUnsafePointer(to: &addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
        Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}

guard connected == 0 else {
    close(fd)
    print(fallback)
    exit(0)
}

inputData.withUnsafeBytes { ptr in
    guard let base = ptr.baseAddress else { return }
    _ = send(fd, base, ptr.count, 0)
}
Darwin.shutdown(fd, SHUT_WR)

var response = Data()
var buf = [UInt8](repeating: 0, count: 4096)
while true {
    let n = recv(fd, &buf, buf.count, 0)
    if n <= 0 { break }
    response.append(contentsOf: buf[0..<n])
}
close(fd)

if response.isEmpty {
    print(fallback)
} else {
    FileHandle.standardOutput.write(response)
    FileHandle.standardOutput.write(Data([0x0A]))
}
