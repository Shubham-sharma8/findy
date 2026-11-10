import Foundation
import SwiftUI
import AppKit

// MARK: - Spotlight Result & Health

public struct SpotlightResult: Equatable, Sendable {
    public var items: [FileItem]
    public var totalCount: Int
    public var totalSize: Int64

    public init(items: [FileItem] = [], totalCount: Int = 0, totalSize: Int64 = 0) {
        self.items = items
        self.totalCount = totalCount
        self.totalSize = totalSize
    }
}

public enum SpotlightHealth: Equatable, Sendable {
    case unknown
    case ok
    case disabled
    case empty
}

// MARK: - Spotlight Runner

public enum Spotlight {
    private static let excludedFragments: [String] = [
        "/DerivedData/", "/Pods/", "/node_modules/", "/site-packages/",
        ".app/", ".framework/", ".bundle/", ".lproj/", ".xcassets/",
        ".xcodeproj/", ".xcworkspace/", ".photoslibrary/", ".musiclibrary/", ".tvlibrary/"
    ]

    public static func isAllowedPath(_ path: String) -> Bool {
        for frag in excludedFragments {
            if path.contains(frag) { return false }
        }
        return true
    }

    @MainActor
    public static func run(
        _ predicateFormat: String,
        scopes: [URL],
        sortKey: String = kMDItemFSContentChangeDate as String,
        limit: Int = 300,
        timeout: Double = 3.5,
        accept: (@Sendable (FileItem) -> Bool)? = nil
    ) async -> SpotlightResult {
        guard let predicate = NSPredicate(fromMetadataQueryString: predicateFormat) else {
            return SpotlightResult()
        }
        return await withCheckedContinuation { continuation in
            let query = NSMetadataQuery()
            query.predicate = predicate
            query.searchScopes = scopes
            query.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: false)]

            var finished = false
            var observer: NSObjectProtocol?

            let complete: () -> Void = {
                guard !finished else { return }
                finished = true
                query.disableUpdates()
                query.stop()
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                let result = collect(query, limit: limit, accept: accept)
                continuation.resume(returning: result)
            }

            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { _ in
                complete()
            }

            if !query.start() {
                complete()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                complete()
            }
        }
    }

    private static func collect(
        _ query: NSMetadataQuery,
        limit: Int,
        accept: (@Sendable (FileItem) -> Bool)?
    ) -> SpotlightResult {
        let count = query.resultCount
        guard count > 0 else { return SpotlightResult() }

        var items: [FileItem] = []
        items.reserveCapacity(min(count, limit))
        var matchedInSample = 0
        var sampleBytes: Int64 = 0
        let maxInspect = accept == nil ? min(count, max(limit * 2, 450)) : min(count, 1_500)
        var inspected = 0

        for i in 0..<maxInspect {
            inspected += 1
            guard let md = query.result(at: i) as? NSMetadataItem,
                  let path = md.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            if !path.hasSuffix(".app") && !isAllowedPath(path) { continue }
            guard let item = FileItem(metadata: md) else { continue }
            if let accept, !accept(item) { continue }
            matchedInSample += 1
            sampleBytes += item.size
            if items.count < limit {
                items.append(item)
            } else if accept == nil && inspected >= limit {
                break
            }
        }

        if inspected < count && inspected > 0 && matchedInSample > 0 {
            let ratio = Double(count) / Double(inspected)
            let estimatedTotal = max(items.count, Int((Double(matchedInSample) * ratio).rounded()))
            let estimatedBytes = max(sampleBytes, Int64((Double(sampleBytes) * ratio).rounded()))
            return SpotlightResult(items: items, totalCount: estimatedTotal, totalSize: estimatedBytes)
        }
        return SpotlightResult(items: items, totalCount: matchedInSample, totalSize: sampleBytes)
    }
}

// MARK: - Disk Search Fallback

