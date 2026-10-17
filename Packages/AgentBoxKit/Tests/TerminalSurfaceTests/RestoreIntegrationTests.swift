import AgentBoxCore
import AgentBoxProtocol
import AgentBoxStore
import AppKit
import Darwin
import Foundation
import Testing

@testable import AgentBoxUI

/// Reabertura com o `agentboxd` real (T1-23): matar o app e reabrir reanexa com o mesmo conteúdo; matar o daemon deixa os
/// panes `interrupted` com o cold log esmaecido e nada é relançado; Resume reconstrói o argv do CLI.
@MainActor
@Suite(.serialized) struct RestoreIntegrationTests {
    /// Uma "execução do app": runtime + modelo + área de panes ligados ao mesmo banco e ao mesmo daemon. `die()` descarta tudo
    /// do lado do app sem tocar no daemon, como um `kill -9` do app.
    private final class AppRun {
        let runtime: TerminalRuntime
        let model: WorkspaceModel
        let area: PaneAreaView
        let window: NSWindow
        var report: ReconcileReport?

        init(harness: DaemonHarness, session: Session, binDirectory: URL) {
            runtime = TerminalRuntime(
                configuration: .init(
                    daemonHome: harness.home, daemonExecutable: agentboxdBinary(), stopDaemonOnQuit: false, appSocketPath: "/tmp/none.sock",
                    loginEnvironment: { ["PATH": "\(binDirectory.path):/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"] }),
                registry: nil, elements: nil)
            model = WorkspaceModel(runtime: runtime)
            area = PaneAreaView(model: model, registry: nil, elements: nil, router: nil)
            window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1200, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = area
            area.frame = NSRect(x: 0, y: 0, width: 1200, height: 700)
            model.sessionLookup = { _ in session }
        }

        /// Abrir o app: reconcilia com o daemon, carrega o workspace e seleciona a sessão (o que `AppEnvironment` faz).
        func open(store: AgentBoxStore, session: Session) async throws {
            report = await model.restoreSessions(store: store)
            await model.attach(store: store)
            model.ingest(try await store.snapshot())
            model.setSession(session.id)
            area.layoutSubtreeIfNeeded()
        }

        func screen(_ id: UUID) -> String {
            guard let entry = runtime.existingEntry(for: id) else { return "" }
            return String(decoding: entry.host.surface.getBufferAsData(kind: .active), as: UTF8.self)
        }

        func die() async {
            window.close()
            await runtime.client.stop()
        }
    }

    private struct World {
        let harness: DaemonHarness
        let store: AgentBoxStore
        let session: Session
        let binDirectory: URL

        init() async throws {
            harness = try DaemonHarness()
            try await harness.start()
            store = try await AgentBoxStore.open(paths: .default(environment: ["AGENTBOX_HOME": harness.home.path]))
            session = Session(kind: .clean, folderPath: NSTemporaryDirectory(), title: "restore")
            binDirectory = URL(fileURLWithPath: "/tmp/abrestorebin-\(UInt32.random(in: 0 ... 0xFFFFFF))", isDirectory: true)
            try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        }

        func installFakeCLI(_ name: String, script: String) throws {
            let url = binDirectory.appendingPathComponent(name)
            try ("#!/bin/sh\n" + script + "\n").write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        /// Sessão com uma tab e um terminal já salvos no banco (como o `SessionLauncher` deixa).
        func seed(spec: LaunchSpec, provider: TerminalProvider = .custom) async throws -> (tab: Tab, terminal: Terminal) {
            let tabID = UUID.v7(), termID = UUID.v7()
            let terminal = Terminal(id: termID, tabID: tabID, provider: provider, title: "t", cwd: NSTemporaryDirectory(), launchSpec: spec)
            let tab = Tab(id: tabID, sessionID: session.id, title: "t", layout: .leaf(Pane(content: .terminal(termID))), focusedTerminalID: termID)
            try await store.saveBundle(session: session, tabs: [tab], terminals: [terminal])
            return (tab, terminal)
        }

        func finish(_ runs: AppRun...) async {
            for run in runs { await run.die() }
            await harness.stop()
            try? FileManager.default.removeItem(at: binDirectory)
        }
    }

