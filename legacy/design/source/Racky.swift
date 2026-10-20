import SwiftUI
import AppKit
import AVKit
import CoreText

// Design prototype. All tasks, sites, sessions and metrics are illustrative.
// No Docker daemon, real authentication or model endpoint is contacted.

enum Ink {
    static let base = Color(hex: 0x151517)
    static let side = Color(hex: 0x19191B)
    static let panel = Color(hex: 0x1E1E21)
    static let raised = Color(hex: 0x29292D)
    static let line = Color.white.opacity(0.085)
    static let text = Color(hex: 0xE8E8EB)
    static let muted = Color(hex: 0xA1A1AA)
    static let faint = Color(hex: 0x82828C)
    static let mint = Color(hex: 0xCDD5EA)
    static let amber = Color(hex: 0xEAC48B)
    static let blue = Color(hex: 0xA3C6E7)
    static let red = Color(hex: 0xE4A49B)
}
extension Color { init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16)&255)/255, green: Double((hex >> 8)&255)/255, blue: Double(hex&255)/255, opacity: 1) } }
extension View {
    func panel(_ radius: CGFloat = 14) -> some View { self.background(Ink.panel).clipShape(RoundedRectangle(cornerRadius: radius)).overlay(RoundedRectangle(cornerRadius: radius).stroke(Ink.line, lineWidth: 1)) }
    func ruleBottom() -> some View { self.overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: 1) } }
}

enum Screen: String, CaseIterable {
    case overview = "Agora", agents = "Agentes", agentDetail = "Atlas", workspace = "Pesquisa B2B", profiles = "Boxes", memory = "Contexto da tarefa", results = "Resultados", activity = "Atividade", settings = "Clientes locais"
    var icon: String { switch self { case .overview: "square.grid.2x2"; case .agents: "person.2"; case .agentDetail: "person.crop.circle"; case .workspace: "desktopcomputer"; case .profiles: "person.crop.square.stack"; case .memory: "square.stack.3d.up"; case .results: "tablecells"; case .activity: "waveform.path"; case .settings: "slider.horizontal.3" } }
}
@MainActor final class Studio: ObservableObject {
    @Published var rendering = false
    @Published var previewAgent = ""
    @Published var selectedAgent = "Atlas"
    @Published var agentTab = "Memória"
    @Published var liveMode = "Ao vivo"
    private var hoverTask: Task<Void,Never>?
    func showPreview(_ name:String) { hoverTask?.cancel(); previewAgent=name }
    func hidePreview() { hoverTask?.cancel(); hoverTask=Task { try? await Task.sleep(for:.milliseconds(240)); guard !Task.isCancelled else { return }; previewAgent="" } }
    func openAgent(_ name:String) { selectedAgent=name; previewAgent=""; go(.agentDetail) }
    @Published var screen: Screen = .overview
    @Published var modal = ""
    @Published var human = false
    @Published var waiting = true
    @Published var paused = true
    @Published var engine = "Claude Code"
    @Published var nextEngine = "Codex"
    @Published var terminal = "Agente"
    @Published var location = "Pasta"
    @Published var attachedBox = true
    @Published var skills:Set<String> = ["Coleta","Validação"]
    @Published var composer = ""
    @Published var messages: [String] = []
    @Published var toast = ""
    @Published var search = ""
    @Published var activeTab = "Desktop"
    @Published var selectedProfile = "Pesquisa B2B"
    @Published var newTask = "Mapear empresas de logística no Brasil"
    func go(_ s: Screen) { screen=s; modal=""; previewAgent="" }
    func alert(_ text: String) { toast=text; Task { try? await Task.sleep(for: .seconds(3)); if toast == text { toast="" } } }
    func takeControl() { human=true; paused=true; waiting=false; alert("Controle humano ativo. O agente está pausado.") }
    func giveBack() { human=false; paused=false; waiting=false; alert("Contexto atualizado. O agente pode continuar.") }
    func switchEngine() { engine = nextEngine; modal=""; paused = human || waiting; alert("A transferência entre CLIs ainda não está implementada.") }
}

struct BoxMark: View {
    var size: CGFloat = 38
    var color: Color = Ink.mint
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size*0.28).fill(color)
            RoundedRectangle(cornerRadius: size*0.15).stroke(Ink.base.opacity(0.3), lineWidth: 1.2).frame(width:size*0.66,height:size*0.59).rotationEffect(.degrees(-8))
            HStack(spacing:size*0.12) { Capsule().frame(width:size*0.08,height:size*0.2); Capsule().frame(width:size*0.08,height:size*0.2) }.foregroundStyle(Ink.base).rotationEffect(.degrees(-8))
        }.frame(width:size,height:size)
    }
}
struct Tag: View {
    var text: String; var color: Color = Ink.mint; var dot = true
    var body: some View { HStack(spacing:5) { if dot { Circle().fill(color).frame(width:5,height:5) }; Text(text).font(.ui(size:11,weight:.medium)) }.foregroundStyle(color).padding(.horizontal,8).padding(.vertical,5).background(color.opacity(0.08)).clipShape(Capsule()) }
}
struct Action: View {
    var title: String; var icon: String = ""; var primary = false; var tint: Color = Ink.mint; var run: () -> Void
    var body: some View { Button(action:run) { HStack(spacing:7) { if !icon.isEmpty { Image(systemName:icon).font(.ui(size:12,weight:.medium)) }; Text(title).font(.ui(size:12,weight:.semibold)) }.padding(.horizontal,13).frame(height:34).foregroundStyle(primary ? Ink.base : Ink.text).background(primary ? tint : Ink.raised).clipShape(RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(primary ? .clear : Ink.line,lineWidth:1)) }.buttonStyle(.plain).accessibilityLabel(title) }
}
struct SmallIcon: View { var name: String; var body: some View { Image(systemName:name).font(.ui(size:13)).foregroundStyle(Ink.muted).frame(width:24,height:24) } }
struct Heading: View {
    var eyebrow: String; var title: String; var subtitle: String
    var body: some View { Text(title).font(.ui(size:22,weight:.semibold)) }
}
struct SectionLabel: View {
    var title: String; var detail: String = ""
    var body: some View { HStack { Text(title).font(.ui(size:15,weight:.semibold)); Spacer(); Text(detail).font(.ui(size:11)).foregroundStyle(Ink.muted) } }
}

struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: Studio
    var body: some View {
        HStack(spacing:0) {
            Sidebar(model:model).frame(width:220)
            Rectangle().fill(Ink.line).frame(width:1)
            VStack(spacing:0) {
                Group {
                    switch model.screen {
                    case .overview: Overview(model:model)
                    case .agents: AgentLibrary(model:model)
                    case .agentDetail: AgentDetail(model:model)
                    case .workspace: TerminalWorkspace(model:model)
                    case .profiles: Profiles(model:model)
                    case .memory: MemoryScreen(model:model)
                    case .results: ResultsScreen(model:model)
                    case .activity: ActivityScreen(model:model)
                    case .settings: RuntimeSettings(model:model)
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.background(Ink.base).foregroundStyle(Ink.text).font(.ui(size:13)).preferredColorScheme(.dark)
        .accessibilityHidden(!model.modal.isEmpty)
        .allowsHitTesting(model.modal.isEmpty)
        .animation(reduceMotion ? nil : .easeInOut(duration:0.22), value:model.human)
        .animation(reduceMotion ? nil : .easeInOut(duration:0.2), value:model.screen)
        .animation(reduceMotion ? nil : .easeOut(duration:0.18), value:model.modal)
        .overlay { if !model.modal.isEmpty { ModalLayer(model:model).transition(.opacity) } }
        .overlay(alignment:.topLeading) { if !model.previewAgent.isEmpty { AgentPeek(model:model).frame(width:370).offset(x:227,y:370).transition(.opacity.combined(with:.scale(scale:0.97,anchor:.topLeading))).onHover { inside in if inside { model.showPreview(model.previewAgent) } else { model.hidePreview() } } } }
        .animation(reduceMotion ? nil : .spring(response:0.28,dampingFraction:0.86), value:model.previewAgent)
        .overlay(alignment:.bottom) { if !model.toast.isEmpty { Text(model.toast).font(.ui(size:12,weight:.medium)).padding(.horizontal,18).padding(.vertical,12).background(Ink.raised).clipShape(Capsule()).overlay(Capsule().stroke(Ink.line)).padding(.bottom,42).shadow(color:.black.opacity(0.3),radius:20).transition(.move(edge:.bottom).combined(with:.opacity)) } }
    }
    var topBar: some View {
        HStack(spacing:12) {
            Text("Pessoal").foregroundStyle(Ink.faint); Image(systemName:"chevron.right").font(.ui(size:9)).foregroundStyle(Ink.faint)
            Text(model.screen.rawValue).fontWeight(.medium)
            Spacer()
            Button { model.go(.activity) } label: { HStack(spacing:6) { Circle().fill(Ink.amber).frame(width:5,height:5); Text(model.waiting ? "1 precisa de você" : "Tudo em dia") }.font(.ui(size:11)).foregroundStyle(model.waiting ? Ink.amber : Ink.muted) }.buttonStyle(.plain)
            Rectangle().fill(Ink.line).frame(width:1,height:16)
            Text("⌘ K").font(.ui(size:10,design:.monospaced)).foregroundStyle(Ink.faint)
            Button { model.modal="search" } label: { SmallIcon(name:"magnifyingglass") }.buttonStyle(.plain).keyboardShortcut("k",modifiers:.command)
        }.padding(.horizontal,25).frame(height:56).ruleBottom()
    }
}
struct Sidebar: View {
    @ObservedObject var model: Studio
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:7) { ForEach([0xFF6458,0xF8BF4F,0x4BCB65],id:\.self) { c in Circle().fill(Color(hex:UInt32(c))).frame(width:10,height:10) }; Spacer() }.padding(.top,19).padding(.bottom,32)
            HStack(spacing:9) { BoxMark(size:28); Text("racky").font(.ui(size:17,weight:.semibold)); Spacer() }.padding(.bottom,26)
            Action(title:"Nova sessão",icon:"plus") { model.modal="new" }.keyboardShortcut("n",modifiers:.command).padding(.bottom,24)
            VStack(spacing:5) { nav(.overview); nav(.agents); nav(.profiles); nav(.results) }
            HStack { Text("Sessões"); Spacer(); Image(systemName:"ellipsis") }.font(.ui(size:11)).foregroundStyle(Ink.faint).padding(.top,34).padding(.bottom,13)
            conversation("Atlas","Empresas de logística",0)
            conversation("Radar","Preços de monitores",1)
            conversation("Lumen","Relatório de mercado",2)
            Spacer()
            HStack(spacing:8) { BrandIcon(name:"Docker",size:24); Text("Docker não verificado"); Spacer() }.font(.ui(size:11)).foregroundStyle(Ink.faint).padding(.horizontal,10).padding(.bottom,18)
            nav(.settings)
            HStack(spacing:9) { Text("G").font(.ui(size:11)).frame(width:26,height:26).background(Ink.raised).clipShape(Circle()); Text("Gabriel").font(.ui(size:12)); Spacer(); Button { model.modal="search" } label: { Image(systemName:"magnifyingglass") }.buttonStyle(.plain).keyboardShortcut("k",modifiers:.command).foregroundStyle(Ink.faint) }.padding(.top,18).padding(.bottom,18)
        }.padding(.horizontal,17).background(Ink.side)
    }
    func nav(_ s:Screen) -> some View { Button { model.go(s) } label: { HStack(spacing:10) { Image(systemName:s.icon).frame(width:18); Text(s.rawValue); Spacer() }.font(.ui(size:12,weight:model.screen == s ? .semibold : .regular)).foregroundStyle(model.screen == s ? Ink.text : Ink.muted).padding(.horizontal,10).frame(height:37).background(model.screen == s ? Ink.raised : .clear).clipShape(RoundedRectangle(cornerRadius:7)) }.buttonStyle(.plain) }
    func conversation(_ name:String,_ topic:String,_ kind:Int) -> some View {
        Button { model.selectedAgent=name; model.terminal="Agente";model.attachedBox=true;model.go(.workspace) } label: { HStack(spacing:10) { AgentAvatar(name:name,size:27); VStack(alignment:.leading,spacing:4) { HStack { Text(name).font(.ui(size:12,weight:.medium)); Spacer(); Circle().fill(kind == 0 && model.waiting ? Ink.amber : (kind == 2 ? Ink.faint : Ink.mint)).frame(width:5,height:5) }; Text(topic).font(.ui(size:10)).foregroundStyle(Ink.faint).lineLimit(1) } }.padding(9).background(model.screen == .workspace && model.selectedAgent == name ? Ink.raised : .clear).clipShape(RoundedRectangle(cornerRadius:8)) }.buttonStyle(.plain).padding(.bottom,5)
        .onHover { inside in if inside { model.showPreview(name) } else { model.hidePreview() } }
        .contextMenu { Button("Ver prévia") { model.showPreview(name) }; Button("Abrir agente") { model.openAgent(name) } }
        .accessibilityAction(named:"Ver prévia") { model.showPreview(name) }
    }
}
struct Overview: View {
    @ObservedObject var model: Studio
    var body: some View { VStack(alignment:.leading,spacing:24) {
        HStack { Text("Agora").font(.ui(size:23,weight:.semibold)); Spacer(); HStack(spacing:0) { ForEach(["Ao vivo","Histórico"],id:\.self) { item in Button { model.liveMode=item } label: { Text(item).font(.ui(size:12)).padding(.horizontal,13).padding(.vertical,8).background(model.liveMode == item ? Ink.raised : .clear).clipShape(RoundedRectangle(cornerRadius:7)) }.buttonStyle(.plain) } }.padding(3).background(Ink.side).clipShape(RoundedRectangle(cornerRadius:9)) }
        HStack(spacing:18) { LiveCard(model:model,name:"Atlas",topic:"Empresas de logística",kind:0); LiveCard(model:model,name:"Radar",topic:"Preços de monitores",kind:1) }
        HStack { Text("Seus agentes").font(.ui(size:14,weight:.semibold)); Spacer(); Button("Ver todos") { model.go(.agents) }.buttonStyle(.plain).foregroundStyle(Ink.muted).font(.ui(size:12)) }.padding(.top,8)
        HStack(spacing:16) { ForEach(["Atlas","Radar","Lumen"],id:\.self) { name in Button { model.openAgent(name) } label: { HStack(spacing:12) { AgentAvatar(name:name,size:38); VStack(alignment:.leading,spacing:5) { Text(name).font(.ui(size:13,weight:.semibold)); Text(name == "Atlas" ? "12 pesquisas · 3 boxes" : (name == "Radar" ? "8 pesquisas · 2 boxes" : "5 pesquisas · 1 box")).font(.ui(size:11)).foregroundStyle(Ink.faint) }; Spacer(); Image(systemName:"arrow.up.right").foregroundStyle(Ink.faint) }.padding(18).panel(10) }.buttonStyle(.plain) } }
        HStack { Text("Recentes").font(.ui(size:14,weight:.semibold)); Spacer() }.padding(.top,8)
        ForEach([("Lumen","Relatório de mercado","Concluído","16:42"),("Atlas","Fornecedores do Sudeste","86 registros","Ontem")],id:\.1) { item in HStack(spacing:13) { AgentAvatar(name:item.0,size:28); Text(item.1).font(.ui(size:12)); Spacer(); Text(item.2).foregroundStyle(Ink.muted); Text(item.3).foregroundStyle(Ink.faint).frame(width:55,alignment:.trailing) }.font(.ui(size:11)).padding(.vertical,9).ruleBottom() }
        Spacer(minLength:0)
    }.padding(30) }
}
struct DesktopView: View {
    var human = false; var waiting = true; var compact = false
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:8) { Image(systemName:"globe"); Text("Atlas · diretório de empresas"); Spacer(); Image(systemName:"minus"); Image(systemName:"square"); Image(systemName:"xmark") }.font(.ui(size:9)).foregroundStyle(Color(hex:0x778078)).padding(.horizontal,12).frame(height:31).background(Color(hex:0xE0E5DE))
            HStack(spacing:10) { Image(systemName:"arrow.left"); Image(systemName:"arrow.clockwise"); HStack(spacing:7) { Image(systemName:"lock.fill").font(.ui(size:8)); Text("atlas.example/empresas/logistica"); Spacer() }.font(.ui(size:10)).padding(.horizontal,11).frame(height:24).background(.white.opacity(0.65)).clipShape(RoundedRectangle(cornerRadius:5)); Image(systemName:"ellipsis") }.font(.ui(size:10)).foregroundStyle(Color(hex:0x738075)).padding(.horizontal,12).frame(height:38).background(Color(hex:0xEEF0EA))
            ZStack {
                VStack(alignment:.leading,spacing:18) {
                    HStack { Text("atlas").font(.ui(size:22,weight:.bold)).tracking(-1); Text("/ empresas").font(.ui(size:10)).foregroundStyle(.gray); Spacer(); Text("Explorar").font(.ui(size:10)); Text("Minha conta").font(.ui(size:10)) }
                    Rectangle().fill(.black.opacity(0.08)).frame(height:1)
                    HStack { VStack(alignment:.leading,spacing:7) { Text("Logística no Brasil").font(.ui(size:20,weight:.semibold)); Text("Empresas, operações e conexões.").font(.ui(size:10)).foregroundStyle(.gray) }; Spacer(); Text("142 empresas").font(.ui(size:9)).foregroundStyle(.gray) }
                    HStack { Text("⌕  Buscar empresas"); Spacer(); Text("Região  ⌄"); Text("Setor  ⌄") }.font(.ui(size:10)).foregroundStyle(.gray).padding(10).background(.black.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:5))
                    ForEach(Array([("M","Meridiana Logística","São Paulo · Transporte rodoviário"),("V","Via Norte Transportes","Paraná · Armazenagem e distribuição"),("P","Porto Claro Operações","Santa Catarina · Logística integrada")].enumerated()),id:\.offset) { _,x in HStack(spacing:12) { Text(x.0).font(.ui(size:14,weight:.medium)).frame(width:36,height:36).background(Color(hex:0xDCE5DD)).clipShape(RoundedRectangle(cornerRadius:7)); VStack(alignment:.leading,spacing:5) { Text(x.1).font(.ui(size:11,weight:.semibold)); Text(x.2).font(.ui(size:9)).foregroundStyle(.gray) }; Spacer(); Image(systemName:"arrow.up.right").font(.ui(size:10)).foregroundStyle(.gray) }.padding(.vertical,5) }
                    Spacer(minLength:0)
                }.padding(23).foregroundStyle(Color(hex:0x263A2B)).background(Color(hex:0xF5F6F1))
                if waiting || human {
                    Color(hex:0x18221D).opacity(0.28)
                    VStack(spacing:14) { Image(systemName:"hand.raised.circle").font(.ui(size:28,weight:.light)).foregroundStyle(Color(hex:0x4B6555)); Text("Uma verificação rápida").font(.ui(size:17,weight:.semibold)); Text("O site solicitou confirmação humana.\nResolva a verificação neste navegador.").font(.ui(size:11)).multilineTextAlignment(.center).lineSpacing(4).foregroundStyle(.gray); HStack(spacing:12) { RoundedRectangle(cornerRadius:3).stroke(Color.gray.opacity(0.4)).frame(width:22,height:22); Text("Área de verificação do site").font(.ui(size:11)); Spacer(); Image(systemName:"shield.lefthalf.filled").foregroundStyle(Color(hex:0x4B6555)) }.padding(15).background(Color(hex:0xF1F3EE)).clipShape(RoundedRectangle(cornerRadius:6)); Text("Representação ilustrativa · nenhuma verificação real").font(.ui(size:8)).foregroundStyle(.gray) }.padding(25).frame(width:330).foregroundStyle(Color(hex:0x273C2E)).background(Color(hex:0xFCFDF9)).clipShape(RoundedRectangle(cornerRadius:12)).shadow(color:.black.opacity(0.15),radius:30,y:12)
                }
            }.frame(maxHeight:.infinity)
        }.clipShape(RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(human ? Ink.amber.opacity(0.85) : .white.opacity(0.1),lineWidth:human ? 2 : 1))
    }
}

