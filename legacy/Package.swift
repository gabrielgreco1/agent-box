// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Racky",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Racky", targets: ["Racky"]),
        .executable(name: "RackyMCP", targets: ["RackyMCP"])
    ],
    dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")],
    targets: [
        .target(name: "RackyCore"),
        .executableTarget(name: "Racky", dependencies: ["RackyCore", "SwiftTerm"], resources: [.copy("Resources/Brands")]),
        .executableTarget(name: "RackyMCP", dependencies: ["RackyCore"]),
        .testTarget(name: "RackyCoreTests", dependencies: ["RackyCore"]),
        .testTarget(name: "RackyRuntimeTests", dependencies: ["Racky", "SwiftTerm"])
    ],
    swiftLanguageModes: [.v5]
)
