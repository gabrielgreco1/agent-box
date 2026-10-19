import AgentBoxCore
import AgentBoxDesignSystem
import AgentBoxProtocol
import AgentBoxViewerKit
import AppKit
import SwiftUI

/// Medidas do viewer (03 §11).
enum ViewerMetrics {
    static let header = DS.Space.s8
    static let banner = DS.Space.s10
    static let pill: CGFloat = 22
    static let frameStroke: CGFloat = 1.5
    static let frameStrokeStrong: CGFloat = 2
    static let noteWidth: CGFloat = 300
    static let noteHeight: CGFloat = 64
    static let badgeSeconds: Double = 3
    static let cardWidth: CGFloat = 360
    static let separator: CGFloat = 1
    static let strip: CGFloat = 72
    static let stripThumbWidth: CGFloat = 104
}

/// Embrulha a view AppKit do WebView (a mesma instância durante toda a vida do viewer).
struct ViewerCanvas: NSViewRepresentable {
    let web: ComputerViewerWebView
    func makeNSView(context: Context) -> ComputerViewerWebView { web }
    func updateNSView(_ nsView: ComputerViewerWebView, context: Context) {}
}

/// Viewer de computador como pane (03 §11): header 32, banner de ajuda, canvas noVNC com borda viva conforme o controle.
struct ComputerViewerView: View {
    let controller: ComputerViewerController
    let computers: ComputersController
    /// Nome da sessão de origem para o botão `Back to <sessão>`; `nil` na janela própria (sem página para voltar).
    var backTitle: String?
    @State private var badgeVisible = false
    @State private var breathing = false

    private var model: ComputerViewerModel { controller.model }
    private var id: String { controller.name }

    var body: some View {
        VStack(spacing: 0) {
            ViewerHeader(controller: controller, backTitle: backTitle)
            ViewerStrip(computers: computers, current: id)
            if let help = model.help { helpBanner(help) }
            ZStack {
                ViewerCanvas(web: controller.web)
                controlFrame
                stateOverlay
                keyboardBadge
                if model.handBackNoteVisible { handBackCard.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(DS.Space.s3) }
                if model.blockedClickAt != nil { blockedTip }
            }
            .background(DS.Color.canvas)
        }
        .background(DS.Color.canvas)
        .a11y(.viewer(id), kind: "container", label: id)
        .task { await controller.start() }
        .onChange(of: model.keyboardCaptured) { _, captured in
            guard captured else { badgeVisible = false; return }
            badgeVisible = true
            Task {
                try? await Task.sleep(for: .seconds(ViewerMetrics.badgeSeconds))
                badgeVisible = false
            }
        }
    }

    // MARK: Borda viva (04 momento 3, básico)

    private var frameColor: Color {
        if model.help != nil, model.control != .human { return DS.Color.agentNeedsInput }
        switch model.control {
        case .agent: return DS.Color.aiAccent
        case .revoking: return DS.Color.aiAccent.opacity(0.4)
        case .human: return DS.Color.textPrimary
        }
    }

    private var controlFrame: some View {
        Rectangle()
            .strokeBorder(frameColor, lineWidth: model.control == .human ? ViewerMetrics.frameStrokeStrong : ViewerMetrics.frameStroke)
            .opacity(model.help != nil && model.control != .human ? (breathing ? 1 : 0.45) : 1)
            .allowsHitTesting(false)
            .animation(MotionPolicy.shared.reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: breathing)
            .onAppear { breathing = true }
            .a11y(.viewerControlFrame(id), kind: "frame", value: model.control.rawValue)
    }

    // MARK: Estados do canvas (03 §11.4)

