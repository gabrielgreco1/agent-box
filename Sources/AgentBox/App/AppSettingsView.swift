import SwiftUI
import AppKit
import AgentBoxCore

struct AppSettingsView:View {
    @State private var category="Clientes"
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Picker("Configurações",selection:$category){Text("Clientes locais").tag("Clientes");Text("Computadores").tag("Docker");Text("Recursos").tag("Recursos")}.pickerStyle(.segmented)
            switch category {
            case "Docker": DockerSettingsView()
            case "Recursos":
                Form {
                    Section("Listener") {Text("Captura de rede por fonte");Text("A captura ainda não foi conectada ao runtime. Nenhum tráfego é gravado por este app.").font(.caption).foregroundStyle(.secondary)}
                    Section("Credenciais") {Text("Login dos CLIs permanece nos clientes locais.");Text("Importação de .env e concessões via Keychain serão entregues em uma próxima etapa. Não salve segredos em memórias ou skills.").font(.caption).foregroundStyle(.secondary)}
                    Section("Agentes e skills") {Text("A biblioteca permite salvar definições, selecionar memória e importar arquivos de skill. A ativação nativa no CLI depende do adapter.").font(.caption).foregroundStyle(.secondary)}
                }.formStyle(.grouped)
            default:LocalClientsView()
            }
        }.padding(16).frame(minWidth:640,minHeight:420)
    }
}

private struct ClientObservation:Identifiable {
    var provider:CLIProvider
    var id:String {provider.rawValue}
    var path:String?
    var version="Não verificado"
    var auth="Login não verificado"
    var checkedAt:Date?
}

private struct LocalClientsView:View {
    @State private var observations=CLIProvider.allCases.filter{$0 != .shell}.map{ClientObservation(provider:$0)}
    @State private var busy=false
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack{Text("Usa o login existente no terminal").foregroundStyle(.secondary);Spacer();Button("Verificar novamente"){refresh()}.disabled(busy)}.padding(.vertical,14)
            ForEach(observations){item in
                HStack(spacing:12) {
                    if let url=Bundle.module.url(forResource:item.provider.rawValue,withExtension:"png",subdirectory:"Brands"),let image=NSImage(contentsOf:url) {Image(nsImage:image).resizable().scaledToFit().padding(item.provider == .codex ? 2.5:0).frame(width:26,height:26)}
                    VStack(alignment:.leading,spacing:5){Text(item.provider.displayName);Text(item.path ?? "Executável não encontrado").font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)}
                    Spacer()
                    VStack(alignment:.trailing,spacing:5){Text(item.auth).font(.caption);Text(item.version).font(.caption2).foregroundStyle(.secondary).lineLimit(1)}
                }.padding(.vertical,16)
                Divider()
            }
            if busy {ProgressView().controlSize(.small).padding(.top,12)}
            Text("Nenhuma conta é conectada pelo Agent Box. A verificação consulta comandos oficiais de status sem copiar credenciais.").font(.caption).foregroundStyle(.secondary).padding(.top,16)
            Spacer()
        }.task {refresh()}
    }
    private func refresh() {
        guard !busy else {return};busy=true
        Task {
            var results:[ClientObservation]=[]
            for provider in CLIProvider.allCases where provider != .shell {
                var item=ClientObservation(provider:provider)
                do {
                    let path=try CLIExecutableResolver().resolve(provider);item.path=path
                    let version=await CLIVersionProbe.run(executable:path)
                    switch version {case .version(let text):item.version=text;case .timedOut:item.version="Verificação expirou";case .failed:item.version="Versão indisponível"}
                    switch provider {
                    case .claude:
                        let result=await CLICommandProbe.run(executable:path,arguments:["auth","status","--json"],timeout:4)
                        if result.timedOut {item.auth="Status indisponível"}
                        else if let data=result.output.data(using:.utf8),let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let loggedIn=json["loggedIn"] as? Bool {item.auth=loggedIn ? "Autenticado no CLI":"Não autenticado"}
                        else {item.auth="Status não reconhecido"}
                    case .codex:
                        let result=await CLICommandProbe.run(executable:path,arguments:["login","status"],timeout:4)
                        if result.timedOut {item.auth="Status indisponível"}
                        else if result.exitCode == 0 && result.output.lowercased().contains("logged in") {item.auth="Autenticado no CLI"}
                        else if result.output.lowercased().contains("not logged in") {item.auth="Não autenticado"}
                        else {item.auth="Status não reconhecido"}
                    case .opencode:item.auth="Credenciais não verificadas"
                    case .shell:break
                    }
                    item.checkedAt=Date()
                } catch {item.auth="Não instalado";item.version="—"}
                results.append(item)
            }
            observations=results;busy=false
        }
    }
}
