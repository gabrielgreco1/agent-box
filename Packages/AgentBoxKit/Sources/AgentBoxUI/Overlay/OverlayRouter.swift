import AgentBoxDesignSystem
import AgentBoxProtocol
import AppKit
import Observation
import SwiftUI

/// O que fecha um overlay (03 §20, 02 §12.17).
public enum OverlayDismissReason: Sendable, Equatable {
    case escape, scrim, action
}

/// Descrição de um overlay: o conteúdo é uma view já montada com seus modelos (zero lógica de domínio aqui, T3).
public struct OverlaySpec {
    /// `<nome>` de `overlay.<nome>` (03 §22).
    public var name: String
    public var id: A11yID
    public var width: CGFloat
    public var cornerRadius: CGFloat
    /// Ação de Cancel (Esc). Sem handler registrado, Esc fecha direto: o overlay nunca prende o usuário.
    public var cancelAction: ActionID?
    /// `false` quando há dados digitados: o clique no scrim é ignorado (02 §12.17, regra 7).
    public var dismissOnScrim: @MainActor () -> Bool
    public var content: @MainActor () -> AnyView

    public init(
        name: String, id: A11yID, width: CGFloat = DS.Layout.dialogWidth, cornerRadius: CGFloat = DS.Radius.card,
        cancelAction: ActionID? = nil, dismissOnScrim: @escaping @MainActor () -> Bool = { true },
        content: @escaping @MainActor () -> AnyView
    ) {
        self.name = name
        self.id = id
        self.width = width
        self.cornerRadius = cornerRadius
        self.cancelAction = cancelAction
        self.dismissOnScrim = dismissOnScrim
        self.content = content
    }
}

public struct OverlayEntry: Identifiable {
    public let id = UUID()
    public let spec: OverlaySpec
    /// Botão que abriu o overlay (origem da animação, M-101) e seu frame no momento da abertura.
    public let originID: A11yID?
    public let originFrame: CGRect?
    public fileprivate(set) var isClosing = false
}

/// Evento de motion (04 §7.1.1): `M-101 begin|settled|end`, `M-102 begin|end`.
public struct OverlayMotionEvent: Equatable, Sendable {
    public let name: String
    public let time: TimeInterval
}

/// Pilha de overlays dentro da janela (00 T5, 02 §12.17). Um nível mais um sub-overlay no máximo; só o topo recebe teclas.
/// Fechar devolve o foco ao elemento de origem no INÍCIO da saída (04 princípio 8), antes de a animação terminar.
@MainActor @Observable
public final class OverlayRouter {
    public static let maxDepth = 2

    public private(set) var stack: [OverlayEntry] = []
    /// Botão de origem do overlay aberto: mantém o fundo "ativo" enquanto o overlay existe (M-101, M-102).
    public private(set) var originActive: A11yID?
    public private(set) var events: [OverlayMotionEvent] = []
    /// Frames dos cartões no espaço global da janela (usados pelo clique no scrim).
    @ObservationIgnored public private(set) var cardFrames: [UUID: CGRect] = [:]

    @ObservationIgnored public var focus: OverlayFocusCoordinator?
    /// Dispara uma ação do registro; `false` se ela não está disponível (então Esc fecha direto).
    @ObservationIgnored public var performAction: @MainActor (ActionID) -> Bool = { _ in false }
    /// Frame de um controle pelo `A11yID` (origem da animação).
    @ObservationIgnored public var frameOf: @MainActor (A11yID) -> CGRect? = { _ in nil }

    private var pendingRemovals: [UUID: Task<Void, Never>] = [:]

    public init() {}

    /// Overlays visíveis e interativos (os que estão saindo não contam).
    public var live: [OverlayEntry] { stack.filter { !$0.isClosing } }
    public var top: OverlayEntry? { live.last }
    /// Enquanto há overlay vivo o terminal não aceita first responder nem teclas (02 §12.17).
    public var isPresenting: Bool { !live.isEmpty }
    public var blocksTerminalInput: Bool { isPresenting }

    // MARK: Abrir

    /// Abre um overlay a partir do botão `origin`. Devolve `false` se a pilha já tem o máximo (um sub-overlay).
    @discardableResult
    public func present(_ spec: OverlaySpec, from origin: A11yID? = nil) -> Bool {
        guard live.count < Self.maxDepth else { return false }
        let wasEmpty = live.isEmpty
        let frame = origin.flatMap(frameOf)
        stack.append(OverlayEntry(spec: spec, originID: origin, originFrame: frame))
        if wasEmpty {
            originActive = origin
            focus?.capture()
        } else {
            focus?.focusOverlay()
        }
        record("M-101 begin")
        scheduleOpenEvents()
        return true
    }

