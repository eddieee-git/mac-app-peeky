import AppKit
@preconcurrency import ApplicationServices
import Combine

// MARK: - Panel & views

final class TaskbarPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
}

/// Scroll view that turns a normal (vertical) mouse wheel into horizontal movement.
final class HorizontalScrollView: NSScrollView {
    var onScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 14
            scroll(by: -event.scrollingDeltaY * factor, animated: false)
        } else {
            super.scrollWheel(with: event)
            onScroll?()
        }
    }

    var maxOffset: CGFloat { max(0, (documentView?.frame.width ?? 0) - contentView.bounds.width) }
    var offset: CGFloat { contentView.bounds.origin.x }

    func scroll(by dx: CGFloat, animated: Bool) {
        scroll(to: offset + dx, animated: animated)
    }

    func scroll(to x: CGFloat, animated: Bool) {
        var origin = contentView.bounds.origin
        origin.x = min(max(0, x), maxOffset)
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                ctx.allowsImplicitAnimation = true
                contentView.animator().setBoundsOrigin(origin)
            }, completionHandler: { [weak self] in
                guard let self else { return }
                self.reflectScrolledClipView(self.contentView)
                self.onScroll?()
            })
        } else {
            contentView.setBoundsOrigin(origin)
            reflectScrolledClipView(contentView)
            onScroll?()
        }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A single menu bar item inside the strip. Highlights on hover; drag to reorder.
final class ItemButton: NSButton {
    var onRightClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((NSEvent) -> Void)?
    var onDragEnded: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var isHovered = false { didSet { updateBackground() } }
    /// 키보드(← →)로 고른 아이콘.
    var isSelected = false { didSet { updateBackground() } }

    private func updateBackground() {
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
            : isHovered ? NSColor.labelColor.withAlphaComponent(0.13).cgColor : nil
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        wantsLayer = true
        layer?.cornerRadius = 6
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    /// 짧게 누르면 클릭, 4pt 넘게 끌면 순서 바꾸기.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = event.locationInWindow
        var dragging = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseDragged {
                if !dragging, hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > 4 {
                    dragging = true
                    isHovered = false
                    onDragBegan?()
                }
                if dragging { onDragMoved?(next) }
            } else {
                if dragging {
                    onDragEnded?()
                } else if let action {
                    NSApp.sendAction(action, to: target, from: self)
                }
                break
            }
        }
    }
}

// MARK: - Controller

@MainActor
final class TaskbarController: NSObject {
    private enum Metrics {
        static let height: CGFloat = 36
        static let padding: CGFloat = 6
        static let gap: CGFloat = 4
        static let arrowWidth: CGFloat = 22
        static let itemHeight: CGFloat = 26
        static let iconHeight: CGFloat = 20
        static let itemSpacing: CGFloat = 2
        static let rowSpacing: CGFloat = 2
        static let fallbackIconSize: CGFloat = 18
    }

    private let store = ItemStore.shared
    private let prefs = Preferences.shared
    private let hider: MenuBarHider
    private let openSettings: () -> Void
    private var draggedButton: ItemButton?

    private let panel: TaskbarPanel
    private let background = NSVisualEffectView()
    private let scrollView = HorizontalScrollView()
    private let strip = FlippedView()
    private let leftButton = NSButton()
    private let rightButton = NSButton()
    private let settingsButton = NSButton()
    /// 지금 바에 놓인 아이콘 버튼(바 순서대로)과 키보드로 고른 위치.
    private var itemButtons: [ItemButton] = []
    private var selectedIndex: Int?
    private var perRowCount = 1
    private let emptyLabel = NSTextField(labelWithString: "")

    private var anchorRightX: CGFloat?
    private var anchorScreen: NSScreen?
    private var mouseMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var rebuildScheduled = false

    var isVisible: Bool { panel.isVisible }

