import AgentBoxDesignSystem
import AgentBoxProtocol
import AppKit
import SwiftUI

/// Liga uma view AppKit à árvore de automação (`ctl ui tree`): o `UIElementStore` só vê o que passa por `.a11y(...)` do SwiftUI.
@MainActor
final class ElementRegistration {
    private let token = UUID()
    private weak var store: UIElementStore?

    init(store: UIElementStore?, id: A11yID, kind: String, label: String?, parent: A11yID?) {
        self.store = store
        store?.register(token, id: id, kind: kind, label: label, value: nil, action: nil, parent: parent)
    }

    /// `view` em coordenadas da janela, com o y do topo (o mesmo espaço dos frames do SwiftUI).
    func updateFrame(of view: NSView) {
        guard let window = view.window, let content = window.contentView else { return }
        let rect = view.convert(view.bounds, to: nil)
        let top = content.bounds.height - rect.maxY
        store?.updateFrame(token, CGRect(x: rect.minX, y: top, width: rect.width, height: rect.height))
    }

    func remove() { store?.unregister(token) }
}

/// Pane: a `TerminalHostView` com o chrome SwiftUI por cima (cabeçalho de 24, botões, banners). A view do terminal nunca
/// anima o próprio frame; só a opacidade (pane inativo a 0,8, M-308).
@MainActor
final class PaneContainerView: NSView {
    let terminalID: UUID
    let entry: TerminalEntry
    let chrome = PaneChromeModel()
    private let headerHost: NSHostingView<AnyView>
    private let floatingHost: NSHostingView<AnyView>
    private let bannerHost: NSHostingView<AnyView>
    private let cardHost: NSHostingView<AnyView>
    private let dim = NSView()
    private var tracking: NSTrackingArea?
    private var registrations: [ElementRegistration] = []
    private let elements: UIElementStore?
    private(set) var showsHeader = false

    override var isFlipped: Bool { true }

    init(entry: TerminalEntry, registry: ActionRegistry?, elements: UIElementStore?) {
        terminalID = entry.terminalID
        self.entry = entry
        self.elements = elements
        func host(_ view: some View) -> NSHostingView<AnyView> {
            let h = NSHostingView(
                rootView: AnyView(
                    view.environment(\.actionRegistry, registry).environment(\.elementStore, elements).environment(\.a11yParent, nil)))
            h.safeAreaRegions = []
            return h
        }
        headerHost = host(PaneHeaderView(model: chrome))
        floatingHost = host(PaneFloatingButtons(model: chrome))
        bannerHost = host(PaneBannerView(model: chrome))
        cardHost = host(PaneCardView(model: chrome))
        super.init(frame: .zero)
        chrome.terminalID = entry.terminalID
        wantsLayer = true
        layer?.masksToBounds = true
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(MotionTokens.Opacity.exitedDim).cgColor
        addSubview(entry.host)
        for v in [dim, headerHost, floatingHost, bannerHost, cardHost] { addSubview(v) }
        for v in [dim, headerHost, floatingHost, bannerHost, cardHost] as [NSView] { v.isHidden = true }
        updateTracking()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }  // required init?(coder:) não usado

    /// Só o pane visível aparece em `ctl ui tree`: os das outras tabs e sessões saem da árvore.
    func setTreeVisible(_ visible: Bool) {
        if !visible {
            teardown()
        } else if registrations.isEmpty {
            let id = terminalID.uuidString
            registrations = [
                ElementRegistration(store: elements, id: .pane(id), kind: "pane", label: nil, parent: .windowMain),
                ElementRegistration(store: elements, id: .paneTerminal(id), kind: "terminal", label: nil, parent: .pane(id)),
            ]
            needsLayout = true
        }
    }

    func teardown() {
        registrations.forEach { $0.remove() }
        registrations = []
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Hover

    private func updateTracking() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTracking()
    }

    override func mouseEntered(with event: NSEvent) { chrome.hovering = true }
    override func mouseExited(with event: NSEvent) { chrome.hovering = false }

    // MARK: Estado

    /// `multiPane`: a tab tem 2+ panes, então o cabeçalho de 24 aparece; com 1 pane só os botões flutuantes.
    func apply(title: String, provider: TerminalProvider, glyph: DSIndicatorGlyph, focused: Bool, multiPane: Bool, expanded: Bool, state: PaneRunState) {
        chrome.title = title
        chrome.provider = provider
        chrome.glyph = glyph
        chrome.focused = focused
        chrome.expanded = expanded
        chrome.state = state
        if case .failed(let detail) = state { chrome.errorDetail = detail }
        showsHeader = multiPane
        headerHost.isHidden = !multiPane
        floatingHost.isHidden = multiPane
        let banner: Bool
        let card: Bool
        switch state {
        case .interrupted, .closing(stuck: true): (banner, card) = (true, false)
        case .exited(let code, let signal): (banner, card) = code == 0 && signal == nil ? (true, false) : (false, true)
        case .failed: (banner, card) = (false, true)
        default: (banner, card) = (false, false)
        }
        bannerHost.isHidden = !banner
        cardHost.isHidden = !card
        var dimmed = false
        if card, case .exited = state { dimmed = true }
        dim.isHidden = !dimmed
        setHostAlpha(focused || multiPane == false ? 1 : MotionTokens.Opacity.inactivePane)
        needsLayout = true
    }

