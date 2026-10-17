import AgentBoxDesignSystem
import AgentBoxProtocol
import SwiftUI

// Controles interativos do DS ligados ao registro de ações (02 §12, 08 AR-805). Cada um dispara
// `ActionRegistry.perform` por `ActionButton`; o visual vem de AgentBoxDesignSystem/Components.

/// Botão do DS (02 §12.1). `loading` troca o rótulo por spinner + rótulo de progresso mantendo a largura.
public struct DSButton: View {
    private let action: ActionID
    private let id: A11yID?
    private let title: LocalizedStringKey
    private let variant: DSButtonVariant
    private let size: DSButtonSize
    private let symbol: String?
    private let keycap: String?
    private let loading: LocalizedStringKey?
    private let argument: ActionArgument

    public init(
        _ action: ActionID, id: A11yID? = nil, _ title: LocalizedStringKey, variant: DSButtonVariant = .outline,
        size: DSButtonSize = .sm, symbol: String? = nil, keycap: String? = nil, loading: LocalizedStringKey? = nil,
        argument: ActionArgument = .press
    ) {
        self.action = action
        self.id = id
        self.title = title
        self.variant = variant
        self.size = size
        self.symbol = symbol
        self.keycap = keycap
        self.loading = loading
        self.argument = argument
    }

    public var body: some View {
        ActionButton(action, id: id, argument: argument) {
            ZStack {
                label.opacity(loading == nil ? 1 : 0)
                if let loading {
                    HStack(spacing: DS.Space.s1_5) {
                        DSSpinner(size: size.icon - DS.Space.s0_5, delayed: false)
                        Text(loading, bundle: .module)
                    }
                }
            }
        }
        .buttonStyle(DSButtonStyle(variant, size, hasIcon: symbol != nil))
        .disabled(loading != nil)
    }

    private var label: some View {
        HStack(spacing: DS.Space.s1_5) {
            if let symbol { Image(systemName: symbol).font(.system(size: size.icon)) }
            Text(title, bundle: .module)
            if let keycap { Keycaps(keycap).opacity(variant == .primary ? 0.8 : 1) }
        }
    }
}

/// Botão de ícone do DS (02 §12.2). O nome é o rótulo de acessibilidade e o tooltip.
public struct DSIconButton: View {
    private let action: ActionID
    private let id: A11yID?
    private let symbol: String
    private let name: String
    private let variant: DSIconButtonVariant
    private let destructive: Bool
    private let active: Bool

    public init(
        _ action: ActionID, id: A11yID? = nil, symbol: String, name: String, variant: DSIconButtonVariant = .header,
        destructive: Bool = false, active: Bool = false
    ) {
        self.action = action
        self.id = id
        self.symbol = symbol
        self.name = name
        self.variant = variant
        self.destructive = destructive
        self.active = active
    }

    public var body: some View {
        ActionButton(action, id: id, tooltip: name) {
            Image(systemName: symbol)
        }
        .buttonStyle(DSIconButtonStyle(variant, destructive: destructive, active: active))
        .accessibilityLabel(Text(verbatim: name))
    }
}

/// Controle segmentado (02 §12.12): `Picker(.segmented)` do sistema é proibido. Cada segmento dispara `action` com
/// `select(<valor>)`; ←/→ movem a seleção com o controle focado; o fundo do ativo desliza (M-113, `snappy`).
public struct DSSegmented: View {
    public struct Option: Identifiable, Equatable {
        public let id: String
        public let title: LocalizedStringKey

        public init(_ id: String, _ title: LocalizedStringKey) {
            self.id = id
            self.title = title
        }

        public static func == (lhs: Option, rhs: Option) -> Bool { lhs.id == rhs.id }
    }

    private let options: [Option]
    private let selection: String
    private let action: ActionID
    private let id: A11yID
    @Namespace private var namespace
    @Environment(\.actionRegistry) private var registry

    public init(_ options: [Option], selection: String, action: ActionID, id: A11yID) {
        self.options = options
        self.selection = selection
        self.action = action
        self.id = id
    }

    public var body: some View {
        HStack(spacing: .zero) {
            ForEach(options) { option in
                let active = option.id == selection
                ActionButton(action, argument: .select(option.id)) {
                    Text(option.title, bundle: .module)
                }
                .buttonStyle(DSSegmentStyle(active: active))
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .fill(DS.Color.accent)
                            .matchedGeometryEffect(id: "segment-indicator", in: namespace)
                    }
                }
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(DSMetrics.segmentedPadding)
        .frame(height: DSMetrics.segmentedHeight)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Color.secondary))
        .animation(MotionPolicy.shared.animation(MotionTokens.Springs.snappy), value: selection)
        .fixedSize()
        .focusable()
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .a11y(id, kind: "segmented", value: selection)
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard let registry, let index = options.firstIndex(where: { $0.id == selection }) else { return .ignored }
        let next = index + delta
        guard options.indices.contains(next) else { return .handled }
        let target = options[next].id
        Task { _ = try? await registry.perform(action, .select(target)) }
        return .handled
    }
}

