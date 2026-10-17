import AgentBoxDesignSystem
import SwiftUI

/// Medidores do módulo Insights. Linguagem visual única: marcas radiais/verticais ("tick marks") acesas até o valor,
/// como um instrumento. Cor só diz estado (02 §1.5): neutro até 75%, `warning` até 90%, `destructive` acima.
/// Animações são one-shots com tokens de 04 (`twEaseOut`, contadores e barras); nenhum loop infinito (04 R5).

nonisolated enum InsightsMetrics {
    static let ringSize: CGFloat = 112
    static let ringSizeCompact: CGFloat = 64
    static let ringTicks = 54
    static let ringSweep: Double = 270
    static let ringTickLength: CGFloat = 7
    static let ringTickWidth: CGFloat = 2
    static let barTicks = 56
    static let barHeight: CGFloat = 14
    static let heatCell: CGFloat = 10
    static let sparkHeight: CGFloat = 40
    static let coreBarHeight: CGFloat = 26
    static let compactWidth: CGFloat = 250
    static let rowBarHeight: CGFloat = 2
}

enum InsightsTone {
    /// Cor da parte acesa do medidor para uma fração de uso.
    static func color(for fraction: Double) -> Color {
        if fraction >= 0.9 { return DS.Color.destructive }
        if fraction >= 0.75 { return DS.Color.warning }
        return DS.Color.textPrimary
    }
}

// MARK: - Valor animado

/// Entrega ao conteúdo o valor "mostrado": começa em 0 e vai ao alvo com `twEaseOut` (contadores e barras de 04).
/// Reduce Motion / modo instantâneo mostram o alvo direto, sem estado intermediário.
struct AnimatedValue<Content: View>: View {
    let value: Double
    var duration: Double = MotionTokens.Duration.ripple
    @ViewBuilder let content: (Double) -> Content
    @State private var shown: Double = 0

    var body: some View {
        let policy = MotionPolicy.shared
        let animates: Bool = { if case .normal = policy.resolution { return true } else { return false } }()
        content(animates ? shown : value)
            .animation(policy.animation(MotionTokens.Easing.twEaseOut, duration), value: shown)
            .onAppear { shown = value }
            .onChange(of: value) { _, new in shown = new }
    }
}

/// Texto numérico cujo valor é interpolado pelo SwiftUI durante a animação (contagem).
struct CountingText: View, Animatable {
    var value: Double
    let format: @Sendable (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: format(value)).monospacedDigit()
    }
}

/// Número com contagem animada: `AnimatedNumber(value: 0.31) { InsightsFormat.percent($0) }`.
struct AnimatedNumber: View {
    let value: Double
    let format: @Sendable (Double) -> String

    var body: some View {
        AnimatedValue(value: value) { CountingText(value: $0, format: format) }
    }
}

// MARK: - Anel de marcas

/// Marcas radiais ao longo de 270° (do canto inferior esquerdo ao inferior direito). `lit` acende as primeiras marcas.
struct RingTicks: Shape {
    var count: Int = InsightsMetrics.ringTicks
    var lit: Double = 1  // 0…1; animável
    var tickLength: CGFloat = InsightsMetrics.ringTickLength

    var animatableData: Double {
        get { lit }
        set { lit = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let litCount = lit >= 1 ? count : (lit <= 0 ? 0 : Int((lit * Double(count)).rounded(.up)))
        for i in 0..<litCount {
            let t = count > 1 ? Double(i) / Double(count - 1) : 0
            let theta = (135 + t * InsightsMetrics.ringSweep) * .pi / 180
            let c = CGFloat(cos(theta)), s = CGFloat(sin(theta))
            path.move(to: CGPoint(x: center.x + c * (radius - tickLength), y: center.y + s * (radius - tickLength)))
            path.addLine(to: CGPoint(x: center.x + c * radius, y: center.y + s * radius))
        }
        return path
    }
}

/// Medidor circular de uma janela de limite. Real = marcas sólidas; estimado = marcas a 55% e selo `est.`.
struct RingMeter: View {
    let fraction: Double?
    /// Fração do tempo da janela já decorrida: marcador de ritmo (cursor externo). `nil` = sem marcador.
    var elapsed: Double?
    var estimated: Bool = false
    var caption: String
    var compact: Bool = false

