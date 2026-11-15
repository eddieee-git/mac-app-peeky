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
    private var hover: HoverWatcher!
    private var settingsWindow: NSWindow?
    private var hotKeys: [HotKey] = []
    private var refreshWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private let prefs = Preferences.shared

    private static let numberKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                     kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    func applicationDidFinishLaunching(_ notification: Notification) {
        taskbar = TaskbarController(hider: hider, openSettings: { [weak self] in self?.showSettings() })
        hover = HoverWatcher { [weak self] in
            guard let self, let first = self.prefs.groups.first, !self.taskbar.isVisible else { return }
            self.toggleBar(group: first.id)
        }

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
        prefs.$hideInMenuBar
            .sink { [weak self] enabled in self?.hider.setEnabled(enabled) }
            .store(in: &cancellables)
        prefs.$hoverToOpen
            .sink { [weak self] enabled in self?.hover.setEnabled(enabled) }
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
        ItemStore.log("launch \(Bundle.main.bundlePath) version=\(Updater.shared.currentVersion) axTrusted=\(AX.isTrusted) preflight=\(CGPreflightScreenCaptureAccess())")
        ItemStore.shared.checkScreenCapture()
        if !AX.isTrusted || !prefs.hasLaunchedBefore {
            prefs.hasLaunchedBefore = true
            showSettings()
            if !AX.isTrusted { AX.requestTrust() }
        }
        ItemStore.shared.refresh(full: true)
        Updater.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 접힌 구분선이 남아 다른 항목을 가리지 않게 펼쳐 둔다.
        hider.expand()
    }

    // MARK: Groups → status items & hot keys

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
        let work = DispatchWorkItem { ItemStore.shared.refresh(full: true) }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let raw = sender.identifier?.rawValue, let group = UUID(uuidString: raw) else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(for: group)
        } else {
            toggleBar(group: group)
        }
    }

    private func toggleBar(group: UUID) {
        taskbar.toggle(group: group, anchor: statusItems[group]?.button?.window?.frame)
    }

    private func showMenu(for group: UUID) {
        guard let statusItem = statusItems[group] else { return }
        taskbar.hide()
        let menu = NSMenu()
        let name = prefs.groups.first { $0.id == group }?.name ?? "Peeky"
        let open = menu.addItem(withTitle: L("%@ 열기", name), action: #selector(menuOpenGroup(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = group
        if hider.isEnabled {
            let title = hider.isCollapsed ? L("숨긴 항목 메뉴바에 펼치기") : L("메뉴바 항목 다시 숨기기")
            menu.addItem(withTitle: title, action: #selector(menuToggleHidden), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: L("새 그룹 추가"), action: #selector(menuAddGroup), keyEquivalent: "").target = self
        menu.addItem(withTitle: L("설정…"), action: #selector(menuSettings), keyEquivalent: ",").target = self
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

    @objc private func menuAddGroup() {
        prefs.addGroup()
        showSettings()
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
