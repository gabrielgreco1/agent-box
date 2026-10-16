import SwiftUI
import AppKit

/// All terminal content is illustrative. Production uses a PTY and the original CLI TUI.
struct TerminalWorkspace: View {
    @ObservedObject var model:Studio
    @State private var chosenModel="Padrão"
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:0) { tab(model.selectedAgent+" · "+model.engine,"Agente"); tab("zsh","Shell"); Button { model.modal="new" } label: { Image(systemName:"plus").frame(width:40,height:45) }.buttonStyle(.plain); Spacer(); Image(systemName:"rectangle.split.2x1").foregroundStyle(Ink.faint).padding(.trailing,20) }.background(Ink.side).ruleBottom()
            HStack(spacing:15) {
                if model.terminal == "Shell" { Text("zsh · Shell local").foregroundStyle(Ink.muted); Button("Iniciar agente") { model.modal="new" }.buttonStyle(.plain) } else {
                if model.rendering { HStack(spacing:8) { BrandIcon(name:model.engine,size:18); Text(model.engine); Image(systemName:"chevron.down") }.frame(width:125); HStack { Text(chosenModel); Image(systemName:"chevron.down") }.frame(width:90) } else {
                Menu { ForEach(["Claude Code","Codex","OpenCode","Outro CLI"],id:\.self) { name in Button(name) { if name == "Outro CLI" { model.alert("Clientes configuráveis entram no plano de implementação.") } else if name != model.engine { model.nextEngine=name; model.modal="engine" } } } } label: { HStack(spacing:7) { BrandIcon(name:model.engine,size:18);Text(model.engine) } }.menuStyle(.borderlessButton).frame(width:125)
                Menu { ForEach((model.engine == "OpenCode" ? ["Padrão"] : model.engine == "Codex" ? ["Padrão","GPT · rápido","GPT · avançado"] : ["Padrão","Sonnet","Opus"]),id:\.self) { name in Button(name) { chosenModel=name; model.alert("A troca de modelo ainda não está conectada ao CLI.") } } } label: { Text(chosenModel) }.menuStyle(.borderlessButton).frame(width:90)
                }
                Divider().frame(height:15)
                Button { model.openAgent(model.selectedAgent) } label: { Label(model.selectedAgent,systemImage:"person.crop.circle") }.buttonStyle(.plain)
                Button { model.modal="skills" } label: { Text("\(model.skills.count) skills"); Image(systemName:"chevron.down").font(.ui(size:8)) }.buttonStyle(.plain)
                }
                Spacer(); Text(model.location == "Worktree" ? "Worktree" : (model.location == "Avulso" ? "Avulso" : "Sem worktree")).foregroundStyle(Ink.faint); Text(model.attachedBox ? "Box B2B" : "Sem desktop").foregroundStyle(Ink.muted)
            }.font(.ui(size:11)).padding(.horizontal,20).frame(height:45).ruleBottom()
            HStack(spacing:0) {
                cli.frame(maxWidth:.infinity,maxHeight:.infinity)
                if model.attachedBox {
                Rectangle().fill(Ink.line).frame(width:1)
                VStack(spacing:0) {
                    HStack { Text("Desktop").font(.ui(size:12,weight:.semibold)); Spacer(); Circle().fill(Ink.mint).frame(width:5,height:5); Text("Ao vivo").font(.ui(size:10)).foregroundStyle(Ink.muted); Button { model.modal="fullscreen" } label: { Image(systemName:"arrow.up.left.and.arrow.down.right") }.buttonStyle(.plain) }.padding(.horizontal,18).frame(height:44).ruleBottom()
                    if model.waiting || model.human { HStack { Image(systemName:model.human ? "cursorarrow" : "bell.badge"); Text(model.human ? "Você no controle" : "Ação necessária"); Spacer(); Button(model.human ? "Devolver" : "Assumir") { model.human ? model.giveBack() : model.takeControl() }.buttonStyle(.plain).fontWeight(.semibold) }.font(.ui(size:11)).foregroundStyle(Ink.amber).padding(14).background(Ink.amber.opacity(0.06)) }
                    DesktopView(human:model.human,waiting:model.waiting).padding(14).frame(maxHeight:.infinity).background(Color(hex:0x1B1D21))
                    HStack { Text("Box B2B"); Spacer(); Text(model.human ? "Agente pausado" : "Observando"); Button { model.human ? model.giveBack() : model.takeControl() } label: { Image(systemName:"cursorarrow") }.buttonStyle(.plain) }.font(.ui(size:10)).foregroundStyle(Ink.faint).padding(15).ruleBottom()
                }.frame(maxWidth:.infinity)
                }
            }
        }.onChange(of:model.engine) { chosenModel="Padrão" }
    }
    func tab(_ label:String,_ value:String) -> some View { Button { model.terminal=value } label: { HStack(spacing:8) { BrandIcon(name:value == "Shell" ? "Shell" : model.engine,size:18); Text(label).lineLimit(1); if model.waiting && value == "Agente" { Circle().fill(Ink.amber).frame(width:5,height:5) }; Image(systemName:"xmark").font(.ui(size:8)).foregroundStyle(Ink.faint) }.font(.ui(size:11)).padding(.horizontal,17).frame(height:45).background(model.terminal == value ? Ink.base : .clear).overlay(alignment:.bottom) { if model.terminal == value { Rectangle().fill(Ink.mint).frame(height:1) } } }.buttonStyle(.plain) }
    var cli:some View {
        VStack(alignment:.leading,spacing:20) {
            if model.terminal == "Shell" {
                Text("zsh").font(.system(size:13,weight:.medium,design:.monospaced))
                Text("\(model.location == "Avulso" ? "~" : (model.location == "Worktree" ? "~/Pesquisas/worktrees/logistica" : "~/Pesquisas/logistica"))\n\n$ ▌").font(.system(size:12,design:.monospaced)).foregroundStyle(Ink.muted).lineSpacing(8)
            } else {
                HStack { BrandIcon(name:model.engine,size:27); Text(model.engine).font(.system(size:18,weight:.semibold,design:.monospaced)); Spacer() }
                Text("\(chosenModel) · ~/Pesquisas/logistica").font(.system(size:11,design:.monospaced)).foregroundStyle(Ink.faint)
                Rectangle().fill(Ink.line).frame(height:1)
                Text("❯ Encontre 50 empresas de logística no Brasil.\n  Salve nome, site, região e fonte.").font(.system(size:12,design:.monospaced)).lineSpacing(7)
                Text("● 32 empresas validadas.\n\n  ✓ fontes consultadas\n  ✓ empresas.csv atualizado\n  ✓ contexto salvo").font(.system(size:12,design:.monospaced)).foregroundStyle(Ink.muted).lineSpacing(8)
                if model.waiting || model.human {
                    VStack(alignment:.leading,spacing:10) { Text("! Ação necessária").foregroundStyle(Ink.amber); Text(model.human ? "  Você está no controle. Vou aguardar." : "  O site pediu uma verificação.\n  Assuma a tela para continuar.").foregroundStyle(Ink.muted) }.font(.system(size:12,design:.monospaced)).lineSpacing(7).padding(.vertical,10)
                } else { Text("● Conferindo a página.\n  Continuando do registro 33…").font(.system(size:12,design:.monospaced)).foregroundStyle(Ink.muted).lineSpacing(8) }
                if let message=model.messages.last { Text("❯ "+message).font(.system(size:12,design:.monospaced)) }
            }
            Spacer(minLength:20)
            HStack { Text("❯").foregroundStyle(Ink.muted); if model.rendering { Text("Escreva no terminal…").foregroundStyle(Ink.faint) } else { TextField("Escreva no terminal…",text:$model.composer).textFieldStyle(.plain).onSubmit { if !model.composer.isEmpty { model.messages.append(model.composer);model.composer="" } } } }.font(.system(size:12,design:.monospaced)).padding(.vertical,14).overlay(alignment:.top) { Rectangle().fill(Ink.line).frame(height:1) }
            HStack { Text("Terminal não conectado"); Spacer(); Text("") }.font(.ui(size:10)).foregroundStyle(Ink.faint)
        }.padding(24).background(Ink.base)
    }
}
struct SessionLauncher: View {
    @ObservedObject var model:Studio
    @State private var cli="Claude Code"
    @State private var location="Pasta"
    @State private var box=true
    var body:some View {
        VStack(alignment:.leading,spacing:23) {
            HStack { Text("Nova sessão").font(.ui(size:22,weight:.semibold)); Spacer(); Button { model.modal="" } label: { Image(systemName:"xmark") }.buttonStyle(.plain).keyboardShortcut(.cancelAction) }
            HStack(spacing:10) { ForEach(["Claude Code","Codex","OpenCode","Shell"],id:\.self) { item in Button { cli=item } label: { VStack(spacing:10) { BrandIcon(name:item,size:32); Text(item).font(.ui(size:12)) }.frame(maxWidth:.infinity).padding(.vertical,22).background(cli == item ? Ink.raised : Ink.base).clipShape(RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(cli == item ? Ink.mint.opacity(0.5) : Ink.line)) }.buttonStyle(.plain) } }
            HStack { Text("Local").foregroundStyle(Ink.muted); Spacer(); Group { if model.rendering { HStack { Text("Pasta").padding(7).background(Ink.raised).clipShape(RoundedRectangle(cornerRadius:5)); Text("Worktree").padding(7); Text("Avulso").padding(7) }.padding(3).background(Ink.base).clipShape(RoundedRectangle(cornerRadius:7)) } else { Picker("",selection:$location) { ForEach(["Pasta","Worktree","Avulso"],id:\.self) { Text($0) } }.pickerStyle(.segmented) } }.frame(width:310) }.font(.ui(size:12))
            HStack { Image(systemName:location == "Worktree" ? "arrow.triangle.branch" : "folder").foregroundStyle(Ink.faint); Text(location == "Worktree" ? "pesquisa / nova branch" : (location == "Avulso" ? "Sem projeto" : "~/Pesquisas/logistica")); Spacer(); Image(systemName:"chevron.down").foregroundStyle(Ink.faint) }.font(.ui(size:12)).padding(15).background(Ink.base).clipShape(RoundedRectangle(cornerRadius:8))
            if cli != "Shell" { HStack { Text("Agente").foregroundStyle(Ink.muted); Spacer(); if model.rendering { Text(model.selectedAgent); Image(systemName:"chevron.down") } else { Menu(model.selectedAgent) { ForEach(["Atlas","Radar","Lumen","Íris","Nexo","Prisma"],id:\.self) { name in Button(name) { model.selectedAgent=name } } }.frame(width:150) } }.font(.ui(size:12)); HStack { Text("Skills").foregroundStyle(Ink.muted); Spacer(); if model.rendering { Text("Coleta · Validação"); Image(systemName:"chevron.down") } else { Menu(model.skills.sorted().joined(separator:" · ")) { ForEach(["Coleta","Validação","Navegação","Extração de tabelas"],id:\.self) { name in Button { if model.skills.contains(name) { model.skills.remove(name) } else { model.skills.insert(name) } } label: { Label(name,systemImage:model.skills.contains(name) ? "checkmark" : "plus") } } }.frame(width:230) } }.font(.ui(size:12)) }
            Group { if model.rendering { HStack { BrandIcon(name:"Docker",size:24); Text("Anexar desktop Docker"); Spacer(); Image(systemName:"switch.2").foregroundStyle(Ink.mint) } } else { Toggle(isOn:$box) { HStack { BrandIcon(name:"Docker",size:24); Text("Anexar desktop Docker") } }.toggleStyle(.switch) } }.font(.ui(size:12))
            HStack { Text(cli == "Shell" ? "Terminal sem agente" : "Usa o login existente do CLI").font(.ui(size:11)).foregroundStyle(Ink.faint); Spacer(); Action(title:"Abrir sessão",icon:"arrow.up.right",primary:true) { if cli != "Shell" { model.engine=cli }; model.terminal=cli == "Shell" ? "Shell" : "Agente";model.location=location;model.attachedBox=box;model.go(.workspace);model.alert("O terminal ainda não está conectado a um processo.") } }
        }.frame(width:550)
    }
}
struct SkillPicker:View {
    @ObservedObject var model:Studio
    var body:some View { VStack(alignment:.leading,spacing:22) { HStack { Text("Skills da sessão").font(.ui(size:22,weight:.semibold)); Spacer(); Button { model.modal="" } label: { Image(systemName:"xmark") }.buttonStyle(.plain) }; ForEach(["Coleta","Validação","Navegação","Extração de tabelas"],id:\.self) { item in Button { if model.skills.contains(item) { model.skills.remove(item) } else { model.skills.insert(item) } } label: { HStack { Image(systemName:model.skills.contains(item) ? "checkmark.square.fill" : "square"); Text(item); Spacer(); Text("Local").foregroundStyle(Ink.faint) }.font(.ui(size:13)).padding(14).panel(8) }.buttonStyle(.plain) }; Text("A ativação segue as capacidades do CLI selecionado.").font(.ui(size:11)).foregroundStyle(Ink.faint); Action(title:"Concluir",primary:true) { model.modal="" } }.frame(width:440) }
}
struct RuntimeSettings: View {
    @ObservedObject var model:Studio
    var body:some View { VStack(alignment:.leading,spacing:25) {
        HStack { Text("Clientes locais").font(.ui(size:23,weight:.semibold)); Spacer(); Action(title:"Verificar novamente",icon:"arrow.clockwise") { model.alert("A verificação de clientes ainda não está implementada.") } }
        ForEach(["Claude Code","Codex","OpenCode","Outros CLIs"],id:\.self) { name in HStack(spacing:17) { BrandIcon(name:name,size:36).frame(width:40); VStack(alignment:.leading,spacing:8) { Text(name).font(.ui(size:15,weight:.semibold)); Text(name == "Outros CLIs" ? "Executável e argumentos configuráveis" : "Login existente no terminal").font(.ui(size:12)).foregroundStyle(Ink.faint) }; Spacer(); Text(name == "Outros CLIs" ? "Adicionar" : "Não verificado").font(.ui(size:11)).foregroundStyle(Ink.muted); Button { model.modal="new" } label: { Image(systemName:"arrow.up.right") }.buttonStyle(.plain) }.padding(23).panel(10) }
        HStack { Text("Pedidos de ação").font(.ui(size:14,weight:.semibold)); Spacer(); Text("Ping + som").font(.ui(size:12)).foregroundStyle(Ink.muted); Button("Testar som") { NSSound.beep() }.buttonStyle(.plain).font(.ui(size:12)) }.padding(22).panel(10)
        HStack { Text("Motion").font(.ui(size:14,weight:.semibold)); Spacer(); Button("Ver estudo") { model.modal="motion" }.buttonStyle(.plain).font(.ui(size:12)) }.padding(22).panel(10)
        Spacer()
    }.padding(30) }
}
