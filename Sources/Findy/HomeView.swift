import SwiftUI
import AppKit

// MARK: - Spotlight Health Banner

public struct SpotlightBanner: View {
    public let health: SpotlightHealth
    public let refresh: () -> Void

    public init(health: SpotlightHealth, refresh: @escaping () -> Void) {
        self.health = health
        self.refresh = refresh
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(health == .disabled ? "Spotlight indexing is turned off" : "Spotlight isn't returning any files")
                        .font(.system(size: 14, weight: .bold))
                    Text("Findy finds your files through Spotlight, and also includes an instant on-disk fallback scanner.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Spotlight Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Spotlight-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                Button("Copy Terminal Fix") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("sudo mdutil -i on / && sudo mdutil -E /", forType: .string)
                }
                .buttonStyle(.bordered)
                Button("Refresh", action: refresh)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Horizontal Shelf

public struct Shelf: View {
    public let title: String
    public let item: SidebarItem
    @Environment(AppState.self) private var state
    @Environment(LibraryStore.self) private var store
    @Environment(Player.self) private var player

    public init(title: String, item: SidebarItem) {
        self.title = title
        self.item = item
    }

    public var body: some View {
        let res = store.collections[item]
        let files = res?.items ?? []

        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title, count: res?.totalCount, loading: store.loading.contains(item))
                    Button("See All") {
                        state.selection = item
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(files.prefix(12)) { file in
                            GalleryCard(
                                item: file,
                                list: files,
                                isSelected: state.selectedFiles.contains(file.url),
                                isPlaying: player.current?.url == file.url && player.isPlaying
                            )
                            .environment(\.cardSize, .small)
                            .frame(width: 165)
                            .modifier(FileInteractions(item: file, list: files))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Home View

public struct HomeView: View {
    @Environment(AppState.self) private var state
    @Environment(LibraryStore.self) private var store
    @Environment(CleanupStore.self) private var cleanup
    @Environment(SourceStore.self) private var sources

    public init() {}

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var summaryLine: String {
        let totalFiles = FileCategory.allCases.reduce(0) { $0 + (store.collections[.category($1)]?.totalCount ?? 0) }
        let totalBytes = FileCategory.allCases.reduce(Int64(0)) { $0 + (store.collections[.category($1)]?.totalSize ?? 0) }
        if totalFiles == 0 {
            return "Taking stock of everything on your Mac…"
        }
        return "\(Fmt.plural(totalFiles, "file")) · \(Fmt.bytes(totalBytes)) across your Mac"
    }

    private var folders: [Location] {
        var list = Location.standard
        let stdSet = Set(list.map(\.url.standardizedFileURL))
        for pinnedURL in state.pinned where !stdSet.contains(pinnedURL.standardizedFileURL) {
            list.append(Location(url: pinnedURL, title: pinnedURL.lastPathComponent, symbol: "folder.fill"))
        }
        return list
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                // Hero Greeting + Quick Space Lens Button
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(summaryLine)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        state.selection = .spaceLens
                    } label: {
                        Label("Space Lens", systemImage: "chart.pie.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }

                if store.spotlightHealth == .disabled || store.spotlightHealth == .empty {
                    SpotlightBanner(health: store.spotlightHealth) {
                        state.refreshToken += 1
                    }
                }

                // Categories Grid
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Categories")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                        ForEach(FileCategory.allCases) { cat in
                            let res = store.collections[.category(cat)]
                            Button {
                                state.selection = .category(cat)
                            } label: {
                                CategoryTile(
                                    category: cat,
                                    count: res?.totalCount,
                                    size: res?.totalSize
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Folders Grid
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Locations", count: folders.count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 12)], spacing: 12) {
                        ForEach(folders) { loc in
                            Button {
                                state.selection = .location(loc)
                            } label: {
                                FolderItemCard(url: loc.url, title: loc.title)
                            }
                            .buttonStyle(.plain)
                        }
                        AddFolderCard(action: pickFolder)
                    }
                }

                // Clean Up Section
                CleanupSection(showsHeader: true)

                // Downloaded From Section
                SourcesSection(limit: 6)

                // Shelves
                Shelf(title: "Recent Files", item: .smart(.recents))
                Shelf(title: "Screenshots", item: .smart(.screenshots))
                Shelf(title: "Large Files", item: .smart(.large))
                Shelf(title: "Recent Photos", item: .category(.images))
                Shelf(title: "Recent Videos", item: .category(.videos))
            }
            .padding(24)
        }
        .task(id: state.refreshToken) {
            let token = state.refreshToken
            await withTaskGroup(of: Void.self) { group in
                for sc in SmartCollection.allCases {
                    group.addTask { @MainActor in
                        await store.load(.smart(sc), token: token)
                    }
                }
                for cat in FileCategory.allCases {
                    group.addTask { @MainActor in
                        await store.load(.category(cat), token: token)
                    }
                }
                group.addTask { @MainActor in
                    await cleanup.load(scopes: store.scopes, token: token)
                }
                group.addTask { @MainActor in
                    await sources.load(scopes: store.scopes, token: token)
                }
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Pin to Sidebar"
        if panel.runModal() == .OK, let url = panel.url {
            if !state.pinned.contains(url) {
                state.pinned.append(url)
            }
            state.openFolder(url)
        }
    }
}
