import AppKit
import AgentBoxProtocol
import Testing
@testable import AgentBoxDesignSystem

/// Logos oficiais de agente (02 §2.10): PNGs em `Resources/AgentLogos`, proveniência em `sources.json`.
@MainActor @Suite struct AgentLogoTests {
    @Test func officialLogosAreBundledAtBothScales() throws {
        for provider in [TerminalProvider.claude, .codex, .opencode] {
            let name = try #require(DSAgentLogoImages.name(for: provider), "\(provider) deve ter logo oficial")
            let image = try #require(DSAgentLogoImages.image(for: provider), "\(name)@3x.png ausente no bundle")
            #expect(image.size.width > 0 && image.size.height > 0)
            for scale in [2, 3] {
                #expect(DSAgentLogoImages.fileURL(name, scale: scale) != nil, "\(name)@\(scale)x.png ausente")
            }
        }
    }

    @Test func shellAndCustomUseSFSymbolsNotBrandFiles() {
        #expect(DSAgentLogoImages.name(for: .shell) == nil)
        #expect(DSAgentLogoImages.name(for: .custom) == nil)
    }

    @Test func provenanceFileTravelsWithTheLogos() throws {
        let url = try #require(DSAgentLogoImages.provenanceURL, "sources.json ausente em Resources/AgentLogos")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("Logos identify third-party integrations, not Agent Box ownership."))
        #expect(text.contains("\"file\": \"claude.png\""))
        #expect(text.contains("\"file\": \"opencode.png\""))
    }
}