    var body: some View {
        let size = compact ? InsightsMetrics.ringSizeCompact : InsightsMetrics.ringSize
        let tick = compact ? InsightsMetrics.ringTickLength * 0.7 : InsightsMetrics.ringTickLength
        ZStack {
            RingTicks(lit: 1, tickLength: tick)
                .stroke(DS.Color.fg10, style: StrokeStyle(lineWidth: InsightsMetrics.ringTickWidth, lineCap: .butt))
            if let fraction {
                AnimatedValue(value: min(1, max(0, fraction))) { shown in
                    RingTicks(lit: shown, tickLength: tick)
                        .stroke(InsightsTone.color(for: fraction).opacity(estimated ? 0.55 : 1),
                                style: StrokeStyle(lineWidth: InsightsMetrics.ringTickWidth, lineCap: .butt))
                }
            }
            if let elapsed { PaceCaret(position: elapsed, size: size) }
            VStack(spacing: DS.Space.s0_5) {
                if let fraction {
                    AnimatedNumber(value: fraction * 100) { "\(Int($0.rounded()))%" }
                        .dsFont(compact ? DS.Font.control : DS.Font.display)
                        .foregroundStyle(DS.Color.textPrimary)
                } else {
                    Text(verbatim: "–")
                        .dsFont(compact ? DS.Font.control : DS.Font.display)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                HStack(spacing: DS.Space.s1) {
                    Text(verbatim: caption).dsFont(DS.Font.micro).foregroundStyle(DS.Color.textSecondary)
                    if estimated && !compact { Text("est.").dsFont(DS.Font.micro).foregroundStyle(DS.Color.textTertiary) }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// Cursor de ritmo: marca fina fora do anel na posição do tempo decorrido.
struct PaceCaret: View {
    let position: Double
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let radius = min(canvas.width, canvas.height) / 2
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let theta = (135 + min(1, max(0, position)) * InsightsMetrics.ringSweep) * .pi / 180
            let c = CGFloat(cos(theta)), s = CGFloat(sin(theta))
            var p = Path()
            p.move(to: CGPoint(x: center.x + c * (radius - InsightsMetrics.ringTickLength - DS.Space.s1), y: center.y + s * (radius - InsightsMetrics.ringTickLength - DS.Space.s1)))
            p.addLine(to: CGPoint(x: center.x + c * (radius + DS.Space.s0_5), y: center.y + s * (radius + DS.Space.s0_5)))
            context.stroke(p, with: .color(DS.Color.textSecondary), style: StrokeStyle(lineWidth: MotionTokens.Stroke.liveBorder, lineCap: .round))
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

// MARK: - Barra de marcas

/// Marcas verticais acesas até o valor; marcas mais altas a cada `majorEvery`. Usada na janela de 7 dias (um dia = 8 marcas).
struct BarTicks: Shape {
    var count: Int = InsightsMetrics.barTicks
    var lit: Double = 1
    var majorEvery: Int = 8
    var onlyLit = true

    var animatableData: Double {
        get { lit }
        set { lit = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.width / CGFloat(count)
        let litCount = lit >= 1 ? count : (lit <= 0 ? 0 : Int((lit * Double(count)).rounded(.up)))
        let end = onlyLit ? litCount : count
        for i in 0..<end {
            let x = rect.minX + step * (CGFloat(i) + 0.5)
            let major = i % majorEvery == 0
            let h = major ? rect.height : rect.height * 0.7
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY - h))
        }
        return path
    }
}

struct TickBar: View {
    let fraction: Double?
    var elapsed: Double?
    var estimated = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            BarTicks(lit: 1, onlyLit: false)
                .stroke(DS.Color.fg10, style: StrokeStyle(lineWidth: InsightsMetrics.ringTickWidth, lineCap: .butt))
            if let fraction {
                AnimatedValue(value: min(1, max(0, fraction))) { shown in
                    BarTicks(lit: shown)
                        .stroke(InsightsTone.color(for: fraction).opacity(estimated ? 0.55 : 1),
                                style: StrokeStyle(lineWidth: InsightsMetrics.ringTickWidth, lineCap: .butt))
                }
            }
            if let elapsed {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(DS.Color.textSecondary)
                        .frame(width: MotionTokens.Stroke.liveBorder, height: InsightsMetrics.barHeight + DS.Space.s1)
                        .offset(x: proxy.size.width * min(1, max(0, elapsed)) - MotionTokens.Stroke.liveBorder / 2, y: -DS.Space.s0_5)
                }
            }
        }
        .frame(height: InsightsMetrics.barHeight)
    }
}
