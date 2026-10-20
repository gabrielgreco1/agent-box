import RackyCore
import RackyDesignSystem
import RackyPlatform
import AppKit
import Foundation
import SwiftTerm

/// Arquivo ou pasta clicado no terminal, com o `:linha:col` do texto.
nonisolated public struct TerminalFileTarget: Equatable, Sendable {
    public var path: String
    public var line: Int?
    public var column: Int?
    public var isDirectory: Bool
}

/// ⌘-clique abre no visualizador do app; ⇧⌘-clique no app padrão do sistema (03 §4.1).
nonisolated public enum TerminalLinkOpenMode: Sendable {
    case inApp
    case system
}

/// Caminhos de arquivo no terminal: sublinhado e dica ao passar o mouse com ⌘, e o clique (03 §4.1). URLs ficam com o
/// SwiftTerm (detecção implícita, OSC 8 e realce próprios); aqui só entram caminhos que existem em disco.
///
/// O SwiftTerm expõe `mouseMoved`/`flagsChanged` como `public` (não `open`), então o acompanhamento do mouse é uma
/// `NSTrackingArea` própria e um monitor local de `flagsChanged`. A leitura da linha usa `visibleRowsText` (cópia) e o
/// `stat` roda fora do main; o resultado só vale se o mouse ainda está na mesma célula.
@MainActor
final class TerminalLinkInteraction: NSResponder {
    private struct Hover: Equatable {
        var target: TerminalFileTarget
        var row: Int
        var columns: Range<Int>
    }

    private unowned let surface: TerminalSurfaceView
    /// Pasta onde caminhos relativos são resolvidos (cwd do terminal).
    var cwd: () -> String? = { nil }
    var onOpen: ((TerminalFileTarget, TerminalLinkOpenMode) -> Void)?

    private let underline = NSView()
    private let tip = LinkTipView()
    private var hover: Hover?
    private var probe: Task<Void, Never>?
    private var probedCell: (row: Int, col: Int, text: String)?
    private var monitor: Any?
    private var claimed: Hover?