struct Profiles: View {
    @ObservedObject var model: Studio
    let sites = [("in","LinkedIn","Sessão disponível","Verificada há 2 h"),("𝕏","X / Twitter","Sessão disponível","Verificada há 4 h"),("C","Crunchbase","Entrar novamente","Sessão expirada"),("G","Google","Sessão disponível","Verificada há 1 h"),("+","Outros 6 sites","5 disponíveis · 1 pendente","Ver todos os sites")]
    var body: some View {
        VStack(alignment:.leading,spacing:25) {
            HStack { Heading(eyebrow:"AMBIENTES QUE LEMBRAM",title:"Boxes",subtitle:"Guarde a sessão do navegador e os arquivos de cada contexto de trabalho."); Spacer(); Action(title:"Novo perfil",icon:"plus",primary:true) { model.modal="profile" } }
            HStack(alignment:.top,spacing:23) {
                VStack(spacing:12) { profile("Pesquisa B2B","10 sites · 8 sessões disponíveis",Ink.mint,selected:true); profile("Mercado & concorrência","3 sites · 3 sessões disponíveis",Ink.blue); profile("Ambiente limpo","Sem contas · navegação pública",Ink.muted); Spacer(); HStack(alignment:.top,spacing:9) { Image(systemName:"info.circle"); Text("Um perfil tem uma box ativa por vez. Outras pesquisas aguardam ou usam um perfil separado.").lineSpacing(4) }.font(.ui(size:11)).foregroundStyle(Ink.faint).padding(14) }.frame(width:275)
                VStack(alignment:.leading,spacing:20) {
                    HStack(spacing:13) { BoxMark(size:43); VStack(alignment:.leading,spacing:6) { Text("Pesquisa B2B").font(.ui(size:20,weight:.semibold)); Text("Seu contexto para pesquisar empresas e mercado.").font(.ui(size:11)).foregroundStyle(Ink.muted) }; Spacer(); Tag(text:"Em uso",color:Ink.amber) }
                    HStack(spacing:22) { detail("AMBIENTE","Linux · navegador e terminal"); detail("RETOMADA","Persistente"); detail("ÚLTIMO BACKUP","Hoje, 16:30") }.padding(.vertical,5)
                    Rectangle().fill(Ink.line).frame(height:1)
                    SectionLabel(title:"Sessões dos sites",detail:"Estado da última verificação")
                    ForEach(Array(sites.enumerated()),id:\.offset) { i,s in HStack(spacing:12) { BrandIcon(name:s.1,size:22).frame(width:32,height:32); VStack(alignment:.leading,spacing:5) { Text(s.1).font(.ui(size:12,weight:.medium)); Text(s.3).font(.ui(size:10)).foregroundStyle(Ink.faint) }; Spacer(); Text(s.2).font(.ui(size:10)).foregroundStyle(i == 2 ? Ink.amber : Ink.muted); Button { model.go(.workspace); model.takeControl() } label: { Image(systemName:"arrow.up.right").font(.ui(size:11)).foregroundStyle(Ink.faint).frame(width:28,height:28) }.buttonStyle(.plain) }.padding(.vertical,3) }
                    HStack(alignment:.top,spacing:9) { Image(systemName:"lock.shield").foregroundStyle(Ink.mint); Text("Logins ficam no perfil protegido. Senhas e cookies não entram na memória do agente. Um site ainda pode pedir login ou verificação novamente.").font(.ui(size:11)).lineSpacing(4).foregroundStyle(Ink.muted) }.padding(14).background(Ink.mint.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:9))
                    HStack { Action(title:"Abrir navegador",icon:"arrow.up.right",primary:true) { model.go(.workspace); model.takeControl() }; Action(title:"Backup do perfil",icon:"externaldrive") { model.alert("Backup é uma operação planejada; nenhum dado real foi copiado.") }; Spacer(); Text("Opções  ⋯").foregroundStyle(Ink.faint) }
                }.padding(24).panel().frame(maxWidth:.infinity)
            }
            Spacer(minLength:0)
        }.padding(30)
    }
    func profile(_ name:String,_ sub:String,_ color:Color,selected:Bool=false) -> some View { Button { model.selectedProfile=name; model.alert("Perfil selecionado: \(name). Os detalhes demonstram Pesquisa B2B.") } label: { HStack(spacing:12) { BoxMark(size:34,color:color); VStack(alignment:.leading,spacing:6) { Text(name).font(.ui(size:12,weight:.semibold)); Text(sub).font(.ui(size:10)).foregroundStyle(Ink.muted) }; Spacer() }.padding(15).background(selected ? Ink.raised : Ink.panel).clipShape(RoundedRectangle(cornerRadius:11)).overlay(RoundedRectangle(cornerRadius:11).stroke(selected ? Ink.mint.opacity(0.35) : Ink.line)) }.buttonStyle(.plain) }
    func detail(_ label:String,_ value:String) -> some View { VStack(alignment:.leading,spacing:7) { Text(label).font(.ui(size:8,weight:.medium)).tracking(1).foregroundStyle(Ink.faint); Text(value).font(.ui(size:10)) } }
}

