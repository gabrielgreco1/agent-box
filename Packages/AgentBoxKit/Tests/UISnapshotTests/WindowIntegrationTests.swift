import AgentBoxProtocol
import AppKit
import SwiftUI
import Testing

@testable import AgentBoxUI

@MainActor
@Suite struct UIElementStoreTests {
    @Test func snapshotBuildsHierarchyFromParentLinks() {
        let store = UIElementStore()
        let a = UUID(), b = UUID(), c = UUID()
        store.register(a, id: .windowMain, kind: "window", label: nil, value: nil, action: nil, parent: nil)
        store.register(b, id: .windowTitlebar, kind: "container", label: nil, value: nil, action: nil, parent: .windowMain)
        store.register(c, id: .windowAppName, kind: "text", label: "Agent Box", value: nil, action: nil, parent: .windowTitlebar)
        store.updateFrame(c, CGRect(x: 1, y: 2, width: 30, height: 10))
        let tree = store.snapshot()
        #expect(tree.roots.map(\.id) == [.windowMain])
        #expect(tree.find(.windowAppName)?.label == "Agent Box")
        #expect(tree.find(.windowAppName)?.frame == UIFrame(x: 1, y: 2, width: 30, height: 10))
        #expect(tree.roots[0].children[0].children[0].id == .windowAppName)
        #expect(store.snapshot(root: .windowTitlebar).roots.first?.children.first?.id == .windowAppName)
        #expect(store.snapshot(root: .sidebar).roots.isEmpty)
    }

    @Test func unregisterRemovesTheElement() {
        let store = UIElementStore()
        let t = UUID()
        store.register(t, id: .windowMain, kind: "window", label: nil, value: nil, action: nil, parent: nil)
        store.unregister(t)
        #expect(store.snapshot().roots.isEmpty)
    }

    @Test func duplicateIDsAreDetected() {
        let store = UIElementStore()
        store.register(UUID(), id: .tabsNew, kind: "button", label: nil, value: nil, action: nil, parent: nil)
        store.register(UUID(), id: .tabsNew, kind: "button", label: nil, value: nil, action: nil, parent: nil)
        #expect(store.duplicateIDs == [.tabsNew])
    }

    @Test func orphanParentBecomesRoot() {
        let store = UIElementStore()
        store.register(UUID(), id: .windowAppName, kind: "text", label: nil, value: nil, action: nil, parent: .windowTitlebar)
        #expect(store.snapshot().roots.map(\.id) == [.windowAppName])
    }

    @Test func controlStateComesFromTheActionEnablement() {
        let store = UIElementStore()
        store.enablement = { $0 == .tabNewAgent ? .disabled(reason: "Select a session first.") : .enabled }
        store.register(UUID(), id: .tabsNew, kind: "button", label: "New Tab", value: nil, action: .tabNewAgent, parent: nil)
        let node = store.snapshot().find(.tabsNew)
        #expect(node?.enabled == false)
        #expect(node?.disabledReason == "Select a session first.")
        #expect(node?.action == .tabNewAgent)
    }
}

/// A janela vazia lista os controles pelo registro (T1-02: "ctl ui tree lista a janela vazia").
@MainActor
@Suite struct EmptyWindowTreeTests {
    private func host(_ env: AppEnvironment) async -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 760, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: MainWindowView(env: env))
        window.contentView = hosting
        window.orderBack(nil)  // fora da tela; sem ativar o app nem roubar foco
        hosting.layoutSubtreeIfNeeded()
        for _ in 0..<80 {
            try? await Task.sleep(for: .milliseconds(25))
            if env.elements.snapshot().find(.windowAppName)?.frame != nil { break }
        }
        return window
    }

    @Test func windowListsItsCanonicalControls() async {
        let env = AppEnvironment(environment: [:])
        let window = await host(env)
        defer { window.close() }
        let tree = await env.registry.uiTree(root: nil)
        #expect(tree.roots.map(\.id) == [.windowMain])
        for id in [A11yID.windowMain, .windowTitlebar, .windowAppName] {
            #expect(tree.find(id) != nil, "\(id.rawValue) deveria estar na árvore")
        }
        #expect(tree.find(.windowAutomationBadge) == nil, "o selo só aparece com a automação ligada")
        #expect(tree.window?.width == 760)
        // varredura (AC-T01): todo ID da árvore é canônico e nenhum se repete
        for node in tree.flattened() { #expect(A11yID.isCanonical(node.id.rawValue)) }
        #expect(env.elements.duplicateIDs.isEmpty)
        #expect(tree.find(.windowAppName)?.frame != nil)
    }

    @Test func automationBadgeAppearsOnlyWhenAutomationIsOn() async {
        let sock = FileManager.default.temporaryDirectory.appendingPathComponent("abx-\(UUID().uuidString.prefix(8))/app.sock").path
        let env = AppEnvironment(environment: ["AGENTBOX_AUTOMATION": "1", "AGENTBOX_APP_SOCK": sock])
        let window = await host(env)
        defer { window.close() }
        let tree = await env.registry.uiTree(root: nil)
        #expect(tree.find(.windowAutomationBadge) != nil)
        await env.stop()
    }

    @Test func hideAppNameActionRemovesTheLabelFromTheTree() async throws {
        let env = AppEnvironment(environment: [:])
        let window = await host(env)
        defer { window.close() }
        let result = try await env.registry.perform(.appHideAppName, .press)
        #expect(result.message == "hidden")
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(25))
            if env.elements.snapshot().find(.windowAppName) == nil { break }
        }
        #expect(await env.registry.uiTree(root: nil).find(.windowAppName) == nil)
        #expect(await env.registry.appState().registeredActions.contains(.appHideAppName))
    }

    @Test func futureSliceActionsAreNotRegisteredNorRendered() async {
        let env = AppEnvironment(environment: [:])
        #expect(env.registry.availability(of: .viewToggleRightPanel) == .unavailable(.slice2))
        #expect(!env.registry.isRendered(.pageInbox))
    }
}