    private static let echoer = ["/bin/sh", "-c", "echo MARK-$$; exec cat"]

    // MARK: kill do app e reabertura

    @Test func killingTheAppAndReopeningReattachesTwoPanesWithTheSameContentAndPIDs() async throws {
        let world = try await World()
        let first = try await world.seed(spec: LaunchSpec(provider: .custom, customArgv: Self.echoer))
        let run1 = AppRun(harness: world.harness, session: world.session, binDirectory: world.binDirectory)
        try await run1.open(store: world.store, session: world.session)
        let a = first.terminal.id
        try await eventually("pane A running with its marker", timeout: .seconds(30)) {
            run1.model.terminal(a)?.state == .running && run1.screen(a).contains("MARK-")
        }
        // Segundo pane (split) e foco nele; escreve algo em cada um.
        guard case .created(let b) = run1.model.split(.horizontal) else { Issue.record("split failed"); return await world.finish(run1) }
        run1.area.layoutSubtreeIfNeeded()
        try await eventually("pane B running", timeout: .seconds(30)) { run1.model.terminal(b)?.state == .running && run1.screen(b).contains("MARK-") }
        run1.runtime.existingEntry(for: a)?.host.surface.send(txt: "typed-in-A\r")
        run1.runtime.existingEntry(for: b)?.host.surface.send(txt: "typed-in-B\r")
        try await eventually("both echo", timeout: .seconds(15)) { run1.screen(a).contains("typed-in-A") && run1.screen(b).contains("typed-in-B") }
        run1.model.focus(terminalID: a)
        await run1.model.settlePersistence()
        try await Task.sleep(for: .milliseconds(800))  // debounce do foco (300 ms) + gravação

        let before = (try await run1.runtime.client.list()).filter { $0.state == .running }
        #expect(before.count == 2)
        let pids = Dictionary(uniqueKeysWithValues: before.map { ($0.sessionID.description, $0.pid) })
        let sessionA = try #require(run1.model.terminal(a)?.ptySessionID), sessionB = try #require(run1.model.terminal(b)?.ptySessionID)
        let layoutBefore = try #require(run1.model.activeTab?.layout)
        let markA = run1.screen(a)
        #expect(markA.contains("MARK-"))

        // kill -9 do app: o lado do app some; o daemon fica.
        await run1.die()

        let run2 = AppRun(harness: world.harness, session: world.session, binDirectory: world.binDirectory)
        try await run2.open(store: world.store, session: world.session)
        #expect(run2.report?.alive.count == 2)
        #expect(run2.report?.interrupted.isEmpty == true)
        #expect(run2.model.tabs.count == 1)
        #expect(run2.model.activeTab?.layout == layoutBefore, "mesma árvore de splits, com as mesmas frações")
        #expect(run2.model.focusedTerminalID == a, "o foco volta ao pane que estava focado")
        try await eventually("both panes reattached with the same text", timeout: .seconds(30)) {
            run2.screen(a).contains("MARK-") && run2.screen(a).contains("typed-in-A") && run2.screen(b).contains("typed-in-B")
        }
        #expect(run2.model.terminal(a)?.ptySessionID == sessionA && run2.model.terminal(b)?.ptySessionID == sessionB)
        #expect(run2.screen(a).contains(markA.components(separatedBy: "MARK-")[1].prefix(while: \.isNumber).description), "mesmo PID no conteúdo")
        let after = (try await run2.runtime.client.list()).filter { $0.state == .running }
        #expect(Dictionary(uniqueKeysWithValues: after.map { ($0.sessionID.description, $0.pid) }) == pids, "nenhum processo novo: mesmos PIDs")
        #expect(run2.model.paneState(a) == .running && run2.model.paneState(b) == .running)
        // O app não escreveu nada por conta própria nos PTYs além do que o teste digitou (T11).
        for session in after {
            #expect(session.inputBytesByOrigin[.appPaste] == 0 && session.inputBytesByOrigin[.ctl] == 0 && session.inputBytesByOrigin[.parentToChild] == 0, "reabrir não digita no terminal")
        }
        // Digitar depois de reabrir funciona.
        run2.runtime.existingEntry(for: a)?.host.surface.send(txt: "after-reopen\r")
        try await eventually("typing works after reopen", timeout: .seconds(15)) { run2.screen(a).contains("after-reopen") }
        await world.finish(run2)
    }

