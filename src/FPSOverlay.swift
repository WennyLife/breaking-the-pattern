import Cocoa
import Carbon

struct FPSObservation: Codable {
    var source: String = "WineD3D presentation log"
    let fps: Double
    let sourceSeconds: Double?
    let intervalSeconds: Double?
}

// Consume only WineD3D's presentation counter: wglSwapBuffers logs the same frames.
struct FPSParser {
    static let expression = try! NSRegularExpression(pattern: #"trace:fps:wined3d_cs_exec_present\s+([0-9A-Fa-fx]+)\s+@\s+approx\s+([0-9]+(?:\.[0-9]+)?)fps"#)
    static func parse(_ line: String) -> Double? {
        record(line)?.1
    }
    static func record(_ line: String) -> (String, Double)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = expression.firstMatch(in: line, range: range),
              let chainRange = Range(match.range(at: 1), in: line),
              let numberRange = Range(match.range(at: 2), in: line),
              let number = Double(line[numberRange]), number.isFinite, number >= 0, number <= 10000 else { return nil }
        return (String(line[chainRange]), number)
    }
}

// Apple Metal HUD logs presentation intervals in milliseconds. Reduce each
// emitted batch to a rate; these batches are not an exact per-frame capture.
struct MetalFPSParser {
    static let dateFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f
    }()
    static func observation(_ line: String) -> FPSObservation? {
        guard let marker = line.range(of: "metal-HUD: "),
              let time = dateFormat.date(from: String(line.prefix(23))) else { return nil }
        let fields = line[marker.upperBound...].split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count >= 5, (fields.count - 3) % 2 == 0 else { return nil }
        let numbers = fields.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == fields.count, numbers.allSatisfy({ $0.isFinite }) else { return nil }
        let intervals = stride(from: 3, to: numbers.count, by: 2).map { numbers[$0] }
        guard intervals.allSatisfy({ $0 > 0 && $0 < 60000 }) else { return nil }
        let fps = 1000 * Double(intervals.count) / intervals.reduce(0,+)
        guard fps <= 10000 else { return nil }
        return FPSObservation(source: "Apple Metal HUD presentation intervals", fps: fps, sourceSeconds: time.timeIntervalSince1970, intervalSeconds: nil)
    }
}

final class LogReader {
    let url: URL
    private var file: FileHandle?
    private var pending = Data()
    private var chains = Set<String>()
    private var inode: UInt64?
    private var offset: UInt64 = 0
    private(set) var reset = false
    private let tailExisting: Bool
    private var sourceTimes: [String: Double] = [:]
    private(set) var observations: [FPSObservation] = []
    init(_ path: String, tailExisting: Bool = false) { url = URL(fileURLWithPath: path); self.tailExisting = tailExisting }
    func poll() -> [Double] {
        reset = false
        observations.removeAll(keepingCapacity: true)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber, let node = attrs[.systemFileNumber] as? NSNumber else { return [] }
        if file == nil || inode != node.uint64Value || size.uint64Value < offset {
            let initial = inode == nil
            try? file?.close(); file = try? FileHandle(forReadingFrom: url)
            pending.removeAll(); chains.removeAll(); sourceTimes.removeAll(); offset = 0; inode = node.uint64Value; reset = true
            let old = (attrs[.modificationDate] as? Date).map { Date().timeIntervalSince($0) > 5 } ?? true
            if old || (initial && tailExisting) {
                offset = (try? file?.seekToEnd()) ?? 0
            }
        }
        guard let file, let chunk = try? file.read(upToCount: 65536), !chunk.isEmpty else { return [] }
        offset += UInt64(chunk.count)
        pending.append(chunk)
        var samples: [Double] = []
        while let end = pending.firstIndex(of: 10) {
            let line = String(decoding: pending[..<end], as: UTF8.self)
            pending.removeSubrange(...end)
            if let metal = MetalFPSParser.observation(line), let time = metal.sourceSeconds {
                let interval = sourceTimes["metal"].map { time - $0 }
                sourceTimes["metal"] = time
                if let interval, interval > 0 {
                    samples.append(metal.fps)
                    observations.append(FPSObservation(source: metal.source, fps: metal.fps, sourceSeconds: time, intervalSeconds: interval))
                }
            } else if let (chain, value) = FPSParser.record(line) {
                let time = line.split(separator: ":", maxSplits: 1).first.flatMap { Double($0) }
                let interval = time.flatMap { t in sourceTimes[chain].map { t - $0 } }
                if let time { sourceTimes[chain] = time }
                // Wine starts prev_time at zero; its first interval is not a valid FPS sample.
                if chains.insert(chain).inserted { continue }
                samples.append(value)
                observations.append(FPSObservation(fps: value, sourceSeconds: time, intervalSeconds: interval))
            }
        }
        // Keep memory bounded even if a third-party component writes a malformed long line.
        if pending.count > 65536 { pending.removeAll(keepingCapacity: true) }
        return samples
    }
    deinit { try? file?.close() }
}

