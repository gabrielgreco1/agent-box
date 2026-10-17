import AgentBoxPlatform
import SwiftUI

/// Casca vazia (T1-01): abre uma janela sem UI de produto.
@main
struct AgentBoxApp: App {
    private let log = LogFacade(.app, category: "lifecycle")

    init() {
        log.publicInfo("launch")
    }

    var body: some Scene {
        WindowGroup {
            Color.clear
                .frame(minWidth: 640, minHeight: 400)
        }
    }
}
