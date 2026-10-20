import Foundation
import ServiceManagement

// App de spike (bundle app.racky.s01test): registra/consulta/desregistra o LaunchAgent de teste.
let suffix = ProcessInfo.processInfo.environment["S01_SUF"] ?? (Bundle.main.bundleIdentifier ?? "").replacingOccurrences(of: "app.racky.s01test", with: ""); let plist = "app.racky.ptyd.test-s01\(suffix).plist"
let svc = SMAppService.agent(plistName: plist)
func name(_ s: SMAppService.Status) -> String {
    switch s { case .notRegistered: "notRegistered"; case .enabled: "enabled"; case .requiresApproval: "requiresApproval"; case .notFound: "notFound"; @unknown default: "unknown" }
}
let cmd = CommandLine.arguments.dropFirst().first ?? "status"
print("before: \(name(svc.status))")
switch cmd {
case "register":
    do { try svc.register(); print("register: ok") } catch { print("register: error \(error)") }
case "unregister":
    do { try svc.unregister(); print("unregister: ok") } catch { print("unregister: error \(error)") }
case "reregister":
    do { try svc.unregister(); print("unregister: ok") } catch { print("unregister: error \(error)") }
    var spins = 0
    while svc.status == .enabled && spins < 50 { usleep(100_000); spins += 1 }
    print("status after unregister (\(spins) spins): \(name(svc.status))")
    let gap = Int(ProcessInfo.processInfo.environment["S01_GAP_MS"] ?? "0") ?? 0
    if gap > 0 { usleep(UInt32(gap) * 1000) }
    do { try svc.register(); print("register: ok") } catch { print("register: error \(error)") }
default: break
}
print("after: \(name(svc.status))")
