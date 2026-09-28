import AppKit
import ServiceManagement

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class SettingsWindowController: NSWindowController, NSToolbarDelegate {

    private weak var delegate: AppDelegate?

    private enum Pane: String, CaseIterable {
        case record, crate, equalizer, sounds, stats

        var title: String {
            switch self {
            case .record: return L.t("Пластинка", "Record")
            case .crate: return L.t("Картотека", "Crate")
            case .equalizer: return L.t("Эквалайзер", "Equalizer")
            case .sounds: return L.t("Звуки", "Sounds")
            case .stats: return L.t("Статистика", "Stats")
            }
        }
        var symbol: String {
            switch self {
            case .record: return "opticaldisc"
            case .crate: return "square.stack"
            case .equalizer: return "waveform"
            case .sounds: return "speaker.wave.2"
            case .stats: return "chart.bar"
            }
        }
        var tint: NSColor {
            switch self {
            case .record: return NSColor(red: 0.86, green: 0.24, blue: 0.18, alpha: 1)
            case .crate: return NSColor(red: 0.72, green: 0.47, blue: 0.20, alpha: 1)
            case .equalizer: return NSColor(red: 0.52, green: 0.40, blue: 0.84, alpha: 1)
            case .sounds: return NSColor(red: 0.24, green: 0.55, blue: 0.86, alpha: 1)
            case .stats: return NSColor(red: 0.36, green: 0.62, blue: 0.36, alpha: 1)
            }
        }
        var identifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue) }
    }

    private static let paneWidth: CGFloat = 440
    private static let fixedContentSize = NSSize(width: 460, height: 720)

    private static let cardFill: CGColor =
        (NSColor.windowBackgroundColor.blended(withFraction: 0.09, of: .labelColor)
            ?? NSColor.windowBackgroundColor).cgColor

    convenience init(delegate: AppDelegate) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        self.init(window: window)
        self.delegate = delegate

        let toolbar = NSToolbar(identifier: "VinylSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        select(Pane(rawValue: Preferences.settingsPaneID ?? "") ?? .record)
    }

    override func showWindow(_ sender: Any?) {
        if let current { select(current) }
        super.showWindow(sender)
        window?.center()
    }

    func languageChanged() {
        let toolbar = NSToolbar(identifier: "VinylSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window?.toolbar = toolbar
        if let current { select(current) }
    }

    private var current: Pane?

    private func select(_ pane: Pane) {
        current = pane
        Preferences.settingsPaneID = pane.rawValue
        window?.toolbar?.selectedItemIdentifier = pane.identifier
        window?.title = pane.title

        let content = build(pane)
        let frame = NSView()
        frame.translatesAutoresizingMaskIntoConstraints = false
        frame.widthAnchor.constraint(equalToConstant: Self.fixedContentSize.width).isActive = true
        frame.heightAnchor.constraint(equalToConstant: Self.fixedContentSize.height).isActive = true
        content.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        frame.addSubview(scroll)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalToConstant: Self.paneWidth),
            scroll.topAnchor.constraint(equalTo: frame.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: frame.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: frame.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: frame.bottomAnchor),
        ])

        let controller = NSViewController()
        controller.view = frame
        window?.contentViewController = controller
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Pane.allCases.map(\.identifier)
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Pane.allCases.map(\.identifier)
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Pane.allCases.map(\.identifier)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = Pane(rawValue: id.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = pane.title
        item.image = Self.tile(symbol: pane.symbol, tint: pane.tint)
        item.target = self
        item.action = #selector(paneClicked(_:))
        return item
    }

    private static func tile(symbol: String, tint: NSColor, side: CGFloat = 28,
                             padding: CGFloat = 4) -> NSImage {
        let canvasSide = side + padding * 2
        let size = NSSize(width: canvasSide, height: canvasSide)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(x: padding, y: padding, width: side, height: side)
        NSBezierPath(roundedRect: rect, xRadius: side * 0.24, yRadius: side * 0.24).addClip()
        tint.setFill()
        rect.fill()
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.52, weight: .medium)
            .applying(.init(paletteColors: [.white]))
        if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            glyph.isTemplate = false
            let origin = NSPoint(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2)
            glyph.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        }
        image.unlockFocus()
        return image
    }

    @objc private func paneClicked(_ sender: NSToolbarItem) {
        guard let pane = Pane(rawValue: sender.itemIdentifier.rawValue) else { return }
        select(pane)
    }

    private func build(_ pane: Pane) -> NSView {
        switch pane {
        case .record: return buildRecordPane()
        case .crate: return buildCratePane()
        case .equalizer: return buildEqualizerPane()
        case .sounds: return buildSoundsPane()
        case .stats: return buildStatsPane()
        }
    }

    private func buildRecordPane() -> NSView {
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        configure(grid)
        let languageGrid = NSGridView(numberOfColumns: 2, rows: 0)
        configure(languageGrid)
        addRow(languageGrid, L.t("Язык", "Language"), popup(
            options: Language.allCases.map { ($0.name, $0.rawValue) }, current: Preferences.language.rawValue,
            action: #selector(AppDelegate.setLanguage(_:))))

        addRow(grid, L.t("Тема", "Theme"), popup(
            options: Theme.all.map { ($0.localizedName, $0.id) }, current: Preferences.themeID,
            action: #selector(AppDelegate.setTheme(_:))))
        addRow(grid, L.t("Направление", "Direction"), popup(
            options: RecordArtwork.Side.allCases.map { ($0.name, $0.rawValue) },
            current: Preferences.sideID, action: #selector(AppDelegate.setSide(_:))))
        addRow(grid, L.t("Размер", "Size"), popup(
            options: Preferences.diameters.map { ($0.label, $0.points) },
            current: Preferences.diameter, action: #selector(AppDelegate.setSize(_:))))
        addRow(grid, L.t("Скорость", "Speed"), popup(
            options: Preferences.speeds.map { ($0.label, $0.secondsPerRevolution) },
            current: Preferences.secondsPerRevolution, action: #selector(AppDelegate.setSpeed(_:))))
        addRow(grid, L.t("Акцент", "Accent"), popup(
            options: Accent.all.map { ($0.localizedName, $0.id) }, current: Preferences.accentID,
            action: #selector(AppDelegate.setAccent(_:))))
        addRow(grid, L.t("Непрозрачность", "Opacity"), popup(
            options: Preferences.opacities.map { ($0.label, $0.value) }, current: Preferences.opacity,
            action: #selector(AppDelegate.setOpacity(_:))))

        let display = NSStackView(views: [
            checkbox(L.t("Подпись", "Caption"), Preferences.showCaption, #selector(AppDelegate.toggleCaption)),
            checkbox(L.t("Полоса прогресса", "Progress ring"), Preferences.showProgress,
                    #selector(AppDelegate.toggleProgress)),
            checkbox(L.t("Время трека", "Track time"), Preferences.showTime,
                    #selector(AppDelegate.toggleTime)),
            checkbox(L.t("Поверх всех окон", "Always on top"), Preferences.alwaysOnTop,
                    #selector(AppDelegate.toggleAlwaysOnTop)),
            checkbox(L.t("Прятать, когда ничего не играет", "Hide when nothing is playing"),
                    Preferences.hideWhenIdle, #selector(AppDelegate.toggleHideWhenIdle)),
            checkbox(L.t("Запускать при входе", "Launch at login"),
                    SMAppService.mainApp.status == .enabled, #selector(AppDelegate.toggleLaunchAtLogin)),
        ])
        display.orientation = .vertical
        display.alignment = .leading
        display.spacing = 9

        let tips = NSTextField(labelWithString: L.t(
            "Двойной клик по конверту — перевернуть его: там полное название и что играло до этого.\n"
            + "Крутить пластинку рукой — перемотка. Клик по кружку в центре — открыть плеер.",
            "Double-click the sleeve to turn it over: the full title and what played before.\n"
            + "Drag the record itself to scrub. Click the paper label to bring the player forward."))
        tips.textColor = .secondaryLabelColor
        tips.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        tips.lineBreakMode = .byWordWrapping
        tips.preferredMaxLayoutWidth = Self.paneWidth - 88

        let resetButton = NSButton(title: L.t("Собрать всё на место", "Bring everything back"), target: delegate,
                                   action: #selector(AppDelegate.resetPosition))
        resetButton.bezelStyle = .rounded
        resetButton.bezelColor = Pane.record.tint.withAlphaComponent(0.85)
        resetButton.contentTintColor = .white

        return page([
            section(nil, languageGrid, tint: Pane.record.tint),
            section(L.t("Внешний вид", "Appearance"), grid, tint: Pane.record.tint),
            section(L.t("Отображение", "Display"), display, tint: Pane.record.tint),
            section(L.t("Что умеет виджет", "What the widget does"), tips, tint: Pane.record.tint),
            resetButton,
        ])
    }

    private func buildCratePane() -> NSView {
        let toggles = NSStackView(views: [
            checkbox(L.t("Показывать картотеку", "Show the crate"), Preferences.showCrate,
                    #selector(AppDelegate.toggleCrate)),
            checkbox(L.t("Отражения", "Reflections"), Preferences.crateReflections,
                    #selector(AppDelegate.toggleCrateReflections)),
        ])
        toggles.orientation = .vertical
        toggles.alignment = .leading
        toggles.spacing = 9

        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        configure(grid)
        addRow(grid, L.t("Стиль", "Style"), popup(
            options: CrateStyle.allCases.map { ($0.name, $0.rawValue) },
            current: Preferences.crateStyleID, action: #selector(AppDelegate.setCrateStyle(_:))))
        addRow(grid, L.t("Размер", "Size"), popup(
            options: Preferences.crateSizes.map { ($0.label, $0.multiplier) },
            current: Preferences.crateSizeMultiplier, action: #selector(AppDelegate.setCrateSize(_:))))
        addRow(grid, L.t("Сколько обложек", "How many covers"), popup(
            options: Preferences.crateDepths.map { ($0.label, $0.count) },
            current: Preferences.crateDepth, action: #selector(AppDelegate.setCrateDepth(_:))))

        return page([
            section(nil, toggles, tint: Pane.crate.tint),
            section(L.t("Оформление", "Look"), grid, tint: Pane.crate.tint),
        ])
    }

    private func buildSoundsPane() -> NSView {
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        configure(grid)
        for slot in SoundSlot.allCases {
            let variants = Sounds.variants(for: slot)
            let chosen = Preferences.soundChoice(for: slot) ?? ""
            var options: [(String, [String])] = [(L.t("Выключено", "Off"), [slot.rawValue, ""])]
            options += variants.map { ($0, [slot.rawValue, $0]) }
            addRow(grid, slot.name, popup(options: options, current: [slot.rawValue, chosen],
                                          action: #selector(AppDelegate.setSound(_:))))
        }
        addRow(grid, L.t("Громкость", "Volume"), popup(
            options: Preferences.volumes.map { ($0.label, $0.value) }, current: Preferences.soundVolume,
            action: #selector(AppDelegate.setVolume(_:))))

        let folderButton = NSButton(title: L.t("Открыть папку со звуками…", "Open the sounds folder…"),
                                    target: delegate, action: #selector(AppDelegate.openSoundFolder))
        folderButton.bezelStyle = .rounded
        folderButton.bezelColor = Pane.sounds.tint.withAlphaComponent(0.85)
        folderButton.contentTintColor = .white

        return page([
            section(L.t("Выбор звуков", "Choose sounds"), grid, tint: Pane.sounds.tint),
            folderButton,
        ])
    }

    private func buildEqualizerPane() -> NSView {
        let tint = Pane.equalizer.tint
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        configure(grid)
        addRow(grid, L.t("Режим", "Mode"), popup(
            options: EqualizerMode.allCases.map { ($0.name, $0.rawValue) },
            current: Preferences.equalizerModeID, action: #selector(AppDelegate.setEqualizerMode(_:))))
        addRow(grid, L.t("Тема", "Theme"), popup(
            options: EqualizerStyle.allCases.map { ($0.name, $0.rawValue) },
            current: Preferences.equalizerStyleID, action: #selector(AppDelegate.setEqualizerStyle(_:))))

        let toggle = NSStackView(views: [
            checkbox(L.t("Показывать эквалайзер", "Show the equalizer"), Preferences.showEqualizer,
                    #selector(AppDelegate.toggleEqualizer)),
        ])
        toggle.orientation = .vertical
        toggle.alignment = .leading

        let hint = NSTextField(labelWithString: L.t(
            "«Спектр» — своё окно, его можно перетащить куда угодно. «Громкость» встаёт по бокам от конверта.",
            "\"Spectrum\" is its own window you can drag anywhere. \"Level\" sits either side of the sleeve."))
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = Self.paneWidth - 88

        var sections: [NSView] = [
            section(nil, toggle, tint: tint),
            section(L.t("Как выглядит", "How it looks"), grid, tint: tint),
            section(nil, hint, tint: tint),
        ]

        if let state = delegate?.audioMeterStatusText() {
            let status = NSTextField(labelWithString: state.text)
            status.lineBreakMode = .byWordWrapping
            status.preferredMaxLayoutWidth = Self.paneWidth - 88
            var content: [NSView] = [status]
            if state.offerPrivacy {
                let button = NSButton(title: L.t("Открыть настройки приватности…",
                                                 "Open Privacy settings…"),
                                      target: delegate, action: #selector(AppDelegate.openPrivacySettings))
                button.bezelStyle = .rounded
                button.bezelColor = tint.withAlphaComponent(0.85)
                button.contentTintColor = .white
                content.append(button)
            }
            let stack = NSStackView(views: content)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 10
            sections.append(section(L.t("Доступ к звуку", "Audio access"), stack, tint: tint))
        }
        return page(sections)
    }

    private func buildStatsPane() -> NSView {
        let tint = Pane.stats.tint
        let entries = PlayLog.load()
        guard !entries.isEmpty else {
            let empty = NSTextField(labelWithString: L.t(
                "Пока нечего показать — статистика появится, когда что-нибудь послушаешь.",
                "Nothing to show yet — stats appear once you've listened to something."))
            empty.textColor = .secondaryLabelColor
            empty.lineBreakMode = .byWordWrapping
            empty.preferredMaxLayoutWidth = Self.paneWidth - 88
            return page([section(L.t("Статистика", "Stats"), empty, tint: tint)])
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today

        let totals = NSGridView(numberOfColumns: 2, rows: 0)
        configure(totals)
        func totalsRow(_ label: String, _ summary: PlayLog.Summary) {
            let value = "\(summary.tracks) \(PlayLog.plural(summary.tracks))"
                + " · " + PlayLog.duration(summary.seconds)
            let field = NSTextField(labelWithString: value)
            field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            addRow(totals, label, field)
        }
        totalsRow(L.t("Сегодня", "Today"), PlayLog.summary(entries, since: today))
        totalsRow(L.t("За неделю", "This week"), PlayLog.summary(entries, since: weekAgo))
        totalsRow(L.t("Всего", "All time"), PlayLog.summary(entries))

        func chart(_ rows: [(name: String, seconds: Int, plays: Int)]) -> NSView {
            let stack = NSStackView(views: rows.prefix(5).map { row in
                let name = NSTextField(labelWithString: row.name)
                name.lineBreakMode = .byTruncatingTail
                name.widthAnchor.constraint(equalToConstant: 232).isActive = true
                let value = NSTextField(labelWithString: PlayLog.duration(row.seconds))
                value.textColor = .secondaryLabelColor
                value.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize,
                                                        weight: .regular)
                let line = NSStackView(views: [name, value])
                line.orientation = .horizontal
                line.spacing = 10
                return line
            })
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 7
            return stack
        }

        let allTime = PlayLog.summary(entries)
        var sections: [NSView] = [
            section(L.t("Итоги", "Totals"), totals, tint: tint),
        ]
        if !allTime.artists.isEmpty {
            sections.append(section(L.t("Чаще всего слушаешь", "Most played artists"),
                                    chart(allTime.artists), tint: tint))
        }
        if !allTime.titles.isEmpty {
            sections.append(section(L.t("Любимые треки", "Top tracks"),
                                    chart(allTime.titles), tint: tint))
        }
        return page(sections)
    }

    private func page(_ sections: [NSView]) -> NSView {
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.paneWidth).isActive = true
        for view in sections { view.translatesAutoresizingMaskIntoConstraints = false }
        return stack
    }

    private func card(_ content: NSView, tint: NSColor) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = Self.cardFill
        box.layer?.cornerRadius = 10
        box.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        let margin: CGFloat = 14
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: margin),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: margin),
            content.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -margin),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -margin),
        ])
        box.widthAnchor.constraint(equalToConstant: Self.paneWidth - 44).isActive = true
        return box
    }

    private func section(_ title: String?, _ content: NSView, tint: NSColor) -> NSView {
        let boxed = card(content, tint: tint)
        guard let title else { return boxed }
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = tint.cgColor
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true

        let heading = NSTextField(labelWithString: title)
        heading.font = .boldSystemFont(ofSize: 11)
        heading.textColor = .secondaryLabelColor

        let headingRow = NSStackView(views: [dot, heading])
        headingRow.orientation = .horizontal
        headingRow.alignment = .centerY
        headingRow.spacing = 6

        let stack = NSStackView(views: [headingRow, boxed])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    private func configure(_ grid: NSGridView) {
        grid.rowSpacing = 11
        grid.columnSpacing = 14
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading
        grid.translatesAutoresizingMaskIntoConstraints = false
    }

    private func addRow(_ grid: NSGridView, _ title: String, _ control: NSView) {
        let label = NSTextField(labelWithString: title)
        label.alignment = .left
        label.widthAnchor.constraint(equalToConstant: 165).isActive = true
        grid.addRow(with: [label, control])
    }

    private func checkbox(_ title: String, _ checked: Bool, _ action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: delegate, action: action)
        button.state = checked ? .on : .off
        return button
    }

    private func popup<T: Equatable>(options: [(label: String, value: T)], current: T,
                                     action: Selector) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        let menu = NSMenu()
        for option in options {
            let entry = NSMenuItem(title: option.label, action: action, keyEquivalent: "")
            entry.target = delegate
            entry.representedObject = option.value
            menu.addItem(entry)
        }
        button.menu = menu
        if let index = options.firstIndex(where: { $0.value == current }) {
            button.selectItem(at: index)
        }
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.separatorColor.cgColor
        return button
    }
}
