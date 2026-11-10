import Foundation
import SwiftUI
import CryptoKit
import Vision

// MARK: - Duplicate Group

public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var files: [FileItem]
    public var keep: URL

    public init(id: UUID = UUID(), files: [FileItem], keep: URL) {
        self.id = id
        self.files = files
        self.keep = keep
    }

    public var extras: [FileItem] {
        files.filter { $0.url != keep }
    }

    public var reclaimableBytes: Int64 {
        extras.reduce(0) { $0 + $1.size }
    }
}

// MARK: - Duplicate Scanner (Exact SHA-256 + Vision Perceptual FeaturePrint)

public enum DuplicateScanner {
    public static func fingerprint(_ url: URL, size: Int64, full: Bool) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        if !full {
            let windowSize = 16_384
            guard let head = try? handle.read(upToCount: windowSize), !head.isEmpty else { return nil }
            hasher.update(data: head)
            if size >= Int64(windowSize * 3) {
                let midOffset = UInt64(max(0, (size / 2) - Int64(windowSize / 2)))
                if (try? handle.seek(toOffset: midOffset)) != nil,
                   let mid = try? handle.read(upToCount: windowSize), !mid.isEmpty {
                    hasher.update(data: mid)
                }
                let tailOffset = UInt64(max(0, size - Int64(windowSize)))
                if (try? handle.seek(toOffset: tailOffset)) != nil,
                   let tail = try? handle.read(upToCount: windowSize), !tail.isEmpty {
                    hasher.update(data: tail)
                }
            }
            return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
        } else {
            while let chunk = try? handle.read(upToCount: 262_144), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
        }
    }

    public static func pickKeeper(_ items: [FileItem]) -> URL {
        let copyPattern = try? NSRegularExpression(pattern: #"\(\d+\)|copy|[ _-]\d\.\w+$"#, options: .caseInsensitive)
        let sorted = items.sorted { a, b in
            let aHasCopy = copyPattern?.firstMatch(in: a.name, range: NSRange(a.name.startIndex..., in: a.name)) != nil
            let bHasCopy = copyPattern?.firstMatch(in: b.name, range: NSRange(b.name.startIndex..., in: b.name)) != nil
            if aHasCopy != bHasCopy { return !aHasCopy }
            let aInDownloads = a.url.path.contains("/Downloads/")
            let bInDownloads = b.url.path.contains("/Downloads/")
            if aInDownloads != bInDownloads { return !aInDownloads }
            let aDepth = a.url.pathComponents.count
            let bDepth = b.url.pathComponents.count
            if aDepth != bDepth { return aDepth < bDepth }
            if a.name.count != b.name.count { return a.name.count < b.name.count }
            return a.created < b.created
        }
        return sorted.first?.url ?? items[0].url
    }

    public static func pickBestPhoto(_ items: [FileItem]) -> URL {
        let sorted = items.sorted { a, b in
            let resA = (a.pixelWidth ?? 0) * (a.pixelHeight ?? 0)
            let resB = (b.pixelWidth ?? 0) * (b.pixelHeight ?? 0)
            if resA != resB { return resA > resB }
            if a.size != b.size { return a.size > b.size }
            return a.created < b.created
        }
        return sorted.first?.url ?? items[0].url
    }

    public static func exactDuplicates(
        _ candidates: [FileItem],
        progress: @Sendable (Int, Int) -> Void
    ) -> [DuplicateGroup] {
        let eligible = candidates.filter { $0.size >= 51_200 && $0.category != .folders && $0.category != .apps }
        var bySize: [Int64: [FileItem]] = [:]
        for item in eligible {
            bySize[item.size, default: []].append(item)
        }
        let potentialGroups = bySize.values.filter { $0.count > 1 }
        let totalToCheck = potentialGroups.reduce(0) { $0 + $1.count }
        var checked = 0

        var groups: [DuplicateGroup] = []
        for sameSize in potentialGroups {
            var byPartial: [String: [FileItem]] = [:]
            for item in sameSize {
                checked += 1
                progress(checked, totalToCheck)
                if let partial = fingerprint(item.url, size: item.size, full: false) {
                    byPartial[partial, default: []].append(item)
                }
            }
            for partialMatches in byPartial.values where partialMatches.count > 1 {
                var byFull: [String: [FileItem]] = [:]
                for item in partialMatches {
                    if let full = fingerprint(item.url, size: item.size, full: true) {
                        byFull[full, default: []].append(item)
                    }
                }
                for exactMatches in byFull.values where exactMatches.count > 1 {
                    let keeper = pickKeeper(exactMatches)
                    groups.append(DuplicateGroup(files: exactMatches, keep: keeper))
                }
            }
        }
        return groups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    private static func featureObservation(_ url: URL) -> VNFeaturePrintObservation? {
        let req = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(url: url, options: [:])
        try? handler.perform([req])
        return req.results?.first as? VNFeaturePrintObservation
    }

    public static func similarPhotos(
        _ candidates: [FileItem],
        progress: @Sendable (Int, Int) -> Void
    ) -> [DuplicateGroup] {
        let photos = Array(candidates.filter { $0.category == .images && $0.size >= 30_000 }.prefix(240))
        guard photos.count > 1 else { return [] }

        var observations: [(FileItem, VNFeaturePrintObservation)] = []
        for (idx, item) in photos.enumerated() {
            progress(idx + 1, photos.count)
            if let obs = featureObservation(item.url) {
                observations.append((item, obs))
            }
        }

        var visited = Set<URL>()
        var groups: [DuplicateGroup] = []
        for i in 0..<observations.count {
            let (itemA, obsA) = observations[i]
            if visited.contains(itemA.url) { continue }
            var cluster: [FileItem] = [itemA]
            for j in (i + 1)..<observations.count {
                let (itemB, obsB) = observations[j]
                if visited.contains(itemB.url) { continue }
                var dist: Float = 999
                try? obsA.computeDistance(&dist, to: obsB)
                if dist < 0.35 {
                    cluster.append(itemB)
                    visited.insert(itemB.url)
                }
            }
            if cluster.count > 1 {
                visited.insert(itemA.url)
                let best = pickBestPhoto(cluster)
                groups.append(DuplicateGroup(files: cluster, keep: best))
            }
        }
        return groups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }
}

// MARK: - Duplicate Finder Store

@Observable
public final class DuplicateFinder {
    public enum Phase: String, Sendable {
        case idle
        case gathering
        case hashing
        case finished
    }

    public var phase: Phase = .idle
    public var similarPhase: Phase = .idle
    public var exact: [DuplicateGroup] = []
    public var similar: [DuplicateGroup] = []
    public var scannedFiles: Int = 0
    public var lastScan: Date?

    public init() {}

    public var exactReclaimable: Int64 {
        exact.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public var similarReclaimable: Int64 {
        similar.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public var extraCopies: Int {
        exact.reduce(0) { $0 + $1.extras.count }
    }

    @MainActor
    public func scan(scopes: [URL]) async {
        guard phase != .gathering && phase != .hashing else { return }
        phase = .gathering
        scannedFiles = 0
        let spot = await Spotlight.run("kMDItemFSSize >= 51200", scopes: scopes, limit: 1_200, timeout: 5.0)
        phase = .hashing
        let items = spot.items
        let found = await Task.detached {
            DuplicateScanner.exactDuplicates(items) { _, _ in }
        }.value
        self.exact = found
        self.scannedFiles = items.count
        self.lastScan = Date()
        self.phase = .finished
    }

    @MainActor
    public func scanSimilar(scopes: [URL]) async {
        guard similarPhase != .gathering && similarPhase != .hashing else { return }
        similarPhase = .gathering
        let spot = await Spotlight.run(
            "kMDItemContentTypeTree == 'public.image' && kMDItemFSSize >= 30000 && kMDItemPixelWidth >= 300 && kMDItemIsScreenCapture != 1",
            scopes: scopes,
            limit: 260,
            timeout: 4.5
        )
        similarPhase = .hashing
        let items = spot.items
        let found = await Task.detached {
            DuplicateScanner.similarPhotos(items) { _, _ in }
        }.value
        self.similar = found
        self.similarPhase = .finished
    }

    public func setKeeper(_ url: URL, in groupID: UUID) {
        if let idx = exact.firstIndex(where: { $0.id == groupID }) {
            exact[idx].keep = url
        }
        if let idx = similar.firstIndex(where: { $0.id == groupID }) {
            similar[idx].keep = url
        }
    }

    public func remove(_ urls: Set<URL>) {
        func prune(_ list: [DuplicateGroup]) -> [DuplicateGroup] {
            list.compactMap { group in
                let remaining = group.files.filter { !urls.contains($0.url) }
                guard remaining.count > 1 else { return nil }
                let keep = remaining.contains(where: { $0.url == group.keep }) ? group.keep : remaining[0].url
                return DuplicateGroup(id: group.id, files: remaining, keep: keep)
            }
        }
        exact = prune(exact)
        similar = prune(similar)
    }
}

// MARK: - Duplicates View

public struct DuplicatesView: View {
    public enum Tab: String, CaseIterable, Identifiable {
        case exact = "Exact Copies"
        case similar = "Similar Photos"
        public var id: String { rawValue }
    }

    @Environment(AppState.self) private var state
    @Environment(LibraryStore.self) private var store
    @Environment(DuplicateFinder.self) private var finder
    @Environment(CleanupStore.self) private var cleanup
    @Environment(TextIndex.self) private var textIndex

    @State private var tab: Tab = .exact
    @State private var confirmAll: Bool = false

    public init() {}

    private var groups: [DuplicateGroup] {
        tab == .exact ? finder.exact : finder.similar
    }

    private var reclaimable: Int64 {
        tab == .exact ? finder.exactReclaimable : finder.similarReclaimable
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                content
            }
            .padding(24)
        }
        .task {
            if finder.phase == .idle {
                await finder.scan(scopes: store.scopes)
            }
        }
        .onChange(of: tab) {
            if tab == .similar && finder.similarPhase == .idle {
                Task { await finder.scanSimilar(scopes: store.scopes) }
            }
        }
        .confirmationDialog(
            "Move all extra copies to the Trash?",
            isPresented: $confirmAll,
            titleVisibility: .visible
        ) {
            Button("Trash All Extras (\(Fmt.bytes(reclaimable)))", role: .destructive) {
                let allExtras = groups.flatMap(\.extras)
                FileActions.trash(allExtras) { removed in
                    finder.remove(removed)
                    store.remove(removed)
                    cleanup.remove(removed)
                    textIndex.forget(removed)
                    state.showToast("Moved \(removed.count) duplicate copies to Trash")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("One copy of each file is kept (marked “Keep”). You can restore anything from the Trash.")
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Duplicates")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(
                    tab == .exact
                        ? "Findy compares file contents with SHA-256, so only true identical copies are matched."
                        : "Spots burst shots, edits and re-saved copies of the same picture, on-device."
                )
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            if !groups.isEmpty {
                Button(role: .destructive) {
                    confirmAll = true
                } label: {
                    Label("Trash All Extras (\(Fmt.bytes(reclaimable)))", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let currentPhase = (tab == .exact) ? finder.phase : finder.similarPhase
        if currentPhase == .gathering || currentPhase == .hashing {
            VStack(spacing: 12) {
                ProgressView()
                Text(tab == .exact ? "Scanning for identical copies…" : "Looking at your photos…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else if groups.isEmpty {
            ContentUnavailableView(
                tab == .exact ? "No duplicates found" : "No look-alike photos",
                systemImage: "checkmark.seal.fill",
                description: Text("Your home folders look nice and tidy!")
            )
            .frame(minHeight: 280)
        } else {
            LazyVStack(spacing: 14) {
                ForEach(groups) { group in
                    DuplicateGroupCard(
                        group: group,
                        isSimilar: tab == .similar,
                        onKeep: { url in finder.setKeeper(url, in: group.id) },
                        onTrash: { extras in
                            FileActions.trash(extras) { removed in
                                finder.remove(removed)
                                store.remove(removed)
                                cleanup.remove(removed)
                                textIndex.forget(removed)
                                state.showToast("Moved \(removed.count) copies to Trash")
                            }
                        }
                    )
                }
            }
        }
    }
}

public struct DuplicateGroupCard: View {
    public let group: DuplicateGroup
    public var isSimilar: Bool
    public let onKeep: (URL) -> Void
    public let onTrash: ([FileItem]) -> Void
    @Environment(AppState.self) private var state

    public init(group: DuplicateGroup, isSimilar: Bool, onKeep: @escaping (URL) -> Void, onTrash: @escaping ([FileItem]) -> Void) {
        self.group = group
        self.isSimilar = isSimilar
        self.onKeep = onKeep
        self.onTrash = onTrash
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(group.files.count) copies · \(Fmt.bytes(group.reclaimableBytes)) can be freed", systemImage: "square.on.square")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Click to keep this copy · double-click to preview")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Button {
                    onTrash(group.extras)
                } label: {
                    Text("Keep 1, Trash \(group.extras.count)")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(group.files) { item in
                        copyTile(item)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    private func copyTile(_ item: FileItem) -> some View {
        let isKeeper = item.url == group.keep
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                ThumbnailView(item: item, cornerRadius: 10)
                    .frame(width: 150, height: 105)
                if isKeeper {
                    Text("Keep")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.green))
                        .padding(6)
                }
            }
            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text(item.url.deletingLastPathComponent().lastPathComponent)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 150)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isKeeper ? Theme.green.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isKeeper ? Theme.green.opacity(0.6) : Theme.line, lineWidth: isKeeper ? 1.5 : 1)
        )
        .onTapGesture(count: 2) {
            state.preview(item, in: group.files)
        }
        .onTapGesture {
            onKeep(item.url)
        }
    }
}
