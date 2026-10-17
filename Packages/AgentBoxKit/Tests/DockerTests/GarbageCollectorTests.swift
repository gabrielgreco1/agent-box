import Foundation
import Testing

@testable import AgentBoxDocker

private func resource(_ kind: ManagedResourceKind, _ name: String, computer: String?, ephemeral: Bool = true) -> ManagedResource {
    var labels = [AgentBoxLabel.owner: "install-1", AgentBoxLabel.ephemeral: ephemeral ? "true" : "false"]
    if let computer { labels[AgentBoxLabel.computer] = computer }
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
        let inventory = try await gc.inventory(labels: ["agentbox.owner=install-1", "agentbox.test=1"])
        #expect(inventory.map(\.kind) == [.container, .network, .volume])
        for request in await daemon.log.items {
            #expect(request.query.contains("filters=%7B%22label%22%3A%5B%22agentbox.owner%3Dinstall-1%22%2C%22agentbox.test%3D1%22%5D%7D"))
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
                let body = #"{"Volumes":[{"Name":"eph","Labels":{"agentbox.ephemeral":"true","agentbox.computer":"c1"}},{"Name":"profile-x","Labels":{"agentbox.ephemeral":"false","agentbox.computer":"c1"}}]}"#
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
        let monitor = EventMonitor(client: daemon.client, labels: ["agentbox.owner=x"], initialDelay: .milliseconds(20), maxDelay: .milliseconds(40))
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
}
