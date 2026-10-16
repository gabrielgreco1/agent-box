import Foundation

public struct DockerConnection: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var contextName: String?
    public init(contextName: String? = nil) { self.contextName = contextName }
    public func validate() throws {
        guard schemaVersion == 1 else {throw DockerConnectionError.invalidConfiguration}
        if let name=contextName {
            guard !name.isEmpty, name.count <= 128, !name.hasPrefix("-"), !name.contains(where:{$0.isNewline || $0 == "\0"}) else {throw DockerConnectionError.invalidConfiguration}
        }
    }
}
public enum DockerConnectionError: Error, LocalizedError {
    case invalidConfiguration
    public var errorDescription:String? {"Contexto Docker inválido. Escolha um contexto existente ou use o padrão do CLI."}
}
public struct DockerConnectionStore {
    public let fileURL:URL
    public init(fileURL:URL = AppPaths.applicationSupport.appendingPathComponent("docker-connection.json")) {self.fileURL=fileURL}
    public func load() throws -> DockerConnection {
        guard FileManager.default.fileExists(atPath:fileURL.path) else {return DockerConnection()}
        let value=try JSONDecoder().decode(DockerConnection.self,from:Data(contentsOf:fileURL));try value.validate();return value
    }
    public func save(_ value:DockerConnection) throws {
        try value.validate()
        try FileManager.default.createDirectory(at:fileURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try JSONEncoder().encode(value).write(to:fileURL,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:fileURL.path)
    }
}
