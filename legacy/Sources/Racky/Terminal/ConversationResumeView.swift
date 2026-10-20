import AppKit
import SwiftUI
import RackyCore

/// Metadata review only. The callback owns exclusive-writer admission and PTY launch.
@MainActor struct ConversationResumeView: View {
    @Environment(\.dismiss) private var dismiss
    let initialCandidate: CLIConversationCandidate?
    let onResume: @MainActor (CLIConversationCandidate, Bool) async throws -> Void

    @State private var provider: CLIProvider
    @State private var nativeSessionID: String
    @State private var directory: String
    @State private var selectedCandidate: CLIConversationCandidate?
    @State private var activeClaude: [CLIConversationCandidate] = []
    @State private var discoveryRefreshed = false
    @State private var externalWriterClosed = false
    @State private var executablePath: String?
    @State private var executableError: String?
    @State private var errorText: String?
    @State private var discovering = false
    @State private var resuming = false

    init(initialCandidate: CLIConversationCandidate? = nil, defaultDirectory: String,
         onResume: @escaping @MainActor (CLIConversationCandidate, Bool) async throws -> Void) {
        self.initialCandidate = initialCandidate
        self.onResume = onResume
        _provider = State(initialValue: initialCandidate?.identity.provider ?? .claude)
        _nativeSessionID = State(initialValue: initialCandidate?.identity.nativeSessionID ?? "")
        _directory = State(initialValue: initialCandidate?.projectPath ?? defaultDirectory)
        _selectedCandidate = State(initialValue: initialCandidate)
    }

    private var normalizedIdentity: CLIConversationIdentity? {
        try? CLIConversationIdentity(provider: provider,
                                     nativeSessionID: nativeSessionID.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isListedActive: Bool {
        guard let normalizedIdentity, provider == .claude else { return false }
        if activeClaude.contains(where: { $0.identity == normalizedIdentity }) { return true }
        return !discoveryRefreshed && initialCandidate?.identity == normalizedIdentity &&
            initialCandidate?.activity == .active
    }

    private var directoryIsValid: Bool { (try? WorkspaceDirectory.resolve(directory)) != nil }
    private var canResume: Bool {
        normalizedIdentity != nil && directoryIsValid && executablePath != nil &&
            !isListedActive && externalWriterClosed && !resuming && !discovering
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Retomar conversa").font(.system(size: 15, weight: .medium))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Cliente", selection: $provider) {
                        Text("Claude Code").tag(CLIProvider.claude)
                        Text("Codex").tag(CLIProvider.codex)
                        Text("OpenCode").tag(CLIProvider.opencode)
                    }
                    .onChange(of: provider) { _, _ in
                        selectedCandidate = nil
                        nativeSessionID = ""
                        externalWriterClosed = false
                        errorText = nil
                        resolveExecutable()
                    }
                    if let executableError {
                        Text(executableError).foregroundStyle(.red)
                    } else if executablePath != nil {
                        Text("Cliente encontrado")
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }

                    TextField("ID da conversa", text: $nativeSessionID)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: nativeSessionID) { _, _ in externalWriterClosed = false }
                    HStack(spacing: 8) {
                        TextField("Pasta do projeto", text: $directory)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: directory) { _, _ in externalWriterClosed = false }
                        Button("Escolher…") { chooseDirectory() }
                    }
                    if !nativeSessionID.isEmpty && normalizedIdentity == nil {
                        Text("ID inválido para este CLI.").foregroundStyle(.red)
                    }
                    if !directoryIsValid {
                        Text("Escolha uma pasta existente.").foregroundStyle(.red)
                    }

