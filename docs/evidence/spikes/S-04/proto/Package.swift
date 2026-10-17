// swift-tools-version:6.0
// Spike S-04: reattach prototype (daemon with forkpty + 4 MiB ring + client rebuild with SwiftTerm Terminal).
// SwiftTerm version is selectable: ST=1.20.0 (default) or ST=1.99.0, via a local checkout in ../s02/src/st-<ver>.
import PackageDescription
import Foundation
let ver = ProcessInfo.processInfo.environment["ST"] ?? "1.20.0"
let package = Package(
    name: "s04",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../s02/src/st-\(ver)")],
    targets: [
        .executableTarget(
            name: "s04",
            dependencies: [.product(name: "SwiftTerm", package: "st-\(ver)")],
            path: "Sources/s04",
            swiftSettings: [.swiftLanguageMode(.v5)])
    ])
