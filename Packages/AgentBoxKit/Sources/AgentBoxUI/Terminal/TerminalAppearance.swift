import AgentBoxDesignSystem
import AppKit
import Carbon.HIToolbox
import SwiftTerm

/// Aparência do terminal (02 §3). Os valores padrão vêm dos tokens; Settings › Terminal sobrescreve depois (T1-26).
public struct TerminalAppearance: Equatable {
    public var fontSize: CGFloat
    public var padding: CGFloat
    public var scrollback: Int
    /// `Option as Meta` (02 §3). `auto` decide pelo layout de teclado.
    public var optionAsMeta: OptionAsMeta

    public init(
        fontSize: CGFloat = DS.TerminalFont.defaultSize, padding: CGFloat = DS.TerminalFont.padding, scrollback: Int = 5000,
        optionAsMeta: OptionAsMeta = .auto
    ) {
        self.fontSize = Self.clamp(fontSize)
        self.padding = padding
        self.scrollback = scrollback
        self.optionAsMeta = optionAsMeta
    }

    public static func clamp(_ size: CGFloat) -> CGFloat {
        min(max(size, DS.TerminalFont.sizeMin), DS.TerminalFont.sizeMax)
    }

    /// SF Mono Medium (500); o negrito (700) é derivado pela view. Line height 1.0 = altura natural da célula.
    public var font: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
    }
}

public enum OptionAsMeta: String, CaseIterable, Sendable {
    case auto, left, right, always, never

    /// `Auto`: Option vira Meta nos layouts latinos sem composição por Option (US, ABC, Dvorak, Colemak...); em
    /// layouts onde Option compõe caracteres (ABNT2, ISO europeus) a tecla fica com o sistema.
    public func resolves(layoutID: String?) -> Bool {
        switch self {
        case .always: return true
        case .never: return false
        case .left, .right: return true  // SwiftTerm só distingue ligado/desligado; lado exato fica para o endurecimento
        case .auto:
            guard let id = layoutID?.lowercased() else { return true }
            let metaFriendly = ["keylayout.us", "keylayout.abc", "keylayout.dvorak", "keylayout.colemak", "keylayout.usextended"]
            return metaFriendly.contains { id.contains($0) }
        }
    }
}

/// Aplica o tema de 02 §3 numa view do SwiftTerm: paleta ANSI do dono, fundo, texto, cursor, seleção e fonte.
public enum TerminalTheme {
    static func swiftTermColor(_ c: DSRGBA) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red8: UInt16((c.red * 255).rounded()), green8: UInt16((c.green * 255).rounded()), blue8: UInt16((c.blue * 255).rounded()))
    }

    /// Paleta de 16 cores (índices 0-7 normais, 8-15 bright).
    public static var ansiPalette: [SwiftTerm.Color] { DS.Terminal.ansi.map(swiftTermColor) }

    @MainActor
    public static func apply(to view: TerminalView, appearance: TerminalAppearance) {
        view.installColors(ansiPalette)
        view.nativeBackgroundColor = DS.Terminal.background.nsColor
        view.nativeForegroundColor = DS.Terminal.foreground.nsColor
        view.caretColor = DS.Terminal.cursor.nsColor
        view.caretTextColor = DS.Terminal.cursorText.nsColor
        view.selectedTextBackgroundColor = DS.Terminal.selectionBackground.nsColor
        view.font = appearance.font
        view.optionAsMetaKey = appearance.optionAsMeta.resolves(layoutID: TerminalKeyboardLayout.currentID())
    }
}

enum TerminalKeyboardLayout {
    static func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}
