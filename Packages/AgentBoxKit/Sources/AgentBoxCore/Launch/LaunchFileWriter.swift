import Foundation

/// Cria e apaga `AB/run/launch/<runID>/` (06 §2.8): diretório `0700`, arquivos `0600`. O app nunca escreve no PTY;
/// aqui só vai o prompt longo (T11, AC-308).
public enum LaunchFileWriter {
    public static func materialize(_ plan: LaunchPlan) throws {
        guard !plan.files.isEmpty else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: plan.launchDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: plan.launchDirectory.path)
        for file in plan.files {
            let url = plan.launchDirectory.appendingPathComponent(file.name)
            guard fm.createFile(atPath: url.path, contents: file.contents, attributes: [.posixPermissions: NSNumber(value: file.posixMode)]) else {
                throw LaunchPlanError.promptFileUnreadable(url.path)
            }
            try fm.setAttributes([.posixPermissions: NSNumber(value: file.posixMode)], ofItemAtPath: url.path)
        }
    }

    /// Apaga o diretório do lançamento (no `exit`, e também depois de erro).
    public static func cleanup(launchDirectory: URL) {
        try? FileManager.default.removeItem(at: launchDirectory)
    }
}
