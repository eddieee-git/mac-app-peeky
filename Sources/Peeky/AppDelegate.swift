import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// One menu bar icon per group.
    private var statusItems: [UUID: NSStatusItem] = [:]
    private var taskbar: TaskbarController!
    private let hider = MenuBarHider()
    private var settingsWindow: NSWindow?
    private var hotKeys: [HotKey] = []
    private var refreshWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private let prefs = Preferences.shared
    private var isArranging = false
    private var arrangeRetries = 0
    /// 지금까지 본 아이콘. 새 아이콘이 생기면 자리를 정리한다.
    private var seenItemIDs: Set<String>?

    private static let numberKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                     kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    func applicationDidFinishLaunching(_ notification: Notification) {
        taskbar = TaskbarController(hider: hider, openSettings: { [weak self] in self?.showSettings() })

        // @Published emits the new value before it is stored, so pass it along explicitly.
        prefs.$groups
            .sink { [weak self] groups in self?.syncGroups(groups) }
            .store(in: &cancellables)
        prefs.$hotKeyModifiers
            .dropFirst()
            .sink { [weak self] _ in
                // 값이 저장된 뒤에 단축키와 아이콘 설명을 함께 다시 만든다.
                DispatchQueue.main.async { if let self { self.syncGroups(self.prefs.groups) } }
            }
            .store(in: &cancellables)
        hider.protectedItems = { [weak self] in self.map { Array($0.statusItems.values) } ?? [] }
        StatusIconCheck.groupItems = { [weak self] in
            guard let self else { return [] }
            return self.prefs.groups.compactMap { group in self.statusItems[group.id].map { (group.name, $0) } }
        }
        StatusIconCheck.resetPositions = { [weak self] in self?.resetIconPositions() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            ItemStore.log("status icons hidden=\(StatusIconCheck.hiddenGroupNames())")
            // `open -a Peeky --args --reset-icons`: 아이콘을 못 찾을 때 셸에서 자리를 되돌린다.
            if CommandLine.arguments.contains("--reset-icons") { StatusIconCheck.resetPositions() }
            if CommandLine.arguments.contains("--arrange") { StatusIconCheck.arrange() }
        }
        hider.onBlocked = { [weak self] in self?.showHiderBlocked() }
        hider.onRightClick = { [weak self] item in self?.showMenu(for: nil, on: item) }
        StatusIconCheck.arrange = { [weak self] in self?.arrangeMenuBar(collapseAfter: true) }
        // 시작할 때는 바로 접는다. 설정에서 새로 켜면 고른 대로 아이콘을 옮긴 뒤 접는다.
        hider.setEnabled(prefs.hideInMenuBar)
        prefs.$hideInMenuBar
            .dropFirst()
            .sink { [weak self] enabled in
                self?.hider.setEnabled(enabled, collapseNow: false)
                if enabled { self?.arrangeMenuBar(collapseAfter: true) }
            }
            .store(in: &cancellables)
        // 아이콘마다 「보이기 / 숨기기」를 바꾸면 잠시 뒤 한 번에 다시 정리한다.
        Publishers.Merge(prefs.$assignments.map { _ in () }, prefs.$excludedIDs.map { _ in () })
            .dropFirst(2)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self, self.prefs.hideInMenuBar else { return }
                self.arrangeMenuBar(collapseAfter: false)
            }
            .store(in: &cancellables)
        prefs.$diagnosticLog
            .dropFirst()
            .sink { enabled in if !enabled { try? FileManager.default.removeItem(atPath: ItemStore.logPath) } }
            .store(in: &cancellables)

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(self, selector: #selector(appsChanged), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(appsChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        try? FileManager.default.removeItem(atPath: ItemStore.logPath)
        ItemStore.log("launch \(Bundle.main.bundlePath) version=\(AppUpdater.shared.currentVersion) axTrusted=\(AX.isTrusted) preflight=\(CGPreflightScreenCaptureAccess())")
        ItemStore.shared.checkScreenCapture()
        if !AX.isTrusted || !prefs.hasLaunchedBefore {
            prefs.hasLaunchedBefore = true
            showSettings()
            if !AX.isTrusted { AX.requestTrust() }
        }
        ItemStore.shared.refresh(full: true) { [weak self] in self?.noteNewItems() }
        AppUpdater.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 접힌 구분선이 남아 다른 항목을 가리지 않게 펼쳐 둔다.
        hider.expand()
    }

    // MARK: Menu bar hiding

    /// 「숨기기」로 고른 아이콘은 › 왼쪽, 「보이기」는 오른쪽에 오도록 하나씩 옮긴다.
    /// 옮길 때마다 자리가 바뀌므로 매번 다시 읽는다. 마우스를 직접 움직이므로 안전하게:
    /// - 메뉴바가 안 보이면(전체 화면 등) 하지 않는다. 클릭이 앱 화면에 들어갈 수 있다.
    /// - 사용자가 마우스를 누르거나 움직이면 멈추고 잠시 뒤 다시 한다.
    /// - 옮긴 아이콘이 메뉴바에서 사라졌으면 멈추고 알린다.
    /// - 노치 뒤라 잡을 수 없거나 옮겨지지 않은 아이콘은 「옮기지 못함」으로 표시한다.
    private func arrangeMenuBar(collapseAfter: Bool) {
        guard hider.isEnabled, AX.isTrusted, !isArranging else { return }
        guard NSEvent.pressedMouseButtons == 0, hider.menuBarIsVisible else {
            retryArrangeLater(collapseAfter: collapseAfter)
            return
        }
        isArranging = true
        let wasCollapsed = hider.isCollapsed
        hider.expand()
        var tried = Set<String>()
        var unmovable = Set<String>()
        var moved = 0
        var pointer = NSEvent.mouseLocation
        var pending: (id: String, name: String, wasLeft: Bool)?

        func userIsBusy() -> Bool {
            let now = NSEvent.mouseLocation
            return NSEvent.pressedMouseButtons != 0 || hypot(now.x - pointer.x, now.y - pointer.y) > 3
                || !hider.menuBarIsVisible
        }
        func finish(interrupted: Bool) {
            isArranging = false
            ItemStore.shared.unmovableIDs = unmovable
            ItemStore.log("arrange: moved \(moved), unmovable \(unmovable.count), interrupted \(interrupted)")
            if collapseAfter || wasCollapsed { hider.collapse() }
            if interrupted { retryArrangeLater(collapseAfter: collapseAfter) } else { arrangeRetries = 0 }
        }
        func step(recheckedMissing: Bool = false) {
            ItemStore.shared.refresh(full: true) { [self] in
                if userIsBusy() { finish(interrupted: true); return }
                let items = ItemStore.shared.items
                guard let divider = hider.dividerFrame, let toggle = hider.toggleFrame else { finish(interrupted: false); return }
                if let last = pending {
                    guard let item = items.first(where: { $0.id == last.id }) else {
                        // 한 번 못 읽었을 수도 있으니 잠깐 뒤 다시 본다.
                        if !recheckedMissing {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                MainActor.assumeIsolated { step(recheckedMissing: true) }
                            }
                            return
                        }
                        finish(interrupted: false)
                        showIconLost(name: last.name)
                        return
                    }
                    pending = nil
                    if let frame = item.frame, (frame.midX < divider.midX) == last.wasLeft { unmovable.insert(item.id) }
                }
                guard tried.count < 40 else { finish(interrupted: false); return }
                let plan = nextMove(in: items, divider: divider, toggle: toggle, skipping: tried)
                unmovable.formUnion(plan.blocked)
                guard let (item, move) = plan.move else { finish(interrupted: false); return }
                tried.insert(item.id)
                moved += 1
                pending = (item.id, item.displayName, move.from.midX < divider.midX)
                ItemMover.perform([move]) {
                    MainActor.assumeIsolated { pointer = NSEvent.mouseLocation }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { step() } }
                }
            }
        }
        // 펼친 뒤 메뉴바가 자리를 잡을 시간을 준다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { step() } }
    }

    /// 사용자가 마우스를 쓰고 있었거나 메뉴바가 가려져 있었으면 조금 뒤 다시 한다(몇 번까지만).
    private func retryArrangeLater(collapseAfter: Bool) {
        guard arrangeRetries < 6 else { arrangeRetries = 0; return }
        arrangeRetries += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.prefs.hideInMenuBar else { return }
                self.arrangeMenuBar(collapseAfter: collapseAfter)
            }
        }
    }

    /// 옮겨야 할 다음 아이콘. 옮겨야 하지만 노치 뒤라 잡을 수 없는 아이콘은 `blocked`로 돌려준다.
    private func nextMove(in items: [MenuBarItem], divider: NSRect, toggle: NSRect, skipping: Set<String>)
        -> (move: (MenuBarItem, ItemMover.Move)?, blocked: Set<String>) {
        var blocked = Set<String>()
        for item in items where !skipping.contains(item.id) && !item.isFixed {
            guard let frame = item.frame, frame.width > 1 else { continue }
            let wantsHidden = prefs.group(for: item.id) != nil
            let isLeft = frame.midX < divider.midX
            guard wantsHidden != isLeft else { continue }
            if NotchGeometry.isHidden(frame) { blocked.insert(item.id); continue }
            let target = wantsHidden ? divider.minX - 3 : toggle.maxX + 3
            return ((item, .init(from: frame, toX: target)), blocked)
        }
        return (nil, blocked)
    }

    private func showIconLost(name: String) {
        let alert = NSAlert()
        alert.messageText = L("%@ 아이콘이 메뉴바에서 사라졌어요", name)
        alert.informativeText = L("옮기는 중에 메뉴바 밖에 놓였을 수 있어요. 그 앱을 종료했다가 다시 열면 돌아와요. 정리는 멈췄어요.")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showHiderBlocked() {
        let alert = NSAlert()
        alert.messageText = L("Peeky 아이콘이 › 버튼 왼쪽에 있어요")
        alert.informativeText = L("이대로 숨기면 Peeky 아이콘도 사라져서 펼쳐 두었어요. Peeky 아이콘을 오른쪽 끝으로 옮긴 뒤 › 버튼을 다시 눌러 주세요.")
        alert.addButton(withTitle: L("Peeky 아이콘을 오른쪽 끝으로 옮기기"))
        alert.addButton(withTitle: L("닫기"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { resetIconPositions() }
    }

    // MARK: Groups → status items & hot keys

    /// 아이콘을 지웠다가 처음 자리로 다시 만든다. 노치 뒤나 구분선 왼쪽에 들어가 못 찾을 때 쓴다.
    private func resetIconPositions() {
        let hiding = prefs.hideInMenuBar
        hider.setEnabled(false)
        for item in statusItems.values { NSStatusBar.system.removeStatusItem(item) }
        statusItems.removeAll()
        DispatchQueue.main.async { [self] in
            for (index, group) in prefs.groups.enumerated() {
                StatusItemPlacement.prepare(autosaveName: "PeekyGroup-\(group.id.uuidString)",
                                            position: StatusItemPlacement.groupPosition(index: index), force: true)
            }
            StatusItemPlacement.prepare(autosaveName: MenuBarHider.toggleAutosaveName,
                                        position: StatusItemPlacement.togglePosition, force: true)
            StatusItemPlacement.prepare(autosaveName: MenuBarHider.autosaveName,
                                        position: StatusItemPlacement.dividerPosition, force: true)
            syncGroups(prefs.groups)
            if hiding { hider.setEnabled(true, collapseNow: false) }
            ItemStore.log("status icons reset, hidden=\(StatusIconCheck.hiddenGroupNames())")
        }
    }

    private func syncGroups(_ groups: [ItemGroup]) {
        let ids = Set(groups.map(\.id))
        for (id, item) in statusItems where !ids.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            statusItems[id] = nil
            if taskbar.groupID == id { taskbar.hide() }
        }

        for (index, group) in groups.enumerated() {
            let item = statusItems[group.id] ?? {
                let name = "PeekyGroup-\(group.id.uuidString)"
                StatusItemPlacement.prepare(autosaveName: name, position: StatusItemPlacement.groupPosition(index: index))
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.autosaveName = name
                item.button?.target = self
                item.button?.action = #selector(statusItemClicked(_:))
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                item.button?.identifier = NSUserInterfaceItemIdentifier(group.id.uuidString)
                statusItems[group.id] = item
                return item
            }()
            item.button?.image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: group.name)
                ?? NSImage(systemSymbolName: "ellipsis.rectangle", accessibilityDescription: group.name)
            item.button?.toolTip = "Peeky – \(group.name) \(shortcutText(index: index))"
        }
        registerHotKeys(groups: groups, modifiers: prefs.hotKeyModifiers)
    }

    func shortcutText(index: Int) -> String {
        let modifiers = prefs.hotKeyModifiers
        guard modifiers != .off, index < Self.numberKeys.count else { return "" }
        return "\(modifiers.symbol)\(index + 1)"
    }

    /// <보조 키>+B는 첫 그룹, <보조 키>+1…9는 각 그룹을 연다.
    private func registerHotKeys(groups: [ItemGroup], modifiers: HotKeyModifiers) {
        hotKeys.removeAll()
        guard modifiers != .off else { return }
        if let first = groups.first {
            addHotKey(kVK_ANSI_B, modifiers: modifiers, group: first.id)
        }
        for (index, group) in groups.prefix(Self.numberKeys.count).enumerated() {
            addHotKey(Self.numberKeys[index], modifiers: modifiers, group: group.id)
        }
    }

    private func addHotKey(_ key: Int, modifiers: HotKeyModifiers, group: UUID) {
        if let hotKey = HotKey(keyCode: UInt32(key), modifiers: modifiers.carbonFlags, action: { [weak self] in
            self?.toggleBar(group: group)
        }) {
            hotKeys.append(hotKey)
        } else {
            ItemStore.log("hotkey \(modifiers.symbol)\(key) could not be registered (already in use?)")
        }
    }

    @objc private func appsChanged() {
        // Apps add their status items a moment after launching; debounce and rescan everything.
        ItemStore.shared.invalidate()
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            ItemStore.shared.refresh(full: true) {
                MainActor.assumeIsolated { self?.noteNewItems() }
            }
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// 새 앱의 아이콘은 macOS가 왼쪽 끝(숨기는 쪽)에 놓는다. 새 아이콘은 「보이기」가 기본이라 자리를 맞춘다.
    private func noteNewItems() {
        let ids = Set(ItemStore.shared.items.map(\.id))
        defer { seenItemIDs = (seenItemIDs ?? []).union(ids) }
        guard let seen = seenItemIDs, !ids.subtracting(seen).isEmpty, prefs.hideInMenuBar else { return }
        arrangeMenuBar(collapseAfter: false)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let raw = sender.identifier?.rawValue, let group = UUID(uuidString: raw) else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(for: group, on: statusItems[group])
        } else {
            toggleBar(group: group)
        }
    }

    private func toggleBar(group: UUID) {
        taskbar.toggle(group: group, anchor: statusItems[group]?.button?.window?.frame)
    }

    /// 그룹 아이콘이나 ‹ › 버튼·구분선을 오른쪽 클릭했을 때의 메뉴. 꼭 필요한 것만 둔다:
    /// 바 열기, (숨기기를 켰을 때) 펼치기/숨기기, 설정, (새 버전이 있을 때) 업데이트, 종료.
    private func showMenu(for group: UUID?, on statusItem: NSStatusItem?) {
        guard let statusItem else { return }
        taskbar.hide()
        let menu = NSMenu()
        let shown = prefs.groups.filter { group == nil || $0.id == group }
        for g in shown {
            let title = prefs.groups.count == 1 ? L("바 열기") : L("%@ 열기", g.name)
            let open = menu.addItem(withTitle: title, action: #selector(menuOpenGroup(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = g.id
        }
        if hider.isEnabled {
            let title = hider.isCollapsed ? L("숨긴 아이콘 보이기") : L("아이콘 다시 숨기기")
            menu.addItem(withTitle: title, action: #selector(menuToggleHidden), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("설정…"), action: #selector(menuSettings), keyEquivalent: ",").target = self
        if AppUpdater.shared.available != nil { menu.addItem(AppUpdater.shared.makeMenuItem()) }
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Peeky 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpenGroup(_ sender: NSMenuItem) {
        if let group = sender.representedObject as? UUID { toggleBar(group: group) }
    }

    @objc private func menuToggleHidden() {
        hider.isCollapsed ? hider.expand() : hider.collapse()
    }

    @objc private func menuSettings() { showSettings() }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = L("Peeky 설정")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 580, height: 760))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
