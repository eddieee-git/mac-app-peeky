import AppKit
import ApplicationServices
import ScreenCaptureKit

/// One status item ("menu extra") owned by some app, as seen through Accessibility.
struct MenuBarItem: Identifiable {
    let id: String          // stable key used for the user's show/hide choice
    let pid: pid_t
    let bundleID: String
    let appName: String
    let label: String       // best human-readable name for the item
    let element: AXUIElement
    let frame: CGRect?      // global CoreGraphics coordinates
    let appIcon: NSImage?

    var displayName: String { label == appName ? appName : "\(appName) – \(label)" }
    var isHiddenByNotch: Bool { NotchGeometry.isHidden(frame) }
}

private struct AppInfo {
    let pid: pid_t
    let bundleID: String
    let name: String
    let icon: NSImage?
}

@MainActor
final class ItemStore: ObservableObject {
    static let shared = ItemStore()

    @Published private(set) var items: [MenuBarItem] = []
    /// Captured pictures of the real menu bar items (needs Screen Recording permission).
    @Published private(set) var images: [String: NSImage] = [:]
    /// Whether screen capture really works. CGPreflightScreenCaptureAccess() can report false on
    /// recent macOS even when the user turned Peeky on, so this is confirmed with a real ScreenCaptureKit call.
    @Published private(set) var screenCaptureOK = CGPreflightScreenCaptureAccess()
    private var checkingCapture = false

    private let scanQueue = DispatchQueue(label: "peeky.scan", qos: .userInitiated)
    private var isScanning = false
    private var pendingCompletions: [() -> Void] = []

    /// 상태 아이콘이 있는 앱. 빠른 새로고침은 이 앱들에만 묻는다.
    private var knownPIDs = Set<pid_t>()
    private var needsFullScan = true
    /// 캡처한 이미지의 원래 크기. 크기가 같으면 다시 캡처하지 않는다.
    private var capturedSizes: [String: CGSize] = [:]

    /// Items the bar should show, in the user's order (else menu bar order, left → right).
    func barItems(in group: UUID?) -> [MenuBarItem] {
        guard let group else { return [] }
        let prefs = Preferences.shared
        let notchOnly = prefs.onlyNotchHidden(for: group)
        let list = items.filter { prefs.group(for: $0.id) == group && (!notchOnly || $0.isHiddenByNotch) }
        return prefs.ordered(list) { $0.id }
    }

    /// 다음 새로고침에서 실행 중인 앱 전체를 다시 훑는다(앱이 켜지거나 꺼졌을 때).
    func invalidate() { needsFullScan = true }

    /// - Parameters:
    ///   - full: 실행 중인 모든 앱을 훑는다. 아니면 상태 아이콘이 있던 앱만 다시 본다.
    ///   - captureIDs: 이 항목들만 아이콘을 캡처한다(nil이면 전부).
    func refresh(full: Bool = false, captureIDs: Set<String>? = nil, completion: (() -> Void)? = nil) {
        if let completion { pendingCompletions.append(completion) }
        guard !isScanning else { return }
        guard AX.isTrusted else {
            items = []
            flushCompletions()
            return
        }
        isScanning = true
        let scanAll = full || needsFullScan || knownPIDs.isEmpty
        needsFullScan = false
        let known = knownPIDs

        let myPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != myPID && !$0.isTerminated && (scanAll || known.contains($0.processIdentifier)) }
            .map { AppInfo(pid: $0.processIdentifier,
                           bundleID: $0.bundleIdentifier ?? "pid.\($0.processIdentifier)",
                           name: $0.localizedName ?? $0.bundleIdentifier ?? "?",
                           icon: $0.icon) }

