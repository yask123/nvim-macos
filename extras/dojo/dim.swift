// dojo-dim: quietly darkens everything behind the Dojo window, so the page
// you're editing is the only bright thing on screen.
//
// A click-through veil sits directly beneath Neovide's front window while
// Neovide is the active app, and fades away as soon as you switch to anything
// else. Neovim starts one per window and talks to it over stdin:
//   on | off | opacity 0.45
// It exits when stdin closes (that Neovim quit) or Neovide quits. When several
// Dojo windows are open, only one helper draws; the others wait on a lock.
//
// Build: swiftc -O dim.swift -o dojo-dim      Run: dojo-dim <opacity> <lockfile>

import AppKit

let bundleID = "com.neovide.neovide"
let args = CommandLine.arguments
var opacity = CGFloat(args.count > 1 ? Double(args[1]) ?? 0.45 : 0.45)
let lockPath = args.count > 2 ? args[2] : NSTemporaryDirectory() + "dojo-dim.lock"
var wanted = true  // on/off as last asked, even before this helper holds the lock

final class Veil {
    private var windows: [NSWindow] = []
    private var enabled = wanted
    private var shown = false
    private var front: Int = 0
    private var timer: Timer?

    init() {
        rebuild()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
            [weak self] _ in self?.update()
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) {
            note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == bundleID && neovide() == nil { exit(0) }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuild()
            self?.update()
        }
        // Follow Neovide's front window while it's active (switching between
        // Dojo windows, ⌘` cycling). Cheap: one window-list read per tick.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.update()
        }
        update()
    }

    private func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.alphaValue = 0
            w.level = .normal
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.setFrame(screen.frame, display: false)
            return w
        }
        shown = false
        front = 0
    }

    func set(enabled on: Bool) {
        enabled = on
        update()
    }

    func set(opacity value: CGFloat) {
        opacity = max(0, min(0.9, value))
        if shown { windows.forEach { $0.alphaValue = opacity } }
    }

    func update() {
        guard enabled, let app = neovide(), app.isActive, !app.isHidden,
            let target = frontWindow(pid: app.processIdentifier)
        else {
            hide()
            return
        }
        if target != front || !shown {
            front = target
            windows.forEach { $0.order(.below, relativeTo: target) }
        }
        if !shown {
            shown = true
            fade(to: opacity)
        }
    }

    private func hide() {
        guard shown else { return }
        shown = false
        front = 0
        fade(to: 0)
    }

    private func fade(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            windows.forEach { $0.animator().alphaValue = alpha }
        }
    }
}

func neovide() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
}

// The frontmost ordinary window of that process (window lists are front to back).
func frontWindow(pid: pid_t) -> Int? {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
    for info in list {
        guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
            (info[kCGWindowLayer as String] as? Int) == 0,
            let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
            (bounds["Width"] ?? 0) > 200, (bounds["Height"] ?? 0) > 150
        else { continue }
        return info[kCGWindowNumber as String] as? Int
    }
    return nil
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no Dock icon; it never activates itself
var veil: Veil?

// Commands from Neovim; end of input means that Neovim has quit.
DispatchQueue.global().async {
    while let line = readLine() {
        let parts = line.split(separator: " ")
        DispatchQueue.main.async {
            switch parts.first {
            case "on", "off":
                wanted = parts.first == "on"
                veil?.set(enabled: wanted)
            case "opacity": if parts.count > 1, let v = Double(parts[1]) { veil?.set(opacity: CGFloat(v)) }
            default: break
            }
        }
    }
    exit(0)
}

// One veil at a time: wait for the lock, then start drawing.
DispatchQueue.global().async {
    let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
    if fd >= 0 { flock(fd, LOCK_EX) }
    DispatchQueue.main.async { veil = Veil() }
}

app.run()
