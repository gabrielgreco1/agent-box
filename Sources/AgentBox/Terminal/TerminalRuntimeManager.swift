import AppKit
import AgentBoxCore
import Darwin
import SwiftTerm
import SwiftUI

public enum TerminalProcessState: Equatable {
    case idle
    case starting
    case running(pid: Int32)
    case exited(code: Int32?)
    case failed(String)
}

/// Owns the PTY and emulator for each terminal ID for the lifetime of this app process.
/// A SwiftUI pane only attaches/detaches the retained renderer. It never starts a command.
@MainActor
public final class TerminalRuntimeManager: ObservableObject {
    @Published public private(set) var processStates: [UUID: TerminalProcessState] = [:]
    public var hasRunningProcesses: Bool {
        processStates.values.contains { if case .running = $0 { return true }; return false }
    }

    private final class Entry {
        let view: LocalProcessTerminalView
        let observer: ProcessObserver
        let generation: UUID
        init(view: LocalProcessTerminalView, observer: ProcessObserver, generation: UUID) {
            self.view = view; self.observer = observer; self.generation = generation
        }
    }

    private final class ProcessObserver: NSObject, LocalProcessTerminalViewDelegate {
        var onExit: ((Int32?) -> Void)?
        func processTerminated(source: TerminalView, exitCode: Int32?) { onExit?(exitCode) }
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }

    private var entries: [UUID: Entry] = [:]
    private let resolver: CLIExecutableResolver

    public init(resolver: CLIExecutableResolver = CLIExecutableResolver()) {
        self.resolver = resolver
    }

    public func state(for id: UUID) -> TerminalProcessState { processStates[id] ?? .idle }

    // Internal for runtime tests; UI attaches through TerminalSurface.
    func renderer(for id: UUID) -> LocalProcessTerminalView? { entries[id]?.view }

    public func start(_ terminal: TerminalRecord) {
        if case .running = state(for: terminal.id) { return }
        if case .starting = state(for: terminal.id) { return }
        processStates[terminal.id] = .starting
        do {
            let executable = try resolver.resolve(terminal.provider)
            let cwd = try resolver.validateWorkingDirectory(terminal.cwd)
            // A previous run has a distinct renderer. The record ID remains the UI identity.
            let entry = makeEntry(id: terminal.id)
            entries[terminal.id] = entry
            let args = terminal.provider == .shell && terminal.arguments.isEmpty ? ["-l"] : terminal.arguments
            entry.view.startProcess(executable: executable, args: args,
                                    environment: childEnvironment(executable: executable), currentDirectory: cwd)
            let process = entry.view.process
            if let process, process.running && process.shellPid > 0 {
                processStates[terminal.id] = .running(pid: process.shellPid)
            } else {
                processStates[terminal.id] = .failed("Could not start a PTY for \(executable).")
            }
        } catch {
            processStates[terminal.id] = .failed(error.localizedDescription)
        }
    }

    public func stop(_ id: UUID) {
        guard let entry = entries[id], case .running(let pid) = state(for: id) else { return }
        // SwiftTerm starts a new session with a process group headed by the child PID.
        // An interactive shell may move a foreground job into another group.
        signalOwnedGroups(entry: entry, leaderPID: pid, signal: SIGTERM)
        // Keep the run active until SwiftTerm's exit monitor confirms it ended.
        // Calling view.terminate() here would cancel that monitor prematurely.
    }

    public func forceStop(_ id: UUID) {
        guard let entry = entries[id], case .running(let pid) = state(for: id) else { return }
        signalOwnedGroups(entry: entry, leaderPID: pid, signal: SIGKILL)
    }

    public func shutdown() {
        let hadRunningProcesses = hasRunningProcesses
        for id in Array(entries.keys) { stop(id) }
        // The quit flow explicitly authorized ending these processes. Give SIGTERM
        // a short grace period, then prevent an orphaned process from surviving us.
        if hadRunningProcesses { usleep(500_000) }
        for id in Array(entries.keys) {
            if case .running(let pid) = state(for: id), let entry = entries[id] {
                signalOwnedGroups(entry: entry, leaderPID: pid, signal: SIGKILL)
            }
            entries[id]?.view.terminate()
        }
        entries.removeAll()
    }

