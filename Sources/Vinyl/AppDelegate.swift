import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: WidgetWindow!
    private var record: RecordView!
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindowController?
    private let client = NowPlayingClient()
    private var current = NowPlaying()
    private var currentArtwork: NSImage?
    private var history: [String] = []
    private var sessionTrackCount = 0
    private let sessionStart = Date()
    private var listenAccumulated: TimeInterval = 0
    private var listenSince: Date?
    private var crateWindow: WidgetWindow?
    private var crateView: CrateView?
    private var crateCovers: [CGImage] = []
    private var crateTitles: [String] = []
    private var crateToken = 0
    private var crateToast: NSWindow?

    private let audioMeter = AudioMeter()
    private var leftMeterWindow: WidgetWindow?
    private var rightMeterWindow: WidgetWindow?
    private var leftMeterView: EqualizerView?
    private var rightMeterView: EqualizerView?
    private var spectrumWindow: WidgetWindow?
    private var spectrumView: EqualizerView?
    private var meterTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Sounds.installBuiltIns()

        record = RecordView(configuration: Self.currentConfiguration())
        record.secondsPerRevolution = Preferences.secondsPerRevolution
        window = WidgetWindow(canvas: record.canvasSize)
        record.onToggle = { [weak self] in self?.client.send("toggle") }
        record.onNext = { [weak self] in self?.client.send("next") }
        record.onPrevious = { [weak self] in self?.client.send("prev") }
        record.onOpenPlayer = { [weak self] in
            guard let id = self?.current.appBundleID,
                  let app = NSRunningApplication.runningApplications(
                      withBundleIdentifier: id).first else { return }
            app.activate()
        }
        record.onSeek = { [weak self] seconds in
            self?.client.send(String(format: "seek %.2f", seconds))
        }
        record.contextMenuProvider = { [weak self] in
            let menu = NSMenu()
            self?.populate(menu)
            return menu
        }
        record.backSideProvider = { [weak self] in self?.sleeveBackLines() ?? [] }
        window.contentView = record
        window.restorePosition()
        window.alphaValue = Preferences.opacity
        window.orderFront(nil)

        history = Preferences.savedHistory
        loadCrate()
        setUpStatusItem()
        applyCrate()
        setUpEqualizer()
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main
        ) { [weak self] _ in self?.positionMeters() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rescueOffscreenWindows() }

        client.onChange = { [weak self] state, artwork in
            self?.apply(state: state, artwork: artwork)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.window.isVisible else { return }
            guard !(Preferences.hideWhenIdle && !self.current.isPlaying) else { return }
            self.window.applyLevel()
            self.window.orderFront(nil)
            self.crateWindow?.applyLevel()
            self.crateWindow?.orderFront(nil)
            self.orderMetersFront()
        }

        client.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let title = current.title {
            PlayLog.append(artist: current.artist, title: title, seconds: Int(listenedSoFar()))
        }
        client.stop()
        audioMeter.stop()
    }

    private static func currentConfiguration() -> RecordView.Configuration {
        RecordView.Configuration(sleeveSide: CGFloat(Preferences.diameter),
                                 themeID: Preferences.themeID,
                                 showsCaption: Preferences.showCaption,
                                 showsProgress: Preferences.showProgress,
                                 showsTime: Preferences.showTime,
                                 sideID: Preferences.sideID,
                                 accentID: Preferences.accentID)
    }

    private func applyConfiguration() {
        record.configuration = Self.currentConfiguration()
        window.resize(to: record.canvasSize)
        if Preferences.showCrate { applyCrate() }
        window.alphaValue = Preferences.opacity
        record.setNowPlaying(title: current.title, artist: current.artist, artwork: currentArtwork)
        if Preferences.showEqualizer { buildMeterWindows() }
    }

    private func sleeveBackLines() -> [String] {
        var lines: [String] = []

        if let title = current.title, !title.isEmpty {
            lines.append("#" + L.t("Сейчас играет", "Now playing"))
            if let artist = current.artist, !artist.isEmpty { lines.append(artist) }
            lines.append("*" + title)
            lines.append("")
        }

        let played = history.prefix(6).filter { entry in
            let trimmed = entry.trimmingCharacters(in: CharacterSet(charactersIn: " —-"))
            return !trimmed.isEmpty
        }
        if !played.isEmpty {
            lines.append("#" + L.t("До этого", "Before this"))
            for (index, entry) in played.enumerated() { lines.append("\(index + 1). \(entry)") }
        }

        let today = PlayLog.summary(PlayLog.load(),
                                    since: Calendar.current.startOfDay(for: Date()))
        if today.tracks > 0 {
            lines.append("")
            lines.append("#" + L.t("Сегодня", "Today"))
            lines.append("\(today.tracks) \(PlayLog.plural(today.tracks))"
                         + " · " + PlayLog.duration(today.seconds))
        }
        return lines
    }

    private func isStranded(_ frame: NSRect) -> Bool {
        !NSScreen.screens.contains { screen in
            let overlap = screen.frame.intersection(frame)
            guard !overlap.isNull else { return false }
            return overlap.width * overlap.height >= frame.width * frame.height * 0.25
        }
    }

    private func rescueOffscreenWindows() {
        if isStranded(window.frame) {
            window.placeAtDefaultPosition()
            Preferences.origin = window.frame.origin
        }
        window.applyLevel()
        if let crateWindow, isStranded(crateWindow.frame) {
            crateWindow.placeAtDefaultPosition()
            Preferences.crateOrigin = crateWindow.frame.origin
        }
        crateWindow?.applyLevel()
        positionMeters()
        orderMetersFront()
    }

    private func listenedSoFar() -> TimeInterval {
        listenAccumulated + (listenSince.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func apply(state: NowPlaying, artwork: NSImage?) {
        if let previous = current.title, state.title != previous {
            let artist = current.artist.map { "\($0) — " } ?? ""
            pushToCrate(currentArtwork, label: artist + previous)
            Sounds.shared.play(.swap)
            sessionTrackCount += 1
            let entry = artist + previous
            if !entry.trimmingCharacters(in: CharacterSet(charactersIn: " —-")).isEmpty {
                history.removeAll { $0 == entry }
                history.insert(entry, at: 0)
                history = Array(history.prefix(8))
                Preferences.savedHistory = history
            }
            PlayLog.append(artist: current.artist, title: previous,
                           seconds: Int(listenedSoFar()))
            listenAccumulated = 0
            listenSince = state.isPlaying ? Date() : nil
        } else if state.isPlaying != current.isPlaying {
            if state.isPlaying {
                listenSince = Date()
            } else {
                listenAccumulated = listenedSoFar()
                listenSince = nil
            }
        }
        if state.artworkToken != current.artworkToken || state.title != current.title {
            currentArtwork = artwork
            record.setNowPlaying(title: state.title, artist: state.artist, artwork: artwork)
        }
        if state.isPlaying != current.isPlaying { updateStatusIcon(playing: state.isPlaying) }
        if Preferences.hideWhenIdle && !state.isPlaying {
            window.orderOut(nil)
            crateWindow?.orderOut(nil)
            orderMetersOut()
        } else if !window.isVisible {
            window.orderFront(nil)
            window.applyLevel()
            if Preferences.showCrate { applyCrate() }
            orderMetersFront()
        }
        Sounds.shared.setPlaying(state.isPlaying)
        record.setSpinning(state.isPlaying)
        record.setProgress(state.progress(), duration: state.duration,
                           playing: state.isPlaying)
        current = state
    }

    private var sessionSummary: String {
        let minutes = max(0, Int(Date().timeIntervalSince(sessionStart) / 60))
        let hours = minutes / 60
        let time = hours > 0
            ? L.t("\(hours) ч \(minutes % 60) мин", "\(hours) h \(minutes % 60) min")
            : L.t("\(minutes) мин", "\(minutes) min")
        let noun = PlayLog.plural(sessionTrackCount)
        return L.t("За сессию: \(sessionTrackCount) \(noun), \(time)",
                   "This session: \(sessionTrackCount) \(noun), \(time)")
    }

    private var crateSide: CGFloat { CGFloat(Preferences.diameter) * CGFloat(Preferences.crateSizeMultiplier) }

    private func pushToCrate(_ artwork: NSImage?, label: String) {
        guard let artwork,
              let source = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        crateToken += 1
        guard let cover = RecordArtwork.cover(from: source, token: 900_000 + crateToken,
                                              side: crateSide,
                                              theme: Theme.named(Preferences.themeID), scale: 2)
        else { return }
        crateCovers.insert(cover, at: 0)
        crateTitles.insert(label, at: 0)
        crateCovers = Array(crateCovers.prefix(Preferences.crateDepth))
        crateTitles = Array(crateTitles.prefix(Preferences.crateDepth))
        crateView?.show(crateCovers, animated: true)
        saveCrate()
    }

    private var crateFolder: URL {
        Sounds.folder.appendingPathComponent("crate", isDirectory: true)
    }

    private func saveCrate() {
        let folder = crateFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let existing = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil) {
            for url in existing { try? FileManager.default.removeItem(at: url) }
        }
        for (index, cover) in crateCovers.enumerated() {
            guard let data = NSBitmapImageRep(cgImage: cover)
                .representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: folder.appendingPathComponent("\(index).png"))
        }
        let titles = crateTitles.joined(separator: "\n")
        try? titles.write(to: folder.appendingPathComponent("titles.txt"),
                          atomically: true, encoding: .utf8)
    }

    private func loadCrate() {
        let folder = crateFolder
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil) else { return }
        let covers = files
            .filter { $0.pathExtension == "png" }
            .sorted { (Int($0.deletingPathExtension().lastPathComponent) ?? 0)
                    < (Int($1.deletingPathExtension().lastPathComponent) ?? 0) }
            .compactMap { NSImage(contentsOfFile: $0.path)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil) }
        guard !covers.isEmpty else { return }
        crateCovers = covers
        let titlesFile = folder.appendingPathComponent("titles.txt")
        let titles = (try? String(contentsOf: titlesFile, encoding: .utf8))?
            .components(separatedBy: "\n") ?? []
        crateTitles = titles + Array(repeating: "", count: max(0, covers.count - titles.count))
    }

    private func applyCrate() {
        guard Preferences.showCrate else {
            crateWindow?.orderOut(nil)
            crateWindow = nil
            crateView = nil
            return
        }
        let style = CrateStyle(rawValue: Preferences.crateStyleID) ?? .rack
        let view = CrateView(side: crateSide, themeID: Preferences.themeID,
                             depth: Preferences.crateDepth, style: style,
                             reflections: Preferences.crateReflections)
        view.onSelectCard = { [weak self] index in self?.selectedCrateCard(index) }
        view.contextMenuProvider = { [weak self] in
            let menu = NSMenu()
            self?.populate(menu)
            return menu
        }
        let panel = WidgetWindow(canvas: view.frame.size)
        panel.contentView = view
        panel.restore(Preferences.crateOrigin)
        panel.alphaValue = Preferences.opacity
        panel.orderFront(nil)
        crateWindow?.orderOut(nil)
        crateWindow = panel
        crateView = view
        view.show(crateCovers, animated: false)
    }

    private var equalizerStyle: EqualizerStyle {
        EqualizerStyle(rawValue: Preferences.equalizerStyleID) ?? .hifi
    }
    private var equalizerMode: EqualizerMode {
        EqualizerMode(rawValue: Preferences.equalizerModeID) ?? .spectrum
    }
    private var equalizerAccentColor: NSColor { record.currentAccentColor }
    private var meterSize: CGSize {
        let height = record.artworkRect.height
        return CGSize(width: max(16, height * 0.09), height: height)
    }

    private var spectrumSize: CGSize {
        let width = record.artworkRect.width * 1.15
        return CGSize(width: width, height: max(48, width * 0.34))
    }

    private func setUpEqualizer() {
        guard Preferences.showEqualizer else { return }
        audioMeter.start()
        buildMeterWindows()
        startMeterTimer()
    }

    private func buildMeterWindows() {
        for panel in [leftMeterWindow, rightMeterWindow, spectrumWindow] { panel?.orderOut(nil) }
        leftMeterWindow = nil; rightMeterWindow = nil
        leftMeterView = nil; rightMeterView = nil
        spectrumWindow = nil; spectrumView = nil

        let style = equalizerStyle
        let accent = equalizerAccentColor

        switch equalizerMode {
        case .level:
            let size = EqualizerView.windowSize(for: meterSize)
            let left = EqualizerView(frame: NSRect(origin: .zero, size: size),
                                     style: style, accentColor: accent, columns: 1)
            let leftPanel = WidgetWindow(canvas: size)
            leftPanel.isMovable = false
            leftPanel.contentView = left
            let right = EqualizerView(frame: NSRect(origin: .zero, size: size),
                                      style: style, accentColor: accent, columns: 1)
            let rightPanel = WidgetWindow(canvas: size)
            rightPanel.isMovable = false
            rightPanel.contentView = right
            leftMeterWindow = leftPanel
            rightMeterWindow = rightPanel
            leftMeterView = left
            rightMeterView = right
            positionMeters()
            leftPanel.alphaValue = Preferences.opacity
            rightPanel.alphaValue = Preferences.opacity

        case .spectrum:
            let size = EqualizerView.windowSize(for: spectrumSize)
            let view = EqualizerView(frame: NSRect(origin: .zero, size: size), style: style,
                                     accentColor: accent, columns: AudioMeter.bandCount,
                                     standalone: true)
            view.contextMenuProvider = { [weak self] in
                let menu = NSMenu()
                self?.populate(menu)
                return menu
            }
            let panel = WidgetWindow(canvas: size)
            panel.contentView = view
            view.onMoved = { [weak panel] in
                guard let panel else { return }
                Preferences.spectrumOrigin = panel.frame.origin
            }
            panel.restore(Preferences.spectrumOrigin)
            panel.alphaValue = Preferences.opacity
            spectrumWindow = panel
            spectrumView = view
        }
        if window.isVisible { orderMetersFront() }
    }

    private func positionMeters() {
        guard let left = leftMeterWindow, let right = rightMeterWindow else { return }
        let gap: CGFloat = 10
        let margin = EqualizerView.glowMargin
        let anchor = window.frame
        let sleeve = record.artworkRect
        let extent = record.fullExtentRect
        let y = anchor.minY + sleeve.midY - left.frame.height / 2
        let extentMinX = anchor.minX + extent.minX
        let extentMaxX = anchor.minX + extent.maxX
        left.setFrameOrigin(NSPoint(x: extentMinX - gap - left.frame.width + margin, y: y))
        right.setFrameOrigin(NSPoint(x: extentMaxX + gap - margin, y: y))
    }

    private func orderMetersFront() {
        for panel in [leftMeterWindow, rightMeterWindow, spectrumWindow] {
            panel?.applyLevel()
            panel?.orderFront(nil)
        }
    }

    private func orderMetersOut() {
        for panel in [leftMeterWindow, rightMeterWindow, spectrumWindow] { panel?.orderOut(nil) }
    }

    private func startMeterTimer() {
        guard meterTimer == nil else { return }
        var lastAccent: NSColor?
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self,
                  (self.leftMeterWindow?.isVisible ?? false) || (self.spectrumWindow?.isVisible ?? false)
            else { return }
            switch self.equalizerMode {
            case .level:
                self.leftMeterView?.update(levels: [self.audioMeter.left])
                self.rightMeterView?.update(levels: [self.audioMeter.right])
            case .spectrum:
                self.spectrumView?.update(levels: (0..<AudioMeter.bandCount)
                    .map { self.audioMeter.band(at: $0) })
            }
            guard self.equalizerStyle.usesAccent else { return }
            let accent = self.equalizerAccentColor
            guard !accent.isEqual(lastAccent) else { return }
            lastAccent = accent
            self.leftMeterView?.accentColor = accent
            self.rightMeterView?.accentColor = accent
            self.leftMeterView?.refreshColors()
            self.rightMeterView?.refreshColors()
        }
    }

    @objc func toggleEqualizer() {
        Preferences.showEqualizer.toggle()
        if Preferences.showEqualizer {
            setUpEqualizer()
        } else {
            meterTimer?.invalidate()
            meterTimer = nil
            orderMetersOut()
            leftMeterWindow = nil
            rightMeterWindow = nil
            leftMeterView = nil
            rightMeterView = nil
            spectrumWindow = nil
            spectrumView = nil
            audioMeter.stop()
        }
    }

    @objc func setEqualizerStyle(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Preferences.equalizerStyleID = id
        if Preferences.showEqualizer { buildMeterWindows() }
    }

    func audioMeterStatusText() -> (text: String, offerPrivacy: Bool)? {
        guard Preferences.showEqualizer else { return nil }
        switch audioMeter.status {
        case .stopped:
            return (L.t("Захват звука выключен.", "Audio capture is off."), false)
        case .unsupported:
            return (L.t("Нужна macOS 14.4 или новее — на этой системе захват звука недоступен.",
                        "Needs macOS 14.4 or newer — audio capture isn't available on this system."),
                    false)
        case .failed(let reason):
            return (L.t("Не удалось начать захват звука (\(reason)).",
                        "Couldn't start audio capture (\(reason))."), true)
        case .waiting:
            return (L.t("Звук пока не приходит. Если музыка играет, а столбики не шевелятся — "
                        + "macOS не дала доступ к записи звука системы.",
                        "No audio yet. If something is playing and the bars stay dark, "
                        + "macOS hasn't granted access to system audio."), true)
        case .receiving:
            return (L.t("Звук приходит — эквалайзер работает.",
                        "Audio is coming through — the equalizer is working."), false)
        }
    }

    @objc func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func setEqualizerMode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Preferences.equalizerModeID = id
        if Preferences.showEqualizer { buildMeterWindows() }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(playing: false)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateStatusIcon(playing: Bool) {
        let symbol = playing ? "opticaldisc.fill" : "opticaldisc"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Vinyl")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem()
        header.view = headerRow()
        menu.addItem(header)

        let transport = NSMenuItem()
        transport.view = transportRow()
        menu.addItem(transport)
        menu.addItem(.separator())

        if !history.isEmpty {
            menu.addItem(submenu(L.t("Недавние", "Recent"), symbol: "clock.arrow.circlepath") { sub in
                let stats = NSMenuItem(title: sessionSummary, action: nil, keyEquivalent: "")
                stats.isEnabled = false
                sub.addItem(stats)
                sub.addItem(.separator())
                for track in history {
                    let entry = NSMenuItem(title: track, action: nil, keyEquivalent: "")
                    entry.isEnabled = false
                    sub.addItem(entry)
                }
            })
            menu.addItem(.separator())
        }

        menu.addItem(item(L.t("Собрать всё на место", "Bring everything back"), #selector(resetPosition),
                          symbol: "scope"))
        menu.addItem(item(L.t("Настройки…", "Settings…"), #selector(openSettings),
                          symbol: "gearshape"))
        menu.addItem(item(L.t("Выйти", "Quit"), #selector(quit), symbol: "xmark.circle"))
    }

    private func headerRow() -> NSView {
        let art = NSImageView()
        art.image = currentArtwork ?? NSImage(systemSymbolName: "opticaldisc",
                                              accessibilityDescription: nil)
        art.imageScaling = .scaleProportionallyUpOrDown
        art.wantsLayer = true
        art.layer?.cornerRadius = 6
        art.layer?.masksToBounds = true
        art.translatesAutoresizingMaskIntoConstraints = false
        art.widthAnchor.constraint(equalToConstant: 42).isActive = true
        art.heightAnchor.constraint(equalToConstant: 42).isActive = true

        let title = NSTextField(labelWithString: current.title ?? L.t("Ничего не играет", "Nothing playing"))
        title.font = .boldSystemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1

        var textViews: [NSView] = [title]
        if let artist = current.artist, !artist.isEmpty {
            let artistLabel = NSTextField(labelWithString: artist)
            artistLabel.font = .systemFont(ofSize: 11)
            artistLabel.textColor = .secondaryLabelColor
            artistLabel.lineBreakMode = .byTruncatingTail
            artistLabel.maximumNumberOfLines = 1
            textViews.append(artistLabel)
        }
        let text = NSStackView(views: textViews)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [art, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 260).isActive = true
        return row
    }

    private func transportRow() -> NSView {
        func button(_ symbol: String, _ size: CGFloat, _ action: Selector) -> NSButton {
            let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            let button = NSButton(image: image ?? NSImage(), target: self, action: action)
            button.isBordered = false
            button.imagePosition = .imageOnly
            return button
        }
        let prev = button("backward.end.fill", 15, #selector(previousTrack))
        let toggle = button(current.isPlaying ? "pause.fill" : "play.fill", 20, #selector(togglePlayback))
        let next = button("forward.end.fill", 15, #selector(nextTrack))

        let row = NSStackView(views: [prev, toggle, next])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .equalCentering
        row.edgeInsets = NSEdgeInsets(top: 4, left: 40, bottom: 8, right: 40)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 260).isActive = true
        return row
    }

    private func item(_ title: String, _ action: Selector, symbol: String? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        if let symbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            image?.isTemplate = true
            entry.image = image?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        }
        return entry
    }

    private func submenu(_ title: String, symbol: String?,
                         build: (NSMenu) -> Void) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let symbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            image?.isTemplate = true
            entry.image = image?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        }
        let sub = NSMenu()
        build(sub)
        entry.submenu = sub
        return entry
    }

    private static func thumbnail(_ artwork: NSImage?, side: CGFloat = 20) -> NSImage? {
        guard let artwork else { return nil }
        let size = NSSize(width: side, height: side)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size),
                                xRadius: side * 0.22, yRadius: side * 0.22)
        path.addClip()
        artwork.draw(in: NSRect(origin: .zero, size: size),
                     from: .zero, operation: .copy, fraction: 1)
        thumb.unlockFocus()
        return thumb
    }

    @objc private func togglePlayback() { client.send("toggle") }
    @objc private func nextTrack() { client.send("next") }
    @objc private func previousTrack() { client.send("prev") }

    @objc func setSize(_ sender: NSMenuItem) {
        guard let points = sender.representedObject as? Double else { return }
        Preferences.diameter = points
        applyConfiguration()
    }

    @objc func setSpeed(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        Preferences.secondsPerRevolution = seconds
        record.secondsPerRevolution = seconds
    }

    @objc func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let lang = Language(rawValue: raw)
        else { return }
        Preferences.language = lang
        settingsWindow?.languageChanged()
    }

    @objc func setTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Preferences.themeID = id
        applyConfiguration()
    }

    @objc func setAccent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Preferences.accentID = id
        applyConfiguration()
    }

    @objc func setOpacity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        Preferences.opacity = value
        window.alphaValue = value
        crateWindow?.alphaValue = value
        for panel in [leftMeterWindow, rightMeterWindow, spectrumWindow] {
            panel?.alphaValue = value
        }
    }

    @objc func setSide(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Preferences.sideID = id
        applyConfiguration()
    }

    @objc func toggleHideWhenIdle() {
        Preferences.hideWhenIdle.toggle()
        if Preferences.hideWhenIdle {
            if !current.isPlaying {
                window.orderOut(nil)
                orderMetersOut()
            }
        } else if !window.isVisible {
            window.orderFront(nil)
            window.applyLevel()
            orderMetersFront()
        }
    }

    @objc func setSound(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let slot = SoundSlot(rawValue: pair[0]) else { return }
        Preferences.setSoundChoice(pair[1].isEmpty ? nil : pair[1], for: slot)
        Sounds.shared.forget()
        if slot.isLoop {
            Sounds.shared.refreshAmbience()
        } else {
            Sounds.shared.play(slot)
        }
    }

    @objc func setVolume(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        Preferences.soundVolume = value
        Sounds.shared.refreshVolume()
        Sounds.shared.play(.swap)
    }

    private static var soundFolderReadme: String {
        L.t("""
        Каждая папка в sounds/ — это один звук виджета. Всё, что в ней лежит,
        появляется в Настройки → Звуки под именем файла.

          sounds/start/     музыка пошла, опускается игла
          sounds/stop/      музыка на паузе
          sounds/swap/      смена трека
          sounds/ambience/  шум пластинки, пока играет музыка (петля)
          sounds/scratch/   пока крутишь пластинку рукой (петля)

        Подходят .wav, .aiff, .caf, .m4a и .mp3.
        Петли должны стыковаться без шва, иначе на повторе будет щелчок.
        «Vinyl» — встроенный звук, он возвращается при каждом запуске.
        """, """
        Each folder in sounds/ is one of the widget's sounds. Whatever you put
        there shows up in Settings → Sounds under its file name.

          sounds/start/     music starts, the needle drops
          sounds/stop/      music pauses
          sounds/swap/      the track changes
          sounds/ambience/  record crackle while music plays (loop)
          sounds/scratch/   while you turn the record by hand (loop)

        .wav, .aiff, .caf, .m4a and .mp3 all work.
        Loops must join seamlessly or they click on every repeat.
        "Vinyl" is the built-in sound and comes back on every launch.
        """)
    }

    @objc func openSoundFolder() {
        let folder = Sounds.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let readme = folder.appendingPathComponent(L.t("ЧИТАЙ МЕНЯ.txt", "README.txt"))
        if !FileManager.default.fileExists(atPath: readme.path) {
            try? Self.soundFolderReadme.write(to: readme, atomically: true, encoding: .utf8)
        }
        Sounds.shared.forget()
        NSWorkspace.shared.activateFileViewerSelecting([readme])
    }

    @objc func toggleCrate() {
        Preferences.showCrate.toggle()
        applyCrate()
    }

    @objc func setCrateSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        Preferences.crateSizeMultiplier = value
        applyCrate()
    }

    @objc func setCrateStyle(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Preferences.crateStyleID = id
        applyCrate()
    }

    @objc func setCrateDepth(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        Preferences.crateDepth = value
        crateCovers = Array(crateCovers.prefix(value))
        crateTitles = Array(crateTitles.prefix(value))
        saveCrate()
        applyCrate()
    }

    private func selectedCrateCard(_ index: Int) {
        guard index < crateTitles.count, !crateTitles[index].isEmpty else { return }
        let text = crateTitles[index]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        crateToast?.orderOut(nil)
        let label = NSTextField(labelWithString: L.t("Скопировано: \(text)", "Copied: \(text)"))
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.sizeToFit()
        let padding: CGFloat = 10
        let size = NSSize(width: label.frame.width + padding * 2,
                          height: label.frame.height + padding * 2)
        label.frame = NSRect(x: padding, y: padding, width: label.frame.width,
                             height: label.frame.height)

        let toast = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: .borderless, backing: .buffered, defer: false)
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.hasShadow = true
        toast.level = .floating
        toast.ignoresMouseEvents = true
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.addSubview(label)
        toast.contentView = background

        if let crateWindow {
            let anchor = crateWindow.frame
            toast.setFrameOrigin(NSPoint(x: anchor.midX - size.width / 2,
                                         y: anchor.maxY + 8))
        }
        toast.orderFront(nil)
        crateToast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak toast] in
            guard let toast else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                toast.animator().alphaValue = 0
            } completionHandler: {
                toast.orderOut(nil)
            }
        }
    }

    @objc func toggleCrateReflections() {
        Preferences.crateReflections.toggle()
        applyCrate()
    }

    @objc func toggleTime() {
        Preferences.showTime.toggle()
        applyConfiguration()
    }

    @objc func toggleProgress() {
        Preferences.showProgress.toggle()
        applyConfiguration()
    }

    @objc func toggleCaption() {
        Preferences.showCaption.toggle()
        applyConfiguration()
    }

    @objc func toggleAlwaysOnTop() {
        Preferences.alwaysOnTop.toggle()
        window.applyLevel()
        crateWindow?.applyLevel()
        for panel in [leftMeterWindow, rightMeterWindow, spectrumWindow] { panel?.applyLevel() }
    }

    @objc func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Vinyl: launch-at-login failed — \(error)")
        }
    }

    @objc func resetPosition() {
        window.placeAtDefaultPosition()
        Preferences.origin = window.frame.origin
        if let crateWindow {
            crateWindow.placeAtDefaultPosition()
            Preferences.crateOrigin = crateWindow.frame.origin
        }
        if let spectrumWindow {
            spectrumWindow.placeAtDefaultPosition()
            Preferences.spectrumOrigin = spectrumWindow.frame.origin
        }
        positionMeters()
        orderMetersFront()
    }

    @objc private func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(delegate: self) }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }
}
