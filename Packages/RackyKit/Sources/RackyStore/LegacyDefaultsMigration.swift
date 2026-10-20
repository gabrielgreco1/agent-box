import Foundation
import RackyProtocol

/// Copia os UserDefaults do app anterior (domínio = bundle id antigo: frame da janela salvo etc.) para o domínio do app atual.
/// Lê o antigo e grava o novo; nunca apaga o antigo. Valores que o app novo já tem vencem. Roda uma vez (marca no próprio domínio).
public enum LegacyDefaultsMigration {
    public static let completedKey = "racky.legacyDefaultsMigrated.v1"

    /// - Parameters:
    ///   - legacy: onde os valores antigos vivem (`UserDefaults.standard` lê o domínio por nome em `legacyDomain`).
    ///   - target: onde gravar. `domain` é o nome do domínio do alvo (bundle id atual), para saber o que ele já tem.
    /// - Returns: quantas chaves foram copiadas.
    @discardableResult
    public static func migrate(
        legacyDomain: String = LegacyNames.bundleIdentifier, legacy: UserDefaults = .standard,
        targetDomain: String? = Bundle.main.bundleIdentifier, target: UserDefaults = .standard
    ) -> Int {
        if target.bool(forKey: completedKey) { return 0 }
        let old = legacy.persistentDomain(forName: legacyDomain) ?? [:]
        let existing = targetDomain.flatMap { target.persistentDomain(forName: $0) } ?? [:]
        var copied = 0
        for (key, value) in old where key != completedKey && existing[key] == nil && target.object(forKey: key) == nil {
            target.set(value, forKey: key)
            copied += 1
        }
        target.set(true, forKey: completedKey)
        return copied
    }
}