    init(hider: MenuBarHider, openSettings: @escaping () -> Void) {
        self.hider = hider
        self.openSettings = openSettings
        panel = TaskbarPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: Metrics.height),
                             styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: true)
        super.init()
        setUpPanel()

        // Re-layout whenever items, captured images or preferences change while visible.
        store.objectWillChange.sink { [weak self] _ in self?.scheduleRebuild() }.store(in: &cancellables)
        prefs.objectWillChange.sink { [weak self] _ in self?.scheduleRebuild() }.store(in: &cancellables)
    }

    private func setUpPanel() {
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }

        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        panel.contentView = background

        configureIconButton(leftButton, symbol: "chevron.left", tip: L("왼쪽으로"), action: #selector(scrollLeft))
        configureIconButton(rightButton, symbol: "chevron.right", tip: L("오른쪽으로"), action: #selector(scrollRight))
        configureIconButton(settingsButton, symbol: "gearshape", tip: L("설정"), action: #selector(settingsTapped))

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = strip
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.onScroll = { [weak self] in self?.updateArrows() }
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor

        [leftButton, scrollView, rightButton, settingsButton, emptyLabel].forEach(background.addSubview)
    }

    private func configureIconButton(_ button: NSButton, symbol: String, tip: String, action: Selector) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        button.toolTip = tip
        button.target = self
        button.action = action
    }

    // MARK: Show / hide

    /// Group whose items the bar is showing.
    private(set) var groupID: UUID?

    /// - Parameter anchor: frame (AppKit coordinates) of the group's status item, if it is visible.
    func toggle(group: UUID, anchor: NSRect?) {
        if isVisible && groupID == group { hide() } else { show(group: group, anchor: anchor) }
    }

    func show(group: UUID, anchor: NSRect?) {
        groupID = group
        selectedIndex = nil
        let mouse = NSEvent.mouseLocation
        if let anchor, let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }),
           !NotchGeometry.isHidden(CGRect(x: anchor.minX, y: 0, width: anchor.width, height: 1)) {
            anchorScreen = screen
            anchorRightX = anchor.maxX
        } else {
            anchorScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            anchorRightX = nil
        }

        rebuild()
        scrollView.scroll(to: scrollView.maxOffset, animated: false) // start at the right, nearest the visible items
        panel.orderFrontRegardless()
        panel.makeKey()
        installMouseMonitor()

        // Positions change when apps add/remove items; rescan the known apps every time the bar opens,
        // and only capture icons this bar shows.
        store.refresh(captureIDs: Set(store.barItems(in: group).map(\.id)))
    }

    func hide() {
        panel.orderOut(nil)
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    // MARK: Layout

    private func scheduleRebuild() {
        guard !rebuildScheduled, draggedButton == nil else { return }
        rebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rebuildScheduled = false
            if self.isVisible { self.rebuild() }
        }
    }

    private func rebuild() {
        let wasAtEnd = scrollView.offset >= scrollView.maxOffset - 1
        strip.subviews.forEach { $0.removeFromSuperview() }

        // Split items into 1–3 rows (in menu bar order), each row filled left → right.
        let items = store.barItems(in: groupID)
        let rowCount = max(1, min(prefs.rowCount(for: groupID), items.count))
        let perRow = Int((Double(items.count) / Double(rowCount)).rounded(.up))
        perRowCount = max(perRow, 1)
        itemButtons = []
        var rowX = [CGFloat](repeating: 0, count: rowCount)
        for (index, item) in items.enumerated() {
            let row = index / max(perRow, 1)
            let button = makeButton(for: item)
            itemButtons.append(button)
            button.frame.origin = CGPoint(x: rowX[row], y: CGFloat(row) * (Metrics.itemHeight + Metrics.rowSpacing))
            strip.addSubview(button)
            rowX[row] = button.frame.maxX + Metrics.itemSpacing
        }
        let contentWidth = max(0, (rowX.max() ?? 0) - Metrics.itemSpacing)
        let stripHeight = CGFloat(rowCount) * Metrics.itemHeight + CGFloat(rowCount - 1) * Metrics.rowSpacing
        let panelHeight = stripHeight + Metrics.padding * 2
        strip.frame = NSRect(x: 0, y: 0, width: contentWidth, height: stripHeight)

        let emptyText: String? = !AX.isTrusted ? L("손쉬운 사용 권한이 필요해요 — ⚙︎ 눌러 설정")
            : items.isEmpty ? L("숨긴 아이콘이 없어요 — ⚙︎에서 「숨기기」를 고르세요") : nil
        emptyLabel.stringValue = emptyText ?? ""
        emptyLabel.isHidden = emptyText == nil
        emptyLabel.sizeToFit()

        let stripWidth = emptyText != nil ? emptyLabel.frame.width : min(contentWidth, CGFloat(prefs.maxStripWidth))
        let overflow = contentWidth > stripWidth + 0.5

        // [‹] [ strip ] [›]  — arrows only when there is something to scroll to.
        // 설정(⚙) 버튼은 바가 비어 있을 때(권한 필요, 숨긴 아이콘 없음)만 안내 옆에 둔다.
        // 평소에는 Peeky 아이콘 오른쪽 클릭 → 설정으로 연다.
        let showsGear = emptyText != nil
        var cx = Metrics.padding
        let midY = panelHeight / 2
        leftButton.isHidden = !overflow
        rightButton.isHidden = !overflow
        if overflow {
            leftButton.frame = NSRect(x: cx, y: midY - 11, width: Metrics.arrowWidth, height: 22)
            cx += Metrics.arrowWidth + Metrics.gap
        }
        scrollView.frame = NSRect(x: cx, y: Metrics.padding, width: stripWidth, height: stripHeight)
        scrollView.isHidden = emptyText != nil
        emptyLabel.frame.origin = CGPoint(x: cx, y: midY - emptyLabel.frame.height / 2)
        cx += stripWidth + Metrics.gap
        if overflow {
            rightButton.frame = NSRect(x: cx, y: midY - 11, width: Metrics.arrowWidth, height: 22)
            cx += Metrics.arrowWidth + Metrics.gap
        }
        settingsButton.isHidden = !showsGear
        if showsGear {
            settingsButton.frame = NSRect(x: cx, y: midY - 11, width: 22, height: 22)
            cx += 22 + Metrics.padding
        } else {
            cx += Metrics.padding - Metrics.gap
        }

        positionPanel(width: cx, height: panelHeight)
        // 다시 그린 뒤에도 고른 아이콘을 표시한다(없어졌으면 지운다).
        if let index = selectedIndex, !itemButtons.indices.contains(index) { selectedIndex = nil }
        for (i, button) in itemButtons.enumerated() { button.isSelected = i == selectedIndex }
        if wasAtEnd { scrollView.scroll(to: scrollView.maxOffset, animated: false) }
        updateArrows()
    }

    private func makeButton(for item: MenuBarItem) -> ItemButton {
        let button = ItemButton(frame: .zero)
        let width: CGFloat
        if let captured = store.image(for: item) {
            let scale = Metrics.iconHeight / max(captured.size.height, 1)
            let size = NSSize(width: captured.size.width * scale, height: Metrics.iconHeight)
            let image = captured.copy() as! NSImage
            image.size = size
            button.image = image
            button.contentTintColor = image.isTemplate ? .labelColor : nil
            width = size.width + 4
        } else {
            let icon = (item.appIcon?.copy() as? NSImage) ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
            if icon.isTemplate {
                // macOS 기본 항목의 기호: 비율을 지키고 메뉴바 글자색으로.
                button.image = icon.withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? icon
                button.contentTintColor = .labelColor
            } else {
                icon.size = NSSize(width: Metrics.fallbackIconSize, height: Metrics.fallbackIconSize)
                button.image = icon
            }
            width = Metrics.fallbackIconSize + 12
        }
        button.frame.size = NSSize(width: width, height: Metrics.itemHeight)
        let status = item.status(hiding: prefs.hideInMenuBar, unmovable: store.unmovableIDs.contains(item.id))
        button.toolTip = item.displayName + (status.map { "  (\($0.text))" } ?? "") + L("\n끌어서 순서 바꾸기")
        button.setAccessibilityLabel(item.displayName)
        button.target = self
        button.action = #selector(itemClicked(_:))
        button.identifier = NSUserInterfaceItemIdentifier(item.id)
        button.onRightClick = { [weak self] in self?.activate(item, secondary: true) }
        button.onDragBegan = { [weak self, weak button] in if let button { self?.dragBegan(button) } }
        button.onDragMoved = { [weak self] event in self?.dragMoved(event) }
        button.onDragEnded = { [weak self] in self?.dragEnded() }
        return button
    }

    private func positionPanel(width: CGFloat, height: CGFloat) {
        guard let screen = anchorScreen ?? NSScreen.main else { return }
        let menuBarHeight = NotchGeometry.menuBarHeight(on: screen)
        var right = anchorRightX ?? (screen.frame.maxX - 8)
        right = min(right, screen.frame.maxX - 6)
        let x = max(screen.frame.minX + 6, right - width)
        let y = screen.frame.maxY - menuBarHeight - height - 6
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func updateArrows() {
        leftButton.isEnabled = scrollView.offset > 0.5
        rightButton.isEnabled = scrollView.offset < scrollView.maxOffset - 0.5
    }

    @objc private func boundsChanged() { updateArrows() }

    // MARK: Actions

    @objc private func scrollLeft() { scrollView.scroll(by: -scrollView.contentView.bounds.width * 0.8, animated: true) }
    @objc private func scrollRight() { scrollView.scroll(by: scrollView.contentView.bounds.width * 0.8, animated: true) }

    @objc private func settingsTapped() {
        hide()
        openSettings()
    }

    @objc private func itemClicked(_ sender: ItemButton) {
        guard let id = sender.identifier?.rawValue, let item = store.items.first(where: { $0.id == id }) else { return }
        activate(item, secondary: false)
    }

    /// Opens the real item's menu. Accessibility "press" works even when the item sits under the notch.
    /// Items Peeky hid from the menu bar are unfolded first, then folded again after the menu closes.
    private func activate(_ item: MenuBarItem, secondary: Bool) {
        hide()
        let element = item.element
        hider.revealForClick {
            // Read the frame again: unfolding the divider moves items.
            let frame = AX.frame(element) ?? item.frame
            let clickable = frame.map { !NotchGeometry.isHidden($0) } ?? false
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
                // AXPress on a status item can block until its menu closes, so stay off the main thread.
                var ok = secondary ? AX.perform(element, kAXShowMenuAction) : false
                if !ok { ok = AX.perform(element, kAXPressAction) }
                if !ok, clickable, let frame {
                    AX.click(at: CGPoint(x: frame.midX, y: frame.midY), right: secondary)
                }
            }
        }
    }

    // MARK: Drag to reorder

    private func dragBegan(_ button: ItemButton) {
        draggedButton = button
        strip.addSubview(button) // bring to front
        button.alphaValue = 0.85
    }

    private func dragMoved(_ event: NSEvent) {
        guard let button = draggedButton else { return }
        let point = strip.convert(event.locationInWindow, from: nil)
        button.frame.origin = CGPoint(x: point.x - button.frame.width / 2,
                                      y: min(max(0, point.y - button.frame.height / 2), strip.frame.height - button.frame.height))
        // Scroll when dragging near either edge of the visible strip.
        let visible = scrollView.contentView.bounds
        if point.x < visible.minX + 16 { scrollView.scroll(by: -8, animated: false) }
        if point.x > visible.maxX - 16 { scrollView.scroll(by: 8, animated: false) }
    }

    private func dragEnded() {
        guard let dragged = draggedButton else { return }
        draggedButton = nil
        let others = strip.subviews.compactMap { $0 as? ItemButton }.filter { $0 !== dragged }
        let rowHeight = Metrics.itemHeight + Metrics.rowSpacing
        func slot(_ view: NSView) -> (Int, CGFloat) { (Int(view.frame.midY / rowHeight), view.frame.midX) }
        let ordered = others.sorted { slot($0) < slot($1) }
        let drop = slot(dragged)
        let insertAt = ordered.firstIndex { slot($0) > drop } ?? ordered.count
        var ids = ordered.compactMap { $0.identifier?.rawValue }
        if let id = dragged.identifier?.rawValue { ids.insert(id, at: insertAt) }
        prefs.setOrder(ids)
        rebuild()
    }

    /// ← → ↑ ↓로 아이콘을 고르고 Return·Space로 연다. 고른 아이콘이 안 보이면 그쪽으로 넘긴다.
    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: hide(); return true                         // esc
        case 123: moveSelection(by: -1); return true         // ←
        case 124: moveSelection(by: 1); return true          // →
        case 126: moveSelection(by: -perRowCount); return true   // ↑
        case 125: moveSelection(by: perRowCount); return true    // ↓
        case 36, 49, 76:                                     // Return, Space, Enter
            guard let index = selectedIndex, itemButtons.indices.contains(index) else { return false }
            itemClicked(itemButtons[index])
            return true
        default: return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !itemButtons.isEmpty else { return }
        let next: Int
        if let current = selectedIndex {
            next = min(max(0, current + delta), itemButtons.count - 1)
        } else {
            next = delta < 0 ? itemButtons.count - 1 : 0
        }
        select(next)
    }

    private func select(_ index: Int?) {
        selectedIndex = index
        for (i, button) in itemButtons.enumerated() { button.isSelected = i == index }
        guard let index, itemButtons.indices.contains(index) else { return }
        let frame = itemButtons[index].frame
        let visible = scrollView.contentView.bounds
        if frame.minX < visible.minX {
            scrollView.scroll(to: frame.minX - 8, animated: true)
        } else if frame.maxX > visible.maxX {
            scrollView.scroll(to: frame.maxX - visible.width + 8, animated: true)
        }
    }
}
