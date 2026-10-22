import Foundation

/// Conexões de exemplo da etapa 2 (spec data-hub): servem para desenhar e testar as telas antes dos drivers. Só aparecem com
/// `RACKY_DATA_DEMO=1` (e nos testes de captura).
enum DataHubFixtures {
    static let supabase = "conn-supabase"
    static let analytics = "conn-analytics"
    static let bucket = "conn-s3"
    static let sheets = "conn-sheets"
    static let webhook = "conn-webhook"

    static var connections: [DataConnection] {
        [
            DataConnection(
                id: supabase, kind: .supabase, name: "Supabase", environment: .production, address: "db.xkqzrwm.supabase.co · postgres",
                children: [
                    DataNode(id: "\(supabase)/public", kind: .schema, name: "public", children: [
                        DataNode(id: "\(supabase)/public/hotels", kind: .table, name: "hotels", size: 12_430),
                        DataNode(id: "\(supabase)/public/books", kind: .table, name: "books", size: 80),
                        DataNode(id: "\(supabase)/public/permits", kind: .table, name: "permits", size: 3_112),
                        DataNode(id: "\(supabase)/public/hotel_prices_daily", kind: .view, name: "hotel_prices_daily", size: 941),
                    ]),
                    DataNode(id: "\(supabase)/analytics", kind: .schema, name: "analytics", children: [
                        DataNode(id: "\(supabase)/analytics/price_history", kind: .table, name: "price_history", size: 240_512),
                    ]),
                ]),
            DataConnection(
                id: analytics, kind: .postgres, name: "Analytics", environment: .development,
                address: "analytics-dev.c9x2.us-east-1.rds.amazonaws.com",
                children: [
                    DataNode(id: "\(analytics)/public", kind: .schema, name: "public", children: [
                        DataNode(id: "\(analytics)/public/listings", kind: .table, name: "listings", size: 5_120),
                        DataNode(id: "\(analytics)/public/runs", kind: .table, name: "runs", size: 88),
                    ]),
                ]),
            DataConnection(
                id: bucket, kind: .s3, name: "scrapes-raw", environment: nil, address: "s3://scrapes-raw · us-east-1",
                children: [
                    DataNode(id: "\(bucket)/books", kind: .folder, name: "books", children: [
                        DataNode(id: "\(bucket)/books/2026-10-21", kind: .folder, name: "2026-10-21"),
                        DataNode(id: "\(bucket)/books/2026-10-22", kind: .folder, name: "2026-10-22"),
                    ]),
                    DataNode(id: "\(bucket)/hotels", kind: .folder, name: "hotels"),
                ]),
            DataConnection(
                id: sheets, kind: .googleSheets, name: "Pricing", environment: nil, address: "docs.google.com · Hotel pricing",
                children: [
                    DataNode(id: "\(sheets)/pricing", kind: .spreadsheet, name: "Hotel pricing", children: [
                        DataNode(id: "\(sheets)/pricing/LA", kind: .sheet, name: "LA", size: 412),
                        DataNode(id: "\(sheets)/pricing/NYC", kind: .sheet, name: "NYC", size: 390),
                    ]),
                ]),
            DataConnection(id: webhook, kind: .webhook, name: "Price alerts", environment: nil, address: "https://hooks.acme.dev/racky/price-alerts", children: []),
        ]
    }

    /// Quem grava em cada lugar.
    static func writers(of object: DataObject, datasetNamed: (String) -> String?) -> [DataWriter] {
        switch object {
        case .table(supabase, "public", "books"):
            return [DataWriter(id: "copy-books", kind: .sync(from: .dataset("books2")), name: "books2", live: false, detail: "every new row · last copy 5h ago")]
        case .table(supabase, "public", "hotels"):
            return [
                DataWriter(id: "agent-claude", kind: .agent(session: "Hotel prices"), name: "Claude Code", live: true, detail: "writing now"),
                DataWriter(id: "agent-codex", kind: .agent(session: "Hotel prices"), name: "Codex 1", live: true, detail: "writing now"),
            ]
        case .webhook(webhook):
            return [DataWriter(id: "copy-hook", kind: .sync(from: .dataset("hotels")), name: "hotels", live: false, detail: "batches of 50 rows · last 2m ago")]
        case .folder(bucket, let path) where path.first == "books":
            return [DataWriter(id: "copy-s3", kind: .sync(from: .dataset("books2")), name: "books2", live: false, detail: "daily at 06:00 · Parquet")]
        default:
            return []
        }
    }

    /// Para onde um dataset do Racky vai (pelo nome).
    static func destinations(ofDataset name: String) -> [DataDestination] {
        switch name {
        case "books2", "books":
            return [
                DataDestination(id: "d1", target: .table(connection: supabase, schema: "public", name: "books"), detail: "copy · every new row"),
                DataDestination(id: "d2", target: .folder(connection: bucket, path: ["books"]), detail: "copy · daily at 06:00"),
            ]
        case "hotels":
            return [DataDestination(id: "d3", target: .webhook(connection: webhook), detail: "batches of 50 rows")]
        default:
            return []
        }
    }