        scanQueue.async {
            let found = Self.scan(apps)
            DispatchQueue.main.async {
                self.items = found
                self.knownPIDs = Set(found.map(\.pid))
                self.isScanning = false
                self.flushCompletions()
                self.captureImages(only: captureIDs)
            }
        }
    }

    private func flushCompletions() {
        let callbacks = pendingCompletions
        pendingCompletions.removeAll()
        callbacks.forEach { $0() }
    }

    func image(for item: MenuBarItem) -> NSImage? { images[item.id] }

    /// Probes ScreenCaptureKit. Only runs once the user has asked for the permission (or macOS already
    /// reports it), so Peeky never triggers the system prompt on its own.
    func checkScreenCapture() {
        let asked = UserDefaults.standard.bool(forKey: "requestedScreenCapture")
        guard !checkingCapture, asked || CGPreflightScreenCaptureAccess() else { return }
        checkingCapture = true
        Task {
            var ok = false
            var detail = ""
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                ok = !content.windows.isEmpty
                detail = "windows=\(content.windows.count)"
            } catch {
                detail = "error=\(error.localizedDescription)"
            }
            checkingCapture = false
            Self.log("screenCapture probe ok=\(ok) preflight=\(CGPreflightScreenCaptureAccess()) \(detail)")
            if ok != screenCaptureOK {
                screenCaptureOK = ok
                if ok { captureImages(only: nil) }
            }
        }
    }

    nonisolated static let logPath = NSHomeDirectory() + "/Library/Logs/Peeky.log"

    /// 진단 로그를 켰을 때만 ~/Library/Logs/Peeky.log에 한 줄 더한다(권한 문제 확인용).
    nonisolated static func log(_ line: String) {
        guard UserDefaults.standard.bool(forKey: "diagnosticLog") else { return }
        let path = NSHomeDirectory() + "/Library/Logs/Peeky.log"
        let text = "\(Date()) \(line)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Accessibility scan

    nonisolated private static func scan(_ apps: [AppInfo]) -> [MenuBarItem] {
        var result: [MenuBarItem] = []
        for app in apps {
            let axApp = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(axApp, 0.25)
            guard let bar = AX.element(axApp, "AXExtrasMenuBar") else { continue }

            var usedKeys = Set<String>()
            for (index, child) in AX.children(bar).enumerated() {
                AXUIElementSetMessagingTimeout(child, 0.5)
                let identifier = AX.string(child, kAXIdentifierAttribute)
                let desc = AX.string(child, kAXDescriptionAttribute)
                let title = AX.string(child, kAXTitleAttribute)
                let help = AX.string(child, kAXHelpAttribute)

                // Prefer stable attributes for the key: titles (e.g. a clock) can change constantly.
                var key = identifier ?? desc ?? help ?? title ?? "#\(index)"
                if usedKeys.contains(key) { key += "#\(index)" }
                usedKeys.insert(key)

                // macOS 26의 제어 센터에는 크기가 0인 빈 자리 항목이 여럿 있다. 화면에 없으니 건너뛴다.
                let frame = AX.frame(child)
                if identifier == nil, desc == nil, title == nil, help == nil,
                   frame.map({ $0.width < 1 || $0.height < 1 }) ?? true { continue }
                if UserDefaults.standard.bool(forKey: "diagnosticLog") {
                    log("item \(app.bundleID) [\(index)] id=\(identifier ?? "-") desc=\(desc ?? "-") title=\(title ?? "-") help=\(help ?? "-")")
                }
                let label = SystemItemNames.label(bundleID: app.bundleID, identifier: identifier,
                                                  description: desc, title: title, help: help,
                                                  appName: app.name, index: index)
                result.append(MenuBarItem(id: "\(app.bundleID)|\(key)",
                                          pid: app.pid,
                                          bundleID: app.bundleID,
                                          appName: app.name,
                                          label: label,
                                          element: child,
                                          frame: frame,
                                          appIcon: app.icon))
            }
        }
        // Menu bar order: left → right. Items without a frame go last.
        return result.sorted { ($0.frame?.minX ?? .greatestFiniteMagnitude) < ($1.frame?.minX ?? .greatestFiniteMagnitude) }
    }

    // MARK: - Screen capture of the real icons

    /// 메뉴바에서 숨기기 직전에 부른다. 숨긴 항목은 화면 밖으로 나가 캡처할 수 없으니,
    /// 아직 보일 때 항목을 다시 읽고 이미지가 없는 것을 캡처해 둔다.
    func prepareForHiding(completion: @escaping () -> Void) {
        guard screenCaptureOK, AX.isTrusted else { completion(); return }
        refresh(captureIDs: []) { [weak self] in
            guard let self else { completion(); return }
            self.captureImages(only: nil) {
                Self.log("hide: captured \(self.images.count) of \(self.items.count) icons before hiding")
                completion()
            }
        }
    }

    /// 이미지가 없거나 크기가 바뀐 항목만 캡처한다. `only`가 있으면 그 항목만 본다.
    private func captureImages(only: Set<String>?, completion: (() -> Void)? = nil) {
        guard screenCaptureOK else { completion?(); return }
        let targets = items.compactMap { item -> (String, CGRect)? in
            guard only?.contains(item.id) ?? true,
                  let f = item.frame, f.width > 1, f.height > 1, !NotchGeometry.isOffScreen(f) else { return nil }
            if let old = capturedSizes[item.id], images[item.id] != nil,
               abs(old.width - f.width) < 1, abs(old.height - f.height) < 1 { return nil }
            return (item.id, f)
        }
        guard !targets.isEmpty else { completion?(); return }

        Task {
            defer { completion?() }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
            let statusWindows = content.windows.filter { $0.windowLayer == Int(CGWindowLevelForKey(.statusWindow)) }
            let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
            var captured: [String: NSImage] = [:]

            for (id, frame) in targets {
                guard let window = statusWindows.min(by: { distance($0.frame, frame) < distance($1.frame, frame) }),
                      distance(window.frame, frame) < 6 else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.width = max(1, Int(window.frame.width * scale))
                config.height = max(1, Int(window.frame.height * scale))
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
                      let analysis = ImageTools.analyze(cg), analysis.hasContent else { continue }
                let image = NSImage(cgImage: cg, size: window.frame.size)
                // Monochrome icons follow the menu bar tint; render them as templates so they
                // stay readable on the bar's own background in light and dark mode.
                image.isTemplate = analysis.isMonochrome
                captured[id] = image
                self.capturedSizes[id] = frame.size
            }
            if !captured.isEmpty { self.images.merge(captured) { _, new in new } }
        }
    }
}

private func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
    abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width)
}

enum ImageTools {
    struct Analysis {
        let hasContent: Bool
        let isMonochrome: Bool
    }

    /// Samples the image to see whether it has any visible pixels and whether those are colourless.
    static func analyze(_ image: CGImage) -> Analysis? {
        let w = 48, h = 16
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var opaque = 0, colored = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Int(pixels[i + 3])
            guard a > 48 else { continue }
            opaque += 1
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            let spread = Double(max(r, g, b) - min(r, g, b)) / Double(a)
            if spread > 0.18 { colored += 1 }
        }
        return Analysis(hasContent: opaque > 3, isMonochrome: opaque > 0 && Double(colored) / Double(opaque) < 0.08)
    }
}