public enum DiskSearch {
    public static func run(
        _ parsed: ParsedQuery,
        scopes: [URL],
        limit: Int = 250,
        timeBudget: Double = 2.0,
        maxEntries: Int = 15_000
    ) async -> [FileItem] {
        await Task.detached {
            let start = Date()
            var results: [FileItem] = []
            var inspected = 0
            let fm = FileManager.default
            let keys: [URLResourceKey] = [
                .nameKey, .fileSizeKey, .contentModificationDateKey,
                .creationDateKey, .contentTypeKey, .isDirectoryKey, .isPackageKey, .tagNamesKey
            ]

            let searchDirs = parsed.folder.map { [$0.url] } ?? scopes
            for root in searchDirs {
                guard let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                while let fileURL = enumerator.nextObject() as? URL {
                    inspected += 1
                    if inspected > maxEntries || Date().timeIntervalSince(start) > timeBudget {
                        break
                    }
                    if !Spotlight.isAllowedPath(fileURL.path) && !fileURL.path.hasSuffix(".app") {
                        continue
                    }
                    guard let item = FileItem(url: fileURL) else { continue }
                    if parsed.matches(item) {
                        results.append(item)
                        if results.count >= limit { break }
                    }
                }
                if results.count >= limit { break }
            }
            return results.sorted { $0.modified > $1.modified }
        }.value
    }
}

// MARK: - Library Store

@Observable
public final class LibraryStore {
    public var collections: [SidebarItem: SpotlightResult] = [:]
    public var loading: Set<SidebarItem> = []
    public var searchResult: SpotlightResult?
    public var searchedQuery: String = ""
    public var isSearching: Bool = false
    public var spotlightHealth: SpotlightHealth = .unknown
    public var parsedQuery: ParsedQuery?
    public var textMatchCount: Int = 0

    public let scopes: [URL]
    public let searchTimeout: Double
    private var loadedToken: Int = -1
    private var latestQuery: Int = 0

    public init(scopes: [URL] = LibraryStore.defaultScopes(), searchTimeout: Double = 3.5) {
        self.scopes = scopes
        self.searchTimeout = searchTimeout
    }

    public static func defaultScopes() -> [URL] {
        Location.standard.map(\.url)
    }

    public static func listFolder(_ url: URL) async throws -> [FileItem] {
        try await Task.detached {
            let keys: [URLResourceKey] = [
                .nameKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                .contentModificationDateKey, .creationDateKey,
                .contentTypeKey, .isDirectoryKey, .isPackageKey, .tagNamesKey
            ]
            let urls = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
            return urls.compactMap { FileItem(url: $0) }
        }.value
    }

    @MainActor
    public func load(_ item: SidebarItem, token: Int) async {
        if token != loadedToken {
            loadedToken = token
            collections.removeAll()
        }
        guard collections[item] == nil && !loading.contains(item) else { return }
        loading.insert(item)
        let res = await result(for: item, token: token)
        collections[item] = res
        loading.remove(item)
    }

