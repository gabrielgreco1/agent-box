import AgentBoxProtocol
import SwiftUI

/// Único `Button` permitido pela lint de UI: dispara `ActionRegistry.perform` (08 AR-805).
/// Se a fatia da ação ainda não existe, não renderiza nada (AC-T28, nunca "desabilitado").
/// Desabilitado só por pré-condição real, com o motivo no tooltip.
public struct ActionButton<Label: View>: View {
    private let action: ActionID
    private let a11yID: A11yID
    private let label: Label
    @Environment(\.actionRegistry) private var registry

    public init(_ action: ActionID, id: A11yID, @ViewBuilder label: () -> Label) {
        self.action = action
        self.a11yID = id
        self.label = label()
    }

    public var body: some View {
        if let registry, registry.isRendered(action) {
            let availability = registry.availability(of: action)
            Button {
                Task { _ = try? await registry.perform(action, .press) }
            } label: {
                label
            }
            .disabled(!availability.isEnabled)
            .help(Self.tooltip(availability))
            .a11y(a11yID, kind: "button", label: action.spec.label, action: action)
        }
    }

    private static func tooltip(_ availability: ActionAvailability) -> String {
        if case .disabled(let reason) = availability { return reason }
        return ""
    }
}

/// Renderiza o conteúdo só se a fatia já foi entregue (feature flag por fatia, AC-T28).
public struct SliceGate<Content: View>: View {
    private let slice: ReleaseSlice
    private let flags: SliceFlags
    private let content: Content

    public init(_ slice: ReleaseSlice, flags: SliceFlags, @ViewBuilder content: () -> Content) {
        self.slice = slice
        self.flags = flags
        self.content = content()
    }

    public var body: some View {
        if flags.isEnabled(slice) { content }
    }
}
