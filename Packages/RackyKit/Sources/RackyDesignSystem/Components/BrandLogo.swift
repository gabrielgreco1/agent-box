import AppKit
import SwiftUI

/// Marca de um lugar de dados (banco, warehouse, storage, planilha, webhook): o logo na cor da marca, sozinho ou num ladrilho
/// neutro. Os SVGs vêm da Simple Icons (CC0) e da Devicon (MIT); `sources.json` guarda a origem.
public enum DSDataBrand: String, CaseIterable, Sendable {
    case postgres, supabase, mysql, sqlServer, sqlite
    case bigQuery, snowflake, clickHouse, databricks
    case s3, gcs, r2
    case googleSheets, airtable
    case webhook
    case prefect

    var file: String? {
        switch self {
        case .postgres: "data-postgresql"
        case .supabase: "data-supabase"
        case .mysql: "data-mysql"
        case .sqlServer: "data-microsoftsqlserver"
        case .sqlite: "data-sqlite"
        case .bigQuery: "data-googlebigquery"
        case .snowflake: "data-snowflake"
        case .clickHouse: "data-clickhouse"
        case .databricks: "data-databricks"
        case .s3: "data-amazons3"
        case .gcs: "data-googlecloudstorage"
        case .r2: "data-cloudflare"
        case .googleSheets: "data-googlesheets"
        case .airtable: "data-airtable"
        case .webhook: nil
        case .prefect: "data-prefect"
        }
    }

    /// Cor da marca; as muito escuras (SQLite) clareadas para aparecer no fundo escuro.
    public var color: Color {
        let hex: UInt32 = switch self {
        case .postgres: 0x6B8FEF
        case .supabase: 0x3FCF8E
        case .mysql: 0x5D96C8
        case .sqlServer: 0xE0484B
        case .sqlite: 0x5AA4D6
        case .bigQuery: 0x669DF6
        case .snowflake: 0x29B5E8
        case .clickHouse: 0xFFCC01
        case .databricks: 0xFF3621
        case .s3: 0x6DBE45
        case .gcs: 0xAECBFA
        case .r2: 0xF38020
        case .googleSheets: 0x34A853
        case .airtable: 0x18BFFF
        case .webhook: 0xD5568C
        case .prefect: 0x7DA2F5
        }
        return DSRGBA(hex: hex).color
    }
}

public struct DSDataLogo: View {
    private let brand: DSDataBrand
    private let size: CGFloat
    private let tile: Bool

    /// `tile`: o logo num quadrado arredondado com o fundo da marca (explorer, Add connection); sem ele, só o logo.
    public init(_ brand: DSDataBrand, size: CGFloat, tile: Bool = false) {
        self.brand = brand
        self.size = size
        self.tile = tile
    }

    public var body: some View {
        Group {
            if tile {
                // Ladrilho neutro: a cor é só do logo, nunca do fundo (sem brilho nem tinta).
                mark(size: size * 0.6)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.24).fill(DS.Color.secondary))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(DS.Color.border))
            } else {
                mark(size: size)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func mark(size: CGFloat) -> some View {
        if let image = DSDataLogoImages.image(brand) {
            Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .foregroundStyle(brand.color)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "point.3.filled.connected.trianglepath.dotted").font(.system(size: size * 0.82, weight: .semibold))
                .foregroundStyle(brand.color)
                .frame(width: size, height: size)
        }
    }
}

@MainActor
enum DSDataLogoImages {
    private static var cache: [DSDataBrand: NSImage] = [:]

    static func image(_ brand: DSDataBrand) -> NSImage? {
        if let cached = cache[brand] { return cached }
        guard let file = brand.file, let url = Bundle.module.url(forResource: file, withExtension: "svg", subdirectory: "AgentLogos"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache[brand] = image
        return image
    }
}
