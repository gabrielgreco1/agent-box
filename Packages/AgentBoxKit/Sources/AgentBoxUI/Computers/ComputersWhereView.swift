import AgentBoxCore
import AgentBoxDesignSystem
import AgentBoxProtocol
import SwiftUI

/// Medidas da escolha "onde os computadores rodam" (página Computers, BK-12).
enum WhereMetrics {
    static let column: CGFloat = 720
    static let heroIcon: CGFloat = 52
    static let choiceHeight: CGFloat = 156
    static let choiceIcon: CGFloat = 40
    static let miniLogo: CGFloat = 16
    static let providerTileHeight: CGFloat = 92
    static let providerLogo: CGFloat = 26
    static let regionChipHeight: CGFloat = 44
    static let stepperButton: CGFloat = 24
    static let stepperValue: CGFloat = 76
    static let ringWidth: CGFloat = 1.5
    static let compactBar: CGFloat = 44
    static let pulse: CGFloat = 7
    static let stagger: Double = 0.04
}

/// "Where do agents' computers run?" (BK-12, P27): a escolha principal é local (Docker no Mac) ou a nuvem do próprio usuário. Com
/// computadores na lista vira uma faixa compacta que abre a escolha inteira em "Change".
struct ComputersWhereView: View {
    let settings: SettingsModel
    /// Página já tem computadores: mostra a faixa compacta (a escolha abre por cima da tabela).
    let compact: Bool
    @Namespace private var ring

    private var target: AppSettings.ComputerRunTarget { settings.settings.computers.runOn }

    var body: some View {
        if compact {
            VStack(spacing: 0) {
                CompactWhereBar(settings: settings)
                if settings.computersWhereOpen {
                    ScrollView { chooser.padding(.vertical, DS.Space.s6) }
                        .frame(maxHeight: 560)
                        .transition(MotionPolicy.shared.reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    DS.Color.border.frame(height: DSMetrics.hairline)
                }
            }
            .animation(MotionPolicy.shared.animation(MotionTokens.Springs.panel), value: settings.computersWhereOpen)
        } else {
            ScrollView {
                VStack(spacing: DS.Space.s8) {
                    hero
                    chooser
                }
                .padding(.vertical, DS.Space.s10)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var hero: some View {
        VStack(spacing: DS.Space.s2) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.large).fill(DS.Color.secondary)
                RoundedRectangle(cornerRadius: DS.Radius.large).strokeBorder(DS.Color.borderStrong)
                Image(systemName: "display.2").font(.system(size: 22, weight: .medium)).foregroundStyle(DS.Color.textPrimary)
            }
            .frame(width: WhereMetrics.heroIcon, height: WhereMetrics.heroIcon)
            .padding(.bottom, DS.Space.s2)
            Text("Where do agents' computers run?", bundle: .module).dsFont(DS.Font.pageTitle).foregroundStyle(DS.Color.textPrimary)
            Text("Each subagent gets its own computer with a browser, so agents work side by side without touching your Mac.", bundle: .module)
                .dsFont(DS.Font.dialogBody).foregroundStyle(DS.Color.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            HStack(spacing: DS.Space.s3) {
                WhereChoiceCard(target: .local, selected: target == .local, ring: ring) {
                    LocalStatusLine(status: settings.dockerStatus)
                }
                WhereChoiceCard(target: .cloud, selected: target == .cloud, ring: ring) {
                    CloudSummaryLine(settings: settings, selected: target == .cloud)
                }
            }
            .animation(MotionPolicy.shared.animation(MotionTokens.Springs.lively), value: target)
            if target == .cloud {
                CloudSetupView(settings: settings)
                    .transition(MotionPolicy.shared.reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)))
            }
            NewSessionsRow(settings: settings)
        }
        .frame(width: WhereMetrics.column)
        .frame(maxWidth: .infinity)
        .animation(MotionPolicy.shared.animation(MotionTokens.Springs.panel), value: target)
        .a11y(.computersWhere, kind: "container")
    }
}

// MARK: Cards de escolha

private struct WhereChoiceCard<Status: View>: View {
    let target: AppSettings.ComputerRunTarget
    let selected: Bool
    let ring: Namespace.ID
    @ViewBuilder let status: () -> Status
    @State private var hovering = false

    private var title: String {
        target == .local ? String(localized: "This Mac", bundle: .module) : String(localized: "Your cloud", bundle: .module)
    }

    private var detail: String {
        target == .local
            ? String(localized: "Free. Computers run in Docker on this Mac.", bundle: .module)
            : String(localized: "More computers at once and more power, on your own account.", bundle: .module)
    }