    @ViewBuilder
    private var stateOverlay: some View {
        switch model.connection {
        case .connecting:
            card { Text("Connecting…", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary) }
                .a11y(.viewerConnecting(id), kind: "status", label: "Connecting…")
        case .reconnecting:
            statusPill(String(localized: "Reconnecting…", bundle: .module), reconnect: false)
        case .delayed(let since):
            statusPill(String(localized: "Slow connection · last frame \(since.formatted(date: .omitted, time: .standard))", bundle: .module), reconnect: false)
        case .disconnected, .error:
            card {
                VStack(spacing: DS.Space.s3) {
                    Text(verbatim: String(localized: "Disconnected from \(id).", bundle: .module)).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                    DSButton(.computerReconnect, "Reconnect", variant: .outline, size: .xs)
                }
            }
            .a11y(.viewerDisconnected(id), kind: "status", label: "Disconnected")
        case .stopped:
            card { Text("This computer is stopped.", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary) }
                .a11y(.viewerStatus(id), kind: "status", label: "This computer is stopped.")
        case .live:
            EmptyView()
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(DS.Space.s4)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.Color.overlayCard))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Color.border))
    }

    private func statusPill(_ text: String, reconnect: Bool) -> some View {
        HStack(spacing: DS.Space.s2) {
            DSSpinner(kind: .neutral, size: DS.Space.s3)
            Text(verbatim: text).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
            DSButton(.computerReconnect, "Reconnect", variant: .ghost, size: .xs)
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: ViewerMetrics.pill)
        .background(Capsule().fill(DS.Color.chrome))
        .overlay(Capsule().strokeBorder(DS.Color.border))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, DS.Space.s3)
        .a11y(.viewerStatus(id), kind: "status", label: text)
    }

    private var keyboardBadge: some View {
        HStack(spacing: DS.Space.s1_5) {
            Image(systemName: "keyboard")
            Text("Keyboard captured · ⌃⌥ to release", bundle: .module)
        }
        .dsFont(DS.Font.label)
        .foregroundStyle(DS.Color.textPrimary)
        .padding(.horizontal, DS.Space.s2_5)
        .frame(height: ViewerMetrics.pill)
        .background(Capsule().fill(DS.Color.chrome))
        .overlay(Capsule().strokeBorder(DS.Color.border))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.Space.s2)
        .opacity(model.keyboardCaptured && badgeVisible ? 1 : 0)
        .allowsHitTesting(false)
        .a11y(.viewerKeyboardBadge(id), kind: "badge", label: "Keyboard captured · ⌃⌥ to release", value: model.keyboardCaptured ? "captured" : "released")
    }

    private var blockedTip: some View {
        Text("Claude is using this computer. Take over to interact.", bundle: .module)
            .dsFont(DS.Font.label)
            .foregroundStyle(DS.Color.textPrimary)
            .padding(.horizontal, DS.Space.s3)
            .frame(height: ViewerMetrics.pill)
            .background(Capsule().fill(DS.Color.chrome))
            .overlay(Capsule().strokeBorder(DS.Color.border))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, DS.Space.s6)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    // MARK: Banner de ajuda (03 §11.4)

    private func helpBanner(_ help: HelpSummary) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(DS.Color.agentNeedsInputText)
                Text(verbatim: "\(controller.name) needs you · \(help.headline)")
                    .dsFont(DS.Font.label)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                if model.control == .agent {
                    DSButton(.computerTakeOver, "Take Over", variant: .primary, size: .xs, symbol: "cursorarrow.click")
                }
                DSButton(.computerDeclineHelp, id: .viewerHelpBannerDecline(id), "Decline…", variant: .ghost, size: .xs)
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(height: ViewerMetrics.banner)
            if model.declineVisible { declineForm }
        }
        .background(DS.Color.agentNeedsInput.opacity(0.1))
        .overlay(alignment: .bottom) { DS.Color.agentNeedsInput.opacity(0.25).frame(height: ViewerMetrics.separator) }
        .a11y(.viewerHelpBanner(id), kind: "banner", label: help.headline)
    }

    private var declineForm: some View {
        HStack(spacing: DS.Space.s2) {
            ZStack(alignment: .leading) {
                if model.declineReason.isEmpty {
                    Text("Reason (optional)", bundle: .module).dsFont(DS.Font.inputCompact).foregroundStyle(DS.Color.textQuaternary).allowsHitTesting(false)
                }
                TextField(text: Bindable(controller.model).declineReason) { EmptyView() }
                    .textFieldStyle(.plain)
                    .dsFont(DS.Font.inputCompact)
                    .foregroundStyle(DS.Color.textPrimary)
            }
            .dsFieldChrome()
            Text("The agent will be told you declined.", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            DSButton(.computerDeclineHelp, "Cancel", variant: .ghost, size: .xs, argument: .select("cancel"))
            DSButton(.computerDeclineHelp, "Decline", variant: .outline, size: .xs, argument: .select("confirm"))
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.bottom, DS.Space.s2)
    }

    // MARK: Hand Back (03 §11.5)

    private var handBackCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Note for Claude Code (optional)", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
            ZStack(alignment: .topLeading) {
                if model.handBackNote.isEmpty {
                    Text("e.g. Logged in, continue from page 3", bundle: .module)
                        .dsFont(DS.Font.inputCompact).foregroundStyle(DS.Color.textQuaternary).allowsHitTesting(false)
                }
                TextEditor(text: Bindable(controller.model).handBackNote)
                    .scrollContentBackground(.hidden)
                    .dsFont(DS.Font.inputCompact)
                    .foregroundStyle(DS.Color.textPrimary)
            }
            .frame(height: ViewerMetrics.noteHeight)
            .dsFieldChrome(height: nil)
            .a11y(.viewerHandBackNote(id), kind: "textfield", value: model.handBackNote)
            HStack(spacing: DS.Space.s2) {
                Spacer(minLength: 0)
                DSButton(.computerHandBack, "Cancel", variant: .ghost, size: .xs, argument: .select("cancel"))
                DSButton(.computerHandBack, id: .viewerHandBackConfirm(id), "Hand Back", variant: .primary, size: .xs, keycap: "⌘↵", argument: .select("confirm"))
            }
        }
        .padding(DS.Space.s3)
        .frame(width: ViewerMetrics.noteWidth)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.Color.overlayCard))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Color.border))
    }
}