// Local, append-only evidence from the same samples shown by the HUD.
// This is an interval average reported by Wine, not a frame-by-frame capture.
final class FPSTelemetry {
    let sessionID = UUID().uuidString
    let directory: URL
    let logPath: String
    let gamePID: pid_t?
    let events: FileHandle
    var lastState: String?
    var lastObservation: FPSObservation?
    var lastReceivedAt: Double?
    var recent: [(Double, Double)] = []
    var lastError: String?
    init(directory: URL, logPath: String, gamePID: pid_t?) throws {
        self.directory = directory; self.logPath = logPath; self.gamePID = gamePID
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let eventsURL = directory.appendingPathComponent("session-\(sessionID).jsonl")
        FileManager.default.createFile(atPath: eventsURL.path, contents: nil)
        events = try FileHandle(forWritingTo: eventsURL)
    }
    func record(_ observations: [FPSObservation], state: String, foreground: Bool?, displayed: Double?, now: Double = Date().timeIntervalSince1970) {
        if lastState != state || state != "live" { recent.removeAll() }
        do {
            for observation in observations {
                lastObservation = observation; lastReceivedAt = now
                let intervalOK = observation.intervalSeconds.map { $0 > 0 && $0 <= 2.5 } ?? false
                if foreground == true && intervalOK && lastState == "live" { recent.append((now, observation.fps)) }
                var sample: [String: Any] = ["kind": "sample", "session_id": sessionID, "received_at_unix": now, "fps": observation.fps, "state": state, "foreground": foreground as Any? ?? NSNull()]
                sample["source"] = observation.source
                sample["source_seconds"] = observation.sourceSeconds as Any? ?? NSNull()
                sample["interval_seconds"] = observation.intervalSeconds as Any? ?? NSNull()
                try append(sample)
            }
            recent.removeAll { now - $0.0 > 30 }
            guard lastState != state || !observations.isEmpty else { return }
            if lastState != state { try append(["kind": "state", "session_id": sessionID, "received_at_unix": now, "state": state]) }
            let values = recent.map(\.1)
            let snapshot: [String: Any] = [
                "schema_version": 1, "session_id": sessionID, "updated_at_unix": now,
                "game_pid": gamePID as Any? ?? NSNull(), "source_log": logPath,
                "source": lastObservation?.source ?? "waiting", "measurement": "presentation interval average",
                "frame_by_frame": false, "scene": "unknown", "state": state,
                "game_foreground": foreground as Any? ?? NSNull(),
                "displayed_fps": displayed.map { Double(String(format: "%.1f", $0))! } as Any? ?? NSNull(),
                "current_fps": displayed as Any? ?? NSNull(),
                "last_sample_received_at_unix": lastReceivedAt as Any? ?? NSNull(),
                "interval_seconds": lastObservation?.intervalSeconds as Any? ?? NSNull(),
                "foreground_recent_30s": ["sample_count": values.count, "minimum_interval_fps": values.min() as Any? ?? NSNull(), "maximum_interval_fps": values.max() as Any? ?? NSNull(), "mean_interval_fps": (values.isEmpty ? nil : values.reduce(0,+)/Double(values.count)) as Any? ?? NSNull()],
                "limitations": ["Menus and in-game pause cannot be distinguished from gameplay.", "Background and intervals longer than 2.5 seconds are excluded from foreground statistics.", "Interval minima are not 1% low or minimum per-frame FPS."]
            ]
            try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("latest.json"), options: .atomic)
            lastState = state; lastError = nil
        } catch { lastError = error.localizedDescription }
    }
    private func append(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(10); try events.write(contentsOf: data)
    }
    deinit { try? events.close() }
}

