import RackyCore
import RackyDesignSystem
import RackyProtocol
import RackyStore
import SwiftUI

// A página Data (spec data-hub): explorer à esquerda (Racky e Connections), tabs dos objetos abertos e, em cima de cada objeto, a
// barra de localização (onde estou, o que é) e a linha de fluxo (quem grava aqui, para onde isto vai).

enum DataMetrics {
    static let explorerWidth: CGFloat = 268
    static let rowHeight = DS.Space.s6 + DS.Space.s0_5
    static let indent = DS.Space.s3 + DS.Space.s0_5
    static let tabHeight = DS.Space.s8 + DS.Space.s1
    static let tabMaxWidth: CGFloat = 220
    static let locationHeight: CGFloat = 52
    static let flowHeight = DS.Space.s8 + DS.Space.s1
    static let icon: CGFloat = 12
    static let chipHeight = DS.Space.s6
    static let liveDot: CGFloat = 6
    static let badgePadding: CGFloat = 1
    static let underline: CGFloat = 2
    static let emptyTextWidth: CGFloat = 440
    static let previewWidth: CGFloat = 460
    static let connectWidth: CGFloat = 660
    static let editorHeight: CGFloat = 160
}

/// Ícones por tipo de lugar e de objeto (mesmos no explorer, nas tabs e na barra de localização).
enum DataSymbols {
    static func connection(_ kind: DataConnectionKind) -> String {
        switch kind.family {
        case .database: "cylinder.split.1x2"
        case .warehouse: "square.stack.3d.up"
        case .storage: "archivebox"
        case .spreadsheet: "tablecells.badge.ellipsis"
        case .outgoing: "paperplane"
        }
    }

    static func node(_ kind: DataNode.Kind) -> String {
        switch kind {
        case .schema: "folder"
        case .table: "tablecells"
        case .view: "eye"
        case .bucket: "archivebox"
        case .folder: "folder"
        case .file: "doc"
        case .spreadsheet: "doc.richtext"
        case .sheet: "tablecells"
        }
    }

    static func object(_ object: DataObject) -> String {
        switch object {
        case .dataset: "tablecells"
        case .table: "tablecells"
        case .query: "terminal"
        case .folder: "folder"
        case .webhook: "paperplane"
        case .tab: "tablecells"
        }
    }
}

struct DataPageView: View {
    let hub: DataHubController

    var body: some View {
        HStack(spacing: 0) {
            DataExplorer(hub: hub)
            VStack(spacing: 0) {
                DataTabStrip(hub: hub)
                if let active = hub.active {
                    if hub.connection(active.connectionID)?.environment == .production { DataProductionBanner(hub: hub, object: active) }
                    DataLocationBar(hub: hub, object: active)
                    DataLineageStrip(hub: hub, object: active)
                    DataObjectView(hub: hub, object: active)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .a11y(.dataObject, kind: "container", label: active.key)
                } else {
                    DataEmptyState(hub: hub)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DS.Color.canvas)
        .overlay {
            if hub.showingConnect { DataConnectSheet(hub: hub) }
        }
        .a11y(.dataPage, kind: "page")
        .task { await hub.datasets.reloadList() }
    }
}

// MARK: Explorer

struct DataExplorer: View {
    let hub: DataHubController

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    VStack(alignment: .leading, spacing: DS.Space.s0_5) {
                        Text("Data", bundle: .module).dsFont(DS.Font.composerTitle).foregroundStyle(DS.Color.textPrimary)
                        Text("What agents collect, and the places you connect", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                    }
                    .padding(.horizontal, DS.Space.s2)
                    .padding(.bottom, DS.Space.s3)
                    section(String(localized: "On this Mac", bundle: .module), caption: String(localized: "Saved by Racky as your agents collect", bundle: .module), id: "racky")
                    racky
                    section(String(localized: "Connections", bundle: .module), caption: String(localized: "Your own databases and services, outside Racky", bundle: .module), id: "connections")
                        .padding(.top, DS.Space.s3)
                    connections
                }
                .padding(.horizontal, DS.Space.s2)
                .padding(.vertical, DS.Space.s3)
            }
            ActionButton(.dataAddConnection, id: .dataAddConnection, argument: .press) {
                HStack(spacing: DS.Space.s1_5) {
                    Image(systemName: "plus").font(.system(size: DS.Space.s2_5, weight: .semibold))
                    Text("Add connection", bundle: .module).dsFont(DS.Font.label)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.horizontal, DS.Space.s3)
                .frame(height: DataMetrics.tabHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        }
        .frame(width: DataMetrics.explorerWidth)
        .background(DS.Color.chrome)
        .overlay(alignment: .trailing) { DS.Color.border.frame(width: ComputersMetrics.separator) }
        .a11y(.dataExplorer, kind: "tree")
    }

    private func section(_ title: String, caption: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(verbatim: title.uppercased()).dsFont(DS.Font.micro).tracking(0.6).foregroundStyle(DS.Color.textTertiary)
            Text(verbatim: caption).dsFont(DS.Font.small).foregroundStyle(DS.Color.textQuaternary).lineLimit(1)
        }
        .padding(.horizontal, DS.Space.s2)
        .padding(.bottom, DS.Space.s1)
        .a11y(.dataExplorerSection(id), kind: "header", label: title)
    }

