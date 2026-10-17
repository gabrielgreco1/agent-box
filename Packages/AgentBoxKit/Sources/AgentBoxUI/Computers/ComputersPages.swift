import AgentBoxCore
import AgentBoxDesignSystem
import AgentBoxProtocol
import AppKit
import ImageIO
import SwiftUI

/// Imagem decodificada fora do main thread (audit/09 N13). `CGImage` é imutável.
struct DecodedThumbnail: @unchecked Sendable {  // SAFETY: CGImage é imutável depois de criada.
    let image: CGImage
}

/// Decodifica o JPEG da miniatura num ator próprio: o main thread nunca decodifica.
actor ThumbnailDecoder {
    static let shared = ThumbnailDecoder()
    func decode(_ data: Data) -> DecodedThumbnail? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return DecodedThumbnail(image: image)
    }
}

enum ComputersMetrics {
    static let pageHeader = DS.Space.s8 + DS.Space.s1
    static let rowHeight = DS.Space.s8 + DS.Space.s4
    static let tableHeader = DS.Layout.paneHeaderHeight + DS.Space.s1
    static let thumbWidth: CGFloat = 286
    static let thumbHeight: CGFloat = 179
    static let rowThumbWidth: CGFloat = 64
    static let rowThumbHeight: CGFloat = 40
    static let stateBorder: CGFloat = 1.5
    static let separator: CGFloat = 1
    static let needsBand = DS.Space.s6
    static let colName: CGFloat = 160
    static let colSession: CGFloat = 140
    static let colMode: CGFloat = 80
    static let colState: CGFloat = 110
    static let colLease: CGFloat = 90
    static let colProxy: CGFloat = 100
    static let colAge: CGFloat = 90
}

/// Miniatura (DS §12.25): frame vivo (≤ 1 fps), borda de estado, rodapé com nome e estado; faixa laranja com `Needs you · CAPTCHA`.
struct ComputerThumbnailView: View {
    let row: ComputerRow
    var compact = false
    @State private var decoded: DecodedThumbnail?

    private var border: Color {
        if row.needsYou { return DS.Color.agentNeedsInput }
        switch row.snapshot.control {
        case .human: return DS.Color.textPrimary
        case .revoking: return DS.Color.aiAccent.opacity(0.4)
        case .agent: return row.snapshot.state == .inUse ? DS.Color.aiAccent : DS.Color.border
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                DS.Color.canvas
                if let decoded {
                    Image(decorative: decoded.image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: row.snapshot.display == "http" ? "network" : "display").foregroundStyle(DS.Color.textQuaternary)
                }
                if let help = row.snapshot.help {
                    HStack(spacing: DS.Space.s2) {
                        Text(verbatim: "Needs you · \(help.kind.rawValue.uppercased())").dsFont(DS.Font.label).foregroundStyle(DS.Color.textOnPrimary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Space.s2)
                    .frame(height: ComputersMetrics.needsBand)
                    .background(DS.Color.agentNeedsInput)
                }
            }
            .frame(height: compact ? ComputersMetrics.rowThumbHeight : ComputersMetrics.thumbHeight)
            if !compact {
                HStack(spacing: DS.Space.s1_5) {
                    Text(verbatim: row.snapshot.name).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    Spacer(minLength: DS.Space.s1)
                    Text(verbatim: stateText).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                }
                .padding(.horizontal, DS.Space.s2)
                .frame(height: DS.Space.s6 - DS.Space.s1)
                .background(DS.Color.chrome)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(border, lineWidth: ComputersMetrics.stateBorder))
        .task(id: row.thumbnail?.count ?? 0) {
            guard let data = row.thumbnail else { return }
            decoded = await ThumbnailDecoder.shared.decode(data)
        }
    }

    private var stateText: String {
        if row.snapshot.control == .human { return String(localized: "You're in control", bundle: .module) }
        switch row.snapshot.state {
        case .inUse: return String(localized: "In use", bundle: .module)
        case .ready: return String(localized: "Ready", bundle: .module)
        case .stopped: return String(localized: "Stopped", bundle: .module)
        case .queued: return String(localized: "Queued", bundle: .module)
        case .provisioning: return String(localized: "Starting", bundle: .module)
        case .failed: return String(localized: "Failed", bundle: .module)
        }
    }
}

// MARK: Painel direito: aba Computers (03 §10.4)

/// Corpo do módulo Computers do painel direito (03 §10.4). O header (título e resumo) é do contêiner (`ComputersModule`).
struct ComputersPanelView: View {
    let controller: ComputersController

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DS.Space.s3) {
                if controller.model.rows.isEmpty {
                    Text("No computers in this session. Agents create them when they need a browser.", bundle: .module)
                        .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).multilineTextAlignment(.center)
                        .padding(DS.Space.s4)
                        .a11y(.rightPanelComputersEmpty, kind: "text")
                }
                ForEach(controller.model.rows) { row in
                    ZStack(alignment: .bottomTrailing) {
                        ActionButton(.computerOpenViewer, argument: .select(row.id)) {
                            ComputerThumbnailView(row: row)
                        }
                        .buttonStyle(.plain)
                        if row.snapshot.control == .agent {
                            DSButton(.computerTakeOver, id: .rightPanelComputersThumbTakeOver(row.id), "Take Over", variant: .primary, size: .xs, argument: .select(row.id))
                                .padding(.trailing, DS.Space.s2).padding(.bottom, DS.Space.s8)
                        }
                    }
                    .a11y(.rightPanelComputersThumb(row.id), kind: "thumbnail", label: row.id, value: row.snapshot.control.rawValue)
                }
            }
            .padding(DS.Space.s3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.panel)
    }
}