    /// Os mesmos livros do dataset books2 dos prints (a cópia tem os mesmos valores da fonte).
    static let bookTitles = ["Cometh the Hour", "Crazy Love", "Daily Fantasy Sports", "Dear Mr. Knightley", "Demigods & Magicians", "Doctor Sleep", "Don't Get Caught", "Eat Fat, Get Thin"]
    static func book(_ i: Int) -> (title: String, price: String, rating: String, url: String) {
        ("\(bookTitles[i % bookTitles.count]) \(i)", String(format: "%.2f", 11.21 + Double(i * 7 % 50)), "\(1 + i % 5)", "books.toscrape.com/catalogue/book_\(900 + i)")
    }

    static let hotelNames = ["Grand Plaza", "Harbor View", "The Ritz", "Shutters on the Beach", "Hotel Figueroa", "The Hoxton", "Ace Hotel", "Freehand LA", "Line Hotel", "Hotel Erwin"]

    static func grid(for object: DataObject) -> DataGrid {
        switch object {
        case .table(_, _, "books"):
            return DataGrid(
                columns: [.init(name: "url", type: "text", key: true, nullable: false), .init(name: "title", type: "text"), .init(name: "price", type: "numeric"),
                          .init(name: "rating", type: "int4"), .init(name: "copied_at", type: "timestamptz")],
                rows: (0..<12).map { n in
                    let b = book(79 - n)
                    return [b.url, b.title, b.price, b.rating, "2026-10-22 07:24:16"]
                },
                total: 80)
        case .table(_, _, "price_history"), .table(_, _, "hotels"), .table(_, _, "hotel_prices_daily"), .table(_, _, "listings"):
            return DataGrid(
                columns: [.init(name: "url", type: "text", key: true, nullable: false), .init(name: "name", type: "text"), .init(name: "price", type: "int4"),
                          .init(name: "rating", type: "numeric"), .init(name: "city", type: "text"), .init(name: "seen_at", type: "timestamptz")],
                rows: (0..<14).map { i in
                    ["booking.com/hotel/us/stay-\(1200 - i)", "\(hotelNames[i % hotelNames.count]) \(1200 - i)", "\(140 + (i * 37) % 480)",
                     String(format: "%.1f", 3.6 + Double(i % 13) / 10), i % 3 == 0 ? "New York" : "Los Angeles", "2026-10-22 11:\(String(format: "%02d", 59 - i)):04"]
                },
                total: 12_430)
        case .query:
            return DataGrid(
                columns: [.init(name: "city", type: "text"), .init(name: "hotels", type: "int8"), .init(name: "avg_price", type: "numeric"), .init(name: "min_price", type: "int4")],
                rows: [["Los Angeles", "8,212", "312.40", "89"], ["New York", "4,104", "388.15", "121"], ["San Francisco", "114", "296.02", "140"]],
                total: 3)
        case .folder:
            return DataGrid(
                columns: [.init(name: "url", type: "string"), .init(name: "title", type: "string"), .init(name: "price", type: "double"), .init(name: "rating", type: "int32")],
                rows: (0..<10).map { n in let b = book(79 - n); return [b.url, b.title, b.price, b.rating] },
                total: 80)
        case .tab:
            return DataGrid(
                columns: [.init(name: "A · Hotel", type: "text"), .init(name: "B · Price", type: "number"), .init(name: "C · Updated", type: "date")],
                rows: (0..<10).map { i in ["\(hotelNames[i]) \(1200 - i)", "\(140 + (i * 37) % 480)", "2026-10-22"] },
                total: 412)
        default:
            return DataGrid(columns: [], rows: [], total: 0)
        }
    }

    struct FileEntry: Identifiable, Equatable {
        var id: String { name }
        var name: String
        var folder: Bool
        var format: String
        var bytes: Int
        var modified: String
    }

    static func files(in path: [String]) -> [FileEntry] {
        switch path {
        case []:
            return [FileEntry(name: "books", folder: true, format: "", bytes: 0, modified: "5h ago"), FileEntry(name: "hotels", folder: true, format: "", bytes: 0, modified: "1d ago")]
        case ["books"]:
            return [FileEntry(name: "2026-10-21", folder: true, format: "", bytes: 0, modified: "1d ago"), FileEntry(name: "2026-10-22", folder: true, format: "", bytes: 0, modified: "5h ago")]
        default:
            return [
                FileEntry(name: "books-run-01.parquet", folder: false, format: "Parquet", bytes: 18_442, modified: "5h ago"),
                FileEntry(name: "books-run-01.jsonl", folder: false, format: "JSON Lines", bytes: 41_207, modified: "5h ago"),
                FileEntry(name: "_manifest.json", folder: false, format: "JSON", bytes: 612, modified: "5h ago"),
            ]
        }
    }

    static func deliveries(now: Date) -> [DataDelivery] {
        (0..<12).map { i in
            DataDelivery(id: i, at: now.addingTimeInterval(Double(-i * 95)), status: i == 4 ? 502 : 200, rows: i == 4 ? 0 : 50, milliseconds: 120 + (i * 37) % 300)
        }
    }

    /// Corpo de uma entrega ao webhook (prévia).
    static let samplePayload = """
        [
          { "name": "Grand Plaza 1200", "price": 140, "rating": 3.6, "url": "https://booking.com/hotel/us/stay-1200" },
          { "name": "Harbor View 1199", "price": 177, "rating": 3.7, "url": "https://booking.com/hotel/us/stay-1199" },
          … 48 more
        ]
        """

    static let sampleQuery = """
        select city, count(*) as hotels, round(avg(price), 2) as avg_price, min(price) as min_price
        from public.hotels
        group by city
        order by hotels desc;
        """
}
