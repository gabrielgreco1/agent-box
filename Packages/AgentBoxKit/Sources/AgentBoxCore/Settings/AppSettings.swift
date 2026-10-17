import AgentBoxProtocol
import Foundation

/// Configuração do app (03 §14), gravada em `setting` sob `AppSettings.storeKey`. Só as chaves da Fatia 1 existem;
/// chaves novas entram com o `decodeIfPresent` e o padrão da spec, então um banco antigo nunca falha ao abrir.
public struct AppSettings: Codable, Equatable, Sendable {
    public static let storeKey = "app.settings"

    public var general = General()
    public var agents = Agents()
    public var terminal = Terminal()
    public var notifications = Notifications()
    public var computers = Computers()

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        general = try c.decodeIfPresent(General.self, forKey: .general) ?? General()
        agents = try c.decodeIfPresent(Agents.self, forKey: .agents) ?? Agents()
        terminal = try c.decodeIfPresent(Terminal.self, forKey: .terminal) ?? Terminal()
        notifications = try c.decodeIfPresent(Notifications.self, forKey: .notifications) ?? Notifications()
        computers = try c.decodeIfPresent(Computers.self, forKey: .computers) ?? Computers()
    }

    /// Settings › Computers (F12): padrão de "Subagent computers" das novas sessões. Sessões existentes não mudam.
    public struct Computers: Codable, Equatable, Sendable {
        public var defaultSubagentMode = SubagentComputersMode.off

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            defaultSubagentMode = try c.decodeIfPresent(SubagentComputersMode.self, forKey: .defaultSubagentMode) ?? .off
        }
    }

    public enum BranchPrefixMode: String, Codable, Sendable, CaseIterable { case gitUser, custom, none }

    public struct General: Codable, Equatable, Sendable {
        public var keepAgentsRunning = true
        public var askBeforeQuit = true
        public var confirmCloseTerminal = true
        public var confirmDeleteSession = true
        /// Padrão de transição (P15, R3.2).
        public var worktreeFolder = "~/AgentBox/worktrees"
        public var cleanSessionFolder = "~/AgentBox/sessions"
        public var branchPrefix = BranchPrefixMode.gitUser
        public var branchPrefixCustom = ""

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            keepAgentsRunning = try c.decodeIfPresent(Bool.self, forKey: .keepAgentsRunning) ?? true
            askBeforeQuit = try c.decodeIfPresent(Bool.self, forKey: .askBeforeQuit) ?? true
            confirmCloseTerminal = try c.decodeIfPresent(Bool.self, forKey: .confirmCloseTerminal) ?? true
            confirmDeleteSession = try c.decodeIfPresent(Bool.self, forKey: .confirmDeleteSession) ?? true
            worktreeFolder = try c.decodeIfPresent(String.self, forKey: .worktreeFolder) ?? "~/AgentBox/worktrees"
            cleanSessionFolder = try c.decodeIfPresent(String.self, forKey: .cleanSessionFolder) ?? "~/AgentBox/sessions"
            branchPrefix = try c.decodeIfPresent(BranchPrefixMode.self, forKey: .branchPrefix) ?? .gitUser
            branchPrefixCustom = try c.decodeIfPresent(String.self, forKey: .branchPrefixCustom) ?? ""
        }
    }

    public struct Agents: Codable, Equatable, Sendable {
        public var defaultAgent = TerminalProvider.claude

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            defaultAgent = try c.decodeIfPresent(TerminalProvider.self, forKey: .defaultAgent) ?? .claude
        }
    }

    public enum NotificationSound: String, Codable, Sendable, CaseIterable { case system, none }

    /// Settings › Notifications (03 §14.2, 06 §3.5). A permissão do sistema não vive aqui: só o usuário a pede, pelo botão da seção.
    public struct Notifications: Codable, Equatable, Sendable {
        public var needsInput = true
        public var finished = true
        public var failed = true
        public var terminalBell = false
        public var suppressWhenVisible = true
        public var sound = NotificationSound.system
        public var dockBadge = true

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            needsInput = try c.decodeIfPresent(Bool.self, forKey: .needsInput) ?? true
            finished = try c.decodeIfPresent(Bool.self, forKey: .finished) ?? true
            failed = try c.decodeIfPresent(Bool.self, forKey: .failed) ?? true
            terminalBell = try c.decodeIfPresent(Bool.self, forKey: .terminalBell) ?? false
            suppressWhenVisible = try c.decodeIfPresent(Bool.self, forKey: .suppressWhenVisible) ?? true
            sound = try c.decodeIfPresent(NotificationSound.self, forKey: .sound) ?? .system
            dockBadge = try c.decodeIfPresent(Bool.self, forKey: .dockBadge) ?? true
        }
    }

    public enum CursorStyle: String, Codable, Sendable, CaseIterable { case block, bar, underline }

    public struct Terminal: Codable, Equatable, Sendable {
        public static let fontSizeRange = 8...32
        public static let defaultFont = "SF Mono"
        public static let defaultTheme = "ghostty-default-dark"
        /// Famílias monoespaçadas que existem em todo macOS.
        public static let fontFamilies = ["SF Mono", "Menlo", "Monaco", "Courier New"]

        public var fontFamily = Terminal.defaultFont
        public var fontSize = 14
        /// A v1 traz só a paleta do dono (02 §3); a chave existe para a Fatia 2 em diante.
        public var theme = Terminal.defaultTheme
        public var cursor = CursorStyle.block
        public var cursorBlink = true

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? Terminal.defaultFont
            let size = try c.decodeIfPresent(Int.self, forKey: .fontSize) ?? 14
            fontSize = min(max(size, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
            theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? Terminal.defaultTheme
            cursor = try c.decodeIfPresent(CursorStyle.self, forKey: .cursor) ?? .block
            cursorBlink = try c.decodeIfPresent(Bool.self, forKey: .cursorBlink) ?? true
        }
    }
}

/// Validação dos campos de texto (03 §14.1 regra 3): valor inválido não grava e o anterior continua valendo.
public enum SettingsValidation {
    public static func folder(_ text: String) -> Result<String, SettingsValidationError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .failure(.init("Enter a folder path.")) }
        guard trimmed.hasPrefix("/") || trimmed == "~" || trimmed.hasPrefix("~/") else {
            return .failure(.init("Use an absolute path, starting with / or ~."))
        }
        return .success(trimmed.count > 1 && trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed)
    }

    public static func fontSize(_ text: String) -> Result<Int, SettingsValidationError> {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else { return .failure(.init("Enter a number from 8 to 32.")) }
        let range = AppSettings.Terminal.fontSizeRange
        guard range.contains(value) else { return .failure(.init("Size must be between \(range.lowerBound) and \(range.upperBound).")) }
        return .success(value)
    }

    public static func branchPrefix(_ text: String) -> Result<String, SettingsValidationError> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(" ") || trimmed.contains("..") || trimmed.hasPrefix("/") || trimmed.contains("~") {
            return .failure(.init("A branch prefix can't contain spaces, \"..\" or \"~\"."))
        }
        return .success(trimmed)
    }
}

public struct SettingsValidationError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
