import AgentBoxDocker
import Foundation
import Testing

@testable import AgentBoxCore

// T3-06 (AC-420…423): `box_collect` lê o run folder (mesmo sem o computador), refaz a validação contra o reqlog de hoje e devolve ao pai
// resultado, marcas por afirmação e timeline. Unidade sobre pastas temporárias; a integração com o scheduler está em `ResultFlowTests`.

enum RunFixture {
    static let ids = ["01ARZ3NDEKTSV4RRFFQ69G5FAV", "01ARZ3NDEKTSV4RRFFQ69G5FAW", "01ARZ3NDEKTSV4RRFFQ69G5FAX", "01ARZ3NDEKTSV4RRFFQ69G5FAY"]

    static func temp() throws -> RunFolder {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("abx-run-\(UUID().uuidString.lowercased())/phoenix-az", isDirectory: true)
        let run = RunFolder(root: root)
        try run.ensureLayout()
        return run
    }

    static func cleanup(_ run: RunFolder) { try? FileManager.default.removeItem(at: run.root.deletingLastPathComponent()) }

    /// Registros do reqlog com a cadeia de hash válida (como o egress grava).
    static func seed(_ run: RunFolder, _ records: [(id: String, trust: String)]) async throws {
        let log = ChainedLog(file: run.requestsFile)
        for (n, record) in records.enumerated() {
            try await log.append([
                "id": .string(record.id), "trust": .string(record.trust), "method": "GET", "status": 200, "source": "browser",
                "url": .string("https://aca-prod.example.test/permits/\(n)"),
            ])
        }
    }

    static func write(_ run: RunFolder, result json: String) throws {
        try Data(json.utf8).write(to: run.resultFile)
    }
}

@Suite("T3-06 coleta do run") struct ResultCollectorTests {
    @Test func handwrittenResultWithFiveClaimsIsMarkedPerField() async throws {
        // AC-421: 5 afirmações; 3 citam ids que existem, 1 cita um id inexistente e 1 não cita nada.
        let run = try RunFixture.temp()
        defer { RunFixture.cleanup(run) }
        let ids = RunFixture.ids
        try await RunFixture.seed(run, [(ids[0], "observed"), (ids[1], "observed"), (ids[2], "reported")])
        try RunFixture.write(run, result: """
            {"permits": 12, "owner": "ACME LLC (request \(ids[1]))", "status": "Issued — \(ids[2])", "ghost": "see \(ids[3])", "notes": "looks fine"}
            """)
        let collected = RunCollector.collect(run: run, name: "phoenix-az")
        #expect(collected.handwritten, "result.json was not written by result_submit")
        #expect(collected.totalFields == 5)
        let by = Dictionary(uniqueKeysWithValues: collected.fields.map { ($0.pointer, $0) })
        #expect(by["/owner"]?.status == .verified && by["/status"]?.status == .verified)
        #expect(by["/ghost"]?.status == .citedMissing && by["/ghost"]?.statusLabel == "Cited request not found")
        #expect(by["/notes"]?.status == .notVerified && by["/notes"]?.statusLabel == "Not verified")
        #expect(by["/permits"]?.status == .notVerified)
        #expect(collected.verified == 2 && collected.citedMissing == 1 && collected.notVerified == 2)
        // O link leva ao request do reqlog, com o selo do trust (CS-263).
        let link = try #require(by["/status"]?.links.first)
        #expect(link.kind == .request && link.exists && link.trust == "reported" && link.summary?.hasPrefix("200 GET https://aca-prod") == true)
        #expect(by["/ghost"]?.links.first?.exists == false)
        #expect(collected.integrity == .ok(lines: 3))
    }

