import Foundation
import AppKit

public final class AppPreferencesStore {
    public static let minOpacity: Double = 0.45
    public static let maxOpacity: Double = 1.0
    public static let defaultOpacity: Double = 0.96
    public static let defaultDockWidth: CGFloat = 300
    public static let minDockWidth: CGFloat = 270
    public static let maxDockWidth: CGFloat = 440
    public static let edgeInset: CGFloat = 10

    private let defaults: UserDefaults

    private enum Keys {
        static let placementMode = "clipvoice.window.placementMode"
        static let floatingFrame = "clipvoice.window.floatingFrame"
        static let dockWidth = "clipvoice.window.dockWidth"
        static let opacity = "clipvoice.window.opacity"
        static let isPinned = "clipvoice.window.isPinned"
        static let hotkeyEnabled = "clipvoice.hotkey.enabled"
    }

    public init(suiteName: String? = nil) {
        if let suiteName, !suiteName.isEmpty, let suite = UserDefaults(suiteName: suiteName) {
            self.defaults = suite
        } else {
            self.defaults = .standard
        }
    }

    public static func clampOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultOpacity }
        return min(max(value, minOpacity), maxOpacity)
    }

    public static func clampDockWidth(_ width: CGFloat, in visibleFrame: NSRect) -> CGFloat {
        let maxAllowed = max(minDockWidth, min(maxDockWidth, visibleFrame.width - edgeInset * 2))
        return min(max(width, minDockWidth), maxAllowed)
    }

    public var placementMode: WindowPlacementMode {
        get {
            guard let raw = defaults.string(forKey: Keys.placementMode),
                  let mode = WindowPlacementMode(rawValue: raw) else {
                return .floating
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.placementMode)
        }
    }

    public var opacity: Double {
        get {
            guard defaults.object(forKey: Keys.opacity) != nil else {
                return Self.defaultOpacity
            }
            return Self.clampOpacity(defaults.double(forKey: Keys.opacity))
        }
        set {
            defaults.set(Self.clampOpacity(newValue), forKey: Keys.opacity)
        }
    }

    public var dockWidth: CGFloat {
        get {
            let stored = defaults.double(forKey: Keys.dockWidth)
            return stored > 0 ? CGFloat(stored) : Self.defaultDockWidth
        }
        set {
            defaults.set(Double(max(Self.minDockWidth, newValue)), forKey: Keys.dockWidth)
        }
    }

    public var isPinned: Bool {
        get {
            defaults.object(forKey: Keys.isPinned) == nil ? true : defaults.bool(forKey: Keys.isPinned)
        }
        set {
            defaults.set(newValue, forKey: Keys.isPinned)
        }
    }

    public var hotkeyEnabled: Bool {
        get {
            defaults.object(forKey: Keys.hotkeyEnabled) == nil ? true : defaults.bool(forKey: Keys.hotkeyEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.hotkeyEnabled)
        }
    }

    public func savedFloatingFrame() -> NSRect? {
        guard let str = defaults.string(forKey: Keys.floatingFrame) else { return nil }
        let rect = NSRectFromString(str)
        guard rect.width >= 270, rect.height >= 360 else { return nil }
        return rect
    }

    public func saveFloatingFrame(_ frame: NSRect) {
        defaults.set(NSStringFromRect(frame), forKey: Keys.floatingFrame)
    }

    public func resetDisplayDefaults() {
        defaults.removeObject(forKey: Keys.floatingFrame)
        defaults.set(Self.defaultOpacity, forKey: Keys.opacity)
        defaults.set(Double(Self.defaultDockWidth), forKey: Keys.dockWidth)
        defaults.set(WindowPlacementMode.floating.rawValue, forKey: Keys.placementMode)
        defaults.set(true, forKey: Keys.isPinned)
    }

    /// Computes a safe target frame inside the selected screen's visibleFrame.
    public static func targetFrame(
        for mode: WindowPlacementMode,
        screenVisibleFrame: NSRect,
        dockWidth: CGFloat,
        savedFloatingFrame: NSRect?,
        availableScreens: [NSRect]
    ) -> NSRect {
        switch mode {
        case .dockLeft:
            let w = clampDockWidth(dockWidth, in: screenVisibleFrame)
            let h = max(400, screenVisibleFrame.height - edgeInset * 2)
            return NSRect(
                x: screenVisibleFrame.minX + edgeInset,
                y: screenVisibleFrame.minY + edgeInset,
                width: w,
                height: h
            )
        case .dockRight:
            let w = clampDockWidth(dockWidth, in: screenVisibleFrame)
            let h = max(400, screenVisibleFrame.height - edgeInset * 2)
            return NSRect(
                x: screenVisibleFrame.maxX - w - edgeInset,
                y: screenVisibleFrame.minY + edgeInset,
                width: w,
                height: h
            )
        case .floating:
            if let saved = savedFloatingFrame, isFrameSafeOnScreen(saved, availableScreens: availableScreens) {
                return saved
            }
            let width: CGFloat = min(460, max(320, screenVisibleFrame.width - 48))
            let height: CGFloat = min(600, max(440, screenVisibleFrame.height - 48))
            let x = screenVisibleFrame.maxX - width - 24
            let y = screenVisibleFrame.maxY - height - 24
            return NSRect(x: x, y: y, width: width, height: height)
        }
    }

    /// Prevents saved frames from launching off-screen when displays change.
    public static func isFrameSafeOnScreen(_ frame: NSRect, availableScreens: [NSRect]) -> Bool {
        guard frame.width >= 270, frame.height >= 360 else { return false }
        for visible in availableScreens {
            let intersection = frame.intersection(visible)
            if !intersection.isNull && intersection.width >= 140 && intersection.height >= 140 {
                return true
            }
        }
        return false
    }
}
