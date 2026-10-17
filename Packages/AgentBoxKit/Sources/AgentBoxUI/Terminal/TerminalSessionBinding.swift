import AgentBoxCore
import AgentBoxPlatform
import AgentBoxProtocol
import Foundation
import Synchronization
import SwiftTerm

/// Observador de quadros já alimentados no emulador (medição: `scripts/bench.sh`). Chamado na thread de parse, depois
/// do `feed`; sem observador o custo é uma leitura de lock por quadro.
public nonisolated final class TerminalFrameObserver: Sendable {
    private let handler = Mutex<(@Sendable (Data) -> Void)?>(nil)
    public init() {}
    public func set(_ handler: (@Sendable (Data) -> Void)?) { self.handler.withLock { $0 = handler } }
    func fed(_ bytes: Data) {
        let current = handler.withLock { $0 }
        current?(bytes)
    }
}

/// Liga um `TerminalHostView` a uma sessão do daemon (06 §1, 08 AR-406/AR-709):
/// - saída: uma `Task` fora do main consome `PTYAttachment.updates` e chama `feed` (seguro em qualquer thread na
///   SwiftTerm 1.99); o main só desenha. O backlog por pane (`PTYBacklogGauge`) é do `PTYClient`, que pede `snapshot`
///   acima de 4 MiB.
/// - `snapshot`: refaz o emulador (`ESC c` + preâmbulo de modos) e reaplica o replay; durante o replay o emulador não
///   responde a consultas (AR-105).
/// - input: teclas, colagem e respostas saem por `PTYInputPipe` com a origem marcada, na ordem.
/// - resize: `PTYResizeCoordinator` com debounce, uma vez por transição (AR-710).
@MainActor
public final class TerminalSessionBinding {
    public let sessionID: SessionID
    private let client: PTYClient
    private let host: TerminalHostView
    private var pipe: PTYInputPipe?
    private var resizer: PTYResizeCoordinator?
    private var consumer: Task<Void, Never>?
    /// Eventos do daemon para este pane (título, cwd, bell, prompt, `sessionGone`), entregues no main.
    public var onEvent: ((EventPayload) -> Void)?
    public let frameObserver = TerminalFrameObserver()

    public init(client: PTYClient, sessionID: SessionID, host: TerminalHostView) {
        self.client = client
        self.sessionID = sessionID
        self.host = host
    }

    public var resizeCoordinator: PTYResizeCoordinator? { resizer }

    /// Anexa a sessão com o tamanho atual da view e começa a alimentá-la.
    public func start(mode: AttachMode = .snapshot) async throws {
        let surface = host.surface
        let dims = surface.terminalDimensions
        let size = PTYResizeCoordinator.Size(cols: UInt16(clamping: dims.cols), rows: UInt16(clamping: dims.rows))
        let attachment = try await client.attach(sessionID: sessionID, cols: size.cols, rows: size.rows, mode: mode)

        let pipe = PTYInputPipe(client: client, sessionID: sessionID)
        self.pipe = pipe
        surface.setOutputSink { bytes, origin in pipe.send(bytes, origin: origin) }

        let client = self.client
        let sessionID = self.sessionID
        let resizer = PTYResizeCoordinator(initial: size) { applied in
            try? await client.resize(sessionID: sessionID, cols: applied.cols, rows: applied.rows)
        }
        self.resizer = resizer
        surface.onResize = { cols, rows in
            resizer.request(.init(cols: UInt16(clamping: cols), rows: UInt16(clamping: rows)))
        }
        // O layout pode ter mudado entre a medição e agora.
        let current = surface.terminalDimensions
        resizer.request(.init(cols: UInt16(clamping: current.cols), rows: UInt16(clamping: current.rows)))

        let feeder = surface.feedSender
        let gauge = attachment.backlog
        let updates = attachment.updates
        let observer = frameObserver
        // DETACHED: o consumo do stream e o parse não podem herdar o MainActor (AR-406, AR-709); o ciclo de vida é `consumer`.
        consumer = Task.detached(priority: .userInitiated) { [weak self] in
            await Self.consume(updates, feeder: feeder, surface: surface, gauge: gauge, observer: observer) { event in
                Task { @MainActor in self?.onEvent?(event) }
            }
        }
    }

    public func stop() {
        consumer?.cancel()
        consumer = nil
        resizer?.close()
        resizer = nil
        host.surface.setOutputSink(nil)
        host.surface.onResize = nil
        pipe?.finish()
        pipe = nil
        let client = self.client
        let sessionID = self.sessionID
        Task { try? await client.detach(sessionID: sessionID) }
    }

    /// Escreve bytes no PTY como se fossem do usuário (testes e `Send` de ações do app, com a origem pedida).
    public func send(_ bytes: [UInt8], origin: InputOrigin) {
        pipe?.send(bytes, origin: origin)
    }

    nonisolated private static func consume(
        _ updates: AsyncStream<PTYUpdate>, feeder: TerminalFeedSender, surface: TerminalSurfaceView, gauge: PTYBacklogGauge,
        observer: TerminalFrameObserver, onEvent: @escaping @Sendable (EventPayload) -> Void
    ) async {
        let reset: [UInt8] = [0x1b, 0x63]
        var replayRemaining: Int64 = 0
        for await update in updates {
            if Task.isCancelled { return }
            switch update {
            case .snapshot(let snapshot):
                surface.setReplaying(true)
                if !snapshot.resumed {
                    let preamble = [UInt8](snapshot.modesPreamble)
                    if !preamble.starts(with: reset) { feeder.feed(byteArray: reset[...]) }
                    if !preamble.isEmpty { feeder.feed(byteArray: preamble[...]) }
                }
                replayRemaining = Int64(clamping: snapshot.endSeq &- snapshot.startSeq)
                if replayRemaining == 0 { surface.setReplaying(false) }
            case .output(let frame):
                let count = frame.bytes.count
                feeder.feed(byteArray: [UInt8](frame.bytes)[...])
                gauge.consumed(count)
                observer.fed(frame.bytes)
                if replayRemaining > 0 {
                    replayRemaining -= Int64(count)
                    if replayRemaining <= 0 { surface.setReplaying(false) }
                }
            case .event(let event):
                onEvent(event)
            case .disconnected:
                // Até o próximo `.snapshot` não chegam bytes; o replay seguinte liga o silêncio de novo.
                break
            }
        }
    }
}