    // MARK: Fechar

    /// Fecha o overlay do topo.
    public func dismiss(_ reason: OverlayDismissReason = .action) {
        guard let entry = top, let index = stack.firstIndex(where: { $0.id == entry.id }) else { return }
        stack[index].isClosing = true
        let last = live.isEmpty
        if last {
            originActive = nil
            focus?.restore()
        } else {
            focus?.focusOverlay()
        }
        record("M-102 begin")
        scheduleRemoval(of: entry.id)
    }

    /// Fecha tudo (troca de janela, ⌘Q confirmado).
    public func dismissAll() {
        while isPresenting { dismiss(.action) }
    }

    /// Esc: dispara o Cancel do overlay do topo (ou fecha direto se a ação não está disponível).
    public func escapePressed() {
        guard let entry = top else { return }
        if let cancel = entry.spec.cancelAction, performAction(cancel) { return }
        dismiss(.escape)
    }

    /// Clique no scrim: só fecha overlays sem dados digitados (02 §12.17, regra 7).
    public func scrimClicked() {
        guard let entry = top, entry.spec.dismissOnScrim() else { return }
        if let cancel = entry.spec.cancelAction, performAction(cancel) { return }
        dismiss(.scrim)
    }

    func setCardFrame(_ id: UUID, _ frame: CGRect) { cardFrames[id] = frame }

    // MARK: Tempo

    private func scheduleRemoval(of id: UUID) {
        let wait = Self.exitWait()
        if wait <= 0 {
            finishRemoval(id)
            return
        }
        pendingRemovals[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.finishRemoval(id)
        }
    }

    private func finishRemoval(_ id: UUID) {
        pendingRemovals[id] = nil
        stack.removeAll { $0.id == id }
        cardFrames[id] = nil
        record("M-102 end")
    }

    private func scheduleOpenEvents() {
        let scale = Self.durationScale()
        guard let scale else {
            record("M-101 settled")
            record("M-101 end")
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(OverlayMotion.enterDuration * scale))
            self?.record("M-101 settled")
            try? await Task.sleep(for: .seconds(OverlayMotion.endTime * scale - OverlayMotion.enterDuration * scale))
            self?.record("M-101 end")
        }
    }

    /// Duração real da saída sob a política de motion (0 = sem animação).
    static func exitWait() -> Double {
        switch MotionPolicy.shared.resolution {
        case .none: 0
        case .crossfade(let d): d
        case .normal(let scale): OverlayMotion.exitDuration * scale
        }
    }

    /// Escala de duração da entrada; `nil` = instantâneo.
    static func durationScale() -> Double? {
        switch MotionPolicy.shared.resolution {
        case .none: nil
        case .crossfade: 1
        case .normal(let scale): scale
        }
    }

    private func record(_ name: String) {
        events.append(OverlayMotionEvent(name: name, time: ProcessInfo.processInfo.systemUptime))
        if events.count > 256 { events.removeFirst(events.count - 256) }
    }
}

/// Foco do overlay (02 §12.17): guarda o first responder ao abrir, prende o foco no overlay e devolve ao fechar.
@MainActor
public final class OverlayFocusCoordinator {
    public weak var window: NSWindow?
    public weak var hostView: NSView?
    private weak var saved: NSResponder?

    public init() {}

    public var savedResponder: NSResponder? { saved }

    /// Guarda o first responder atual e leva o foco ao overlay.
    public func capture() {
        guard let window else { return }
        let current = window.firstResponder
        if let host = hostView, let view = current as? NSView, view === host || view.isDescendant(of: host) {
            // Já estava dentro do overlay (reabertura): não sobrescreve o alvo guardado.
        } else {
            saved = current
        }
        focusOverlay()
    }

    public func focusOverlay() {
        guard let window, let hostView else { return }
        window.makeFirstResponder(hostView)
    }

    /// Devolve o first responder guardado (o terminal volta a receber teclas).
    public func restore() {
        guard let window else { return }
        let target = saved
        saved = nil
        if let target, window.makeFirstResponder(target) { return }
        window.makeFirstResponder(window.contentView)
    }
}
