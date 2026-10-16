import Foundation

public enum ComputerCreationPermission: String, Codable, CaseIterable, Sendable {
    case disabled, manual, automatic
    public var rank: Int { switch self {case .disabled: return 0; case .manual: return 1; case .automatic: return 2} }
}
public enum ComputerModePreference: String, Codable, CaseIterable, Sendable { case adaptive, alwaysGraphical }

public struct ComputerResourceLimits: Codable, Equatable, Sendable {
    public var cpus: Double
    public var memoryMiB: Int
    public var maxComputers: Int
    public init(cpus: Double = 1, memoryMiB: Int = 768, maxComputers: Int = 2) {
        self.cpus=cpus; self.memoryMiB=memoryMiB; self.maxComputers=maxComputers
    }
    public func validate() throws {
        guard cpus.isFinite, (0.25...32).contains(cpus), (128...65536).contains(memoryMiB),
              (1...64).contains(maxComputers) else { throw ComputerPolicyError.invalidLimits }
    }
    func restricted(by other: Self) -> Self {
        Self(cpus: min(cpus,other.cpus), memoryMiB: min(memoryMiB,other.memoryMiB), maxComputers: min(maxComputers,other.maxComputers))
    }
}
public enum ComputerPolicyScope: String, Codable, CaseIterable, Sendable { case project, session, terminal, agent }
public struct ComputerPolicyOverride: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(scope.rawValue):\(scopeID)" }
    public var scope: ComputerPolicyScope
    public var scopeID: String
    public var creation: ComputerCreationPermission?
    public var modePreference: ComputerModePreference?
    public var limits: ComputerResourceLimits?
    public var networkAllowed: Bool?
    public init(scope: ComputerPolicyScope, scopeID: String, creation: ComputerCreationPermission? = nil,
                modePreference: ComputerModePreference? = nil, limits: ComputerResourceLimits? = nil, networkAllowed: Bool? = nil) {
        self.scope=scope; self.scopeID=scopeID; self.creation=creation; self.modePreference=modePreference; self.limits=limits; self.networkAllowed=networkAllowed
    }
}
/// The host constructs this ancestry from its registry. Untrusted tools must not choose their own ancestry.
public struct ComputerPolicyContext: Equatable, Sendable {
    public var projectID: String?
    public var sessionID: UUID?
    public var terminalID: UUID
    public var agentID: UUID?
    public init(terminalID: UUID, projectID: String? = nil, sessionID: UUID? = nil, agentID: UUID? = nil) {
        self.terminalID=terminalID; self.projectID=projectID; self.sessionID=sessionID; self.agentID=agentID
    }
    var keys: [(ComputerPolicyScope,String)] {
        var result: [(ComputerPolicyScope,String)] = []
        if let projectID {result.append((.project,projectID))}
        if let sessionID {result.append((.session,sessionID.uuidString.lowercased()))}
        result.append((.terminal,terminalID.uuidString.lowercased()))
        if let agentID {result.append((.agent,agentID.uuidString.lowercased()))}
        return result
    }
}
public struct EffectiveComputerPolicy: Equatable, Sendable {
    public var creation: ComputerCreationPermission
    public var modePreference: ComputerModePreference
    public var limits: ComputerResourceLimits
    public var networkAllowed: Bool
    /// Records every considered layer, including layers whose attempted expansion was capped.
    public var sources: [String]
}
public struct ComputerPolicy: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 2
    public var creation: ComputerCreationPermission
    public var modePreference: ComputerModePreference
    public var limits: ComputerResourceLimits
    public var networkAllowed: Bool
    public var overrides: [ComputerPolicyOverride]
    public init(creation: ComputerCreationPermission = .disabled, modePreference: ComputerModePreference = .adaptive,
                limits: ComputerResourceLimits = .init(), networkAllowed: Bool = true, overrides: [ComputerPolicyOverride] = []) {
        self.creation=creation; self.modePreference=modePreference; self.limits=limits; self.networkAllowed=networkAllowed; self.overrides=overrides
    }
    enum CodingKeys: String, CodingKey { case schemaVersion, creation, modePreference, limits, networkAllowed, overrides }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        let version=try c.decode(Int.self,forKey:.schemaVersion)
        guard (1...2).contains(version) else {throw ComputerPolicyError.unsupportedVersion}
        schemaVersion=2
        creation=try c.decode(ComputerCreationPermission.self,forKey:.creation)
        modePreference=try c.decode(ComputerModePreference.self,forKey:.modePreference)
        limits=try c.decodeIfPresent(ComputerResourceLimits.self,forKey:.limits) ?? .init()
        networkAllowed=try c.decodeIfPresent(Bool.self,forKey:.networkAllowed) ?? true
        overrides=try c.decodeIfPresent([ComputerPolicyOverride].self,forKey:.overrides) ?? []
        try validate()
    }
    public func validate() throws {
        guard schemaVersion == 2 else {throw ComputerPolicyError.unsupportedVersion}
        try limits.validate()
        var seen=Set<String>()
        for item in overrides {
            guard !item.scopeID.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                  seen.insert(item.id.lowercased()).inserted else {throw ComputerPolicyError.invalidScope}
            if item.scope != .project, UUID(uuidString:item.scopeID) == nil {throw ComputerPolicyError.invalidScope}
            try item.limits?.validate()
        }
    }
    public func effective(for context: ComputerPolicyContext) throws -> EffectiveComputerPolicy {
        try validate()
        var result=EffectiveComputerPolicy(creation:creation,modePreference:modePreference,limits:limits,networkAllowed:networkAllowed,sources:["Global"])
        for (scope,key) in context.keys {
            guard let item=overrides.first(where:{$0.scope==scope && (scope == .project ? $0.scopeID==key : $0.scopeID.lowercased()==key)}) else {continue}
            result.sources.append(item.id)
            if let value=item.creation, value.rank < result.creation.rank {result.creation=value}
            if item.modePreference == .alwaysGraphical {result.modePreference = .alwaysGraphical}
            if let value=item.limits {result.limits=result.limits.restricted(by:value)}
            if item.networkAllowed == false {result.networkAllowed=false}
        }
        return result
    }
}
public struct ComputerPolicyStore {
    public let fileURL: URL
    public init(fileURL: URL = AppPaths.applicationSupport.appendingPathComponent("computer-policy.json")) {self.fileURL=fileURL}
    public func load() throws -> ComputerPolicy {
        guard FileManager.default.fileExists(atPath:fileURL.path) else {return ComputerPolicy()}
        return try JSONDecoder().decode(ComputerPolicy.self,from:Data(contentsOf:fileURL))
    }
    public func save(_ policy: ComputerPolicy) throws {
        try policy.validate()
        let directory=fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        if FileManager.default.fileExists(atPath:fileURL.path) {
            let data=try Data(contentsOf:fileURL)
            if let old=try? JSONSerialization.jsonObject(with:data) as? [String:Any], old["schemaVersion"] as? Int == 1 {
                let backup=fileURL.appendingPathExtension("v1.backup")
                if !FileManager.default.fileExists(atPath:backup.path) {try data.write(to:backup,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:backup.path)}
            }
        }
        try JSONEncoder().encode(policy).write(to:fileURL,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:fileURL.path)
    }
}
public enum ComputerPolicyError: Error, LocalizedError {
    case unsupportedVersion, creationDisabled, invalidLimits, invalidScope, graphicalUnavailable
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion:return "Versão de política de computadores não suportada."
        case .creationDisabled:return "A criação de computadores está desativada pela política efetiva."
        case .invalidLimits:return "Use 0,25–32 CPUs, 128–65536 MiB e 1–64 computadores."
        case .invalidScope:return "Escopo vazio, repetido ou com ID inválido."
        case .graphicalUnavailable:return "A política exige desktop. O runtime gráfico ainda não está disponível; nenhum container HTTP foi criado."
        }
    }
}
