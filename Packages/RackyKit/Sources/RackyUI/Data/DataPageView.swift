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
                    DataFlowLine(hub: hub, object: active)
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
                    section(String(localized: "Racky", bundle: .module), caption: String(localized: "Stored in this app, on this Mac", bundle: .module), id: "racky")
                    racky
                    section(String(localized: "Connections", bundle: .module), caption: String(localized: "Outside Racky: your databases, storage and endpoints", bundle: .module), id: "connections")
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
        HStack(spacing: 0) {
            ForEach(hub.tabs, id: \.self) { object in tab(object) }
            Spacer(minLength: 0)
        }
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
                    Text(verbatim: place?.name ?? String(localized: "Racky", bundle: .module)).dsFont(DS.Font.small).foregroundStyle(DS.Color.textQuaternary).lineLimit(1)
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
        .frame(maxWidth: DataMetrics.tabMaxWidth, maxHeight: .infinity)
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
        case .dataset: String(localized: "Dataset in Racky", bundle: .module)
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
                    Text(verbatim: String(localized: "Copy of Racky › \(source)", bundle: .module)).dsFont(DS.Font.small).foregroundStyle(DS.Color.dataKey)
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
    private var placeName: String { connection?.name ?? String(localized: "Racky", bundle: .module) }

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
                BrandMark(size: DS.Space.s3 + DS.Space.s0_5)
                Text("Racky", bundle: .module).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                Text("in this app", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
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

// MARK: Fluxo

/// "De onde vem e para onde vai", sempre com as mesmas duas palavras: **Comes from** (agentes que gravam aqui, cópias de um dataset
/// do Racky, você numa consulta) e **Goes to** (cópias deste objeto em outros lugares). Cada item diz o que é e abre o lugar dele.
struct DataFlowLine: View {
    let hub: DataHubController
    let object: DataObject

    var body: some View {
        let writers = hub.writers(of: object)
        let destinations = hub.destinations(of: object)
        HStack(spacing: DS.Space.s2) {
            label("arrow.down.right", String(localized: "Comes from", bundle: .module))
            if writers.isEmpty {
                Text(verbatim: emptyWriters).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary).lineLimit(1)
            }
            ForEach(writers) { writer in writerChip(writer) }
            if !destinations.isEmpty {
                DS.Color.border.frame(width: ComputersMetrics.separator, height: DS.Space.s4).padding(.horizontal, DS.Space.s1)
                label("arrow.up.right", String(localized: "Goes to", bundle: .module))
                ForEach(destinations) { destination in destinationChip(destination) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(height: DataMetrics.flowHeight)
        .background(DS.Color.chrome.opacity(0.5))
        .overlay(alignment: .bottom) { DS.Color.border.frame(height: ComputersMetrics.separator) }
        .a11y(.dataFlow, kind: "group", label: (writers.map(\.name) + destinations.map { $0.target.key }).joined(separator: ", "))
    }

    private var emptyWriters: String {
        switch object {
        case .query: String(localized: "You, with this query", bundle: .module)
        case .dataset: String(localized: "No agent has written here yet", bundle: .module)
        default: String(localized: "Nothing in Racky writes here", bundle: .module)
        }
    }

    private func label(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: DS.Space.s1) {
            Image(systemName: symbol).font(.system(size: DS.Space.s2_5, weight: .semibold))
            Text(verbatim: title).dsFont(DS.Font.label)
        }
        .foregroundStyle(DS.Color.textTertiary)
        .fixedSize()
    }

    private func writerChip(_ writer: DataWriter) -> some View {
        let source: DataObject? = if case .sync(let from) = writer.kind, case .dataset(let name) = from, let id = hub.datasetID(named: name) { .dataset(id) } else { nil }
        let content = HStack(spacing: DS.Space.s1_5) {
            if writer.live { LiveDot() }
            switch writer.kind {
            case .agent(let session):
                Text("Agent", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                Text(verbatim: writer.name).dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                Text(verbatim: String(localized: "in \(session)", bundle: .module) + (writer.detail.isEmpty ? "" : " · \(writer.detail)"))
                    .dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            case .sync:
                Text("Copy of", bundle: .module).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
                BrandMark(size: DS.Space.s3)
                Text(verbatim: "Racky › \(writer.name)").dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                Text(verbatim: writer.detail).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(.horizontal, DS.Space.s2)
        .frame(height: DataMetrics.chipHeight)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.secondary))
        .fixedSize()
        return Group {
            if let source {
                ActionButton(.dataOpen, id: .dataFlowItem(writer.id), argument: .select(source.key)) { content }.buttonStyle(.plain)
            } else {
                content.a11y(.dataFlowItem(writer.id), kind: "text", label: writer.name)
            }
        }
    }

    private func destinationChip(_ destination: DataDestination) -> some View {
        let connection = hub.connection(destination.target.connectionID)
        return ActionButton(.dataOpen, id: .dataFlowItem(destination.id), argument: .select(destination.target.key)) {
            HStack(spacing: DS.Space.s1_5) {
                Image(systemName: connection.map { DataSymbols.connection($0.kind) } ?? "tablecells").font(.system(size: DS.Space.s2_5)).foregroundStyle(DS.Color.textSecondary)
                Text(verbatim: "\(connection?.name ?? "") › \(DataLabels.title(destination.target, hub: hub))").dsFont(DS.Font.label).foregroundStyle(DS.Color.textPrimary)
                if let environment = connection?.environment { EnvironmentBadge(environment: environment) }
                Text(verbatim: destination.detail).dsFont(DS.Font.small).foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Space.s2)
            .frame(height: DataMetrics.chipHeight)
            .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.secondary))
            .fixedSize()
        }
        .buttonStyle(.plain)
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
        let you: String = if case .query = object {
            String(localized: "Queries that change data ask you to confirm first.", bundle: .module)
        } else {
            String(localized: "You're viewing it read only; edits ask you to confirm.", bundle: .module)
        }
        guard live > 0 else { return you }
        return you + " " + (live == 1 ? String(localized: "1 agent is writing here now.", bundle: .module) : String(localized: "\(live) agents are writing here now.", bundle: .module))
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
