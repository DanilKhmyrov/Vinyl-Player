import AppKit

enum Preferences {
    private static let defaults = UserDefaults.standard

    enum Key {
        static let diameter = "diameter"
        static let secondsPerRevolution = "secondsPerRevolution"
        static let alwaysOnTop = "alwaysOnTop"
        static let showCaption = "showCaption"
        static let showProgress = "showProgress"
        static let showTime = "showTime"
        static let showCrate = "showCrate"
        static let crateOrigin = "crateOrigin"
        static let crateSize = "crateSize"
        static let crateDepth = "crateDepth"
        static let crateReflections = "crateReflections"
        static let crateStyle = "crateStyle"
        static let history = "history"
        static let side = "side"
        static let opacity = "opacity"
        static let hideWhenIdle = "hideWhenIdle"
        static let accent = "accent"
        static let soundVolume = "soundVolume"
        static let theme = "theme"
        static let originX = "originX"
        static let originY = "originY"
        static let hasOrigin = "hasOrigin"
        static let language = "language"
        static let showEqualizer = "showEqualizer"
        static let equalizerStyle = "equalizerStyle"
        static let equalizerMode = "equalizerMode"
        static let spectrumOrigin = "spectrumOrigin"
        static let settingsPane = "settingsPane"
    }

    static var language: Language {
        get { Language(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .ru }
        set { defaults.set(newValue.rawValue, forKey: Key.language) }
    }

    static var speeds: [(label: String, secondsPerRevolution: Double)] {
        [
            ("45 RPM", 60.0 / 45.0),
            ("33⅓ RPM", 60.0 / (100.0 / 3.0)),
            ("16⅔ RPM", 60.0 / (50.0 / 3.0)),
            (L.t("Медленно", "Slow"), 8.0),
        ]
    }

    static var crateSizes: [(label: String, multiplier: Double)] {
        [(L.t("Маленькая", "Small"), 0.40), (L.t("Средняя", "Medium"), 0.55),
         (L.t("Большая", "Large"), 0.75)]
    }
    static var crateDepths: [(label: String, count: Int)] {
        [(L.t("4 обложки", "4 covers"), 4), (L.t("6 обложек", "6 covers"), 6),
         (L.t("8 обложек", "8 covers"), 8)]
    }

    static var crateSizeMultiplier: Double {
        get { defaults.object(forKey: Key.crateSize) as? Double ?? 0.55 }
        set { defaults.set(newValue, forKey: Key.crateSize) }
    }

    static var crateDepth: Int {
        get { (defaults.object(forKey: Key.crateDepth) as? Int) ?? 6 }
        set { defaults.set(newValue, forKey: Key.crateDepth) }
    }

    static var savedHistory: [String] {
        get { defaults.stringArray(forKey: Key.history) ?? [] }
        set { defaults.set(newValue, forKey: Key.history) }
    }

    static var crateStyleID: String {
        get { defaults.string(forKey: Key.crateStyle) ?? CrateStyle.rack.rawValue }
        set { defaults.set(newValue, forKey: Key.crateStyle) }
    }

    static var crateReflections: Bool {
        get { defaults.object(forKey: Key.crateReflections) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.crateReflections) }
    }

    static var diameters: [(label: String, points: Double)] {
        [(L.t("Маленькая", "Small"), 160), (L.t("Средняя", "Medium"), 240),
         (L.t("Большая", "Large"), 340), (L.t("Огромная", "Huge"), 460)]
    }

    static var diameter: Double {
        get { defaults.object(forKey: Key.diameter) as? Double ?? 240 }
        set { defaults.set(newValue, forKey: Key.diameter) }
    }

    static var secondsPerRevolution: Double {
        get { defaults.object(forKey: Key.secondsPerRevolution) as? Double ?? 60.0 / (100.0 / 3.0) }
        set { defaults.set(newValue, forKey: Key.secondsPerRevolution) }
    }

    static var alwaysOnTop: Bool {
        get { defaults.bool(forKey: Key.alwaysOnTop) }
        set { defaults.set(newValue, forKey: Key.alwaysOnTop) }
    }

