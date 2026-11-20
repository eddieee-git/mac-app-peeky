import AppKit

/// 메뉴바에서 항목을 실제로 숨긴다. 구분선 상태 아이콘(│)을 아주 길게 늘리면, 그 왼쪽에 있는 항목이
/// 화면 밖으로 밀려난다. 무엇을 숨길지는 사용자가 ⌘를 누른 채 아이콘을 구분선 왼쪽으로 끌어 정한다.
/// 숨긴 항목은 Peeky 바에서 누를 수 있고, 누를 때는 잠깐 펼쳤다가 다시 접는다.
@MainActor
final class MenuBarHider {
    static let autosaveName = "PeekyDivider"
    static let toggleAutosaveName = "PeekyToggle"
    private static let collapsedLength: CGFloat = 10_000
    /// 펼쳤을 때 구분선은 거의 자리를 차지하지 않는 투명한 막대다. 기준은 › 버튼으로 보여 준다.
    private static let expandedLength: CGFloat = 1

    /// 늘어나는 구분선. 접으면 그림이 긴 막대 가운데(화면 밖)로 가므로 그림을 지운다.
    private var divider: NSStatusItem?
    /// 구분선 바로 오른쪽의 펼치기/접기 버튼. 접었을 때도 보인다.
    private var toggle: NSStatusItem?
    private var recollapseMonitor: Any?
    private var recollapseWork: DispatchWorkItem?
    private var menuWatch: Timer?
    private(set) var isCollapsed = false
    /// 접었을 때 화면 밖으로 밀려나면 안 되는 Peeky 자신의 상태 아이콘들.
    var protectedItems: () -> [NSStatusItem] = { [] }
    /// Peeky 아이콘이 구분선 왼쪽에 있어서 접기를 되돌렸을 때 부른다.
    var onBlocked: (() -> Void)?
    /// ‹ › 버튼이나 구분선을 오른쪽 클릭했을 때 메뉴를 띄운다.
    var onRightClick: ((NSStatusItem) -> Void)?

    var isEnabled: Bool { divider != nil }
    /// 구분선과 ‹ › 버튼의 지금 자리(AppKit 좌표, x는 CG와 같다).
    var dividerFrame: NSRect? { divider?.button?.window?.frame }
    var toggleFrame: NSRect? { toggle?.button?.window?.frame }
    /// 메뉴바가 지금 화면에 보이는지. 전체 화면 앱이나 「메뉴 막대 자동 숨김」으로 가려졌으면 false.
    var menuBarIsVisible: Bool {
        guard let window = toggle?.button?.window, window.isVisible,
              window.occlusionState.contains(.visible) else { return false }
        return NSScreen.screens.contains { $0.frame.contains(NSPoint(x: window.frame.midX, y: window.frame.midY)) }
    }

    /// `collapseNow`가 false면 펼친 채로 구분선만 만든다(처음 켰을 때 아이콘을 옮길 수 있게).
    func setEnabled(_ enabled: Bool, collapseNow: Bool = true) {
        if enabled, divider == nil {
            StatusItemPlacement.prepare(autosaveName: Self.autosaveName, position: StatusItemPlacement.dividerPosition)
            StatusItemPlacement.prepare(autosaveName: Self.toggleAutosaveName, position: StatusItemPlacement.togglePosition)
            // 펼치기 버튼을 먼저 만들어야 구분선이 그 왼쪽에 자리 잡는다.
            let toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            toggle.autosaveName = Self.toggleAutosaveName
            toggle.button?.target = self
            toggle.button?.action = #selector(toggleClicked(_:))
            toggle.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            self.toggle = toggle

            let item = NSStatusBar.system.statusItem(withLength: Self.expandedLength)
            item.autosaveName = Self.autosaveName
            item.button?.appearsDisabled = true
            item.button?.target = self
            item.button?.action = #selector(toggleClicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            divider = item
            updateAppearance()
            if collapseNow {
                // 메뉴바가 구분선 자리를 잡은 뒤에 접는다.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.collapse() }
            }
        } else if !enabled, let divider {
            NSStatusBar.system.removeStatusItem(divider)
            if let toggle { NSStatusBar.system.removeStatusItem(toggle) }
            self.divider = nil
            self.toggle = nil
            isCollapsed = false
            cancelRecollapse()
        }
    }

    private func updateAppearance() {
        toggle?.button?.image = NSImage(systemSymbolName: isCollapsed ? "chevron.compact.left" : "chevron.compact.right",
                                        accessibilityDescription: isCollapsed ? L("숨긴 항목 펼치기") : L("숨기기"))
        toggle?.button?.toolTip = isCollapsed ? L("숨긴 항목 펼치기") : L("› 왼쪽 아이콘 숨기기")
    }

    /// 숨기기 전에 아이콘을 캡처해 둔 뒤 접는다. 캡처가 늦어도 3초 뒤에는 접는다.
    func collapse() {
        guard divider != nil else { return }
        cancelRecollapse()
        var done = false
        let finish: @MainActor () -> Void = { [weak self] in
            guard !done else { return }
            done = true
            self?.applyCollapse()
        }
        ItemStore.shared.prepareForHiding(completion: finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { finish() } }
    }

