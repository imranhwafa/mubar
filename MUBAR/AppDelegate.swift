import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sampler = SamplerCoordinator()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var welcomePanel: NSPanel?
    private var defaultsObserver: NSObjectProtocol?

    private var lowBatteryFlashTimer: Timer?
    private var flashOn = false
    private var hoverCloseTimer: Timer?

    private static let firstRunKey = "firstRunDone.v1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            // Transparent overlay that detects hover without intercepting clicks.
            let hover = StatusHoverView(frame: button.bounds)
            hover.autoresizingMask = [.width, .height]
            hover.onEnter = { [weak self] in self?.handleHoverEnter() }
            hover.onExit  = { [weak self] in self?.handleHoverExit() }
            button.addSubview(hover)
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.contentViewController = NSHostingController(
            rootView: PopoverRoot()
                .environmentObject(sampler)
                .environmentObject(sampler.battery)
                .environmentObject(sampler.cpu)
                .environmentObject(sampler.memory)
                .environmentObject(sampler.network)
                .environmentObject(sampler.disk)
                .environmentObject(sampler.bluetooth)
        )

        sampler.onTick = { [weak self] in self?.refreshLabel() }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshLabel() }
        }

        refreshLabel()
        showWelcomeIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let o = defaultsObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Click handling

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return showPopover() }
        let isRightClick = event.type == .rightMouseUp ||
            (event.type == .leftMouseUp && event.modifierFlags.contains(.control))
        if isRightClick {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    // MARK: - Hover to open

    private func handleHoverEnter() {
        guard UserDefaults.standard.bool(forKey: FeaturePrefs.hoverToOpenKey) else { return }
        hoverCloseTimer?.invalidate()
        hoverCloseTimer = nil
        if !popover.isShown { showPopover() }
    }

    private func handleHoverExit() {
        guard UserDefaults.standard.bool(forKey: FeaturePrefs.hoverToOpenKey) else { return }
        // Brief grace period: if the cursor moved into the popover, keep it open;
        // otherwise (cursor left entirely) close it.
        hoverCloseTimer?.invalidate()
        hoverCloseTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.closePopoverIfCursorAway() }
        }
    }

    private func closePopoverIfCursorAway() {
        guard popover.isShown else { return }
        let mouse = NSEvent.mouseLocation
        if let win = popover.contentViewController?.view.window,
           win.frame.insetBy(dx: -8, dy: -8).contains(mouse) {
            return   // cursor is over the popover — leave it open
        }
        popover.performClose(nil)
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open MUBAR", action: #selector(showPopoverAction), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…",  action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "About MUBAR", action: #selector(showAbout),    keyEquivalent: "")
        menu.addItem(.separator())
        let launch = NSMenuItem(title: "Launch at Login",
                                action: #selector(toggleLaunchAtLogin),
                                keyEquivalent: "")
        launch.state = LaunchAtLogin.isRegistered ? .on : .off
        menu.addItem(launch)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MUBAR", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach so left-click goes back to popover.
        statusItem.menu = nil
    }

    // MARK: - Menu actions

    @objc private func showPopoverAction() { showPopover() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isRegistered)
    }

    @objc private func openSettings() {
        // Settings is presented as a sheet on top of the popover.
        if !popover.isShown { showPopover() }
        NotificationCenter.default.post(name: .mubarOpenSettings, object: nil)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(string:
            "Live system stats in your menu bar.\n" +
            "Built with SwiftUI + AppKit.",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "MUBAR",
        ])
    }

    // MARK: - Welcome

    private func showWelcomeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.firstRunKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.firstRunKey)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.center()
        panel.title = "Welcome to MUBAR"
        let isPresentedBinding = Binding<Bool>(
            get: { true },
            set: { [weak panel] new in
                if !new { panel?.close() }
            }
        )
        let view = WelcomeSheet(
            isPresented: isPresentedBinding,
            openSettings: { [weak self] in self?.openSettings() }
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomePanel = panel
    }

    // MARK: - Label rendering

    private func refreshLabel() {
        guard let button = statusItem.button else { return }

        if AppearancePrefs.pillEnabled {
            // Render the whole label (background pill + content) into an image.
            let image = MenuBarLabelBuilder.renderPillImage(
                battery: sampler.battery.snapshot,
                cpu: sampler.cpu.snapshot,
                memory: sampler.memory.snapshot,
                network: sampler.network.snapshot,
                disk: sampler.disk.snapshot,
                bluetooth: sampler.bluetooth.snapshot
            )
            button.attributedTitle = NSAttributedString(string: "")
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            let title = MenuBarLabelBuilder.build(
                battery: sampler.battery.snapshot,
                cpu: sampler.cpu.snapshot,
                memory: sampler.memory.snapshot,
                network: sampler.network.snapshot,
                disk: sampler.disk.snapshot,
                bluetooth: sampler.bluetooth.snapshot
            )
            button.image = nil
            button.attributedTitle = title
        }

        updateLowBatteryFlash()
        if AppearancePrefs.pulseBarOnUpdate { pulseButton() }
    }

    // MARK: - Animations

    /// Briefly dips the status item opacity to acknowledge a refresh.
    private func pulseButton() {
        guard let button = statusItem.button else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            button.animator().alphaValue = 0.45
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                button.animator().alphaValue = 1.0
            }
        }
    }

    /// Pulses the whole item while battery is low (and not charging).
    private func updateLowBatteryFlash() {
        let snap = sampler.battery.snapshot
        let isLow = AppearancePrefs.flashLowBattery
            && snap.isPresent
            && snap.state != .charging
            && snap.state != .charged
            && (snap.percent ?? 100) < 20

        if isLow, lowBatteryFlashTimer == nil {
            let t = Timer(timeInterval: 0.9, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tickLowBatteryFlash() }
            }
            RunLoop.main.add(t, forMode: .common)
            lowBatteryFlashTimer = t
        } else if !isLow, lowBatteryFlashTimer != nil {
            lowBatteryFlashTimer?.invalidate()
            lowBatteryFlashTimer = nil
            flashOn = false
            statusItem.button?.alphaValue = 1.0
        }
    }

    private func tickLowBatteryFlash() {
        flashOn.toggle()
        guard let button = statusItem.button else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            button.animator().alphaValue = flashOn ? 0.35 : 1.0
        }
    }
}

extension Notification.Name {
    static let mubarOpenSettings = Notification.Name("MUBAROpenSettings")
}

/// Transparent overlay placed on the status item button. Detects hover via a
/// tracking area but passes all clicks through to the button beneath it.
final class StatusHoverView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // clicks fall through

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent)  { onExit?() }
}
