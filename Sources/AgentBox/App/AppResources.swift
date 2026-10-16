import Foundation

/// SwiftPM's executable accessor looks beside Bundle.main, not Contents/Resources.
/// Resolve packaged assets directly so an installed app never reads the build checkout.
enum AppResources {
    static func brandURL(_ name: String) -> URL? {
        if Bundle.main.bundleURL.pathExtension == "app", let resources = Bundle.main.resourceURL {
            let url = resources.appendingPathComponent("AgentBox_AgentBox.bundle/Brands/\(name).png")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Brands")
    }
}
