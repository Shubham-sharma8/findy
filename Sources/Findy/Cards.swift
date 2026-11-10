import SwiftUI
import AppKit

// MARK: - Selection Checkbox

public struct SelectionCheckbox: View {
    public let item: FileItem
    public let isSelected: Bool
    @Environment(AppState.self) private var state

    public init(item: FileItem, isSelected: Bool) {
        self.item = item
        self.isSelected = isSelected
    }

    public var body: some View {
        Button {
            if state.selectedFiles.contains(item.url) {
                state.selectedFiles.remove(item.url)
                if state.selectedFiles.isEmpty {
                    state.isSelecting = false
                }
            } else {
                state.selectedFiles.insert(item.url)
                state.isSelecting = true
            }
            state.focusedItem = item
            state.selectionAnchor = item.url
        } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.9))
                .background(
                    Circle()
                        .fill(isSelected ? Color.white : Color.black.opacity(0.35))
                        .frame(width: 18, height: 18)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                state.hoveredCheckbox = item.url
            } else if state.hoveredCheckbox == item.url {
                state.hoveredCheckbox = nil
            }
        }
    }
}

// MARK: - Gallery Card (Grid View)

public struct GalleryCard: View {
    public let item: FileItem
    public let list: [FileItem]
    public var isSelected: Bool
    public var isPlaying: Bool
    @Environment(AppState.self) private var state
    @Environment(\.cardSize) private var envCardSize
    @State private var hovering = false

    public init(item: FileItem, list: [FileItem], isSelected: Bool, isPlaying: Bool = false) {
        self.item = item
        self.list = list
        self.isSelected = isSelected
        self.isPlaying = isPlaying
    }

    private var activeSize: CardSize {
        envCardSize ?? state.cardSize
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                FitThumbnail(item: item, isPlaying: isPlaying, hovering: hovering)
                    .frame(height: activeSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Theme.line,
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )

                if hovering || isSelected || state.isSelecting {
                    SelectionCheckbox(item: item, isSelected: isSelected)
                        .padding(8)
                }

                // Tag or Duration badge
                VStack {
                    Spacer()
                    HStack {
                        if !item.tags.isEmpty {
                            HStack(spacing: 3) {
                                ForEach(item.tags.prefix(3), id: \.self) { tName in
                                    if let fTag = FinderTag.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(tName) == .orderedSame }) {
                                        Circle()
                                            .fill(fTag.color)
                                            .frame(width: 8, height: 8)
                                    }
                                }
                            }
                            .padding(5)
                            .background(Capsule().fill(.ultraThinMaterial))
                        }
                        Spacer()
                        if let duration = item.duration, duration > 0 {
                            Text(Fmt.duration(duration))
                                .font(Theme.mono(10, .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.black.opacity(0.65)))
                        }
                    }
                    .padding(7)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(item.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : (hovering ? Color.primary.opacity(0.04) : .clear))
        )
        .onHover { hovering = $0 }
    }
}

// MARK: - File Row (List View)

public struct FileRow: View {
    public let item: FileItem
    public var isSelected: Bool
    public var isPlaying: Bool
    @Environment(AppState.self) private var state
    @State private var hovering = false

    public init(item: FileItem, isSelected: Bool, isPlaying: Bool = false) {
        self.item = item
        self.isSelected = isSelected
        self.isPlaying = isPlaying
    }

    public var body: some View {
        HStack(spacing: 12) {
            if state.isSelecting || isSelected || hovering {
                SelectionCheckbox(item: item, isSelected: isSelected)
                    .frame(width: 22)
            } else {
                Color.clear.frame(width: 22)
            }

            ThumbnailView(item: item, cornerRadius: 6)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    ForEach(item.tags.prefix(3), id: \.self) { tName in
                        if let fTag = FinderTag.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(tName) == .orderedSame }) {
                            Circle()
                                .fill(fTag.color)
                                .frame(width: 7, height: 7)
                        }
                    }
                }
                Text(Fmt.displayPath(item.url.deletingLastPathComponent()))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let src = DownloadSources.source(for: item.url) {
                SourceBadge(source: src, size: 10.5)
            }

            Text(item.kindDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(Fmt.date(item.modified))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 95, alignment: .trailing)

            Text(item.sizeText)
                .font(Theme.mono(11))
                .foregroundStyle(.secondary)
                .frame(width: 75, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : (hovering ? Color.primary.opacity(0.04) : .clear))
        )
        .onHover { hovering = $0 }
    }
}

