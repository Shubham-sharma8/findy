import Foundation

// MARK: - Parsed Query

public struct ParsedQuery: Equatable, Sendable {
    public var raw: String
    public var terms: [String] = []
    public var category: FileCategory?
    public var extensions: [String] = []
    public var screenshotsOnly: Bool = false
    public var kindLabel: String?
    public var after: Date?
    public var before: Date?
    public var dateLabel: String?
    public var minSize: Int64?
    public var maxSize: Int64?
    public var camera: String?
    public var source: DownloadSource?
    public var folder: Location?
    public var tag: FinderTag?

    public init(raw: String) {
        self.raw = raw
    }

    public var isStructured: Bool {
        category != nil || !extensions.isEmpty || screenshotsOnly || after != nil || before != nil
            || minSize != nil || maxSize != nil || camera != nil || source != nil || folder != nil || tag != nil
    }

    public var chips: [String] {
        var list: [String] = []
        if let kindLabel {
            list.append(kindLabel)
        } else if screenshotsOnly {
            list.append("Screenshots")
        } else if let category {
            list.append(category.title)
        }
        if let dateLabel {
            list.append(dateLabel)
        }
        if let minSize, let maxSize {
            list.append("\(Fmt.bytes(minSize)) – \(Fmt.bytes(maxSize))")
        } else if let minSize {
            list.append("Over \(Fmt.bytes(minSize))")
        } else if let maxSize {
            list.append("Under \(Fmt.bytes(maxSize))")
        }
        if let camera {
            list.append("Camera: \(camera.capitalized)")
        }
        if let source {
            list.append("From \(source.name)")
        }
        if let folder {
            list.append("In \(folder.title)")
        }
        if let tag {
            list.append("Tag: \(tag.rawValue)")
        }
        for term in terms {
            list.append("“\(term)”")
        }
        return list
    }

    public static func termClause(_ term: String, includeContent: Bool = true) -> String {
        let escaped = term.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
        guard !escaped.isEmpty else { return "kMDItemFSName == '*'" }
        if includeContent {
            return "(kMDItemFSName == '*\(escaped)*'cd || kMDItemTitle == '*\(escaped)*'cd || kMDItemTextContent == '*\(escaped)*'cd)"
        }
        return "(kMDItemFSName == '*\(escaped)*'cd || kMDItemTitle == '*\(escaped)*'cd)"
    }

    public var spotlightQuery: String {
        var clauses: [String] = []
        if screenshotsOnly {
            clauses.append("kMDItemIsScreenCapture == 1")
        } else if !extensions.isEmpty {
            let extClauses = extensions.map { "kMDItemFSName == '*.\($0)'c" }
            clauses.append("(" + extClauses.joined(separator: " || ") + ")")
        } else if let category {
            clauses.append(category.spotlightQuery)
        }
        if let after {
            let iso = Self.isoString(after)
            clauses.append("(kMDItemFSContentChangeDate >= $time.iso(\(iso)) || kMDItemContentCreationDate >= $time.iso(\(iso)))")
        }
        if let before {
            let iso = Self.isoString(before)
            clauses.append("(kMDItemFSContentChangeDate < $time.iso(\(iso)) || kMDItemContentCreationDate < $time.iso(\(iso)))")
        }
        if let minSize {
            clauses.append("kMDItemFSSize >= \(minSize)")
        }
        if let maxSize {
            clauses.append("kMDItemFSSize <= \(maxSize)")
        }
        if let camera {
            let c = camera.replacingOccurrences(of: "\"", with: "")
            clauses.append("(kMDItemAcquisitionModel == '*\(c)*'cd || kMDItemAcquisitionMake == '*\(c)*'cd)")
        }
        if let source {
            clauses.append(source.spotlightClause)
        }
        for term in terms {
            clauses.append(Self.termClause(term, includeContent: true))
        }
        if clauses.isEmpty {
            return "kMDItemFSName == '*'"
        }
        return clauses.joined(separator: " && ")
    }

