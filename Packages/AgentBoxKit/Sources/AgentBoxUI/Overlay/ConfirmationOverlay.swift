import AgentBoxDesignSystem
import AgentBoxProtocol
import Observation
import SwiftUI

/// Estado observável de uma confirmação: o handler de `dialog.<nome>.dontAsk` grava aqui e o checkbox lê.
@MainActor @Observable
public final class ConfirmationState {
    public var dontAsk = false
    public init() {}
}

/// Dados de uma confirmação (02 §12.18, 03 §16, M-103). Textos já localizados; IDs de `03 §22`.
public struct ConfirmationModel {
    public var name: String
    public var rootID: A11yID
    public var title: String
    public var message: String
    public var confirmTitle: LocalizedStringKey
    public var cancelTitle: LocalizedStringKey
    public var confirmAction: ActionID
    public var confirmID: A11yID
    public var cancelAction: ActionID
    public var cancelID: A11yID
    public var dontAsk: DontAsk?
    public var destructive: Bool
    /// Botão padrão (↵): `Cancel` nos quits que param os agentes (03 §16.10), senão a confirmação.
    public var defaultsToCancel: Bool
    public var symbol: String?
    /// Estado dos controles que o registro altera (hoje: "Don't ask again").
    public var state = ConfirmationState()

    public struct DontAsk {
        public var action: ActionID
        public var id: A11yID
        public init(action: ActionID, id: A11yID) {
            self.action = action
            self.id = id
        }
    }

    public init(
        name: String, rootID: A11yID, title: String, message: String, confirmTitle: LocalizedStringKey, cancelTitle: LocalizedStringKey = "Cancel",
        confirmAction: ActionID, confirmID: A11yID, cancelAction: ActionID, cancelID: A11yID, dontAsk: DontAsk? = nil,
        destructive: Bool = true, defaultsToCancel: Bool = false, symbol: String? = nil
    ) {
        self.name = name
        self.rootID = rootID
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.confirmAction = confirmAction
        self.confirmID = confirmID
        self.cancelAction = cancelAction
        self.cancelID = cancelID
        self.dontAsk = dontAsk
        self.destructive = destructive
        self.defaultsToCancel = defaultsToCancel
        self.symbol = symbol
    }

    /// "Close this terminal?" (03 §16.1).
    public static func closeTerminal(message: String) -> ConfirmationModel {
        ConfirmationModel(
            name: "confirmClose", rootID: .overlayConfirmClose, title: String(localized: "Close this terminal?", bundle: .module),
            message: message, confirmTitle: "Close Terminal", confirmAction: .dialogCloseTerminalConfirm,
            confirmID: .overlayConfirmCloseConfirm, cancelAction: .dialogCloseTerminalCancel, cancelID: .overlayConfirmCloseCancel,
            dontAsk: DontAsk(action: .dialogCloseTerminalDontAsk, id: .overlayConfirmCloseDontAsk), symbol: "xmark.octagon")
    }

    /// "Remove "<project>" from Agent Box?" (03 §16.6): arquiva as sessões; nenhum arquivo é apagado.
    public static func removeProject(name: String, sessionCount: Int) -> ConfirmationModel {
        ConfirmationModel(
            name: "confirmRemoveProject", rootID: .overlayConfirmRemoveProject,
            title: String(localized: "Remove \"\(name)\" from Agent Box?", bundle: .module),
            message: String(localized: "Its \(sessionCount) sessions are archived. No files, worktrees or branches are deleted.", bundle: .module),
            confirmTitle: "Remove", confirmAction: .dialogRemoveProjectConfirm, confirmID: .overlayConfirmRemoveProjectConfirm,
            cancelAction: .dialogRemoveProjectCancel, cancelID: .overlayConfirmRemoveProjectCancel, symbol: "trash")
    }
}

/// Conteúdo do overlay de confirmação: cartão de 448 pt, destrutivo entra já focado, sem stagger (M-103).
struct ConfirmationOverlayContent: View {
    let model: ConfirmationModel
    @FocusState private var focus: Focus?

    enum Focus { case confirm, cancel }

    var body: some View {
        VStack(alignment: .leading, spacing: DSMetrics.overlayGap) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                if let symbol = model.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: DSMetrics.confirmationIcon))
                        .foregroundStyle(model.destructive ? DS.Color.destructive : DS.Color.textPrimary)
                        .frame(width: DSMetrics.confirmationTile, height: DSMetrics.confirmationTile)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.card)
                                .fill(model.destructive ? DS.Color.destructiveBackground : DS.Color.secondary))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(verbatim: model.title)
                        .dsFont(DS.Font.dialogTitle)
                        .foregroundStyle(DS.Color.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: model.message)
                        .dsFont(DS.Font.dialogBody)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: DS.Space.s2) {
                if let dontAsk = model.dontAsk {
                    DSCheckbox(isOn: model.state.dontAsk, action: dontAsk.action, id: dontAsk.id, "Don't ask again")
                }
                Spacer(minLength: DS.Space.s2)
                DSButton(model.cancelAction, id: model.cancelID, model.cancelTitle, variant: model.defaultsToCancel ? .primary : .outline)
                    .keyboardShortcut(model.defaultsToCancel ? .defaultAction : nil)
                    .focused($focus, equals: .cancel)
                DSButton(
                    model.confirmAction, id: model.confirmID, model.confirmTitle,
                    variant: model.destructive ? .destructive : .primary)
                    .keyboardShortcut(model.defaultsToCancel ? nil : .defaultAction)
                    .focused($focus, equals: .confirm)
            }
        }
        .padding(DSMetrics.overlayPadding)
        .task {
            await Task.yield()
            focus = model.defaultsToCancel ? .cancel : .confirm
        }
    }
}

public extension OverlaySpec {
    /// Overlay de confirmação (M-103): 448 pt, sem stagger, Esc = Cancel, clique no scrim = Cancel (não há dados digitados).
    static func confirmation(_ model: ConfirmationModel) -> OverlaySpec {
        OverlaySpec(
            name: model.name, id: model.rootID, width: DS.Layout.confirmationWidth, cancelAction: model.cancelAction,
            content: { AnyView(ConfirmationOverlayContent(model: model)) })
    }
}
