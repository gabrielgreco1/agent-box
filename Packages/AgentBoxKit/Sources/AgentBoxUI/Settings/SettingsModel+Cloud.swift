import AgentBoxCore
import AgentBoxProtocol
import Foundation

/// Página Computers › onde rodar (BK-12, P27): local ou nuvem própria, provedor, região, tetos e links. Tudo salva na hora (03 §14.1).
extension SettingsModel {
    var cloudProvider: CloudProviderInfo { CloudProviderCatalog.provider(settings.computers.cloud.provider) ?? CloudProviderCatalog.aws }

    func registerCloudActions(in registry: ActionRegistry) throws {
        try registry.register(.computersRunOn) { [unowned self] arg in
            guard let raw = arg.value, let target = AppSettings.ComputerRunTarget(rawValue: raw) else {
                throw ActionError.failed(.computersRunOn, message: "expected local or cloud")
            }
            change("Where computers run") { $0.computers.runOn = target }
            return target.rawValue
        }
        try registry.register(.computersWhereToggle) { [unowned self] _ in
            computersWhereOpen.toggle()
            return computersWhereOpen ? "open" : "closed"
        }
        try registry.register(.computersCloudProvider) { [unowned self] arg in
            guard let id = arg.value, let provider = CloudProviderCatalog.provider(id) else {
                throw ActionError.failed(.computersCloudProvider, message: "unknown provider")
            }
            guard provider.available else {
                throw ActionError.failed(.computersCloudProvider, message: String(localized: "\(provider.name) is coming soon.", bundle: .module))
            }
            change("Cloud provider") { settings in
                settings.computers.cloud.provider = provider.id
                if !provider.regions.contains(where: { $0.id == settings.computers.cloud.region }), let first = provider.regions.first {
                    settings.computers.cloud.region = first.id
                }
            }
            return provider.id
        }
        try registry.register(.computersCloudRegion) { [unowned self] arg in
            guard let id = arg.value, cloudProvider.regions.contains(where: { $0.id == id }) else {
                throw ActionError.failed(.computersCloudRegion, message: "unknown region")
            }
            change("Cloud region") { $0.computers.cloud.region = id }
            return id
        }
        try registry.register(.computersCloudLimits) { [unowned self] arg in
            guard let raw = arg.value, let update = Self.limitUpdate(raw, current: settings.computers.cloud) else {
                throw ActionError.failed(.computersCloudLimits, message: "expected daily=<n>, monthly=<n>, max=<n> or daily+/daily-…")
            }
            change("Cloud limits") { $0.computers.cloud = update }
            let c = settings.computers.cloud
            return "daily=\(c.dailyCapUSD) monthly=\(c.monthlyCapUSD) max=\(c.maxComputers)"
        }
        try registry.register(
            .computersCloudConnect,
            enablement: { .disabled(reason: String(localized: "Cloud computers are in testing. Your choices are saved.", bundle: .module)) }
        ) { _ in "unavailable" }
        try registry.register(.computersCloudOpenLink) { [unowned self] arg in
            guard let raw = arg.value, let link = cloudProvider.links.first(where: { $0.kind.rawValue == raw }) else {
                throw ActionError.failed(.computersCloudOpenLink, message: "expected console, pricing or setup")
            }
            openURL(link.url)
            return link.url.absoluteString
        }
    }

    /// `daily=12`, `monthly=80`, `max=4` (valor exato) ou `daily+`/`max-` (um passo). Fora do intervalo fica no limite.
    static func limitUpdate(_ raw: String, current: AppSettings.Cloud) -> AppSettings.Cloud? {
        var cloud = current
        let key: String
        let value: (Int, Int) -> Int  // (atual, passo) -> novo
        if let eq = raw.firstIndex(of: "=") {
            key = String(raw[..<eq])
            guard let n = Int(raw[raw.index(after: eq)...]) else { return nil }
            value = { _, _ in n }
        } else if raw.hasSuffix("+") || raw.hasSuffix("-") {
            key = String(raw.dropLast())
            let sign = raw.hasSuffix("+") ? 1 : -1
            value = { now, step in now + sign * step }
        } else {
            return nil
        }
        switch key {
        case "daily": cloud.dailyCapUSD = value(cloud.dailyCapUSD, step(cloud.dailyCapUSD)).clamped(AppSettings.Cloud.dailyCapRange)
        case "monthly": cloud.monthlyCapUSD = value(cloud.monthlyCapUSD, step(cloud.monthlyCapUSD) * 5).clamped(AppSettings.Cloud.monthlyCapRange)
        case "max": cloud.maxComputers = value(cloud.maxComputers, 1).clamped(AppSettings.Cloud.maxComputersRange)
        default: return nil
        }
        return cloud
    }

    /// Passo do teto: 1 até 10, 5 até 50, 10 depois (um clique sempre muda algo que importa).
    private static func step(_ value: Int) -> Int { value < 10 ? 1 : value < 50 ? 5 : 10 }
}

private extension Int {
    func clamped(_ range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