    static var showCaption: Bool {
        get { defaults.object(forKey: Key.showCaption) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showCaption) }
    }

    static var showEqualizer: Bool {
        get { defaults.object(forKey: Key.showEqualizer) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showEqualizer) }
    }

    static var equalizerStyleID: String {
        get { defaults.string(forKey: Key.equalizerStyle) ?? "hifi" }
        set { defaults.set(newValue, forKey: Key.equalizerStyle) }
    }

    static var equalizerModeID: String {
        get { defaults.string(forKey: Key.equalizerMode) ?? "level" }
        set { defaults.set(newValue, forKey: Key.equalizerMode) }
    }

    static var settingsPaneID: String? {
        get { defaults.string(forKey: Key.settingsPane) }
        set { defaults.set(newValue, forKey: Key.settingsPane) }
    }

    static var spectrumOrigin: CGPoint? {
        get {
            guard defaults.object(forKey: Key.spectrumOrigin + "X") != nil else { return nil }
            return CGPoint(x: defaults.double(forKey: Key.spectrumOrigin + "X"),
                           y: defaults.double(forKey: Key.spectrumOrigin + "Y"))
        }
        set {
            guard let newValue else { return }
            defaults.set(newValue.x, forKey: Key.spectrumOrigin + "X")
            defaults.set(newValue.y, forKey: Key.spectrumOrigin + "Y")
        }
    }

    static var crateOrigin: CGPoint? {
        get {
            guard defaults.object(forKey: Key.crateOrigin + "X") != nil else { return nil }
            return CGPoint(x: defaults.double(forKey: Key.crateOrigin + "X"),
                           y: defaults.double(forKey: Key.crateOrigin + "Y"))
        }
        set {
            guard let newValue else { return }
            defaults.set(newValue.x, forKey: Key.crateOrigin + "X")
            defaults.set(newValue.y, forKey: Key.crateOrigin + "Y")
        }
    }

    static var showCrate: Bool {
        get { defaults.object(forKey: Key.showCrate) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.showCrate) }
    }

    static var showTime: Bool {
        get { defaults.object(forKey: Key.showTime) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showTime) }
    }

    static var showProgress: Bool {
        get { defaults.object(forKey: Key.showProgress) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showProgress) }
    }

    static var sideID: String {
        get { defaults.string(forKey: Key.side) ?? RecordArtwork.Side.right.rawValue }
        set { defaults.set(newValue, forKey: Key.side) }
    }

    static var opacity: Double {
        get { defaults.object(forKey: Key.opacity) as? Double ?? 1 }
        set { defaults.set(newValue, forKey: Key.opacity) }
    }

    static var hideWhenIdle: Bool {
        get { defaults.bool(forKey: Key.hideWhenIdle) }
        set { defaults.set(newValue, forKey: Key.hideWhenIdle) }
    }

    static var accentID: String {
        get { defaults.string(forKey: Key.accent) ?? Accent.all[0].id }
        set { defaults.set(newValue, forKey: Key.accent) }
    }

    static let opacities: [(label: String, value: Double)] = [
        ("100 %", 1.0), ("90 %", 0.9), ("75 %", 0.75), ("60 %", 0.6),
    ]

    static func soundChoice(for slot: SoundSlot) -> String? {
        let key = "sound." + slot.rawValue
        if let stored = defaults.string(forKey: key) { return stored.isEmpty ? nil : stored }
        guard let fallback = slot.defaultChoice,
              Sounds.variants(for: slot).contains(fallback) else { return nil }
        return fallback
    }

    static func setSoundChoice(_ choice: String?, for slot: SoundSlot) {
        defaults.set(choice ?? "", forKey: "sound." + slot.rawValue)
    }

    static var soundVolume: Double {
        get { defaults.object(forKey: Key.soundVolume) as? Double ?? 0.5 }
        set { defaults.set(newValue, forKey: Key.soundVolume) }
    }

    static var volumes: [(label: String, value: Double)] {
        [(L.t("Тихо", "Quiet"), 0.25), (L.t("Средне", "Medium"), 0.5),
         (L.t("Громко", "Loud"), 1.0)]
    }

    static var themeID: String {
        get { defaults.string(forKey: Key.theme) ?? Theme.sleeve.id }
        set { defaults.set(newValue, forKey: Key.theme) }
    }

    static var origin: CGPoint? {
        get {
            guard defaults.bool(forKey: Key.hasOrigin) else { return nil }
            return CGPoint(x: defaults.double(forKey: Key.originX),
                           y: defaults.double(forKey: Key.originY))
        }
        set {
            guard let newValue else {
                defaults.set(false, forKey: Key.hasOrigin)
                return
            }
            defaults.set(newValue.x, forKey: Key.originX)
            defaults.set(newValue.y, forKey: Key.originY)
            defaults.set(true, forKey: Key.hasOrigin)
        }
    }
}
