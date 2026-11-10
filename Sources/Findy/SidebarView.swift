import SwiftUI

// MARK: - Sidebar Row

public struct SidebarRow<LabelContent: View>: View {
    public let isSelected: Bool
    public let action: () -> Void
    @ViewBuilder public let label: () -> LabelContent
    @State private var hovering = false

    public init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> LabelContent) {
        self.isSelected = isSelected
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : (hovering ? Color.primary.opacity(0.05) : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Sidebar View

public struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Environment(LibraryStore.self) private var store
    @Environment(Player.self) private var player
    @Environment(DuplicateFinder.self) private var duplicates
    @Environment(CleanupStore.self) private var cleanup
    @Environment(SourceStore.self) private var sources
    @Environment(FileShelf.self) private var shelf
    @State private var shelfDropTargeted = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Top Traffic-Lights & Brand Header Bar
            HStack(spacing: 8) {
                Spacer()
                    .frame(width: 68)
                FindyLogo(size: 20)
                Text("Findy")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        state.sidebarCollapsed = true
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help("Hide Sidebar")
            }
            .padding(.trailing, 10)
            .frame(height: 48)
            .background(WindowDragArea())

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Primary Navigation
                    VStack(alignment: .leading, spacing: 2) {
                        row(.home, "Home", "house.fill")
                        ForEach(SmartCollection.allCases) { sc in
                            row(.smart(sc), sc.title, sc.symbol, badge: store.collections[.smart(sc)]?.totalCount)
                        }
                        row(
                            .spaceLens,
                            "Space Lens",
                            "chart.pie.fill",
                            detail: "New"
                        )
                        row(
                            .fileShelf,
                            "File Shelf",
                            "tray.full.fill",
                            badge: shelf.items.isEmpty ? nil : shelf.items.count,
                            detail: shelf.items.isEmpty ? "Drop" : nil
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(shelfDropTargeted ? Color.accentColor : .clear, lineWidth: 1.5)
                        )
                        .onDrop(of: [.fileURL], isTargeted: $shelfDropTargeted) { providers in
                            for provider in providers {
                                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                                    if let d = data as? Data, let url = URL(dataRepresentation: d, relativeTo: nil) {
                                        Task { @MainActor in
                                            shelf.addURLs([url])
                                            state.showToast("Added \(url.lastPathComponent) to File Shelf", symbol: "tray.and.arrow.down.fill")
                                        }
                                    }
                                }
                            }
                            return true
                        }
                        row(
                            .cleanupHub,
                            "Clean Up",
                            "sparkles",
                            detail: cleanup.totalReclaimable > 0 ? Fmt.bytes(cleanup.totalReclaimable) : nil
                        )
                        row(
                            .duplicates,
                            "Duplicates",
                            "square.on.square",
                            badge: duplicates.extraCopies > 0 ? duplicates.extraCopies : nil
                        )
                        row(
                            .sources,
                            "Downloaded From",
                            "arrow.down.circle",
                            badge: sources.groups.isEmpty ? nil : sources.groups.count
                        )
                    }

                    // Saved Searches
                    SavedSearchesSection()

                    // Categories
                    VStack(alignment: .leading, spacing: 2) {
                        heading("Categories")
                        ForEach(FileCategory.allCases) { cat in
                            row(
                                .category(cat),
                                cat.title,
                                cat.symbol,
                                badge: store.collections[.category(cat)]?.totalCount,
                                tint: cat.tint
                            )
                        }
                    }

                    // Favourites (Pinned)
                    if !state.pinned.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            heading("Favourites")
                            ForEach(state.pinned, id: \.self) { url in
                                folderRow(Location(url: url, title: url.lastPathComponent, symbol: "star.fill"), starred: true)
                            }
                        }
                    }

                    // Standard Locations
                    VStack(alignment: .leading, spacing: 2) {
                        heading("Locations")
                        ForEach(Location.standard) { loc in
                            folderRow(loc, starred: false)
                        }
                    }

                    // Finder Color Tags
                    VStack(alignment: .leading, spacing: 2) {
                        heading("Finder Tags")
                        ForEach(FinderTag.allCases) { tag in
                            SidebarRow(isSelected: isSelected(.tag(tag))) {
                                state.searchText = ""
                                state.selection = .tag(tag)
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(tag.color)
                                        .frame(width: 9, height: 9)
                                    Text(tag.rawValue)
                                        .font(.system(size: 12.5, weight: isSelected(.tag(tag)) ? .semibold : .regular))
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }

            if player.current != nil {
                Divider()
                MiniPlayer()
            }
        }
        .frame(width: 225)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
    }

    private func isSelected(_ item: SidebarItem) -> Bool {
        !state.isSearching && state.selection == item
    }

    private func row(
        _ item: SidebarItem,
        _ title: String,
        _ symbol: String,
        badge: Int? = nil,
        detail: String? = nil,
        tint: Color = .accentColor
    ) -> some View {
        let selected = isSelected(item)
        return SidebarRow(isSelected: selected) {
            state.searchText = ""
            state.selection = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : tint)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.green)
                } else if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func folderRow(_ loc: Location, starred: Bool) -> some View {
        let item = SidebarItem.location(loc)
        let selected = isSelected(item)
        return SidebarRow(isSelected: selected) {
            state.searchText = ""
            state.selection = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: loc.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(starred ? Theme.star : (selected ? Color.accentColor : .secondary))
                    .frame(width: 18)
                Text(loc.title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
            }
        }
        .contextMenu {
            if starred {
                Button("Remove from Sidebar") {
                    state.togglePin(loc.url)
                }
            } else {
                Button("Pin to Favourites") {
                    state.togglePin(loc.url)
                }
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([loc.url])
            }
        }
    }
}