    // MARK: daemon morto

    @Test func killingTheDaemonWhileTheAppIsClosedLeavesInterruptedPanesWithTheColdLogAndRelaunchesNothing() async throws {
        let world = try await World()
        let seeded = try await world.seed(spec: LaunchSpec(provider: .custom, customArgv: ["/bin/sh", "-c", "echo COLD-LINE-$$; exec cat"]))
        let run1 = AppRun(harness: world.harness, session: world.session, binDirectory: world.binDirectory)
        try await run1.open(store: world.store, session: world.session)
        let id = seeded.terminal.id
        try await eventually("running with output", timeout: .seconds(30)) { run1.model.terminal(id)?.state == .running && run1.screen(id).contains("COLD-LINE-") }
        try await Task.sleep(for: .milliseconds(400))  // o cold log grava em lote (100 ms)
        await run1.model.settlePersistence()
        await run1.die()
        await SessionReconciler.markCleanExit(store: world.store)  // ⌘Q limpo
        await world.harness.killDaemon()

        let run2 = AppRun(harness: world.harness, session: world.session, binDirectory: world.binDirectory)
        try await run2.open(store: world.store, session: world.session)
        #expect(run2.report?.interrupted[id] == .appClosed)
        #expect(run2.model.terminal(id)?.state == .interrupted)
        guard case .interrupted = run2.model.paneState(id) else { Issue.record("pane must be Interrupted"); return await world.finish(run2) }
        #expect(run2.model.interruptionReasons[id] == .appClosed)
        try await eventually("cold log scrollback on screen", timeout: .seconds(15)) { run2.screen(id).contains("COLD-LINE-") }
        // Nada foi relançado: o daemon nem foi religado e nenhuma sessão nova existe.
        try await Task.sleep(for: .milliseconds(500))
        #expect(run2.runtime.connection == .idle, "reabrir não sobe daemon só para descobrir o que morreu")
        #expect(run2.model.terminal(id)?.state == .interrupted)
        // Persistido: uma terceira abertura continua interrompida (sem processo, o estado não muda sozinho).
        await run2.die()
        let run3 = AppRun(harness: world.harness, session: world.session, binDirectory: world.binDirectory)
        try await run3.open(store: world.store, session: world.session)
        #expect(run3.model.terminal(id)?.state == .interrupted)
        #expect(run3.report?.alive.isEmpty == true && run3.report?.interrupted.isEmpty == true)
        await world.finish(run3)
    }

    @Test func killingTheDaemonWhileTheAppIsOpenInterruptsTheRunningPanes() async throws {
        let world = try await World()
        let seeded = try await world.seed(spec: LaunchSpec(provider: .custom, customArgv: ["/bin/sh", "-c", "echo LIVE-LINE-$$; exec cat"]))
        let run = AppRun(harness: world.harness, session: world.session, binDirectory: world.binDirectory)
        try await run.open(store: world.store, session: world.session)
        let id = seeded.terminal.id
        try await eventually("running", timeout: .seconds(30)) { run.model.terminal(id)?.state == .running && run.screen(id).contains("LIVE-LINE-") }
        try await Task.sleep(for: .milliseconds(400))
        await world.harness.killDaemon()
        // O monitor espera 2 s pela reconexão, sobe um daemon novo como filho e o modelo confere o que sobrou.
        try await eventually("interrupted after the daemon died", timeout: .seconds(40)) {
            if case .interrupted = run.model.paneState(id) { true } else { false }
        }
        #expect(run.model.interruptionReasons[id] == .unexpected)
        #expect(run.model.terminal(id)?.state == .interrupted)
        try await eventually("cold log scrollback", timeout: .seconds(10)) { run.screen(id).contains("LIVE-LINE-") }
        let sessions = try await run.runtime.client.list()
        #expect(sessions.filter { $0.state == .running }.isEmpty, "o daemon novo não tem sessões: nada foi relançado sozinho")
        run.runtime.daemonKill()
        await world.finish(run)
    }