    private func setHostAlpha(_ alpha: CGFloat) {
        let host = entry.host
        guard host.alphaValue != alpha else { return }
        if MotionPolicy.shared.reduceMotion || window == nil {
            host.alphaValue = alpha
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MotionTokens.Duration.paneOpacity
                context.timingFunction = Motion.caTiming(MotionTokens.Easing.ease)
                host.animator().alphaValue = alpha
            }
        }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        entry.host.frame = bounds
        let w = bounds.width
        headerHost.frame = NSRect(x: 0, y: 0, width: w, height: PaneMetrics.headerHeight)
        let size = floatingHost.fittingSize
        floatingHost.frame = NSRect(x: max(0, w - size.width - DS.Space.s1), y: DS.Space.s1, width: min(size.width, w), height: size.height)
        let top = showsHeader ? PaneMetrics.headerHeight : 0
        bannerHost.frame = NSRect(x: 0, y: top, width: w, height: PaneMetrics.banner)
        dim.frame = bounds
        let cardSize = cardHost.fittingSize
        cardHost.frame = NSRect(
            x: ((w - cardSize.width) / 2).rounded(), y: ((bounds.height - cardSize.height) / 2).rounded(), width: cardSize.width, height: cardSize.height)
        if registrations.count == 2 {
            registrations[0].updateFrame(of: self)
            registrations[1].updateFrame(of: entry.host.surface)
        }
    }
}

/// Divisor entre dois panes: 3 pt visíveis (`paneDivider`), 9 de hit, cursor de resize por `addCursorRect`, arrasto imediato,
/// duplo clique iguala os dois lados (DS §12.23). Não grava a cada quadro: o modelo faz debounce de 300 ms e grava ao soltar.
@MainActor
final class PaneDividerView: NSView {
    private(set) var geometry: DividerGeometry
    private let model: WorkspaceModel
    private let line = NSView()
    private var registration: ElementRegistration?
    private var lastRatio: Double

    override var isFlipped: Bool { true }

    init(geometry: DividerGeometry, model: WorkspaceModel, elements: UIElementStore?) {
        self.geometry = geometry
        self.model = model
        lastRatio = geometry.ratio
        self.elements = elements
        super.init(frame: .zero)
        line.wantsLayer = true
        line.layer?.backgroundColor = DS.ColorSpec.paneDivider.nsColor.cgColor
        addSubview(line)
        setAccessibilityIdentifier(A11yID.paneDivider(geometry.secondLeadingPaneID.uuidString).rawValue)
    }

    private let elements: UIElementStore?

