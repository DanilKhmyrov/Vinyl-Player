import AVFoundation

enum SoundSlot: String, CaseIterable {
    case scratch, ambience, swap, start, stop

    var name: String {
        switch self {
        case .scratch: return L.t("Прокрутка рукой", "Hand scratch")
        case .ambience: return L.t("Шум при игре", "Ambience while playing")
        case .swap: return L.t("Смена пластинки", "Record swap")
        case .start: return L.t("Запуск (play)", "Start (play)")
        case .stop: return L.t("Пауза (stop)", "Pause (stop)")
        }
    }

    var isLoop: Bool { self == .scratch || self == .ambience }

    var defaultChoice: String? {
        switch self {
        case .scratch, .swap: return Sounds.builtInName
        default: return nil
        }
    }
}

final class Sounds {
    static let shared = Sounds()

    private let engine = AVAudioEngine()
    private let varispeed = AVAudioUnitVarispeed()
    private var players: [SoundSlot: AVAudioPlayerNode] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private var cache: [SoundSlot: AVAudioPCMBuffer] = [:]
    private var wired = false
    private var idleWork: DispatchWorkItem?
    private var ambienceRunning = false
    private var musicPlaying = false
    private var pendingShots = 0

    private init() {}

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vinyl", isDirectory: true)
    }

    private static func folder(for slot: SoundSlot) -> URL {
        folder.appendingPathComponent("sounds/\(slot.rawValue)", isDirectory: true)
    }

    private static let extensions = ["wav", "aiff", "aif", "m4a", "mp3", "caf"]

    static let builtInName = "Vinyl"

    static func installBuiltIns() {
        let fileManager = FileManager.default
        for slot in SoundSlot.allCases {
            guard let source = Bundle.main.url(forResource: slot.rawValue, withExtension: "wav", subdirectory: "Sounds"),
                  let data = try? Data(contentsOf: source) else { continue }
            let directory = folder(for: slot)
            let target = directory.appendingPathComponent("\(builtInName).wav")
            if let existing = try? Data(contentsOf: target), existing == data { continue }
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: target)
        }
    }

    static func variants(for slot: SoundSlot) -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder(for: slot), includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    func forget() {
        cache.removeAll()
    }

    private func player(for slot: SoundSlot) -> AVAudioPlayerNode {
        if let existing = players[slot] { return existing }
        let node = AVAudioPlayerNode()
        players[slot] = node
        return node
    }

    private func ensureRunning() -> Bool {
        idleWork?.cancel()
        if !wired {
            engine.attach(varispeed)
            engine.connect(varispeed, to: engine.mainMixerNode, format: format)
            for slot in SoundSlot.allCases {
                let node = player(for: slot)
                engine.attach(node)
                engine.connect(node, to: slot == .scratch ? varispeed : engine.mainMixerNode,
                               format: format)
            }
            wired = true
        }
        guard !engine.isRunning else { return true }
        do {
            try engine.start()
            return true
        } catch {
            NSLog("Vinyl: audio engine failed — \(error)")
            return false
        }
    }

    private func stopWhenIdle(after delay: TimeInterval = 3) {
        idleWork?.cancel()
        guard !ambienceRunning, pendingShots == 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.ambienceRunning, self.pendingShots == 0 else { return }
            self.engine.stop()
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func buffer(for slot: SoundSlot) -> AVAudioPCMBuffer? {
        if let cached = cache[slot] { return cached }
        guard let choice = Preferences.soundChoice(for: slot), !choice.isEmpty else { return nil }
        for ext in Self.extensions {
            let url = Self.folder(for: slot).appendingPathComponent("\(choice).\(ext)")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let loaded = read(url) {
                cache[slot] = loaded
                return loaded
            }
        }
        return nil
    }

    private func read(_ url: URL) -> AVAudioPCMBuffer? {
        do {
            let file = try AVAudioFile(forReading: url)
            guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length))
            else { return nil }
            try file.read(into: source)
            if file.processingFormat == format { return source }

            guard let converter = AVAudioConverter(from: file.processingFormat, to: format),
                  let output = AVAudioPCMBuffer(
                      pcmFormat: format,
                      frameCapacity: AVAudioFrameCount(Double(source.frameLength)
                          * format.sampleRate / file.processingFormat.sampleRate) + 4096)
            else { return nil }
            var fed = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true; status.pointee = .haveData; return source
            }
            return error == nil ? output : nil
        } catch {
            NSLog("Vinyl: could not read \(url.lastPathComponent) — \(error)")
            return nil
        }
    }

    func play(_ slot: SoundSlot) {
        guard !slot.isLoop, let buffer = buffer(for: slot), ensureRunning() else { return }
        let node = player(for: slot)
        node.stop()
        node.volume = Float(Preferences.soundVolume) * 0.7
        pendingShots += 1
        node.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingShots = max(0, self.pendingShots - 1)
                node.stop()
                self.stopWhenIdle()
            }
        }
        node.play()
    }

    func setPlaying(_ playing: Bool) {
        guard playing != musicPlaying else { return }
        musicPlaying = playing
        play(playing ? .start : .stop)
        refreshAmbience()
    }

    func refreshAmbience() {
        guard musicPlaying, let buffer = buffer(for: .ambience), ensureRunning() else {
            if ambienceRunning {
                players[.ambience]?.stop()
                ambienceRunning = false
                stopWhenIdle()
            }
            return
        }
        let node = player(for: .ambience)
        node.stop()
        node.volume = Float(Preferences.soundVolume) * 0.22
        node.scheduleBuffer(buffer, at: nil, options: .loops)
        node.play()
        ambienceRunning = true
    }

    func refreshVolume() {
        if ambienceRunning {
            players[.ambience]?.volume = Float(Preferences.soundVolume) * 0.22
        }
    }

    func beginScratch() {
        guard let buffer = buffer(for: .scratch), ensureRunning() else { return }
        idleWork?.cancel()
        let node = player(for: .scratch)
        node.volume = 0
        node.scheduleBuffer(buffer, at: nil, options: .loops)
        node.play()
    }

    func updateScratch(turnsPerSecond: Double) {
        let speed = min(abs(turnsPerSecond), 6)
        varispeed.rate = Float(min(max(0.4 + speed * 0.7, 0.4), 4))
        players[.scratch]?.volume =
            Float(min(speed * 0.8, 1) * Preferences.soundVolume) * 0.30
    }

    func endScratch() {
        players[.scratch]?.volume = 0
        players[.scratch]?.stop()
        stopWhenIdle()
    }
}