    // MARK: Resume e Start Fresh

    @Test func resumeRebuildsTheArgvWithTheNativeIDAndStartFreshStartsANewConversation() async throws {
        let world = try await World()
        try world.installFakeCLI("claude", script: "echo \"ARGV:$@\"; exec cat")
        let seeded = try await world.seed(
            spec: LaunchSpec(provider: .claude, permissionMode: "bypassPermissions", initialPrompt: "hello there"), provider: .claude)
        let id = seeded.terminal.id
        let run1 = AppRun(harness: world.harness, session: world.session, binDirectory: world.binDirectory)
        try await run1.open(store: world.store, session: world.session)
        try await eventually("claude running", timeout: .seconds(30)) { run1.model.terminal(id)?.state == .running && run1.screen(id).contains("ARGV:") }
        let native = try #require(run1.model.terminal(id)?.nativeConversationID)
        #expect(run1.screen(id).contains("ARGV:--session-id \(native) --dangerously-skip-permissions hello there"), "AC-307: o primeiro start")
        await run1.model.settlePersistence()
        try await Task.sleep(for: .milliseconds(400))
        await run1.die()
        await world.harness.killDaemon()

        // Reabre com o daemon morto: Interrupted; Resume sobe um daemon novo e relança com o ID e as mesmas flags.
        let run2 = AppRun(harness: world.harness, session: world.session, binDirectory: world.binDirectory)
        try await run2.open(store: world.store, session: world.session)
        guard case .interrupted = run2.model.paneState(id) else { Issue.record("must be Interrupted"); return await world.finish(run2) }
        #expect(RestorePlanner.hasExactResume(try #require(run2.model.terminal(id))))
        run2.model.resume(id)
        try await eventually("resumed", timeout: .seconds(40)) {
            run2.model.paneState(id) == .running && run2.screen(id).contains("ARGV:--resume")
        }
        let resumed = run2.screen(id)
        #expect(resumed.contains("ARGV:--resume \(native) --dangerously-skip-permissions"), "mesmo ID, mesmas flags, sem --session-id")
        #expect(!resumed.contains("hello there"), "o prompt inicial nunca se repete no Resume")
        #expect(run2.model.terminal(id)?.nativeConversationID == native)
        #expect(run2.model.terminal(id)?.state == .running)

        // Start Fresh em cima: conversa nova (UUID diferente), sem prompt.
        run2.model.startFresh(id)
        try await eventually("fresh", timeout: .seconds(40)) {
            let t = run2.model.terminal(id)
            return run2.model.paneState(id) == .running && t?.nativeConversationID != nil && t?.nativeConversationID != native
                && run2.screen(id).contains("ARGV:--session-id")
        }
        let fresh = try #require(run2.model.terminal(id)?.nativeConversationID)
        #expect(run2.screen(id).contains("ARGV:--session-id \(fresh) --dangerously-skip-permissions"))
        #expect(!run2.screen(id).contains("--resume"))
        run2.runtime.daemonKill()
        await world.finish(run2)
    }
}

extension TerminalRuntime {
    /// Testes: derruba o daemon filho que o runtime tenha subido.
    func daemonKill() {
        let pid = daemonPID
        if pid > 0 { Darwin.kill(pid, SIGKILL) }
    }
}