// MARK: - Folder Cards

public struct FolderCard<MenuContent: View>: View {
    public let title: String
    public let tint: Color
    public var count: Int?
    public var detail: String?
    public var previews: [FileItem] = []
    public var isSelected: Bool = false
    @ViewBuilder public let menu: () -> MenuContent

    @Environment(ThemeSettings.self) private var theme
    @State private var hovering = false

    public init(
        title: String,
        tint: Color,
        count: Int? = nil,
        detail: String? = nil,
        previews: [FileItem] = [],
        isSelected: Bool = false,
        @ViewBuilder menu: @escaping () -> MenuContent
    ) {
        self.title = title
        self.tint = tint
        self.count = count
        self.detail = detail
        self.previews = previews
        self.isSelected = isSelected
        self.menu = menu
    }

    public var body: some View {
        if theme.style == .minimal {
            MinimalFolderCard(
                title: title,
                detail: detail ?? (count.map { Fmt.plural($0, "item") } ?? "Folder"),
                previews: previews,
                isSelected: isSelected,
                menu: menu
            )
        } else {
            playful
        }
    }

    private var playful: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if !previews.isEmpty {
                        PreviewStack(items: previews, tint: tint)
                    } else {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                }
                .padding(.top, 12)

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(detail ?? (count.map { Fmt.plural($0, "item") } ?? "Folder"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(height: 112)
            .background(
                FolderShape()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                FolderShape()
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.22), lineWidth: isSelected ? 2 : 1)
            )

            if hovering {
                DotsButton(content: menu)
                    .padding(10)
            }
        }
        .scaleEffect(hovering ? 1.015 : 1.0)
        .animation(.snappy(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }
}

public struct MinimalFolderCard<MenuContent: View>: View {
    public let title: String
    public let detail: String
    public var previews: [FileItem]
    public var isSelected: Bool
    @ViewBuilder public let menu: () -> MenuContent
    @State private var hovering = false

    public init(
        title: String,
        detail: String,
        previews: [FileItem],
        isSelected: Bool,
        @ViewBuilder menu: @escaping () -> MenuContent
    ) {
        self.title = title
        self.detail = detail
        self.previews = previews
        self.isSelected = isSelected
        self.menu = menu
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if hovering {
                DotsButton(content: menu)
            }
        }
        .padding(12)
        .frame(height: 76)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Theme.line, lineWidth: isSelected ? 2 : 1)
        )
        .onHover { hovering = $0 }
    }
}

public struct FolderItemCard: View {
    public let url: URL
    public var title: String
    public var tint: Color
    public var isSelected: Bool = false
    public var list: [FileItem] = []
    public var item: FileItem?

    @Environment(AppState.self) private var state
    @State private var count: Int?
    @State private var previews: [FileItem] = []

    public init(url: URL, title: String, tint: Color? = nil, isSelected: Bool = false, list: [FileItem] = [], item: FileItem? = nil) {
        self.url = url
        self.title = title
        self.tint = tint ?? Theme.pastel(for: title)
        self.isSelected = isSelected
        self.list = list
        self.item = item
    }

    public var body: some View {
        FolderCard(
            title: title,
            tint: tint,
            count: count,
            previews: previews,
            isSelected: isSelected
        ) {
            if let item {
                FileContextMenu(items: [item], list: list)
            } else {
                Button("Open Folder") { state.openFolder(url) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                let isPinned = state.pinned.contains(url)
                Button(isPinned ? "Remove from Favourites" : "Add to Favourites") {
                    state.togglePin(url)
                }
            }
        }
        .task(id: url) {
            if let items = try? await LibraryStore.listFolder(url) {
                count = items.count
                previews = Array(items.filter { $0.category != .folders }.prefix(3))
            }
        }
    }
}

public struct AddFolderCard: View {
    public let action: () -> Void
    @State private var hovering = false

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text("Add Folder")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(hovering ? Color.accentColor : Color.secondary.opacity(0.35))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
