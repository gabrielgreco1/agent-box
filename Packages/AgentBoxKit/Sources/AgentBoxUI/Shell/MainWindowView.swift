import AgentBoxProtocol
import AppKit
import SwiftUI

/// Janela principal ainda vazia (T1-02): só a faixa da titlebar com o nome do app e o selo "Automation on".
/// Cada região leva `A11yID` canônico, então `ctl ui tree` a lista.
public struct MainWindowView: View {
    private let env: AppEnvironment

    public init(env: AppEnvironment) { self.env = env }

    public var body: some View {
        VStack(spacing: 0) {
            titlebar
            Color.clear
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowReader { env.elements.window = $0 })
        .a11y(.windowMain, kind: "window", label: "Agent Box")
        .environment(\.elementStore, env.elements)
        .environment(\.actionRegistry, env.registry)
        .task { await env.start() }
    }

    private var titlebar: some View {
        HStack {
            if !env.shell.appNameHidden {
                Text("Agent Box", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .a11y(.windowAppName, kind: "text", label: "Agent Box")
            }
            Spacer()
            if env.automationEnabled {
                Text("Automation on", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .a11y(.windowAutomationBadge, kind: "text", label: "Automation on")
            }
        }
        .padding()
        .a11y(.windowTitlebar, kind: "container")
    }
}

/// Entrega a `NSWindow` que hospeda a view (para tamanho, escala e captura).
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    final class Reader: NSView {
        var onWindow: (NSWindow?) -> Void = { _ in }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow(window)
        }
    }

    func makeNSView(context: Context) -> Reader {
        let v = Reader()
        v.onWindow = onWindow
        return v
    }

    func updateNSView(_ nsView: Reader, context: Context) { nsView.onWindow = onWindow }
}