/// Faixa de miniaturas (03 §11.3): os outros computadores, 72 de altura; clicar troca o viewer. Oculta com um computador só.
struct ViewerStrip: View {
    let computers: ComputersController
    let current: String

    var body: some View {
        let others = computers.model.rows.filter { $0.id != current }
        if !others.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: DS.Space.s2) {
                    ForEach(others) { row in
                        ActionButton(.computerOpenViewer, argument: .select(row.id)) {
                            ComputerThumbnailView(row: row, compact: true).frame(width: ViewerMetrics.stripThumbWidth)
                        }
                        .buttonStyle(.plain)
                        .a11y(.viewerStripThumb(current, row.id), kind: "thumbnail", label: row.id)
                    }
                }
                .padding(.horizontal, DS.Space.s3)
            }
            .frame(height: ViewerMetrics.strip)
            .background(DS.Color.canvas)
            .overlay(alignment: .bottom) { DS.Color.border.frame(height: ViewerMetrics.separator) }
            .a11y(.viewerStrip(current), kind: "container")
        }
    }
}

/// Header de 32 (03 §11.2): nome, tipo, URL, pill de controle, Take Over / Hand Back, janela própria.
struct ViewerHeader: View {
    let controller: ComputerViewerController
    var backTitle: String?
    private var model: ComputerViewerModel { controller.model }
    private var id: String { controller.name }

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            if let backTitle {
                DSButton(.pageClose, id: .viewerBack(id), "Back to \(backTitle)", variant: .ghost, size: .xs, symbol: "arrow.left")
            }
            Image(systemName: "display").foregroundStyle(DS.Color.textSecondary)
            Text(verbatim: controller.name).dsFont(DS.Font.bodyStrong).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                .a11y(.viewerName(id), kind: "text", label: controller.name)
            Text(verbatim: modeLabel).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                .a11y(.viewerMode(id), kind: "text", label: modeLabel)
            Text(verbatim: model.snapshot?.url ?? "")
                .dsFont(DS.Font.monoMicro)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .a11y(.viewerUrl(id), kind: "text", value: model.snapshot?.url)
            Spacer(minLength: DS.Space.s2)
            ControlPill(model: model, id: id)
            controls
            ActionButton(.computerPaste, tooltip: String(localized: "Paste to Computer", bundle: .module)) { Image(systemName: "doc.on.clipboard") }
                .buttonStyle(DSIconButtonStyle(.header))
            ActionButton(.computerCopySelection, tooltip: String(localized: "Copy Selection from Computer", bundle: .module)) { Image(systemName: "doc.on.doc") }
                .buttonStyle(DSIconButtonStyle(.header))
            ActionButton(.computerPopOut, id: .viewerPopOut(id), tooltip: String(localized: "Open in New Window", bundle: .module)) {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(DSIconButtonStyle(.header))
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: ViewerMetrics.header)
        .background(DS.Color.chrome)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ViewerMetrics.separator) }
    }

    private var modeLabel: String {
        switch model.snapshot?.display {
        case "desktop": String(localized: "Desktop", bundle: .module)
        case "http": String(localized: "HTTP", bundle: .module)
        default: String(localized: "Headless", bundle: .module)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.control {
        case .agent:
            DSButton(.computerTakeOver, id: .viewerTakeOver(id), "Take Over", variant: .primary, size: .xs, symbol: "cursorarrow.click", keycap: "⇧⌘R")
        case .revoking:
            DSButton(
                .computerTakeOver, id: .viewerTakeOver(id), "Take Over", variant: .primary, size: .xs, loading: "Requesting control…")
            if model.forceAvailable {
                DSButton(.computerForceTakeOver, id: .viewerForceTakeOver(id), "Force Take Over", variant: .destructive, size: .xs)
            }
        case .human:
            DSButton(.computerHandBack, id: .viewerHandBack(id), "Hand Back", variant: .primary, size: .xs, symbol: "hand.raised", keycap: "⇧⌘R")
        }
    }
}