    var body: some View {
        ActionButton(.computersRunOn, id: target == .local ? .computersWhereLocal : .computersWhereCloud, argument: .select(target.rawValue)) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(alignment: .top) {
                    icon
                    Spacer(minLength: 0)
                    check
                }
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: title).dsFont(DS.Font.composerTitle).foregroundStyle(DS.Color.textPrimary)
                Text(verbatim: detail).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                status().padding(.top, DS.Space.s1)
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, minHeight: WhereMetrics.choiceHeight, maxHeight: WhereMetrics.choiceHeight, alignment: .topLeading)
            .background(background)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: DS.Radius.large).strokeBorder(DS.Color.textPrimary.opacity(0.85), lineWidth: WhereMetrics.ringWidth)
                        .matchedGeometryEffect(id: "ring", in: ring)
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.large).strokeBorder(hovering ? DS.Color.borderStrong : DS.Color.border)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.large))
            .scaleEffect(hovering && !selected && !MotionPolicy.shared.reduceMotion ? 1.008 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(MotionPolicy.shared.animation(MotionTokens.Springs.snappy), value: hovering)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: DS.Radius.large)
            .fill(
                LinearGradient(
                    colors: selected ? [DS.Color.secondary, DS.Color.chrome] : [hovering ? DS.Color.secondary.opacity(0.6) : DS.Color.chrome, DS.Color.chrome],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    @ViewBuilder private var icon: some View {
        HStack(spacing: -6) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Color.canvas.opacity(0.6))
                RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(DS.Color.border)
                Image(systemName: target == .local ? "laptopcomputer" : "cloud")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(DS.Color.textPrimary)
                    .symbolEffect(.bounce, value: selected)
            }
            .frame(width: WhereMetrics.choiceIcon, height: WhereMetrics.choiceIcon)
            if target == .local {
                badge { DSBrandLogo("docker", size: WhereMetrics.miniLogo - 2, tint: DSRGBA(hex: 0x2496ED).color) }
            } else {
                ForEach(Array(CloudProviderCatalog.all.prefix(3).enumerated()), id: \.element.id) { index, provider in
                    badge { DSBrandLogo(provider.logo, size: WhereMetrics.miniLogo - 4, tint: DSRGBA(hex: provider.brandHex).color) }
                        .zIndex(Double(-index))
                }
            }
        }
    }

    private func badge<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Circle().fill(DS.Color.chrome)
            Circle().strokeBorder(DS.Color.borderStrong)
            content()
        }
        .frame(width: WhereMetrics.miniLogo + 6, height: WhereMetrics.miniLogo + 6)
        .offset(y: WhereMetrics.choiceIcon / 2 - 6)
    }

    private var check: some View {
        ZStack {
            Circle().strokeBorder(selected ? Color.clear : DS.Color.borderStrong, lineWidth: WhereMetrics.ringWidth)
            if selected {
                Circle().fill(DS.Color.primary)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(DS.Color.textOnPrimary)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 18, height: 18)
    }
}

/// Estado do Docker no card "This Mac": ponto vivo quando está pronto, aviso e "Open Docker" quando está parado.
private struct LocalStatusLine: View {
    let status: DockerStatusInfo

    var body: some View {
        HStack(spacing: DS.Space.s1_5) {
            PulseDot(color: status.stopped ? DS.Color.warning : DS.Color.agentDone, pulsing: !status.stopped)
            Text(verbatim: status.stopped ? String(localized: "Docker isn't running", bundle: .module) : status.text)
                .dsFont(DS.Font.small).foregroundStyle(status.stopped ? DS.Color.warning : DS.Color.textTertiary).lineLimit(1)
            if status.stopped {
                DSButton(.dockerStart, id: nil, "Open Docker", variant: .ghost, size: .xs)
            }
        }
    }
}

/// Resumo da nuvem no card: provedor, região e teto quando escolhida; senão, o selo de prévia.
private struct CloudSummaryLine: View {
    let settings: SettingsModel
    let selected: Bool

