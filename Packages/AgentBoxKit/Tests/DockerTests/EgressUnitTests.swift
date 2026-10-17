import AgentBoxProtocol
import CryptoKit
import Foundation
import Testing

@testable import AgentBoxDocker

private func tempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("abx-egress-unit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("T3-02 - config do egress, segredos em arquivo e integridade do reqlog")
struct EgressUnitTests {
    private func json(_ config: EgressConfigFile) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: try config.jsonData()) as? [String: Any])
    }

    @Test func directConfigHasNoUpstream() throws {
        let root = try json(EgressConfigFile.make(profile: nil, secret: nil, allowCIDRs: ["172.30.0.0/24"], internalSubnet: "172.18.0.0/16"))
        #expect(root["via"] as? String == "direct" && root["upstream"] == nil)
        #expect(root["internal_subnet"] as? String == "172.18.0.0/16" && root["allow_cidrs"] as? [String] == ["172.30.0.0/24"])
        #expect(root["proxy_port"] as? Int == 3128 && root["admin_port"] as? Int == 8790)
    }

    @Test func genericProxyUsesUsernameAndSecretAsPassword() throws {
        let profile = ProxyProfile(name: "corp", scheme: .socks5, host: "10.1.2.3", port: 1080, username: "alice",
                                   geo: ProxyGeo(country: "br", mode: .suffix, template: "-cc-{cc}"))
        let root = try json(EgressConfigFile.make(profile: profile, secret: "s3cr3t-pass"))
        let up = try #require(root["upstream"] as? [String: Any])
        #expect(up["scheme"] as? String == "socks5" && up["host"] as? String == "10.1.2.3" && up["port"] as? Int == 1080)
        #expect(up["username"] as? String == "alice" && up["password"] as? String == "s3cr3t-pass")
        let geo = try #require(up["geo"] as? [String: Any])
        #expect(geo["country"] as? String == "br" && geo["template"] as? String == "-cc-{cc}")
        #expect(root["via"] as? String == "corp")
    }

    @Test func zytePresetPutsTheKeyInTheUsernameWithEmptyPassword() throws {
        let profile = ProxyProfile.zytePreset(name: "zyte", secretID: "proxy-x")
        let up = try #require(json(EgressConfigFile.make(profile: profile, secret: "ZYTEKEY123"))["upstream"] as? [String: Any])
        #expect(up["host"] as? String == "proxy.zyte.com" && up["port"] as? Int == 8011 && up["scheme"] as? String == "http")
        #expect(up["username"] as? String == "ZYTEKEY123" && up["password"] as? String == "")
    }

    @Test func workEnvironmentPointsAtTheEgressAndHoldsNoSecrets() {
        let env = EgressOrchestrator.workEnvironment()
        #expect(env.contains("HTTP_PROXY=http://egress:3128") && env.contains("HTTPS_PROXY=http://egress:3128") && env.contains("ALL_PROXY=http://egress:3128"))
        #expect(env.contains { $0.hasPrefix("NO_PROXY=") && $0.contains("egress") })
        #expect(env.allSatisfy { !$0.lowercased().contains("token") && !$0.lowercased().contains("pass") })
    }

    // MARK: segredos em arquivo

    @Test func secretFilesAre0400In0700AndReplaceAtomically() throws {
        let root = try tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let files = BoxSecretFiles(root: root)
        let id = UUID().uuidString.lowercased()
        let token = try files.write(Data("one".utf8), named: "token", computerID: id, role: .egress)
        try files.write(Data("{}".utf8), named: "egress.json", computerID: id, role: .egress)
        #expect(try files.permissionViolations(computerID: id).isEmpty)
        func mode(_ url: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)?.intValue ?? -1 }
        #expect(mode(token) == 0o400 && mode(token.deletingLastPathComponent()) == 0o700 && mode(token.deletingLastPathComponent().deletingLastPathComponent()) == 0o700)
        try files.write(Data("two".utf8), named: "token", computerID: id, role: .egress)  // troca por rename
        #expect(try String(contentsOf: token, encoding: .utf8) == "two" && mode(token) == 0o400)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: token.deletingLastPathComponent().path).filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
        // permissão frouxa é detectada
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: token.path)
        #expect(try files.permissionViolations(computerID: id).map { URL(fileURLWithPath: $0).lastPathComponent } == ["token"])
        try files.removeAll(computerID: id)
        #expect(!FileManager.default.fileExists(atPath: try files.computerDirectory(id).path))
        try files.removeAll(computerID: id)  // idempotente
    }

    @Test func secretFilesRejectPathTricks() throws {
        let root = try tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let files = BoxSecretFiles(root: root)
        for bad in ["../etc", "a/b", "", "..", "x y"] {
            #expect(throws: BoxSecretFilesError.self) { try files.computerDirectory(bad) }
        }
        for bad in ["../x", "a/b", ".hidden", "", ".."] {
            #expect(throws: BoxSecretFilesError.self) { try files.write(Data(), named: bad, computerID: "ok", role: .egress) }
        }
    }

    @Test func proxySecretFileStoreKeeps0600AndRefusesLooseFiles() throws {
        let root = try tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ProxySecretFileStore(root: root)
        let id = ProxySecretFileStore.secretID(proxyID: UUID())
        #expect(try store.load(secretID: id) == nil)
        try store.store("hunter2", secretID: id)
        #expect(try store.load(secretID: id) == "hunter2")
        let path = store.directory.appendingPathComponent(id).path
        #expect(((try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? NSNumber)?.intValue == 0o600)
        #expect(((try FileManager.default.attributesOfItem(atPath: store.directory.path)[.posixPermissions]) as? NSNumber)?.intValue == 0o700)
        try store.store("rotated", secretID: id)
        #expect(try store.load(secretID: id) == "rotated")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        #expect(throws: BoxSecretFilesError.self) { try store.load(secretID: id) }
        try store.remove(secretID: id)
        #expect(try store.load(secretID: id) == nil)
        #expect(throws: BoxSecretFilesError.self) { try store.load(secretID: "../../etc/passwd") }
    }

    // MARK: integridade do reqlog

    private func chain(_ count: Int, tamperAt: Int? = nil) -> String {
        var previous = ReqlogIntegrity.genesis
        var lines: [String] = []
        for index in 0..<count {
            let line = "{\"id\":\"\(index)\",\"prev_sha256\":\"\(previous)\",\"url\":\"http://x/\(index)\"}"
            previous = SHA256.hash(data: Data(line.utf8)).map { String(format: "%02x", $0) }.joined()
            lines.append(line)
        }
        if let tamperAt { lines[tamperAt] = lines[tamperAt].replacingOccurrences(of: "http://x/", with: "http://evil/") }
        return lines.joined(separator: "\n") + "\n"
    }

    @Test func reqlogIntegrityVerifiesAndLocatesTampering() throws {
        let root = try tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("requests.jsonl")
        #expect(try ReqlogIntegrity.verify(file: file) == .ok(lines: 0), "sem arquivo: nada a verificar")
        try chain(6).write(to: file, atomically: true, encoding: .utf8)
        let ok = try ReqlogIntegrity.verify(file: file)
        #expect(ok == .ok(lines: 6) && ok.message == "Log integrity: OK")
        try chain(6, tamperAt: 2).write(to: file, atomically: true, encoding: .utf8)
        let bad = try ReqlogIntegrity.verify(file: file)
        #expect(bad == .tampered(line: 4) && bad.message == "Tampered at line 4")  // a linha 3 mudou: a 4 deixa de encaixar
        var lines = chain(6).split(separator: "\n").map(String.init)
        lines.remove(at: 1)
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        #expect(try ReqlogIntegrity.verify(file: file) == .tampered(line: 2), "linha apagada")
    }

    @Test func buildContextHashIgnoresPythonBytecode() throws {
        let root = try tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("FROM scratch\n".utf8).write(to: root.appendingPathComponent("Dockerfile"))
        let before = try BuildContext.contentHash(of: root)
        let cache = root.appendingPathComponent("pkg/__pycache__", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: cache.appendingPathComponent("m.cpython-313.pyc"))
        try Data("x".utf8).write(to: root.appendingPathComponent("stray.pyc"))
        #expect(try BuildContext.contentHash(of: root) == before)
    }

    @Test func shippedEgressContextIsPinnedByDigestAndHasNoPackageManagerPins() throws {
        var root = URL(fileURLWithPath: #filePath)
        while root.path != "/", !FileManager.default.fileExists(atPath: root.appendingPathComponent("runtime/egress/Dockerfile").path) { root.deleteLastPathComponent() }
        let dockerfile = try String(contentsOf: root.appendingPathComponent("runtime/egress/Dockerfile"), encoding: .utf8)
        let from = try #require(dockerfile.split(separator: "\n").first { $0.hasPrefix("FROM ") })
        #expect(from.contains("@sha256:") && from.split(separator: ":").last?.count == 64, "base fixada por digest: \(from)")
        #expect(dockerfile.contains("USER 10003") && dockerfile.contains("HEALTHCHECK"))
        let manifest = try String(contentsOf: root.appendingPathComponent("runtime/images.json"), encoding: .utf8)
        #expect(manifest.contains("\"agentbox-egress\"") && manifest.contains(String(from.dropFirst(5))))
    }

    // MARK: testes unitários do egress (Python) rodam junto da suíte Swift

    @Test func pythonEgressUnitSuitePasses() throws {
        let python = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/Library/Frameworks/Python.framework/Versions/Current/bin/python3"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let python else { return }  // sem Python no Mac: a suíte roda no CI Linux (08 §8)
        var root = URL(fileURLWithPath: #filePath)
        while root.path != "/", !FileManager.default.fileExists(atPath: root.appendingPathComponent("runtime/egress/tests").path) { root.deleteLastPathComponent() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-B", "-m", "unittest", "discover", "-s", "tests"]
        process.currentDirectoryURL = root.appendingPathComponent("runtime/egress")
        var env = ProcessInfo.processInfo.environment
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = env
        let output = Pipe()
        process.standardError = output
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        #expect(process.terminationStatus == 0, "unittest do egress falhou:\n\(text.suffix(2000))")
        #expect(text.contains("OK"))
    }
}
