import AgentBoxPlatform
import AgentBoxUI
import SwiftUI

/// Casca (T1-01/T1-02): um `@main` que monta o `AppEnvironment` e a janela principal. Sem lógica de produto.
@main
struct AgentBoxApp: App {
    private let log = LogFacade(.app, category: "lifecycle")
    private let env = AppEnvironment()

    init() {
        log.publicInfo("launch")
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView(env: env)
        }
        .defaultSize(width: 1440, height: 900)
    }
}
