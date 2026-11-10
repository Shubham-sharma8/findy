import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Finder Color Tags (Improved Feature)

public enum FinderTag: String, CaseIterable, Identifiable, Codable, Sendable {
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"
    case gray = "Gray"

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .red: return Color(red: 0.95, green: 0.30, blue: 0.28)
        case .orange: return Color(red: 0.96, green: 0.58, blue: 0.18)
        case .yellow: return Color(red: 0.95, green: 0.78, blue: 0.18)
        case .green: return Color(red: 0.25, green: 0.78, blue: 0.42)
        case .blue: return Color(red: 0.24, green: 0.54, blue: 0.96)
        case .purple: return Color(red: 0.65, green: 0.38, blue: 0.92)
        case .gray: return Color.secondary
        }
    }
}

// MARK: - File Category

public enum FileCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case images
    case videos
    case music
    case documents
    case archives
    case apps
    case code
    case folders
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .images: return "Images"
        case .videos: return "Videos"
        case .music: return "Music"
        case .documents: return "Documents"
        case .archives: return "Archives"
        case .apps: return "Applications"
        case .code: return "Code"
        case .folders: return "Folders"
        case .other: return "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .images: return "photo.fill"
        case .videos: return "play.rectangle.fill"
        case .music: return "music.note"
        case .documents: return "doc.text.fill"
        case .archives: return "shippingbox.fill"
        case .apps: return "app.dashed"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .folders: return "folder.fill"
        case .other: return "doc.fill"
        }
    }

    public var fillsTile: Bool {
        self == .images || self == .videos
    }

    public var gradient: [Color] {
        switch self {
        case .images: return [Color(red: 0.98, green: 0.42, blue: 0.55), Color(red: 0.96, green: 0.25, blue: 0.42)]
        case .videos: return [Color(red: 0.58, green: 0.36, blue: 0.96), Color(red: 0.42, green: 0.24, blue: 0.86)]
        case .music: return [Color(red: 0.98, green: 0.54, blue: 0.22), Color(red: 0.92, green: 0.36, blue: 0.16)]
        case .documents: return [Color(red: 0.22, green: 0.58, blue: 0.98), Color(red: 0.14, green: 0.42, blue: 0.88)]
        case .archives: return [Color(red: 0.78, green: 0.58, blue: 0.32), Color(red: 0.62, green: 0.42, blue: 0.22)]
        case .apps: return [Color(red: 0.20, green: 0.74, blue: 0.86), Color(red: 0.12, green: 0.56, blue: 0.74)]
        case .code: return [Color(red: 0.22, green: 0.78, blue: 0.52), Color(red: 0.14, green: 0.62, blue: 0.38)]
        case .folders: return [Color(red: 0.34, green: 0.64, blue: 0.96), Color(red: 0.22, green: 0.48, blue: 0.84)]
        case .other: return [Color(red: 0.54, green: 0.58, blue: 0.66), Color(red: 0.40, green: 0.44, blue: 0.52)]
        }
    }

    public var spotlightQuery: String {
        switch self {
        case .images:
            return "kMDItemContentTypeTree == 'public.image'"
        case .videos:
            return "kMDItemContentTypeTree == 'public.movie' && kMDItemFSName != '*.ts'c"
        case .music:
            return "kMDItemContentTypeTree == 'public.audio'"
        case .documents:
            return "(kMDItemContentTypeTree == 'com.adobe.pdf' || kMDItemContentTypeTree == 'public.composite-content' || kMDItemContentTypeTree == 'public.presentation' || kMDItemContentTypeTree == 'public.spreadsheet' || kMDItemContentTypeTree == 'public.rtf' || ((kMDItemFSName == '*.txt'c || kMDItemFSName == '*.md'c) && kMDItemLastUsedDate == *))"
        case .archives:
            return "(kMDItemContentTypeTree == 'public.archive' || kMDItemContentTypeTree == 'com.apple.disk-image')"
        case .apps:
            return "kMDItemContentTypeTree == 'com.apple.application-bundle'"
        case .code:
            return "kMDItemContentTypeTree == 'public.source-code' && kMDItemFSName != '*.ts'c && kMDItemLastUsedDate == *"
        case .folders:
            return "kMDItemContentTypeTree == 'public.folder'"
        case .other:
            return "kMDItemFSName == '*'"
        }
    }

    public static func classify(_ type: UTType?, isDirectory: Bool) -> FileCategory {
        if let type {
            if type.conforms(to: .applicationBundle) { return .apps }
            if isDirectory && (type.conforms(to: .folder) || type.conforms(to: .directory)) && !type.conforms(to: .package) {
                return .folders
            }
            if type.conforms(to: .image) { return .images }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .videos }
            if type.conforms(to: .audio) { return .music }
            if type.conforms(to: .archive) || type.conforms(to: .diskImage) || type.identifier == "com.apple.installer-package-archive" {
                return .archives
            }
            if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .json) || type.conforms(to: .yaml) || type.conforms(to: .xml) {
                return .code
            }
            if type.conforms(to: .pdf) || type.conforms(to: .presentation) || type.conforms(to: .spreadsheet) || type.conforms(to: .compositeContent) || type.conforms(to: .text) || type.conforms(to: .rtf) {
                return .documents
            }
        }
        if isDirectory { return .folders }
        return .other
    }
}

