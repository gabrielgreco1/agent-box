import Darwin
import Foundation

// Launcher estavel: o job do launchd fica preso ao cdhash DESTE binario (que nunca muda); ele so faz exec do daemon real.
var size: UInt32 = 0
_NSGetExecutablePath(nil, &size)
var buffer = [CChar](repeating: 0, count: Int(size))
_NSGetExecutablePath(&buffer, &size)
let me = URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
let real = me.deletingLastPathComponent().appendingPathComponent("s01d-real").path
var argv: [UnsafeMutablePointer<CChar>?] = [strdup(real)] + CommandLine.arguments.dropFirst().map { strdup($0) } + [nil]
execv(real, &argv)
perror("exec")
exit(70)
