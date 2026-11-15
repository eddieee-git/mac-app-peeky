import AppKit

/// 메뉴바에서 항목을 실제로 숨긴다. 구분선 상태 아이콘(│)을 아주 길게 늘리면, 그 왼쪽에 있는 항목이
/// 화면 밖으로 밀려난다. 무엇을 숨길지는 사용자가 ⌘를 누른 채 아이콘을 구분선 왼쪽으로 끌어 정한다.
/// 숨긴 항목은 Peeky 바에서 누를 수 있고, 누를 때는 잠깐 펼쳤다가 다시 접는다.
@MainActor
final class MenuBarHider {
    static let autosaveName = "PeekyDivider"
    private static let collapsedLength: CGFloat = 10_000
    private static let expandedLength: CGFloat = 14

    private var divider: NSStatusItem?
    private var recollapseMonitor: Any?
    private var recollapseWork: DispatchWorkItem?
    private(set) var isCollapsed = false
    /// 접었을 때 화면 밖으로 밀려나면 안 되는 Peeky 자신의 상태 아이콘들.
    var protectedItems: () -> [NSStatusItem] = { [] }
    /// Peeky 아이콘이 구분선 왼쪽에 있어서 접기를 되돌렸을 때 부른다.
    var onBlocked: (() -> Void)?

    var isEnabled: Bool { divider != nil }

    /// `collapseNow`가 false면 펼친 채로 구분선만 만든다(처음 켰을 때 아이콘을 옮길 수 있게).
    func setEnabled(_ enabled: Bool, collapseNow: Bool = true) {
        if enabled, divider == nil {
            StatusItemPlacement.prepare(autosaveName: Self.autosaveName, position: StatusItemPlacement.dividerPosition)
            let item = NSStatusBar.system.statusItem(withLength: Self.expandedLength)
            item.autosaveName = Self.autosaveName
            item.button?.image = NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: L("Peeky 구분선"))?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
            item.button?.appearsDisabled = true
            item.button?.target = self
            item.button?.action = #selector(dividerClicked)
            item.button?.toolTip = L("Peeky 구분선 — 이 왼쪽의 항목은 메뉴바에서 숨겨요. 누르면 펼치기/접기")
            divider = item
            if collapseNow {
                // 메뉴바가 구분선 자리를 잡은 뒤에 접는다.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.collapse() }
            }
        } else if !enabled, let divider {
            NSStatusBar.system.removeStatusItem(divider)
            self.divider = nil
            isCollapsed = false
            cancelRecollapse()
        }
    }

    func collapse() {
        guard let divider else { return }
        cancelRecollapse()
        divider.length = Self.collapsedLength
        isCollapsed = true
        // Peeky 아이콘까지 밀려났으면 되돌린다. 그대로 두면 Peeky를 누를 방법이 없어진다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.isCollapsed, self.protectedItemIsHidden() else { return }
            self.expand()
            self.onBlocked?()
        }
    }

    private func protectedItemIsHidden() -> Bool {
        protectedItems().contains { item in
            guard let window = item.button?.window, window.isVisible else { return true }
            return NotchGeometry.isOffScreen(window.frame)
        }
    }

    func expand() {
        guard let divider else { return }
        divider.length = Self.expandedLength
        isCollapsed = false
    }

    @objc private func dividerClicked() {
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
        // 메뉴가 열린 동안에는 펼쳐 둔다. 다음 클릭(메뉴 고르기·닫기) 뒤에 접는다.
        recollapseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
            Task { @MainActor in self?.recollapseSoon(after: 0.8) }
        }
        // 아무것도 하지 않으면 잠시 뒤에 접는다.
        recollapseSoon(after: 20)
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
        if let recollapseMonitor { NSEvent.removeMonitor(recollapseMonitor) }
        recollapseMonitor = nil
    }
}

/// 새 상태 아이콘이 노치 쪽(왼쪽 끝)에 생겨 가려지지 않도록, 처음 만들 때만 오른쪽 가까이에 놓는다.
/// macOS가 `NSStatusItem Preferred Position <autosaveName>`에 기억하는 값(오른쪽 끝에서 잰 거리)을 미리 넣는다.
/// 사용자가 ⌘로 끌어 옮긴 뒤에는 그 값이 바뀌어 있으니 건드리지 않는다.
enum StatusItemPlacement {
    static let dividerPosition: Double = 400

    static func prepare(autosaveName: String, position: Double) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil { defaults.set(position, forKey: key) }
    }

    /// 그룹 아이콘 자리: 구분선보다 오른쪽, 그룹 순서대로.
    static func groupPosition(index: Int) -> Double { 200 + Double(index) * 30 }
}

/// 노치에 마우스를 잠깐 올리면 바를 연다.
@MainActor
final class HoverWatcher {
    private var timer: Timer?
    private var enteredAt: Date?
    private var firedThisVisit = false
    private let action: () -> Void
    private static let dwell: TimeInterval = 0.35

    init(action: @escaping () -> Void) { self.action = action }

    func setEnabled(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard let rect = NotchGeometry.notchRect else { return }
        let inside = rect.insetBy(dx: -4, dy: -2).contains(NSEvent.mouseLocation)
        guard inside else {
            enteredAt = nil
            firedThisVisit = false
            return
        }
        if enteredAt == nil { enteredAt = Date() }
        if !firedThisVisit, let enteredAt, Date().timeIntervalSince(enteredAt) >= Self.dwell {
            firedThisVisit = true
            action()
        }
    }
}
