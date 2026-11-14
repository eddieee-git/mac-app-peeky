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

    /// Items the bar should show, in menu bar order (left → right).
    func barItems(in group: UUID?) -> [MenuBarItem] {
        let prefs = Preferences.shared
        return items.filter { prefs.group(for: $0.id) == group && group != nil && (!prefs.onlyNotchHidden || $0.isHiddenByNotch) }
    }

    func refresh(completion: (() -> Void)? = nil) {
        if let completion { pendingCompletions.append(completion) }
        guard !isScanning else { return }
        guard AX.isTrusted else {
            items = []
            flushCompletions()
            return
        }
        isScanning = true

        let myPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != myPID && !$0.isTerminated }
            .map { AppInfo(pid: $0.processIdentifier,
                           bundleID: $0.bundleIdentifier ?? "pid.\($0.processIdentifier)",
                           name: $0.localizedName ?? $0.bundleIdentifier ?? "?",
                           icon: $0.icon) }

        scanQueue.async {
            let found = Self.scan(apps)
            DispatchQueue.main.async {
                self.items = found
                self.isScanning = false
                self.flushCompletions()
                self.captureImages()
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
                if ok { captureImages() }
            }
        }
    }

    /// Appends a line to ~/Library/Logs/Peeky.log (permission troubleshooting).
    nonisolated static func log(_ line: String) {
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

                let label = desc ?? title ?? help ?? app.name
                result.append(MenuBarItem(id: "\(app.bundleID)|\(key)",
                                          pid: app.pid,
                                          bundleID: app.bundleID,
                                          appName: app.name,
                                          label: label,
                                          element: child,
                                          frame: AX.frame(child),
                                          appIcon: app.icon))
            }
        }
        // Menu bar order: left → right. Items without a frame go last.
        return result.sorted { ($0.frame?.minX ?? .greatestFiniteMagnitude) < ($1.frame?.minX ?? .greatestFiniteMagnitude) }
    }

    // MARK: - Screen capture of the real icons

    private func captureImages() {
        guard screenCaptureOK else { return }
        let targets = items.compactMap { item -> (String, CGRect)? in
            guard let f = item.frame, f.width > 1, f.height > 1 else { return nil }
            return (item.id, f)
        }
        guard !targets.isEmpty else { return }

        Task {
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
            }
            self.images.merge(captured) { _, new in new }
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
