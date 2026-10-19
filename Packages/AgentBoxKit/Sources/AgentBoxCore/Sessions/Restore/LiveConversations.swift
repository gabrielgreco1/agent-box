import Foundation

/// F32: conversas de agente que já têm um processo vivo nesta máquina (`--resume <id>` ou `--session-id <id>` na linha de
/// comando), venha ele de onde vier: deste app, de outra build com os mesmos dados ou de um terminal solto. A retomada
/// automática nunca relança uma dessas, senão a mesma conversa roda duas vezes.
public enum LiveConversations {
    /// IDs que aparecem depois de `--resume`/`--session-id` em `args` (uma linha de comando por elemento).
    public static func ids(inCommandLines lines: [String]) -> Set<String> {
        var found = Set<String>()
        for line in lines {
            let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            for (i, word) in words.enumerated() {
                if (word == "--resume" || word == "--session-id" || word == "-r"), i + 1 < words.count { found.insert(words[i + 1]) }
                for prefix in ["--resume=", "--session-id="] where word.hasPrefix(prefix) { found.insert(String(word.dropFirst(prefix.count))) }
            }
        }
        return found
    }

    /// Linhas de comando de todos os processos do usuário (`ps`). Vazio se `ps` falhar: aí nada é tratado como vivo.
    public static func current() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-x", "-ww", "-o", "args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ids(inCommandLines: String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init))
    }
}