    @Test func submittedResultKeepsItsFileCitationsAndAHandEditInvalidatesThem() async throws {
        let run = try RunFixture.temp()
        defer { RunFixture.cleanup(run) }
        let id = RunFixture.ids[0]
        try await RunFixture.seed(run, [(id, "observed")])
        try Data("a,b\n1,2\n".utf8).write(to: run.work.appendingPathComponent("permits.csv"))
        let result: JSON = ["total": 12, "csv": "permits.csv"]
        let data = result.data(pretty: true)
        try data.write(to: run.resultFile)
        let stored: JSON = [
            "result_sha256": .string(RunCollector.sha256(data)),
            "fields": [["pointer": "/total", "citations": [["ref": .string(id)]]], ["pointer": "/csv", "citations": [["ref": "/work/permits.csv"]]]],
        ]
        try stored.data().write(to: run.validationFile)

        var collected = RunCollector.collect(run: run, name: "phoenix-az")
        #expect(!collected.handwritten && collected.verified == 2)
        let file = try #require(collected.fields.first { $0.pointer == "/csv" }?.links.first)
        #expect(file.kind == .file && file.exists && file.fileURL?.lastPathComponent == "permits.csv")

        // Reescrito à mão depois do result_submit: as marcas velhas não valem, volta o padrão de ids.
        try RunFixture.write(run, result: #"{"total": 99, "csv": "permits.csv"}"#)
        collected = RunCollector.collect(run: run, name: "phoenix-az")
        #expect(collected.handwritten && collected.verified == 0 && collected.notVerified == 2)
    }

    @Test func citationsThatEscapeWorkOrFollowSymlinksNeverVerify() async throws {
        let run = try RunFixture.temp()
        defer { RunFixture.cleanup(run) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("abx-secret-\(UUID().uuidString.lowercased())")
        try Data("secret".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: run.work.appendingPathComponent("leak.txt"), withDestinationURL: outside)
        let data = (["a": "x", "b": "y"] as JSON).data(pretty: true)
        try data.write(to: run.resultFile)
        let stored: JSON = [
            "result_sha256": .string(RunCollector.sha256(data)),
            "fields": [["pointer": "/a", "citations": [["ref": "/work/leak.txt"]]], ["pointer": "/b", "citations": [["ref": "../../etc/passwd"]]]],
        ]
        try stored.data().write(to: run.validationFile)
        let collected = RunCollector.collect(run: run, name: "phoenix-az")
        #expect(collected.verified == 0)
        #expect(collected.fields.allSatisfy { $0.status == .citedMissing && $0.links.allSatisfy { !$0.exists && $0.fileURL == nil } })
    }

    @Test func aSymlinkedResultJSONIsNotFollowed() throws {
        let run = try RunFixture.temp()
        defer { RunFixture.cleanup(run) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("abx-secret-\(UUID().uuidString.lowercased()).json")
        try Data(#"{"stolen": true}"#.utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: run.resultFile, withDestinationURL: outside)
        let collected = RunCollector.collect(run: run, name: "phoenix-az")
        #expect(collected.result == nil && collected.fields.isEmpty)
        #expect(collected.resultNote?.contains("symlinks") == true)
    }

    @Test func missingOrInvalidResultsExplainThemselves() throws {
        let run = try RunFixture.temp()
        defer { RunFixture.cleanup(run) }
        #expect(RunCollector.collect(run: run, name: "x").resultNote == "No result.json yet")
        try RunFixture.write(run, result: "not json")
        #expect(RunCollector.collect(run: run, name: "x").resultNote == "result.json is not valid JSON")
        try RunFixture.write(run, result: "[1,2]")
        #expect(RunCollector.collect(run: run, name: "x").resultNote == "result.json must be an object")
    }

    @Test func tamperedLogsAreFlagged() async throws {
        let run = try RunFixture.temp()
        defer { RunFixture.cleanup(run) }
        try await RunFixture.seed(run, [(RunFixture.ids[0], "observed"), (RunFixture.ids[1], "observed")])
        var text = try String(contentsOf: run.requestsFile, encoding: .utf8)
        text = text.replacingOccurrences(of: "permits/0", with: "permits/9")
        try Data(text.utf8).write(to: run.requestsFile)
        #expect(RunCollector.collect(run: run, name: "x").integrity == .tampered(line: 2))
    }

    @Test func jsonRespectsIncludeAndKeepsTheSummaryUnder20kCharacters() async throws {
        let run = try RunFixture.temp()
        defer { RunFixture.cleanup(run) }
        try await RunFixture.seed(run, [(RunFixture.ids[0], "observed")])
        var fields: [String: JSON] = [:]
        for i in 0..<400 { fields["field\(i)"] = .string(String(repeating: "x", count: 200) + " \(RunFixture.ids[0])") }
        try JSON.object(fields).data().write(to: run.resultFile)
        try Data(String(repeating: "12:00:00.000  HTTP    200 GET /x\n", count: 2000).utf8).write(to: run.timelineFile)
        let collected = RunCollector.collect(run: run, name: "phoenix-az")
        let full = collected.json()
        #expect(full["summary_md"]?.string?.count ?? .max <= RunCollector.summaryLimit)
        #expect(full["result"]?["truncated"] == true, "a result bigger than the summary limit goes by path, not inline")
        #expect(full["paths"]?["work"]?.string == run.work.path && full["validation"]?["summary"]?["verified"] == 400)
        let only = collected.json(include: [.validation])
        #expect(only["result"] == nil && only["timeline_md"] == nil && only["validation"] != nil && only["summary_md"] != nil)
    }

    @Test func summaryMarksUnverifiedClaimsForTheParent() async throws {
        let run = try RunFixture.temp()
        defer { RunFixture.cleanup(run) }
        try await RunFixture.seed(run, [(RunFixture.ids[0], "observed")])
        try RunFixture.write(run, result: #"{"price": "10 \#(RunFixture.ids[0])", "claim": "unsupported", "ghost": "\#(RunFixture.ids[3])"}"#)
        let md = RunCollector.collect(run: run, name: "phoenix-az").summaryMarkdown()
        #expect(md.contains("phoenix-az: 1 verified · 1 cited request not found · 1 not verified"))
        #expect(md.contains("| /claim | unsupported | Not verified | - |"))
        #expect(md.contains("\(RunFixture.ids[3]) (not found)"))
        #expect(md.contains("Log integrity: OK"))
    }
}

@Suite("T3-06 pasta do run no host") struct RunArchiveTests {
    @Test func metadataRoundTripsAndNeedsNoNetwork() throws {
        let run = try RunFixture.temp()
        defer { RunFixture.cleanup(run) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var meta = RunMetadata(computer: "phoenix-az", display: "headless", proxy: "zyte-us", parent: "parent-1", child: "parent-1-w1", batch: "permits-oct", session: "permits-oct", startedAt: start)
        run.writeMetadata(meta)
        #expect(run.readMetadata() == meta && run.readMetadata()?.outcome == .running && run.readMetadata()?.durationSeconds == nil)
        meta.endedAt = start.addingTimeInterval(125)
        meta.outcome = .released
        run.writeMetadata(meta)
        #expect(run.readMetadata()?.durationSeconds == 125 && run.readMetadata()?.outcome == .released)
        #expect(FileManager.default.fileExists(atPath: run.root.appendingPathComponent("box.json").path))
    }

    @Test func aRepeatedNameArchivesThePreviousRunAndNeverDeletesIt() async throws {
        let run = try RunFixture.temp()
        defer { RunFixture.cleanup(run) }
        #expect(!run.hasContent, "the empty layout is not a previous run")
        #expect(try RunArchive.archivePrevious(run: run, name: "phoenix-az") == nil)
        try RunFixture.write(run, result: #"{"a": 1}"#)
        try Data("ok".utf8).write(to: run.logs.appendingPathComponent("journal.jsonl"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try #require(try RunArchive.archivePrevious(run: run, name: "phoenix-az", now: now))
        #expect(first.deletingLastPathComponent().lastPathComponent == "_archive" && first.lastPathComponent.hasPrefix("phoenix-az-"))
        #expect(FileManager.default.fileExists(atPath: first.appendingPathComponent("work/result.json").path))
        #expect(!FileManager.default.fileExists(atPath: run.root.path), "the live folder is free for the new run")
        // Dois arquivamentos no mesmo segundo não se sobrescrevem.
        try run.ensureLayout()
        try RunFixture.write(run, result: #"{"a": 2}"#)
        let second = try #require(try RunArchive.archivePrevious(run: run, name: "phoenix-az", now: now))
        #expect(second != first && FileManager.default.fileExists(atPath: first.path) && FileManager.default.fileExists(atPath: second.path))
    }

    @Test func sessionFoldersListRunsButNotTheArchiveOrBatchMarkers() throws {
        let run = try RunFixture.temp()
        defer { RunFixture.cleanup(run) }
        let session = run.root.deletingLastPathComponent()
        let other = RunFolder(root: session.appendingPathComponent("austin-tx", isDirectory: true))
        try other.ensureLayout()
        try FileManager.default.createDirectory(at: session.appendingPathComponent("_archive/phoenix-az-1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: session.appendingPathComponent("_batches/permits-oct"), withIntermediateDirectories: true)
        #expect(RunArchive.runs(inSession: session).map { $0.root.lastPathComponent } == ["austin-tx", "phoenix-az"])
    }

    @Test func sessionSlugs() {
        #expect(RunArchive.slug("Permits Oct!", fallback: "p") == "permits-oct")
        #expect(RunArchive.slug("  houston / permits  ", fallback: "p") == "houston-permits")
        #expect(RunArchive.slug("日本語", fallback: "abcd1234") == "abcd1234")
        #expect(RunArchive.slug(nil, fallback: "abcd1234") == "abcd1234")
        #expect(RunArchive.slug("../../etc", fallback: "p") == "etc", "no path separators survive")
    }
}