// MARK: - Filters, View Modes & Sort Keys

public enum DateFilter: String, CaseIterable, Identifiable, Sendable {
    case any
    case today
    case week
    case month
    case year

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any: return "Any Time"
        case .today: return "Today"
        case .week: return "Past Week"
        case .month: return "Past Month"
        case .year: return "Past Year"
        }
    }

    public var cutoff: Date? {
        let now = Date()
        let cal = Calendar.current
        switch self {
        case .any: return nil
        case .today: return cal.startOfDay(for: now)
        case .week: return cal.date(byAdding: .day, value: -7, to: now)
        case .month: return cal.date(byAdding: .month, value: -1, to: now)
        case .year: return cal.date(byAdding: .year, value: -1, to: now)
        }
    }
}

public enum SizeFilter: String, CaseIterable, Identifiable, Sendable {
    case any
    case mb1
    case mb10
    case mb100
    case gb1

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any: return "Any Size"
        case .mb1: return "Over 1 MB"
        case .mb10: return "Over 10 MB"
        case .mb100: return "Over 100 MB"
        case .gb1: return "Over 1 GB"
        }
    }

    public var minBytes: Int64 {
        switch self {
        case .any: return 0
        case .mb1: return 1_000_000
        case .mb10: return 10_000_000
        case .mb100: return 100_000_000
        case .gb1: return 1_000_000_000
        }
    }
}

public enum ViewMode: String, CaseIterable, Identifiable, Sendable {
    case grid
    case list

    public var id: String { rawValue }
}

public enum CardSize: String, CaseIterable, Identifiable, Sendable {
    case xsmall
    case small
    case medium
    case large
    case xlarge

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .xsmall: return "Extra Small"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .xlarge: return "Extra Large"
        }
    }

    public var minWidth: CGFloat {
        switch self {
        case .xsmall: return 120
        case .small: return 155
        case .medium: return 195
        case .large: return 245
        case .xlarge: return 310
        }
    }

    public var height: CGFloat {
        switch self {
        case .xsmall: return 105
        case .small: return 130
        case .medium: return 160
        case .large: return 200
        case .xlarge: return 250
        }
    }

    public var bigger: CardSize? {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }

    public var smaller: CardSize? {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self), idx > 0 else { return nil }
        return all[idx - 1]
    }

    public static func columns(for size: CardSize, in width: CGFloat, spacing: CGFloat) -> Int {
        let available = max(width, size.minWidth)
        return max(1, Int((available + spacing) / (size.minWidth + spacing)))
    }
}

private struct CardSizeKey: EnvironmentKey {
    static let defaultValue: CardSize? = nil
}

extension EnvironmentValues {
    public var cardSize: CardSize? {
        get { self[CardSizeKey.self] }
        set { self[CardSizeKey.self] = newValue }
    }
}

public enum SortKey: String, CaseIterable, Identifiable, Sendable {
    case name
    case date
    case size
    case kind

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .name: return "Name"
        case .date: return "Date"
        case .size: return "Size"
        case .kind: return "Kind"
        }
    }

    public var defaultAscending: Bool {
        switch self {
        case .name, .kind: return true
        case .date, .size: return false
        }
    }
}

