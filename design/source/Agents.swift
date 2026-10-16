import SwiftUI

extension Font {
    // One family throughout the UI. The design argument is accepted for legacy call sites.
    static func ui(size:CGFloat,weight:Font.Weight = .regular,design:Font.Design = .default) -> Font {
        .system(size:size,weight:weight,design:design)
    }
}
struct AgentAvatar: View {
    let name:String
    var size:CGFloat=38
    var body: some View {
        Text(String(name.prefix(1))).font(.ui(size:size*0.38,weight:.semibold))
            .foregroundStyle(name == "Atlas" ? Ink.mint : (name == "Radar" ? Ink.amber : Ink.blue))
            .frame(width:size,height:size).background(name == "Atlas" ? Color(hex:0x2C313C) : (name == "Radar" ? Color(hex:0x373029) : Color(hex:0x2A3237)))
            .clipShape(RoundedRectangle(cornerRadius:size*0.28))
    }
}
struct LiveSurface: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var kind=0
    var frozen=false
    var body: some View {
        if frozen || reduceMotion { content(1.6) } else {
            TimelineView(.animation(minimumInterval:1.0/30.0)) { timeline in content(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:8)) }
        }
    }
    func content(_ t:Double) -> some View {
        GeometryReader { g in
            let phase=t/8
            ZStack(alignment:.topLeading) {
                Color(hex:0xECEDEA)
                VStack(alignment:.leading,spacing:0) {
                    HStack(spacing:5) { ForEach(0..<3) { _ in Circle().fill(.black.opacity(0.15)).frame(width:5,height:5) }; Spacer(); Image(systemName:"lock"); Text(kind == 0 ? "atlas.example" : "catalogo.example"); Spacer() }.font(.ui(size:8)).foregroundStyle(Color.black.opacity(0.45)).padding(12).background(Color(hex:0xE0E1DF))
                    HStack { Text(kind == 0 ? "Empresas" : "Monitores").font(.ui(size:19,weight:.semibold)); Spacer(); Image(systemName:"magnifyingglass").font(.ui(size:12)) }.padding(.horizontal,22).padding(.top,20).padding(.bottom,14)
                    ForEach(0..<4) { row in
                        HStack(spacing:11) {
                            RoundedRectangle(cornerRadius:5).fill(Color.black.opacity(0.05)).frame(width:28,height:28).overlay(Text(kind == 0 ? ["M","V","P","N"][row] : "▱").font(.ui(size:12,weight:.medium)))
                            VStack(alignment:.leading,spacing:4) { Text(kind == 0 ? ["Meridiana","Via Norte","Porto Claro","Nexo"][row] : ["Studio 27”","Display 32”","Pro 24”","Wide 34”"][row]).font(.ui(size:10,weight:.medium)); RoundedRectangle(cornerRadius:2).fill(.black.opacity(0.06)).frame(width:88,height:3) }
                            Spacer(); Image(systemName: row < Int(phase*5) ? "checkmark" : "arrow.up.right").font(.ui(size:9)).foregroundStyle(Color.black.opacity(0.4))
                        }.padding(.horizontal,10).frame(height:47).background(row == Int(phase*4) ? Color(hex:0xDCE3E1) : .clear).clipShape(RoundedRectangle(cornerRadius:6)).padding(.horizontal,12)
                    }
                }.foregroundStyle(Color(hex:0x33383A)).offset(y: -max(0,t-4)*3)
                Image(systemName:"cursorarrow").font(.ui(size:17,weight:.semibold)).foregroundStyle(Color(hex:0x30333A)).offset(x:g.size.width*(0.46+0.24*sin(phase*6.28)),y:85+CGFloat(phase)*110)
            }.clipped()
        }
    }
}
struct LiveCard: View {
    @ObservedObject var model: Studio
    let name:String
    let topic:String
    let kind:Int
    @State private var hovered=false
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:10) { AgentAvatar(name:name,size:28); Text(name).font(.ui(size:13,weight:.semibold)); Spacer(); Circle().fill(kind == 0 ? Ink.amber : Ink.mint).frame(width:5,height:5); Text(model.liveMode == "Histórico" ? "Replay" : (kind == 0 ? "Precisa de você" : "Ao vivo")).font(.ui(size:10)).foregroundStyle(Ink.muted) }.padding(15)
            LiveSurface(kind:kind,frozen:model.rendering).frame(height:225).clipShape(RoundedRectangle(cornerRadius:6)).padding(.horizontal,9)
                .overlay(alignment:.bottomTrailing) { if hovered { Button { model.selectedAgent=name;model.go(.workspace) } label: { Image(systemName:"arrow.up.right").font(.ui(size:13)).frame(width:33,height:33).background(Ink.base).clipShape(Circle()) }.buttonStyle(.plain).padding(21).transition(.opacity) } }
            HStack { VStack(alignment:.leading,spacing:5) { Text(topic).font(.ui(size:12,weight:.medium)); Text(kind == 0 ? "32 / 50 · Box B2B" : "8 / 12 · Box Mercado").font(.ui(size:10)).foregroundStyle(Ink.faint) }; Spacer(); Button { model.openAgent(name) } label: { Image(systemName:"ellipsis").foregroundStyle(Ink.muted) }.buttonStyle(.plain) }.padding(15)
            HStack(spacing:3) { ForEach(0..<24) { i in Capsule().fill(i < (kind == 0 ? 15 : 19) ? Ink.mint.opacity(0.45) : Ink.line).frame(height:3) } }.padding(.horizontal,15).padding(.bottom,15)
        }.panel(12).onHover { hovered=$0 }.animation(.easeInOut(duration:0.18),value:hovered)
    }
}
struct AgentPeek: View {
    @ObservedObject var model:Studio
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:9) { AgentAvatar(name:model.previewAgent,size:26); Text(model.previewAgent).font(.ui(size:12,weight:.semibold)); Spacer(); Text(model.previewAgent == "Lumen" ? "Última atividade" : "Ao vivo").font(.ui(size:10)).foregroundStyle(Ink.muted); Button { model.previewAgent="" } label: { Image(systemName:"xmark").font(.ui(size:10)) }.buttonStyle(.plain) }
            LiveSurface(kind:model.previewAgent == "Radar" ? 1 : 0,frozen:model.rendering).frame(height:185).clipShape(RoundedRectangle(cornerRadius:6))
            HStack { Text(model.previewAgent == "Radar" ? "Comparando preços · Box Mercado" : "Validando empresas · Box B2B").font(.ui(size:11)).foregroundStyle(Ink.muted); Spacer() }
            HStack { Button("Abrir conversa") { model.go(.workspace) }; Spacer(); Button("Ver agente") { model.openAgent(model.previewAgent) } }.buttonStyle(.plain).font(.ui(size:11))
        }.padding(14).background(Ink.panel).clipShape(RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(Color.white.opacity(0.15)))
    }
}
struct AgentLibrary: View {
    @ObservedObject var model:Studio
    let names=["Atlas","Radar","Lumen","Íris","Nexo","Prisma"]
    var body:some View {
        VStack(alignment:.leading,spacing:25) {
            HStack { Text("Agentes").font(.ui(size:23,weight:.semibold)); Spacer(); Action(title:"Importar",icon:"square.and.arrow.down") { model.alert("Prévia: escolha definições existentes para importar. Seus agentes originais serão preservados.") }; Action(title:"Novo agente",icon:"plus",primary:true) { model.modal="new" } }
            HStack(spacing:8) { Image(systemName:"magnifyingglass"); Text("Buscar agente"); Spacer(); Text("6 agentes") }.font(.ui(size:12)).foregroundStyle(Ink.faint).padding(13).background(Ink.side).clipShape(RoundedRectangle(cornerRadius:8))
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:18) {
                ForEach(Array(names.enumerated()),id:\.element) { i,name in
                    Button { model.openAgent(name) } label: {
                        VStack(alignment:.leading,spacing:22) {
                            HStack { AgentAvatar(name:name,size:43); Spacer(); Image(systemName:"ellipsis").foregroundStyle(Ink.faint) }
                            VStack(alignment:.leading,spacing:7) { Text(name).font(.ui(size:17,weight:.semibold)); Text(["Pesquisa de empresas","Preços e concorrência","Leitura de relatórios","Fontes e evidências","Organização de dados","Revisão de resultados"][i]).font(.ui(size:12)).foregroundStyle(Ink.muted) }
                            HStack { Text("\([12,8,5,3,7,4][i]) pesquisas"); Spacer(); Text("\([3,2,1,2,3,1][i]) boxes") }.font(.ui(size:11)).foregroundStyle(Ink.faint)
                            HStack { Image(systemName:"square.stack.3d.up"); Text("\([24,12,8,6,15,7][i]) memórias"); Spacer(); Text(i < 2 ? "Em uso" : "Disponível").foregroundStyle(i < 2 ? Ink.mint : Ink.muted) }.font(.ui(size:11)).padding(.top,12).overlay(alignment:.top) { Rectangle().fill(Ink.line).frame(height:1) }
                        }.padding(23).panel(12)
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
        }.padding(30)
    }
}
struct AgentDetail: View {
    @ObservedObject var model:Studio
    @State private var memories:Set<Int>=[0,1,2]
    var body:some View {
        VStack(alignment:.leading,spacing:26) {
            HStack(spacing:14) { Button { model.go(.agents) } label: { Image(systemName:"chevron.left").foregroundStyle(Ink.muted) }.buttonStyle(.plain); AgentAvatar(name:model.selectedAgent,size:42); Text(model.selectedAgent).font(.ui(size:23,weight:.semibold)); Spacer(); Action(title:"Usar agente",icon:"play",primary:true) { model.modal="new" } }
            HStack(spacing:24) { ForEach(["Memória","Histórico","Boxes","Skills"],id:\.self) { tab in Button { withAnimation(.easeInOut(duration:0.2)) { model.agentTab=tab } } label: { Text(tab).font(.ui(size:13,weight:model.agentTab == tab ? .semibold : .regular)).foregroundStyle(model.agentTab == tab ? Ink.text : Ink.faint).padding(.bottom,12).overlay(alignment:.bottom) { if model.agentTab == tab { Rectangle().fill(Ink.mint).frame(height:2) } } }.buttonStyle(.plain) }; Spacer(); Text("12 pesquisas · 3 boxes").font(.ui(size:11)).foregroundStyle(Ink.faint) }.ruleBottom()
            if model.agentTab == "Histórico" { history } else if model.agentTab == "Boxes" { boxes } else if model.agentTab == "Skills" { VStack(spacing:15) { ForEach(["Coleta","Validação","Navegação"],id:\.self) { name in HStack { Image(systemName:"doc.text");Text(name);Spacer();Text("Local").foregroundStyle(Ink.faint) }.font(.ui(size:13)).padding(22).panel(10) } } } else { memory }
            Spacer(minLength:0)
        }.padding(30)
    }
    var memory:some View {
        HStack(alignment:.top,spacing:24) {
            VStack(alignment:.leading,spacing:20) {
                HStack { Text("AI memory").font(.ui(size:15,weight:.semibold)); Spacer(); Text("24 memórias").font(.ui(size:11)).foregroundStyle(Ink.faint) }
                ForEach(0..<3) { i in
                    Button { if memories.contains(i) { memories.remove(i) } else { memories.insert(i) } } label: {
                        HStack(alignment:.top,spacing:13) { Image(systemName:memories.contains(i) ? "checkmark.square.fill" : "square").foregroundStyle(memories.contains(i) ? Ink.mint : Ink.faint); VStack(alignment:.leading,spacing:8) { Text(["Priorizar fontes oficiais","Manter URL e data em cada registro","Deduplicar pelo domínio da empresa"][i]).font(.ui(size:13,weight:.medium)); Text(["Preferência sua · 6 pesquisas","Padrão de coleta · 4 pesquisas","Box B2B · atualizado hoje"][i]).font(.ui(size:11)).foregroundStyle(Ink.faint) }; Spacer(); Image(systemName:"ellipsis").foregroundStyle(Ink.faint) }.padding(20).panel(10)
                    }.buttonStyle(.plain)
                }
                HStack { Text("Contextos").font(.ui(size:14,weight:.semibold)); Spacer() }.padding(.top,8)
                HStack(spacing:10) { Tag(text:"Logística no Brasil",color:Ink.muted,dot:false); Tag(text:"Fornecedores",color:Ink.muted,dot:false); Tag(text:"Sites oficiais",color:Ink.muted,dot:false) }
                Text("\(memories.count) selecionadas para a próxima execução").font(.ui(size:11)).foregroundStyle(Ink.faint)
            }.frame(maxWidth:.infinity)
            VStack(alignment:.leading,spacing:20) {
                Text("Retomar trabalho").font(.ui(size:14,weight:.semibold))
                LiveSurface(frozen:model.rendering).frame(height:155).clipShape(RoundedRectangle(cornerRadius:6))
                Text("Empresas de logística").font(.ui(size:13,weight:.medium))
                HStack { Text("Box B2B"); Spacer(); Text("32 / 50") }.font(.ui(size:11)).foregroundStyle(Ink.muted)
                HStack { BrandIcon(name:"Claude Code",size:18); Text("Claude Code"); Spacer(); Button { model.modal="engine" } label: { Image(systemName:"arrow.left.arrow.right") }.buttonStyle(.plain) }.font(.ui(size:11)).foregroundStyle(Ink.muted)
                Action(title:"Continuar",icon:"play",primary:true) { model.go(.workspace) }
            }.padding(20).panel(12).frame(width:280)
        }
    }
    var history:some View {
        VStack(spacing:16) {
            ForEach(0..<3) { i in HStack(spacing:22) {
                LiveSurface(kind:i == 1 ? 1 : 0,frozen:true).frame(width:210,height:130).clipShape(RoundedRectangle(cornerRadius:7))
                VStack(alignment:.leading,spacing:10) { Text(["Empresas de logística","Fornecedores do Sudeste","Mapeamento de distribuidores"][i]).font(.ui(size:14,weight:.semibold)); Text(["Box B2B · Claude Code → Codex","Box Mercado · Codex","Box Pesquisa · Claude Code"][i]).font(.ui(size:12)).foregroundStyle(Ink.muted); HStack(spacing:13) { Text(["32 registros","86 registros","42 registros"][i]); Text(["3 memórias usadas","5 memórias usadas","2 memórias usadas"][i]) }.font(.ui(size:11)).foregroundStyle(Ink.faint) }; Spacer(); VStack(alignment:.trailing,spacing:14) { Text(["Hoje","Ontem","12 out"][i]).font(.ui(size:11)).foregroundStyle(Ink.faint); Action(title:i == 0 ? "Continuar" : "Rever",icon:i == 0 ? "play" : "clock") { model.go(.workspace) } }
            }.padding(17).panel(10) }
        }
    }
    var boxes:some View {
        VStack(spacing:16) { ForEach(["B2B","Mercado","Pesquisa"],id:\.self) { name in HStack(spacing:15) { Image(systemName:"desktopcomputer").font(.ui(size:23)).foregroundStyle(Ink.muted); VStack(alignment:.leading,spacing:7) { Text("Box \(name)").font(.ui(size:14,weight:.medium)); Text(name == "B2B" ? "10 sites · usada hoje" : "Perfil preservado · última sessão salva").font(.ui(size:11)).foregroundStyle(Ink.faint) }; Spacer(); Action(title:"Abrir") { model.go(.profiles) } }.padding(22).panel(10) } }
    }
}


/// Original third-party brand assets. Provenance: assets/brands/sources.json.
@MainActor enum BrandAssets {
    static let files:[String:String] = ["Claude Code":"claude", "Codex":"codex", "OpenCode":"opencode", "Docker":"docker", "LinkedIn":"linkedin", "X / Twitter":"x", "Google":"google", "Crunchbase":"crunchbase"]
    static let images:[String:NSImage] = {
        var result:[String:NSImage]=[:]
        for file in Set(files.values) {
            let url=Bundle.main.url(forResource:file,withExtension:"png",subdirectory:"Brands") ?? URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets/brands/"+file+".png")
            result[file]=NSImage(contentsOf:url)
        }
        return result
    }()
}
struct BrandIcon:View {
    var name:String
    var size:CGFloat=20
    var body:some View {
        Group {
            if let file=BrandAssets.files[name],let image=BrandAssets.images[file] { Image(nsImage:image).resizable().scaledToFit().padding(name == "Codex" ? size * 0.09 : 0) }
            else { Image(systemName:name.hasPrefix("Outros 6") ? "plus" : "terminal").resizable().scaledToFit().foregroundStyle(Ink.muted).padding(2) }
        }.frame(width:size,height:size).accessibilityHidden(true)
    }
}