                    if provider == .claude {
                        HStack {
                            Button(discoveryRefreshed ? "Atualizar sessões ativas" : "Buscar sessões ativas") {
                                discoverClaude()
                            }
                            .disabled(discovering || resuming || executablePath == nil || !directoryIsValid)
                            if discovering { ProgressView().controlSize(.small) }
                        }
                        Text("Conversas abertas no Claude")
                            .foregroundStyle(.secondary)
                        if discoveryRefreshed {
                            if activeClaude.isEmpty {
                                Text("Nenhuma conversa ativa encontrada.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(activeClaude, id: \.identity) { candidate in
                                    Button {
                                        selectedCandidate = candidate
                                        nativeSessionID = candidate.identity.nativeSessionID
                                        directory = candidate.projectPath
                                        externalWriterClosed = false
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(candidate.identity.nativeSessionID)
                                                .font(.system(size: 11, design: .monospaced))
                                            Text(candidate.projectPath).lineLimit(1).truncationMode(.middle)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Selecionar sessão ativa \(candidate.identity.nativeSessionID)")
                                }
                            }
                        }
                    } else {
                        Text("Informe o ID da conversa que deseja continuar.")
                            .foregroundStyle(.secondary)
                    }

                    if isListedActive {
                        Text("Esta conversa está aberta. Feche o outro terminal e atualize a lista.")
                            .foregroundStyle(.orange)
                    } else {
                        Toggle("Fechei esta conversa nos outros terminais",
                               isOn: $externalWriterClosed)
                            .toggleStyle(.checkbox)
                    }
                    if let errorText { Text(errorText).foregroundStyle(.red).textSelection(.enabled) }
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Cancelar") { dismiss() }.disabled(resuming)
                Spacer()
                Button("Retomar no terminal") { resume() }
                    .disabled(!canResume)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13))
        .padding(18)
        .frame(width: 620, height: 490)
        .onAppear(perform: resolveExecutable)
    }

    private func resolveExecutable() {
        do {
            executablePath = try CLIExecutableResolver().resolve(provider)
            executableError = nil
        } catch {
            executablePath = nil
            executableError = error.localizedDescription
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        do {
            directory = try WorkspaceDirectoryAccess.shared.remember(selected)
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    private func discoverClaude() {
        guard let executablePath else { return }
        let cwd: String
        do {
            cwd = try WorkspaceDirectory.resolve(directory)
            try WorkspaceDirectoryAccess.shared.activate(cwd)
        } catch { errorText = error.localizedDescription; return }
        discovering = true
        errorText = nil
        Task {
            do {
                let candidates = try await Task.detached(priority: .utility) {
                    try CLIConversationCatalog.discoverActiveClaude(executablePath: executablePath,
                                                                    workingDirectory: cwd)
                }.value
                activeClaude = candidates
                discoveryRefreshed = true
                externalWriterClosed = false
            } catch { errorText = discoveryMessage(error) }
            discovering = false
        }
    }

    private func resume() {
        guard canResume, let normalizedIdentity else { return }
        let cwd: String
        let candidate: CLIConversationCandidate
        do {
            cwd = try WorkspaceDirectory.resolve(directory)
            try WorkspaceDirectoryAccess.shared.activate(cwd)
            if let selectedCandidate, selectedCandidate.identity == normalizedIdentity,
               selectedCandidate.projectPath == cwd, selectedCandidate.activity != .active {
                candidate = selectedCandidate
            } else {
                candidate = try CLIConversationCatalog.explicitIdentity(provider: provider,
                    sessionID: normalizedIdentity.nativeSessionID, projectPath: cwd)
            }
        } catch { errorText = error.localizedDescription; return }
        resuming = true
        errorText = nil
        Task {
            do {
                try await onResume(candidate, externalWriterClosed)
                dismiss()
            } catch {
                errorText = error.localizedDescription
                resuming = false
            }
        }
    }

    private func discoveryMessage(_ error: Error) -> String {
        switch error as? CLIConversationError {
        case .listingFailed: return "O Claude não retornou a lista de sessões ativas."
        case .listingTimedOut: return "A consulta de sessões ativas excedeu o tempo limite."
        case .listingTooLarge: return "A lista de sessões ativas excedeu o limite seguro."
        case .invalidListing: return "O formato da lista do Claude não corresponde ao adaptador verificado."
        case .executableUnavailable: return "O CLI Claude não está disponível."
        default: return error.localizedDescription
        }
    }
}
