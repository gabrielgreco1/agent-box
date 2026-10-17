import AgentBoxCore
import AgentBoxDesignSystem
import AppKit
import SnapshotTesting
import SwiftUI
import Testing

@testable import AgentBoxUI

/// Snapshots das abas do módulo Insights (Claude, Codex, Machine, Proxy) em largura cheia (310, padrão do painel direito),
/// larga (480) e compacta (220). Dados 100% sintéticos (`InsightsPreviewData`). Gravar com `AB_RECORD_SNAPSHOTS=1`.
@MainActor
@Suite(.serialized) struct InsightsSnapshotTests {
    func snap(_ model: InsightsModel, compact: Bool = false, size: CGSize, name: String, line: UInt = #line) {
        DSFonts.registerIfNeeded()
        let previous = MotionPolicy.shared.preference
        MotionPolicy.shared.preference = .on  // valores finais, sem contagem em andamento
        defer { MotionPolicy.shared.preference = previous }
        let root = InsightsModuleView(model: model, compact: compact)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        withSnapshotTesting(record: ComponentSnapshotTests.recording) {
            assertSnapshot(of: host, as: .image(precision: 0.98, perceptualPrecision: 0.97), named: name, testName: "insights", line: line)
        }
    }

    static let tall = CGSize(width: 310, height: 1_040)

    @Test func claudeFull() { snap(InsightsPreviewData.model(tab: .claude), size: Self.tall, name: "claude-310") }
    @Test func claudeEstimated() { snap(InsightsPreviewData.model(tab: .claude, estimated: true), size: CGSize(width: 310, height: 760), name: "claude-estimated-310") }
    @Test func claudeWide() { snap(InsightsPreviewData.model(tab: .claude), size: CGSize(width: 480, height: 1_040), name: "claude-480") }
    @Test func codexFull() { snap(InsightsPreviewData.model(tab: .codex), size: CGSize(width: 310, height: 1_000), name: "codex-310") }
    @Test func machineFull() { snap(InsightsPreviewData.model(tab: .machine), size: CGSize(width: 310, height: 1_180), name: "machine-310") }
    @Test func proxyFull() { snap(InsightsPreviewData.model(tab: .proxy), size: CGSize(width: 310, height: 620), name: "proxy-310") }

    @Test func compactTabs() {
        for tab in InsightsTab.allCases {
            snap(InsightsPreviewData.model(tab: tab), size: CGSize(width: 220, height: 420), name: "\(tab.rawValue)-compact-220")
        }
    }

    @Test func forcedCompactAtNormalWidth() {
        snap(InsightsPreviewData.model(tab: .machine), compact: true, size: CGSize(width: 310, height: 420), name: "machine-forced-compact-310")
    }

    @Test func emptyStates() {
        snap(InsightsModel(preview: .empty, tab: .claude, now: InsightsPreviewData.now), size: CGSize(width: 310, height: 240), name: "claude-empty-310")
        snap(InsightsModel(preview: .empty, tab: .machine, now: InsightsPreviewData.now), size: CGSize(width: 310, height: 240), name: "machine-empty-310")
        snap(InsightsModel(preview: .empty, tab: .proxy, now: InsightsPreviewData.now), size: CGSize(width: 310, height: 240), name: "proxy-empty-310")
    }

    @Test func dockerUnavailableAndHighLoadStates() {
        var s = InsightsPreviewData.snapshot()
        s.dockerAvailable = false
        s.computers = []
        s.machine?.cpu = CPUSample(total: 0.93, user: 0.8, system: 0.13, perCore: Array(repeating: 0.93, count: 14), load1: 12, load5: 9, load15: 6)
        s.machine?.memory?.pressure = .critical
        snap(InsightsPreviewData.model(tab: .machine, snapshot: s), size: CGSize(width: 310, height: 1_180), name: "machine-stressed-310")
    }

    @Test func contentFitsTheColumnAtEveryWidth() {
        DSFonts.registerIfNeeded()
        for width in [220.0, 260, 310, 480] {
            for tab in InsightsTab.allCases {
                let host = NSHostingView(rootView: InsightsModuleView(model: InsightsPreviewData.model(tab: tab))
                    .frame(width: width, height: 900))
                host.frame = NSRect(x: 0, y: 0, width: width, height: 900)
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.width <= width + 0.5, "\(tab) overflows at \(width)")
            }
        }
    }
}

