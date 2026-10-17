import AgentBoxUI
import AppKit

// Casca AppKit (00 T5): sem cena SwiftUI; a janela é um NSWindow configurado à mão.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
