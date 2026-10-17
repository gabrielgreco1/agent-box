import AgentBoxProtocol
import Foundation

extension EgressUpstream {
    /// Monta o upstream a partir do perfil e do segredo (lido do armazenamento, nunca do banco).
    ///
    /// - Preset `zyte`: a chave do provedor vai como USUÁRIO do proxy e a senha fica vazia (`proxy.zyte.com:8011`).
    /// - Demais: `username` do perfil e o segredo como senha. Sem usuário e sem segredo = proxy aberto.
    public init(profile: ProxyProfile, secret: String?) {
        let user: String?
        let password: String?
        if profile.preset == .zyte {
            user = secret ?? profile.username
            password = ""
        } else {
            user = profile.username
            password = secret
        }
        self.init(
            scheme: profile.scheme.rawValue, host: profile.host, port: profile.port, username: user, password: password,
            geoCountry: profile.geo?.country, geoMode: profile.geo?.mode.rawValue ?? "suffix",
            geoTemplate: profile.geo?.template ?? "-country-{cc}", geoHeader: profile.geo?.header ?? "X-Country")
    }
}

extension EgressConfigFile {
    /// Config para um computador. `profile == nil` é o modo `direct`. `internalSubnet` é preenchida pelo orquestrador.
    public static func make(profile: ProxyProfile?, secret: String?, allowCIDRs: [String] = [], allowHosts: [String] = [],
                            internalSubnet: String = "") -> EgressConfigFile {
        EgressConfigFile(
            via: profile?.name ?? "direct", upstream: profile.map { EgressUpstream(profile: $0, secret: secret) }, internalSubnet: internalSubnet,
            allowCIDRs: allowCIDRs, allowHosts: allowHosts)
    }
}
