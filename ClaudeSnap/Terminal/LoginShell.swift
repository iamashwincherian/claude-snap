import Foundation

enum LoginShell {
    /// The user's actual login shell (via the password database), not `$SHELL` — a GUI app
    /// launched from Finder/Dock doesn't inherit a Terminal.app-style environment.
    static var path: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            return String(cString: shell)
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }
}