func argument(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

if CommandLine.arguments.contains("--self-test") {
    func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    require(FPSParser.parse("013c:trace:fps:wined3d_cs_exec_present 0247C510 @ approx 59.96fps") == 59.96, "real WineD3D line")
    require(FPSParser.parse("013c:trace:fps:wglSwapBuffers @ approx 59.96fps") == nil, "exclude duplicate OpenGL sample")
    require(FPSParser.parse("013c:trace:fps:wined3d_cs_exec_present 0247C510 @ approx 0.00fps") == 0, "retain real zero")
    require(FPSParser.parse("random fps: 60") == nil, "exclude unrelated output")
    let metal = MetalFPSParser.observation("2026-10-15 22:58:00.500 wine[123:456] metal-HUD: 100,600,1200,10,5,20,6")
    require(abs((metal?.fps ?? 0) - 66.6666667) < 0.001, "Metal averages intervals, not reciprocal rates")
    require(MetalFPSParser.observation("2026-10-15 22:58:00.500 wine[123:456] metal-HUD: 100,600,1200,0,5") == nil, "reject zero Metal interval")
    require(MetalFPSParser.observation("2026-10-15 22:58:00.500 wine[123:456] metal-HUD: 100,600,1200,nan,5") == nil, "reject nonfinite Metal interval")
    let path = NSTemporaryDirectory() + UUID().uuidString + ".log"
    FileManager.default.createFile(atPath: path, contents: Data())
    let writer = try! FileHandle(forWritingTo: URL(fileURLWithPath: path))
    let reader = LogReader(path)
    try! writer.write(contentsOf: Data("013c:trace:fps:wined3d_cs_exec_present 0247C510 @ approx 0.00fps\n".utf8))
    require(reader.poll().isEmpty, "discard first interval of swapchain")
    try! writer.write(contentsOf: Data("013c:trace:fps:wined3d_cs_exec_present 0247C510 @ approx 2".utf8))
    require(reader.poll().isEmpty, "incomplete line is withheld")
    try! writer.write(contentsOf: Data("5.50fps\n".utf8))
    require(reader.poll() == [25.5], "split line reassembled")
    require(reader.poll().isEmpty, "old sample not repeated")
    try! writer.write(contentsOf: Data("013c:trace:fps:wined3d_cs_exec_present 0247C510 @ approx 25.50fps\n013c:trace:fps:wined3d_cs_exec_present 0247C510 @ approx 25.50fps\n".utf8))
    require(reader.poll() == [25.5,25.5], "equal consecutive values are separate samples")
    let tail = LogReader(path, tailExisting: true)
    require(tail.poll().isEmpty, "live overlay never replays existing history")
    try! writer.truncate(atOffset: 0); try! writer.seek(toOffset: 0)
    require(reader.poll().isEmpty && reader.reset, "truncation resets partial data and session")
    try! writer.write(contentsOf: Data("100.000:013c:trace:fps:wined3d_cs_exec_present 0247C510 @ approx 0.00fps\n101.500:013c:trace:fps:wined3d_cs_exec_present 0247C510 @ approx 25.56fps\n".utf8))
    require(reader.poll() == [25.56], "timestamped sample retained exactly")
    require(reader.observations.last?.intervalSeconds == 1.5, "source interval preserved")
    let wineObservation = reader.observations
    try! writer.write(contentsOf: Data("2026-10-15 22:58:00.000 wine[123:456] metal-HUD: 100,600,1200,20,5\n2026-10-15 22:58:00.500 wine[123:456] metal-HUD: 130,600,1200,20,5\n".utf8))
    require(reader.poll() == [50], "Metal history initializes once")
    require(reader.observations.last?.intervalSeconds == 0.5, "Metal timestamps retain source cadence")
    require(reader.poll().isEmpty, "Metal samples are not replayed")
    let telemetryURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    let telemetry = try! FPSTelemetry(directory: telemetryURL, logPath: path, gamePID: 123)
    telemetry.record([], state: "live", foreground: true, displayed: nil, now: 1000)
    telemetry.record(wineObservation, state: "live", foreground: true, displayed: 25.56, now: 1001)
    func snapshot() -> [String: Any] { try! JSONSerialization.jsonObject(with: Data(contentsOf: telemetryURL.appendingPathComponent("latest.json"))) as! [String: Any] }
    require(telemetry.lastError == nil, "telemetry serialization succeeds")
    require(snapshot()["current_fps"] as? Double == 25.56, "unrounded source FPS retained")
    require(snapshot()["displayed_fps"] as? Double == 25.6, "HUD rounding explicitly recorded")
    require((snapshot()["foreground_recent_30s"] as? [String: Any])?["sample_count"] as? Int == 1, "foreground interval included")
    telemetry.record([], state: "background", foreground: false, displayed: 25.56, now: 1002)
    require((snapshot()["foreground_recent_30s"] as? [String: Any])?["sample_count"] as? Int == 0, "background clears foreground window")
    telemetry.record([], state: "stale", foreground: false, displayed: nil, now: 1008)
    require(snapshot()["current_fps"] is NSNull, "stale sample never reported as current")
    require(snapshot()["last_sample_received_at_unix"] as? Double == 1001, "stale timestamp does not advance")
    telemetry.record([], state: "stopped", foreground: nil, displayed: nil, now: 1009)
    require(snapshot()["state"] as? String == "stopped", "shutdown state recorded")
    let events = try! String(contentsOf: telemetryURL.appendingPathComponent("session-\(telemetry.sessionID).jsonl"), encoding: .utf8)
    require(events.split(separator: "\n").filter { $0.contains("\"kind\":\"sample\"") }.count == 1, "one JSONL event per fresh source sample")
    try? FileManager.default.removeItem(at: telemetryURL)
    try! writer.close()
    try? FileManager.default.removeItem(atPath: path)
    print("PASS: parser, source timestamps, exact/displayed values, foreground windows, stale state, shutdown and no sample replay")
    exit(0)
}

if let path = argument("--inspect-log") {
    let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
    let samples = lines.compactMap { FPSParser.parse(String($0)) ?? MetalFPSParser.observation(String($0))?.fps }
    print("samples=\(samples.count) last=\(samples.last.map { String($0) } ?? "none")")
    exit(0)
}

final class HUDView: NSView {
    var fps: Double?
    var details = false
    var average: Double?
    var minimum: Double?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSColor(calibratedRed: 0.039, green: 0.063, blue: 0.075, alpha: 0.90).setFill()
        let shape = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        shape.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke(); shape.lineWidth = 1; shape.stroke()
        let color: NSColor
        if let fps { color = fps >= 50 ? NSColor(red: 0.77, green: 0.92, blue: 0.53, alpha: 1) : fps >= 30 ? NSColor(red: 0.94, green: 0.83, blue: 0.51, alpha: 1) : NSColor(red: 0.96, green: 0.61, blue: 0.55, alpha: 1) }
        else { color = .secondaryLabelColor }
        let value = fps.map { String(format: "%.1f", $0) } ?? "—"
        (value as NSString).draw(at: NSPoint(x: 16, y: 10), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: (fps ?? 0) >= 100 ? 27 : 33, weight: .semibold), .foregroundColor: color])
        ("FPS" as NSString).draw(at: NSPoint(x: 111, y: 31), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor(red: 0.75, green: 0.8, blue: 0.74, alpha: 1)])
        if details {
            let avg = average.map { String(format: "%.1f", $0) } ?? "—"
            let low = minimum.map { String(format: "%.1f", $0) } ?? "—"
            let caption = "Média recente: \(avg)\nMenor amostra: \(low)"
            (caption as NSString).draw(in: NSRect(x: 16, y: 65, width: 175, height: 38), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.lightGray])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var view: HUDView!
    var timer: Timer?
    var status: NSStatusItem!
    var reader: LogReader?
    var lastSample: TimeInterval?
    var history: [(TimeInterval, Double)] = []
    var right = false
    var details = false
    var parentPID: pid_t?
    var started = ProcessInfo.processInfo.systemUptime
    var diagnostics: FileHandle?
    var hotKey: EventHotKeyRef?
    var hidden = false
    var telemetry: FPSTelemetry?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let path = argument("--log") else {
            let alert = NSAlert(); alert.messageText = "Contador de FPS do Underground 2"
            alert.informativeText = "Abra o aplicativo ‘Need for Speed Underground 2’. O contador inicia automaticamente com ele. Use Command + Option + 9 para mostrar ou ocultar."
            alert.runModal(); NSApp.terminate(nil); return
        }
        reader = LogReader(path, tailExisting: true)
        if let raw = argument("--parent-pid"), let pid = Int32(raw) { parentPID = pid }
        let telemetryDirectory = argument("--telemetry-dir").map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Underground 2 FPS/Telemetria")
        telemetry = try? FPSTelemetry(directory: telemetryDirectory, logPath: path, gamePID: parentPID)
        if let path = argument("--diagnostics") {
            FileManager.default.createFile(atPath: path, contents: Data())
            diagnostics = try? FileHandle(forWritingTo: URL(fileURLWithPath: path))
        }
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 154, height: 70), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Underground 2 FPS"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        // Wine raises fullscreen windows above NSStatusWindowLevel, or above the
        // shielding level when capturing a display. Keep this click-through HUD above both.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
        panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        view = HUDView(frame: NSRect(x: 0, y: 0, width: 154, height: 70))
        view.setAccessibilityElement(true); view.setAccessibilityRole(.staticText)
        view.setAccessibilityLabel("FPS do Underground 2")
        view.setAccessibilityValue("Aguardando medição")
        panel.contentView = view
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "FPS"
        let menu = NSMenu()
        for (title, selector) in [("Mostrar / esconder · ⌘⌥9", #selector(toggleVisibility)), ("Alternar detalhes", #selector(toggleDetails)), ("Mover para o outro canto", #selector(togglePosition)), ("Fechar contador", #selector(closeHUD))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        status.menu = menu
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            delegate.toggleVisibility()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), nil)
        let registration = RegisterEventHotKey(UInt32(kVK_ANSI_9), UInt32(cmdKey | optionKey), EventHotKeyID(signature: 0x4E465350, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        try? diagnostics?.write(contentsOf: Data("hotkey_command_option_9_status=\(registration) window_level=\(panel.level.rawValue)\n".utf8))
        position(); panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(self, selector: #selector(position), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        tick()
    }
    @objc func position() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main else { return }
        let size = NSSize(width: details ? 205 : 154, height: details ? 112 : 70)
        let frame = screen.frame
        panel.setFrame(NSRect(x: right ? frame.maxX - size.width - 24 : frame.minX + 24, y: frame.maxY - size.height - 52, width: size.width, height: size.height), display: true)
        view.frame = NSRect(origin: .zero, size: size)
    }
    @objc func toggleDetails() { details.toggle(); view.details = details; position(); view.needsDisplay = true }
    @objc func togglePosition() { right.toggle(); position() }
    @objc func closeHUD() { NSApp.terminate(nil) }
    @objc func toggleVisibility() {
        hidden.toggle()
        if hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if let parentPID, kill(parentPID, 0) != 0 && errno == ESRCH { NSApp.terminate(nil); return }
        let samples = reader?.poll() ?? []
        if reader?.reset == true {
            lastSample = nil; history.removeAll(); view.fps = nil; view.average = nil; view.minimum = nil; view.needsDisplay = true
        }
        if !samples.isEmpty {
            lastSample = now
            history.append(contentsOf: samples.map { (now, $0) })
            history.removeAll { now - $0.0 > 30 }
            view.fps = samples.last
            view.setAccessibilityValue(samples.last.map { String(format: "%.1f FPS", $0) } ?? "Aguardando medição")
            view.average = history.map(\.1).reduce(0, +) / Double(history.count)
            view.minimum = history.map(\.1).min()
            view.needsDisplay = true
            if let value = samples.last {
                try? diagnostics?.write(contentsOf: Data("measured_fps=\(value) samples=\(samples.count)\n".utf8))
            }
        } else if now - (lastSample ?? started) > 5, view.fps != nil {
            view.fps = nil; view.average = nil; view.minimum = nil; history.removeAll(); view.needsDisplay = true
            view.setAccessibilityValue("Sem medição recente")
            try? diagnostics?.write(contentsOf: Data("stale=no_current_sample\n".utf8))
        }
        let foreground = parentPID.map { NSWorkspace.shared.frontmostApplication?.processIdentifier == $0 }
        let state = view.fps == nil ? (lastSample == nil ? "waiting" : "stale") : (foreground == false ? "background" : "live")
        telemetry?.record(reader?.observations ?? [], state: state, foreground: foreground, displayed: view.fps)
    }
    func applicationWillTerminate(_ notification: Notification) {
        telemetry?.record([], state: "stopped", foreground: nil, displayed: nil)
        timer?.invalidate(); if let hotKey { UnregisterEventHotKey(hotKey) }; try? diagnostics?.close()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
