import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleTerminal = Self("toggleTerminal", default: .init(.backtick, modifiers: [.control]))
}

@MainActor
enum HotkeyManager {
    static func registerToggleHandler(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .toggleTerminal) {
            handler()
        }
    }
}
