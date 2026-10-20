import Foundation
import Testing

@testable import RackyDocker

private func resource(_ kind: ManagedResourceKind, _ name: String, computer: String?, ephemeral: Bool = true) -> ManagedResource {
    var labels = [RackyLabel.owner: "install-1", RackyLabel.ephemeral: ephemeral ? "true" : "false"]
    if let computer { labels[RackyLabel.computer] = computer }
    return ManagedResource(kind: kind, id: name, name: name, labels: labels)
}

@Suite struct GarbageCollectorTests {
    @Test func planKeepsKnownComputersAndSplitsOrphansByEphemeralAndFinished() {
        let gc = GarbageCollector(client: DockerClient(socketPath: "/nonexistent"))
        let inventory = [
            resource(.container, "known-runtime", computer: "known"),
            resource(.network, "known-net", computer: "known"),
            resource(.container, "finished-work", computer: "done"),
            resource(.volume, "finished-profile", computer: "done", ephemeral: false),
            resource(.container, "mystery", computer: "unknown"),
            resource(.volume, "nolabel-computer", computer: nil),
        ]
        let plan = gc.plan(inventory: inventory, knownComputerIDs: ["known"], finishedComputerIDs: ["done"])
        #expect(plan.removeWithoutAsking.map(\.name) == ["finished-work"], "efêmero de run terminado some sem perguntar")
        #expect(plan.needsConfirmation.map(\.name) == ["finished-profile", "mystery", "nolabel-computer"])
    }