    var body: some View {
        HStack(spacing: DS.Space.s1_5) {
            PreviewPill()
            if selected {
                let cloud = settings.settings.computers.cloud
                let provider = settings.cloudProvider
                let city = provider.regions.first { $0.id == cloud.region }?.city ?? cloud.region
                Text(verbatim: "\(provider.name) · \(city) · " + String(localized: "up to \(cloud.maxComputers)", bundle: .module))
                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
    }
}

private struct PreviewPill: View {
    var body: some View {
        Text("Preview", bundle: .module)
            .dsFont(DS.Font.micro).foregroundStyle(DS.Color.aiAccent)
            .padding(.horizontal, DS.Space.s1_5).padding(.vertical, DS.Space.s0_5)
            .background(Capsule().fill(DS.Color.aiAccent.opacity(0.12)))
            .overlay(Capsule().strokeBorder(DS.Color.aiAccent.opacity(0.3)))
    }
}

/// Ponto de estado com um anel que pulsa devagar (some com Reduce Motion).
private struct PulseDot: View {
    let color: Color
    let pulsing: Bool
    @State private var expanded = false

    var body: some View {
        ZStack {
            if pulsing, !MotionPolicy.shared.reduceMotion {
                Circle().fill(color.opacity(expanded ? 0 : 0.45)).scaleEffect(expanded ? 2.4 : 1)
            }
            Circle().fill(color)
        }
        .frame(width: WhereMetrics.pulse, height: WhereMetrics.pulse)
        .onAppear {
            guard pulsing, !MotionPolicy.shared.reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { expanded = true }
        }
    }
}

// MARK: Nuvem

/// Provedor, conta, região e tetos. Tudo a um clique; cada linha entra com um pequeno atraso (escalonado).
private struct CloudSetupView: View {
    let settings: SettingsModel
    @State private var shown = false

    private var cloud: AppSettings.Cloud { settings.settings.computers.cloud }
    private var provider: CloudProviderInfo { settings.cloudProvider }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "flask").font(.system(size: 11)).foregroundStyle(DS.Color.aiAccent)
                Text("Cloud computers are in testing. Your choices are saved and used as soon as it ships.", bundle: .module)
                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
            }
            .stagger(0, shown)
            sectionLabel("Provider").stagger(1, shown)
            HStack(spacing: DS.Space.s2) {
                ForEach(CloudProviderCatalog.all) { info in
                    ProviderTile(info: info, selected: info.id == provider.id)
                }
            }
            .stagger(2, shown)
            VStack(spacing: 0) {
                SetupRow(step: 1, title: String(localized: "Account", bundle: .module)) {
                    HStack(spacing: DS.Space.s2) {
                        DSButton(.computersCloudConnect, id: .computersCloudConnect, "Connect \(provider.name)…", variant: .primary, size: .sm)
                        LinkChip(kind: .setup, title: String(localized: "How sign-in works", bundle: .module), provider: provider)
                    }
                } detail: {
                    Text("Sign in through your browser with single sign-on. Racky never sees your password.", bundle: .module)
                }
                divider
                SetupRow(step: 2, title: String(localized: "Region", bundle: .module)) {
                    RegionGrid(provider: provider, selected: cloud.region)
                } detail: {
                    Text("Pick the closest one: the computer's screen streams to you from there.", bundle: .module)
                }
                divider
                SetupRow(step: 3, title: String(localized: "Spending limit", bundle: .module)) {
                    HStack(spacing: DS.Space.s4) {
                        LimitStepper(key: "daily", id: .computersCloudDailyCap, value: "$\(cloud.dailyCapUSD)", unit: String(localized: "per day", bundle: .module))
                        LimitStepper(
                            key: "monthly", id: .computersCloudMonthlyCap, value: "$\(cloud.monthlyCapUSD)", unit: String(localized: "per month", bundle: .module))
                    }
                } detail: {
                    Text("At the limit Racky stops creating computers and shuts down the ones that would go over it.", bundle: .module)
                }
                divider
                SetupRow(step: 4, title: String(localized: "At most", bundle: .module)) {
                    LimitStepper(
                        key: "max", id: .computersCloudMaxComputers, value: "\(cloud.maxComputers)",
                        unit: cloud.maxComputers == 1 ? String(localized: "computer at once", bundle: .module) : String(localized: "computers at once", bundle: .module))
                } detail: {
                    if let hourly = provider.referenceHourlyUSD, let day = CloudProviderCatalog.fullDayUSD(provider: provider, computers: cloud.maxComputers) {
                        Text(verbatim: String(
                            localized: "About \(hourly.formatted(.currency(code: "USD").precision(.fractionLength(2)))) per computer per hour. All of them running all day: \(day.formatted(.currency(code: "USD").precision(.fractionLength(0)))).",
                            bundle: .module))
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: DS.Radius.large).fill(DS.Color.chrome))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.large).strokeBorder(DS.Color.border))
            .stagger(3, shown)
            HStack(spacing: DS.Space.s2) {
                LinkChip(kind: .console, title: String(localized: "\(provider.name) console", bundle: .module), provider: provider)
                LinkChip(kind: .pricing, title: String(localized: "Pricing", bundle: .module), provider: provider)
            }
            .stagger(4, shown)
        }
        .onAppear { shown = true }
    }

    private var divider: some View { DS.Color.border.frame(height: DSMetrics.hairline).padding(.leading, DS.Space.s4 + 28) }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title, bundle: .module).dsFont(DS.Font.sectionLabel).foregroundStyle(DS.Color.textTertiary).padding(.leading, DS.Space.s1)
    }
}