    private func applyCollapse() {
        guard let divider else { return }
        divider.length = Self.collapsedLength
        isCollapsed = true
        updateAppearance()
        // Peeky 아이콘까지 밀려났으면 되돌린다. 그대로 두면 Peeky를 누를 방법이 없어진다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.isCollapsed else { return }
            self.logFrames("after-collapse")
            guard self.protectedItemIsHidden() else { return }
            self.expand()
            self.onBlocked?()
        }
    }

    private func logFrames(_ when: String) {
        func describe(_ item: NSStatusItem?) -> String {
            guard let w = item?.button?.window else { return "no-window" }
            return "\(w.frame) visible=\(w.isVisible)"
        }
        ItemStore.log("hider \(when) divider=\(describe(divider)) toggle=\(describe(toggle))")
        for item in protectedItems() { ItemStore.log("hider \(when) peeky=\(describe(item))") }
    }

    private func protectedItemIsHidden() -> Bool {
        (protectedItems() + [toggle].compactMap { $0 }).contains { item in
            guard let window = item.button?.window, window.isVisible else { return true }
            return NotchGeometry.isOffScreen(window.frame)
        }
    }

    func expand() {
        guard let divider else { return }
        divider.length = Self.expandedLength
        isCollapsed = false
        updateAppearance()
    }

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let item = [toggle, divider].compactMap { $0 }.first { $0.button === sender }
            if let item, let onRightClick { onRightClick(item); return }
        }
        isCollapsed ? expand() : collapse()
    }

    /// 숨긴 항목을 누르기 전에 잠깐 펼친다. 펼친 뒤 다음 클릭이 끝나면(메뉴를 닫으면) 다시 접는다.
    func revealForClick(_ action: @escaping () -> Void) {
        guard isEnabled, isCollapsed else { action(); return }
        expand()
        // 메뉴바가 다시 배치될 시간을 준다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            action()
            self?.scheduleRecollapse()
        }
    }

    private func scheduleRecollapse() {
        cancelRecollapse()
        // 열린 메뉴가 닫히면 바로 접는다. 메뉴 창은 화면 기록 권한 없이도 창 목록에서 층(level)으로 알아볼 수 있다.
        var sawMenu = false
        menuWatch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Self.menuIsOpen() {
                    sawMenu = true
                } else if sawMenu {
                    self.recollapseSoon(after: 0.2)
                }
            }
        }
        // 메뉴가 아니라 창이나 팝오버를 여는 앱도 있다: 다음 마우스 클릭 뒤에 접는다.
        recollapseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !Self.menuIsOpen() else { return }
                self.recollapseSoon(after: 0.8)
            }
        }
        // 아무것도 하지 않으면 잠시 뒤에 접는다.
        recollapseSoon(after: 20)
    }

    private static func menuIsOpen() -> Bool {
        let level = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowLayer as String] as? Int) == level }
    }

    private func recollapseSoon(after delay: TimeInterval) {
        recollapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.collapse() }
        recollapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelRecollapse() {
        recollapseWork?.cancel()
        recollapseWork = nil
        menuWatch?.invalidate()
        menuWatch = nil
        if let recollapseMonitor { NSEvent.removeMonitor(recollapseMonitor) }
        recollapseMonitor = nil
    }
}

/// 새 상태 아이콘이 노치 쪽(왼쪽 끝)에 생겨 가려지지 않도록, 처음 만들 때만 오른쪽 가까이에 놓는다.
/// macOS가 `NSStatusItem Preferred Position <autosaveName>`에 기억하는 값(오른쪽 끝에서 잰 거리)을 미리 넣는다.
/// 사용자가 ⌘로 끌어 옮긴 뒤에는 그 값이 바뀌어 있으니 건드리지 않는다.
enum StatusItemPlacement {
    static let dividerPosition: Double = 400
    static let togglePosition: Double = 380

    /// `force`면 사용자가 옮긴 자리도 덮어쓴다(「아이콘 자리 되돌리기」에서만).
    static func prepare(autosaveName: String, position: Double, force: Bool = false) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        let defaults = UserDefaults.standard
        if force || defaults.object(forKey: key) == nil { defaults.set(position, forKey: key) }
    }

    /// 그룹 아이콘 자리: 구분선보다 오른쪽, 그룹 순서대로.
    static func groupPosition(index: Int) -> Double { 200 + Double(index) * 30 }
}

/// Peeky 자신의 그룹 아이콘이 메뉴바에서 보이는지 확인한다. 노치 뒤에 있거나, 자리가 없어
/// macOS가 화면 밖으로 밀어냈거나, 시스템 설정에서 꺼져 창이 없으면 안 보이는 것으로 본다.
@MainActor
enum StatusIconCheck {
    /// AppDelegate가 채운다: (그룹 이름, 상태 아이콘)
    static var groupItems: () -> [(name: String, item: NSStatusItem)] = { [] }
    /// Peeky 아이콘·구분선·‹› 버튼을 처음 자리(오른쪽 끝 가까이, 그룹 → ‹› → 구분선 순)로 되돌린다.
    static var resetPositions: () -> Void = {}
    /// 「보이기 / 숨기기」에 맞게 메뉴바 아이콘을 다시 옮긴다.
    static var arrange: () -> Void = {}
    /// 「보이기」 아이콘을 맨 오른쪽(시계·제어 센터 바로 왼쪽)으로 옮긴다. 자리가 모자라도 가장 오래 보인다.
    static var bringToFront: (String) -> Void = { _ in }

    static func hiddenGroupNames() -> [String] {
        groupItems().filter { isHidden($0.item) }.map(\.name)
    }

    static func isHidden(_ item: NSStatusItem) -> Bool {
        guard let window = item.button?.window, window.isVisible, window.frame.width > 0 else { return true }
        return NotchGeometry.isHidden(window.frame)
    }
}