struct MemoryScreen: View {
    @ObservedObject var model: Studio
    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            HStack { Heading(eyebrow:"CONTINUIDADE ENTRE AGENTES",title:"Contexto da tarefa",subtitle:"Objetivo, decisões e evidências disponíveis para Claude Code, Codex ou OpenCode."); Spacer(); Tag(text:"Checkpoint #018") }
            HStack(alignment:.top,spacing:22) {
                VStack(alignment:.leading,spacing:22) {
                    HStack { BoxMark(size:30); Text("Mapa de empresas B2B").font(.ui(size:16,weight:.semibold)); Spacer(); Text("Atualizado às 18:42").font(.ui(size:10)).foregroundStyle(Ink.faint) }
                    memoryBlock("Objetivo","Encontrar 50 empresas de logística no Brasil, com site oficial, região e evidência verificável para cada registro.","target")
                    memoryBlock("O que já sabemos","32 empresas validadas. Prioridade para fontes primárias. Empresas duplicadas são agrupadas pelo domínio oficial.","checkmark.seal")
                    memoryBlock("Decisões suas","Somente empresas em operação no Brasil. Não inferir contatos pessoais. Manter a URL e a data de cada evidência.","person.crop.circle")
                    memoryBlock("Próximo passo","Após a verificação humana, retomar a página 4 do diretório. Faltam 18 empresas. Conferir a página antes de agir.","arrow.right.circle")
                    HStack(spacing:9) { Image(systemName:"lock.shield"); Text("Senhas, cookies e raciocínio interno dos modelos não fazem parte deste contexto.").font(.ui(size:10)).lineSpacing(3) }.foregroundStyle(Ink.faint).padding(.top,2)
                }.padding(24).panel().frame(maxWidth:.infinity)
                VStack(alignment:.leading,spacing:22) {
                    SectionLabel(title:"Histórico da pesquisa")
                    timeline("18:42","Checkpoint #018","32 registros · aguardando você",Ink.amber)
                    timeline("18:36","Critério atualizado","Você: priorizar sites oficiais",Ink.mint)
                    timeline("18:22","Primeira coleta","18 empresas com evidência",Ink.mint)
                    timeline("18:10","Pesquisa iniciada","Claude Code · perfil Pesquisa B2B",Ink.blue)
                    Rectangle().fill(Ink.line).frame(height:1)
                    Text("Pronto para outro agente").font(.ui(size:14,weight:.semibold))
                    Text("O próximo agente recebe um resumo verificável e acesso aos mesmos arquivos. A sessão do navegador continua na box.").font(.ui(size:12)).foregroundStyle(Ink.muted).lineSpacing(5)
                    Action(title:"Trocar agente",icon:"arrow.left.arrow.right",primary:true) { model.modal="engine" }
                }.padding(23).panel().frame(width:310)
            }
            Spacer(minLength:0)
        }.padding(30)
    }
    func memoryBlock(_ title:String,_ text:String,_ icon:String) -> some View { VStack(alignment:.leading,spacing:9) { HStack(spacing:8) { Image(systemName:icon).foregroundStyle(Ink.mint); Text(title).fontWeight(.semibold) }.font(.ui(size:12)); Text(text).font(.ui(size:12)).foregroundStyle(Ink.muted).lineSpacing(5).fixedSize(horizontal:false,vertical:true) } }
    func timeline(_ time:String,_ title:String,_ sub:String,_ color:Color) -> some View { HStack(alignment:.top,spacing:12) { VStack(spacing:7) { Circle().fill(color).frame(width:6,height:6); Rectangle().fill(Ink.line).frame(width:1,height:37) }.padding(.top,4); VStack(alignment:.leading,spacing:6) { Text(time).font(.ui(size:9,design:.monospaced)).foregroundStyle(Ink.faint); Text(title).font(.ui(size:12,weight:.medium)); Text(sub).font(.ui(size:10)).foregroundStyle(Ink.muted) } } }
}