private extension View {
    /// Entrada escalonada: cada bloco sobe 6 pt e aparece um pouco depois do anterior.
    func stagger(_ index: Int, _ shown: Bool) -> some View {
        let reduce = MotionPolicy.shared.reduceMotion
        return opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 6)
            .animation(
                MotionPolicy.shared.animation(MotionTokens.Springs.panel)?.delay(reduce ? 0 : WhereMetrics.stagger * Double(index)), value: shown)
    }
}

private struct ProviderTile: View {
    let info: CloudProviderInfo
    let selected: Bool
    @State private var hovering = false

    private var brand: Color { DSRGBA(hex: info.brandHex).color }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack(alignment: .top) {
                DSBrandLogo(info.logo, size: WhereMetrics.providerLogo, tint: info.available ? brand : DS.Color.textSecondary)
                Spacer(minLength: 0)
                if !info.available {
                    Text("Soon", bundle: .module).dsFont(DS.Font.micro).foregroundStyle(DS.Color.textTertiary)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: info.name).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
            Text(verbatim: info.referenceHourlyUSD.map { "≈ " + $0.formatted(.currency(code: "USD").precision(.fractionLength(2))) + "/h" } ?? " ")
                .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, minHeight: WhereMetrics.providerTileHeight, maxHeight: WhereMetrics.providerTileHeight, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.large).fill(selected ? brand.opacity(0.08) : (hovering ? DS.Color.secondary.opacity(0.6) : DS.Color.chrome)))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.large)
                .strokeBorder(selected ? brand.opacity(0.75) : (hovering ? DS.Color.borderStrong : DS.Color.border), lineWidth: selected ? WhereMetrics.ringWidth : 1))
        .shadow(color: selected ? brand.opacity(0.18) : .clear, radius: 12, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        .opacity(info.available ? 1 : 0.55)

        Group {
            if info.available {
                ActionButton(.computersCloudProvider, id: .computersCloudProvider(info.id), argument: .select(info.id)) { content }
                    .buttonStyle(.plain)
            } else {
                content
                    .dsTooltip(String(localized: "\(info.name) is coming soon.", bundle: .module), shortcut: nil)
                    .a11y(.computersCloudProvider(info.id), kind: "text", label: info.name, value: "soon")
            }
        }
        .onHover { hovering = $0 && info.available }
        .offset(y: hovering && !MotionPolicy.shared.reduceMotion ? -1 : 0)
        .animation(MotionPolicy.shared.animation(MotionTokens.Springs.snappy), value: hovering)
        .animation(MotionPolicy.shared.animation(MotionTokens.Springs.lively), value: selected)
    }
}

private struct SetupRow<Control: View, Detail: View>: View {
    let step: Int
    let title: String
    @ViewBuilder let control: () -> Control
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Text(verbatim: "\(step)")
                .dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(DS.Color.secondary))
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(verbatim: title).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary)
                control()
                detail().dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s4)
    }
}

private struct RegionGrid: View {
    let provider: CloudProviderInfo
    let selected: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 3), spacing: DS.Space.s2) {
            ForEach(provider.regions) { region in
                RegionChip(region: region, selected: region.id == selected)
            }
        }
    }
}

private struct RegionChip: View {
    let region: CloudRegionInfo
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        ActionButton(.computersCloudRegion, id: .computersCloudRegion(region.id), argument: .select(region.id)) {
            HStack(spacing: DS.Space.s2) {
                Text(verbatim: region.flag).font(.system(size: 16))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: region.city).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    Text(verbatim: region.id).dsFont(DS.Font.micro).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(DS.Color.textPrimary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, DS.Space.s2_5)
            .frame(height: WhereMetrics.regionChipHeight)
            .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(selected ? DS.Color.secondary : (hovering ? DS.Color.secondary.opacity(0.5) : DS.Color.canvas.opacity(0.4))))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(selected ? DS.Color.borderStrong : DS.Color.border))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(MotionPolicy.shared.animation(MotionTokens.Springs.snappy), value: selected)
        .animation(MotionPolicy.shared.animation(MotionTokens.Easing.ease, MotionTokens.Duration.hover), value: hovering)
    }
}

