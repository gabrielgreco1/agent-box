import SwiftUI
import AppKit
import AVFoundation

/// Decorative, silent animation. Real controls and transitions stay native.
/// Uses the included poster when Reduce Motion is enabled or the video is absent.
struct MotionAssetView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if !reduceMotion, let url = Bundle.main.url(forResource: "box-loop", withExtension: "mp4") {
                LoopingAsset(url: url)
            } else if let url = Bundle.main.url(forResource: "box-poster", withExtension: "png"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
            } else { BoxMark(size: 120) }
        }.accessibilityHidden(true)
    }
}
private struct LoopingAsset: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> LoopSurface { LoopSurface(url: url) }
    func updateNSView(_ view: LoopSurface, context: Context) {}
    static func dismantleNSView(_ view: LoopSurface, coordinator: ()) { view.stop() }
}
private final class LoopSurface: NSView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private let videoLayer = AVPlayerLayer()
    init(url: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        videoLayer.player = player
        videoLayer.videoGravity = .resizeAspect
        layer?.addSublayer(videoLayer)
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func layout() { super.layout(); videoLayer.frame = bounds }
    func stop() { player.pause(); looper?.disableLooping(); player.removeAllItems(); videoLayer.player = nil }
}
