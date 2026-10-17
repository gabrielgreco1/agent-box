import AgentBoxCore
import AppKit
import Foundation
import UserNotifications

/// Notificação do macOS para um pedido de ajuda de computador (03 §9.2, 07 CS-430, CS-433): uma por `request_id`, sem conteúdo de página.
@MainActor
public protocol HelpNotifying: AnyObject {
    func notify(item: InboxItem, content: HelpNotificationContent)
}

@MainActor
public final class NoopHelpNotifier: HelpNotifying {
    public init() {}
    public func notify(item: InboxItem, content: HelpNotificationContent) {}
}

/// Guarda o que foi entregue (testes de unidade e evidência).
@MainActor
public final class RecordingHelpNotifier: HelpNotifying {
    public private(set) var delivered: [(item: InboxItem, content: HelpNotificationContent)] = []
    public init() {}
    public func notify(item: InboxItem, content: HelpNotificationContent) { delivered.append((item, content)) }
}

/// `UNUserNotificationCenter` com delegate: o clique abre o viewer (padrão) ou, na ação `Take Over`, já assume o controle.
@MainActor
public final class SystemHelpNotifier: NSObject, HelpNotifying, UNUserNotificationCenterDelegate {
    nonisolated public static let category = "agentbox.computer.help"
    nonisolated public static let takeOverAction = "agentbox.computer.takeOver"
    private let open: @MainActor (String, Bool) -> Void
    private var authorized: Bool?

    /// `open(computerName, takeOver)` é chamado no clique. Precisa de um app com bundle (não roda em `swift test`).
    public init?(open: @escaping @MainActor (String, Bool) -> Void) {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        self.open = open
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.category,
                actions: [UNNotificationAction(identifier: Self.takeOverAction, title: "Take Over", options: [.foreground])],
                intentIdentifiers: [])
        ])
    }

    public func notify(item: InboxItem, content: HelpNotificationContent) {
        let center = UNUserNotificationCenter.current()
        let payload = UNMutableNotificationContent()
        payload.title = content.title
        payload.body = content.body
        payload.sound = .default
        payload.threadIdentifier = content.threadID
        payload.categoryIdentifier = Self.category
        payload.userInfo = ["computer": item.computer, "request": item.id]
        let request = UNNotificationRequest(identifier: "help-\(item.id)", content: payload, trigger: nil)  // id = request_id: uma vez
        Task {
            if self.authorized == nil { self.authorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false }
            guard self.authorized == true else { return }
            try? await center.add(request)
        }
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let computer = info["computer"] as? String
        let takeOver = response.actionIdentifier == Self.takeOverAction
        Task { @MainActor in
            if let computer { self.open(computer, takeOver) }
            completionHandler()
        }
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Janela própria do viewer (03 §11, `WindowGroup(for: ComputerID.self)` no desenho; aqui uma `NSWindow`): mesmo layout sem a
/// sidebar, título `<computer> — Agent Box`, mínimo 640×420.
@MainActor
final class ViewerPopOut: NSObject, NSWindowDelegate {
    let controller: ComputerViewerController
    private let window: NSWindow
    private let onClose: () -> Void

    init(controller: ComputerViewerController, computers: ComputersController, onClose: @escaping () -> Void) {
        self.controller = controller
        self.onClose = onClose
        let content = ChromeHostingView(content: ComputerViewerView(controller: controller, computers: computers))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = "\(controller.name) — Agent Box"
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = content
        window.delegate = self
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { onClose() }
}
