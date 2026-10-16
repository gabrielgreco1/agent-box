import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AgentBoxCore

struct LibraryView: View {
    private let onLaunch: ((UUID) -> Void)?
    private let onOpenRun: ((AgentUsageRecord) -> Bool)?
    @StateObject private var store=LibraryStore()
    @State private var selection:UUID?
    @State private var tab="Instruções"
    @State private var query=""
    @State private var showArchived=false
    @State private var editingAgent:SavedAgent?
    @State private var editingMemory:AgentMemory?
    @State private var pendingDelete:UUID?
    @State private var context:String?
    @State private var viewedSkill:SkillEntry?
    @State private var viewedAgentRevision:AgentDefinitionRevision?
    @State private var viewedMemoryRevision:AgentMemoryRevision?
    @State private var projectKey=""
    @State private var taskKey=""
    @State private var profileKey=""
    init(onLaunch: ((UUID) -> Void)? = nil, onOpenRun: ((AgentUsageRecord) -> Bool)? = nil) {
        self.onLaunch = onLaunch
        self.onOpenRun = onOpenRun
    }
    private var selected:SavedAgent? {store.document.agents.first{$0.id==selection}}
    var body:some View {
        HSplitView {
            VStack(alignment:.leading,spacing:10) {
                HStack { Text("Agentes").font(.headline); Spacer(); Button { editingAgent=SavedAgent(name:"") } label:{Image(systemName:"plus")}.help("Novo agente") }
                TextField("Buscar agentes",text:$query).textFieldStyle(.roundedBorder)
                List(selection:$selection) {
                    ForEach(store.document.agents.filter{($0.archived==showArchived) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query))}) { agent in
                        HStack(spacing:8) {
                            Image(systemName:"person.crop.square").foregroundStyle(.secondary)
                            VStack(alignment:.leading,spacing:3){Text(agent.name);Text(agent.provider.displayName).font(.caption).foregroundStyle(.secondary)}
                        }.tag(agent.id)
                    }
                }.listStyle(.sidebar)
                Toggle("Arquivados",isOn:$showArchived).toggleStyle(.checkbox).font(.caption)
            }.padding(14).frame(minWidth:210,idealWidth:230,maxWidth:320)
            VStack(alignment:.leading,spacing:0) {
                if let agent=selected {
                    HStack {
                        Text(agent.name).font(.system(size:16,weight:.medium));Text("r\(agent.revision)").font(.caption).foregroundStyle(.secondary);Spacer()
                        Menu("Revisões") {
                            ForEach(store.document.agentRevisions.filter{$0.agentID==agent.id}.sorted{$0.revision > $1.revision}) { revision in
                                Button("r\(revision.revision) · \(revision.recordedAt.formatted())") { viewedAgentRevision=revision }
                            }
                        }
                        Button("Editar"){editingAgent=agent}
                        if let onLaunch {
                            Button("Usar…") { onLaunch(agent.id) }.disabled(agent.archived)
                        }
                        Menu { Button("Duplicar"){selection=store.duplicate(agent)};Button(agent.archived ? "Restaurar":"Arquivar"){var changed=agent;changed.archived.toggle();store.saveAgent(changed)} } label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).frame(width:24)
                    }.padding(16)
                    Picker("Área",selection:$tab) {ForEach(["Instruções","Memória","Skills","Histórico"],id:\.self){Text($0)}}.pickerStyle(.segmented).padding(.horizontal,16).padding(.bottom,12)
                    Divider()
                    ScrollView {
                        VStack(alignment:.leading,spacing:16) {
                            switch tab {
                            case "Memória": memories(agent)
                            case "Skills": skills(agent)
                            case "Histórico": history(agent)
                            default:
                                if !agent.summary.isEmpty {Text(agent.summary).foregroundStyle(.secondary)}
                                Text(agent.instructions.isEmpty ? "Adicione as instruções deste agente em Editar." : agent.instructions).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                            }
                        }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
                    }
                    Divider()
                    HStack {
                        Text("Definição salva · preparar contexto não inicia execução").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Preparar contexto"){do{context=try LibraryContext.prepare(agentID:agent.id,in:store.document,projectKey:projectKey.isEmpty ? nil : projectKey,taskKey:taskKey.isEmpty ? nil : taskKey,profileKey:profileKey.isEmpty ? nil : profileKey).text}catch{store.error=error.localizedDescription}}.disabled(agent.archived)
                    }.padding(14)
                } else {
                    ContentUnavailableView("Sua biblioteca",systemImage:"person.2",description:Text("Crie agentes reutilizáveis com instruções, memória e skills."))
                }
            }.frame(minWidth:480)
        }.frame(minWidth:760,minHeight:500)
        .sheet(item:$editingAgent){ agent in AgentEditor(agent:agent){saved in if store.saveAgent(saved) {selection=saved.id;return true};return false} }
        .sheet(item:$editingMemory){ memory in MemoryEditor(memory:memory,agentID:selection ?? UUID()){ saved in if let id=selection {return store.saveMemory(saved,agentID:id)};return false } }
        .sheet(isPresented:Binding(get:{context != nil},set:{if !$0 {context=nil}})) { contextSheet }
        .sheet(item:$viewedSkill){skill in SkillViewer(skill:skill)}
        .sheet(item:$viewedAgentRevision){revision in AgentRevisionViewer(revision:revision)}
        .sheet(item:$viewedMemoryRevision){revision in MemoryRevisionViewer(revision:revision)}
        .alert("Biblioteca",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error=nil}})){Button("OK"){store.error=nil}} message:{Text(store.error ?? "")}
        .confirmationDialog("Excluir memória?",isPresented:Binding(get:{pendingDelete != nil},set:{if !$0 {pendingDelete=nil}}),titleVisibility:.visible){Button("Excluir",role:.destructive){if let id=pendingDelete {store.deleteMemory(id)};pendingDelete=nil}} message:{Text("A memória será removida das próximas seleções. Contexto já enviado a um CLI não é apagado.")}
    }
    @ViewBuilder private func memories(_ agent:SavedAgent)->some View {
        HStack {Text("Memórias selecionadas para este agente").foregroundStyle(.secondary);Spacer();Button("Nova memória"){editingMemory=AgentMemory(title:"",content:"",scopeKey:agent.id.uuidString)}}
        Text("Memórias de projeto, tarefa e perfil exigem ID de escopo correspondente no preparo do contexto.").font(.caption).foregroundStyle(.secondary)
        HStack { TextField("ID do projeto",text:$projectKey);TextField("ID da tarefa",text:$taskKey);TextField("ID do perfil",text:$profileKey) }.textFieldStyle(.roundedBorder)
        let items=store.document.memories.filter{$0.scope == .preference || ($0.scope == .agent && $0.scopeKey==agent.id.uuidString) || agent.memoryIDs.contains($0.id)}
        if items.isEmpty {Text("Nenhuma memória salva.").foregroundStyle(.secondary)}
        ForEach(items){memory in
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Toggle(memory.title,isOn:Binding(get:{agent.memoryIDs.contains(memory.id)},set:{store.selectMemory(memory.id,agentID:agent.id,selected:$0)})).toggleStyle(.checkbox).disabled(memory.archived && !agent.memoryIDs.contains(memory.id))
                    Spacer();Text(memory.scope.label).font(.caption).foregroundStyle(.secondary)
                    Menu("r\(memory.revision)") {
                        ForEach(store.document.memoryRevisions.filter{$0.memoryID==memory.id}.sorted{$0.revision > $1.revision}) { revision in
                            Button("r\(revision.revision) · \(revision.recordedAt.formatted())") { viewedMemoryRevision=revision }
                        }
                    }
                    Button {editingMemory=memory}label:{Image(systemName:"pencil")}.help("Editar memória")
                    Button {store.setMemoryArchived(memory,archived:!memory.archived)}label:{Image(systemName:memory.archived ? "tray.and.arrow.up" : "archivebox")}.help(memory.archived ? "Restaurar memória" : "Arquivar memória")
                    Button {pendingDelete=memory.id}label:{Image(systemName:"trash")}.help("Excluir memória")
                }
                Text(memory.content).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                Text("\(memory.kind.label) · \(memory.source) · r\(memory.revision)" + (memory.archived ? " · arquivada" : "")).font(.caption2).foregroundStyle(.secondary)
                if let validUntil=memory.validUntil { Text("Válida até \(validUntil.formatted())").font(.caption2).foregroundStyle(.secondary) }
            }.padding(.vertical,8)
            Divider()
        }
    }
    @ViewBuilder private func skills(_ agent:SavedAgent)->some View {
        HStack {Text("Arquivos selecionados para o contexto").foregroundStyle(.secondary);Spacer();Button("Importar SKILL.md"){importSkill(agent.id)}}
        Text("A importação lê o arquivo. Não instala ferramentas nem executa scripts. A ativação no CLI será feita pelo adapter correspondente.").font(.caption).foregroundStyle(.secondary)
        if store.document.skills.isEmpty {Text("Nenhuma skill importada.").foregroundStyle(.secondary)}
        ForEach(store.document.skills){skill in
            VStack(alignment:.leading,spacing:7) {
                HStack {Toggle(skill.name,isOn:Binding(get:{agent.skillIDs.contains(skill.id)},set:{store.selectSkill(skill.id,agentID:agent.id,selected:$0)})).toggleStyle(.checkbox);Spacer();Button("Ver arquivo"){viewedSkill=skill}}
                if !skill.summary.isEmpty {Text(skill.summary).font(.caption).foregroundStyle(.secondary)}
                Text(skill.sourcePath).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }.padding(.vertical,8)
            Divider()
        }
    }
    @ViewBuilder private func history(_ agent:SavedAgent)->some View {
        let items=store.document.history.filter{$0.agentID==agent.id}.sorted{$0.startedAt > $1.startedAt}
        if items.isEmpty {ContentUnavailableView("Sem execuções registradas",systemImage:"clock",description:Text("Salvar ou editar uma definição não cria execução. O histórico é preenchido pelo adapter após lançamento real."))}
        ForEach(items){item in
            VStack(alignment:.leading,spacing:6) {
                Text("Execução \(item.id.uuidString) · r\(item.agentRevision)").font(.subheadline).textSelection(.enabled)
                Text(item.startedAt.formatted()).font(.caption).foregroundStyle(.secondary)
                Text("Terminal: \(item.terminalID.uuidString)").font(.caption).textSelection(.enabled)
                if let sessionID=item.sessionID {Text("Sessão: \(sessionID.uuidString)").font(.caption).textSelection(.enabled)}
                if let onOpenRun {
                    Button("Abrir terminal") {
                        if !onOpenRun(item) {
                            store.error = "A sessão ou o terminal desta execução não está mais disponível no workspace."
                        }
                    }
                }
                if !item.computerIDs.isEmpty {Text("Computadores: \(item.computerIDs.map(\.uuidString).joined(separator:", "))").font(.caption).textSelection(.enabled)}
                if !item.profileIDs.isEmpty {Text("Perfis: \(item.profileIDs.map(\.uuidString).joined(separator:", "))").font(.caption).textSelection(.enabled)}
                if let task=item.taskSummary {Text("Tarefa: \(task)").font(.caption).textSelection(.enabled)}
                if let result=item.resultSummary {Text("Resultado: \(result)").font(.caption).textSelection(.enabled)}
                Text("Memórias: \(item.selectedMemories.count) · Skills: \(item.selectedSkills.count)").font(.caption2).foregroundStyle(.secondary)
                if !store.document.agentRevisions.contains(where:{$0.agentID==item.agentID && $0.revision==item.agentRevision}) {
                    Text("Snapshot desta revisão não disponível no registro antigo.").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.vertical,8)
            Divider()
        }
    }
    private func importSkill(_ id:UUID){let panel=NSOpenPanel();panel.allowsMultipleSelection=false;panel.canChooseDirectories=false;panel.title="Importar instruções da skill";panel.allowedContentTypes=[.plainText,.text];if panel.runModal() == .OK,let url=panel.url {store.importSkill(url,agentID:id)}}
    private var contextSheet:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Contexto selecionado").font(.headline)
            Text("Revise antes de exportar. O conteúdo é texto local; nenhuma sessão foi iniciada, memória ativada ou skill instalada.").font(.caption).foregroundStyle(.secondary)
            ScrollView{Text(context ?? "").font(.system(size:12,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
            HStack{Button("Fechar"){context=nil};Spacer();Button("Exportar…"){let panel=NSSavePanel();panel.nameFieldStringValue="agent-context.md";if panel.runModal() == .OK,let url=panel.url {do{try (context ?? "").write(to:url,atomically:true,encoding:.utf8)}catch{store.error=error.localizedDescription}}};Button("Copiar"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(context ?? "",forType:.string)}}
        }.padding(20).frame(width:680,height:520)
    }
}

private struct AgentEditor:View {
    @Environment(\.dismiss) private var dismiss
    @State var agent:SavedAgent
    var onSave:(SavedAgent)->Bool
    var body:some View {
        VStack(alignment:.leading,spacing:14){Text(agent.name.isEmpty ? "Novo agente":"Editar agente").font(.headline)
            TextField("Nome",text:$agent.name).textFieldStyle(.roundedBorder)
            TextField("Descrição curta",text:$agent.summary).textFieldStyle(.roundedBorder)
            Picker("CLI preferido",selection:$agent.provider){ForEach(CLIProvider.allCases.filter{$0 != .shell}){Text($0.displayName).tag($0)}}
            Text("Instruções").font(.caption).foregroundStyle(.secondary)
            TextEditor(text:$agent.instructions).font(.system(size:12,design:.monospaced)).border(Color.secondary.opacity(0.25))
            HStack{Button("Cancelar"){dismiss()};Spacer();Button("Salvar"){agent.name=agent.name.trimmingCharacters(in:.whitespacesAndNewlines);if onSave(agent) {dismiss()}}.disabled(agent.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)}
        }.padding(20).frame(width:580,height:470)
    }
}
private struct MemoryEditor:View {
    @Environment(\.dismiss) private var dismiss
    @State var memory:AgentMemory
    let agentID:UUID
    var onSave:(AgentMemory)->Bool
    var body:some View {
        VStack(alignment:.leading,spacing:14){
            Text("Memória").font(.headline)
            TextField("Título",text:$memory.title).textFieldStyle(.roundedBorder)
            HStack {
                Picker("Tipo",selection:$memory.kind){ForEach(MemoryKind.allCases,id:\.self){Text($0.label).tag($0)}}
                Picker("Escopo",selection:$memory.scope){ForEach(MemoryScope.allCases,id:\.self){Text($0.label).tag($0)}}
            }
            if memory.scope == .project || memory.scope == .task || memory.scope == .profile {
                TextField("ID do escopo",text:$memory.scopeKey).textFieldStyle(.roundedBorder)
            }
            TextField("Fonte ou evidência",text:$memory.source).textFieldStyle(.roundedBorder)
            TextField("Autor",text:$memory.author).textFieldStyle(.roundedBorder)
            Toggle("Definir validade",isOn:Binding(get:{memory.validUntil != nil},set:{memory.validUntil=$0 ? Date().addingTimeInterval(86400) : nil}))
            if memory.validUntil != nil {
                DatePicker("Válida até",selection:Binding(get:{memory.validUntil ?? Date()},set:{memory.validUntil=$0}))
            }
            TextEditor(text:$memory.content).font(.system(size:12)).border(Color.secondary.opacity(0.25))
            HStack { Button("Cancelar"){dismiss()};Spacer();Button("Salvar") {
                memory.title=memory.title.trimmingCharacters(in:.whitespacesAndNewlines)
                if memory.scope == .agent { memory.scopeKey=agentID.uuidString }
                if memory.scope == .preference { memory.scopeKey="" }
                if onSave(memory) { dismiss() }
            }.disabled(memory.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ||
                       memory.content.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ||
                       memory.source.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ||
                       ((memory.scope == .project || memory.scope == .task || memory.scope == .profile) &&
                        memory.scopeKey.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)).keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width:600,height:540)
    }
}

private struct SkillViewer:View {
    @Environment(\.dismiss) private var dismiss
    var skill:SkillEntry
    var body:some View{VStack(alignment:.leading,spacing:12){Text(skill.name).font(.headline);Text(skill.sha256).font(.caption2).textSelection(.enabled);ScrollView{Text(skill.content).font(.system(size:12,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)};Button("Fechar"){dismiss()}}.padding(20).frame(width:640,height:480)}
}

private struct AgentRevisionViewer:View {
    @Environment(\.dismiss) private var dismiss
    let revision:AgentDefinitionRevision
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("\(revision.name) · revisão \(revision.revision)").font(.headline)
            Text(revision.recordedAt.formatted()).font(.caption).foregroundStyle(.secondary)
            ScrollView { Text(revision.instructions).font(.system(size:12,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
            Button("Fechar") { dismiss() }
        }.padding(20).frame(width:620,height:460)
    }
}

private struct MemoryRevisionViewer:View {
    @Environment(\.dismiss) private var dismiss
    let revision:AgentMemoryRevision
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("\(revision.title) · revisão \(revision.revision)").font(.headline)
            Text("\(revision.kind.label) · \(revision.scope.label) · \(revision.source)").font(.caption).foregroundStyle(.secondary)
            Text(revision.recordedAt.formatted()).font(.caption).foregroundStyle(.secondary)
            ScrollView { Text(revision.content).font(.system(size:12)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
            Button("Fechar") { dismiss() }
        }.padding(20).frame(width:620,height:460)
    }
}