let resultRows = [("Meridiana Logística","São Paulo","Transporte","Site oficial"),("Via Norte Transportes","Paraná","Distribuição","Site oficial"),("Porto Claro Operações","Santa Catarina","Integrada","Diretório + site"),("Nexo Armazéns","Minas Gerais","Armazenagem","Site oficial"),("Rota Sul Cargas","Rio Grande do Sul","Transporte","Site oficial"),("Horizonte Cargo","Pernambuco","Internacional","Diretório + site"),("Ponte Logística","Bahia","Distribuição","Site oficial")]
struct ResultsScreen: View {
    @ObservedObject var model: Studio
    @State var filter = ""
    var body: some View { VStack(alignment:.leading,spacing:24) {
        HStack { Heading(eyebrow:"DADOS COM ORIGEM",title:"Resultados",subtitle:"Cada registro acompanha a fonte, a data e a evidência da coleta."); Spacer(); Action(title:"Exportar",icon:"square.and.arrow.up",primary:true) { model.modal="export" } }
        HStack(spacing:34) { stat("32","registros validados"); stat("18","a pesquisar"); stat("3","fontes consultadas"); Spacer(); Tag(text:"Coleta pausada",color:Ink.amber) }.padding(20).panel()
        VStack(spacing:0) {
            HStack { Image(systemName:"magnifyingglass").foregroundStyle(Ink.faint); Group { if model.rendering { Text("Buscar nos resultados…").foregroundStyle(Ink.faint) } else { TextField("Buscar nos resultados…",text:$filter).textFieldStyle(.plain) } }.font(.ui(size:12)); Spacer(); Text("Mapa de empresas B2B").font(.ui(size:11)).foregroundStyle(Ink.muted); Image(systemName:"line.3.horizontal.decrease") }.padding(17).ruleBottom()
            HStack { Text("EMPRESA").frame(maxWidth:.infinity,alignment:.leading); Text("REGIÃO").frame(width:150,alignment:.leading); Text("SEGMENTO").frame(width:130,alignment:.leading); Text("FONTE").frame(width:150,alignment:.leading); Text("EVIDÊNCIA").frame(width:90,alignment:.trailing) }.font(.ui(size:9,weight:.semibold)).tracking(0.8).foregroundStyle(Ink.faint).padding(.horizontal,18).frame(height:42).background(Ink.base.opacity(0.4))
            ForEach(Array(resultRows.enumerated()).filter { filter.isEmpty || $0.element.0.localizedCaseInsensitiveContains(filter) },id:\.offset) { i,r in HStack { HStack(spacing:10) { Text(String(format:"%02d",i+1)).font(.ui(size:10,design:.monospaced)).foregroundStyle(Ink.faint); Text(r.0).fontWeight(.medium) }.frame(maxWidth:.infinity,alignment:.leading); Text(r.1).foregroundStyle(Ink.muted).frame(width:150,alignment:.leading); Text(r.2).foregroundStyle(Ink.muted).frame(width:130,alignment:.leading); Text(r.3).foregroundStyle(Ink.muted).frame(width:150,alignment:.leading); Button { model.modal="evidence" } label: { HStack(spacing:5) { Text("#0\(32-i)"); Image(systemName:"arrow.up.right") }.foregroundStyle(Ink.mint).frame(width:90,alignment:.trailing) }.buttonStyle(.plain) }.font(.ui(size:11)).padding(.horizontal,18).frame(height:54).ruleBottom() }
            HStack { Text("7 de 32 registros nesta prévia · empresas fictícias"); Spacer(); Text("‹   1   2   3   4   5   ›") }.font(.ui(size:10)).foregroundStyle(Ink.faint).padding(17)
        }.panel()
        HStack(spacing:8) { Image(systemName:"checkmark.seal").foregroundStyle(Ink.mint); Text("A exportação inclui URL de origem, horário da coleta e referência da evidência.").font(.ui(size:11)).foregroundStyle(Ink.muted) }
        Spacer(minLength:0)
    }.padding(30) }
    func stat(_ value:String,_ label:String) -> some View { HStack(alignment:.firstTextBaseline,spacing:8) { Text(value).font(.ui(size:27,weight:.medium,design:.rounded)); Text(label).font(.ui(size:11)).foregroundStyle(Ink.muted) } }
}
struct ActivityScreen: View {
    @ObservedObject var model: Studio
    var body: some View { VStack(alignment:.leading,spacing:25) {
        Heading(eyebrow:"SEM PERDER O FIO",title:"Atividade",subtitle:"Pedidos dos agentes, mudanças de contexto e entregas em uma única linha do tempo.")
        HStack(alignment:.top,spacing:18) { BoxMark(size:45,color:Ink.amber); VStack(alignment:.leading,spacing:10) { HStack { Text("Verificação humana").font(.ui(size:16,weight:.semibold)); Tag(text:"Aguardando você",color:Ink.amber); Spacer(); Text("Agora").font(.ui(size:10)).foregroundStyle(Ink.faint) }; Text("Mapa de empresas B2B").font(.ui(size:12,weight:.medium)); Text("Claude Code: “A página pediu uma verificação. Pausei a pesquisa com 32 registros salvos. Pode assumir a tela?”").font(.ui(size:12)).foregroundStyle(Ink.muted).lineSpacing(4); HStack { Action(title:"Abrir a box",icon:"arrow.up.right",primary:true,tint:Ink.amber) { model.go(.workspace) }; Action(title:"Responder") { model.go(.workspace); model.composer="" } } } }.padding(24).panel()
        SectionLabel(title:"Hoje",detail:"Eventos de todas as boxes")
        ForEach(Array([("18:42","Checkpoint salvo","Pesquisa B2B","32 registros e estado da tarefa preservados.","square.stack.3d.up"),("18:39","Coleta em andamento","Radar de preços","8 de 12 produtos validados em 3 fontes.","arrow.down.doc"),("16:42","Entrega concluída","Leitura de relatórios","Panorama do setor pronto para exportar.","checkmark.circle"),("16:30","Perfil preservado","Pesquisa B2B","Backup local concluído antes da pesquisa.","externaldrive")].enumerated()),id:\.offset) { _,r in HStack(spacing:18) { Text(r.0).font(.ui(size:11,design:.monospaced)).foregroundStyle(Ink.faint).frame(width:45); Image(systemName:r.4).font(.ui(size:15)).foregroundStyle(Ink.mint).frame(width:36,height:36).background(Ink.mint.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:9)); VStack(alignment:.leading,spacing:7) { HStack { Text(r.1).font(.ui(size:13,weight:.medium)); Text("· \(r.2)").font(.ui(size:11)).foregroundStyle(Ink.faint) }; Text(r.3).font(.ui(size:11)).foregroundStyle(Ink.muted) }; Spacer(); Image(systemName:"chevron.right").font(.ui(size:10)).foregroundStyle(Ink.faint) }.padding(.vertical,13).ruleBottom() }
        Spacer()
    }.padding(30) }
}
struct FilePanel: View { var body: some View { VStack(alignment:.leading,spacing:23) { SectionLabel(title:"Arquivos da pesquisa",detail:"/work") ; ForEach([("tablecells","empresas.csv","32 registros · atualizado agora"),("doc.text","contexto.md","Resumo portátil · checkpoint #018"),("folder","evidencias/","32 fontes · HTML e metadados"),("terminal","coletor.py","Script da pesquisa")],id:\.1) { x in HStack(spacing:12) { Image(systemName:x.0).foregroundStyle(Ink.mint); VStack(alignment:.leading,spacing:5) { Text(x.1).font(.ui(size:12)); Text(x.2).font(.ui(size:10)).foregroundStyle(Ink.faint) }; Spacer() }.padding(.vertical,10).ruleBottom() }; Spacer() }.padding(24).frame(maxHeight:.infinity) } }
struct NetworkPanel: View { var body: some View { VStack(alignment:.leading,spacing:20) { SectionLabel(title:"Requisições observadas",detail:"Navegador + ferramentas instrumentadas"); HStack { Tag(text:"Direto"); Text("Proxy desligado").foregroundStyle(Ink.muted); Spacer() }; ForEach(0..<6) { i in HStack { Text(i == 5 ? "403" : "200").foregroundStyle(i == 5 ? Ink.amber : Ink.mint).frame(width:35); Text("GET").foregroundStyle(Ink.faint); Text(i == 5 ? "/verify" : "/api/companies?page=\(i+1)"); Spacer(); Text("\(42+i*11) ms").foregroundStyle(Ink.faint) }.font(.ui(size:11,design:.monospaced)).padding(.vertical,10).ruleBottom() }; Text("Cobertura instrumentada. O painel não promete capturar todo o tráfego do sistema.").font(.ui(size:11)).foregroundStyle(Ink.faint).lineSpacing(4); Spacer() }.padding(24).frame(maxHeight:.infinity) } }

