import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - File Shelf / Drop Basket (Improved Feature)

@Observable
public final class FileShelf {
    public static let shared = FileShelf()

    public private(set) var items: [FileItem] = []
    private let storageKey: String

    public init(storageKey: String = "findy.fileShelf.urls") {
        self.storageKey = storageKey
        let savedPaths = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        self.items = savedPaths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .compactMap { FileItem(url: $0) }
    }

    public var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    public func contains(_ url: URL) -> Bool {
        let std = url.standardizedFileURL
        return items.contains { $0.url.standardizedFileURL == std }
    }

    public func add(_ newItems: [FileItem]) {
        var existing = Set(items.map { $0.url.standardizedFileURL })
        var updated = items
        for item in newItems {
            let std = item.url.standardizedFileURL
            if !existing.contains(std) {
                existing.insert(std)
                updated.append(item)
            }
        }
        items = updated
        persist()
    }

    public func addURLs(_ urls: [URL]) {
        let fileItems = urls.compactMap { FileItem(url: $0) }
        add(fileItems)
    }

    public func remove(_ urls: Set<URL>) {
        let stdSet = Set(urls.map(\.standardizedFileURL))
        items = items.filter { !stdSet.contains($0.url.standardizedFileURL) }
        persist()
    }

    public func clear() {
        items = []
        persist()
    }

    public func refresh() {
        items = items.compactMap { FileItem(url: $0.url) }
        persist()
    }

    public func copyAll(to destinationFolder: URL) throws -> [URL] {
        let fm = FileManager.default
        var copied: [URL] = []
        for item in items {
            let target = Self.uniqueDestinationURL(for: item.url.lastPathComponent, in: destinationFolder)
            if item.url.standardizedFileURL != target.standardizedFileURL {
                try fm.copyItem(at: item.url, to: target)
                copied.append(target)
            } else {
                copied.append(item.url)
            }
        }
        return copied
    }

    public func moveAll(to destinationFolder: URL) throws -> [URL] {
        let fm = FileManager.default
        var moved: [URL] = []
        var movedOrigins = Set<URL>()
        for item in items {
            if item.url.deletingLastPathComponent().standardizedFileURL == destinationFolder.standardizedFileURL {
                moved.append(item.url)
                movedOrigins.insert(item.url)
                continue
            }
            let target = Self.uniqueDestinationURL(for: item.url.lastPathComponent, in: destinationFolder)
            try fm.moveItem(at: item.url, to: target)
            moved.append(target)
            movedOrigins.insert(item.url)
        }
        remove(movedOrigins)
        return moved
    }

    public static func uniqueDestinationURL(for fileName: String, in folder: URL) -> URL {
        let fm = FileManager.default
        let candidate = folder.appendingPathComponent(fileName)
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        let ext = (fileName as NSString).pathExtension
        let stem = (fileName as NSString).deletingPathExtension
        var counter = 2
        while true {
            let nextName = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            let nextURL = folder.appendingPathComponent(nextName)
            if !fm.fileExists(atPath: nextURL.path) {
                return nextURL
            }
            counter += 1
        }
    }

    private func persist() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: storageKey)
    }
}

// MARK: - File Shelf Interactive View