    private static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: date)
    }

    public func matches(_ item: FileItem) -> Bool {
        if screenshotsOnly {
            let lower = item.name.lowercased()
            let isScreen = lower.contains("screenshot") || lower.contains("screen shot") || lower.contains("screen_shot")
            if !isScreen { return false }
        }
        if !extensions.isEmpty {
            let ext = item.url.pathExtension.lowercased()
            if !extensions.contains(ext) { return false }
        } else if let category, item.category != category {
            return false
        }
        if let after, item.modified < after && item.created < after {
            return false
        }
        if let before, item.modified >= before && item.created >= before {
            return false
        }
        if let minSize, item.size < minSize {
            return false
        }
        if let maxSize, item.size > maxSize {
            return false
        }
        if let folder {
            let folderPrefix = folder.url.standardizedFileURL.path
            if !item.url.standardizedFileURL.path.hasPrefix(folderPrefix) {
                return false
            }
        }
        if let tag {
            let hasTag = item.tags.contains { $0.caseInsensitiveCompare(tag.rawValue) == .orderedSame }
            if !hasTag { return false }
        }
        for term in terms {
            let lower = term.lowercased()
            let matchesName = item.name.lowercased().contains(lower)
            let matchesTitle = item.title?.lowercased().contains(lower) ?? false
            let matchesArtist = item.artist?.lowercased().contains(lower) ?? false
            if !matchesName && !matchesTitle && !matchesArtist {
                return false
            }
        }
        return true
    }
}

// MARK: - Natural Language Search Parser

public enum NaturalSearch {
    private struct Kind: Sendable {
        var category: FileCategory?
        var extensions: [String] = []
        var screenshots: Bool = false
        let label: String
    }

