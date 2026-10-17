import AgentBoxDesignSystem
import AgentBoxProtocol
import AppKit
import Observation
import SwiftUI

public struct ToastAction: Equatable, Sendable {
    public let action: ActionID
    public let title: String

    public init(_ action: ActionID, title: String) {
        self.action = action
        self.title = title
    }
}

public struct ToastItem: Identifiable, Equatable {
    public let id = UUID()
    public let kind: DSToastKind
    public let title: String
    public let detail: String?
    public let action: ToastAction?
    /// `nil` = fica até terminar (progresso).
    public let duration: Double?
    /// Barra de tempo linear do Undo (M-110): largura 1 → 0 na duração do toast.
    public let timeBar: Bool
}

/// Toasts (02 §12.19, M-110). Canto inferior direito, até 3 visíveis (o resto vira "+N more"); hover pausa o tempo.
/// Duração: 4 s informativo, 8 s com Undo, 60 s erro, progresso até terminar.
@MainActor @Observable
public final class ToastCenter {
    public static let maxVisible = 3

    public private(set) var items: [ToastItem] = []
    /// Fração restante (1 → 0) congelada enquanto o hover pausa o toast.
    public private(set) var paused: Set<UUID> = []
    @ObservationIgnored public private(set) var cardFrames: [UUID: CGRect] = [:]
    @ObservationIgnored private var deadlines: [UUID: Date] = [:]
    @ObservationIgnored private var remaining: [UUID: Double] = [:]
    @ObservationIgnored private var timers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored public var announce: @MainActor (String, Bool) -> Void = { text, urgent in
        var s = AttributedString(text)
        if urgent { s.accessibilitySpeechAnnouncementPriority = .high }
        AccessibilityNotification.Announcement(s).post()
    }

    public init() {}

    public static func defaultDuration(kind: DSToastKind, hasUndo: Bool) -> Double? {
        switch kind {
        case .error: 60
        case .progress: nil
        default: hasUndo ? 8 : 4
        }
    }

    public var visible: [ToastItem] { Array(items.suffix(Self.maxVisible)) }
    public var overflow: Int { max(0, items.count - Self.maxVisible) }

    @discardableResult
    public func show(
        kind: DSToastKind, title: String, detail: String? = nil, action: ToastAction? = nil, undo: Bool = false,
        duration: Double?? = nil
    ) -> UUID {
        let seconds: Double? = duration ?? Self.defaultDuration(kind: kind, hasUndo: undo)
        let item = ToastItem(kind: kind, title: title, detail: detail, action: action, duration: seconds, timeBar: undo && seconds != nil)
        withAnimation(MotionPolicy.shared.animation(MotionTokens.Easing.standard, MotionTokens.Duration.base)) {
            items.append(item)
        }
        announce([title, detail].compactMap { $0 }.joined(separator: ". "), kind == .error)
        if let seconds { startTimer(item.id, seconds) }
        return item.id
    }

    public func dismiss(_ id: UUID) {
        timers[id]?.cancel()
        timers[id] = nil
        deadlines[id] = nil
        remaining[id] = nil
        paused.remove(id)
        withAnimation(MotionPolicy.shared.animation(MotionTokens.Easing.exit, MotionTokens.Duration.fast)) {
            items.removeAll { $0.id == id }
        }
        cardFrames[id] = nil
    }

    /// Hover: congela o tempo restante.
    public func pause(_ id: UUID) {
        guard let deadline = deadlines[id], !paused.contains(id) else { return }
        remaining[id] = max(0, deadline.timeIntervalSinceNow)
        timers[id]?.cancel()
        timers[id] = nil
        paused.insert(id)
    }

    public func resume(_ id: UUID) {
        guard paused.contains(id), let left = remaining[id] else { return }
        paused.remove(id)
        startTimer(id, left)
    }

    /// Fração restante (1 → 0) para a barra de tempo.
    public func timeFraction(_ id: UUID, at date: Date = Date()) -> Double? {
        guard let item = items.first(where: { $0.id == id }), let total = item.duration, total > 0 else { return nil }
        if let left = remaining[id], paused.contains(id) { return left / total }
        guard let deadline = deadlines[id] else { return 1 }
        return max(0, min(1, deadline.timeIntervalSince(date) / total))
    }

    func setCardFrame(_ id: UUID, _ frame: CGRect) { cardFrames[id] = frame }

    private func startTimer(_ id: UUID, _ seconds: Double) {
        deadlines[id] = Date().addingTimeInterval(seconds)
        timers[id]?.cancel()
        timers[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }
}

/// Pilha de toasts no canto inferior direito, 16 da direita e 40 acima do rodapé (02 §12.19).
struct ToastStack: View {
    let toasts: ToastCenter

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.Space.s2) {
            if toasts.overflow > 0 {
                Text(verbatim: String(localized: "+\(toasts.overflow) more", bundle: .module))
                    .dsFont(DS.Font.small)
                    .foregroundStyle(DS.Color.textSecondary)
                    .accessibilityHidden(true)
            }
            ForEach(toasts.visible) { item in
                ToastView(item: item, toasts: toasts)
                    .transition(Self.transition)
            }
        }
        .padding(.trailing, DS.Space.s4)
        .padding(.bottom, DS.Space.s10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(!toasts.items.isEmpty)
    }

    /// M-110: entrada y +12 → 0 com fade; saída só fade. Reduce Motion: só fade.
    static var transition: AnyTransition {
        if MotionPolicy.shared.reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: MotionTokens.Distance.medium)),
            removal: .opacity)
    }
}

private struct ToastView: View {
    let item: ToastItem
    let toasts: ToastCenter

    var body: some View {
        Group {
            if item.timeBar {
                // Barra de tempo linear do Undo: 15 quadros/s bastam para uma barra de 1 pt (04 R6).
                TimelineView(.animation(minimumInterval: 1.0 / MotionTokens.Loop.spinner.fps)) { context in
                    card(fraction: toasts.timeFraction(item.id, at: context.date))
                }
            } else {
                card(fraction: nil)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { toasts.setCardFrame(item.id, $0) }
        .onHover { inside in
            if inside { toasts.pause(item.id) } else { toasts.resume(item.id) }
        }
        .a11y(.toast(item.kind.rawValue), kind: "toast", label: item.title)
        .accessibilityElement(children: .contain)
    }

    private func card(fraction: Double?) -> some View {
        DSToastCard(kind: item.kind, title: item.title, detail: item.detail, timeFraction: fraction) {
            if let action = item.action {
                ActionButton(action.action, id: .toastAction(item.kind.rawValue)) {
                    Text(verbatim: action.title)
                }
                .buttonStyle(DSButtonStyle(.ghost, .xs))
            }
        }
    }
}
