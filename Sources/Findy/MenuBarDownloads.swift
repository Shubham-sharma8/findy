import Foundation
import SwiftUI
import AppKit

// MARK: - Recent Downloads Loader

public enum RecentDownloads {
    public static func load(limit: Int = 12) -> [FileItem] {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let keys: [URLResourceKey] = [
            .nameKey, .fileSizeKey, .contentModificationDateKey,
            .creationDateKey, .contentTypeKey, .isDirectoryKey, .isPackageKey
        ]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: downloads,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .compactMap { FileItem(url: $0) }
            .sorted { $0.modified > $1.modified }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Menu Bar Recent Downloads Popover

public struct MenuBarDownloadsView: View {
    public let state: AppState
    @State private var items: [FileItem] = RecentDownloads.load(limit: 16)
    @State private var filterText: String = ""

    public init(state: AppState) {
        self.state = state
    }

    private var filteredItems: [FileItem] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.name.lowercased().contains(q) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Label("Recent Downloads", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button("Open Downloads") {
                    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Filter recent downloads…", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()

            if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text(items.isEmpty ? "Your Downloads folder is empty." : "No downloads match “\(filterText)”")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredItems) { item in
                            MenuBarRow(item: item)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 360)
            }

            Divider()

            HStack {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where window.canBecomeMain {
                        window.makeKeyAndOrderFront(nil)
                    }
                } label: {
                    Label("Open Findy", systemImage: "macwindow")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    items = RecentDownloads.load(limit: 16)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh Downloads")

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 370)
        .onAppear {
            items = RecentDownloads.load(limit: 16)
        }
    }
}

private struct MenuBarRow: View {
    let item: FileItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(item: item, cornerRadius: 7)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                FileShelf.shared.add([item])
            } label: {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Add to File Shelf")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.07) : .clear)
        )
        .onHover { hovering = $0 }
        .onTapGesture {
            NSWorkspace.shared.open(item.url)
        }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
    }
}
