import AppKit

enum ScreenLocator {
    static func screenForPanel(preference: DisplayPreference) -> NSScreen? {
        switch preference {
        case .withPointer:
            return screenWithCursor() ?? NSScreen.main
        case .main:
            return NSScreen.main
        }
    }

    static func screenWithCursor() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
}
