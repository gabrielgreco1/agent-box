// S-03 probe: servidor UDS que autentica o peer (uid, PID, audit token, requisito) e imprime JSON por conexao;
// cliente que so conecta.
// Uso: peerprobe serve <sock> <requirement|-> [n]   |   peerprobe client <sock> [hold-ms]   |   peerprobe self
import CommonCrypto
import Darwin
import Foundation
import Security

let localPeerToken: Int32 = 0x006  // LOCAL_PEERTOKEN (sys/un.h)
let localPeerPid: Int32 = 0x002  // LOCAL_PEERPID

func makeAddress(_ path: String) -> (sockaddr_un, socklen_t) {
    var a = sockaddr_un()
    a.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &a.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
    a.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return (a, socklen_t(MemoryLayout<sockaddr_un>.size))
}

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

func sha1(_ d: Data) -> [UInt8] {
    var h = [UInt8](repeating: 0, count: 20)
    d.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG(d.count), &h) }
    return h
}

func signingInfo(_ code: SecStaticCode) -> [String: Any] {
    var info: CFDictionary?
    SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
    let d = info as? [String: Any] ?? [:]
    let flags = (d[kSecCodeInfoFlags as String] as? UInt32) ?? 0
    var leaf = ""
    if let certs = d[kSecCodeInfoCertificates as String] as? [SecCertificate], let c = certs.first {
        leaf = hex(sha1(SecCertificateCopyData(c) as Data))
    }
    return [
        "identifier": d[kSecCodeInfoIdentifier as String] ?? "nil", "flags": String(flags, radix: 16), "adhoc": (flags & 0x2) != 0,
        "leafSHA1": leaf,
    ]
}

func selfInfo() -> [String: Any] {
    var code: SecCode?
    SecCodeCopySelf([], &code)
    var st: SecStaticCode?
    SecCodeCopyStaticCode(code!, [], &st)
    return signingInfo(st!)
}

func check(fd: Int32, requirement: String?) -> [String: Any] {
    var out: [String: Any] = [:]
    var uid: uid_t = 0
    var gid: gid_t = 0
    out["getpeereid"] = getpeereid(fd, &uid, &gid) == 0 ? Int(uid) : -1
    out["uidMatches"] = uid == getuid()
    var pid: pid_t = 0
    var plen = socklen_t(MemoryLayout<pid_t>.size)
    out["LOCAL_PEERPID"] = getsockopt(fd, 0, localPeerPid, &pid, &plen) == 0 ? Int(pid) : -1
    var token = audit_token_t()
    var tlen = socklen_t(MemoryLayout<audit_token_t>.size)
    let rc = getsockopt(fd, 0, localPeerToken, &token, &tlen)
    out["LOCAL_PEERTOKEN"] = rc == 0 ? "ok(len=\(tlen))" : "errno=\(errno)"
    guard rc == 0 else { return out }
    out["tokenPid"] = Int(token.val.5)
    let tokenData = withUnsafeBytes(of: token) { Data($0) }
    var guest: SecCode?
    let gs = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: tokenData] as CFDictionary, [], &guest)
    out["guestStatus"] = Int(gs)
    guard gs == errSecSuccess, let guest else { return out }
    out["validityNoReq"] = Int(SecCodeCheckValidity(guest, SecCSFlags(rawValue: kSecCSStrictValidate), nil))
    var st: SecStaticCode?
    SecCodeCopyStaticCode(guest, [], &st)
    let info = signingInfo(st!)
    out["peerIdentifier"] = info["identifier"] ?? "nil"
    out["peerAdhoc"] = info["adhoc"] ?? false
    out["peerLeafSHA1"] = info["leafSHA1"] ?? ""
    if let requirement {
        var req: SecRequirement?
        out["reqCompile"] = Int(SecRequirementCreateWithString(requirement as CFString, [], &req))
        if let req {
            let s = SecCodeCheckValidity(guest, SecCSFlags(rawValue: kSecCSStrictValidate), req)
            out["reqStatus"] = Int(s)
            out["ACCEPT"] = s == errSecSuccess
        }
    }
    return out
}

func json(_ o: [String: Any]) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), encoding: .utf8)!
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "self":
    print(json(selfInfo()))
case "serve":
    let path = args[2]
    let reqArg = args[3]
    var n = args.count > 4 ? Int(args[4])! : 1
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var (a, l) = makeAddress(path)
    _ = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, l) } }
    listen(fd, 8)
    print("listening")
    fflush(stdout)
    while n > 0 {
        let c = accept(fd, nil, nil)
        n -= 1
        var r = check(fd: c, requirement: reqArg == "-" ? nil : reqArg)
        r["server"] = selfInfo()
        print(json(r))
        fflush(stdout)
        close(c)
    }
case "client":
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var (a, l) = makeAddress(args[2])
    let rc = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, l) } }
    if rc != 0 {
        perror("connect")
        exit(1)
    }
    usleep(UInt32((args.count > 3 ? Int(args[3])! : 500) * 1000))
default:
    print("uso")
    exit(64)
}