    @MainActor
    public func result(for item: SidebarItem, token: Int) async -> SpotlightResult {
        switch item {
        case .smart(let sc):
            switch sc {
            case .recents:
                let r = await Spotlight.run("kMDItemLastUsedDate >= $time.today(-30)", scopes: scopes, sortKey: kMDItemLastUsedDate as String, limit: 200)
                if !r.items.isEmpty { return r }
                let fallback = await DiskSearch.run(NaturalSearch.parse("from last month"), scopes: scopes, limit: 150)
                return SpotlightResult(items: fallback, totalCount: fallback.count, totalSize: fallback.reduce(0) { $0 + $1.size })
            case .large:
                let r = await Spotlight.run("kMDItemFSSize > 100000000", scopes: scopes, sortKey: kMDItemFSSize as String, limit: 200)
                if !r.items.isEmpty { return r }
                let fallback = await DiskSearch.run(NaturalSearch.parse("over 100 mb"), scopes: scopes, limit: 150)
                return SpotlightResult(items: fallback, totalCount: fallback.count, totalSize: fallback.reduce(0) { $0 + $1.size })
            case .screenshots:
                let r = await Spotlight.run("kMDItemIsScreenCapture == 1", scopes: scopes, limit: 250)
                if !r.items.isEmpty { return r }
                let fallback = await DiskSearch.run(NaturalSearch.parse("screenshots"), scopes: scopes, limit: 150)
                return SpotlightResult(items: fallback, totalCount: fallback.count, totalSize: fallback.reduce(0) { $0 + $1.size })
            }
        case .category(let cat):
            let searchScopes: [URL] = (cat == .apps)
                ? [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
                : scopes
            let r = await Spotlight.run(cat.spotlightQuery, scopes: searchScopes, limit: 350)
            if cat == .apps {
                await checkSpotlightHealth(appsCount: r.items.count)
            }
            if !r.items.isEmpty { return r }
            var q = ParsedQuery(raw: cat.title)
            q.category = cat
            let fallback = await DiskSearch.run(q, scopes: searchScopes, limit: 200)
            return SpotlightResult(items: fallback, totalCount: fallback.count, totalSize: fallback.reduce(0) { $0 + $1.size })
        case .tag(let tag):
            var q = ParsedQuery(raw: "tagged \(tag.rawValue)")
            q.tag = tag
            let matches = await DiskSearch.run(q, scopes: scopes, limit: 250)
            return SpotlightResult(items: matches, totalCount: matches.count, totalSize: matches.reduce(0) { $0 + $1.size })
        default:
            return SpotlightResult()
        }
    }

    @MainActor
    public func find(_ query: String, textIndex: TextIndex?, limit: Int = 250) async -> (result: SpotlightResult, parsed: ParsedQuery, textHits: Int) {
        let parsed = NaturalSearch.parse(query)
        let activeScopes = parsed.folder.map { [$0.url] } ?? scopes
        let spot = await Spotlight.run(parsed.spotlightQuery, scopes: activeScopes, limit: limit, timeout: searchTimeout) { item in
            parsed.matches(item)
        }

        var merged = spot.items
        var seen = Set(merged.map(\.url))

        if merged.count < 25 {
            let diskItems = await DiskSearch.run(parsed, scopes: activeScopes, limit: limit)
            for item in diskItems where !seen.contains(item.url) {
                seen.insert(item.url)
                merged.append(item)
            }
        }

        var ocrCount = 0
        if let textIndex, !parsed.terms.isEmpty {
            let ocrMatches = textIndex.matchingURLs(for: parsed.terms)
            for url in ocrMatches where !seen.contains(url) {
                if let item = FileItem(url: url) {
                    seen.insert(url)
                    merged.append(item)
                    ocrCount += 1
                }
            }
        }

        let totalSize = merged.reduce(Int64(0)) { $0 + $1.size }
        let finalResult = SpotlightResult(items: merged, totalCount: max(spot.totalCount, merged.count), totalSize: totalSize)
        return (finalResult, parsed, ocrCount)
    }

    @MainActor
    public func search(_ query: String, textIndex: TextIndex?) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResult = nil
            searchedQuery = ""
            parsedQuery = nil
            textMatchCount = 0
            isSearching = false
            return
        }
        latestQuery += 1
        let token = latestQuery
        isSearching = true
        searchedQuery = trimmed

        let (res, parsed, hits) = await find(trimmed, textIndex: textIndex)
        guard token == latestQuery else { return }
        self.searchResult = res
        self.parsedQuery = parsed
        self.textMatchCount = hits
        self.isSearching = false
    }

    @MainActor
    private func checkSpotlightHealth(appsCount: Int) async {
        if appsCount > 0 {
            spotlightHealth = .ok
            return
        }
        let status = await Task.detached { () -> SpotlightHealth in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
            proc.arguments = ["-s", "/"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.lowercased() ?? ""
            if out.contains("indexing disabled") || out.contains("server is disabled") {
                return .disabled
            }
            return .ok
        }.value
        spotlightHealth = status
    }

    public func remove(_ urls: Set<URL>) {
        for (key, var val) in collections {
            let before = val.items.count
            val.items.removeAll { urls.contains($0.url) }
            let diff = before - val.items.count
            if diff > 0 {
                val.totalCount = max(0, val.totalCount - diff)
                val.totalSize = val.items.reduce(0) { $0 + $1.size }
                collections[key] = val
            }
        }
        if var sr = searchResult {
            sr.items.removeAll { urls.contains($0.url) }
            sr.totalCount = sr.items.count
            sr.totalSize = sr.items.reduce(0) { $0 + $1.size }
            searchResult = sr
        }
    }
}

