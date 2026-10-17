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

/// Logos oficiais de agente (02 §2.10). Arquivos em `Resources/AgentLogos/` vindos de `legacy/design/assets/brands/`
/// (proveniência em `sources.json`, copiada junto). Claude é monocromático: template em `#D97757`.
/// OpenCode é monocromático após remover o fundo opaco do arquivo: template em `textPrimary`.
/// Codex é o ícone de app colorido e fica com as cores originais (template o achataria numa silhueta).
/// Shell usa o SF Symbol `terminal`; `custom` mantém `gearshape` (fora da lista da spec).
@MainActor
enum DSAgentLogoImages {
    /// Carrega o `@3x` (60 px, cobre até 20 pt). Retorna nil só se o recurso faltar no bundle.
    static func image(for provider: TerminalProvider) -> NSImage? {
        guard let name = name(for: provider), let url = fileURL(name, scale: 3) else { return nil }
        return NSImage(contentsOf: url)
    }

    static func fileURL(_ name: String, scale: Int) -> URL? {
        Bundle.module.url(forResource: "\(name)@\(scale)x", withExtension: "png", subdirectory: "AgentLogos")
    }

    /// `sources.json` (proveniência dos logos, copiada junto).
    static var provenanceURL: URL? {
        Bundle.module.url(forResource: "sources", withExtension: "json", subdirectory: "AgentLogos")
    }

    static func name(for provider: TerminalProvider) -> String? {
        switch provider {
        case .claude: "claude"
        case .codex: "codex"
        case .opencode: "opencode"
        case .shell, .custom: nil
        }
    }
}

public struct DSAgentLogo: View {
    private let provider: TerminalProvider
    private let size: CGFloat
    private let dimmed: Bool

    public init(_ provider: TerminalProvider, size: CGFloat = 13, dimmed: Bool = false) {
        self.provider = provider
        self.size = size
        self.dimmed = dimmed
    }

    private var tint: DSRGBA {
        switch provider {
        case .claude: DSRGBA(hex: 0xD97757)
        case .opencode: DS.ColorSpec.textPrimary
        case .codex, .shell, .custom: DS.ColorSpec.textSecondary
        }
    }

    public var body: some View {
        logo
            .opacity(dimmed ? 0.7 : 1)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var logo: some View {
        switch provider {
        case .shell:
            Image(systemName: "terminal")
                .font(.system(size: size - 1))
                .foregroundStyle(tint.color)
        case .custom:
            Image(systemName: "gearshape")
                .font(.system(size: size - 1))
                .foregroundStyle(tint.color)
        case .claude, .codex, .opencode:
            if let nsImage = DSAgentLogoImages.image(for: provider) {
                let template = provider != .codex
                Image(nsImage: nsImage)
                    .renderingMode(template ? .template : .original)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(tint.color)
            } else {
                // Recurso ausente no bundle: teste `AgentLogoTests` falha antes disso chegar à UI.
                Image(systemName: "questionmark.square.dashed")
                    .font(.system(size: size - 1))
                    .foregroundStyle(tint.color)
            }
        }
    }
}
