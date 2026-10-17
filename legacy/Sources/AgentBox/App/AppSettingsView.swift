import SwiftUI
import AppKit
import AgentBoxCore

struct AppSettingsView:View {
    @State private var category="Clientes"
    @ObservedObject private var requests=HumanRequestCenter.shared
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Picker("Configurações",selection:$category){Text("Clientes locais").tag("Clientes");Text("Computadores").tag("Docker");Text("Credenciais").tag("Credenciais");Text("Recursos").tag("Recursos")}.pickerStyle(.segmented)
            switch category {
            case "Docker": DockerSettingsView()
            case "Credenciais": SecretSettingsView()
            case "Recursos":
                Form {
                    Section("Intervenção humana") {
                        Toggle("Notificar e tocar som quando um agente precisar de mim",isOn:Binding(get:{requests.notificationsEnabled},set:{enabled in if enabled {Task{_ = await requests.enableNotifications()}} else {requests.disableNotifications()}}))
                        Text("O pedido permanece no app mesmo com notificações desativadas.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Listener") {
                        Text("Captura de rede por computador")
                        Text("Abra Capturas e dados no painel da box para escolher hosts, campos JSON e retenção. A captura só é ativada após Aplicar e confirmação do runtime.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Credenciais") {Text("Login dos CLIs permanece nos clientes locais. Importe .env e gerencie concessões na aba Credenciais.").font(.caption).foregroundStyle(.secondary)}
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
                    if let url=AppResources.brandURL(item.provider.rawValue),let image=NSImage(contentsOf:url) {Image(nsImage:image).resizable().scaledToFit().padding(item.provider == .codex ? 2.5:0).frame(width:26,height:26)}
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
                        let result=await CLICommandProbe.run(executable:path,arguments:["auth","status","--json"],timeout:8)
                        item.auth=authDescription(CLIAuthStatus.interpret(result,provider:.claude))
                    case .codex:
                        let result=await CLICommandProbe.run(executable:path,arguments:["login","status"],timeout:8)
                        item.auth=authDescription(CLIAuthStatus.interpret(result,provider:.codex))
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

    private func authDescription(_ status:CLIAuthStatus)->String {
        switch status {
        case .authenticated:return "Autenticado no CLI"
        case .unauthenticated:return "Não autenticado"
        case .unavailable:return "Status indisponível"
        case .unrecognized:return "Status não reconhecido"
        }
    }
}
