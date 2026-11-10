import SwiftUI
import AppKit

// MARK: - Understood Chips & Filter Bar

public struct UnderstoodChips: View {
    public let chips: [String]

    public init(chips: [String]) {
        self.chips = chips
    }

    public var body: some View {
        if !chips.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Understood as")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
                Spacer()
            }
        }
    }
}

public struct FilterBar: View {
    public var showsKindFilter: Bool
    public var kinds: [FileCategory: Int]
    public var sources: [(String, Int)]
    @Environment(AppState.self) private var state

    public init(showsKindFilter: Bool, kinds: [FileCategory: Int], sources: [(String, Int)]) {
        self.showsKindFilter = showsKindFilter
        self.kinds = kinds
        self.sources = sources
    }

    public var body: some View {
        HStack(spacing: 8) {
            if !sources.isEmpty {
                FilterPill(
                    label: "Source",
                    value: state.sourceFilter,
                    active: state.sourceFilter != nil
                ) {
                    Button("All Sources") { state.sourceFilter = nil }
                    Divider()
                    ForEach(sources.prefix(12), id: \.0) { name, cnt in
                        Button("\(name) (\(cnt))") {
                            state.sourceFilter = name
                        }
                    }
                }
            }

            if showsKindFilter && kinds.count > 1 {
                FilterPill(
                    label: "Kind",
                    value: state.kindFilter?.title,
                    active: state.kindFilter != nil
                ) {
                    Button("All Kinds") { state.kindFilter = nil }
                    Divider()
                    ForEach(FileCategory.allCases) { cat in
                        if let cnt = kinds[cat], cnt > 0 {
                            Button("\(cat.title) (\(cnt))") {
                                state.kindFilter = cat
                            }
                        }
                    }
                }
            }

            FilterPill(
                label: "Date",
                value: state.dateFilter == .any ? nil : state.dateFilter.title,
                active: state.dateFilter != .any
            ) {
                ForEach(DateFilter.allCases) { df in
                    Button(df.title) { state.dateFilter = df }
                }
            }

            FilterPill(
                label: "Size",
                value: state.sizeFilter == .any ? nil : state.sizeFilter.title,
                active: state.sizeFilter != .any
            ) {
                ForEach(SizeFilter.allCases) { sf in
                    Button(sf.title) { state.sizeFilter = sf }
                }
            }

            FilterPill(
                label: "Tag",
                value: state.tagFilter?.rawValue,
                active: state.tagFilter != nil
            ) {
                Button("Any Tag") { state.tagFilter = nil }
                Divider()
                ForEach(FinderTag.allCases) { tag in
                    Button(tag.rawValue) { state.tagFilter = tag }
                }
            }

            FilterPill(
                label: "Sort",
                value: "\(state.sortKey.title) \(state.ascending ? "↑" : "↓")",
                active: false
            ) {
                ForEach(SortKey.allCases) { key in
                    Button {
                        state.setSort(key)
                    } label: {
                        HStack {
                            Text(key.title)
                            if state.sortKey == key {
                                Image(systemName: state.ascending ? "arrow.up" : "arrow.down")
                            }
                        }
                    }
                }
            }

            if state.filtersActive {
                Button("Reset") {
                    state.kindFilter = nil
                    state.dateFilter = .any
                    state.sizeFilter = .any
                    state.sourceFilter = nil
                    state.tagFilter = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            }

            Spacer()

            SelectToggle()
            ViewModeToggle()
        }
    }
}

public struct SelectToggle: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        Button {
            if state.isSelecting {
                state.clearSelection()
            } else {
                state.isSelecting = true
            }
        } label: {
            Image(systemName: state.isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(state.isSelecting ? Color.accentColor : .secondary)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(state.isSelecting ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .help(state.isSelecting ? "Stop selecting (Esc)" : "Select multiple files")
    }
}

public struct ViewModeToggle: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        HStack(spacing: 2) {
            button(.grid, "square.grid.2x2")
            button(.list, "list.bullet")
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }

    private func button(_ mode: ViewMode, _ symbol: String) -> some View {
        let active = state.viewMode == mode
        return Button {
            state.viewMode = mode
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? .primary : .secondary)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? Color(nsColor: .controlBackgroundColor) : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Selection Bar

public struct SelectionBar: View {
    public let visible: [FileItem]
    public let onTrash: ([FileItem]) -> Void
    @Environment(AppState.self) private var state
    @Environment(FileShelf.self) private var shelf

    public init(visible: [FileItem], onTrash: @escaping ([FileItem]) -> Void) {
        self.visible = visible
        self.onTrash = onTrash
    }

    public var body: some View {
        let selectedItems = visible.filter { state.selectedFiles.contains($0.url) }
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(selectedItems.isEmpty ? "Click files to add them" : "\(Fmt.plural(selectedItems.count, "item")) selected (\(Fmt.bytes(selectedItems.reduce(0) { $0 + $1.size })))")
                .font(.system(size: 12.5, weight: .semibold))

            Spacer()

            Button(selectedItems.count == visible.count ? "Deselect All" : "Select All") {
                if selectedItems.count == visible.count {
                    state.selectedFiles.removeAll()
                } else {
                    state.selectAll(visible)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if !selectedItems.isEmpty {
                Button {
                    shelf.add(selectedItems)
                    state.showToast("Added \(Fmt.plural(selectedItems.count, "item")) to File Shelf", symbol: "tray.and.arrow.down.fill")
                } label: {
                    Label("Add to Shelf", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    do {
                        let zipURL = try FileActions.createZipArchive(from: selectedItems)
                        state.refreshToken += 1
                        state.showToast("Created \(zipURL.lastPathComponent)", symbol: "doc.zipper")
                    } catch {
                        state.showToast("Archive failed: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
                    }
                } label: {
                    Label("Create .zip", systemImage: "doc.zipper")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if selectedItems.count > 1 {
                Button {
                    state.showBatchRename = true
                } label: {
                    Label("Batch Rename…", systemImage: "pencil.and.list.clipboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !selectedItems.isEmpty {
                Button(role: .destructive) {
                    onTrash(selectedItems)
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }

            Button("Done (Esc)") {
                state.clearSelection()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }
}

// MARK: - Browser Header & File Browser

public struct BrowserHeader<Accessory: View>: View {
    public let title: String
    public var subtitle: String?
    public var onBack: (() -> Void)?
    public var showsKindFilter: Bool
    public var kinds: [FileCategory: Int]
    public var sources: [(String, Int)]
    @ViewBuilder public let accessory: () -> Accessory

    public init(
        title: String,
        subtitle: String?,
        onBack: (() -> Void)?,
        showsKindFilter: Bool,
        kinds: [FileCategory: Int],
        sources: [(String, Int)],
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.showsKindFilter = showsKindFilter
        self.kinds = kinds
        self.sources = sources
        self.accessory = accessory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                accessory()
            }

            FilterBar(showsKindFilter: showsKindFilter, kinds: kinds, sources: sources)
        }
    }
}

public struct FileBrowser<Accessory: View>: View {
    public let title: String
    public var subtitle: String?
    public let items: [FileItem]
    public var isLoading: Bool = false
    public var totalCount: Int?
    public var showsKindFilter: Bool = true
    public var emptyTitle: String = "No files found"
    public var emptySymbol: String = "folder"
    public var emptyMessage: String = "There are no matching files."
    public var onBack: (() -> Void)?
    public var chips: [String] = []
    @ViewBuilder public var accessory: () -> Accessory

    @Environment(AppState.self) private var state
    @Environment(LibraryStore.self) private var store
    @Environment(Player.self) private var player
    @Environment(CleanupStore.self) private var cleanup
    @Environment(DuplicateFinder.self) private var duplicates
    @Environment(SourceStore.self) private var sources
    @Environment(TextIndex.self) private var textIndex

    public init(
        title: String,
        subtitle: String? = nil,
        items: [FileItem],
        isLoading: Bool = false,
        totalCount: Int? = nil,
        showsKindFilter: Bool = true,
        emptyTitle: String = "No files found",
        emptySymbol: String = "folder",
        emptyMessage: String = "There are no matching files.",
        onBack: (() -> Void)? = nil,
        chips: [String] = [],
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.isLoading = isLoading
        self.totalCount = totalCount
        self.showsKindFilter = showsKindFilter
        self.emptyTitle = emptyTitle
        self.emptySymbol = emptySymbol
        self.emptyMessage = emptyMessage
        self.onBack = onBack
        self.chips = chips
        self.accessory = accessory
    }

    private var kindCounts: [FileCategory: Int] {
        var counts: [FileCategory: Int] = [:]
        for item in items { counts[item.category, default: 0] += 1 }
        return counts
    }

    private var sourceCounts: [(String, Int)] {
        var counts: [String: Int] = [:]
        for item in items.prefix(300) {
            if let s = DownloadSources.source(for: item.url) {
                counts[s.name, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }
    }

    public var body: some View {
        let filtered = state.sort(state.applyFilters(items), foldersFirst: true)
        let folders = filtered.filter { $0.category == .folders }
        let files = filtered.filter { $0.category != .folders }

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    BrowserHeader(
                        title: title,
                        subtitle: subtitle,
                        onBack: onBack,
                        showsKindFilter: showsKindFilter,
                        kinds: kindCounts,
                        sources: sourceCounts,
                        accessory: accessory
                    )

                    if !chips.isEmpty {
                        UnderstoodChips(chips: chips)
                    }

                    if isLoading && items.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking through your Mac…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                    } else if filtered.isEmpty {
                        ContentUnavailableView(
                            state.filtersActive ? "No files match these filters" : emptyTitle,
                            systemImage: state.filtersActive ? "line.3.horizontal.decrease.circle" : emptySymbol,
                            description: Text(state.filtersActive ? "Try loosening the filters." : emptyMessage)
                        )
                        .frame(minHeight: 280)
                    } else {
                        if !folders.isEmpty && state.viewMode == .grid {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionTitle("Folders", count: folders.count)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 12)], spacing: 12) {
                                    ForEach(folders) { folder in
                                        FolderItemCard(
                                            url: folder.url,
                                            title: folder.displayTitle,
                                            isSelected: state.selectedFiles.contains(folder.url),
                                            list: filtered,
                                            item: folder
                                        )
                                        .modifier(FileInteractions(item: folder, list: filtered))
                                    }
                                }
                            }
                        }

                        let visibleFiles = (state.viewMode == .grid) ? files : filtered
                        if !visibleFiles.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                if !folders.isEmpty && state.viewMode == .grid {
                                    SectionTitle("Files", count: visibleFiles.count)
                                }
                                if state.viewMode == .grid {
                                    LazyVGrid(
                                        columns: [GridItem(.adaptive(minimum: state.cardSize.minWidth), spacing: 14)],
                                        spacing: 14
                                    ) {
                                        ForEach(visibleFiles) { item in
                                            GalleryCard(
                                                item: item,
                                                list: visibleFiles,
                                                isSelected: state.selectedFiles.contains(item.url),
                                                isPlaying: player.current?.url == item.url && player.isPlaying
                                            )
                                            .modifier(FileInteractions(item: item, list: visibleFiles))
                                        }
                                    }
                                } else {
                                    LazyVStack(spacing: 2) {
                                        ForEach(visibleFiles) { item in
                                            FileRow(
                                                item: item,
                                                isSelected: state.selectedFiles.contains(item.url),
                                                isPlaying: player.current?.url == item.url && player.isPlaying
                                            )
                                            .modifier(FileInteractions(item: item, list: visibleFiles))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, (state.isSelecting || state.selectedFiles.count > 1) ? 70 : 0)
            }

            if state.isSelecting || state.selectedFiles.count > 1 {
                SelectionBar(visible: filtered) { toTrash in
                    FileActions.trash(toTrash) { removed in
                        store.remove(removed)
                        cleanup.remove(removed)
                        duplicates.remove(removed)
                        sources.remove(removed)
                        FileShelf.shared.remove(removed)
                        textIndex.forget(removed)
                        state.clearSelection()
                        state.refreshToken += 1
                        state.showToast("Moved \(removed.count) items to Trash")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Detail, Folder, Collection & Search Views

public struct CollectionView: View {
    public let item: SidebarItem
    @Environment(AppState.self) private var state
    @Environment(LibraryStore.self) private var store
    @Environment(TextIndex.self) private var textIndex

    public init(item: SidebarItem) {
        self.item = item
    }

    public var body: some View {
        let res = store.collections[item]
        let items = res?.items ?? []
        let loading = store.loading.contains(item)

        FileBrowser(
            title: item.title,
            subtitle: res.map { "\(Fmt.plural($0.totalCount, "item")) · \(Fmt.bytes($0.totalSize))" },
            items: items,
            isLoading: loading,
            totalCount: res?.totalCount,
            showsKindFilter: {
                if case .category = item { return false }
                return true
            }(),
            emptyTitle: "Findy couldn't find any \(item.title.lowercased()) in your home folders.",
            emptySymbol: "magnifyingglass"
        )
        .task(id: "\(item.title)#\(state.refreshToken)") {
            await store.load(item, token: state.refreshToken)
            if let loaded = store.collections[item]?.items {
                textIndex.index(Array(loaded.prefix(30)))
            }
        }
    }
}

public struct FolderView: View {
    public let location: Location
    @Environment(AppState.self) private var state
    @State private var items: [FileItem] = []
    @State private var loading: Bool = false
    @State private var error: String?

    public init(location: Location) {
        self.location = location
    }

    private var current: URL {
        state.folderPath.last ?? location.url
    }

    public var body: some View {
        FileBrowser(
            title: current.lastPathComponent,
            subtitle: Fmt.displayPath(current),
            items: items,
            isLoading: loading,
            totalCount: items.count,
            showsKindFilter: true,
            emptyTitle: error != nil ? "Can't Open Folder" : "There's nothing in this folder yet.",
            emptySymbol: error != nil ? "lock.fill" : "folder",
            emptyMessage: error ?? "Drop files into this folder in Finder and they'll appear here.",
            onBack: state.folderPath.isEmpty ? nil : {
                _ = state.folderPath.popLast()
            },
            accessory: {
                HStack(spacing: 8) {
                    Button {
                        let newFolderURL = FileShelf.uniqueDestinationURL(for: "Untitled Folder", in: current)
                        do {
                            try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: false)
                            state.refreshToken += 1
                            state.showToast("Created \(newFolderURL.lastPathComponent)", symbol: "folder.badge.plus")
                        } catch {
                            state.showToast("Could not create folder", symbol: "exclamationmark.triangle.fill")
                        }
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([current])
                    } label: {
                        Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        )
        .task(id: "\(current.path)#\(state.refreshToken)") {
            loading = true
            error = nil
            do {
                items = try await LibraryStore.listFolder(current)
            } catch {
                items = []
                self.error = "Findy doesn't have permission to read “\(current.lastPathComponent)”. Allow access in System Settings › Privacy & Security › Files and Folders."
            }
            loading = false
        }
    }
}

public struct SearchView: View {
    @Environment(AppState.self) private var state
    @Environment(LibraryStore.self) private var store
    @Environment(TextIndex.self) private var textIndex

    public init() {}

    public var body: some View {
        let items = store.searchResult?.items ?? []
        let chips = store.parsedQuery?.chips ?? []
        let ocrHits = store.textMatchCount
        let sub: String = {
            if store.isSearching { return "Searching across your Mac…" }
            var s = "\(Fmt.plural(items.count, "result")) in your home folders"
            if ocrHits > 0 {
                s += " · \(ocrHits) found by text inside images"
            }
            return s
        }()

        FileBrowser(
            title: "“\(state.searchText)”",
            subtitle: sub,
            items: items,
            isLoading: store.isSearching,
            totalCount: items.count,
            showsKindFilter: true,
            emptyTitle: "Nothing in your home folders matches “\(state.searchText)”",
            emptySymbol: "magnifyingglass",
            emptyMessage: "Try plain words like “pdfs from last week”, “screenshots over 5 mb”, or “tagged red”.",
            chips: chips,
            accessory: {
                SaveSearchButton()
            }
        )
    }
}

public struct DetailView: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        if state.isSearching {
            SearchView()
        } else {
            switch state.selection ?? .home {
            case .home:
                HomeView()
            case .smart, .category, .tag:
                CollectionView(item: state.selection ?? .home)
            case .location(let loc):
                FolderView(location: loc)
            case .cleanupHub:
                CleanupHubView()
            case .cleanup(let kind):
                CleanupReviewView(kind: kind)
            case .duplicates:
                DuplicatesView()
            case .sources:
                SourcesHubView()
            case .source(let name):
                SourceView(name: name)
            case .spaceLens:
                SpaceLensView()
            case .fileShelf:
                FileShelfView()
            }
        }
    }
}