    @Test func inventoryAsksTheDaemonOnlyForLabelledResources() async throws {
        let daemon = try await FakeDockerDaemon { request, connection in
            switch request.path {
            case "/v1.43/containers/json": await Reply.json(connection, body: (try? Fixtures.data("container-list.json")) ?? Data())
            case "/v1.43/networks": await Reply.json(connection, body: Data("[\((try? Fixtures.text("network-inspect.json")) ?? "")]".utf8))
            case "/v1.43/volumes": await Reply.json(connection, body: Data("{\"Volumes\":[\((try? Fixtures.text("volume-inspect.json")) ?? "")],\"Warnings\":null}".utf8))
            default: await Reply.json(connection, status: 404, body: Data(#"{"message":"?"}"#.utf8))
            }
        }
        defer { daemon.stop() }
        let gc = GarbageCollector(client: daemon.client)
        let inventory = try await gc.inventory(labels: ["racky.owner=install-1", "racky.test=1"])
        #expect(inventory.map(\.kind) == [.container, .network, .volume])
        let current = "filters=%7B%22label%22%3A%5B%22racky.owner%3Dinstall-1%22%2C%22racky.test%3D1%22%5D%7D"
        let previous = "filters=%7B%22label%22%3A%5B%22agentbox.owner%3Dinstall-1%22%2C%22agentbox.test%3D1%22%5D%7D"
        for request in await daemon.log.items {
            #expect(request.query.contains(current) || request.query.contains(previous), "só consultas pelos labels do app, novos ou antigos")
        }
        // Sem label o GC nunca varre o daemon inteiro.
        #expect(try await gc.inventory(labels: []).isEmpty)
    }

    @Test func removalOrderIsContainersNetworksVolumesAndFailuresAreReported() async throws {
        let daemon = try await FakeDockerDaemon { request, connection in
            if request.path.hasSuffix("busy-net") {
                await Reply.json(connection, status: 403, body: Data(#"{"message":"network has active endpoints"}"#.utf8))
            } else {
                await Reply.raw(connection, status: 204, headers: [:], body: Data())
            }
        }
        defer { daemon.stop() }
        let gc = GarbageCollector(client: daemon.client)
        let failures = await gc.remove([
            resource(.volume, "vol-a", computer: "c"), resource(.network, "busy-net", computer: "c"),
            resource(.container, "ctr-a", computer: "c"), resource(.network, "net-b", computer: "c"),
        ])
        let order = await daemon.log.items.map { "\($0.method) \($0.path.split(separator: "/").suffix(2).joined(separator: "/"))" }
        #expect(order == ["DELETE containers/ctr-a", "DELETE networks/busy-net", "DELETE networks/net-b", "DELETE volumes/vol-a"])
        #expect(failures.count == 1 && failures[0].0.name == "busy-net")
    }

    @Test func removeComputerKeepsNamedProfileVolumes() async throws {
        let daemon = try await FakeDockerDaemon { request, connection in
            switch (request.method, request.path) {
            case ("GET", "/v1.43/containers/json"): await Reply.json(connection, body: Data("[]".utf8))
            case ("GET", "/v1.43/networks"): await Reply.json(connection, body: Data("[]".utf8))
            case ("GET", "/v1.43/volumes"):
                let body = #"{"Volumes":[{"Name":"eph","Labels":{"racky.ephemeral":"true","racky.computer":"c1"}},{"Name":"profile-x","Labels":{"racky.ephemeral":"false","racky.computer":"c1"}}]}"#
                await Reply.json(connection, body: Data(body.utf8))
            default: await Reply.raw(connection, status: 204, headers: [:], body: Data())
            }
        }
        defer { daemon.stop() }
        _ = try await GarbageCollector(client: daemon.client).removeComputer(id: "c1")
        let deletes = await daemon.log.items.filter { $0.method == "DELETE" }.map(\.path)
        #expect(deletes == ["/v1.43/volumes/eph"], "o perfil nomeado nunca é removido nesse fluxo (CS-180)")
    }

    @Test func eventMonitorResyncsOnConnectAndReconnectsWithSince() async throws {
        let connections = ConnectionCounter()
        let daemon = try await FakeDockerDaemon { request, connection in
            let n = await connections.next()
            if n == 1 {
                let line = #"{"Type":"container","Action":"start","Actor":{"ID":"abc","Attributes":{"name":"ab-1-runtime"}},"time":100,"timeNano":100000000000}"# + "\n"
                await Reply.chunked(connection, chunks: [Data(line.utf8)])  // encerra o stream: o monitor deve reconectar
            } else {
                #expect(request.query.contains("since=100"))
                await Reply.chunked(connection, chunks: [], delay: nil)
            }
        }
        defer { daemon.stop() }
        let monitor = EventMonitor(client: daemon.client, labels: ["racky.owner=x"], initialDelay: .milliseconds(20), maxDelay: .milliseconds(40))
        var seen: [String] = []
        for await update in monitor.updates() {
            switch update {
            case .resync: seen.append("resync")
            case .event(let event): seen.append("event:\(event.baseAction)")
            case .disconnected: seen.append("down")
            }
            if seen.filter({ $0 == "resync" }).count == 2 { break }
        }
        #expect(seen.prefix(4) == ["resync", "event:start", "down", "resync"])
    }
}

actor ConnectionCounter {
    private var count = 0
    func next() -> Int {
        count += 1
        return count
    }

    // MARK: Labels do nome antigo (rename para Racky)

    @Test func legacyLabelsAreTranslatedFromTheNewOnes() {
        #expect(RackyLabel.legacyKey("racky.owner") == "agentbox.owner")
        #expect(RackyLabel.legacyKey("racky.test_run") == "agentbox.test_run")
        #expect(RackyLabel.legacyKey("other.owner") == nil)
        #expect(RackyLabel.legacyOwner("racky") == "agent-box")
        #expect(RackyLabel.legacyOwner("racky-1a2b3c4d") == "agent-box-1a2b3c4d")
        #expect(RackyLabel.legacyFilter("racky.owner=racky-1a2b3c4d") == "agentbox.owner=agent-box-1a2b3c4d")
        #expect(RackyLabel.legacyFilter("racky.computer=abc") == "agentbox.computer=abc")
        #expect(RackyLabel.legacyFilter("racky.computer") == "agentbox.computer")
        #expect(RackyLabel.legacyFilter("com.docker.compose.project=x") == nil)
    }

    @Test func labelValuesAndOwnershipAcceptTheOldNames() {
        let old = ["agentbox.owner": "agent-box", "agentbox.computer": "c1", "agentbox.ephemeral": "true"]
        #expect(RackyLabel.value(RackyLabel.computer, in: old) == "c1")
        #expect(RackyLabel.isOwned(by: "racky", labels: old))
        #expect(!RackyLabel.isOwned(by: "racky-1a2b3c4d", labels: old), "um app isolado nunca adota os containers do app do dono")
        #expect(RackyLabel.isOwned(by: "racky", labels: [RackyLabel.owner: "racky"]))
        let resource = ManagedResource(kind: .container, id: "x", name: "ab-c1", labels: old)
        #expect(resource.computerID == "c1" && resource.isEphemeral)
    }

    @Test func inventoryAlsoFindsResourcesLabelledWithTheOldNames() async throws {
        let daemon = try await FakeDockerDaemon { request, connection in
            let oldFilter = request.query.contains("agentbox")
            switch request.path {
            case "/v1.43/containers/json":
                let body = oldFilter
                    ? #"[{"Id":"old1","Names":["/ab-1111"],"Image":"agentbox-computer:1","State":"running","Labels":{"agentbox.owner":"agent-box","agentbox.computer":"c-old"}}]"#
                    : #"[{"Id":"new1","Names":["/ab-2222"],"Image":"racky-computer:1","State":"running","Labels":{"racky.owner":"racky","racky.computer":"c-new"}}]"#
                await Reply.json(connection, body: Data(body.utf8))
            case "/v1.43/networks": await Reply.json(connection, body: Data("[]".utf8))
            case "/v1.43/volumes": await Reply.json(connection, body: Data(#"{"Volumes":[],"Warnings":null}"#.utf8))
            default: await Reply.json(connection, status: 404, body: Data(#"{"message":"?"}"#.utf8))
            }
        }
        defer { daemon.stop() }
        let inventory = try await GarbageCollector(client: daemon.client).inventory(labels: ["racky.owner=racky"])
        #expect(inventory.map(\.id).sorted() == ["new1", "old1"])
        #expect(Set(inventory.compactMap(\.computerID)) == ["c-new", "c-old"])
        // Sem equivalente no nome antigo (label de terceiros), só a consulta direta.
        let before = await daemon.log.items.count
        _ = try await GarbageCollector(client: daemon.client).inventory(labels: ["thirdparty=1"])
        #expect(await daemon.log.items.count - before == 3)
    }
}
