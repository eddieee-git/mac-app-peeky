import AppKit

/// Works out where the camera housing (notch) sits, so we can tell which menu bar items it hides.
enum NotchGeometry {
    static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    /// Right edge of the notch in global x coordinates (AppKit and CoreGraphics share x).
    static var notchMaxX: CGFloat? {
        guard let screen = notchScreen, let right = screen.auxiliaryTopRightArea else { return nil }
        // auxiliaryTopRightArea is reported in screen space; normalise in case it is relative.
        let insideScreen = right.minX >= screen.frame.minX - 1 && right.maxX <= screen.frame.maxX + 1
        return insideScreen ? right.minX : screen.frame.minX + right.minX
    }

    /// True when an item (frame in global CG coordinates) can't be seen in the menu bar:
    /// it sits under / to the left of the notch, or macOS pushed it off-screen entirely.
    static func isHidden(_ frame: CGRect?) -> Bool {
        guard let frame, frame.width > 0 else { return true }
        let midX = frame.midX
        let onAnyScreen = NSScreen.screens.contains { midX >= $0.frame.minX && midX <= $0.frame.maxX }
        if !onAnyScreen { return true }
        guard let screen = notchScreen, let notchMaxX else { return false }
        let onNotchScreen = midX >= screen.frame.minX && midX <= screen.frame.maxX
        return onNotchScreen && frame.minX < notchMaxX
    }

    /// Left edge of the notch in global x coordinates.
    static var notchMinX: CGFloat? {
        guard let screen = notchScreen, let left = screen.auxiliaryTopLeftArea else { return nil }
        let insideScreen = left.minX >= screen.frame.minX - 1 && left.maxX <= screen.frame.maxX + 1
        return insideScreen ? left.maxX : screen.frame.minX + left.maxX
    }

    /// The notch area of the menu bar in AppKit coordinates (bottom-left origin), if there is one.
    static var notchRect: NSRect? {
        guard let screen = notchScreen, let minX = notchMinX, let maxX = notchMaxX, maxX > minX else { return nil }
        let height = menuBarHeight(on: screen)
        return NSRect(x: minX, y: screen.frame.maxY - height, width: maxX - minX, height: height)
    }

    /// True when no screen shows the frame at all (macOS pushed the item out of the menu bar).
    static func isOffScreen(_ frame: CGRect) -> Bool {
        !NSScreen.screens.contains { frame.midX >= $0.frame.minX && frame.midX <= $0.frame.maxX }
    }

    /// Height of the menu bar on a given screen.
    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let h = screen.frame.maxY - screen.visibleFrame.maxY
        return h > 0 ? h : NSStatusBar.system.thickness
    }
}