/// `− valor +` com o número animando ao mudar.
private struct LimitStepper: View {
    let key: String
    let id: A11yID
    let value: String
    let unit: String

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            HStack(spacing: 0) {
                button("minus", "\(key)-")
                Text(verbatim: value)
                    .dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary).monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: WhereMetrics.stepperValue - 2 * WhereMetrics.stepperButton)
                    .animation(MotionPolicy.shared.animation(MotionTokens.Springs.snappy), value: value)
                button("plus", "\(key)+")
            }
            .padding(DS.Space.s0_5)
            .background(Capsule().fill(DS.Color.canvas.opacity(0.5)))
            .overlay(Capsule().strokeBorder(DS.Color.border))
            .a11y(id, kind: "stepper", label: unit, value: value)
            Text(verbatim: unit).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
        }
    }

    private func button(_ symbol: String, _ argument: String) -> some View {
        ActionButton(.computersCloudLimits, argument: .select(argument)) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .frame(width: WhereMetrics.stepperButton, height: WhereMetrics.stepperButton)
                .contentShape(Circle())
        }
        .buttonStyle(DSIconButtonStyle(.row))
    }
}

private struct LinkChip: View {
    let kind: CloudProviderLink.Kind
    let title: String
    let provider: CloudProviderInfo
    @State private var hovering = false

    var body: some View {
        if provider.links.contains(where: { $0.kind == kind }) {
            ActionButton(.computersCloudOpenLink, id: .computersCloudLink(kind.rawValue), argument: .select(kind.rawValue)) {
                HStack(spacing: DS.Space.s1) {
                    Text(verbatim: title).dsFont(DS.Font.label)
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                        .offset(x: hovering ? 1 : 0, y: hovering ? -1 : 0)
                }
                .foregroundStyle(hovering ? DS.Color.textPrimary : DS.Color.textSecondary)
                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
                .background(Capsule().fill(hovering ? DS.Color.secondary : Color.clear))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(MotionPolicy.shared.animation(MotionTokens.Springs.snappy), value: hovering)
        }
    }
}

// MARK: Sessões novas e faixa compacta

/// Padrão de "Subagent computers" das sessões novas (o mesmo de Settings › Computers), aqui onde a escolha faz sentido.
private struct NewSessionsRow: View {
    let settings: SettingsModel

    private var mode: SubagentComputersMode { settings.settings.computers.defaultSubagentMode }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: DS.Space.s0_5) {
                Text("New sessions", bundle: .module).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary)
                Text(verbatim: mode.explanation).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                    .id(mode).transition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.s4)
            DSSegmented(
                SubagentComputersMode.allCases.map { .init($0.rawValue, $0.segmentTitle) }, selection: mode.rawValue,
                action: .settingsComputersDefaultSubagentMode, id: .computersNewSessions)
        }
        .padding(DS.Space.s4)
        .background(RoundedRectangle(cornerRadius: DS.Radius.large).fill(DS.Color.chrome))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.large).strokeBorder(DS.Color.border))
        .animation(MotionPolicy.shared.animation(MotionTokens.Easing.standard, MotionTokens.Duration.base), value: mode)
    }
}

private struct CompactWhereBar: View {
    let settings: SettingsModel

    var body: some View {
        let local = settings.settings.computers.runOn == .local
        HStack(spacing: DS.Space.s2) {
            Image(systemName: local ? "laptopcomputer" : "cloud").font(.system(size: 13)).foregroundStyle(DS.Color.textSecondary)
            Text(local ? "Computers run on this Mac" : "Computers run in your cloud", bundle: .module)
                .dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
            if local {
                LocalStatusLine(status: settings.dockerStatus)
            } else {
                CloudSummaryLine(settings: settings, selected: true)
            }
            Spacer(minLength: DS.Space.s2)
            ActionButton(.computersWhereToggle, id: .computersWhereChange) {
                HStack(spacing: DS.Space.s1) {
                    Text(settings.computersWhereOpen ? "Done" : "Change", bundle: .module).dsFont(DS.Font.label)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(settings.computersWhereOpen ? 180 : 0))
                }
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: WhereMetrics.compactBar)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: DSMetrics.hairline) }
    }
}
