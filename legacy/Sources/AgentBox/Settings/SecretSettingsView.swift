import SwiftUI
import AppKit
import AgentBoxCore

struct SecretSettingsView: View {
    @State private var document = SecretDocument()
    @State private var errorText: String?
    @State private var readOnly = false
    @State private var manualName = ""
    @State private var manualValue = ""
    @State private var pendingEnv: EnvParseResult?
    @State private var pendingSource = ""
    @State private var selectedSecretID: UUID?
    @State private var grantScope: SecretGrantScope = .project
    @State private var grantScopeID = ""
    @State private var grantUse: SecretGrantUse = .tool
    @State private var grantDestination = ""
    @State private var grantDelegable = false
    @State private var hasExpiry = false
    @State private var expiry = Date().addingTimeInterval(86400)

    private let repository = SecretRepository()
    private let vault = SecretVault(backend: KeychainSecretStore())

    var body: some View {
        Form {
            Section("Credenciais e variáveis") {
                Text("Valores ficam no Keychain. A lista contém somente nomes e referências. Importar não envia o arquivo a um agente.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("NOME_DA_VARIAVEL", text: $manualName)
                    SecureField("Valor", text: $manualValue)
                    Button("Salvar") { addManual() }
                        .disabled(readOnly || manualName.isEmpty)
                }
                Button("Selecionar arquivo .env…") { chooseEnv() }.disabled(readOnly)
                if let pendingEnv {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Revisar importação · \(pendingSource)").font(.subheadline)
                        Text(pendingEnv.entries.map(\.name).joined(separator: ", ")).textSelection(.enabled)
                        Text("\(pendingEnv.entries.count) nomes · valores mascarados").font(.caption).foregroundStyle(.secondary)
                        if !pendingEnv.duplicateNames.isEmpty {
                            Text("Duplicados: \(pendingEnv.duplicateNames.joined(separator: ", "))")
                                .foregroundStyle(.red)
                        }
                        HStack {
                            Button("Cancelar") { self.pendingEnv = nil; pendingSource = "" }
                            Button("Importar para Keychain") { importEnv() }
                                .disabled(!pendingEnv.duplicateNames.isEmpty || pendingEnv.entries.isEmpty)
                        }
                        Text("O arquivo original permanece no local de origem, ainda com os valores.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if document.references.isEmpty { Text("Nenhuma credencial salva.").foregroundStyle(.secondary) }
                ForEach(document.references) { reference in
                    HStack {
                        Text(reference.name).font(.system(.body, design: .monospaced))
                        Spacer()
                        Text(reference.sourceLabel).font(.caption).foregroundStyle(.secondary)
                        Text("••••••").foregroundStyle(.secondary)
                    }
                }
            }
            Section("Concessões específicas") {
                Text("Nenhuma credencial é liberada a todos os agentes automaticamente. Cada concessão exige identidade de escopo, uso e destino exatos.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Credencial", selection: $selectedSecretID) {
                    Text("Selecione").tag(Optional<UUID>.none)
                    ForEach(document.references) { reference in
                        Text(reference.name).tag(Optional(reference.id))
                    }
                }
                Picker("Escopo", selection: $grantScope) {
                    ForEach(SecretGrantScope.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("ID do escopo (UUID)", text: $grantScopeID)
                Picker("Uso", selection: $grantUse) {
                    ForEach(SecretGrantUse.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Destino específico (ferramenta ou processo)", text: $grantDestination)
                Toggle("Pode ser delegado por um broker compatível", isOn: $grantDelegable)
                Toggle("Definir prazo", isOn: $hasExpiry)
                if hasExpiry { DatePicker("Válida até", selection: $expiry) }
                Button("Criar concessão") { createGrant() }
                    .disabled(readOnly || selectedSecretID == nil || UUID(uuidString: grantScopeID) == nil ||
                              grantDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ForEach(document.grants) { grant in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(document.references.first(where: { $0.id == grant.secretID })?.name ?? "Referência ausente")
                            Text(grant.revokedAt == nil ? "ativa" : "revogada")
                                .font(.caption).foregroundStyle(grant.revokedAt == nil ? .primary : .secondary)
                            Spacer()
                            if grant.revokedAt == nil {
                                Button("Revogar") { revoke(grant.id) }
                            }
                        }
                        Text("\(grant.scope.label) \(grant.scopeID.uuidString) · \(grant.use.label) · \(grant.destination) · r\(grant.revision)")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if grant.delegable { Text("Delegável somente por broker compatível").font(.caption2).foregroundStyle(.secondary) }
                        if let expiresAt = grant.expiresAt { Text("Expira em \(expiresAt.formatted())").font(.caption2).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
                Text("Revogar bloqueia futuras resoluções pelo serviço. Um valor já entregue em env a um processo exige reinício e pode exigir rotação.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
        .task { refresh() }
    }

    private func refresh() {
        do { document = try repository.load(); readOnly = false; errorText = nil }
        catch { readOnly = true; errorText = error.localizedDescription }
    }
    private func addManual() {
        do {
            _ = try vault.add(name: manualName.trimmingCharacters(in: .whitespacesAndNewlines),
                              value: manualValue)
            manualValue = ""; manualName = ""; refresh()
        } catch { errorText = error.localizedDescription }
    }
    private func chooseEnv() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Selecionar arquivo .env"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                pendingEnv = try EnvFileParser.read(url)
                pendingSource = url.lastPathComponent
                errorText = nil
            } catch { pendingEnv = nil; errorText = error.localizedDescription }
        }
    }
    private func importEnv() {
        guard let pendingEnv else { return }
        do {
            _ = try vault.importEnv(pendingEnv, sourceLabel: pendingSource)
            self.pendingEnv = nil; pendingSource = ""; refresh()
        } catch { errorText = error.localizedDescription }
    }
    private func createGrant() {
        guard let secretID = selectedSecretID, let scopeID = UUID(uuidString: grantScopeID) else { return }
        do {
            _ = try vault.grant(secretID: secretID, scope: grantScope, scopeID: scopeID,
                                use: grantUse, destination: grantDestination,
                                delegable: grantDelegable, expiresAt: hasExpiry ? expiry : nil)
            refresh()
        } catch { errorText = error.localizedDescription }
    }
    private func revoke(_ id: UUID) {
        do { try vault.revoke(grantID: id); refresh() }
        catch { errorText = error.localizedDescription }
    }
}
