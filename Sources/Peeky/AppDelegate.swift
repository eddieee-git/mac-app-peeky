import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// One menu bar icon per group.
    private var statusItems: [UUID: NSStatusItem] = [:]
    private var taskbar: TaskbarController!
    private var settingsWindow: NSWindow?
    private var hotKeys: [HotKey] = []
    private var refreshWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private let prefs = Preferences.shared

    private static let numberKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                     kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    func applicationDidFinishLaunching(_ notification: Notification) {
        taskbar = TaskbarController(openSettings: { [weak self] in self?.showSettings() })

        // @Published emits the new value before it is stored, so pass it along explicitly.
        prefs.$groups
            .sink { [weak self] groups in self?.syncGroups(groups) }
            .store(in: &cancellables)

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(self, selector: #selector(appsChanged), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(appsChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/Library/Logs/Peeky.log")
        ItemStore.log("launch path=\(Bundle.main.bundlePath) axTrusted=\(AX.isTrusted) preflight=\(CGPreflightScreenCaptureAccess())")
        ItemStore.shared.checkScreenCapture()
        if !AX.isTrusted || !prefs.hasLaunchedBefore {
            prefs.hasLaunchedBefore = true
            showSettings()
            if !AX.isTrusted { AX.requestTrust() }
        }
        ItemStore.shared.refresh()
        Updater.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
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
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.autosaveName = "PeekyGroup-\(group.id.uuidString)"
                item.button?.target = self
                item.button?.action = #selector(statusItemClicked(_:))
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                item.button?.identifier = NSUserInterfaceItemIdentifier(group.id.uuidString)
                statusItems[group.id] = item
                return item
            }()
            item.button?.image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: group.name)
                ?? NSImage(systemSymbolName: "ellipsis.rectangle", accessibilityDescription: group.name)
            let shortcut = index < Self.numberKeys.count ? "⌃⌥\(index + 1)" : ""
            item.button?.toolTip = "Peeky – \(group.name) \(shortcut)"
        }

        // ⌃⌥B opens the first group, ⌃⌥1…9 open each group.
        hotKeys.removeAll()
        if let first = groups.first {
            addHotKey(kVK_ANSI_B, group: first.id)
        }
        for (index, group) in groups.prefix(Self.numberKeys.count).enumerated() {
            addHotKey(Self.numberKeys[index], group: group.id)
        }
    }

    private func addHotKey(_ key: Int, group: UUID) {
        if let hotKey = HotKey(keyCode: UInt32(key), modifiers: UInt32(controlKey | optionKey), action: { [weak self] in
            self?.toggleBar(group: group)
        }) {
            hotKeys.append(hotKey)
        }
    }

    @objc private func appsChanged() {
        // Apps add their status items a moment after launching; debounce and rescan.
        refreshWork?.cancel()
        let work = DispatchWorkItem { ItemStore.shared.refresh() }
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
        let name = prefs.groups.first { $0.id == group }?.name ?? "바"
        let open = menu.addItem(withTitle: "\(name) 열기", action: #selector(menuOpenGroup(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = group
        menu.addItem(withTitle: "새 그룹 추가", action: #selector(menuAddGroup), keyEquivalent: "").target = self
        menu.addItem(withTitle: "설정…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Peeky 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpenGroup(_ sender: NSMenuItem) {
        if let group = sender.representedObject as? UUID { toggleBar(group: group) }
    }

    @objc private func menuAddGroup() {
        prefs.addGroup()
        showSettings()
    }

    @objc private func menuSettings() { showSettings() }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Peeky 설정"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 720))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