@MainActor
@Suite struct InsightsModelTests {
    @Test func historyKeepsOnlyTheLastSamples() {
        var h = InsightsHistory()
        let machine = InsightsPreviewData.machine()
        for _ in 0..<(InsightsHistory.capacity + 25) { h.append(machine) }
        #expect(h.cpu.count == InsightsHistory.capacity)
        #expect(h.down.count == InsightsHistory.capacity)
    }

    @Test func applyAppendsHistoryOnlyForNewMachineSamples() {
        let model = InsightsModel(preview: .empty, now: InsightsPreviewData.now)
        var s = InsightsPreviewData.snapshot()
        model.apply(s)
        model.apply(s)  // mesma amostra: não duplica
        #expect(model.history.cpu.count == 1)
        let next = s.machine!.at.addingTimeInterval(1.5)
        s.machine?.at = next
        model.apply(s)
        #expect(model.history.cpu.count == 2)
    }

    @Test func serviceBackedModelStreamsMachineSamplesWhileVisible() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agentbox-insights-ui-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = InsightsConfig(
            claudeProjects: dir.appendingPathComponent("p"), codexSessions: dir.appendingPathComponent("c"),
            ledgerURL: dir.appendingPathComponent("l.json"), claudeRateLimitsURL: dir.appendingPathComponent("r.json"),
            machineInterval: 0.05, usageRefreshInterval: 3_600)
        let service = InsightsService(config: config, runner: SystemInsightsCommandRunner(timeout: .milliseconds(1)))
        let model = InsightsModel(service: service, tab: .machine)
        model.viewDidAppear()
        for _ in 0..<60 where model.snapshot.machine == nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(model.snapshot.machine != nil)
        model.viewDidDisappear()
        try await Task.sleep(for: .milliseconds(300))
        let stamp = await service.current.machine?.at
        try await Task.sleep(for: .milliseconds(300))
        #expect(await service.current.machine?.at == stamp)
        await service.stop()
    }
}

@Suite struct InsightsFormatTests {
    @Test func tokens() {
        #expect(InsightsFormat.tokens(842) == "842")
        #expect(InsightsFormat.tokens(1_000) == "1K")
        #expect(InsightsFormat.tokens(12_340) == "12.3K")
        #expect(InsightsFormat.tokens(27_222_968) == "27.2M")
        #expect(InsightsFormat.tokens(1_300_000_000) == "1.3B")
    }

    @Test func costPercentDuration() {
        #expect(InsightsFormat.cost(0.4) == "$0.40")
        #expect(InsightsFormat.cost(565.2) == "$565")
        #expect(InsightsFormat.cost(1_969) == "$2K")
        #expect(InsightsFormat.percent(0.314) == "31%")
        #expect(InsightsFormat.duration(45) == "45s")
        #expect(InsightsFormat.duration(2 * 3_600 + 41 * 60) == "2h 41m")
        #expect(InsightsFormat.duration(3 * 86_400 + 4 * 3_600) == "3d 4h")
    }

    @Test func bytesAndRates() {
        #expect(InsightsFormat.bytes(512 * 1_048_576) == "512 MB")
        #expect(InsightsFormat.bytes(3_650_722_201) == "3.4 GB")
        #expect(InsightsFormat.rate(2_350_000) == "2.2 MB/s")
        #expect(InsightsFormat.rate(512) == "512 B/s")
    }

    @Test func namesAndHeat() {
        #expect(InsightsFormat.modelName("claude-opus-5-5") == "opus-5-5")
        #expect(InsightsFormat.modelName("gpt-6.1-sol") == "gpt-6.1-sol")
        #expect(InsightsFormat.plan("team") == "Team")
        #expect(InsightsFormat.plan(nil) == nil)
        #expect(InsightsFormat.heatLevel(0, max: 10) == 0)
        #expect(InsightsFormat.heatLevel(0.01, max: 10) == 1)
        #expect(InsightsFormat.heatLevel(10, max: 10) == 4)
        #expect(InsightsFormat.ago(Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 7_300)) == "2h")
    }
}
