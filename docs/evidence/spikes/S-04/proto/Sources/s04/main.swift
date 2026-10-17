import Foundation
let a = CommandLine.arguments
if a.count > 1 && a[1] == "daemon" {
    // s04 daemon <sock> <cols> <rows> <ringBytes> <cwd> <argv...>
    runDaemon(sock: a[2], cols: Int(a[3])!, rows: Int(a[4])!, ringBytes: Int(a[5])!, cwd: a[6], argv: Array(a[7...]))
} else if a.count > 1 && a[1] == "harness" {
    // s04 harness <workdir> [reps] [scenario]
    runHarness(exe: a[0], work: a[2], reps: a.count > 3 ? Int(a[3])! : 20, only: a.count > 4 ? a[4] : nil)
} else { print("usage: s04 daemon ... | s04 harness <workdir> [reps] [scenario]") }