public struct FileShelfView: View {
    @Environment(AppState.self) private var state
    @Environment(FileShelf.self) private var shelf
    @State private var isDropTargeted = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                            Text("File Shelf")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                        }
                        Text("Stage files from multiple folders or searches into one basket, then move, copy, archive, or batch-rename them together.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !shelf.items.isEmpty {
                        Button(role: .destructive) {
                            shelf.clear()
                            state.showToast("Cleared File Shelf", symbol: "tray")
                        } label: {
                            Label("Clear Shelf", systemImage: "xmark.bin")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Batch Action Toolbar when Shelf has items
                if !shelf.items.isEmpty {
                    HStack(spacing: 10) {
                        Label("\(Fmt.plural(shelf.items.count, "item")) · \(Fmt.bytes(shelf.totalSize))", systemImage: "shippingbox")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            chooseFolder(prompt: "Move Here") { folder in
                                do {
                                    let moved = try shelf.moveAll(to: folder)
                                    state.refreshToken += 1
                                    state.showToast("Moved \(Fmt.plural(moved.count, "item")) to \(folder.lastPathComponent)", symbol: "folder.fill")
                                } catch {
                                    state.showToast("Move failed: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
                                }
                            }
                        } label: {
                            Label("Move All To…", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            chooseFolder(prompt: "Copy Here") { folder in
                                do {
                                    let copied = try shelf.copyAll(to: folder)
                                    state.refreshToken += 1
                                    state.showToast("Copied \(Fmt.plural(copied.count, "item")) to \(folder.lastPathComponent)", symbol: "doc.on.doc.fill")
                                } catch {
                                    state.showToast("Copy failed: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
                                }
                            }
                        } label: {
                            Label("Copy All To…", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            do {
                                let zipURL = try FileActions.createZipArchive(from: shelf.items)
                                state.refreshToken += 1
                                state.showToast("Created \(zipURL.lastPathComponent)", symbol: "doc.zipper")
                                NSWorkspace.shared.activateFileViewerSelecting([zipURL])
                            } catch {
                                state.showToast("Zip failed: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
                            }
                        } label: {
                            Label("Create .zip Archive", systemImage: "doc.zipper")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            state.selectedFiles = Set(shelf.items.map(\.url))
                            state.showBatchRename = true
                        } label: {
                            Label("Batch Rename…", systemImage: "pencil.and.list.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            FileActions.copy(shelf.items)
                            state.showToast("Copied \(Fmt.plural(shelf.items.count, "file")) to clipboard")
                        } label: {
                            Label("Copy to Clipboard", systemImage: "clipboard")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
                }

                // Drop Zone Card
                VStack(spacing: 10) {
                    Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "plus.viewfinder")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                    Text(isDropTargeted ? "Release to add files to your Shelf" : "Drag & drop files here from Findy or Finder, or press ⇧⌘B on any selected file")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isDropTargeted ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? Color.accentColor : Theme.line,
                            style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4])
                        )
                )
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }

                // Staged Files List
                if shelf.items.isEmpty {
                    ContentUnavailableView(
                        "Your File Shelf Is Empty",
                        systemImage: "tray",
                        description: Text("Right-click any file and choose “Add to File Shelf (⇧⌘B)” or drag files onto the File Shelf in the sidebar.")
                    )
                    .frame(minHeight: 200)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("Staged Files", count: shelf.items.count)
                        LazyVStack(spacing: 4) {
                            ForEach(shelf.items) { item in
                                HStack(spacing: 8) {
                                    FileRow(
                                        item: item,
                                        isSelected: state.selectedFiles.contains(item.url),
                                        isPlaying: false
                                    )
                                    .modifier(FileInteractions(item: item, list: shelf.items))

                                    Button {
                                        shelf.remove([item.url])
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove from Shelf")
                                    .padding(.trailing, 8)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .onChange(of: state.refreshToken) { _, _ in
            shelf.refresh()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                let url: URL?
                if let d = data as? Data {
                    url = URL(dataRepresentation: d, relativeTo: nil)
                } else if let u = data as? URL {
                    url = u
                } else if let nsurl = data as? NSURL {
                    url = nsurl as URL
                } else {
                    url = nil
                }
                if let url {
                    Task { @MainActor in
                        shelf.addURLs([url])
                        state.showToast("Added \(url.lastPathComponent) to File Shelf", symbol: "tray.and.arrow.down.fill")
                    }
                }
            }
        }
        return handled
    }

    private func chooseFolder(prompt: String, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        if panel.runModal() == .OK, let folder = panel.url {
            completion(folder)
        }
    }
}