public enum SmartCollection: String, CaseIterable, Identifiable, Sendable {
    case recents
    case large
    case screenshots

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recents: return "Recents"
        case .large: return "Large Files"
        case .screenshots: return "Screenshots"
        }
    }

    public var symbol: String {
        switch self {
        case .recents: return "clock.fill"
        case .large: return "internaldrive.fill"
        case .screenshots: return "camera.viewfinder"
        }
    }
}

// MARK: - Locations & Sidebar Items

public struct Location: Identifiable, Hashable, Sendable {
    public let url: URL
    public let title: String
    public let symbol: String

    public var id: URL { url }

    public init(url: URL, title: String, symbol: String) {
        self.url = url
        self.title = title
        self.symbol = symbol
    }

    public static var standard: [Location] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var list: [Location] = [
            Location(url: home.appendingPathComponent("Downloads"), title: "Downloads", symbol: "arrow.down.circle.fill"),
            Location(url: home.appendingPathComponent("Desktop"), title: "Desktop", symbol: "menubar.dock.rectangle"),
            Location(url: home.appendingPathComponent("Documents"), title: "Documents", symbol: "doc.text.fill"),
            Location(url: home.appendingPathComponent("Pictures"), title: "Pictures", symbol: "photo.fill"),
            Location(url: home.appendingPathComponent("Movies"), title: "Movies", symbol: "film.stack.fill"),
            Location(url: home.appendingPathComponent("Music"), title: "Music", symbol: "music.note.list")
        ]
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: icloud.path) {
            list.append(Location(url: icloud, title: "iCloud Drive", symbol: "icloud.fill"))
        }
        return list.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }
}

public enum SidebarItem: Hashable, Identifiable, Sendable {
    case home
    case smart(SmartCollection)
    case category(FileCategory)
    case location(Location)
    case cleanup(CleanupKind)
    case cleanupHub
    case duplicates
    case sources
    case source(String)
    case spaceLens
    case fileShelf
    case tag(FinderTag)

    public var id: Self { self }

    public var title: String {
        switch self {
        case .home: return "Home"
        case .smart(let sc): return sc.title
        case .category(let cat): return cat.title
        case .location(let loc): return loc.title
        case .cleanup(let kind): return kind.title
        case .cleanupHub: return "Clean Up"
        case .duplicates: return "Duplicates"
        case .sources: return "Downloaded From"
        case .source(let name): return name
        case .spaceLens: return "Space Lens"
        case .fileShelf: return "File Shelf"
        case .tag(let tag): return tag.rawValue
        }
    }
}

// MARK: - FileItem