    /// Called only by TerminalSurface. A missing renderer is an empty terminal, not a launch request.
    func attach(_ id: UUID, to host: NSView) {
        let entry = entries[id] ?? {
            let entry = makeEntry(id: id)
            entries[id] = entry
            return entry
        }()
        let view = entry.view
        if view.superview !== host { view.removeFromSuperview() }
        for child in host.subviews where child !== view { child.removeFromSuperview() }
        if view.superview == nil {
            view.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                view.topAnchor.constraint(equalTo: host.topAnchor),
                view.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            ])
        }
    }

    private func makeEntry(id: UUID) -> Entry {
        let options = TerminalOptions(cols: 80, rows: 24, termName: "xterm-256color", scrollback: 5_000)
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 480),
                                            font: .monospacedSystemFont(ofSize: 12, weight: .regular), options: options)
        let observer = ProcessObserver()
        let generation = UUID()
        observer.onExit = { [weak self] rawStatus in
            Task { @MainActor [weak self] in
                guard let self, self.entries[id]?.generation == generation else { return }
                self.processStates[id] = .exited(code: Self.decodeWaitStatus(rawStatus))
            }
        }
        view.processDelegate = observer
        return Entry(view: view, observer: observer, generation: generation)
    }

    private func signalOwnedGroups(entry: Entry, leaderPID: Int32, signal: Int32) {
        guard leaderPID > 0 else { return }
        let fd = entry.view.process?.childfd ?? -1
        if fd >= 0 {
            let foreground = Darwin.tcgetpgrp(fd)
            if foreground > 0 && foreground != leaderPID && foreground != Darwin.getpgrp(),
               Darwin.getsid(foreground) == Darwin.getsid(leaderPID) {
                _ = Darwin.kill(-foreground, signal)
            }
        }
        _ = Darwin.kill(-leaderPID, signal)
    }

    private static func decodeWaitStatus(_ status: Int32?) -> Int32? {
        guard let status else { return nil }
        let signal = status & 0x7f
        if signal == 0 { return (status >> 8) & 0xff }
        if signal != 0x7f { return 128 + signal }
        return nil
    }

    private func childEnvironment(executable: String) -> [String] {
        let inherited = ProcessInfo.processInfo.environment
        let allowed = ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"]
        var values = Dictionary(uniqueKeysWithValues: allowed.compactMap { key in inherited[key].map { (key, $0) } })
        values["PATH"] = ([URL(fileURLWithPath: executable).deletingLastPathComponent().path,
                            inherited["PATH"] ?? "", "\(NSHomeDirectory())/.local/bin", "\(NSHomeDirectory())/.bun/bin",
                            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"])
            .filter { !$0.isEmpty }.joined(separator: ":")
        values["TERM"] = "xterm-256color"
        values["COLORTERM"] = "truecolor"
        if values["LANG"] == nil { values["LANG"] = "en_US.UTF-8" }
        return values.map { "\($0.key)=\($0.value)" }
    }
}

public struct TerminalSurface: NSViewRepresentable {
    public let terminal: TerminalRecord
    @ObservedObject public var runtime: TerminalRuntimeManager

    public init(terminal: TerminalRecord, runtime: TerminalRuntimeManager) {
        self.terminal = terminal
        self.runtime = runtime
    }

    public func makeNSView(context: Context) -> NSView {
        let host = NSView()
        runtime.attach(terminal.id, to: host)
        return host
    }

    public func updateNSView(_ host: NSView, context: Context) {
        runtime.attach(terminal.id, to: host)
    }

    public static func dismantleNSView(_ host: NSView, coordinator: ()) {
        host.subviews.forEach { $0.removeFromSuperview() }
    }
}
