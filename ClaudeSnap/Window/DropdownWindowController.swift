import AppKit
import QuartzCore

/// Drives the Quake-style slide-down panel.
///
/// The window's frame is set once per appearance (to the final resting rect, flush under the
/// menu bar on whichever screen is targeted) and never animated itself — that's what gives the
/// real NSWindow shadow drawn by the window server, per the design's "shadow — drawn by the
/// window server; the panel is clipped at the menu bar so no shadow spills upward" note: the card
/// is clipped by its container's `masksToBounds`, so there's no window content above the resting
/// edge for a shadow to render *from* in the first place.
///
/// The actual reveal/retract is a `transform.translation.y` animation on the card layer inside
/// that fixed-frame, clipping container — a spring for reveal (damping 26, stiffness 340, per the
/// design's "AppKit equivalent" note), a quick ease for retract, and a plain cross-fade when
/// Reduce Motion is on.
@MainActor
final class DropdownWindowController: NSObject {
    private(set) var isVisible = false

    private let preferences: AppPreferences
    private let panel: DropdownPanel
    private let containerView: FlippedView
    private let cardView: FlippedView
    private let blurView: NSVisualEffectView
    private let resizeHandle = ResizeHandleView()

    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var keyMonitor: Any?
    private var contentViewController: NSViewController?

    /// The status item button's window. Clicks there must be left entirely to
    /// `StatusBarController.onToggle` — if the outside-click monitor also treated them as
    /// "dismiss", a single click while open would hide() on mouseDown and then toggle() would
    /// see `isVisible == false` and show() again on mouseUp, racing the retract animation.
    weak var statusItemWindow: NSWindow?

    init(preferences: AppPreferences) {
        self.preferences = preferences

        let initialRect = NSRect(x: 0, y: 0, width: 900, height: 500)
        panel = DropdownPanel(contentRect: initialRect)
        containerView = FlippedView(frame: NSRect(origin: .zero, size: initialRect.size))
        cardView = FlippedView(frame: NSRect(origin: .zero, size: initialRect.size))
        blurView = NSVisualEffectView(frame: cardView.bounds)

        super.init()

        setUpViewHierarchy()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    private func setUpViewHierarchy() {
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true

        cardView.wantsLayer = true
        cardView.layer?.masksToBounds = true
        cardView.layer?.cornerRadius = 13
        // Container is flipped (y=0 at top), so the "bottom" corners are the MaxY ones.
        cardView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        cardView.autoresizingMask = [.width, .height]

        blurView.autoresizingMask = [.width, .height]
        blurView.blendingMode = .behindWindow
        blurView.material = .hudWindow
        blurView.state = .active
        cardView.addSubview(blurView)

        containerView.addSubview(cardView)
        panel.contentView = containerView

        resizeHandle.onDrag = { [weak self] in self?.resizeByDrag() }
        cardView.addSubview(resizeHandle)
    }

    @objc private func screenParametersChanged() {
        guard isVisible else { return }
        positionPanel()
    }

    // MARK: - Content

    func embedContent(_ viewController: NSViewController) {
        contentViewController?.view.removeFromSuperview()
        contentViewController = viewController

        let view = viewController.view
        view.frame = cardView.bounds
        view.autoresizingMask = [.width, .height]
        cardView.addSubview(view)
        // Content is embedded after the handle is already a subview, so re-assert z-order on top
        // of it — otherwise the handle would sit behind the terminal and never receive drags.
        cardView.addSubview(resizeHandle, positioned: .above, relativeTo: nil)
    }

    // MARK: - Show / hide

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard !isVisible else { return }
        isVisible = true
        positionPanel()
        cardView.layer?.transform = CATransform3DMakeTranslation(0, -cardView.bounds.height, 0)
        cardView.layer?.opacity = 0
        (contentViewController as? DropdownPresentable)?.panelWillShow()
        panel.makeKeyAndOrderFront(nil)
        animateReveal()
        installOutsideDismissMonitors()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        removeOutsideDismissMonitors()
        animateRetract { [weak self] in
            // A quick re-toggle during the retract animation flips `isVisible` back to true
            // before this completion runs; ordering out then would hide the just-reopened panel.
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
        }
    }

    // MARK: - Geometry

    private func positionPanel() {
        guard let screen = ScreenLocator.screenForPanel(preference: preferences.displayPreference) else { return }

        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let usableHeight = screen.frame.height - menuBarHeight
        let panelHeight = (usableHeight * preferences.screenCoveragePercent / 100).rounded()
        let panelWidth = (screen.frame.width * preferences.widthPercent / 100).rounded()
        let originX = (screen.frame.minX + (screen.frame.width - panelWidth) / 2).rounded()
        let originY = screen.frame.maxY - menuBarHeight - panelHeight
        let rect = NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight)