/// Switch (02 §12.13): rótulo à esquerda, descrição opcional; clicar no rótulo também alterna.
public struct DSSwitch: View {
    private let isOn: Bool
    private let action: ActionID
    private let id: A11yID
    private let title: LocalizedStringKey

    public init(isOn: Bool, action: ActionID, id: A11yID, _ title: LocalizedStringKey) {
        self.isOn = isOn
        self.action = action
        self.id = id
        self.title = title
    }

    public var body: some View {
        ActionButton(action, id: id, argument: .set(isOn ? "off" : "on")) {
            HStack(spacing: DS.Space.s2) {
                DSSwitchVisual(isOn: isOn)
                Text(title, bundle: .module)
                    .dsFont(DS.Font.body)
                    .foregroundStyle(DS.Color.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(verbatim: isOn ? "on" : "off"))
        .accessibilityAddTraits(.isToggle)
    }
}

/// Checkbox (02 §12.13): 14×14, rótulo `body`.
public struct DSCheckbox: View {
    private let isOn: Bool
    private let action: ActionID
    private let id: A11yID
    private let title: LocalizedStringKey

    public init(isOn: Bool, action: ActionID, id: A11yID, _ title: LocalizedStringKey) {
        self.isOn = isOn
        self.action = action
        self.id = id
        self.title = title
    }

    public var body: some View {
        ActionButton(action, id: id, argument: .set(isOn ? "off" : "on")) {
            HStack(spacing: DS.Space.s2) {
                DSCheckboxVisual(isOn: isOn)
                Text(title, bundle: .module)
                    .dsFont(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(verbatim: isOn ? "checked" : "unchecked"))
        .accessibilityAddTraits(.isToggle)
    }
}

/// Linha de lista genérica (02 §12.8).
public struct DSListRow<Content: View>: View {
    private let action: ActionID
    private let id: A11yID?
    private let selected: Bool
    private let argument: ActionArgument
    private let content: Content

    public init(
        _ action: ActionID, id: A11yID? = nil, selected: Bool = false, argument: ActionArgument = .press,
        @ViewBuilder content: () -> Content
    ) {
        self.action = action
        self.id = id
        self.selected = selected
        self.argument = argument
        self.content = content()
    }

    public var body: some View {
        ActionButton(action, id: id, argument: argument) { content }
            .buttonStyle(DSListRowStyle(selected: selected))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Campo de texto (02 §12.10): fundo `input/30`, borda `input`, foco = borda `ring` + anel; inválido = `destructive` + mensagem.
/// Edições passam por `action` (`set(<texto>)`) quando informada. Enter durante composição IME é do `TextField` do sistema.
public struct DSTextField: View {
    private let placeholder: LocalizedStringKey
    @Binding private var text: String
    private let id: A11yID
    private let action: ActionID?
    private let error: String?
    private let multiline: Bool
    private let autofocus: Bool
    @FocusState private var focused: Bool
    @Environment(\.actionRegistry) private var registry
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ placeholder: LocalizedStringKey, text: Binding<String>, id: A11yID, action: ActionID? = nil, error: String? = nil,
        multiline: Bool = false, autofocus: Bool = false
    ) {
        self.placeholder = placeholder
        self._text = text
        self.id = id
        self.action = action
        self.error = error
        self.multiline = multiline
        self.autofocus = autofocus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            field
                .textFieldStyle(.plain)
                .dsFont(DS.Font.input)
                .foregroundStyle(DS.Color.textPrimary)
                .focused($focused)
                .padding(.vertical, multiline ? DS.Space.s2 : .zero)
                .frame(minHeight: multiline ? DSMetrics.textareaMinHeight : nil, alignment: .topLeading)
                .dsFieldChrome(focused: focused, invalid: error != nil, disabled: !isEnabled, height: multiline ? nil : DSMetrics.fieldHeight)
                .onChange(of: text) { _, new in
                    guard let action, let registry else { return }
                    Task { _ = try? await registry.perform(action, .set(new)) }
                }
                .task {
                    guard autofocus else { return }
                    await Task.yield()
                    focused = true
                }
                .a11y(id, kind: multiline ? "textarea" : "textfield", value: text, action: action)
            if let error {
                HStack(spacing: DS.Space.s1) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: DS.Space.s3))
                    Text(verbatim: error).dsFont(DS.Font.small)
                }
                .foregroundStyle(DS.Color.destructive)
            }
        }
    }

    /// O placeholder é desenhado por nós (o `prompt` do sistema ignora a cor `textQuaternary`).
    @ViewBuilder private var field: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder, bundle: .module)
                    .foregroundStyle(DS.Color.textQuaternary)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if multiline {
                TextField(text: $text, axis: .vertical) { EmptyView() }.lineLimit(3...10)
            } else {
                TextField(text: $text) { EmptyView() }
            }
        }
    }
}
