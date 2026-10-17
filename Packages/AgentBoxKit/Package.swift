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
func tests(_ name: String, _ deps: [Target.Dependency]) -> Target {
    .testTarget(name: name, dependencies: deps, swiftSettings: nonisolatedSettings)
}

let package = Package(
    name: "AgentBoxKit",
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
        lib("AgentBoxStore", ["AgentBoxPlatform", grdb]),
        lib("AgentBoxDocker", ["AgentBoxPlatform", "AgentBoxProtocol"]),
        lib("AgentBoxCore", ["AgentBoxProtocol", "AgentBoxPlatform", "AgentBoxStore", "AgentBoxDocker"]),
        lib("AgentBoxDesignSystem", ["AgentBoxProtocol"], ui: true, resources: [.copy("Resources/Fonts")]),
        lib("AgentBoxUI", ["AgentBoxCore", "AgentBoxDesignSystem", "AgentBoxTerminalCore", swiftTerm], ui: true),
        .executableTarget(
            name: "agentboxd",
            dependencies: ["AgentBoxProtocol", "AgentBoxPlatform", "AgentBoxTerminalCore"],
            swiftSettings: nonisolatedSettings
        ),
        .executableTarget(
            name: "agentbox",
            dependencies: ["AgentBoxProtocol", "AgentBoxPlatform", argumentParser],
            swiftSettings: nonisolatedSettings
        ),
        tests("ProtocolTests", ["AgentBoxProtocol"]),
        tests("PlatformTests", ["AgentBoxPlatform"]),
        tests("StoreTests", ["AgentBoxStore"]),
        tests("CoreTests", ["AgentBoxCore"]),
        tests("DockerTests", ["AgentBoxDocker"]),
        tests("TerminalCoreTests", ["AgentBoxTerminalCore"]),
        tests("DesignSystemTests", ["AgentBoxDesignSystem"]),
        tests("DaemonTests", ["AgentBoxProtocol", "AgentBoxPlatform", "AgentBoxTerminalCore"]),
        .testTarget(
            name: "UISnapshotTests",
            dependencies: ["AgentBoxUI", "AgentBoxDesignSystem", snapshotTesting],
            swiftSettings: mainActorSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