struct ModalLayer: View {
    @ObservedObject var model: Studio
    var body: some View { ZStack { Color.black.opacity(0.58).onTapGesture { model.modal="" }; Group { switch model.modal { case "engine": engine; case "new": SessionLauncher(model:model); case "skills": SkillPicker(model:model); case "profile": profile; case "export": export; case "evidence": evidence; case "fullscreen": full; case "motion": motion; default: search } }.padding(28).background(Ink.panel).clipShape(RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(Ink.line)).shadow(color:.black.opacity(0.45),radius:50,y:20) } }
    func modalTitle(_ title:String,_ sub:String) -> some View { VStack(alignment:.leading,spacing:10) { HStack { Text(title).font(.ui(size:23,weight:.semibold)).tracking(-0.5); Spacer(); Button { model.modal="" } label: { Image(systemName:"xmark").foregroundStyle(Ink.faint).frame(width:22,height:22) }.buttonStyle(.plain).keyboardShortcut(.cancelAction) }; Text(sub).font(.ui(size:12)).foregroundStyle(Ink.muted).lineSpacing(4) } }
    var engine: some View { VStack(alignment:.leading,spacing:23) {
        modalTitle("Trocar agente","A pesquisa e a box continuam. O próximo agente recebe o contexto salvo.")
        HStack(spacing:15) { provider(model.engine,selected:false); Image(systemName:"arrow.right").foregroundStyle(Ink.faint); provider(model.nextEngine,selected:true) }
        VStack(alignment:.leading,spacing:14) { Text("O QUE SEGUE COM A PESQUISA").font(.ui(size:9,weight:.semibold)).tracking(1.1).foregroundStyle(Ink.faint); check("Objetivo, critérios e decisões suas"); check("32 registros, arquivos e evidências"); check("Navegador, abas e sessões do perfil"); check("Checkpoint #018 e próximos passos") }.padding(18).background(Ink.base.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius:10))
        HStack(alignment:.top,spacing:9) { Image(systemName:"info.circle"); Text("Cada agente tem sua própria conversa interna. O contexto compartilhado permite retomar o trabalho; não transfere raciocínio privado nem garante respostas idênticas.").lineSpacing(4) }.font(.ui(size:11)).foregroundStyle(Ink.muted)
        HStack { Text("Pausa → checkpoint → troca → retomada").font(.ui(size:10)).foregroundStyle(Ink.faint); Spacer() }
        HStack { Action(title:"Cancelar") { model.modal="" }; Spacer(); Action(title:"Salvar contexto e trocar",icon:"arrow.left.arrow.right",primary:true) { model.switchEngine() } }
    }.frame(width:530) }
    func provider(_ name:String,selected:Bool) -> some View { HStack(spacing:11) { BrandIcon(name:name,size:30); VStack(alignment:.leading,spacing:6) { Text(name).font(.ui(size:13,weight:.semibold)); Text(selected ? "Próximo agente" : "Agente atual").font(.ui(size:10)).foregroundStyle(Ink.muted) }; Spacer(); if selected { Image(systemName:"checkmark.circle.fill").foregroundStyle(Ink.mint) } }.padding(17).frame(maxWidth:.infinity).background(selected ? Ink.mint.opacity(0.05) : Ink.raised).clipShape(RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(selected ? Ink.mint.opacity(0.4) : Ink.line)) }
    func check(_ text:String) -> some View { HStack(spacing:9) { Image(systemName:"checkmark").foregroundStyle(Ink.mint); Text(text) }.font(.ui(size:12)) }
    func field(_ label:String,_ value:String,_ sub:String,_ icon:String) -> some View { VStack(alignment:.leading,spacing:10) { Text(label).font(.ui(size:9,weight:.semibold)).tracking(1).foregroundStyle(Ink.faint); HStack { Image(systemName:icon).foregroundStyle(Ink.mint); Text(value).fontWeight(.medium); Spacer(); Image(systemName:"chevron.down").font(.ui(size:9)).foregroundStyle(Ink.faint) }; Text(sub).font(.ui(size:10)).foregroundStyle(Ink.faint) }.font(.ui(size:12)).padding(15).frame(maxWidth:.infinity).background(Ink.base.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius:10)) }
    var profile: some View { VStack(alignment:.leading,spacing:21) { modalTitle("Novo perfil","Crie um perfil persistente e entre nos sites que fazem parte do seu trabalho."); field("NOME","Pesquisa de mercado","Você pode renomear depois.","person.crop.square"); check("Navegador e arquivos preservados"); check("Login feito por você, no navegador da box"); check("Backup separado da imagem do ambiente"); Text("A sessão pode expirar. O Racky avisa quando for necessário entrar novamente.").font(.ui(size:12)).foregroundStyle(Ink.muted).lineSpacing(4); HStack { Action(title:"Cancelar") { model.modal="" }; Spacer(); Action(title:"Criar e abrir navegador",primary:true) { model.modal=""; model.go(.workspace); model.takeControl() } } }.frame(width:480) }
    var export: some View { VStack(alignment:.leading,spacing:22) { modalTitle("Leve os dados com as fontes.","Prévia da exportação de Mapa de empresas B2B."); HStack(spacing:12) { field("FORMATO","CSV","Compatível com Excel e Sheets","tablecells"); field("REGISTROS","32 validados","Incluir URL e data da coleta","checkmark.seal") }; check("Referências de evidência em cada linha"); check("Manifesto da pesquisa e critérios usados"); HStack { Action(title:"Cancelar") { model.modal="" }; Spacer(); Action(title:"Exportar exemplo",icon:"square.and.arrow.up",primary:true) { model.modal=""; model.alert("Design: a exportação real será implementada com os dados da pesquisa.") } } }.frame(width:480) }
    var evidence: some View { VStack(alignment:.leading,spacing:20) { modalTitle("Evidência #032","Meridiana Logística · registro ilustrativo"); field("FONTE","meridiana.example/sobre","Coletado em 15 out 2026, 18:42","link"); Text("“Operação de transporte e distribuição com sede em São Paulo e atendimento nacional.”").font(.ui(size:15)).lineSpacing(6).padding(20).background(Ink.base).clipShape(RoundedRectangle(cornerRadius:10)); Text("Trecho fictício para demonstrar a experiência. No produto, cada campo aponta para a captura ou resposta original.").font(.ui(size:11)).foregroundStyle(Ink.muted).lineSpacing(4); Action(title:"Fechar",primary:true) { model.modal="" } }.frame(width:480) }
    var full: some View { VStack(spacing:15) { modalTitle("Pesquisa B2B · desktop","Você acompanha a mesma sessão do agente."); DesktopView(human:model.human,waiting:model.waiting).frame(width:900,height:570); HStack { Tag(text:model.human ? "Você no controle" : "Observando",color:model.human ? Ink.amber : Ink.mint); Spacer(); Action(title:model.human ? "Devolver ao agente" : "Assumir controle",primary:true) { model.human ? model.giveBack() : model.takeControl() } } }.frame(width:900) }
    var motion: some View { VStack(alignment:.leading,spacing:20) { modalTitle("Motion","Estudo de movimento para o estado de trabalho de uma box."); MotionAssetView().frame(width:480,height:280).background(Ink.base).clipShape(RoundedRectangle(cornerRadius:12)); Text("Loop de 4 segundos, renderizado frame a frame e reproduzido com AVPlayer. Com Reduzir Movimento, aparece uma imagem estática. As transições da interface são nativas.").font(.ui(size:12)).foregroundStyle(Ink.muted).lineSpacing(4); Action(title:"Fechar",primary:true) { model.modal="" } }.frame(width:480) }
    var search: some View { VStack(alignment:.leading,spacing:20) { modalTitle("Ir para…","Navegue pelo protótipo do Racky."); ForEach(Screen.allCases,id:\.rawValue) { s in Button { model.go(s) } label: { HStack { Image(systemName:s.icon).frame(width:25).foregroundStyle(Ink.mint); Text(s.rawValue); Spacer(); Image(systemName:"arrow.up.left").foregroundStyle(Ink.faint) }.padding(9) }.buttonStyle(.plain) } }.frame(width:400) }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    let model=Studio()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let host=NSHostingView(rootView:RootView(model:model))
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:1440,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        w.title="Racky — Design Preview"; w.titleVisibility = .hidden; w.titlebarAppearsTransparent=true; w.backgroundColor=NSColor(Ink.base); w.contentView=host; w.minSize=NSSize(width:1200,height:800)
        w.standardWindowButton(.closeButton)?.isHidden=true; w.standardWindowButton(.miniaturizeButton)?.isHidden=true; w.standardWindowButton(.zoomButton)?.isHidden=true
        w.center(); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); window=w
        let menu=NSMenu(); let item=NSMenuItem(); menu.addItem(item); let sub=NSMenu(); sub.addItem(withTitle:"Quit Racky",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); item.submenu=sub; NSApp.mainMenu=menu
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
}

