import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AgentBoxCore

struct LibraryView: View {
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
                        Button("Editar"){editingAgent=agent}
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
                        Text("Contexto local · ativação nativa pendente").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Revisar contexto"){do{context=try LibraryContext.render(agentID:agent.id,in:store.document)}catch{store.error=error.localizedDescription}}.disabled(agent.archived)
                    }.padding(14)
                } else {
                    ContentUnavailableView("Sua biblioteca",systemImage:"person.2",description:Text("Crie agentes reutilizáveis com instruções, memória e skills."))
                }
            }.frame(minWidth:480)
        }.frame(minWidth:760,minHeight:500)
        .sheet(item:$editingAgent){ agent in AgentEditor(agent:agent){saved in store.saveAgent(saved);selection=saved.id} }
        .sheet(item:$editingMemory){ memory in MemoryEditor(memory:memory){ saved in if let id=selection {store.saveMemory(saved,agentID:id)} } }
        .sheet(isPresented:Binding(get:{context != nil},set:{if !$0 {context=nil}})) { contextSheet }
        .sheet(item:$viewedSkill){skill in SkillViewer(skill:skill)}
        .alert("Biblioteca",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error=nil}})){Button("OK"){store.error=nil}} message:{Text(store.error ?? "")}
        .confirmationDialog("Excluir memória?",isPresented:Binding(get:{pendingDelete != nil},set:{if !$0 {pendingDelete=nil}}),titleVisibility:.visible){Button("Excluir",role:.destructive){if let id=pendingDelete {store.deleteMemory(id)};pendingDelete=nil}} message:{Text("A memória será removida das próximas seleções. Contexto já enviado a um CLI não é apagado.")}
    }
    @ViewBuilder private func memories(_ agent:SavedAgent)->some View {
        HStack {Text("Memórias selecionadas para este agente").foregroundStyle(.secondary);Spacer();Button("Nova memória"){editingMemory=AgentMemory(title:"",content:"",scopeKey:agent.id.uuidString)}}
        let items=store.document.memories.filter{$0.scope == .preference || ($0.scope == .agent && $0.scopeKey==agent.id.uuidString) || agent.memoryIDs.contains($0.id)}
        if items.isEmpty {Text("Nenhuma memória salva.").foregroundStyle(.secondary)}
        ForEach(items){memory in
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Toggle(memory.title,isOn:Binding(get:{agent.memoryIDs.contains(memory.id)},set:{store.selectMemory(memory.id,agentID:agent.id,selected:$0)})).toggleStyle(.checkbox)
                    Spacer();Text(memory.scope.label).font(.caption).foregroundStyle(.secondary)
                    Button {editingMemory=memory}label:{Image(systemName:"pencil")}.help("Editar memória")
                    Button {pendingDelete=memory.id}label:{Image(systemName:"trash")}.help("Excluir memória")
                }
                Text(memory.content).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                Text("\(memory.source) · r\(memory.revision)").font(.caption2).foregroundStyle(.secondary)
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
        let items=store.document.history.filter{$0.agentID==agent.id}
        if items.isEmpty {ContentUnavailableView("Sem execuções registradas",systemImage:"clock",description:Text("O histórico será preenchido quando o lançamento de agentes salvos estiver integrado ao CLI."))}
        ForEach(items){item in Text("r\(item.agentRevision) · \(item.startedAt.formatted())\nTerminal \(item.terminalID.uuidString)").font(.caption).textSelection(.enabled)}
    }
    private func importSkill(_ id:UUID){let panel=NSOpenPanel();panel.allowsMultipleSelection=false;panel.canChooseDirectories=false;panel.title="Importar instruções da skill";panel.allowedContentTypes=[.plainText,.text];if panel.runModal() == .OK,let url=panel.url {store.importSkill(url,agentID:id)}}
    private var contextSheet:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Contexto selecionado").font(.headline)
            Text("Revise antes de copiar para o CLI. Nenhuma sessão foi iniciada e nenhuma skill foi instalada.").font(.caption).foregroundStyle(.secondary)
            ScrollView{Text(context ?? "").font(.system(size:12,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
            HStack{Button("Fechar"){context=nil};Spacer();Button("Exportar…"){let panel=NSSavePanel();panel.nameFieldStringValue="agent-context.md";if panel.runModal() == .OK,let url=panel.url {do{try (context ?? "").write(to:url,atomically:true,encoding:.utf8)}catch{store.error=error.localizedDescription}}};Button("Copiar"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(context ?? "",forType:.string)}}
        }.padding(20).frame(width:680,height:520)
    }
}

private struct AgentEditor:View {
    @Environment(\.dismiss) private var dismiss
    @State var agent:SavedAgent
    var onSave:(SavedAgent)->Void
    var body:some View {
        VStack(alignment:.leading,spacing:14){Text(agent.name.isEmpty ? "Novo agente":"Editar agente").font(.headline)
            TextField("Nome",text:$agent.name).textFieldStyle(.roundedBorder)
            TextField("Descrição curta",text:$agent.summary).textFieldStyle(.roundedBorder)
            Picker("CLI preferido",selection:$agent.provider){ForEach(CLIProvider.allCases.filter{$0 != .shell}){Text($0.displayName).tag($0)}}
            Text("Instruções").font(.caption).foregroundStyle(.secondary)
            TextEditor(text:$agent.instructions).font(.system(size:12,design:.monospaced)).border(Color.secondary.opacity(0.25))
            HStack{Button("Cancelar"){dismiss()};Spacer();Button("Salvar"){agent.name=agent.name.trimmingCharacters(in:.whitespacesAndNewlines);onSave(agent);dismiss()}.disabled(agent.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)}
        }.padding(20).frame(width:580,height:470)
    }
}
private struct MemoryEditor:View {
    @Environment(\.dismiss) private var dismiss
    @State var memory:AgentMemory
    var onSave:(AgentMemory)->Void
    var body:some View {
        VStack(alignment:.leading,spacing:14){Text("Memória").font(.headline)
            TextField("Título",text:$memory.title).textFieldStyle(.roundedBorder)
            Picker("Escopo",selection:$memory.scope){Text("Este agente").tag(MemoryScope.agent);Text("Preferência reutilizável").tag(MemoryScope.preference)}
            TextField("Fonte",text:$memory.source).textFieldStyle(.roundedBorder)
            TextEditor(text:$memory.content).font(.system(size:12)).border(Color.secondary.opacity(0.25))
            HStack{Button("Cancelar"){dismiss()};Spacer();Button("Salvar"){onSave(memory);dismiss()}.disabled(memory.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || memory.content.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)}
        }.padding(20).frame(width:550,height:400)
    }
}
private struct SkillViewer:View {
    @Environment(\.dismiss) private var dismiss
    var skill:SkillEntry
    var body:some View{VStack(alignment:.leading,spacing:12){Text(skill.name).font(.headline);Text(skill.sha256).font(.caption2).textSelection(.enabled);ScrollView{Text(skill.content).font(.system(size:12,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)};Button("Fechar"){dismiss()}}.padding(20).frame(width:640,height:480)}
}
