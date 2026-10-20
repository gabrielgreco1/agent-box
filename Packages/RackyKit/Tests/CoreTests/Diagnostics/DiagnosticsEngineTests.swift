import RackyDocker
import Foundation
import Synchronization
import Testing

@testable import RackyCore

/// Motor da checklist (R1.1, AC-102): paralelo, timeout por item, cache e sondas 100% falsas.
@Suite struct DiagnosticsEngineTests {
    private final class Collected: Sendable {
        private let state = Mutex<[DiagnosticKey: [DiagnosticItem?]]>([:])
        func add(_ key: DiagnosticKey, _ item: DiagnosticItem?) { state.withLock { $0[key, default: []].append(item) } }
        func last(_ key: DiagnosticKey) -> DiagnosticItem? { state.withLock { $0[key]?.last ?? nil } }
        func history(_ key: DiagnosticKey) -> [DiagnosticItem?] { state.withLock { $0[key] ?? [] } }
    }

    private let runtime = DockerRuntime(kind: .desktop, socketPath: "/tmp/fake.sock", source: .knownSocket)

    private func probes(
        gh: @escaping @Sendable () async -> GitHubProbeResult = { GitHubProbeResult(installed: true, version: "2.60.1", auth: GitHubAuthStatus(state: .connected, host: "github.com", user: "me", scopes: ["repo"])) },
        docker: DockerProbeResult? = nil, image: ImageProbeResult? = .ready,
        conflicts: ConflictScan = ConflictScan()
    ) -> DiagnosticsProbes {
        let dockerResult = docker ?? .running(DockerRunning(runtime: runtime, version: "27", memoryGB: 16, headlessCapacity: 11))
        return DiagnosticsProbes(gh: gh, docker: { dockerResult }, image: { _ in image }, conflicts: { conflicts })
    }

    private func run(_ engine: DiagnosticsEngine, keys: Set<DiagnosticKey> = Set(DiagnosticKey.allCases), force: Bool = false, into collected: Collected) async {
        await engine.run(keys, force: force) { collected.add($0, $1) }
    }

    @Test func everyItemLeavesCheckingWithItsOwnResult() async {
        let engine = DiagnosticsEngine(probes: probes(conflicts: ConflictScan(findings: [ConflictFinding(kind: .notify, provider: .codex, path: "~/.codex/config.toml", message: "x")])))
        let collected = Collected()
        await run(engine, into: collected)
        #expect(collected.history(.gh).first??.state == .checking, "Checking… antes do resultado")
        #expect(collected.last(.gh)?.state == .ok)
        #expect(collected.last(.docker)?.state == .ok)
        #expect(collected.last(.image)?.detail == "Ready")
        #expect(collected.last(.conflicts)?.state == .neutral)
    }

    @Test func aStuckItemTimesOutWithTryAgainAndDoesNotDelayTheOthers() async {
        let engine = DiagnosticsEngine(
            probes: probes(gh: { try? await Task.sleep(for: .seconds(30)); return GitHubProbeResult(installed: false) }),
            configuration: .init(timeout: .milliseconds(150), cacheTTL: .seconds(60)))
        let collected = Collected()
        let start = ContinuousClock.now
        await run(engine, into: collected)
        #expect(ContinuousClock.now - start < .seconds(10), "bem abaixo dos 30 s do item preso, com folga para a suíte carregada")
        #expect(collected.last(.gh)?.fix == .retry && collected.last(.gh)?.state == .problem)
        #expect(collected.last(.docker)?.state == .ok, "o resto chegou")
    }

    @Test func resultsAreCachedUntilForced() async {
        let engine = DiagnosticsEngine(probes: probes())
        let first = Collected()
        await run(engine, into: first)
        let second = Collected()
        await run(engine, into: second)
        #expect(second.last(.gh) == first.last(.gh) && second.last(.docker) == first.last(.docker))
        let cached = await engine.probeRuns
        #expect(cached[.gh] == 1 && cached[.docker] == 1, "segunda rodada saiu do cache")
        await run(engine, force: true, into: Collected())
        let forced = await engine.probeRuns
        #expect(forced[.gh] == 2 && forced[.docker] == 2)
    }

    @Test func aTimedOutItemIsNotCached() async {
        let calls = Mutex(0)
        let engine = DiagnosticsEngine(
            probes: probes(gh: {
                let n = calls.withLock { $0 += 1; return $0 }
                if n == 1 { try? await Task.sleep(for: .seconds(30)) }
                return GitHubProbeResult(installed: false)
            }),
            configuration: .init(timeout: .milliseconds(100), cacheTTL: .seconds(60)))
        await run(engine, keys: [.gh], into: Collected())
        let retry = Collected()
        await run(engine, keys: [.gh], into: retry)
        #expect(retry.last(.gh)?.detail.hasPrefix("Not installed") == true, "Try Again refaz a sonda")
    }

    @Test func imageIsOnlyProbedWhenDockerIsRunning() async {
        let imageCalls = Mutex(0)
        let stopped = DiagnosticsProbes(
            gh: { GitHubProbeResult(installed: false) }, docker: { .installedNotRunning(kind: .desktop) },
            image: { _ in imageCalls.withLock { $0 += 1 }; return .ready }, conflicts: { ConflictScan() })
        let collected = Collected()
        await run(DiagnosticsEngine(probes: stopped), into: collected)
        #expect(imageCalls.withLock { $0 } == 0)
        #expect(collected.last(.docker)?.fix == .startDocker)
        #expect(collected.last(.image)?.state == .neutral)
    }

    @Test func retryingOnlyTheRequestedItems() async {
        let engine = DiagnosticsEngine(probes: probes())
        await run(engine, into: Collected())
        await run(engine, keys: [.gh], force: true, into: Collected())
        let runs = await engine.probeRuns
        #expect(runs[.gh] == 2 && runs[.docker] == 1 && runs[.conflicts] == 1)
    }
}