    func setTreeVisible(_ visible: Bool) {
        if !visible {
            registration?.remove()
            registration = nil
        } else if registration == nil {
            registration = ElementRegistration(
                store: elements, id: .paneDivider(geometry.secondLeadingPaneID.uuidString), kind: "divider", label: nil, parent: .windowMain)
            needsLayout = true
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }  // required init?(coder:) não usado

    func teardown() {
        registration?.remove()
        registration = nil
    }

    func update(_ geometry: DividerGeometry) {
        self.geometry = geometry
        needsLayout = true
        window?.invalidateCursorRects(for: self)
    }

    override func layout() {
        super.layout()
        switch geometry.axis {
        case .horizontal:
            line.frame = NSRect(x: (bounds.width - PaneLayout.dividerThickness) / 2, y: 0, width: PaneLayout.dividerThickness, height: bounds.height)
        case .vertical:
            line.frame = NSRect(x: 0, y: (bounds.height - PaneLayout.dividerThickness) / 2, width: bounds.width, height: PaneLayout.dividerThickness)
        }
        registration?.updateFrame(of: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: geometry.axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { model.equalizeDivider(at: geometry.path) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let area = superview else { return }
        let point = area.convert(event.locationInWindow, from: nil)
        let c = geometry.container
        let t = PaneLayout.dividerThickness
        let ratio: Double
        switch geometry.axis {
        case .horizontal: ratio = Double((point.x - c.minX - t / 2) / max(1, c.width - t))
        case .vertical: ratio = Double((point.y - c.minY - t / 2) / max(1, c.height - t))
        }
        lastRatio = ratio
        model.setRatio(at: geometry.path, ratio: ratio, final: false)
    }

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount < 2 else { return }
        model.setRatio(at: geometry.path, ratio: lastRatio, final: true)
    }
}

/// Área dos panes (abaixo da tab row): mantém uma `PaneContainerView` por terminal da sessão, posiciona a da tab ativa pelo
/// layout em árvore e esconde as outras. Terminais nunca são recriados por trocar de tab ou sessão (04 MA6).
@MainActor
final class PaneAreaView: NSView {
    private let model: WorkspaceModel
    private let registry: ActionRegistry?
    private let elements: UIElementStore?
    private let router: TerminalActionRouter?
    private var containers: [UUID: PaneContainerView] = [:]
    private var dividers: [UUID: PaneDividerView] = [:]
    private let emptyHost: NSHostingView<AnyView>
    private var readyNotified: Set<UUID> = []
    private weak var lastFocusedHost: TerminalHostView?

    override var isFlipped: Bool { true }

    init(model: WorkspaceModel, registry: ActionRegistry?, elements: UIElementStore?, router: TerminalActionRouter?) {
        self.model = model
        self.registry = registry
        self.elements = elements
        self.router = router
        emptyHost = NSHostingView(
            rootView: AnyView(
                PaneEmptyView(model: model).environment(\.actionRegistry, registry).environment(\.elementStore, elements)
                    .environment(\.a11yParent, nil)))
        emptyHost.safeAreaRegions = []
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = DS.ColorSpec.canvas.nsColor.cgColor
        addSubview(emptyHost)
        emptyHost.isHidden = true
        model.addListener { [weak self] in self?.modelChanged() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }  // required init?(coder:) não usado

    private func modelChanged() {
        reconcile()
        needsLayout = true
    }

    /// Cria e remove containers conforme os terminais carregados.
    private func reconcile() {
        let wanted = model.loadedTerminalIDs
        for id in containers.keys where !wanted.contains(id) {
            containers[id]?.teardown()
            containers[id]?.removeFromSuperview()
            containers[id] = nil
            readyNotified.remove(id)
        }
        for id in wanted where containers[id] == nil {
            let container = PaneContainerView(entry: model.runtime.entry(for: id), registry: registry, elements: elements)
            addSubview(container, positioned: .below, relativeTo: nil)
            containers[id] = container
        }
    }

    override func layout() {
        super.layout()
        model.contentSize = bounds.size
        emptyHost.frame = bounds
        position()
    }

    private func position() {
        let sessionLoaded = model.isLoaded
        let tab = model.activeTab
        let noTabs = sessionLoaded && model.tabs.isEmpty
        emptyHost.isHidden = !noTabs
        for c in containers.values {
            c.isHidden = true
            c.setTreeVisible(false)
        }
        var visibleDividers: Set<UUID> = []
        defer {
            for (id, d) in dividers where !visibleDividers.contains(id) {
                d.isHidden = true
                d.setTreeVisible(false)
            }
        }
        guard sessionLoaded, let tab else { return }

        let expandedPane = model.expandedPane(in: tab)
        let multi = tab.layout.leafCount > 1
        let arrangement = tab.layout.arrangement(in: bounds)
        var order: [UUID] = []
        for pane in tab.layout.panes {
            guard case .terminal(let terminalID) = pane.content, let container = containers[terminalID], let terminal = model.terminal(terminalID) else { continue }
            if let expandedPane, expandedPane != pane.id { continue }
            let frame = expandedPane == nil ? (arrangement.panes[pane.id] ?? .zero) : bounds
            guard frame.width > 0, frame.height > 0 else { continue }
            container.isHidden = false
            container.setTreeVisible(true)
            if container.frame != frame { container.frame = frame }
            container.apply(
                title: model.displayTitleOfPane(terminalID), provider: terminal.provider,
                glyph: SidebarProjector.glyph(for: terminal).glyph, focused: model.focusedTerminalID == terminalID,
                multiPane: multi, expanded: expandedPane != nil, state: model.paneState(terminalID))
            order.append(terminalID)
        }
        if expandedPane == nil {
            for geometry in arrangement.dividers {
                let key = geometry.secondLeadingPaneID
                let view: PaneDividerView
                if let existing = dividers[key] { view = existing; view.update(geometry) } else {
                    view = PaneDividerView(geometry: geometry, model: model, elements: elements)
                    dividers[key] = view
                    addSubview(view)
                }
                visibleDividers.insert(key)
                view.isHidden = false
                view.setTreeVisible(true)
                let hit = PaneMetrics.dividerHit
                let rect = geometry.rect
                let frame = geometry.axis == .horizontal
                    ? NSRect(x: rect.midX - hit / 2, y: rect.minY, width: hit, height: rect.height)
                    : NSRect(x: rect.minX, y: rect.midY - hit / 2, width: rect.width, height: hit)
                if view.frame != frame { view.frame = frame }
            }
        }
        // Foco: o roteador de ações de terminal e o first responder acompanham o pane focado.
        if let focusedID = model.focusedTerminalID, let container = containers[focusedID], !container.isHidden {
            let host = container.entry.host
            router?.focus(host)
            if lastFocusedHost !== host {
                lastFocusedHost = host
                let editing = window?.firstResponder is NSText
                if !editing { DispatchQueue.main.async { host.focusTerminal() } }
            }
        }
        // Primeiro layout com tamanho: lança o terminal novo ou religa o que o daemon manteve vivo.
        for id in order where !readyNotified.contains(id) {
            guard let container = containers[id] else { continue }
            container.layoutSubtreeIfNeeded()
            readyNotified.insert(id)
            model.paneReady(id)
        }
    }
}