/// Pill de controle (03 §11.2): agente usando, humano no controle, pedido de ajuda, ocioso.
struct ControlPill: View {
    let model: ComputerViewerModel
    let id: String

    var body: some View {
        HStack(spacing: DS.Space.s1_5) {
            if model.control == .agent, model.help == nil, model.connection != .stopped { DSSpinner(kind: .neutral, size: DS.Space.s3) }
            Text(verbatim: text).dsFont(DS.Font.label).foregroundStyle(foreground).lineLimit(1)
        }
        .padding(.horizontal, DS.Space.s2_5)
        .frame(height: ViewerMetrics.pill)
        .background(Capsule().fill(background))
        .a11y(.viewerControlPill(id), kind: "status", label: text, value: model.control.rawValue)
    }

    private var text: String {
        if model.control == .human { return String(localized: "You're in control", bundle: .module) }
        if model.control == .revoking { return String(localized: "Requesting control…", bundle: .module) }
        if model.help != nil { return String(localized: "Needs You", bundle: .module) }
        if model.connection == .stopped { return String(localized: "Idle", bundle: .module) }
        return String(localized: "Claude is using", bundle: .module)
    }

    private var foreground: Color {
        if model.control == .human { return DS.Color.textPrimary }
        if model.help != nil { return DS.Color.agentNeedsInputText }
        return DS.Color.aiAccent
    }

    private var background: Color {
        if model.control == .human { return DS.Color.fg10 }
        if model.help != nil { return DS.Color.agentNeedsInput.opacity(0.15) }
        return DS.Color.aiAccent.opacity(0.15)
    }
}
