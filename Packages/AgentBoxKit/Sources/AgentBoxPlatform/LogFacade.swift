import os

/// Fachada mínima de log (08 AR-601). Um `Logger` por (subsystem, categoria).
/// Mensagens são `privacy: .private` por padrão; só `publicInfo`/`publicError` expõem texto
/// (use apenas para texto estático sem caminhos, argv, URLs ou IDs). Segredos nunca são registrados.
/// Log em disco com redação (AR-602) entra em tarefa própria.
public struct LogFacade: Sendable {
    /// Subsystems canônicos (08 §0.1).
    public enum Subsystem: String, Sendable {
        case app = "app.agentbox"
        case ptyd = "app.agentbox.ptyd"
        case cli = "app.agentbox.cli"
    }

    public let subsystem: Subsystem
    public let category: String
    private let logger: Logger

    public init(_ subsystem: Subsystem, category: String) {
        self.subsystem = subsystem
        self.category = category
        self.logger = Logger(subsystem: subsystem.rawValue, category: category)
    }

    public func debug(_ message: String) { logger.debug("\(message, privacy: .private)") }
    public func info(_ message: String) { logger.info("\(message, privacy: .private)") }
    public func error(_ message: String) { logger.error("\(message, privacy: .private)") }
    public func publicInfo(_ message: StaticString) { logger.info("\(message, privacy: .public)") }
    public func publicError(_ message: StaticString) { logger.error("\(message, privacy: .public)") }
}
