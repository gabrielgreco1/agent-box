import Foundation

/// Nomes antigos do produto (antes se chamava "Agent Box"). É o ÚNICO lugar do código Swift onde eles aparecem, e só porque
/// existem em máquinas de usuários e em containers já em execução: toda leitura de nome antigo (migração de pasta, label do
/// launchd, Keychain, labels do Docker, variáveis de ambiente) passa por aqui. Ver docs/rebuild/rename-racky.md.
public enum LegacyNames {
    /// `~/Library/Application Support/<isto>`: a pasta de dados anterior.
    public static let dataFolderName = "AgentBox"
    /// `~/<isto>/{worktrees,sessions,projects,runs}`: pastas de trabalho padrão anteriores (nunca movidas).
    public static let userFolderName = "AgentBox"
    /// Banco SQLite dentro de `db/` (com `-wal` e `-shm`).
    public static let databaseFileName = "agentbox.sqlite"
    /// `bundleIdentifier` do app anterior e domínio dos seus UserDefaults.
    public static let bundleIdentifier = "app.agentbox.mac"
    /// LaunchAgent do daemon de PTY anterior.
    public static let launchAgentLabel = "app.agentbox.ptyd.v1"
    public static let launchAgentSocketKey = "AGENTBOX_PTYD_SOCK_V1"
    /// Item do Keychain com a chave mestra do cofre (conta `master-v1`).
    public static let vaultKeychainService = "app.agentbox.vault"
    /// Keychain do app de antes do rebuild (lido só pelo importador de JSON legados, por segredo e com consentimento).
    public static let preRebuildKeychainService = "com.agentbox.secret.v1"
    /// Prefixos das variáveis de ambiente anteriores (`AGENTBOX_HOME`, `AGENT_BOX_HOOK_TOKEN`...).
    public static let environmentPrefixes = ["AGENTBOX_", "AGENT_BOX_"]
    /// Prefixo dos labels de recursos Docker (`agentbox.owner`...) e valor do owner do app instalado.
    public static let dockerLabelPrefix = "agentbox."
    public static let dockerOwner = "agent-box"
    /// Diretório de runtime dentro dos containers criados antes do rename (token e política do egress).
    public static let containerRuntimeDirectory = "/run/agentbox"
    /// Valores gravados no SQLite (CHECK constraint e linhas existentes): não podem mudar sem migrar a tabela.
    public static let importSourceJSON = "agentbox_json"
    public static let importSourceCLI = "agentbox_cli"
    public static let importedFromSecretReferences = "agentbox:secret-references.json"
    /// Coisas EXTERNAS ao app que ainda têm o nome antigo na máquina do usuário: a skill global, o MCP server global e a
    /// pasta do CLI antigo (`~/.agentbox/.env`). O app só as detecta e as bloqueia.
    public static let externalSkillName = "agentbox"
    public static let externalMCPServerName = "agentbox"
    public static let externalCLIFolder = ".agentbox"
    /// Trechos que identificam hooks instalados pela versão anterior (comando `.../agentbox hook ...`).
    public static let hookNeedles = ["agentbox", "agent-box"]
    /// Nomes de processo em relatórios de crash de versões anteriores.
    public static let processNames = ["AgentBox", "agentboxd", "agentbox"]
}
