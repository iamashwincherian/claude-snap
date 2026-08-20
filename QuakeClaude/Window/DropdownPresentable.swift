import Foundation

/// Optional hook for a dropdown panel's content view controller. The panel doesn't use standard
/// AppKit view-controller containment lifecycle (it's a manually managed subview, not a window's
/// `contentViewController`), so `viewDidAppear`/`viewWillDisappear` never fire on their own —
/// this is the explicit substitute.
@MainActor
protocol DropdownPresentable: AnyObject {
    func panelWillShow()
}
