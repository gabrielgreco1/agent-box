import Foundation
import RackyCore

/// Only metadata is persisted here; the reviewed context remains in its protected file.
struct AgentLaunchBindingStore {
    var url = AppPaths.applicationSupport.appendingPathComponent("agent-launch-bindings.json")

    func load() throws -> [UUID: AgentLaunchBinding] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let records = try JSONDecoder().decode([Record].self, from: Data(contentsOf: url))
        guard Set(records.map(\.terminalID)).count == records.count,
              records.allSatisfy({ $0.terminalID == $0.binding.planID }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Dictionary(uniqueKeysWithValues: records.map { ($0.terminalID, $0.binding) })
    }

    func save(_ bindings: [UUID: AgentLaunchBinding]) throws {
        let records = bindings.map { Record(terminalID: $0.key, binding: $0.value) }
            .sorted { $0.terminalID.uuidString < $1.terminalID.uuidString }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                              ofItemAtPath: url.deletingLastPathComponent().path)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private struct Record: Codable {
        let terminalID: UUID
        let binding: AgentLaunchBinding
    }
}
