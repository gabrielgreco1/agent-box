import Foundation

/// Proxy upstream já resolvido (com credenciais). Só existe em memória e no arquivo 0400 montado no egress (07 CS-145).
public struct EgressUpstream: Sendable, Equatable {
    public var scheme: String  // http | https | socks5
    public var host: String
    public var port: Int
    public var username: String?
    public var password: String?
    /// Caminho DENTRO do container do egress (`/run/agentbox/proxy-ca.pem`).
    public var caFile: String?
    public var geoCountry: String?
    public var geoMode: String
    public var geoTemplate: String
    public var geoHeader: String

    public init(scheme: String, host: String, port: Int, username: String? = nil, password: String? = nil, caFile: String? = nil,
                geoCountry: String? = nil, geoMode: String = "suffix", geoTemplate: String = "-country-{cc}", geoHeader: String = "X-Country") {
        self.scheme = scheme; self.host = host; self.port = port; self.username = username; self.password = password
        self.caFile = caFile; self.geoCountry = geoCountry; self.geoMode = geoMode; self.geoTemplate = geoTemplate; self.geoHeader = geoHeader
    }
}

/// Conteúdo de `egress.json` (lido pelo `agentbox_egress.config`). Política, mais o upstream com credenciais quando há.
public struct EgressConfigFile: Sendable, Equatable {
    /// `direct` ou o nome do `ProxyProfile` (vai para `via` no reqlog).
    public var via: String
    public var upstream: EgressUpstream?
    public var internalSubnet: String
    public var proxyPort: Int
    public var adminPort: Int
    /// Exceção explícita e registrada ao filtro SSRF (07 CS-143, "Allow Local Network for This Computer").
    public var allowCIDRs: [String]
    public var allowHosts: [String]
    public var noise: [String]?
    public var bodyQuotaBytes: Int?

    public static let defaultProxyPort = 3128
    public static let defaultAdminPort = 8790

    public init(via: String = "direct", upstream: EgressUpstream? = nil, internalSubnet: String, proxyPort: Int = defaultProxyPort,
                adminPort: Int = defaultAdminPort, allowCIDRs: [String] = [], allowHosts: [String] = [], noise: [String]? = nil,
                bodyQuotaBytes: Int? = nil) {
        self.via = via; self.upstream = upstream; self.internalSubnet = internalSubnet; self.proxyPort = proxyPort
        self.adminPort = adminPort; self.allowCIDRs = allowCIDRs; self.allowHosts = allowHosts; self.noise = noise
        self.bodyQuotaBytes = bodyQuotaBytes
    }

    /// JSON estável (chaves ordenadas). Contém a senha do proxy: só vai para o arquivo 0400 do egress.
    public func jsonData() throws -> Data {
        var root: [String: Any] = [
            "via": via, "internal_subnet": internalSubnet, "proxy_port": proxyPort, "admin_port": adminPort,
            "allow_cidrs": allowCIDRs, "allow_hosts": allowHosts,
        ]
        if let noise { root["noise"] = noise }
        if let bodyQuotaBytes { root["body_quota_bytes"] = bodyQuotaBytes }
        if let up = upstream {
            var u: [String: Any] = ["scheme": up.scheme, "host": up.host, "port": up.port]
            if let name = up.username { u["username"] = name }
            if let password = up.password { u["password"] = password }
            if let caFile = up.caFile { u["ca_file"] = caFile }
            if let country = up.geoCountry {
                u["geo"] = ["country": country, "mode": up.geoMode, "template": up.geoTemplate, "header": up.geoHeader]
            }
            root["upstream"] = u
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted])
    }
}
