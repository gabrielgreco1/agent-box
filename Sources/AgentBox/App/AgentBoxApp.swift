import SwiftUI
import AppKit

@MainActor final class RuntimeLifecycle {
    static let shared=RuntimeLifecycle()
    private(set) var runtime:TerminalRuntimeManager?
    func attach(_ runtime:TerminalRuntimeManager) {self.runtime=runtime}
}

@MainActor final class AgentBoxAppDelegate:NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification:Notification) {
        if let url = AppResources.brandURL("agentbox") {
            NSApp.applicationIconImage = NSImage(contentsOf: url)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool {
        if !hasVisibleWindows {sender.windows.first(where:{$0.canBecomeMain})?.makeKeyAndOrderFront(nil)}
        return true
    }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if RuntimeLifecycle.shared.runtime?.hasRunningProcesses == true {
            let alert=NSAlert();alert.messageText="Encerrar os terminais ativos?";alert.informativeText="Sair encerra os processos deste app. As sessões ficam salvas para abrir novamente; os processos não continuam em segundo plano após sair.";alert.addButton(withTitle:"Cancelar");alert.addButton(withTitle:"Encerrar e sair")
            guard alert.runModal() == .alertSecondButtonReturn else {return .terminateCancel}
        }
        AgentComputerAccess.shared.shutdown()
        RuntimeLifecycle.shared.runtime?.shutdown()
        WorkspaceDirectoryAccess.shared.stopAll()
        return .terminateNow
    }
}

@main struct AgentBoxApplication:App {
    @NSApplicationDelegateAdaptor(AgentBoxAppDelegate.self) private var delegate
    var body:some Scene {
        Window("Agent Box",id:"workspace") {
            AppRootView().preferredColorScheme(.dark)
        }.defaultSize(width:1360,height:860)
        Settings {AppSettingsView().preferredColorScheme(.dark)}
    }
}

private struct AppRootView:View {
    @AppStorage("initialSetupCompleted") private var setupComplete=false
    @State private var showSetup=false
    var body:some View {
        WorkspaceView()
            .onAppear {showSetup = !setupComplete}
            .sheet(isPresented:$showSetup) {
                VStack(alignment:.leading,spacing:12) {
                    Text("Configuração inicial").font(.system(size:18,weight:.medium))
                    Text("Escolha o que o Agent Box pode usar. Você pode revisar estas opções em Configurações.").foregroundStyle(.secondary)
                    AppSettingsView()
                    Divider()
                    HStack {Text("Terminais funcionam sem Docker.").font(.caption).foregroundStyle(.secondary);Spacer();Button("Concluir"){setupComplete=true;showSetup=false}.keyboardShortcut(.defaultAction)}
                }.padding(20).frame(width:760,height:620).interactiveDismissDisabled()
            }
    }
}
