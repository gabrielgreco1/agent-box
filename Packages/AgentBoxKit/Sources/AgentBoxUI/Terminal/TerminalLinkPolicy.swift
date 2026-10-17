import Foundation

/// Quais links o terminal abre com ⌘-clique (03 §4.1). Só esquemas simples e seguros: um programa no terminal pode
/// emitir OSC 8 com qualquer URL, e abrir `x-apple.systempreferences:`, `file:` ou um esquema de app registrado a
/// partir de saída não confiável é um vetor.
public enum TerminalLinkPolicy {
    public static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    public static func openableURL(_ link: String) -> URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2048, let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme)
        else { return nil }
        if scheme != "mailto", url.host?.isEmpty ?? true { return nil }
        return url
    }
}