@main struct RackyMain {
    @MainActor static func main() {
        for style in ["Regular","Medium","SemiBold"] {
            let fontURL = Bundle.main.url(forResource:"Manrope-"+style,withExtension:"ttf") ?? URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fonts/Manrope-"+style+".ttf")
            CTFontManagerRegisterFontsForURL(fontURL as CFURL,.process,nil)
        }
        let app=NSApplication.shared
        if let idx=CommandLine.arguments.firstIndex(of:"--export"),CommandLine.arguments.count>idx+1 {
            let path=CommandLine.arguments[idx+1]; try? FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true)
            let cases:[(String,Screen,String,Bool)] = [("01-overview",.overview,"",false),("02-workspace",.workspace,"",false),("03-human-control",.workspace,"",true),("04-switch-agent",.workspace,"engine",false),("05-profiles",.profiles,"",false),("06-memory",.memory,"",false),("07-results",.results,"",false),("08-connections",.settings,"",false),("09-new-research",.overview,"new",false),("10-attention",.activity,"",false),("11-evidence",.results,"evidence",false),("12-new-profile",.profiles,"profile",false),("13-agents",.agents,"",false),("14-agent-memory",.agentDetail,"",false),("15-hover-preview",.overview,"",false),("16-agent-history",.agentDetail,"",false)]
            for (name,screen,modal,human) in cases {
                let m=Studio(); m.rendering=true; m.screen=screen; m.modal=modal; m.human=human; m.paused=true; m.waiting = !human
                if name == "15-hover-preview" { m.previewAgent="Radar" }; if name == "16-agent-history" { m.agentTab="Histórico" }
                let renderer=ImageRenderer(content:RootView(model:m).frame(width:1440,height:900).environment(\.colorScheme,.dark)); renderer.scale=2
                if let image=renderer.nsImage,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let data=bitmap.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:path).appendingPathComponent(name+".png")); print("Rendered \(name)") } else { fputs("Render failed: \(name)\n",stderr) }
            }
            return
        }
        let delegate=AppDelegate(); app.setActivationPolicy(.regular); app.delegate=delegate; withExtendedLifetime(delegate) { app.run() }
    }
}
