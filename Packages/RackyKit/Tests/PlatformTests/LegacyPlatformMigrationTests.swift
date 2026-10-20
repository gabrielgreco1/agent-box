import Foundation
import RackyProtocol
import Synchronization
import Testing

@testable import RackyPlatform

/// Controle falso do launchd: nada de `launchctl` de verdade (a máquina do dono nunca é tocada).
final class FakeLegacyLaunchd: LegacyLaunchdControlling, @unchecked Sendable {  // SAFETY: estado só sob `lock`.
    struct State {
        var job: LaunchdJobState
        var pid: Int32?
        var children: Int
        var bootoutResult = true
        var calls: [String] = []
    }
    private let lock: Mutex<State>

    init(job: LaunchdJobState, pid: Int32? = nil, children: Int = 0, bootoutResult: Bool = true) {
        lock = Mutex(State(job: job, pid: pid, children: children, bootoutResult: bootoutResult))
    }

    var calls: [String] { lock.withLock { $0.calls } }

    func jobState(label: String) async -> LaunchdJobState { lock.withLock { $0.calls.append("state \(label)"); return $0.job } }
    func jobPID(label: String) async -> Int32? { lock.withLock { $0.pid } }
    func childProcessCount(of pid: Int32) async -> Int { lock.withLock { $0.children } }
    func bootout(label: String) async -> Bool { lock.withLock { $0.calls.append("bootout \(label)"); return $0.bootoutResult } }
}

private final class Counter: @unchecked Sendable {  // SAFETY: só sob `lock`.
    private let lock = Mutex(0)
    var value: Int { lock.withLock { $0 } }
    func increment() { lock.withLock { $0 += 1 } }
}

@Suite struct LegacyDaemonRetirementTests {
    private func retirement(_ launchd: FakeLegacyLaunchd, unregister: Counter = Counter()) -> LegacyDaemonRetirement {
        LegacyDaemonRetirement(launchd: launchd, unregisterService: { unregister.increment() })
    }

    @Test func nothingToDoWhenTheOldJobIsUnknownToLaunchd() async {
        let launchd = FakeLegacyLaunchd(job: .notLoaded)
        #expect(await retirement(launchd).retireIfDrained() == .notPresent)
        #expect(!launchd.calls.contains { $0.hasPrefix("bootout") })
    }

    @Test func neverBootsOutADaemonThatStillHasTerminals() async {
        let unregistered = Counter()
        let launchd = FakeLegacyLaunchd(job: .running, pid: 4242, children: 3)
        #expect(await retirement(launchd, unregister: unregistered).retireIfDrained() == .keptRunning(liveTerminals: 3))
        #expect(!launchd.calls.contains { $0.hasPrefix("bootout") })
        #expect(unregistered.value == 0, "o registro também fica: o daemon antigo drena sozinho")
    }

    @Test func aRunningDaemonWithoutAPIDIsTreatedAsBusy() async {
        let launchd = FakeLegacyLaunchd(job: .running, pid: nil)
        #expect(await retirement(launchd).retireIfDrained() == .keptRunning(liveTerminals: 1))
        #expect(!launchd.calls.contains { $0.hasPrefix("bootout") })
    }

    @Test func retiresARunningDaemonOnceItsTerminalsAreGone() async {
        let unregistered = Counter()
        let launchd = FakeLegacyLaunchd(job: .running, pid: 4242, children: 0)
        #expect(await retirement(launchd, unregister: unregistered).retireIfDrained() == .retired)
        #expect(launchd.calls.contains("bootout \(LegacyNames.launchAgentLabel)"))
        #expect(unregistered.value == 1)
    }

    @Test func retiresAnIdleOrFailedLoadedJob() async {
        for state in [LaunchdJobState.idle, .failed] {
            let launchd = FakeLegacyLaunchd(job: state)
            #expect(await retirement(launchd).retireIfDrained() == .retired)
            #expect(launchd.calls.contains("bootout \(LegacyNames.launchAgentLabel)"))
        }
    }

    @Test func reportsAFailedBootout() async {
        let launchd = FakeLegacyLaunchd(job: .idle, bootoutResult: false)
        #expect(await retirement(launchd).retireIfDrained() == .failed("launchctl bootout failed"))
    }

    @Test func readsThePIDOfTheJobItselfNotOfNestedEntries() {
        let output = "gui/501/x = {\n\tstate = running\n\tpid = 4242\n\tsockets = {\n\t\tpid = 7\n\t}\n}\n"
        #expect(SystemLegacyLaunchd.pid(printOutput: output) == 4242)
        #expect(SystemLegacyLaunchd.pid(printOutput: "gui/501/x = {\n\tstate = waiting\n}\n") == nil)
    }
}

@Suite struct MigratingMasterKeyBackendTests {
    private let key = Data(repeating: 7, count: 32)

    @Test func copiesTheOldKeyToTheNewServiceAndKeepsTheOldOne() async throws {
        let primary = InMemoryMasterKeyBackend()
        let legacy = InMemoryMasterKeyBackend(key: key)
        let backend = MigratingMasterKeyBackend(primary: primary, legacy: legacy)
        #expect(try await backend.loadMasterKey() == key)
        #expect(try await primary.loadMasterKey() == key, "gravou no item novo")
        #expect(try await legacy.loadMasterKey() == key, "o item antigo fica para desfazer a atualização")
        #expect(await primary.storeCount == 1)
        #expect(try await backend.loadMasterKey() == key)
        #expect(await primary.storeCount == 1, "a segunda leitura já vem do item novo")
    }

    @Test func theNewItemWinsOverTheOldOne() async throws {
        let newer = Data(repeating: 9, count: 32)
        let backend = MigratingMasterKeyBackend(primary: InMemoryMasterKeyBackend(key: newer), legacy: InMemoryMasterKeyBackend(key: key))
        #expect(try await backend.loadMasterKey() == newer)
    }

    @Test func noKeyAnywhereMeansNoKey() async throws {
        let backend = MigratingMasterKeyBackend(primary: InMemoryMasterKeyBackend(), legacy: InMemoryMasterKeyBackend())
        #expect(try await backend.loadMasterKey() == nil)
    }

    @Test func deletingRemovesBothSoTheOldKeyCannotComeBack() async throws {
        let primary = InMemoryMasterKeyBackend(key: key)
        let legacy = InMemoryMasterKeyBackend(key: key)
        let backend = MigratingMasterKeyBackend(primary: primary, legacy: legacy)
        try await backend.deleteMasterKey()
        #expect(try await backend.loadMasterKey() == nil)
    }
}