    // MARK: Racky

    @ViewBuilder private var racky: some View {
        let groups = hub.rackyGroups
        if groups.isEmpty {
            Text("No datasets yet. Agents create them when they collect data.", bundle: .module)
                .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                .padding(.horizontal, DS.Space.s2)
        }
        ForEach(groups, id: \.session) { group in
            let node = "racky/\(group.session)"
            let open = !hub.expanded.contains(node)  // sessões abertas por padrão
            row(id: node, depth: 0, symbol: "bubble.left.and.text.bubble.right", title: group.session, detail: nil, chevron: open, toggle: node, live: false, selected: false, open: nil)
            if open {
                ForEach(group.datasets, id: \.dataset.id) { summary in
                    let object = DataObject.dataset(summary.dataset.id)
                    row(id: object.key, depth: 1, symbol: "tablecells", title: summary.dataset.name, detail: summary.rowCount.formatted(),
                        chevron: nil, toggle: nil, live: hub.datasets.isCollecting(summary), selected: hub.active == object, open: object)
                }
            }
        }
    }

    // MARK: Conexões

    @ViewBuilder private var connections: some View {
        if hub.connections.isEmpty {
            Text("Connect a database, a bucket or a spreadsheet to browse it here and let agents write to it.", bundle: .module)
                .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                .padding(.horizontal, DS.Space.s2)
        }
        ForEach(hub.connections) { connection in
            let open = hub.expanded.contains(connection.id)
            let target: DataObject? = connection.kind == .webhook ? .webhook(connection: connection.id) : nil
            HStack(spacing: 0) {
                row(id: connection.id, depth: 0, symbol: DataSymbols.connection(connection.kind), title: connection.name, detail: nil,
                    chevron: connection.kind.canBrowse ? open : nil, toggle: connection.kind.canBrowse ? connection.id : nil,
                    live: target.map(hub.isLive) ?? false, selected: target != nil && hub.active == target, open: target,
                    badge: connection.environment, subtitle: connection.kind.title == connection.name ? nil : connection.kind.title)
            }
            if open {
                ForEach(connection.children) { child in nodeRows(child, connection: connection, depth: 1, path: []) }
                if connection.kind.speaksSQL {
                    ActionButton(.dataNewQuery, id: .dataExplorerNode("\(connection.id)/query"), argument: .select(connection.id)) {
                        rowLabel(depth: 1, symbol: "plus.rectangle", title: String(localized: "New SQL query", bundle: .module), detail: nil, chevron: nil,
                                 live: false, selected: false, badge: nil, subtitle: nil, muted: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func nodeRows(_ node: DataNode, connection: DataConnection, depth: Int, path: [String]) -> AnyView {
        let open = hub.expanded.contains(node.id)
        let object = Self.object(for: node, connection: connection, path: path)
        let expandable = !node.children.isEmpty
        return AnyView(VStack(alignment: .leading, spacing: 0) {
            row(id: node.id, depth: depth, symbol: DataSymbols.node(node.kind), title: node.name, detail: node.size.map { $0.formatted() },
                chevron: expandable ? open : nil, toggle: expandable && object == nil ? node.id : nil,
                live: object.map(hub.isLive) ?? false, selected: object != nil && hub.active == object, open: object)
            if open {
                ForEach(node.children) { child in nodeRows(child, connection: connection, depth: depth + 1, path: path + [node.name]) }
            }
        })
    }

    /// O que abre ao clicar no nó (schema e planilha só expandem).
    static func object(for node: DataNode, connection: DataConnection, path: [String]) -> DataObject? {
        switch node.kind {
        case .table, .view: .table(connection: connection.id, schema: path.last ?? "", name: node.name)
        case .folder, .bucket: .folder(connection: connection.id, path: path + [node.name])
        case .sheet: .tab(connection: connection.id, spreadsheet: path.last ?? "", name: node.name)
        case .schema, .spreadsheet, .file: nil
        }
    }

    @ViewBuilder
    private func row(
        id: String, depth: Int, symbol: String, title: String, detail: String?, chevron: Bool?, toggle: String?, live: Bool, selected: Bool,
        open: DataObject?, badge: DataEnvironment? = nil, subtitle: String? = nil
    ) -> some View {
        let label = rowLabel(depth: depth, symbol: symbol, title: title, detail: detail, chevron: chevron, live: live, selected: selected, badge: badge, subtitle: subtitle)
        HStack(spacing: 0) {
            if let open {
                ActionButton(.dataOpen, id: .dataExplorerNode(id), argument: .select(open.key)) { label }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { if let toggle, !hub.expanded.contains(toggle) { hub.toggle(toggle) } })
            } else if let toggle {
                ActionButton(.dataToggleNode, id: .dataExplorerNode(id), argument: .select(toggle)) { label }
                    .buttonStyle(.plain)
            } else {
                label.a11y(.dataExplorerNode(id), kind: "row", label: title)
            }
        }
    }

    private func rowLabel(
        depth: Int, symbol: String, title: String, detail: String?, chevron: Bool?, live: Bool, selected: Bool, badge: DataEnvironment?,
        subtitle: String?, muted: Bool = false
    ) -> some View {
        HStack(spacing: DS.Space.s1_5) {
            Group {
                if let chevron {
                    Image(systemName: "chevron.right").font(.system(size: DS.Space.s2, weight: .semibold))
                        .rotationEffect(.degrees(chevron ? 90 : 0))
                } else {
                    Color.clear
                }
            }
            .foregroundStyle(DS.Color.textTertiary)
            .frame(width: DS.Space.s2_5)
            Image(systemName: symbol).font(.system(size: DataMetrics.icon)).foregroundStyle(muted ? DS.Color.textTertiary : DS.Color.textSecondary)
                .frame(width: DS.Space.s4)
            Text(verbatim: title).dsFont(DS.Font.cell).foregroundStyle(muted ? DS.Color.textTertiary : DS.Color.textPrimary).lineLimit(1).truncationMode(.middle)
            if let subtitle { Text(verbatim: subtitle).dsFont(DS.Font.small).foregroundStyle(DS.Color.textQuaternary).lineLimit(1) }
            if let badge { EnvironmentBadge(environment: badge) }
            Spacer(minLength: DS.Space.s1)
            if live { LiveDot() }
            if let detail { Text(verbatim: detail).dsFont(DS.Font.monoMicro).foregroundStyle(DS.Color.textTertiary) }
        }
        .padding(.leading, DS.Space.s1 + CGFloat(depth) * DataMetrics.indent)
        .padding(.trailing, DS.Space.s2)
        .frame(height: DataMetrics.rowHeight)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(selected ? DS.Color.sidebarSelected : Color.clear))
        .contentShape(Rectangle())
    }
}

/// `PROD` em âmbar (cuidado), `DEV` neutro.
struct EnvironmentBadge: View {
    let environment: DataEnvironment

    var body: some View {
        let prod = environment == .production
        Text(verbatim: prod ? "PROD" : "DEV")
            .dsFont(DS.Font.keycap)
            .foregroundStyle(prod ? DS.Color.warning : DS.Color.textTertiary)
            .padding(.horizontal, DS.Space.s1)
            .padding(.vertical, DataMetrics.badgePadding)
            .background(RoundedRectangle(cornerRadius: DS.Radius.xs).fill(prod ? DS.Color.warning.opacity(0.12) : DS.Color.secondary))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xs).strokeBorder(prod ? DS.Color.warning.opacity(0.35) : DS.Color.border))
            .fixedSize()
    }
}

struct LiveDot: View {
    var body: some View {
        Circle().fill(DS.Color.dataValid).frame(width: DataMetrics.liveDot, height: DataMetrics.liveDot)
            .help(String(localized: "Something is writing here right now", bundle: .module))
    }
}

// MARK: Tabs

struct DataTabStrip: View {
    let hub: DataHubController
    @Environment(\.pageTrailingInset) private var trailingInset

    var body: some View {
        // Nomes inteiros (o lugar diz qual cópia é): com muitas tabs, a faixa rola de lado em vez de cortar os nomes.
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(hub.tabs, id: \.self) { object in tab(object).id(object) }
                }
            }
            .onChange(of: hub.active) { _, active in if let active { reader.scrollTo(active, anchor: .trailing) } }
            .onAppear { if let active = hub.active { reader.scrollTo(active, anchor: .trailing) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Os botões do painel direito ficam por cima do canto: as tabs param antes deles.
        .padding(.trailing, trailingInset)
        .frame(height: DataMetrics.tabHeight)
        .background(DS.Color.chrome)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
    }

    private func tab(_ object: DataObject) -> some View {
        let active = hub.active == object
        let place = hub.connection(object.connectionID)
        return HStack(spacing: DS.Space.s1_5) {
            ActionButton(.dataOpen, id: .dataTab(object.key), argument: .select(object.key)) {
                HStack(spacing: DS.Space.s1_5) {
                    Image(systemName: DataSymbols.object(object)).font(.system(size: DataMetrics.icon)).foregroundStyle(DS.Color.textTertiary)
                    Text(verbatim: DataLabels.title(object, hub: hub)).dsFont(active ? DS.Font.tabActive : DS.Font.tab)
                        .foregroundStyle(active ? DS.Color.textPrimary : DS.Color.textSecondary).lineLimit(1)
                    // O lugar em letra pequena: duas tabs "books" (Racky e Supabase) não se confundem.
                    Text(verbatim: place?.name ?? String(localized: "This Mac", bundle: .module)).dsFont(DS.Font.small).foregroundStyle(DS.Color.textQuaternary).lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ActionButton(.dataClose, id: .dataTabClose(object.key), argument: .select(object.key), tooltip: String(localized: "Close", bundle: .module)) {
                Image(systemName: "xmark").font(.system(size: DS.Space.s2, weight: .semibold))
            }
            .buttonStyle(DSIconButtonStyle(.tabClose))
            .opacity(active ? 1 : 0.6)
        }
        .padding(.leading, DS.Space.s3)
        .padding(.trailing, DS.Space.s1_5)
        .frame(maxHeight: .infinity)
        .fixedSize(horizontal: true, vertical: false)
        .background(active ? DS.Color.canvas : Color.clear)
        .overlay(alignment: .bottom) { if active { DS.Color.textPrimary.frame(height: DataMetrics.underline) } }
        .overlay(alignment: .trailing) { DS.Color.border.frame(width: ComputersMetrics.separator) }
    }
}

enum DataLabels {
    @MainActor static func title(_ object: DataObject, hub: DataHubController) -> String {
        switch object {
        case .dataset(let id): hub.summary(ofDataset: id)?.dataset.name ?? String(localized: "Dataset", bundle: .module)
        case .table(_, let schema, let name): "\(schema).\(name)"
        case .query(_, let n): String(localized: "Query \(n)", bundle: .module)
        case .folder(_, let path): path.joined(separator: "/")
        case .webhook(let c): hub.connection(c)?.name ?? String(localized: "Webhook", bundle: .module)
        case .tab(_, _, let name): name
        }
    }

    /// O tipo do objeto em palavras (lado direito da barra de localização).
    @MainActor static func kind(_ object: DataObject, hub: DataHubController) -> String {
        switch object {
        case .dataset: String(localized: "Dataset on this Mac", bundle: .module)
        case .table(let c, _, _): hub.connection(c)?.kind.family == .warehouse ? String(localized: "Warehouse table", bundle: .module) : String(localized: "Database table", bundle: .module)
        case .query: String(localized: "SQL query", bundle: .module)
        case .folder: String(localized: "Storage folder", bundle: .module)
        case .webhook: String(localized: "Webhook destination", bundle: .module)
        case .tab: String(localized: "Spreadsheet tab", bundle: .module)
        }
    }
}

// MARK: Barra de localização

/// "Em que lugar estou e o que estou vendo": o chip do lugar (Racky ou a conexão, com o ambiente), a trilha até o objeto e, à direita,
/// o tipo e o tamanho, mais as ações do objeto.
struct DataLocationBar: View {
    let hub: DataHubController
    let object: DataObject

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            placeChip
            ForEach(Array(trail.enumerated()), id: \.offset) { index, crumb in
                Image(systemName: "chevron.right").font(.system(size: DS.Space.s2, weight: .semibold)).foregroundStyle(DS.Color.textQuaternary)
                Text(verbatim: crumb).dsFont(index == trail.count - 1 ? DS.Font.composerTitle : DS.Font.body)
                    .foregroundStyle(index == trail.count - 1 ? DS.Color.textPrimary : DS.Color.textSecondary)
                    .lineLimit(1)
                    .a11y(.dataLocationCrumb("\(index)"), kind: "text", label: crumb)
            }
            Spacer(minLength: DS.Space.s3)
            VStack(alignment: .trailing, spacing: .zero) {
                Text(verbatim: DataLabels.kind(object, hub: hub)).dsFont(DS.Font.label).foregroundStyle(DS.Color.textSecondary)
                if let source = hub.copySource(of: object) {
                    // Uma cópia diz de onde é cópia: a fonte de verdade é o dataset no Racky.
                    Text(verbatim: String(localized: "One-way copy of \(source) (this Mac)", bundle: .module)).dsFont(DS.Font.small).foregroundStyle(DS.Color.dataKey)
                } else if let size {
                    Text(verbatim: size).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                }
            }
            .fixedSize()
            DataObjectActions(hub: hub, object: object)
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(height: DataMetrics.locationHeight)
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .a11y(.dataLocation, kind: "group", label: ([placeName] + trail).joined(separator: " › "))
    }

    private var connection: DataConnection? { hub.connection(object.connectionID) }
    private var placeName: String { connection?.name ?? String(localized: "This Mac", bundle: .module) }

    private var placeChip: some View {
        HStack(spacing: DS.Space.s1_5) {
            if let connection {
                Image(systemName: DataSymbols.connection(connection.kind)).font(.system(size: DataMetrics.icon)).foregroundStyle(DS.Color.textSecondary)
                Text(verbatim: connection.name).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                if connection.kind.title != connection.name {
                    Text(verbatim: connection.kind.title).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                }
                if let environment = connection.environment { EnvironmentBadge(environment: environment) }
            } else {
                Image(systemName: "laptopcomputer").font(.system(size: DataMetrics.icon)).foregroundStyle(DS.Color.textSecondary)
                Text("This Mac", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                Text("saved by Racky", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(.horizontal, DS.Space.s2)
        .frame(height: DataMetrics.chipHeight + DS.Space.s1)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.secondary))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(DS.Color.border))
        .fixedSize()
        .help(connection?.address ?? String(localized: "Stored on this Mac by Racky", bundle: .module))
    }

    private var trail: [String] {
        switch object {
        case .dataset(let id):
            guard let summary = hub.summary(ofDataset: id) else { return [] }
            return [hub.datasets.title(of: summary), summary.dataset.name]
        case .table(_, let schema, let name): return [schema, name]
        case .query(_, let n): return [String(localized: "Query \(n)", bundle: .module)]
        case .folder(_, let path): return path
        case .webhook: return [connection?.address ?? ""]
        case .tab(_, let spreadsheet, let name): return [spreadsheet, name]
        }
    }

    private var size: String? {
        switch object {
        case .dataset(let id):
            return hub.summary(ofDataset: id).map { String(localized: "\($0.rowCount.formatted()) rows", bundle: .module) }
        case .table, .tab:
            let total = DataHubFixtures.grid(for: object).total
            return String(localized: "\(total.formatted()) rows", bundle: .module)
        case .folder(_, let path):
            let count = DataHubFixtures.files(in: path).count
            return String(localized: "\(count) items", bundle: .module)
        case .query, .webhook:
            return nil
        }
    }
}

// MARK: Linhagem

/// O caminho do dado, da esquerda para a direita: quem coleta (agentes) → a fonte (um dataset do Racky, quando há) → as cópias fora
/// do Racky. O objeto aberto fica marcado "You are here"; cada seta diz como o dado passa (coleta, cópia ao vivo, cópia diária, envio).
/// Responde, sem ler mais nada: qual é a fonte, onde estão as cópias, se estão em dia e quando o dado sai do Mac.
struct DataLineageStrip: View {
    let hub: DataHubController
    let object: DataObject

    struct Node: Identifiable {
        enum Role { case agents, source, copy, direct, query }
        var id: String
        var role: Role
        var target: DataObject?
        var place: DataConnection?
        var title: String
        var detail: String
        var live = false
        var current = false
    }

    var body: some View {
        let columns = lineage
        VStack(alignment: .leading, spacing: DS.Space.s1_5) {
        HStack(alignment: .center, spacing: DS.Space.s2) {
            Text("Data path", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textTertiary).fixedSize()
            if columns.isEmpty {
                Text(verbatim: emptyText).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
            }
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                if index > 0 { edge(column.edge) }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    ForEach(column.nodes) { node in chip(node) }
                }
            }
            Spacer(minLength: 0)
        }
        if let sentence = explanation {
            Text(verbatim: sentence).dsFont(DS.Font.small).foregroundStyle(DS.Color.textSecondary)
        }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
        .frame(minHeight: DataMetrics.flowHeight)
        .background(DS.Color.chrome.opacity(0.5))
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .a11y(.dataFlow, kind: "group", label: columns.flatMap(\.nodes).map(\.title).joined(separator: " → "))
    }

    /// Uma frase que diz qual é o original e para que lado o dado anda.
    private var explanation: String? {
        switch object {
        case .query(let connection, _):
            return String(localized: "This query only reads \(hub.connection(connection)?.name ?? ""). SQL that changes data asks you to confirm first.", bundle: .module)
        case .dataset(let id):
            guard let name = hub.summary(ofDataset: id)?.dataset.name else { return nil }
            return hub.destinations(of: object).isEmpty
                ? String(localized: "\(name) on this Mac is the original. Nothing is copied out yet.", bundle: .module)
                : String(localized: "\(name) on this Mac is the original. The copies only receive from it: edits made in a copy don't come back to it.", bundle: .module)
        case .webhook:
            guard let source = hub.copySource(of: object) else { return nil }
            return String(localized: "Racky posts each new row of \(source) (this Mac) to this address. Nothing comes back.", bundle: .module)
        default:
            if let source = hub.copySource(of: object) {
                return String(localized: "This is a one-way copy of \(source) (this Mac). Change the data in \(source): edits made here don't go back.", bundle: .module)
            }
            if !hub.writers(of: object).isEmpty {
                return String(localized: "Agents write into this table directly. Nothing is kept on this Mac.", bundle: .module)
            }
            return nil
        }
    }

    private var emptyText: String {
        String(localized: "Racky doesn't write here or copy from here.", bundle: .module)
    }

    // MARK: Montagem

    private struct Column { var edge: String; var nodes: [Node] }

    private var lineage: [Column] {
        switch object {
        case .query(let connection, _):
            let place = hub.connection(connection)
            return [
                Column(edge: "", nodes: [Node(id: "query", role: .query, place: nil, title: String(localized: "This query", bundle: .module), detail: String(localized: "written by you", bundle: .module), current: true)]),
                Column(edge: String(localized: "reads", bundle: .module), nodes: [Node(id: "db", role: .direct, target: nil, place: place, title: place?.name ?? "", detail: place?.kind.title ?? "")]),
            ]
        case .dataset(let id):
            return chain(sourceID: id)
        default:
            if let source = hub.copySource(of: object), let id = hub.datasetID(named: source) { return chain(sourceID: id) }
            let writers = hub.writers(of: object)
            guard !writers.isEmpty else { return [] }
            return [
                Column(edge: "", nodes: [agentsNode(writers)]),
                Column(edge: String(localized: "write directly", bundle: .module), nodes: [currentNode(role: .direct, detail: String(localized: "written directly · not kept on this Mac", bundle: .module))]),
            ]
        }
    }

    /// Agentes → dataset do Racky (fonte) → cópias.
    private func chain(sourceID: String) -> [Column] {
        let sourceObject = DataObject.dataset(sourceID)
        guard let summary = hub.summary(ofDataset: sourceID) else { return [] }
        var columns: [Column] = []
        let writers = hub.writers(of: sourceObject)
        if !writers.isEmpty { columns.append(Column(edge: "", nodes: [agentsNode(writers)])) }
        columns.append(Column(
            edge: String(localized: "collect", bundle: .module),
            nodes: [Node(
                id: "source", role: .source, target: sourceObject, place: nil, title: summary.dataset.name,
                detail: String(localized: "original · \(summary.rowCount.formatted()) rows", bundle: .module), live: hub.datasets.isCollecting(summary),
                current: object == sourceObject)]))
        let copies = hub.destinations(of: sourceObject).map { destination in
            Node(
                id: destination.id, role: .copy, target: destination.target, place: hub.connection(destination.target.connectionID),
                title: DataLabels.title(destination.target, hub: hub), detail: copyStatus(destination, rows: summary.rowCount), current: destination.target == object)
        }
        if !copies.isEmpty { columns.append(Column(edge: String(localized: "copied one way", bundle: .module), nodes: copies)) }
        return columns
    }

    private func copyStatus(_ destination: DataDestination, rows: Int) -> String {
        switch destination.detail {
        case "live copy": String(localized: "copy, updated live · in sync, \(rows.formatted()) of \(rows.formatted()) rows", bundle: .module)
        case "daily copy": String(localized: "copy, updated daily at 06:00 · last today", bundle: .module)
        case "sends new rows": String(localized: "each new row is posted here", bundle: .module)
        default: destination.detail
        }
    }

    private func agentsNode(_ writers: [DataWriter]) -> Node {
        let agents = writers.filter { if case .agent = $0.kind { true } else { false } }
        let names = agents.map(\.name).joined(separator: ", ")
        let session: String = if case .agent(let s)? = agents.first?.kind { s } else { "" }
        return Node(
            id: "agents", role: .agents, place: nil, title: names.isEmpty ? String(localized: "Agents", bundle: .module) : names,
            detail: String(localized: "session \(session)", bundle: .module), live: agents.contains { $0.live })
    }

    private func currentNode(role: Node.Role, detail: String) -> Node {
        Node(id: "current", role: role, target: object, place: hub.connection(object.connectionID), title: DataLabels.title(object, hub: hub), detail: detail, current: true)
    }

    // MARK: Desenho

    private func edge(_ label: String) -> some View {
        VStack(spacing: .zero) {
            Text(verbatim: label).dsFont(DS.Font.micro).foregroundStyle(DS.Color.textTertiary)
            Image(systemName: "arrow.right").font(.system(size: DS.Space.s3, weight: .semibold)).foregroundStyle(DS.Color.textTertiary)
        }
        .fixedSize()
    }

    private func chip(_ node: Node) -> some View {
        let content = HStack(spacing: DS.Space.s1_5) {
            if node.live { LiveDot() }
            switch node.role {
            case .agents: Image(systemName: "person.2").font(.system(size: DS.Space.s2_5 + 1)).foregroundStyle(DS.Color.textSecondary)
            case .query: Image(systemName: "terminal").font(.system(size: DS.Space.s2_5 + 1)).foregroundStyle(DS.Color.textSecondary)
            case .source: Image(systemName: "laptopcomputer").font(.system(size: DS.Space.s2_5 + 1)).foregroundStyle(DS.Color.textSecondary)
            case .copy, .direct:
                Image(systemName: node.place.map { DataSymbols.connection($0.kind) } ?? "tablecells").font(.system(size: DS.Space.s2_5 + 1)).foregroundStyle(DS.Color.textSecondary)
            }
            VStack(alignment: .leading, spacing: .zero) {
                HStack(spacing: DS.Space.s1) {
                    Text(verbatim: placePrefix(node) + node.title).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    if let environment = node.place?.environment { EnvironmentBadge(environment: environment) }
                    if node.current {
                        Text("You are here", bundle: .module).dsFont(DS.Font.keycap).foregroundStyle(DS.Color.dataKey)
                    }
                }
                Text(verbatim: node.detail).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, DS.Space.s1)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(node.current ? DS.Color.dataKey.opacity(0.1) : DS.Color.secondary))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(node.current ? DS.Color.dataKey.opacity(0.55) : DS.Color.border))
        .fixedSize()
        return Group {
            if let target = node.target, !node.current {
                ActionButton(.dataOpen, id: .dataFlowItem(node.id), argument: .select(target.key)) { content }.buttonStyle(.plain)
            } else {
                content.a11y(.dataFlowItem(node.id), kind: "text", label: node.title)
            }
        }
    }

    /// "Racky › books2", "Supabase › public.books": o lugar sempre antes do nome.
    private func placePrefix(_ node: Node) -> String {
        switch node.role {
        case .source: String(localized: "This Mac › ", bundle: .module)
        case .copy, .direct: node.place.map { $0.name == node.title ? "" : "\($0.name) › " } ?? ""
        case .agents, .query: ""
        }
    }
}

// MARK: Produção

/// Faixa em âmbar em todo objeto de uma conexão de produção: o que é, o que o usuário pode fazer e quem está gravando agora (com
/// "Pause").
struct DataProductionBanner: View {
    let hub: DataHubController
    let object: DataObject

    var body: some View {
        let connection = hub.connection(object.connectionID)
        let live = hub.writers(of: object).filter(\.live)
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: DS.Space.s3))
            Text(verbatim: String(localized: "Production · \(connection?.name ?? "")", bundle: .module)).dsFont(DS.Font.label)
            Text(verbatim: message(object, live: live.count)).dsFont(DS.Font.small).lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            if !live.isEmpty {
                DSButton(.dataPauseWriter, id: .dataProductionPause, live.count == 1 ? "Pause the agent" : "Pause agents", variant: .outline, size: .xs, symbol: "pause.fill", argument: .select("all"))
            }
        }
        .foregroundStyle(DS.Color.warning)
        .padding(.horizontal, DS.Space.s4)
        .frame(height: DS.Space.s8)
        .background(DS.Color.warning.opacity(0.08))
        .overlay(alignment: .bottom) { DS.Color.warning.opacity(0.3).frame(height: ComputersMetrics.separator) }
        .a11y(.dataProduction, kind: "banner", label: connection?.name ?? "")
    }

    private func message(_ object: DataObject, live: Int) -> String {
        // Uma frase com as regras: quem pode gravar aqui e o que você pode fazer.
        let writers = live == 0
            ? String(localized: "No agent is writing here now.", bundle: .module)
            : (live == 1 ? String(localized: "1 agent is writing here now (Pause stops new writes; rows already written stay).", bundle: .module)
                : String(localized: "\(live) agents are writing here now (Pause stops new writes; rows already written stay).", bundle: .module))
        return writers + " " + String(localized: "You can read freely; anything that changes data asks you to confirm.", bundle: .module)
    }
}

// MARK: Vazio

struct DataEmptyState: View {
    let hub: DataHubController

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            Image(systemName: "cylinder.split.1x2").font(.system(size: DS.Space.s8)).foregroundStyle(DS.Color.textQuaternary)
            Text("Pick a dataset or a table on the left", bundle: .module).dsFont(DS.Font.composerTitle).foregroundStyle(DS.Color.textPrimary)
            Text("Racky holds what your agents collected on this Mac. Connections are your own databases, storage and destinations: browse them here and let agents write to them.", bundle: .module)
                .dsFont(DS.Font.body).foregroundStyle(DS.Color.textTertiary).multilineTextAlignment(.center)
                .frame(maxWidth: DataMetrics.emptyTextWidth)
            DSButton(.dataAddConnection, "Add connection", variant: .outline, size: .sm, symbol: "plus")
        }
        .padding(DS.Space.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .a11y(.dataEmpty, kind: "text")
    }
}
