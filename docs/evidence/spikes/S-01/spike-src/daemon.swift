import Darwin
import Foundation

// Daemon de spike: ativa o socket do launchd via launch_activate_socket (dlsym), registra tudo em $LOG e atende uma conexao.
let logPath = ProcessInfo.processInfo.environment["S01_LOG"] ?? "/tmp/s01-daemon.log"
func log(_ s: String) {
    let line = "\(Date()) pid=\(getpid()) \(s)\n"
    if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { FileManager.default.createFile(atPath: logPath, contents: Data(line.utf8)) }
}
typealias Activate = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<UnsafeMutablePointer<Int32>?>, UnsafeMutablePointer<Int>) -> Int32
log("start v29072 argv=\(CommandLine.arguments) env AGENTBOX_PTYD_SOCK_V1=\(ProcessInfo.processInfo.environment["AGENTBOX_PTYD_SOCK_V1"] ?? "<unset>") S01_SOCK=\(ProcessInfo.processInfo.environment["S01_SOCK"] ?? "<unset>")")
guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "launch_activate_socket") else { log("dlsym failed"); exit(2) }
let activate = unsafeBitCast(sym, to: Activate.self)
var fds: UnsafeMutablePointer<Int32>? = nil
var count = 0
let rc = activate("Listeners", &fds, &count)
log("launch_activate_socket rc=\(rc) count=\(count)")
guard rc == 0, count > 0, let fds else { exit(3) }
let fd = fds[0]
var addr = sockaddr_un(); var len = socklen_t(MemoryLayout<sockaddr_un>.size)
withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(fd, $0, &len) } }
let path = withUnsafePointer(to: &addr.sun_path) { $0.withMemoryRebound(to: CChar.self, capacity: 104) { String(cString: $0) } }
log("fd=\(fd) sockname=\(path)")
let idle = Int(ProcessInfo.processInfo.environment["S01_IDLE"] ?? "20") ?? 20
var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
while true {
    let n = poll(&pfd, 1, Int32(idle * 1000))
    if n <= 0 { log("idle exit"); exit(0) }
    let c = accept(fd, nil, nil)
    if c < 0 { continue }
    var uid: uid_t = 0, gid: gid_t = 0
    getpeereid(c, &uid, &gid)
    log("accepted conn peer uid=\(uid)")
    let msg = "hello from daemon pid \(getpid())\n"
    _ = msg.withCString { write(c, $0, strlen($0)) }
    close(c)
}
// 2740325271
