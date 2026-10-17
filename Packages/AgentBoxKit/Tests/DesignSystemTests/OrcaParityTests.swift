import Foundation
import Testing
@testable import AgentBoxDesignSystem

/// Tokens do Agent Box = valores extraídos do Orca 1.4.219 (P17), em `docs/rebuild/reference/orca-1.4.219/tokens/`.
/// Onde diverge, a divergência é declarada com `note` no JSON fonte (02 §0).
@Suite struct OrcaParityTests {
    @Test func everyColorHasAnOrcaReferenceOrAJustification() {
        let (tokens, _) = ColorSource.load()
        for t in tokens where t.orca == nil {
            #expect(!(t.note ?? "").isEmpty, "\(t.name): sem referência do Orca e sem note")
        }
        #expect(tokens.filter { $0.orca != nil }.count > 60, "a maioria dos tokens vem do Orca")
    }

    @Test func darkColorsEqualOrcaExtraction() {
        let orca = OrcaColors()
        let (tokens, _) = ColorSource.load()
        for t in tokens {
            guard let ref = t.orca else { continue }
            guard let want = orca.resolve(ref), let got = HexColor(t.dark) else {
                Issue.record("\(t.name): referência do Orca não resolve (\(ref))")
                continue
            }
            #expect(got == want, "\(t.name) (\(ref)): \(t.dark) != Orca")
            // E o valor Swift gerado é o mesmo do Orca (rgb; alfa em byte quando o Orca traz #rrggbbaa).
            let spec = DS.ColorSpec.all[t.name]
            #expect(spec?.hex == want.rgb, "\(t.name) Swift rgb")
            if let b = want.alphaByte { #expect(spec?.alphaByte == b, "\(t.name) Swift alfa") }
        }
    }

    @Test func lightColorsEqualOrcaExtractionWhereRegistered() {
        let orca = OrcaColors()
        let (tokens, _) = ColorSource.load()
        var checked = 0
        for t in tokens {
            guard let light = t.light, let ref = t.orca, !ref.hasPrefix("palette:") else { continue }
            guard let want = orca.resolve(ref, light: true) else { continue }
            // Valores de 02 §2.11 que o dono fixou à mão podem diferir do Orca; só os "orca-puros" são conferidos.
            if let got = HexColor(light), got == want { checked += 1 }
        }
        #expect(checked > 30, "pares claros registrados batem com o Orca")
    }

    @Test func divergencesFromSpec02AreIntentional() {
        // P17: o extraído vence. Os três casos em que 02 trazia outro número:
        #expect(DS.ColorSpec.warning.hex == 0xeab308, "warning = --status-warning (02 listava #edb200)")
        #expect(DS.ColorSpec.agentWorking.hex == 0xedb200, "spinner working = yellow-500 (DS10)")
        #expect(DS.ColorSpec.border.alphaByte == 0x12, "border = #ffffff12 (02: white/7)")
        #expect(DS.ColorSpec.input.alphaByte == 0x26, "input = #ffffff26 (02: white/15)")
        // Errata da Fatia 0 (02 §0): paleta Tailwind v4 do Orca.
        #expect(DS.ColorSpec.locate.hex == 0x54a2ff)
        #expect(DS.ColorSpec.aiAccent.hex == 0xa685ff)
        #expect(DS.ColorSpec.agentNeedsInput.hex == 0xfe6e00)
        #expect(DS.ColorSpec.agentNeedsInputText.hex == 0xffb96d)
        #expect(DS.ColorSpec.agentDone.hex == 0x00bb7f)
        #expect(DS.ColorSpec.agentFailed.hex == 0xfb2c36)
        #expect(DS.ColorSpec.agentUnknown.hex == 0xf99c00)
        #expect(DS.ColorSpec.prMerged.hex == 0xc07eff)
        #expect(DS.ColorSpec.checksFailing.hex == 0xff2357)
        #expect(DS.Radius.sm == 6)
        #expect(DS.Radius.md == 8)
    }

    @Test func spacingUsesOrcaScale() {
        let doc = Repo.json("\(Repo.orcaTokens)/spacing.json")
        let scale = Set((doc["scale_units_px"] as? [String: NSNumber] ?? [:]).values.map(\.doubleValue))
        #expect(!scale.isEmpty)
        #expect((doc["base_px"] as? NSNumber)?.doubleValue == 4)
        for (name, v) in DS.Space.all {
            #expect(scale.contains(Double(v)), "space.\(name) = \(v) fora da escala do Orca")
        }
    }

    @Test func radiiUseOrcaValues() {
        let doc = Repo.json("\(Repo.orcaTokens)/radii.json")
        let used = Set((doc["border_radius_px_used"] as? [NSNumber] ?? []).map(\.doubleValue))
        let base = (doc["radius_base_px"] as? NSNumber)?.doubleValue ?? 0
        #expect(base == 10)
        #expect(Double(DS.Radius.card) == base, "rCard = --radius")
        #expect(Double(DS.Radius.sm) == base * 0.6, "rSM = --radius-sm (calc(var(--radius) * .6))")
        #expect(Double(DS.Radius.md) == base * 0.8, "rMD = --radius-md (calc(var(--radius) * .8))")
        #expect(Double(DS.Radius.xs) == 2, "rXS = --radius-xs (.125rem)")
        for (name, v) in DS.Radius.all {
            #expect(used.contains(Double(v)), "radius.\(name) = \(v) não aparece no CSS do Orca")
        }
    }

    @Test func typographyUsesOrcaSizesWeightsAndLineHeights() {
        let doc = Repo.json("\(Repo.orcaTokens)/typography.json")
        var sizes = Set((doc["font_sizes_px_used"] as? [NSNumber] ?? []).map(\.doubleValue))
        var weights = Set((doc["font_weights_used"] as? [NSNumber] ?? []).map(\.doubleValue))
        var lineHeights = Set((doc["line_heights_px_used"] as? [NSNumber] ?? []).map(\.doubleValue))
        for v in (doc["font_weight_vars"] as? [String: String] ?? [:]).values { weights.insert(Double(v) ?? 0) }
        // Escala Tailwind: --text-xs ... --text-4xl com line-height `calc(a / b)` (razão sobre o tamanho).
        let scale = doc["text_scale"] as? [String: String] ?? [:]
        for (key, value) in scale where key.hasPrefix("--text-") && !key.contains("--line-height") {
            guard let rem = Self.rem(value) else { continue }
            let size = rem * 16
            sizes.insert(size)
            if let lh = scale[key + "--line-height"], let ratio = Self.calcRatio(lh) { lineHeights.insert(size * ratio) }
        }
        #expect((doc["font_families"] as? [String: String])?["--font-mono"]?.contains("SF Mono") == true)

        let flags = (Repo.json("design/tokens/typography.json")["styles"] as? [String: [String: Any]] ?? [:])
            .compactMapValues { $0["lineHeightSource"] as? String }
        for (name, t) in DS.Font.all {
            #expect(sizes.contains(Double(t.size)), "font.\(name) size \(t.size) fora do Orca")
            #expect(weights.contains(t.weight), "font.\(name) weight \(t.weight) fora do Orca")
            if flags[name] == "spec" {
                #expect(!lineHeights.contains(Double(t.lineHeight)), "font.\(name): flag 'spec' mas o Orca usa \(t.lineHeight)")
            } else {
                #expect(lineHeights.contains(Double(t.lineHeight)), "font.\(name) line-height \(t.lineHeight) fora do Orca")
            }
        }
    }

    @Test func fontFamiliesAreGeistAndSFMono() {
        let doc = Repo.json("\(Repo.orcaTokens)/typography.json")
        let faces = (doc["font_faces"] as? [[String: Any]] ?? []).compactMap { $0["family"] as? String }
        #expect(faces.contains("Geist"), "Orca embute a Geist")
        #expect(DS.Font.uiFamilyName == "Geist")
        #expect(DS.Font.monoFamilyName == "SF Mono")
    }

    @Test func motionOriginatedInOrcaMatchesExtraction() {
        let doc = Repo.json("\(Repo.orcaTokens)/motion.json")
        let ms = Set((doc["durations_ms_used"] as? [NSNumber] ?? []).map(\.doubleValue))
        // Durações herdadas do Orca (04 §3.2): fast 150, base 200, medium 240, panel 300, handoff 360.
        for (name, seconds) in [("fast", MotionTokens.Duration.fast), ("base", MotionTokens.Duration.base),
                                ("medium", MotionTokens.Duration.medium), ("panel", MotionTokens.Duration.panel),
                                ("handoff", MotionTokens.Duration.handoff)] {
            #expect(ms.contains((seconds * 1000).rounded()), "duration.\(name) = \(seconds)s não está no Orca")
        }
        let curves = (doc["timing_functions_used"] as? [String] ?? []).compactMap(Self.bezier)
        // Curvas herdadas do Orca (04 §3.3): standard, expoOut, drawer, exitClip.
        for (name, b) in [("standard", MotionTokens.Easing.standard), ("expoOut", MotionTokens.Easing.expoOut),
                          ("drawer", MotionTokens.Easing.drawer), ("exitClip", MotionTokens.Easing.exitClip)] {
            #expect(curves.contains(b), "easing.\(name) não está no Orca")
        }
    }

    // MARK: parsing de valores CSS

    static func rem(_ s: String) -> Double? {
        guard s.hasSuffix("rem") else { return nil }
        let n = s.dropLast(3)
        return Double(n.hasPrefix(".") ? "0" + n : String(n))
    }

    /// `calc(2 / 1.5)` -> 1.3333
    static func calcRatio(_ s: String) -> Double? {
        guard s.hasPrefix("calc("), s.hasSuffix(")") else { return Double(s) }
        let inner = s.dropFirst(5).dropLast()
        let parts = inner.split(separator: "/").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let a = parts[0], let b = parts[1], b != 0 else { return nil }
        return a / b
    }

    /// `cubic-bezier(.16,1,.3,1)`
    static func bezier(_ s: String) -> Bezier? {
        guard s.hasPrefix("cubic-bezier("), s.hasSuffix(")") else { return nil }
        let nums = s.dropFirst(13).dropLast().split(separator: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "^\\.", with: "0.", options: .regularExpression))
        }
        guard nums.count == 4 else { return nil }
        return Bezier(nums[0], nums[1], nums[2], nums[3])
    }
}
