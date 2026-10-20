import SwiftUI
import RackyCore

@MainActor struct CapturePanel: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CapturePanelStore
    @State private var tab: Tab = .requests
    @State private var draft: CaptureConfiguration?
    @State private var hostsText = ""
    @State private var pathsText = ""
    @State private var fieldsText = ""
    @State private var selectedEventIDs: Set<String> = []
    @State private var datasetName = ""
    @State private var confirmDeleteCaptures = false
    @State private var deleteDatasetID: UUID?
    @State private var staleDraft = false

    private enum Tab: String, CaseIterable {
        case requests = "Requisições"
        case data = "Dados"
        case filters = "Captura"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Listener e dados").font(.system(size: 14, weight: .medium))
                Spacer()
                Label(store.runtimeStateKnown
                      ? (store.captureEnabled ? "Capturando" : "Captura parada") : "Estado não verificado",
                      systemImage: store.runtimeStateKnown && store.captureEnabled ? "record.circle" : "pause.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(store.runtimeStateKnown && store.captureEnabled ? Color.green : .secondary)
            }
            Picker("Exibição", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { item in Text(item.rawValue).tag(item) }
            }
            .pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch tab {
                    case .requests: requests
                    case .data: data
                    case .filters: filters
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = store.errorText {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    .lineLimit(2).textSelection(.enabled)
            }
            if let warning = store.warningText {
                Text(warning).font(.system(size: 11)).foregroundStyle(.orange)
                    .lineLimit(2).textSelection(.enabled)
            }
            if let location = store.exportLocation {
                Text("Exportado em \(location)").font(.system(size: 11))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            HStack {
                if store.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Atualizar") { Task { await store.refresh() } }
                    .disabled(store.isBusy)
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 720, height: 550)
        .task {
            while !Task.isCancelled {
                await store.refresh()
                if draft == nil { loadDraft() }
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .onChange(of: store.configuration) { previous, _ in
            if draft == previous { loadDraft() } else { staleDraft = true }
        }
        .confirmationDialog("Apagar capturas?", isPresented: $confirmDeleteCaptures) {
            Button("Apagar capturas", role: .destructive) {
                selectedEventIDs.removeAll()
                Task { await store.deleteCaptures() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Os resultados de datasets são mantidos.")
        }
        .confirmationDialog("Excluir dataset?", isPresented: Binding(
            get: { deleteDatasetID != nil }, set: { if !$0 { deleteDatasetID = nil } }
        )) {
            Button("Excluir dataset", role: .destructive) {
                guard let id = deleteDatasetID else { return }
                deleteDatasetID = nil
                Task { await store.deleteDataset(id) }
            }
            Button("Cancelar", role: .cancel) { deleteDatasetID = nil }
        } message: {
            Text("As capturas originais são mantidas.")
        }
    }

    private var requests: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup("Cobertura e perdas") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Eventos descartados: \(store.dropped)")
                    ForEach(store.coverage, id: \.self) { item in
                        Text(coverageLabel(item)).help(item)
                    }
                    ForEach(store.gaps, id: \.self) { gap in
                        Label(gapLabel(gap), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help(gap)
                    }
                    if store.coverage.isEmpty && store.gaps.isEmpty {
                        Text("Cobertura ainda não observada.").foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
            HStack {
                Text("\(store.events.count) requisições").foregroundStyle(.secondary)
                Spacer()
                Button("Apagar capturas…") { confirmDeleteCaptures = true }
                    .disabled(store.isBusy || store.events.isEmpty)
            }
            if store.events.isEmpty {
                Text(store.captureEnabled ? "Nenhuma requisição capturada ainda." : "Capture só após ativar filtros e aplicar.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            }
            Text("Com o app fechado, somente o buffer limitado da box retém eventos até a próxima leitura.")
                .foregroundStyle(.secondary)
            ForEach(store.events, id: \.id) { event in
                HStack(alignment: .top, spacing: 8) {
                    if event.hasJSON {
                        Toggle("", isOn: eventSelection(event.id))
                            .labelsHidden().toggleStyle(.checkbox)
                            .accessibilityLabel("Selecionar JSON de \(event.url)")
                    } else {
                        Color.clear.frame(width: 16, height: 16)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(event.source).foregroundStyle(.secondary)
                            Text(event.status)
                            Text(URL(string: event.url)?.host ?? "Host indisponível")
                                .foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Text(event.time).foregroundStyle(.secondary)
                        }
                        Text(event.url).lineLimit(2).truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var data: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Nome do dataset", text: $datasetName)
                    .textFieldStyle(.roundedBorder)
                Button("Criar com JSON selecionado") {
                    let name = datasetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let fields = store.configuration.jsonFields
                    let ids = selectedEventIDs
                    Task { await store.createDataset(name: name, columns: fields, eventIDs: ids) }
                }
                .disabled(store.isBusy || datasetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          selectedEventIDs.isEmpty || store.configuration.jsonFields.isEmpty)
            }
            Text("\(selectedEventIDs.count) eventos JSON selecionados · colunas: \(store.configuration.jsonFields.joined(separator: ", ").ifEmpty("nenhuma"))")
                .foregroundStyle(.secondary).lineLimit(2)
            if store.datasets.isEmpty {
                Text("Nenhum dataset criado a partir de capturas.")
                    .foregroundStyle(.secondary).padding(.vertical, 18)
            }
            ForEach(store.datasets, id: \.id) { dataset in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dataset.name)
                        Text("\(dataset.rowCount) linhas").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("JSON") { Task { await store.exportDataset(dataset.id, csv: false) } }
                        .disabled(store.isBusy)
                    Button("CSV") { Task { await store.exportDataset(dataset.id, csv: true) } }
                        .disabled(store.isBusy)
                    Button("Excluir…") { deleteDatasetID = dataset.id }
                        .disabled(store.isBusy)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder private var filters: some View {
        if draft != nil {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Ativar captura", isOn: configBinding(\.enabled))
                    .toggleStyle(.checkbox)
                Text("O estado acima só muda após Aplicar e confirmação do runtime.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("Hosts permitidos (um por linha ou vírgula)", text: $hostsText)
                    TextField("Caminhos a preservar", text: $pathsText)
                        .help("Só prefixos estáticos; o restante do caminho e a query não são salvos. Não filtra o tráfego observado.")
                }
                .textFieldStyle(.roundedBorder)
                Toggle("Incluir corpo JSON", isOn: configBinding(\.includeJSON))
                    .toggleStyle(.checkbox)
                TextField("Campos JSON permitidos para dataset", text: $fieldsText)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    TextField("Bytes por resposta", value: configBinding(\.maxBodyBytes), format: .number)
                    TextField("Máximo de eventos", value: configBinding(\.maxEvents), format: .number)
                    TextField("Retenção em segundos", value: configBinding(\.retentionSeconds), format: .number)
                }
                .textFieldStyle(.roundedBorder)
                Text("Ativar exige host permitido; incluir JSON exige campos selecionados. Não captura headers ou cookies. JSON inclui somente campos escolhidos; evite dados pessoais ou credenciais.")
                    .foregroundStyle(.secondary)
                Text("Alterar filtros limpa o buffer do runtime; eventos já salvos permanecem. Requisições entre a última leitura e a troca ainda podem ser perdidas.")
                    .foregroundStyle(.secondary)
                if staleDraft {
                    Text("Filtros alterados em outro painel. Descarte a edição e revise os valores atuais.")
                        .foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("Descartar edição") { loadDraft() }
                    Button("Aplicar") { applyDraft() }
                        .disabled(store.isBusy || !canApply || staleDraft)
                }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func configBinding<Value>(_ keyPath: WritableKeyPath<CaptureConfiguration, Value>) -> Binding<Value> {
        Binding(get: { draft![keyPath: keyPath] }, set: { draft?[keyPath: keyPath] = $0 })
    }

    private func eventSelection(_ id: String) -> Binding<Bool> {
        Binding(get: { selectedEventIDs.contains(id) }, set: { selected in
            if selected { selectedEventIDs.insert(id) } else { selectedEventIDs.remove(id) }
        })
    }

    private func loadDraft() {
        draft = store.configuration
        staleDraft = false
        hostsText = store.configuration.hosts.joined(separator: ", ")
        pathsText = store.configuration.pathPrefixes.joined(separator: ", ")
        fieldsText = store.configuration.jsonFields.joined(separator: ", ")
    }

    private func applyDraft() {
        guard var config = draft else { return }
        config.hosts = list(hostsText)
        config.pathPrefixes = list(pathsText)
        config.jsonFields = list(fieldsText)
        Task { await store.apply(config) }
    }

    private var canApply: Bool {
        guard let draft else { return false }
        if draft.enabled && list(hostsText).isEmpty { return false }
        if draft.enabled && draft.includeJSON && list(fieldsText).isEmpty { return false }
        return true
    }

    private func list(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func coverageLabel(_ key: String) -> String {
        switch key {
        case "browser_context_requests": return "Requisições do navegador"
        case "browser_context_responses": return "Respostas do navegador"
        case "browser_context_failures": return "Falhas de rede do navegador"
        case "broker_http_get_head": return "HTTP GET/HEAD do broker"
        default: return String(key.replacingOccurrences(of: "_", with: " ").prefix(64))
        }
    }

    private func gapLabel(_ key: String) -> String {
        switch key {
        case "browser_worker_internal_requests": return "Requisições internas de workers não observadas"
        case "websocket_frames": return "Frames de WebSocket não observados"
        case "cache_revalidation_detail": return "Detalhes de revalidação de cache ausentes"
        case "browser_response_bodies": return "Corpos de resposta do navegador não capturados"
        case "curl": return "curl fora da cobertura"
        case "python_requests": return "Python requests fora da cobertura"
        case "curl_cffi": return "curl_cffi fora da cobertura"
        case "other_python_libraries": return "Outras bibliotecas Python fora da cobertura"
        case "raw_sockets": return "Sockets diretos fora da cobertura"
        case "proxy_traffic": return "Tráfego de proxy fora da cobertura"
        case "broker_http_redirects_not_followed": return "Redirecionamentos HTTP não seguidos"
        case "configuration_changes_clear_ring": return "Mudar filtros limpa o ring do runtime"
        default: return String(key.replacingOccurrences(of: "_", with: " ").prefix(64))
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
