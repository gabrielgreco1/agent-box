// swift-tools-version: 6.2
// AgentBoxKit - pacote local do rebuild (08 AR-121). Versões externas exatas conforme scripts/tool-versions.txt.
// Isolamento padrão (AR-402): UI e DesignSystem em MainActor; demais alvos nonisolated + NonisolatedNonsendingByDefault.
import PackageDescription

let mainActorSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .treatAllWarnings(as: .error),
]
let nonisolatedSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .treatAllWarnings(as: .error),
]

let swiftTerm: Target.Dependency = .product(name: "SwiftTerm", package: "SwiftTerm")
let grdb: Target.Dependency = .product(name: "GRDB", package: "GRDB.swift")
let argumentParser: Target.Dependency = .product(name: "ArgumentParser", package: "swift-argument-parser")
let snapshotTesting: Target.Dependency = .product(name: "SnapshotTesting", package: "swift-snapshot-testing")

func lib(_ name: String, _ deps: [Target.Dependency], ui: Bool = false, resources: [Resource] = []) -> Target {
    .target(name: name, dependencies: deps, resources: resources, swiftSettings: ui ? mainActorSettings : nonisolatedSettings)
}
func tests(_ name: String, _ deps: [Target.Dependency], resources: [Resource] = []) -> Target {
    .testTarget(name: name, dependencies: deps, resources: resources, swiftSettings: nonisolatedSettings)
}

let package = Package(
    name: "AgentBoxKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AgentBoxProtocol", targets: ["AgentBoxProtocol"]),
        .library(name: "AgentBoxPlatform", targets: ["AgentBoxPlatform"]),
        .library(name: "AgentBoxTerminalCore", targets: ["AgentBoxTerminalCore"]),
        .library(name: "AgentBoxStore", targets: ["AgentBoxStore"]),
        .library(name: "AgentBoxDocker", targets: ["AgentBoxDocker"]),
        .library(name: "AgentBoxCore", targets: ["AgentBoxCore"]),
        .library(name: "AgentBoxDesignSystem", targets: ["AgentBoxDesignSystem"]),
        .library(name: "AgentBoxUI", targets: ["AgentBoxUI"]),
        .executable(name: "agentboxd", targets: ["agentboxd"]),
        .executable(name: "agentbox", targets: ["agentbox"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", exact: "1.19.6"),
    ],
    targets: [
        lib("AgentBoxProtocol", []),
        lib("AgentBoxPlatform", ["AgentBoxProtocol"]),
        lib("AgentBoxTerminalCore", [swiftTerm]),
        lib("AgentBoxStore", ["AgentBoxPlatform", "AgentBoxProtocol", grdb]),
        lib("AgentBoxDocker", ["AgentBoxPlatform", "AgentBoxProtocol"]),
        lib("AgentBoxCore", ["AgentBoxProtocol", "AgentBoxPlatform", "AgentBoxStore", "AgentBoxDocker"]),
        lib("AgentBoxDesignSystem", ["AgentBoxProtocol"], ui: true, resources: [.copy("Resources/Fonts")]),
        lib(
            "AgentBoxUI", ["AgentBoxCore", "AgentBoxDesignSystem", "AgentBoxTerminalCore", swiftTerm], ui: true,
            resources: [.process("Resources")]  // String Catalog (lint-ui exige strings no catálogo)
        ),
        .executableTarget(
            name: "agentboxd",
            dependencies: ["AgentBoxProtocol", "AgentBoxPlatform", "AgentBoxTerminalCore"],
            // Modo ad-hoc de desenvolvimento do peer auth (S-03/T1-07): só em debug por padrão; build.sh liga em Release
            // apenas quando assina ad-hoc. O daemon ainda confere que ele próprio é ad-hoc antes de usar o modo.
            swiftSettings: nonisolatedSettings + [.define("AGENTBOX_ALLOW_ADHOC_PEERS", .when(configuration: .debug))]
        ),
        .executableTarget(
            name: "agentbox",
            dependencies: ["AgentBoxProtocol", "AgentBoxPlatform", argumentParser],
            swiftSettings: nonisolatedSettings
        ),
        // Cliente de teste do peer auth (T1-07); fora de `products`, só os testes o usam.
        .executableTarget(name: "peerprobe", dependencies: ["AgentBoxProtocol", "AgentBoxPlatform"], swiftSettings: nonisolatedSettings),
        tests("ProtocolTests", ["AgentBoxProtocol"], resources: [.copy("Fixtures")]),
        tests("PlatformTests", ["AgentBoxPlatform", "AgentBoxProtocol"]),
        tests("StoreTests", ["AgentBoxStore", "AgentBoxProtocol", "AgentBoxPlatform", grdb]),
        .testTarget(
            name: "CoreTests",
            dependencies: ["AgentBoxCore", "AgentBoxProtocol", "AgentBoxPlatform"],
            exclude: ["Launch/Fixtures", "Launch/Golden"], // lidos por caminho (#filePath); golden gravado com AB_UPDATE_GOLDEN=1
            swiftSettings: nonisolatedSettings
        ),
        tests("DockerTests", ["AgentBoxDocker"]),
        tests("TerminalCoreTests", ["AgentBoxTerminalCore", swiftTerm]),
        tests("DesignSystemTests", ["AgentBoxDesignSystem"]),
        tests("DaemonTests", ["AgentBoxProtocol", "AgentBoxPlatform", "AgentBoxTerminalCore", "AgentBoxCore", "agentboxd", "peerprobe", swiftTerm]),
        .testTarget(
            name: "UISnapshotTests",
            dependencies: ["AgentBoxUI", "AgentBoxDesignSystem", snapshotTesting],
            exclude: ["__Snapshots__"],  // referências PNG do swift-snapshot-testing, lidas por caminho
            swiftSettings: mainActorSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
