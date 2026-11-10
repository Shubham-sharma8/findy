import Foundation
import SwiftUI

// MARK: - Space Lens Visual Storage Analyzer (Improved Feature)

public struct SpaceLensSlice: Identifiable, Equatable, Sendable {
    public let category: FileCategory
    public let bytes: Int64
    public let count: Int
    public let fraction: Double

    public var id: FileCategory { category }

    public init(category: FileCategory, bytes: Int64, count: Int, fraction: Double) {
        self.category = category
        self.bytes = bytes
        self.count = count
        self.fraction = fraction
    }
}

public struct SpaceLensFolderSlice: Identifiable, Equatable, Sendable {
    public let folderName: String
    public let folderURL: URL
    public let bytes: Int64
    public let count: Int
    public let fraction: Double

    public var id: String { folderName }

    public init(folderName: String, folderURL: URL, bytes: Int64, count: Int, fraction: Double) {
        self.folderName = folderName
        self.folderURL = folderURL
        self.bytes = bytes
        self.count = count
        self.fraction = fraction
    }
}

public struct SpaceLensSummary: Equatable, Sendable {
    public let totalBytes: Int64
    public let categorySlices: [SpaceLensSlice]
    public let folderSlices: [SpaceLensFolderSlice]
    public let largestFiles: [FileItem]

    public init(
        totalBytes: Int64,
        categorySlices: [SpaceLensSlice],
        folderSlices: [SpaceLensFolderSlice] = [],
        largestFiles: [FileItem]
    ) {
        self.totalBytes = totalBytes
        self.categorySlices = categorySlices
        self.folderSlices = folderSlices
        self.largestFiles = largestFiles
    }
}

public enum SpaceLensAnalyzer {
    private static let knownHomeRoots: Set<String> = [
        "Downloads", "Desktop", "Documents", "Pictures", "Movies", "Music", "Applications"
    ]

    public static func analyze(items: [FileItem]) -> SpaceLensSummary {
        var bytesByCategory: [FileCategory: Int64] = [:]
        var countByCategory: [FileCategory: Int] = [:]
        var bytesByFolder: [String: (url: URL, bytes: Int64, count: Int)] = [:]
        var total: Int64 = 0

        for item in items where item.category != .folders {
            bytesByCategory[item.category, default: 0] += item.size
            countByCategory[item.category, default: 0] += 1
            total += item.size

            let (fName, fURL) = topFolderBucket(for: item.url)
            var entry = bytesByFolder[fName] ?? (url: fURL, bytes: 0, count: 0)
            entry.bytes += item.size
            entry.count += 1
            bytesByFolder[fName] = entry
        }

        let denom = Double(max(1, total))
        let slices = FileCategory.allCases.compactMap { cat -> SpaceLensSlice? in
            guard let b = bytesByCategory[cat], b > 0 else { return nil }
            let c = countByCategory[cat] ?? 0
            return SpaceLensSlice(category: cat, bytes: b, count: c, fraction: Double(b) / denom)
        }
        .sorted { $0.bytes > $1.bytes }

        let folderSlices = bytesByFolder.map { name, info in
            SpaceLensFolderSlice(
                folderName: name,
                folderURL: info.url,
                bytes: info.bytes,
                count: info.count,
                fraction: Double(info.bytes) / denom
            )
        }
        .sorted { $0.bytes > $1.bytes }

        let topFiles = items
            .filter { $0.category != .folders }
            .sorted { $0.size > $1.size }
            .prefix(25)
            .map { $0 }

        return SpaceLensSummary(
            totalBytes: total,
            categorySlices: slices,
            folderSlices: folderSlices,
            largestFiles: topFiles
        )
    }

    private static func topFolderBucket(for url: URL) -> (String, URL) {
        let components = url.standardizedFileURL.pathComponents
        for (idx, comp) in components.enumerated() where knownHomeRoots.contains(comp) {
            let bucketPath = NSString.path(withComponents: Array(components.prefix(idx + 1)))
            return (comp, URL(fileURLWithPath: bucketPath))
        }
        if url.path.contains("com~apple~CloudDocs") {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return ("iCloud Drive", home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"))
        }
        let parent = url.deletingLastPathComponent()
        return (parent.lastPathComponent, parent)
    }
}

// MARK: - Space Lens Interactive View

public struct SpaceLensView: View {
    @Environment(AppState.self) private var state
    @Environment(LibraryStore.self) private var store
    @State private var selectedCategory: FileCategory?

    public init() {}

