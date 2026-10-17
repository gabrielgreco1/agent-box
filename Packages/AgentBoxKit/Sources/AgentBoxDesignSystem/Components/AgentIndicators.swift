import AgentBoxProtocol
import SwiftUI

/// Glifo do indicador de estado (02 §2.6 agente, §2.7 processo). Na Fatia 1 (sem hooks) o agente vivo é `unknown`
/// e o resto vem do estado do processo.
public enum DSIndicatorGlyph: Equatable, Sendable {
    case none
    /// `launching`, ignição e linha pendente: spinner neutro.
    case spinner
    /// Agente vivo sem hooks (`unknown`, "Status unavailable"): círculo tracejado âmbar.
    case unknown
    /// Bolinha de estado de processo (`exited`, `failed`, `interrupted`...).
    case dot(DSRGBA)
    /// Falha de criação (linha pendente com erro): `AlertCircle` `destructive`.
    case alert
}

/// Caixa do indicador (02 §2.6): `sm` 10 · `md` 12 · `lg` 16.
public enum DSIndicatorSize: Sendable {
    case sm, md, lg

    public var box: CGFloat {
        switch self {
        case .sm: 10
        case .md: 12
        case .lg: 16
        }
    }
    public var dot: CGFloat {
        switch self {
        case .sm: 6
        case .md: 8
        case .lg: 10
        }
    }
    var stroke: CGFloat { self == .sm ? MotionTokens.Stroke.liveBorder : MotionTokens.Stroke.ring }
}

/// `AgentStateIndicator` (02 §12.5). Não é focável sozinho: o rótulo entra no da linha que o contém.
public struct DSAgentIndicator: View {
    private let glyph: DSIndicatorGlyph
    private let size: DSIndicatorSize

    public init(_ glyph: DSIndicatorGlyph, size: DSIndicatorSize = .md) {
        self.glyph = glyph
        self.size = size
    }

    public var body: some View {
        ZStack {
            switch glyph {
            case .none:
                Color.clear
            case .spinner:
                DSSpinner(size: size.box, delayed: false)
            case .unknown:
                Circle()
                    .strokeBorder(DS.Color.agentUnknown, style: StrokeStyle(lineWidth: size.stroke * 0.75, dash: [size.box / 4, size.box / 5]))
                    .frame(width: size.box - size.stroke, height: size.box - size.stroke)
            case .dot(let color):
                Circle().fill(color.color).frame(width: size.dot, height: size.dot)
            case .alert:
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: size.box))
                    .foregroundStyle(DS.Color.destructive)
            }
        }
        .frame(width: size.box, height: size.box)
        .accessibilityHidden(true)
    }
}

/// `AgentLogo` (02 §12.6). Os PDFs oficiais ainda não estão no repositório: símbolos do sistema no lugar.
/// Claude mantém `#D97757`; os demais são template.
public struct DSAgentLogo: View {
    private let provider: TerminalProvider
    private let size: CGFloat
    private let dimmed: Bool

    public init(_ provider: TerminalProvider, size: CGFloat = 13, dimmed: Bool = false) {
        self.provider = provider
        self.size = size
        self.dimmed = dimmed
    }

    private var symbol: String {
        switch provider {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .opencode: "curlybraces"
        case .shell: "terminal"
        case .custom: "gearshape"
        }
    }

    private var tint: DSRGBA {
        switch provider {
        case .claude: DSRGBA(hex: 0xD97757)
        case .shell, .custom: DS.ColorSpec.textSecondary
        case .codex, .opencode: DS.ColorSpec.textPrimary
        }
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size - 1, weight: provider == .claude ? .bold : .regular))
            .foregroundStyle(tint.color)
            .opacity(dimmed ? 0.7 : 1)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
