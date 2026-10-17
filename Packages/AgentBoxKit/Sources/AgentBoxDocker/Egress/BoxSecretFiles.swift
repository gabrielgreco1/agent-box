import Foundation

public enum BoxSecretFilesError: Error, Sendable, Equatable {
    case invalidComputerID(String)
    case unsafeFileName(String)
    case insecurePermissions(path: String, mode: Int)
}

/// Segredos de um computador em arquivos (07 CS-602, 08 AR-512): `<root>/boxes/<computerId>/<papel>/`, diretórios 0700 e
/// arquivos 0400, montados SOMENTE LEITURA só no container do papel que usa. Nada em env, argv ou no `Config` do inspect.
/// O diretório do papel (e não cada arquivo) é montado: assim a troca de proxy, que reescreve `egress.json` de forma atômica,
/// continua visível dentro do container.
public struct BoxSecretFiles: Sendable {
    /// Raiz de App Support (`~/Library/Application Support/AgentBox` ou `$AGENTBOX_HOME`).
    public let root: URL

    public init(root: URL) { self.root = root }

    public var boxesDirectory: URL { root.appendingPathComponent("boxes", isDirectory: true) }

    private func validate(_ computerID: String) throws {
        // O id vira nome de pasta: só UUID/slug simples, nunca `..` nem separadores.
        let ok = !computerID.isEmpty && computerID.count <= 64 && computerID.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard ok else { throw BoxSecretFilesError.invalidComputerID(computerID) }
    }

    public func computerDirectory(_ computerID: String) throws -> URL {
        try validate(computerID)
        return boxesDirectory.appendingPathComponent(computerID, isDirectory: true)
    }

    public func roleDirectory(_ computerID: String, role: ComputerRole) throws -> URL {
        try computerDirectory(computerID).appendingPathComponent(role.rawValue, isDirectory: true)
    }

    private func makeDirectory(_ url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    /// Grava `name` (0400) no diretório do papel. Troca atômica: escreve num temporário 0600 e renomeia.
    @discardableResult
    public func write(_ data: Data, named name: String, computerID: String, role: ComputerRole) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix("."), name != ".." else { throw BoxSecretFilesError.unsafeFileName(name) }
        try makeDirectory(boxesDirectory)
        try makeDirectory(try computerDirectory(computerID))
        let directory = try roleDirectory(computerID, role: role)
        try makeDirectory(directory)
        let final = directory.appendingPathComponent(name)
        let temp = directory.appendingPathComponent(".\(name).\(UUID().uuidString).tmp")
        let fm = FileManager.default
        guard fm.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: temp)
        do {
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? handle.close()
            try? fm.removeItem(at: temp)
            throw error
        }
        try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: temp.path)
        // rename(2) troca o arquivo de forma atômica: quem lê (o egress, pelo bind) nunca vê a janela "sem arquivo".
        guard rename(temp.path, final.path) == 0 else {
            let code = errno
            try? fm.removeItem(at: temp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return final
    }

    /// Remove todos os segredos do computador (07 CS-180). Inexistente é sucesso.
    public func removeAll(computerID: String) throws {
        let directory = try computerDirectory(computerID)
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        // arquivos 0400 em diretório 0700 do próprio usuário: removíveis; garante a escrita no diretório antes
        if let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
        }
        try fm.removeItem(at: directory)
    }

    /// Confere modos 0700/0400 (CA-601). Devolve os caminhos fora do padrão.
    public func permissionViolations(computerID: String) throws -> [String] {
        let directory = try computerDirectory(computerID)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var bad: [String] = []
        func mode(_ url: URL) -> Int { ((try? fm.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)?.intValue ?? -1 }
        if mode(directory) != 0o700 { bad.append(directory.path) }
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if mode(url) != (isDirectory ? 0o700 : 0o400) { bad.append(url.path) }
        }
        return bad
    }
}

/// Segredo de proxy em arquivo 0600 em App Support, no lugar do Vault.
///
/// TODO(T2-10): o Vault (08 AR-511, tabela `secret`) ainda não existe. Enquanto isso, o valor do proxy fica em
/// `<root>/secrets/proxy-<proxyId>` (0600, diretório 0700), com `ProxySecretStorage.file` no banco. Quando o Vault entrar,
/// migrar cada arquivo para um item `secret`, trocar `secret_storage` para `vault` e apagar o arquivo.
public struct ProxySecretFileStore: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public var directory: URL { root.appendingPathComponent("secrets", isDirectory: true) }

    public static func secretID(proxyID: UUID) -> String { "proxy-\(proxyID.uuidString.lowercased())" }

    private func url(_ secretID: String) throws -> URL {
        guard secretID.hasPrefix("proxy-"), secretID.count <= 80, secretID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw BoxSecretFilesError.unsafeFileName(secretID)
        }
        return directory.appendingPathComponent(secretID)
    }

    public func store(_ value: String, secretID: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let target = try url(secretID)
        let temp = directory.appendingPathComponent(".\(secretID).\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temp.path, contents: Data(value.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: temp, to: target)
    }

    public func load(secretID: String) throws -> String? {
        let target = try url(secretID)
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard mode & 0o077 == 0 else { throw BoxSecretFilesError.insecurePermissions(path: target.path, mode: mode) }
        return String(decoding: try Data(contentsOf: target), as: UTF8.self)
    }

    public func remove(secretID: String) throws {
        let target = try url(secretID)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    }
}