public struct FileItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public var size: Int64
    public let modified: Date
    public let created: Date
    public let contentType: UTType?
    public let category: FileCategory
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var duration: Double?
    public var artist: String?
    public var album: String?
    public var title: String?
    public var tags: [String]

    public var id: URL { url }

    public init(
        url: URL,
        name: String,
        size: Int64,
        modified: Date,
        created: Date,
        contentType: UTType?,
        category: FileCategory,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        duration: Double? = nil,
        artist: String? = nil,
        album: String? = nil,
        title: String? = nil,
        tags: [String] = []
    ) {
        self.url = url
        self.name = name
        self.size = size
        self.modified = modified
        self.created = created
        self.contentType = contentType
        self.category = category
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.artist = artist
        self.album = album
        self.title = title
        self.tags = tags
    }

    public init?(url: URL) {
        let keys: Set<URLResourceKey> = [
            .nameKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .contentTypeKey,
            .isDirectoryKey,
            .isPackageKey,
            .tagNamesKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let name = values.name ?? url.lastPathComponent
        guard !name.hasPrefix(".") else { return nil }
        let isDir = values.isDirectory ?? false
        let isPkg = values.isPackage ?? false
        let utType = values.contentType ?? UTType(filenameExtension: url.pathExtension)
        let cat = FileCategory.classify(utType, isDirectory: isDir && !isPkg)
        let sz = Int64(values.fileSize ?? values.totalFileAllocatedSize ?? 0)
        let mod = values.contentModificationDate ?? Date.distantPast
        let cre = values.creationDate ?? mod
        let tagList = values.tagNames ?? []

        self.init(
            url: url,
            name: name,
            size: sz,
            modified: mod,
            created: cre,
            contentType: utType,
            category: cat,
            tags: tagList
        )
    }

    private static let metadataAttributeKeys: [String] = [
        NSMetadataItemPathKey,
        NSMetadataItemFSNameKey,
        NSMetadataItemFSSizeKey,
        NSMetadataItemFSContentChangeDateKey,
        kMDItemLastUsedDate as String,
        NSMetadataItemContentCreationDateKey,
        NSMetadataItemContentTypeKey,
        kMDItemPixelWidth as String,
        kMDItemPixelHeight as String,
        kMDItemDurationSeconds as String,
        kMDItemAuthors as String,
        kMDItemAlbum as String,
        kMDItemTitle as String,
        "kMDItemUserTags"
    ]

    public init?(metadata item: NSMetadataItem) {
        let vals = item.values(forAttributes: Self.metadataAttributeKeys)
        guard let path = (vals?[NSMetadataItemPathKey] as? String) ?? (item.value(forAttribute: NSMetadataItemPathKey) as? String) else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        let name = (vals?[NSMetadataItemFSNameKey] as? String) ?? url.lastPathComponent
        guard !name.hasPrefix(".") else { return nil }

        let size = (vals?[NSMetadataItemFSSizeKey] as? NSNumber)?.int64Value ?? 0
        let mod = (vals?[NSMetadataItemFSContentChangeDateKey] as? Date)
            ?? (vals?[kMDItemLastUsedDate as String] as? Date)
            ?? Date.distantPast
        let cre = (vals?[NSMetadataItemContentCreationDateKey] as? Date) ?? mod
        let utiStr = vals?[NSMetadataItemContentTypeKey] as? String
        let utType = utiStr.flatMap { UTType($0) } ?? UTType(filenameExtension: url.pathExtension)
        let isDir = utType?.conforms(to: .folder) ?? false
        let cat = FileCategory.classify(utType, isDirectory: isDir)

        let pw = (vals?[kMDItemPixelWidth as String] as? NSNumber)?.intValue
        let ph = (vals?[kMDItemPixelHeight as String] as? NSNumber)?.intValue
        let dur = (vals?[kMDItemDurationSeconds as String] as? NSNumber)?.doubleValue
        let authors = vals?[kMDItemAuthors as String] as? [String]
        let album = vals?[kMDItemAlbum as String] as? String
        let title = vals?[kMDItemTitle as String] as? String
        let tags = (vals?["kMDItemUserTags"] as? [String]) ?? []

        self.init(
            url: url,
            name: name,
            size: size,
            modified: mod,
            created: cre,
            contentType: utType,
            category: cat,
            pixelWidth: pw,
            pixelHeight: ph,
            duration: dur,
            artist: authors?.first,
            album: album,
            title: title,
            tags: tags
        )
    }

    public var displayTitle: String {
        if category == .apps && name.lowercased().hasSuffix(".app") {
            return String(name.dropLast(4))
        }
        return name
    }

    public var kindDescription: String {
        contentType?.localizedDescription?.capitalized ?? category.title
    }

    public var sizeText: String {
        if category == .folders && size == 0 {
            return "Folder"
        }
        return Fmt.bytes(size)
    }

    public var subtitle: String {
        if category == .folders {
            return Fmt.date(modified)
        }
        return "\(sizeText) · \(Fmt.date(modified))"
    }
}

// MARK: - Formatting Helpers

public enum Fmt {
    public static func bytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    public static func date(_ date: Date) -> String {
        if date == .distantPast { return "—" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today"
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    public static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    public static func plural(_ count: Int, _ singular: String, _ pluralForm: String? = nil) -> String {
        let word = count == 1 ? singular : (pluralForm ?? "\(singular)s")
        return "\(count.formatted()) \(word)"
    }

    public static func displayPath(_ url: URL) -> String {
        let raw = url.path.replacingOccurrences(of: "/System/Volumes/Data", with: "")
        let home = FileManager.default.homeDirectoryForCurrentUser.path.replacingOccurrences(of: "/System/Volumes/Data", with: "")
        return raw.replacingOccurrences(of: home, with: "~")
    }
}
