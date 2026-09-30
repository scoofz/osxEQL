// eqbuddy-focus — hide EQBuddy while EverQuest isn't the frontmost app, macOS side.
//
// EQBuddy's own "Hide when game unfocused" asks Windows (GetForegroundWindow) which
// window is in front. Under osxEQL the game lives in its own Wine virtual desktop
// (explorer /desktop=osxEQL) while EQBuddy (window mode) is a separate Mac window
// outside it, and EQBuddy never sees eqgame.exe as the foreground: the option
// either never fires or keeps the widget hidden. The truth is on the Mac side, where
// every Wine process is its own Mac app — so this helper watches which Mac app is
// frontmost and hides / unhides EQBuddy's app (NSRunningApplication.hide/unhide:
// no Accessibility permission needed).
//
// Shown when: the game isn't running, or the frontmost app is the game (eqgame.exe,
// or the osxEQL virtual-desktop explorer that hosts it) or EQBuddy itself.
// Hidden otherwise. Only un-hides what it hid. Exits when EQBuddy exits.
//
// Started by engine/eqbuddy.sh next to EQBuddy (window mode, autohide on).
// Built by packaging/build-app.sh into the .app, or on first use by the engine.
import AppKit

var cmdCache: [pid_t: String] = [:]

/// Lower-cased "localizedName + argv" of a process: Wine apps all run the same
/// loader binary, so the Windows exe name is only reliably in the arguments.
func ident(_ app: NSRunningApplication) -> String {
    let pid = app.processIdentifier
    if let c = cmdCache[pid] { return c }
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    var args = ""
    if sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 {
        var buf = [UInt8](repeating: 0, count: size)
        if sysctl(&mib, 3, &buf, &size, nil, 0) == 0 {
            args = String(decoding: buf[4..<size].map { $0 == 0 ? 32 : $0 }, as: UTF8.self)
        }
    }
    let s = ((app.localizedName ?? "") + " " + args).lowercased()
    cmdCache[pid] = s
    return s
}

func running(_ needle: String) -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { ident($0).contains(needle) }
}

func isGameSide(_ s: String) -> Bool {
    s.contains("eqgame.exe") || s.contains("eqbuddy.exe") || s.contains("/desktop=osxeql")
}

var hiddenByUs = Set<pid_t>()
var sawBuddy = false
let started = Date()

func update(front: NSRunningApplication?) {
    let buddies = running("eqbuddy.exe")
    if buddies.isEmpty {
        // Give EQBuddy time to start; after that, no EQBuddy = nothing left to do.
        if sawBuddy || Date().timeIntervalSince(started) > 120 { exit(0) }
        return
    }
    sawBuddy = true
    let gameUp = !running("eqgame.exe").isEmpty
    let frontIdent = (front ?? NSWorkspace.shared.frontmostApplication).map(ident) ?? ""
    let show = !gameUp || isGameSide(frontIdent)
    for b in buddies {
        let pid = b.processIdentifier
        if show {
            if hiddenByUs.contains(pid) { b.unhide(); hiddenByUs.remove(pid) }
        } else if !b.isHidden {
            if b.hide() { hiddenByUs.insert(pid) }
        }
    }
}

let nc = NSWorkspace.shared.notificationCenter
nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
    update(front: n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
}
nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { n in
    if let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
        cmdCache[a.processIdentifier] = nil
        hiddenByUs.remove(a.processIdentifier)
    }
    update(front: nil)
}
// Fallback tick: game started/stopped without an activation, EQBuddy gone, etc.
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in update(front: nil) }
update(front: nil)
RunLoop.main.run()
