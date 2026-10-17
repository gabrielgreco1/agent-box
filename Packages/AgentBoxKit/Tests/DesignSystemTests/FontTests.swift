import AppKit
import CoreText
import SwiftUI
import Testing
@testable import AgentBoxDesignSystem

/// Geist embutida e registrada em runtime (02 §4.1). Exige `scripts/bootstrap.sh --fonts` (baixa e confere o SHA-256).
@MainActor @Suite(.offscreenAppKit) struct FontTests {
    private static let hint = "Geist[wght].ttf ausente em Resources/Fonts: rode scripts/bootstrap.sh --fonts"

    @Test func geistFileIsBundledWithLicense() throws {
        let font = try #require(DSFonts.fontURL, Comment(rawValue: Self.hint))
        #expect(font.lastPathComponent == "Geist[wght].ttf")
        let license = try #require(DSFonts.licenseURL, "OFL.txt deve estar no bundle")
        let text = try String(contentsOf: license, encoding: .utf8)
        #expect(text.contains("SIL OPEN FONT LICENSE Version 1.1"))
        #expect(text.contains("Geist"))
    }

    @Test func geistRegistersAndResolvesByFamilyName() throws {
        #expect(DSFonts.registerIfNeeded(), Comment(rawValue: Self.hint))
        let families = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        #expect(families.contains("Geist"), "família Geist registrada")
        // `Font.custom("Geist", size:)` resolve para a família registrada.
        let ns = NSFont(name: "Geist", size: 13)
        #expect(ns != nil, "NSFont(name: Geist) resolve")
        #expect(ns?.familyName == "Geist")
        _ = SwiftUI.Font.custom("Geist", size: 13)
    }

    @Test func uiFontUsesGeistAndTheWeightAxis() throws {
        #expect(DSFonts.registerIfNeeded(), Comment(rawValue: Self.hint))
        let regular = DSFonts.uiFont(size: 13, weight: 400)
        let mid450 = DSFonts.uiFont(size: 13, weight: 450)
        let medium = DSFonts.uiFont(size: 13, weight: 500)
        let semibold = DSFonts.uiFont(size: 13, weight: 600)
        for f in [regular, mid450, medium, semibold] { #expect(f.familyName == "Geist") }
        func wght(_ f: NSFont) -> Double? {
            let variation = CTFontCopyVariation(f as CTFont) as? [NSNumber: NSNumber]
            return variation?[NSNumber(value: DSFonts.weightAxisTag)]?.doubleValue
        }
        #expect((wght(regular) ?? 400) == 400, "400 é o valor padrão do eixo (CT omite o default)")
        #expect(wght(mid450) == 450, "peso intermediário 450 via eixo wght")
        #expect(wght(medium) == 500)
        #expect(wght(semibold) == 600)
    }

    @Test func everyTextStyleResolvesToTheRightFamily() {
        #expect(DSFonts.registerIfNeeded(), Comment(rawValue: Self.hint))
        for (name, style) in DS.Font.all {
            let f = style.nsFont
            switch style.family {
            case .ui:
                #expect(f.familyName == "Geist", "\(name) deve ser Geist")
            case .mono:
                #expect(f.isFixedPitch, "\(name) deve ser monoespaçada (SF Mono)")
                #expect(f.fontName.contains("Monospaced") || f.fontName.contains("SFMono"), "\(name): \(f.fontName)")
            }
            #expect(f.pointSize == style.size, "\(name) tamanho")
            _ = style.font
        }
    }

    @Test func terminalUsesSFMono() {
        let f = DSFonts.monoFont(size: DS.TerminalFont.defaultSize, weight: DS.TerminalFont.weight)
        #expect(f.isFixedPitch)
        // monospacedSystemFont = SF Mono (nome interno ".AppleSystemUIFontMonospaced").
        #expect(f.fontName.contains("Monospaced") || f.fontName.contains("SFMono"), "terminal em SF Mono: \(f.fontName)")
        #expect(f.fontName != "Geist" && f.familyName != "Geist")
        #expect(f.pointSize == 14)
    }

    @Test func tabularDigitsKeepNumbersAligned() {
        #expect(DSFonts.registerIfNeeded(), Comment(rawValue: Self.hint))
        let style = DS.Font.microNumeric
        #expect(style.tabularDigits)
        #expect(style.nsFont.familyName == "Geist")
    }

    @Test func weightMappingIsMonotonic() {
        let ws = stride(from: 100.0, through: 900.0, by: 50).map { DSFonts.systemWeight($0).rawValue }
        #expect(zip(ws, ws.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(DSFonts.systemWeight(400) == .regular)
        #expect(DSFonts.systemWeight(500) == .medium)
        #expect(DSFonts.systemWeight(600) == .semibold)
    }
}