    private static let kinds: [String: Kind] = {
        var map: [String: Kind] = [:]
        func add(_ words: [String], _ kind: Kind) {
            for w in words { map[w] = kind }
        }
        add(["pdf", "pdfs"], Kind(category: .documents, extensions: ["pdf"], label: "PDFs"))
        add(["doc", "docs", "document", "documents"], Kind(category: .documents, label: "Documents"))
        add(["word", "docx"], Kind(category: .documents, extensions: ["doc", "docx", "pages"], label: "Word documents"))
        add(["spreadsheet", "spreadsheets", "excel", "sheets", "numbers", "xlsx", "xls", "csv", "csvs", "tsv"], Kind(category: .documents, extensions: ["xlsx", "xls", "csv", "tsv", "numbers"], label: "Spreadsheets"))
        add(["presentation", "presentations", "slides", "deck", "decks", "powerpoint", "keynote", "keynotes", "ppt", "pptx"], Kind(category: .documents, extensions: ["ppt", "pptx", "key"], label: "Presentations"))
        add(["txt", "md", "rtf", "epub"], Kind(category: .documents, extensions: ["txt", "md", "rtf", "epub"], label: "Text files"))
        add(["screenshot", "screenshots", "screengrab", "screengrabs"], Kind(category: .images, screenshots: true, label: "Screenshots"))
        add(["photo", "photos", "image", "images", "pic", "pics", "picture", "pictures"], Kind(category: .images, label: "Images"))
        add(["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "svg", "tif", "tiff", "psd", "raw", "dng", "cr2", "cr3", "nef", "arw", "raf"], Kind(category: .images, label: "Images"))
        add(["video", "videos", "movie", "movies", "clip", "clips", "footage", "recording", "recordings", "mp4", "mov", "mkv", "avi", "webm", "m4v"], Kind(category: .videos, label: "Videos"))
        add(["music", "audio", "song", "songs", "track", "tracks", "podcast", "podcasts", "mp3", "m4a", "wav", "flac", "aac"], Kind(category: .music, label: "Audio"))
        add(["archive", "archives", "compressed", "zip", "zips"], Kind(category: .archives, extensions: ["zip", "tar", "gz", "7z", "rar"], label: "Archives"))
        add(["installer", "installers", "dmg", "dmgs", "pkg", "pkgs", "mpkg", "iso"], Kind(category: .archives, extensions: ["dmg", "pkg", "mpkg", "iso"], label: "Installers"))
        add(["app", "apps", "application", "applications"], Kind(category: .apps, label: "Applications"))
        add(["code", "script", "scripts", "json", "html", "sh"], Kind(category: .code, label: "Code"))
        add(["folder", "folders"], Kind(category: .folders, label: "Folders"))
        return map
    }()

    private static let stopWords: Set<String> = [
        "find", "search", "show", "get", "give", "me", "my", "all", "the", "a", "an", "some",
        "files", "file", "items", "stuff", "things", "that", "which", "are", "were", "was", "is",
        "with", "have", "has", "containing", "contains", "contain", "named", "called", "please",
        "from", "in", "on", "at", "by", "for", "of", "to", "since", "during", "about", "via"
    ]

    private static let cameras: Set<String> = [
        "iphone", "ipad", "canon", "nikon", "sony", "fuji", "fujifilm", "leica", "panasonic", "olympus", "ricoh", "gopro", "dji", "pixel", "samsung"
    ]

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6,
        "jul": 7, "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12
    ]

    public static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedQuery {
        var parsed = ParsedQuery(raw: input)
        let tokens = tokenize(input)
        guard !tokens.isEmpty else { return parsed }

        var consumed = Array(repeating: false, count: tokens.count)
        let lower = tokens.map { $0.lowercased() }

        var i = 0
        while i < tokens.count {
            let w = lower[i]

            // 1. Tag matching: "tagged red" or "tag blue"
            if (w == "tagged" || w == "tag") && i + 1 < tokens.count {
                if let tag = FinderTag.allCases.first(where: { $0.rawValue.lowercased() == lower[i + 1] }) {
                    parsed.tag = tag
                    consumed[i] = true
                    consumed[i + 1] = true
                    i += 2
                    continue
                }
            }

            // 2. Size comparators: "over 5 mb", "under 100mb", "> 10 mb"
            if let isMin = comparator(w), i + 1 < tokens.count,
               let (bytes, used) = size(at: i + 1, in: lower) {
                if isMin {
                    parsed.minSize = bytes
                } else {
                    parsed.maxSize = bytes
                }
                for k in i..<(i + 1 + used) { consumed[k] = true }
                i += 1 + used
                continue
            }

            // 3. Relative date phrases: "today", "yesterday", "last week", "past month", "this year", "3 days ago"
            if w == "today" {
                parsed.after = calendar.startOfDay(for: now)
                parsed.dateLabel = "Today"
                consumed[i] = true
                i += 1
                continue
            }
            if w == "yesterday" {
                let startToday = calendar.startOfDay(for: now)
                if let startYest = calendar.date(byAdding: .day, value: -1, to: startToday) {
                    parsed.after = startYest
                    parsed.before = startToday
                    parsed.dateLabel = "Yesterday"
                }
                consumed[i] = true
                i += 1
                continue
            }
            if (w == "last" || w == "past" || w == "this") && i + 1 < tokens.count {
                if let comp = dateUnit(lower[i + 1]) {
                    let offset = (w == "this") ? -1 : -1
                    if let cutoff = calendar.date(byAdding: comp, value: offset, to: now) {
                        parsed.after = cutoff
                        parsed.dateLabel = "\(w.capitalized) \(lower[i + 1])"
                        consumed[i] = true
                        consumed[i + 1] = true
                        if i > 0 && ["from", "in", "since", "during"].contains(lower[i - 1]) {
                            consumed[i - 1] = true
                        }
                        i += 2
                        continue
                    }
                }
            }
            if let n = Int(w), i + 2 < tokens.count, let comp = dateUnit(lower[i + 1]), lower[i + 2] == "ago" {
                if let cutoff = calendar.date(byAdding: comp, value: -n, to: now) {
                    parsed.after = cutoff
                    parsed.dateLabel = "Past \(n) \(lower[i + 1])"
                    consumed[i] = true
                    consumed[i + 1] = true
                    consumed[i + 2] = true
                    i += 3
                    continue
                }
            }

            // 4. Year or Month: "in 2025", "from 2024", "january"
            if let yr = year(w), i > 0 && ["in", "from", "during", "of"].contains(lower[i - 1]) {
                var comps = DateComponents()
                comps.year = yr
                comps.month = 1
                comps.day = 1
                if let start = calendar.date(from: comps),
                   let end = calendar.date(byAdding: .year, value: 1, to: start) {
                    parsed.after = start
                    parsed.before = end
                    parsed.dateLabel = "\(yr)"
                    consumed[i - 1] = true
                    consumed[i] = true
                    i += 1
                    continue
                }
            }
            if let m = months[w] {
                let yr = (i + 1 < tokens.count ? year(lower[i + 1]) : nil) ?? calendar.component(.year, from: now)
                var comps = DateComponents()
                comps.year = yr
                comps.month = m
                comps.day = 1
                if let start = calendar.date(from: comps),
                   let end = calendar.date(byAdding: .month, value: 1, to: start) {
                    parsed.after = start
                    parsed.before = end
                    parsed.dateLabel = tokens[i].capitalized
                    consumed[i] = true
                    if i > 0 && ["in", "from", "during"].contains(lower[i - 1]) { consumed[i - 1] = true }
                    if i + 1 < tokens.count && year(lower[i + 1]) != nil {
                        consumed[i + 1] = true
                        i += 2
                        continue
                    }
                    i += 1
                    continue
                }
            }

            // 5. Camera: "taken with iphone", "shot on sony"
            if cameras.contains(w) && i > 0 && ["on", "with", "by", "from"].contains(lower[i - 1]) {
                parsed.camera = w
                consumed[i - 1] = true
                consumed[i] = true
                if i >= 2 && ["shot", "taken"].contains(lower[i - 2]) {
                    consumed[i - 2] = true
                }
                i += 1
                continue
            }

            // 6. Download Source: "from slack", "from chatgpt", "from google drive"
            if i > 0 && ["from", "via", "on"].contains(lower[i - 1]) {
                if i + 1 < tokens.count, let src2 = DownloadSources.forKeyword("\(w) \(lower[i + 1])") {
                    parsed.source = src2
                    consumed[i - 1] = true
                    consumed[i] = true
                    consumed[i + 1] = true
                    i += 2
                    continue
                }
                if let src = DownloadSources.forKeyword(w) {
                    parsed.source = src
                    consumed[i - 1] = true
                    consumed[i] = true
                    i += 1
                    continue
                }
            }

            // 7. Folder Location: "in downloads", "in desktop", "in documents"
            if i > 0 && ["in", "from", "on"].contains(lower[i - 1]) {
                if let loc = Location.standard.first(where: { $0.title.lowercased() == w }) {
                    parsed.folder = loc
                    consumed[i - 1] = true
                    consumed[i] = true
                    i += 1
                    continue
                }
            }

            // 8. Kind / File Category
            if let kind = kinds[w] {
                if kind.screenshots {
                    parsed.screenshotsOnly = true
                    parsed.category = .images
                } else {
                    parsed.category = kind.category
                    if !kind.extensions.isEmpty {
                        parsed.extensions = kind.extensions
                    } else if ["png", "jpg", "jpeg", "heic", "gif", "webp", "svg", "mp4", "mov", "mp3", "m4a", "wav", "json", "html", "sh"].contains(w) {
                        parsed.extensions = [w]
                    }
                }
                parsed.kindLabel = kind.label
                consumed[i] = true
                i += 1
                continue
            }

            i += 1
        }

        // Collect remaining non-stopword terms
        for idx in 0..<tokens.count where !consumed[idx] {
            let word = lower[idx]
            if !stopWords.contains(word) {
                parsed.terms.append(tokens[idx])
            }
        }

        return parsed
    }

    private static func tokenize(_ s: String) -> [String] {
        s.replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private static func comparator(_ word: String) -> Bool? {
        switch word {
        case "over", "above", "larger", "bigger", "greater", "more", "exceeding", ">", ">=":
            return true
        case "under", "below", "smaller", "less", "<", "<=":
            return false
        default:
            return nil
        }
    }

    private static func multiplier(_ unit: String) -> Double? {
        switch unit {
        case "kb", "k": return 1_000
        case "mb", "m": return 1_000_000
        case "gb", "g": return 1_000_000_000
        case "tb", "t": return 1_000_000_000_000
        default: return nil
        }
    }

    private static func size(at index: Int, in tokens: [String]) -> (Int64, Int)? {
        guard index < tokens.count else { return nil }
        let tok = tokens[index]
        let startIdx = (tok == "than" && index + 1 < tokens.count) ? index + 1 : index
        let usedPrefix = startIdx - index
        let candidate = tokens[startIdx]

        // Combined e.g. "10mb"
        for suffix in ["kb", "mb", "gb", "tb"] where candidate.hasSuffix(suffix) {
            let numStr = String(candidate.dropLast(suffix.count))
            if let val = Double(numStr), let mult = multiplier(suffix) {
                return (Int64(val * mult), usedPrefix + 1)
            }
        }
        // Separate e.g. "5" "mb"
        if let val = Double(candidate), startIdx + 1 < tokens.count, let mult = multiplier(tokens[startIdx + 1]) {
            return (Int64(val * mult), usedPrefix + 2)
        }
        return nil
    }

    private static func dateUnit(_ word: String) -> Calendar.Component? {
        switch word {
        case "day", "days": return .day
        case "week", "weeks": return .weekOfYear
        case "month", "months": return .month
        case "year", "years": return .year
        default: return nil
        }
    }

    private static func year(_ word: String?) -> Int? {
        guard let word, word.count == 4, let y = Int(word), (1990...2040).contains(y) else { return nil }
        return y
    }
}
