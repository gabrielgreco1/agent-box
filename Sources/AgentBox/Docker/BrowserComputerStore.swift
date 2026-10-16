import AgentBoxCore
import Foundation
import SwiftUI

/// App-facing state for browser computers. Endpoints and bearer tokens are memory-only.
@MainActor
final class BrowserComputerStore: ObservableObject {
    @Published private(set) var computers: [BrowserManagedComputer] = []
    @Published private(set) var endpoints: [UUID: BrowserRuntimeEndpoint] = [:]
    @Published private(set) var busyComputerIDs: Set<UUID> = []
    @Published private(set) var errorText: String?

    private let service: BrowserComputerService<DockerProcessRunner, KeychainBrowserComputerTokenStore>

    init(runner: DockerProcessRunner = DockerProcessRunner(),
         policyStore: ComputerPolicyStore = ComputerPolicyStore()) {
        service = BrowserComputerService(runner: runner, tokens: KeychainBrowserComputerTokenStore(),
                                         policyStore: policyStore)
    }

    func computer(for terminalID: UUID) -> BrowserManagedComputer? {
        computers.first(where: { $0.terminalID == terminalID })
    }

    func refresh() async {
        do {
            let service = service
            let found = try await Task.detached(priority: .utility) { try service.list() }.value
            computers = found
            endpoints = endpoints.filter { id, _ in found.contains(where: { $0.id == id && $0.running }) }
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    @discardableResult
    func createAndStart(terminalID: UUID, context: ComputerPolicyContext) async throws -> BrowserManagedComputer {
        busyComputerIDs.insert(terminalID)
        defer { busyComputerIDs.remove(terminalID) }
        do {
            let service = service
            let computer = try await Task.detached(priority: .utility) {
                try service.createAndStart(for: terminalID, context: context)
            }.value
            await refresh()
            try await connectReady(computerID: computer.id)
            return computer
        } catch { errorText = error.localizedDescription; throw error }
    }

    @discardableResult
    func start(computerID: UUID, context: ComputerPolicyContext) async throws -> BrowserManagedComputer {
        busyComputerIDs.insert(computerID)
        defer { busyComputerIDs.remove(computerID) }
        do {
            let service = service
            let computer = try await Task.detached(priority: .utility) {
                try service.start(computerID: computerID, context: context)
            }.value
            await refresh()
            try await connectReady(computerID: computerID)
            return computer
        } catch { errorText = error.localizedDescription; throw error }
    }

    func stop(computerID: UUID) async throws {
        busyComputerIDs.insert(computerID)
        defer { busyComputerIDs.remove(computerID) }
        endpoints.removeValue(forKey: computerID)
        do {
            let service = service
            try await Task.detached(priority: .utility) { try service.stop(computerID: computerID) }.value
            await refresh()
        } catch { errorText = error.localizedDescription; throw error }
    }

    func reconnect(computerID: UUID) async throws -> BrowserRuntimeEndpoint {
        do {
            let service = service
            let endpoint = try await Task.detached(priority: .utility) {
                try await service.reconnectEndpoint(computerID: computerID)
            }.value
            endpoints[computerID] = endpoint
            errorText = nil
            return endpoint
        } catch { endpoints.removeValue(forKey: computerID); errorText = error.localizedDescription; throw error }
    }

    private func connectReady(computerID: UUID) async throws {
        var lastError: Error = BrowserComputerError.notReady
        for attempt in 0..<8 {
            do { _ = try await reconnect(computerID: computerID); return }
            catch { lastError = error }
            if attempt < 7 { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        throw lastError
    }
}