// MARK: - Application State

@Observable
public final class AppState {
    public struct Toast: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let message: String
        public let symbol: String
        public var sticky: Bool = false

        public init(message: String, symbol: String = "checkmark.circle.fill", sticky: Bool = false) {
            self.message = message
            self.symbol = symbol
            self.sticky = sticky
        }
    }

    public var selection: SidebarItem? = .home {
        didSet {
            if selection != oldValue {
                folderPath = []
                clearSelection()
                kindFilter = nil
                sourceFilter = nil
            }
        }
    }
    public var folderPath: [URL] = []
    public var searchText: String = ""
    public var kindFilter: FileCategory?
    public var dateFilter: DateFilter = .any
    public var sizeFilter: SizeFilter = .any
    public var sourceFilter: String?
    public var tagFilter: FinderTag?
    public var sidebarCollapsed: Bool = false
    public var viewMode: ViewMode {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }
    public var cardSize: CardSize {
        didSet { UserDefaults.standard.set(cardSize.rawValue, forKey: "cardSize") }
    }
    public var sortKey: SortKey = .date
    public var ascending: Bool = false
    public var selectedFiles: Set<URL> = []
    public var focusedItem: FileItem?
    public var isSelecting: Bool = false
    public var selectionAnchor: URL?
    public var hoveredCheckbox: URL?
    public var showInspector: Bool = false
    public var previewItem: FileItem?
    public var previewList: [FileItem] = []
    public var refreshToken: Int = 0
    public var focusSearchToken: Int = 0
    public var toast: Toast?
    public var showBatchRename: Bool = false
    public var pinned: [URL] {
        didSet {
            UserDefaults.standard.set(pinned.map(\.path), forKey: "pinned")
        }
    }
    public var savedSearches: [SavedSearch] = []

    public init() {
        let vmRaw = UserDefaults.standard.string(forKey: "viewMode") ?? ViewMode.grid.rawValue
        self.viewMode = ViewMode(rawValue: vmRaw) ?? .grid
        let csRaw = UserDefaults.standard.string(forKey: "cardSize") ?? CardSize.medium.rawValue
        self.cardSize = CardSize(rawValue: csRaw) ?? .medium
        let pinnedPaths = UserDefaults.standard.stringArray(forKey: "pinned") ?? []
        self.pinned = pinnedPaths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        self.savedSearches = SavedSearch.load()
    }

    public var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var filtersActive: Bool {
        kindFilter != nil || dateFilter != .any || sizeFilter != .any || sourceFilter != nil || tagFilter != nil
    }

    public func applyFilters(_ items: [FileItem]) -> [FileItem] {
        items.filter { item in
            if let kindFilter, item.category != kindFilter { return false }
            if let cutoff = dateFilter.cutoff, item.modified < cutoff && item.created < cutoff { return false }
            if sizeFilter != .any && item.size < sizeFilter.minBytes { return false }
            if let sourceFilter {
                guard let src = DownloadSources.source(for: item.url), src.name == sourceFilter else { return false }
            }
            if let tagFilter {
                let hasTag = item.tags.contains { $0.caseInsensitiveCompare(tagFilter.rawValue) == .orderedSame }
                if !hasTag { return false }
            }
            return true
        }
    }

    public func sort(_ items: [FileItem], foldersFirst: Bool = false) -> [FileItem] {
        items.sorted { a, b in
            if foldersFirst && (a.category == .folders) != (b.category == .folders) {
                return a.category == .folders
            }
            let cmp: Bool
            switch sortKey {
            case .name:
                cmp = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .date:
                cmp = a.modified < b.modified
            case .size:
                cmp = a.size < b.size
            case .kind:
                cmp = a.kindDescription.localizedStandardCompare(b.kindDescription) == .orderedAscending
            }
            return ascending ? cmp : !cmp
        }
    }

    public func setSort(_ key: SortKey) {
        if sortKey == key {
            ascending.toggle()
        } else {
            sortKey = key
            ascending = key.defaultAscending
        }
    }

    public func clearSelection() {
        selectedFiles.removeAll()
        isSelecting = false
        selectionAnchor = nil
    }

    public func selectAll(_ items: [FileItem]) {
        selectedFiles = Set(items.map(\.url))
        isSelecting = !selectedFiles.isEmpty
    }

    public func select(_ item: FileItem, in list: [FileItem]) {
        focusedItem = item
        let flags = NSEvent.modifierFlags

        if flags.contains(.shift),
           let anchor = selectionAnchor,
           let anchorIdx = list.firstIndex(where: { $0.url == anchor }),
           let targetIdx = list.firstIndex(where: { $0.url == item.url }) {
            let lower = min(anchorIdx, targetIdx)
            let upper = max(anchorIdx, targetIdx)
            for idx in lower...upper {
                selectedFiles.insert(list[idx].url)
            }
            isSelecting = selectedFiles.count > 1
            return
        }

        if flags.contains(.command) || isSelecting {
            if selectedFiles.contains(item.url) {
                selectedFiles.remove(item.url)
            } else {
                selectedFiles.insert(item.url)
            }
            if flags.contains(.command) && selectedFiles.count > 1 {
                isSelecting = true
            }
        } else {
            selectedFiles = [item.url]
        }
        selectionAnchor = item.url
    }

    public func targets(for item: FileItem, in list: [FileItem]) -> [FileItem] {
        if selectedFiles.contains(item.url) && selectedFiles.count > 1 {
            return list.filter { selectedFiles.contains($0.url) }
        }
        return [item]
    }

    public func openFolder(_ url: URL) {
        let std = Location.standard.first { $0.url.standardizedFileURL == url.standardizedFileURL }
        if let std {
            selection = .location(std)
            folderPath = []
        } else if case .location(let root) = selection, url.standardizedFileURL.path.hasPrefix(root.url.standardizedFileURL.path) {
            if let idx = folderPath.firstIndex(of: url) {
                folderPath = Array(folderPath.prefix(through: idx))
            } else {
                folderPath.append(url)
            }
        } else {
            let loc = Location(url: url, title: url.lastPathComponent, symbol: "folder.fill")
            selection = .location(loc)
            folderPath = []
        }
    }

    public func togglePin(_ url: URL) {
        if let idx = pinned.firstIndex(of: url) {
            pinned.remove(at: idx)
            showToast("Removed from Favourites", symbol: "star.slash.fill")
        } else {
            pinned.append(url)
            showToast("Added to Favourites", symbol: "star.fill")
        }
    }

    public func preview(_ item: FileItem, in list: [FileItem]) {
        focusedItem = item
        previewItem = item
        previewList = list
    }

    public func stepPreview(_ delta: Int) {
        guard let current = previewItem,
              let idx = previewList.firstIndex(of: current) else { return }
        let nextIdx = idx + delta
        guard previewList.indices.contains(nextIdx) else { return }
        let nextItem = previewList[nextIdx]
        previewItem = nextItem
        focusedItem = nextItem
    }

    public func showToast(_ message: String, symbol: String = "checkmark.circle.fill") {
        let t = Toast(message: message, symbol: symbol)
        toast = t
        let id = t.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            if self?.toast?.id == id {
                self?.toast = nil
            }
        }
    }
}