// MARK: Página Computers (03 §12.3)

struct PageHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Text(title, bundle: .module).dsFont(DS.Font.sectionLabel).foregroundStyle(DS.Color.textPrimary)
            Spacer(minLength: DS.Space.s2)
            trailing
            ActionButton(.pageClose, tooltip: String(localized: "Close", bundle: .module)) { Image(systemName: "xmark") }
                .buttonStyle(DSIconButtonStyle(.header))
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: ComputersMetrics.pageHeader)
        .background(DS.Color.chrome)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }
}

struct ComputersPageView: View {
    let controller: ComputersController

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Computers") {
                Text(verbatim: controller.model.summaryText).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
            }
            if controller.model.rows.isEmpty {
                Text("No computers yet. Agents create them when they need a browser.", bundle: .module)
                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .a11y(.computersEmpty, kind: "text")
            } else {
                header
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(controller.model.rows) { row in
                            ActionButton(.computerOpenViewer, argument: .select(row.id)) { ComputersRow(row: row) }
                                .buttonStyle(DSListRowStyle())
                                .a11y(.computersRow(row.id), kind: "row", label: row.id, value: row.snapshot.control.rawValue)
                        }
                    }
                }
            }
        }
        .background(DS.Color.canvas)
        .a11y(.computersPage, kind: "page")
    }

    private var header: some View {
        HStack(spacing: DS.Space.s2) {
            Color.clear.frame(width: ComputersMetrics.rowThumbWidth)
            column("Name", ComputersMetrics.colName)
            column("Session", ComputersMetrics.colSession)
            column("Mode", ComputersMetrics.colMode)
            column("State", ComputersMetrics.colState)
            column("Lease", ComputersMetrics.colLease)
            column("Proxy", ComputersMetrics.colProxy)
            column("Last Used", ComputersMetrics.colAge)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: ComputersMetrics.tableHeader)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }

    private func column(_ title: LocalizedStringKey, _ width: CGFloat) -> some View {
        Text(title, bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary).frame(width: width, alignment: .leading)
    }
}

struct ComputersRow: View {
    let row: ComputerRow

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            ComputerThumbnailView(row: row, compact: true).frame(width: ComputersMetrics.rowThumbWidth)
            cell(row.snapshot.name, ComputersMetrics.colName, strong: true)
            cell(row.sessionTitle ?? "—", ComputersMetrics.colSession)
            cell(row.snapshot.display.capitalized, ComputersMetrics.colMode)
            cell(state, ComputersMetrics.colState)
            cell(row.snapshot.control == .human ? String(localized: "You", bundle: .module) : String(localized: "Agent", bundle: .module), ComputersMetrics.colLease)
            cell(row.snapshot.proxy, ComputersMetrics.colProxy)
            cell(row.lastActivity.formatted(.relative(presentation: .numeric)), ComputersMetrics.colAge)
            if row.needsYou {
                Text("Needs you", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.agentNeedsInputText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: ComputersMetrics.rowHeight)
    }

    private var state: String {
        row.snapshot.state == .inUse ? String(localized: "In use", bundle: .module) : row.snapshot.state.rawValue.capitalized
    }

    private func cell(_ text: String, _ width: CGFloat, strong: Bool = false) -> some View {
        Text(verbatim: text).dsFont(strong ? DS.Font.bodyStrong : DS.Font.body).foregroundStyle(strong ? DS.Color.textPrimary : DS.Color.textSecondary)
            .lineLimit(1).frame(width: width, alignment: .leading)
    }
}

