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
// Second job — alert SOUNDS (see "Alert sounds" below): EQBuddy's WPF MediaPlayer
// cannot play anything under osxEQL's Wine, so the sound is played here with afplay.
//
// Usage: eqbuddy-focus --prefix <WINEPREFIX> [--autohide on|off]
// Started by engine/eqbuddy.sh next to EQBuddy. Built by packaging/build-app.sh into
// the .app, or on first use by the engine.
import AppKit

let cliArgs = CommandLine.arguments
func option(_ name: String) -> String? {
    guard let i = cliArgs.firstIndex(of: name), i + 1 < cliArgs.count else { return nil }
    return cliArgs[i + 1]
}
let autohide = (option("--autohide") ?? "on") != "off"
let prefix = option("--prefix")

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

/// One line per decision, to logs/eqbuddy.log (stdout is redirected there).
func note(_ s: String) {
    let t = ISO8601DateFormatter().string(from: Date())
    print("eqbuddy-focus \(t) \(s)")
    fflush(stdout)
}

var hiddenByUs = Set<pid_t>()
var lastState = ""
var sawBuddy = false
let started = Date()

func update(front: NSRunningApplication?) {
    let buddies = running("eqbuddy.exe")
    if buddies.isEmpty {
        // Give EQBuddy time to start; after that, no EQBuddy = nothing left to do.
        if sawBuddy || Date().timeIntervalSince(started) > 120 {
            note("EQBuddy not running — exiting")
            exit(0)
        }
        return
    }
    sawBuddy = true
    let gameUp = !running("eqgame.exe").isEmpty
    let frontIdent = (front ?? NSWorkspace.shared.frontmostApplication).map(ident) ?? ""
    let show = !gameUp || isGameSide(frontIdent)
    let state = "front=[\(frontIdent.prefix(160))] game=\(gameUp) buddies=\(buddies.map { $0.processIdentifier }) -> \(show ? "show" : "hide")"
    if state != lastState { note(state); lastState = state }
    guard autohide else { return }
    for b in buddies {
        let pid = b.processIdentifier
        if show {
            if hiddenByUs.contains(pid) { b.unhide(); hiddenByUs.remove(pid) }
        } else if !b.isHidden {
            if b.hide() { hiddenByUs.insert(pid) } else { note("hide() refused for pid \(pid)") }
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
// ---- Alert sounds -----------------------------------------------------------------
// EQBuddy plays alerts through WPF's MediaPlayer -> Wine's wmp -> DirectShow. Wine's
// WAV parser lives in winegstreamer, and osxEQL's Wine is built without GStreamer, so
// every play fails: "Alert sound could not be played: 0x80040218"
// (VFW_E_CANNOT_RENDER) lands in EQBuddy's error.log. That line IS the "an alert
// wanted a sound now" signal, so we tail error.log and play it on the Mac with
// afplay — as EQBuddy 1.x's native Mac build did (same clip mapping, MIT).
//
// Which sound: the log line doesn't say. We use the sound all enabled sound-rules
// share if they share one, else the shared "Alert sound" (AlertSound) setting.
// Volume: AlertVolume. "Off" plays nothing.
let macClips = ["Ding": "Ping", "Notify": "Glass", "Chimes": "Blow", "Chord": "Pop",
                "Tada": "Hero", "Exclamation": "Sosumi", "Alarm": "Submarine",
                // EQBuddy's legacy SystemSounds names (AlertSoundCatalog.Normalize)
                "Asterisk": "Ping", "Beep": "Pop", "Hand": "Blow", "Question": "Glass"]

func profileDirs() -> [URL] {
    guard let prefix else { return [] }
    let users = URL(fileURLWithPath: prefix).appendingPathComponent("drive_c/users")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: users.path)) ?? []
    return names.map { users.appendingPathComponent($0).appendingPathComponent("AppData/Roaming/EQBuddy Evolved") }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
}

func macClip(_ name: String) -> String? {
    let clip = macClips[name] ?? "Ping"
    for dir in [NSHomeDirectory() + "/Library/Sounds", "/Library/Sounds", "/System/Library/Sounds"] {
        let p = "\(dir)/\(clip).aiff"
        if FileManager.default.fileExists(atPath: p) { return p }
    }
    return nil
}

/// A sound choice (built-in name, "Off", or a Windows path to the player's own file)
/// -> a Mac file afplay can play, or nil for silence.
func resolveSound(_ raw: String) -> String? {
    let choice = raw.trimmingCharacters(in: .whitespaces)
    if choice.caseInsensitiveCompare("Off") == .orderedSame { return nil }
    if choice.isEmpty || macClips[choice] != nil { return macClip(choice.isEmpty ? "Ding" : choice) }
    // Custom file: C:\... inside the prefix.
    if let prefix, choice.count > 3, Array(choice)[1] == ":" {
        let rel = String(choice.dropFirst(3)).replacingOccurrences(of: "\\", with: "/")
        let p = prefix + "/drive_c/" + rel
        if FileManager.default.fileExists(atPath: p) { return p }
    }
    return macClip("Ding")
}

func soundToPlay(settings: URL) -> (String, Double)? {
    guard let data = try? Data(contentsOf: settings),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return macClip("Ding").map { ($0, 1.0) }
    }
    let shared = json["AlertSound"] as? String ?? "Ding"
    let volume = min(max((json["AlertVolume"] as? Double) ?? 1.0, 0), 1)
    var chosen = Set<String>()
    for rule in json["TrackedRules"] as? [[String: Any]] ?? [] {
        guard rule["Enabled"] as? Bool ?? true, rule["AlertSound"] as? Bool ?? false else { continue }
        let own = rule["AlertSoundName"] as? String ?? ""
        chosen.insert(own.isEmpty ? shared : own)
    }
    let pick = chosen.count == 1 ? chosen.first! : shared
    return resolveSound(pick).map { ($0, volume) }
}

var logOffsets: [String: UInt64] = [:]
var lastPlay = Date.distantPast

func pollErrorLogs() {
    for dir in profileDirs() {
        let log = dir.appendingPathComponent("error.log").path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: log),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else {
            if logOffsets[log] == nil { logOffsets[log] = 0 }   // not created yet: read it all once it is
            continue
        }
        guard let from = logOffsets[log] else { logOffsets[log] = size; continue }  // start at the end
        if size < from { logOffsets[log] = size; continue }                          // truncated/rotated
        if size == from { continue }
        guard let fh = FileHandle(forReadingAtPath: log) else { continue }
        fh.seek(toFileOffset: from)
        let chunk = String(decoding: fh.readData(ofLength: Int(size - from)), as: UTF8.self)
        fh.closeFile()
        logOffsets[log] = size
        guard chunk.contains("Alert sound could not be played")
                || chunk.contains("No alert sound could be played") else { continue }
        // EQBuddy already coalesces bursts; keep one sound per half second anyway.
        guard Date().timeIntervalSince(lastPlay) > 0.5,
              let sound = soundToPlay(settings: dir.appendingPathComponent("settings.json")) else { continue }
        let (file, volume) = sound
        lastPlay = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        p.arguments = ["-v", String(format: "%.3f", volume), file]
        do { try p.run() } catch { note("afplay failed: \(error)") }
        note("alert sound -> \((file as NSString).lastPathComponent) @ \(volume)")
    }
}
Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in pollErrorLogs() }
pollErrorLogs()

// Fallback tick: game started/stopped without an activation, EQBuddy gone, etc.
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in update(front: nil) }
note("started (pid \(getpid()), autohide \(autohide ? "on" : "off"), prefix \(prefix ?? "-"))")
update(front: nil)
RunLoop.main.run()