        panel.setFrame(rect, display: true)
        containerView.frame = NSRect(origin: .zero, size: rect.size)
        cardView.frame = NSRect(origin: .zero, size: rect.size)
        // Flipped card, so the bottom edge is `bounds.height`, not `bounds.origin.y`.
        resizeHandle.frame = NSRect(x: 0, y: rect.height - ResizeHandleView.thickness, width: rect.width, height: ResizeHandleView.thickness)
    }

    /// Grows/shrinks the panel from its bottom edge only — the top stays flush under the menu bar,
    /// same as every other resize path here. Writes straight to `screenCoveragePercent` so the
    /// Preferences slider and this handle are always in sync, and so the size survives relaunch
    /// the same way a slider drag would.
    private func resizeByDrag() {
        guard let screen = ScreenLocator.screenForPanel(preference: preferences.displayPreference) else { return }
        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let usableHeight = screen.frame.height - menuBarHeight
        guard usableHeight > 0 else { return }

        // Absolute pointer position rather than accumulated `event.deltaY`: no sign ambiguity, and
        // the panel edge can't drift away from the cursor once a drag clamps at the range ends.
        let height = screen.frame.maxY - menuBarHeight - NSEvent.mouseLocation.y
        let range = AppPreferences.coverageRange
        preferences.screenCoveragePercent = min(range.upperBound, max(range.lowerBound, height / usableHeight * 100))
        positionPanel()
    }

    // MARK: - Animation

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func animateReveal() {
        guard let layer = cardView.layer else { return }
        let height = cardView.bounds.height

        // A show() can land while a retract is still attached. Any leftover retract animation
        // keeps compositing over this reveal — so clear both before touching the model values,
        // and before the reduce-motion/instant early return below, which would otherwise leave
        // the panel pinned invisible with no reveal animation to fight back.
        layer.removeAnimation(forKey: "retract")
        layer.removeAnimation(forKey: "retractFade")

        // Model layer always reflects the settled state; CA animates the visual delta from
        // whatever `fromValue` we hand it, so setting the final values up front and adding the
        // animation afterwards can't race a duplicate show() call.
        layer.transform = CATransform3DIdentity
        layer.opacity = 1

        guard !reduceMotion, preferences.animationSpeed != .instant else { return }

        let translate = CASpringAnimation(keyPath: "transform.translation.y")
        translate.fromValue = -height
        translate.toValue = 0
        translate.damping = 26
        translate.stiffness = 340
        translate.mass = 1
        translate.initialVelocity = 0
        translate.duration = translate.settlingDuration

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = min(0.12, translate.duration)

        layer.add(translate, forKey: "reveal")
        layer.add(fade, forKey: "revealFade")
    }

    private func animateRetract(completion: @escaping () -> Void) {
        guard let layer = cardView.layer else {
            completion()
            return
        }
        let height = cardView.bounds.height
        let duration = reduceMotion ? 0.12 : preferences.animationSpeed.retractDuration

        layer.removeAnimation(forKey: "reveal")
        layer.removeAnimation(forKey: "revealFade")

        layer.transform = CATransform3DMakeTranslation(0, -height, 0)
        layer.opacity = 0

        guard duration > 0 else {
            completion()
            return
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)

        if reduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = duration
            layer.add(fade, forKey: "retractFade")
        } else {
            let translate = CABasicAnimation(keyPath: "transform.translation.y")
            translate.fromValue = 0
            translate.toValue = -height
            translate.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
            translate.duration = duration
            layer.add(translate, forKey: "retract")

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.beginTime = CACurrentMediaTime() + duration * 0.4
            fade.duration = duration * 0.6
            // `.backwards` holds opacity 1 through the delay so the card doesn't blink out before
            // the fade starts. It must still be removed on completion: the model value is already
            // 0, and a retained fill would keep overriding every later reveal, leaving the panel
            // permanently invisible after the first hide.
            fade.fillMode = .backwards
            layer.add(fade, forKey: "retractFade")
        }

        CATransaction.commit()
    }

    // MARK: - Dismiss on outside click / Escape

    private func installOutsideDismissMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // Global-monitor events never carry a usable `.window` (even for a click on our own
            // status item — the button lives in a separate system-hosted window whose events
            // arrive here with `.window == nil`), so identity checks like the local monitor's
            // can't exclude it. Compare screen location against the status item's frame instead.
            guard let self else { return }
            if let statusFrame = self.statusItemWindow?.frame, statusFrame.contains(NSEvent.mouseLocation) { return }
            Task { @MainActor in self.hide() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window !== self.panel, event.window !== self.statusItemWindow else { return event }
            self.hide()
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                self.hide()
                return nil
            }
            return event
        }
    }

    private func removeOutsideDismissMonitors() {
        [globalClickMonitor, localClickMonitor, keyMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalClickMonitor = nil
        localClickMonitor = nil
        keyMonitor = nil
    }
}