    private var allItems: [FileItem] {
        var seen = Set<URL>()
        var combined: [FileItem] = []
        for cat in FileCategory.allCases where cat != .folders {
            if let items = store.collections[.category(cat)]?.items {
                for item in items where !seen.contains(item.url) {
                    seen.insert(item.url)
                    combined.append(item)
                }
            }
        }
        if let large = store.collections[.smart(.large)]?.items {
            for item in large where !seen.contains(item.url) {
                seen.insert(item.url)
                combined.append(item)
            }
        }
        return combined
    }

    public var body: some View {
        let summary = SpaceLensAnalyzer.analyze(items: allItems)
        let displayedFiles: [FileItem] = {
            if let selectedCategory {
                return allItems.filter { $0.category == selectedCategory }.sorted { $0.size > $1.size }
            }
            return summary.largestFiles
        }()

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.pie.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                            Text("Space Lens")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                        }
                        Text("Visual storage breakdown across your indexed home folders (\(Fmt.bytes(summary.totalBytes)) analyzed)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedCategory != nil {
                        Button("Show All Categories") {
                            selectedCategory = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Proportional Treemap / Storage Bar
                VStack(alignment: .leading, spacing: 12) {
                    GeometryReader { geo in
                        let spacingTotal = CGFloat(max(0, summary.categorySlices.count - 1)) * 3
                        let availableW = max(1, geo.size.width - spacingTotal)
                        HStack(spacing: 3) {
                            ForEach(summary.categorySlices) { slice in
                                let width = max(8, availableW * slice.fraction)
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: slice.category.gradient,
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: width)
                                    .opacity(selectedCategory == nil || selectedCategory == slice.category ? 1.0 : 0.35)
                                    .onTapGesture {
                                        if selectedCategory == slice.category {
                                            selectedCategory = nil
                                        } else {
                                            selectedCategory = slice.category
                                        }
                                    }
                                    .help("\(slice.category.title): \(Fmt.bytes(slice.bytes))")
                            }
                        }
                    }
                    .frame(height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // Category Legend Cards
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 10)], spacing: 10) {
                        ForEach(summary.categorySlices) { slice in
                            let active = selectedCategory == slice.category
                            Button {
                                selectedCategory = active ? nil : slice.category
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(slice.category.tint)
                                        .frame(width: 10, height: 10)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(slice.category.title)
                                            .font(.system(size: 12.5, weight: .semibold))
                                        Text("\(Fmt.bytes(slice.bytes)) · \(Int((slice.fraction * 100).rounded()))%")
                                            .font(Theme.mono(11))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(active ? slice.category.tint.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(active ? slice.category.tint : Theme.line, lineWidth: active ? 1.5 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )

                // Storage by Home Folder Breakdown
                if !summary.folderSlices.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Storage by Home Folder", count: summary.folderSlices.count)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                            ForEach(summary.folderSlices.prefix(8)) { folder in
                                Button {
                                    state.openFolder(folder.folderURL)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(folder.folderName)
                                                .font(.system(size: 13, weight: .semibold))
                                                .lineLimit(1)
                                            Text("\(Fmt.bytes(folder.bytes)) · \(Fmt.plural(folder.count, "file"))")
                                                .font(Theme.mono(11))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(Int((folder.fraction * 100).rounded()))%")
                                            .font(Theme.mono(11, .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color(nsColor: .controlBackgroundColor))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Theme.line, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Click to open \(folder.folderName)")
                            }
                        }
                    }
                }

                // Top Largest Files Section
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(
                        selectedCategory.map { "Largest \($0.title)" } ?? "Largest Files Across Your Mac",
                        count: displayedFiles.count
                    )

                    LazyVStack(spacing: 4) {
                        ForEach(displayedFiles.prefix(30)) { item in
                            FileRow(
                                item: item,
                                isSelected: state.selectedFiles.contains(item.url),
                                isPlaying: false
                            )
                            .modifier(FileInteractions(item: item, list: displayedFiles))
                        }
                    }
                }
            }
            .padding(24)
        }
        .task(id: state.refreshToken) {
            let token = state.refreshToken
            var itemsToLoad: [SidebarItem] = [.smart(.large)]
            itemsToLoad.append(contentsOf: FileCategory.allCases.filter { $0 != .folders }.map { .category($0) })
            await withTaskGroup(of: Void.self) { group in
                for target in itemsToLoad {
                    group.addTask { @MainActor in
                        await store.load(target, token: token)
                    }
                }
            }
        }
    }
}
