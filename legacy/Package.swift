// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "AgentBox",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentBox", targets: ["AgentBox"]),
        .executable(name: "AgentBoxMCP", targets: ["AgentBoxMCP"])
    ],
    dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")],
    targets: [
        .target(name: "AgentBoxCore"),
        .executableTarget(name: "AgentBox", dependencies: ["AgentBoxCore", "SwiftTerm"], resources: [.copy("Resources/Brands")]),
        .executableTarget(name: "AgentBoxMCP", dependencies: ["AgentBoxCore"]),
        .testTarget(name: "AgentBoxCoreTests", dependencies: ["AgentBoxCore"]),
        .testTarget(name: "AgentBoxRuntimeTests", dependencies: ["AgentBox", "SwiftTerm"])
    ],
    swiftLanguageModes: [.v5]
)
