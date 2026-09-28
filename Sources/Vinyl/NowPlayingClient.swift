import AppKit

struct NowPlaying: Equatable {
    var isPlaying = false
    var title: String?
    var artist: String?
    var album: String?
    var appBundleID: String?
    var duration: Double?
    var elapsed: Double?
    var timestamp: Double?
    var rate: Double?

    func position(at now: Date = Date()) -> Double? {
        guard let elapsed else { return nil }
        guard let timestamp, let rate, rate > 0 else { return elapsed }
        return elapsed + (now.timeIntervalSince1970 - timestamp) * rate
    }

    func progress(at now: Date = Date()) -> Double? {
        guard let duration, duration > 1, let position = position(at: now) else { return nil }
        return min(max(position / duration, 0), 1)
    }

    func remaining(at now: Date = Date()) -> Double? {
        guard let duration, duration > 1, let position = position(at: now) else { return nil }
        return max(0, duration - position)
    }

    var artworkToken = 0

    static func == (lhs: NowPlaying, rhs: NowPlaying) -> Bool {
        lhs.isPlaying == rhs.isPlaying && lhs.title == rhs.title && lhs.artist == rhs.artist
            && lhs.album == rhs.album && lhs.appBundleID == rhs.appBundleID
            && lhs.artworkToken == rhs.artworkToken && lhs.duration == rhs.duration
            && lhs.elapsed == rhs.elapsed && lhs.timestamp == rhs.timestamp
            && lhs.rate == rhs.rate
    }
}

final class NowPlayingClient {
    var onChange: ((NowPlaying, NSImage?) -> Void)?

    private var process: Process?
    private var stdinPipe: Pipe?
    private var buffer = Data()
    private var state = NowPlaying()
    private var artwork: NSImage?
    private var artworkCounter = 0
    private var restartDelay: TimeInterval = 1
    private var isStopping = false

    private static let bridgeName = "libNowPlayingBridge.dylib"

    func start() {
        isStopping = false
        launch()
    }

    func stop() {
        isStopping = true
        process?.terminate()
        process = nil
    }

    func send(_ command: String) {
        guard let handle = stdinPipe?.fileHandleForWriting,
              let data = (command + "\n").data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
    }

    private static func bridgeURL() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent(bridgeName),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        let beside = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent(bridgeName)
        return FileManager.default.fileExists(atPath: beside.path) ? beside : nil
    }

    private func launch() {
        guard let bridge = Self.bridgeURL() else {
            NSLog("Vinyl: \(Self.bridgeName) not found")
            return
        }

        let script = """
        DynaLoader::dl_load_file($ARGV[0], 0x01) or die "vinyl: cannot load bridge\\n";
        select(undef, undef, undef, undef);
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = ["-MDynaLoader", "-e", script, bridge.path]

        let out = Pipe()
        let input = Pipe()
        task.standardOutput = out
        task.standardInput = input
        task.standardError = FileHandle.nullDevice

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(chunk) }
        }

        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.helperDied() }
        }

        do {
            try task.run()
        } catch {
            NSLog("Vinyl: helper failed to launch — \(error)")
            return
        }

        process = task
        stdinPipe = input
        restartDelay = 1
    }

    private func helperDied() {
        guard !isStopping else { return }
        process = nil
        stdinPipe = nil
        buffer.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay) { [weak self] in
            guard let self, !self.isStopping else { return }
            self.restartDelay = min(self.restartDelay * 2, 30)
            self.launch()
        }
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty else { continue }
            handle(line: Data(line))
        }
    }

    private func handle(line: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }

        if let error = json["error"] as? String {
            NSLog("Vinyl: bridge error — \(error)")
            return
        }

        var next = NowPlaying()
        next.isPlaying = json["playing"] as? Bool ?? false
        next.title = json["title"] as? String
        next.artist = json["artist"] as? String
        next.album = json["album"] as? String
        next.appBundleID = json["app"] as? String
        next.duration = json["duration"] as? Double
        next.elapsed = json["elapsed"] as? Double
        next.timestamp = json["timestamp"] as? Double
        next.rate = json["rate"] as? Double

        if json.keys.contains("artwork") {
            if let base64 = json["artwork"] as? String,
               let data = Data(base64Encoded: base64),
               let image = NSImage(data: data) {
                artwork = image
            } else {
                artwork = nil
            }
            artworkCounter += 1
        }
        next.artworkToken = artworkCounter

        guard next != state else { return }
        state = next
        onChange?(next, artwork)
    }
}
