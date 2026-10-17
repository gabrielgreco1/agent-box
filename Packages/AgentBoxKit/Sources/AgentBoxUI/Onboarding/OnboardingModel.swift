import AgentBoxCore
import AgentBoxPlatform
import AgentBoxProtocol
import AgentBoxStore
import Foundation
import Observation

/// Registro gravado quando o onboarding termina (Done ou Skip). Sem ele, a primeira abertura mostra o overlay.
public nonisolated struct OnboardingRecord: Codable, Equatable, Sendable {
    public nonisolated enum Outcome: String, Codable, Sendable { case done, skipped }
    public var outcome: Outcome
    public var at: Date
}

/// Onboarding mínimo da Fatia 1 (03 §15): checklist de diagnóstico não bloqueante com os CLIs de agente detectados.
/// A detecção é a do Settings (`SettingsModel.agents`): instalado, versão e login, sem nunca rodar `login`.
@MainActor @Observable
public final class OnboardingModel {
    public static let storeKey = "onboarding.state"

    public private(set) var isVisible = false
    /// `Skip setup?` inline (03 §15): `Keep Setting Up` / `Skip`.
    public private(set) var confirmingSkip = false
    public private(set) var record: OnboardingRecord?

    let settings: SettingsModel
    @ObservationIgnored var clock: () -> Date = { Date() }
    @ObservationIgnored private var store: AgentBoxStore?
    @ObservationIgnored private var checked = false
    @ObservationIgnored private let log = LogFacade(.app, category: "onboarding")

    /// Abre o terminal inline com o comando oficial de login (`claude /login`, `codex login`). Sem painel de terminal
    /// disponível (T1-14 ainda não existe nesta base) fica nulo e `account.logIn` aparece desabilitado com o motivo.
    @ObservationIgnored public var loginLauncher: (@MainActor (TerminalProvider, [String]) async -> Void)?
    @ObservationIgnored var present: @MainActor () -> Void = {}
    @ObservationIgnored var dismiss: @MainActor () -> Void = {}

    public init(settings: SettingsModel) { self.settings = settings }

    public static let loginUnavailableReason = "Terminal panes aren't available yet."

    // MARK: Ciclo de vida

    /// Liga ao Store e abre o onboarding se for a primeira abertura (sem registro gravado).
    public func attach(store: AgentBoxStore, forceVisible: Bool = false) async {
        self.store = store
        record = try? await store.setting(Self.storeKey, as: OnboardingRecord.self)
        guard !checked else { return }
        checked = true
        if record == nil || forceVisible { show() }
    }

    /// `app.setup`: abre o onboarding quando o usuário pede (menu do app, Diagnostics).
    public func show() {
        guard !isVisible else { return }
        isVisible = true
        confirmingSkip = false
        present()
        Task { await settings.refreshAgents(force: false) }
    }

    /// Fecha o overlay sem registrar nada (o usuário foi para o Settings; o onboarding volta na próxima abertura).
    public func hide() {
        guard isVisible else { return }
        isVisible = false
        confirmingSkip = false
        dismiss()
    }

    func finish(_ outcome: OnboardingRecord.Outcome) async {
        let value = OnboardingRecord(outcome: outcome, at: clock())
        record = value
        if let store {
            do { try await store.setSetting(Self.storeKey, value) } catch { log.error("could not save onboarding state: \(error)") }
        }
        hide()
    }

    // MARK: Itens da checklist

    /// Só o que a Fatia 1 mostra: Claude Code, Codex e OpenCode (opcional). gh, Docker, imagem e notificações vêm depois.
    public var items: [AgentInfo] { settings.agents }

    public func isOptional(_ provider: TerminalProvider) -> Bool { provider == .opencode }

    // MARK: Ações

    func registerActions(in registry: ActionRegistry) throws {
        try registry.register(.appSetup) { [unowned self] _ in
            show()
            return "opened"
        }
        try registry.register(.onboardingSkip) { [unowned self] _ in
            confirmingSkip = true
            return "confirming"
        }
        try registry.register(.onboardingKeepSettingUp) { [unowned self] _ in
            confirmingSkip = false
            return "kept"
        }
        try registry.register(.onboardingConfirmSkip) { [unowned self] _ in
            await finish(.skipped)
            return "skipped"
        }
        try registry.register(.onboardingDone) { [unowned self] _ in
            await finish(.done)
            return "done"
        }
        try registry.register(
            .accountLogIn,
            enablement: { [unowned self] in loginLauncher == nil ? .disabled(reason: Self.loginUnavailableReason) : .enabled }
        ) { [unowned self] arg in
            guard let raw = arg.value, let provider = TerminalProvider(rawValue: raw), let info = settings.agent(provider) else {
                throw ActionError.failed(.accountLogIn, message: "unknown agent")
            }
            guard info.isInstalled else { throw ActionError.failed(.accountLogIn, message: "\(info.displayName) isn't installed.") }
            guard let command = info.loginCommand else {
                throw ActionError.failed(.accountLogIn, message: "\(info.displayName) has no login command.")
            }
            guard let launcher = loginLauncher else { throw ActionError.failed(.accountLogIn, message: Self.loginUnavailableReason) }
            await launcher(provider, command)
            // Ao fim do login o item vira "Logged in" sem reiniciar o onboarding (AC-104).
            await settings.refreshAgents(force: true, only: provider)
            return settings.agent(provider)?.statusText
        }
    }
}