    init(surface: TerminalSurfaceView) {
        self.surface = surface
        super.init()
        underline.wantsLayer = true
        underline.layer?.backgroundColor = DS.ColorSpec.textPrimary.nsColor.cgColor
        underline.isHidden = true
        tip.isHidden = true
        surface.addSubview(underline)
        surface.addSubview(tip)
        surface.addTrackingArea(
            NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.modifiersChanged(event) }
            return event
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }  // required init?(coder:) não usado

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        probe?.cancel()
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) { update(at: event.locationInWindow, flags: event.modifierFlags) }

    override func mouseExited(with event: NSEvent) { clear() }

    private func modifiersChanged(_ event: NSEvent) {
        guard event.window != nil, event.window === surface.window else { return }
        guard event.modifierFlags.contains(.command), let window = surface.window else { return clear() }
        update(at: window.mouseLocationOutsideOfEventStream, flags: event.modifierFlags)
    }

    private func clear() {
        probe?.cancel()
        probedCell = nil
        guard hover != nil || !underline.isHidden else { return }
        hover = nil
        underline.isHidden = true
        tip.isHidden = true
    }

    /// Célula (coluna, linha da tela) sob o ponto da janela, ou `nil` fora da grade.
    private func cell(at windowPoint: NSPoint) -> (col: Int, row: Int, cellSize: CGSize)? {
        let point = surface.convert(windowPoint, from: nil)
        let dims = surface.terminalDimensions
        guard surface.bounds.contains(point), dims.cols > 0, dims.rows > 0 else { return nil }
        let optimal = surface.getOptimalFrameSize()
        let size = CGSize(width: optimal.width / CGFloat(dims.cols), height: optimal.height / CGFloat(dims.rows))
        guard size.width > 0, size.height > 0 else { return nil }
        let col = Int(point.x / size.width)
        let row = Int((surface.bounds.height - point.y) / size.height)
        guard (0..<dims.cols).contains(col), (0..<dims.rows).contains(row) else { return nil }
        return (col, row, size)
    }

    private func update(at windowPoint: NSPoint, flags: NSEvent.ModifierFlags) {
        guard flags.contains(.command), let hit = cell(at: windowPoint),
            let text = surface.visibleRowsText(hit.row..<hit.row + 1).first
        else { return clear() }
        if let hover, hover.row == hit.row, hover.columns.contains(hit.col), probedCell?.text == text { return }
        if hover != nil {  // saiu do caminho: some já, sem esperar o `stat` da célula nova
            hover = nil
            underline.isHidden = true
            tip.isHidden = true
        }
        if let probed = probedCell, probed.row == hit.row, probed.col == hit.col, probed.text == text { return }
        guard let index = TerminalLinkDetector.characterIndex(forColumn: hit.col, in: text) else { return clear() }
        probe?.cancel()
        probedCell = (hit.row, hit.col, text)
        let cwd = cwd()
        let row = hit.row
        let size = hit.cellSize
        probe = Task { [weak self] in
            let found = await BlockingIOBridge.run { () -> (TerminalLink, Bool)? in
                var isDirectory = false
                let link = TerminalLinkDetector.detect(line: text, column: index, cwd: cwd) { path in
                    guard let kind = PathProbe.kind(of: path) else { return false }
                    isDirectory = kind == .directory
                    return true
                }
                return link.map { ($0, isDirectory) }
            }
            guard !Task.isCancelled, let self, self.probedCell?.row == row, self.probedCell?.text == text else { return }
            guard let (link, isDirectory) = found, case .file(let path, let line, let col) = link.kind else {
                self.hover = nil
                self.underline.isHidden = true
                self.tip.isHidden = true
                return
            }
            let columns = TerminalLinkDetector.columns(of: link.range, in: text)
            self.show(
                Hover(target: TerminalFileTarget(path: path, line: line, column: col, isDirectory: isDirectory), row: row, columns: columns),
                cellSize: size)
        }
    }

    private func show(_ next: Hover, cellSize: CGSize) {
        hover = next
        let x = CGFloat(next.columns.lowerBound) * cellSize.width
        let width = CGFloat(next.columns.count) * cellSize.width
        let top = surface.bounds.height - CGFloat(next.row) * cellSize.height
        underline.frame = CGRect(x: x, y: top - cellSize.height + 1, width: width, height: 1)
        underline.isHidden = false
        tip.configure(isDirectory: next.target.isDirectory)
        let size = tip.fittingSize
        let above = top + DS.Space.s1
        let y = above + size.height <= surface.bounds.height ? above : top - cellSize.height - DS.Space.s1 - size.height
        tip.frame = CGRect(x: min(x, max(0, surface.bounds.width - size.width)), y: y, width: size.width, height: size.height)
        tip.isHidden = false
    }

    // MARK: Clique

    /// ⌘-clique sobre um caminho já resolvido pelo hover: o evento é consumido (não chega ao SwiftTerm nem ao programa).
    func claimClick(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), let hover, let hit = cell(at: event.locationInWindow),
            hit.row == hover.row, hover.columns.contains(hit.col)
        else { return false }
        claimed = hover
        return true
    }

    func finishClaimedClick(_ event: NSEvent) {
        guard let target = claimed?.target else { return }
        claimed = nil
        onOpen?(target, event.modifierFlags.contains(.shift) ? .system : .inApp)
    }

    var hasClaimedClick: Bool { claimed != nil }

    /// Caminho sob o mouse neste instante (já resolvido em disco); usado pelos testes.
    var hoveredTarget: TerminalFileTarget? { hover?.target }
}

/// Dica ao passar o mouse sobre um caminho: duas linhas "ação  atalho" (como no Orca). Não recebe cliques.
@MainActor
private final class LinkTipView: NSView {
    private let stack = NSStackView()
    private let primaryTitle = NSTextField(labelWithString: "")
    private let secondaryTitle = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = DS.ColorSpec.menuSolid.nsColor.cgColor
        layer?.borderColor = DS.ColorSpec.borderStrong.nsColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = DS.Radius.sm
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = DS.Space.s0_5
        stack.edgeInsets = NSEdgeInsets(top: DS.Space.s1_5, left: DS.Space.s2, bottom: DS.Space.s1_5, right: DS.Space.s2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        stack.addArrangedSubview(row(primaryTitle, shortcut: "⌘" + String(localized: "Click", bundle: .module)))
        stack.addArrangedSubview(row(secondaryTitle, shortcut: "⇧⌘" + String(localized: "Click", bundle: .module)))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }  // required init?(coder:) não usado

    private func row(_ title: NSTextField, shortcut: String) -> NSView {
        title.font = DS.Font.small.nsFont
        title.textColor = DS.ColorSpec.textPrimary.nsColor
        let key = NSTextField(labelWithString: shortcut)
        key.font = DS.Font.small.nsFont
        key.textColor = DS.ColorSpec.textTertiary.nsColor
        let row = NSStackView(views: [title, key])
        row.orientation = .horizontal
        row.spacing = DS.Space.s4
        return row
    }

    func configure(isDirectory: Bool) {
        primaryTitle.stringValue = isDirectory ? String(localized: "Open folder", bundle: .module) : String(localized: "Open file", bundle: .module)
        secondaryTitle.stringValue =
            isDirectory ? String(localized: "Reveal in Finder", bundle: .module) : String(localized: "Open with default app", bundle: .module)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
