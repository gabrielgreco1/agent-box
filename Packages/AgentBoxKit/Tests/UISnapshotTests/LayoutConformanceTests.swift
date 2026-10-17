import AgentBoxDesignSystem
import AgentBoxProtocol
import AppKit
import Testing

@testable import AgentBoxUI

/// Medidas da janela e do chrome (03 §1, T1-10): semáforos, faixa de titlebar, largura da sidebar, tamanho mínimo.
@MainActor
@Suite struct LayoutConformanceTests {
    @Test func trafficLightGeometryMatchesTheSpec() {
        for h: CGFloat in [12, 14, 16, 20] {
            let origins = WindowGeometry.trafficLightOrigins(buttonSize: CGSize(width: h, height: h))
            #expect(origins.map(\.x) == [16, 36, 56])
            for o in origins { #expect(DS.Layout.titlebarHeight - (o.y + h / 2) == 18, "centro vertical em y = 18") }
        }
        #expect(WindowGeometry.trafficLightPad(fullScreen: false) == 80)
        #expect(WindowGeometry.trafficLightPad(fullScreen: true) == 0)
        #expect(DS.Layout.titlebarHeight == 36)
    }

    @Test func sidebarWidthIsClamped() {
        #expect(DS.Layout.sidebarWidth == 280)
        #expect(WindowGeometry.clampedSidebarWidth(100) == 220)
        #expect(WindowGeometry.clampedSidebarWidth(900) == 500)
        #expect(WindowGeometry.clampedSidebarWidth(300) == 300)
    }

    /// Posição de um semáforo medida na janela: origem x e distância do centro ao topo.
    private func lightMetrics(_ window: NSWindow, _ type: NSWindow.ButtonType) -> (x: CGFloat, centerFromTop: CGFloat) {
        let b = window.standardWindowButton(type)!
        let r = b.convert(b.bounds, to: nil)
        return (r.minX, window.frame.height - r.midY)
    }

    private func expectLights(_ window: NSWindow, _ note: String) {
        let xs = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].map { lightMetrics(window, $0) }
        #expect(xs.map(\.x) == [16, 36, 56], "\(note): x")
        for m in xs { #expect(abs(m.centerFromTop - 18) < 0.5, "\(note): centro y = \(m.centerFromTop)") }
    }

    @Test func windowIsConfiguredAndTrafficLightsSurviveResizeAndRelayout() async {
        let env = AppEnvironment(environment: [:])
        let controller = await EmptyWindowTreeTests.host(env)
        let window = controller.window!
        defer { window.close() }
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titleVisibility == .hidden)
        #expect(window.toolbar == nil)
        #expect(!window.isMovableByWindowBackground)
        #expect(window.contentMinSize == NSSize(width: 760, height: 480))
        expectLights(window, "760x480")

        window.setContentSize(NSSize(width: 1440, height: 900))
        try? await Task.sleep(for: .milliseconds(100))
        expectLights(window, "1440x900")

        // Se o AppKit mexer nos botões (relayout da titlebar), eles voltam ao lugar.
        window.standardWindowButton(.closeButton)!.setFrameOrigin(NSPoint(x: 3, y: 3))
        window.setContentSize(NSSize(width: 1200, height: 800))
        try? await Task.sleep(for: .milliseconds(100))
        expectLights(window, "depois de bagunçar")
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
        expectLights(window, "mudança de tela")
    }

    @Test func titlebarStripIs36AndSidebarStartsAt280() async {
        let env = AppEnvironment(environment: [:])
        let controller = await EmptyWindowTreeTests.host(env, size: NSSize(width: 1440, height: 900))
        defer { controller.window?.close() }
        let tree = await env.registry.uiTree(root: nil)
        let strip = tree.find(.windowTitlebar)?.frame
        #expect(strip?.height == 36)
        #expect(strip?.y == 0)
        #expect(strip?.width == 280)
        #expect(tree.find(.sidebar)?.frame?.width == 280)
        #expect((tree.find(.windowAppName)?.frame?.x ?? 0) >= 80)
        #expect(tree.find(.windowAppName)?.frame?.height == 24)
        #expect(tree.find(.windowSidebarToggle)?.frame?.width == 32)
        #expect(tree.find(.windowSidebarToggle)?.frame?.height == 24)
        #expect(tree.find(.windowHistoryBack)?.frame?.width == 22)
        #expect(tree.find(.windowHistoryBack)?.frame?.height == 20)
        // ←/→ terminam 12 pt antes da borda direita da faixa
        let fwd = tree.find(.windowHistoryForward)?.frame
        let right: Double = (fwd?.x ?? 0) + (fwd?.width ?? 0)
        #expect(right == 268)
    }

    @Test func toggleSidebarActionCollapsesAndExpands() async throws {
        let env = AppEnvironment(environment: [:])
        let controller = await EmptyWindowTreeTests.host(env, size: NSSize(width: 1440, height: 900))
        defer { controller.window?.close() }
        let r1 = try await env.registry.perform(.viewToggleSidebar, .press)
        #expect(r1.message == "collapsed")
        #expect(env.shell.sidebarCollapsed)
        let r2 = try await env.registry.perform(.viewToggleSidebar, .press)
        #expect(r2.message == "expanded")
        #expect(!env.shell.sidebarCollapsed)
    }
}
