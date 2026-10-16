import Foundation
import UserNotifications
import AgentBoxCore

@MainActor final class HumanRequestCenter: ObservableObject {
    static let shared = HumanRequestCenter()

    @Published private(set) var snapshot = HumanRequestSnapshot()
    @Published private(set) var errorText: String?
    @Published private(set) var notificationsEnabled = false

    private let repository = HumanRequestRepository()
    private let defaultsKey = "AgentBox.humanRequestNotificationsEnabled"

    private init() {
        do {
            snapshot = try repository.load()
        } catch {
            errorText = "Pedidos salvos indisponíveis: \(error.localizedDescription). O arquivo foi preservado."
        }
        notificationsEnabled = UserDefaults.standard.bool(forKey: defaultsKey)
    }

    var pendingCount: Int { snapshot.pendingCount() }

    func ingest(_ request: HumanRequest) throws {
        guard errorText == nil else { throw HumanRequestError.invalidRequest }
        var next = snapshot
        let inserted = try next.record(request)
        guard inserted else { return }
        try repository.save(next)
        snapshot = next
        if notificationsEnabled { notifyOnce(request) }
    }

    func acknowledge(_ id: UUID) throws {
        var next = snapshot
        try next.acknowledge(id)
        try repository.save(next)
        snapshot = next
    }

    func resolve(_ id: UUID) throws {
        var next = snapshot
        try next.resolve(id)
        try repository.save(next)
        snapshot = next
    }

    /// Call only from an explicit user toggle in Settings. Initializing this center never prompts.
    func enableNotifications() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            notificationsEnabled = granted
            UserDefaults.standard.set(granted, forKey: defaultsKey)
            return granted
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    func disableNotifications() {
        notificationsEnabled = false
        UserDefaults.standard.set(false, forKey: defaultsKey)
    }

    private func notifyOnce(_ request: HumanRequest) {
        do {
            var next = snapshot
            guard try next.claimNotification(request.id) else { return }
            // Persist the claim before scheduling; reconnect/relaunch cannot sound twice.
            try repository.save(next)
            snapshot = next
            let content = UNMutableNotificationContent()
            content.title = "Agent Box · precisa de você"
            content.body = request.summary
            content.sound = .default
            content.userInfo = ["request_id": request.id.uuidString,
                                "session_id": request.target.sessionID.uuidString,
                                "terminal_id": request.target.terminalID.uuidString,
                                "computer_id": request.target.computerID.uuidString]
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: request.id.uuidString, content: content, trigger: nil)
            ) { [weak self] error in
                if let error { Task { @MainActor in self?.errorText = error.localizedDescription } }
            }
        } catch { errorText = error.localizedDescription }
    }
}
