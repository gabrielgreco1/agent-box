import AgentBoxCore
import Foundation

/// Retain one instance per displayed computer; the control token stays inside the bridge actor.
@MainActor
final class BrokerDesktopActions {
    private let bridge: ComputerControlBridge<BrowserRuntimeClient>
    private let computerID: UUID
    private var ticket: ComputerControlTicket?

    init(endpoint: BrowserRuntimeEndpoint, broker: ControlBroker, session: URLSession = .shared) async {
        computerID = endpoint.computerID
        bridge = await DesktopBrokerService.bridge(endpoint: endpoint, broker: broker, session: session)
    }

    func actions() -> RemoteDesktopControlActions {
        RemoteDesktopControlActions(
            assume: { [weak self] in
                guard let self else { throw ComputerControlBridgeError.noTicket }
                let ticket = try await self.bridge.assumeHuman()
                self.ticket = ticket
                return ticket.grant
            },
            release: { [weak self] expectedGrant in
                guard let self, let ticket = self.ticket, ticket.grant == expectedGrant else {
                    throw ComputerControlBridgeError.noTicket
                }
                try await self.bridge.releaseHuman(ticket)
                if self.ticket == ticket { self.ticket = nil }
                AgentComputerAccess.shared.humanReleased(computerID: self.computerID)
            },
            streamDisconnected: { [weak self] expectedGrant in
                guard let self, let ticket = self.ticket, ticket.grant == expectedGrant else { return }
                self.ticket = nil
                // Closing an observer must never revoke the agent or a newer human lease.
                for _ in 0..<600 {
                    do { try await self.bridge.releaseHuman(ticket); return }
                    catch ControlBrokerError.transitionInProgress {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                    catch { return }
                }
            },
            pointer: { [weak self] grant, input in
                guard let self, let ticket = self.ticket, ticket.grant == grant else {
                    throw ComputerControlBridgeError.noTicket
                }
                switch input {
                case .move(let x, let y):
                    let point = try Self.pixels(x: x, y: y)
                    try await self.bridge.input(.move(x: point.x, y: point.y), ticket: ticket)
                case .button(let x, let y, let button, let pressed):
                    let point = try Self.pixels(x: x, y: y)
                    guard (0...2).contains(button) else { throw ComputerControlBridgeError.writeDenied }
                    let runtimeButton = button == 2 ? 3 : (button == 1 ? 2 : 1)
                    try await self.bridge.input(.move(x: point.x, y: point.y), ticket: ticket)
                    try await self.bridge.input(.button(button: runtimeButton, pressed: pressed), ticket: ticket)
                case .scroll(let direction, let clicks):
                    guard ["up", "down", "left", "right"].contains(direction), (1...20).contains(clicks) else {
                        throw ComputerControlBridgeError.writeDenied
                    }
                    try await self.bridge.input(.scroll(direction: direction, clicks: clicks), ticket: ticket)
                }
            },
            key: { [weak self] grant, value in
                guard let self, let ticket = self.ticket, ticket.grant == grant else {
                    throw ComputerControlBridgeError.noTicket
                }
                let action: BrowserDesktopInput
                switch value {
                case "Return", "Tab", "Escape", "BackSpace", "Delete", "Up", "Down", "Left", "Right",
                     "Home", "End", "Prior", "Next": action = .key(value)
                default:
                    guard !value.isEmpty, value.utf8.count <= 4096 else {
                        throw ComputerControlBridgeError.writeDenied
                    }
                    action = value.hasPrefix("ctrl+") || value.hasPrefix("alt+") || value.hasPrefix("shift+")
                        ? .key(value) : .text(value)
                }
                try await self.bridge.input(action, ticket: ticket)
            }
        )
    }

    func changeMode(_ mode: BrowserRuntimeMode) async throws -> BrowserRuntimeHealth {
        guard let ticket else { throw ComputerControlBridgeError.noTicket }
        let health = try await bridge.changeMode(mode, ticket: ticket)
        self.ticket = await bridge.ticket()
        return health
    }

    func currentGeneration() async -> UInt64 { await bridge.currentGeneration() }

    private static func pixels(x: Double, y: Double) throws -> (x: Int, y: Int) {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
            throw ComputerControlBridgeError.writeDenied
        }
        return (min(1279, Int(x * 1280)), min(799, Int(y * 800)))
    }
}
