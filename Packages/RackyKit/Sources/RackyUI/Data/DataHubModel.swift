import Foundation
import RackyDesignSystem
import RackyStore

// Área Data (spec data-hub): o que está no Racky (datasets dos agentes) e o que está fora (conexões). Estes tipos descrevem lugares
// e objetos para o explorer, as tabs e a barra de localização. Na etapa 2 as conexões vêm de exemplo (`DataHubFixtures`); a etapa 3
// liga os drivers de verdade.

/// Tipo de conexão. A família decide o ícone, o agrupamento no "Add connection" e o que dá para fazer.
public enum DataConnectionKind: String, CaseIterable, Sendable, Codable {
    case postgres, supabase, mysql, sqlServer, sqlite
    case bigQuery, snowflake, clickHouse, databricks
    case s3, gcs, r2
    case googleSheets, airtable
    case webhook

    public enum Family: String, CaseIterable, Sendable { case database, warehouse, storage, spreadsheet, outgoing }

    public var family: Family {
        switch self {
        case .postgres, .supabase, .mysql, .sqlServer, .sqlite: .database
        case .bigQuery, .snowflake, .clickHouse, .databricks: .warehouse
        case .s3, .gcs, .r2: .storage
        case .googleSheets, .airtable: .spreadsheet
        case .webhook: .outgoing
        }
    }

    public var title: String {
        switch self {
        case .postgres: "PostgreSQL"
        case .supabase: "Supabase"
        case .mysql: "MySQL"
        case .sqlServer: "SQL Server"
        case .sqlite: "SQLite"
        case .bigQuery: "BigQuery"
        case .snowflake: "Snowflake"
        case .clickHouse: "ClickHouse"
        case .databricks: "Databricks"
        case .s3: "Amazon S3"
        case .gcs: "Google Cloud Storage"
        case .r2: "Cloudflare R2"
        case .googleSheets: "Google Sheets"
        case .airtable: "Airtable"
        case .webhook: "Webhook"
        }
    }

    /// O logo do tipo (cor da marca).
    public var brand: DSDataBrand {
        switch self {
        case .postgres: .postgres
        case .supabase: .supabase
        case .mysql: .mysql
        case .sqlServer: .sqlServer
        case .sqlite: .sqlite
        case .bigQuery: .bigQuery
        case .snowflake: .snowflake
        case .clickHouse: .clickHouse
        case .databricks: .databricks
        case .s3: .s3
        case .gcs: .gcs
        case .r2: .r2
        case .googleSheets: .googleSheets
        case .airtable: .airtable
        case .webhook: .webhook
        }
    }

    /// Uma linha que diz o que é ("Postgres hosted by Supabase").
    public var tagline: String {
        switch self {
        case .postgres: String(localized: "Any Postgres database (RDS, Neon, your own)", bundle: .module)
        case .supabase: String(localized: "Postgres hosted by Supabase", bundle: .module)
        case .mysql: String(localized: "MySQL or MariaDB", bundle: .module)
        case .sqlServer: String(localized: "Microsoft SQL Server or Azure SQL", bundle: .module)
        case .sqlite: String(localized: "A database file on this Mac", bundle: .module)
        case .bigQuery: String(localized: "Google Cloud data warehouse", bundle: .module)
        case .snowflake: String(localized: "Snowflake data warehouse", bundle: .module)
        case .clickHouse: String(localized: "Fast analytics database", bundle: .module)
        case .databricks: String(localized: "Lakehouse tables", bundle: .module)
        case .s3: String(localized: "Files in an AWS bucket", bundle: .module)
        case .gcs: String(localized: "Files in a Google Cloud bucket", bundle: .module)
        case .r2: String(localized: "Files in a Cloudflare bucket", bundle: .module)
        case .googleSheets: String(localized: "Rows in a spreadsheet tab", bundle: .module)
        case .airtable: String(localized: "Rows in an Airtable base", bundle: .module)
        case .webhook: String(localized: "Post new rows to a URL", bundle: .module)
        }
    }

    /// Webhook só recebe; o resto dá para navegar e gravar.
    public var canBrowse: Bool { self != .webhook }
    public var speaksSQL: Bool { family == .database || family == .warehouse }
}

public enum DataEnvironment: String, Sendable, Codable { case production, development }

public struct DataConnection: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: DataConnectionKind
    /// Nome que o usuário deu ("Supabase", "Analytics").
    public var name: String
    public var environment: DataEnvironment?
    /// Onde fica (host, projeto, bucket, URL), sem segredo.
    public var address: String
    public var children: [DataNode]
}

/// Um nó do explorer dentro de uma conexão.
public struct DataNode: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case schema, table, view, bucket, folder, file, spreadsheet, sheet }
    public var id: String
    public var kind: Kind
    public var name: String
    /// Linhas (tabela, aba) ou bytes (arquivo).
    public var size: Int?
    public var children: [DataNode] = []
}

/// O que está aberto numa tab da área Data.
public enum DataObject: Hashable, Sendable {
    case dataset(String)
    case table(connection: String, schema: String, name: String)
    case query(connection: String, id: Int)
    case folder(connection: String, path: [String])
    case webhook(connection: String)
    case tab(connection: String, spreadsheet: String, name: String)

    public var connectionID: String? {
        switch self {
        case .dataset: nil
        case .table(let c, _, _), .query(let c, _), .folder(let c, _), .webhook(let c), .tab(let c, _, _): c
        }
    }
}

/// Quem grava num lugar: um agente (com a sessão) ou um sync.
public struct DataWriter: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable, Equatable { case agent(session: String), sync(from: DataObject) }
    public var id: String
    public var kind: Kind
    /// "Codex 1", "Sync from books2".
    public var name: String
    public var live: Bool
    /// "every new row", "daily at 06:00", "last run 3m ago".
    public var detail: String
}

/// Para onde algo vai (a seta → da linha de fluxo).
public struct DataDestination: Identifiable, Equatable, Sendable {
    public var id: String
    public var target: DataObject
    public var detail: String
}

/// Grade simples de uma tabela, arquivo ou resultado de consulta (exemplo na etapa 2).
public struct DataGrid: Equatable, Sendable {
    public struct Column: Equatable, Sendable {
        public var name: String
        public var type: String
        public var key = false
        public var nullable = true
    }
    public var columns: [Column]
    public var rows: [[String]]
    public var total: Int
}

/// Uma entrega a um webhook (log).
public struct DataDelivery: Identifiable, Equatable, Sendable {
    public var id: Int
    public var at: Date
    public var status: Int
    public var rows: Int
    public var milliseconds: Int
}
