import Foundation

enum PlayLog {

    struct Entry {
        let date: Date
        let artist: String
        let title: String
        let seconds: Int
    }

    static var fileURL: URL {
        return Sounds.folder.appendingPathComponent("plays.tsv")
    }

    private static let minimumSeconds = 20

    static func append(artist: String?, title: String, seconds: Int) {
        guard seconds >= minimumSeconds else { return }
        let clean = { (s: String) in
            s.replacingOccurrences(of: "\t", with: " ")
             .replacingOccurrences(of: "\n", with: " ")
        }
        let line = "\(Int(Date().timeIntervalSince1970))\t\(seconds)\t"
                 + "\(clean(artist ?? ""))\t\(clean(title))\n"
        let folder = Sounds.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    static func load() -> [Entry] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4, let stamp = TimeInterval(parts[0]),
                  let seconds = Int(parts[1]) else { return nil }
            return Entry(date: Date(timeIntervalSince1970: stamp), artist: parts[2],
                         title: parts[3], seconds: seconds)
        }
    }

    struct Summary {
        var tracks = 0
        var seconds = 0
        var artists: [(name: String, seconds: Int, plays: Int)] = []
        var titles: [(name: String, seconds: Int, plays: Int)] = []
    }

    static func summary(_ entries: [Entry], since: Date? = nil) -> Summary {
        let scoped = since.map { start in entries.filter { $0.date >= start } } ?? entries
        var summary = Summary()
        summary.tracks = scoped.count
        summary.seconds = scoped.reduce(0) { $0 + $1.seconds }

        func rank(_ key: (Entry) -> String) -> [(name: String, seconds: Int, plays: Int)] {
            var totals: [String: (Int, Int)] = [:]
            for entry in scoped where !key(entry).isEmpty {
                let current = totals[key(entry)] ?? (0, 0)
                totals[key(entry)] = (current.0 + entry.seconds, current.1 + 1)
            }
            return totals.map { (name: $0.key, seconds: $0.value.0, plays: $0.value.1) }
                .sorted { $0.seconds > $1.seconds }
        }
        summary.artists = rank { $0.artist }
        summary.titles = rank { $0.title }
        return summary
    }

    static func plural(_ n: Int) -> String {
        guard Preferences.language == .ru else { return n == 1 ? "track" : "tracks" }
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "трек" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "трека" }
        return "треков"
    }

    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        guard minutes >= 60 else { return "\(minutes) \(L.t("мин", "min"))" }
        let hours = minutes / 60, rest = minutes % 60
        guard rest > 0 else { return "\(hours) \(L.t("ч", "h"))" }
        return "\(hours) \(L.t("ч", "h")) \(rest) \(L.t("мин", "min"))"
    }
}
