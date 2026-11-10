import Foundation
import SwiftUI
import AppKit
import CryptoKit

// MARK: - File Actions

public enum FileActions {
    public static func openExternally(_ items: [FileItem]) {
        for item in items {
            NSWorkspace.shared.open(item.url)
        }
    }

    public static func reveal(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    public static func copy(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { $0.url as NSURL })
    }

    public static func copyPath(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        let joined = items.map(\.url.path).joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(joined, forType: .string)
    }

    public static func openInTerminal(_ url: URL) {
        let dir = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Terminal", dir.path]
        try? proc.run()
    }

    public static func setFinderTag(_ tag: FinderTag?, on items: [FileItem]) {
        for item in items {
            let nsURL = item.url as NSURL
            let tags: [String] = tag.map { [$0.rawValue] } ?? []
            try? nsURL.setResourceValue(tags, forKey: .tagNamesKey)
        }
    }

    public static func sha256(for url: URL) -> String? {
        DuplicateScanner.fingerprint(url, size: 0, full: true)
    }

    public static func createZipArchive(from items: [FileItem], archiveName: String? = nil, in destinationFolder: URL? = nil) throws -> URL {
        guard let first = items.first else {
            throw NSError(domain: "Findy.FileActions", code: 1, userInfo: [NSLocalizedDescriptionKey: "No files selected to compress."])
        }
        let parentDir = destinationFolder ?? first.url.deletingLastPathComponent()
        let baseStem: String
        if let archiveName, !archiveName.isEmpty {
            baseStem = (archiveName as NSString).deletingPathExtension
        } else if items.count == 1 {
            baseStem = first.url.deletingPathExtension().lastPathComponent
        } else {
            baseStem = "Archive"
        }
        let zipURL = FileShelf.uniqueDestinationURL(for: "\(baseStem).zip", in: parentDir)

        if items.count == 1 {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", first.url.path, zipURL.path]
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                throw NSError(domain: "Findy.FileActions", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to create .zip archive."])
            }
            return zipURL
        } else {
            let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("findy-zip-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: stagingDir) }

            for item in items {
                let stagedTarget = FileShelf.uniqueDestinationURL(for: item.url.lastPathComponent, in: stagingDir)
                try FileManager.default.copyItem(at: item.url, to: stagedTarget)
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-c", "-k", "--sequesterRsrc", stagingDir.path, zipURL.path]
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                throw NSError(domain: "Findy.FileActions", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to create .zip archive."])
            }
            return zipURL
        }
    }

    public static func trash(_ items: [FileItem], completion: @escaping (Set<URL>) -> Void) {
        var removed = Set<URL>()
        for item in items {
            if (try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)) != nil {
                removed.insert(item.url)
            }
        }
        completion(removed)
    }
}

// MARK: - File Context Menu

public struct FileContextMenu: View {
    public let items: [FileItem]
    public let list: [FileItem]
    @Environment(AppState.self) private var state
    @Environment(LibraryStore.self) private var store
    @Environment(Player.self) private var player
    @Environment(TextIndex.self) private var textIndex
    @Environment(CleanupStore.self) private var cleanup
    @Environment(DuplicateFinder.self) private var duplicates
    @Environment(SourceStore.self) private var sources
    @Environment(FileShelf.self) private var shelf

    public init(items: [FileItem], list: [FileItem]) {
        self.items = items
        self.list = list
    }

    public var body: some View {
        let first = items.first
        Button {
            if let first {
                if first.category == .folders {
                    state.openFolder(first.url)
                } else {
                    FileActions.openExternally(items)
                }
            }
        } label: {
            Label(items.count > 1 ? "Open \(items.count) Items" : "Open with Default App", systemImage: "arrow.up.forward.app")
        }

        if let first {
            Button {
                state.preview(first, in: list)
            } label: {
                Label("Quick Look (Space)", systemImage: "eye")
            }

            Button {
                state.focusedItem = first
                state.showInspector = true
            } label: {
                Label("Show Details (⌘I)", systemImage: "info.circle")
            }
        }

        Button {
            FileActions.reveal(items)
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }

        if let first {
            Button {
                FileActions.openInTerminal(first.url)
            } label: {
                Label("Open Folder in Terminal", systemImage: "terminal")
            }
        }

        Divider()

        Button {
            FileActions.copy(items)
            state.showToast("Copied \(Fmt.plural(items.count, "file"))")
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
            FileActions.copyPath(items)
            state.showToast("Copied path to clipboard")
        } label: {
            Label("Copy Path", systemImage: "link")
        }

        if let first, TextRecognizer.canRead(first) {
            Button {
                CopyText.run(items, index: textIndex, state: state)
            } label: {
                Label("Copy Text from Image (⇧⌘C)", systemImage: "text.viewfinder")
            }
        }

        if !items.isEmpty {
            Button {
                shelf.add(items)
                state.showToast("Added \(Fmt.plural(items.count, "item")) to File Shelf", symbol: "tray.and.arrow.down.fill")
            } label: {
                Label(items.count > 1 ? "Add \(items.count) Items to File Shelf (⇧⌘B)" : "Add to File Shelf (⇧⌘B)", systemImage: "tray.and.arrow.down")
            }

            Button {
                do {
                    let zipURL = try FileActions.createZipArchive(from: items)
                    state.refreshToken += 1
                    state.showToast("Created \(zipURL.lastPathComponent)", symbol: "doc.zipper")
                } catch {
                    state.showToast("Archive failed: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
                }
            } label: {
                Label(items.count > 1 ? "Compress \(items.count) Items to .zip" : "Compress “\(first?.name ?? "File")” to .zip", systemImage: "doc.zipper")
            }

            Button {
                state.selectedFiles = Set(items.map(\.url))
                state.showBatchRename = true
            } label: {
                Label(items.count > 1 ? "Batch Rename \(items.count) Items… (⇧⌘R)" : "Smart Rename… (⇧⌘R)", systemImage: "pencil.and.list.clipboard")
            }
        }

        Menu("Finder Tag") {
            ForEach(FinderTag.allCases) { tag in
                Button {
                    FileActions.setFinderTag(tag, on: items)
                    if let currentFocus = state.focusedItem, items.contains(where: { $0.url == currentFocus.url }) {
                        state.focusedItem = FileItem(url: currentFocus.url)
                    }
                    state.refreshToken += 1
                    state.showToast("Tagged \(tag.rawValue)", symbol: "tag.fill")
                } label: {
                    Label(tag.rawValue, systemImage: "circle.fill")
                }
            }
            Divider()
            Button("Clear Tags") {
                FileActions.setFinderTag(nil, on: items)
                if let currentFocus = state.focusedItem, items.contains(where: { $0.url == currentFocus.url }) {
                    state.focusedItem = FileItem(url: currentFocus.url)
                }
                state.refreshToken += 1
            }
        }

        if let first, first.category == .folders {
            let isPinned = state.pinned.contains(first.url)
            Button {
                state.togglePin(first.url)
            } label: {
                Label(isPinned ? "Remove from Favourites" : "Add to Favourites", systemImage: isPinned ? "star.slash" : "star")
            }
        }

        Divider()

        Button(role: .destructive) {
            FileActions.trash(items) { removed in
                store.remove(removed)
                cleanup.remove(removed)
                duplicates.remove(removed)
                sources.remove(removed)
                shelf.remove(removed)
                textIndex.forget(removed)
                state.selectedFiles.subtract(removed)
                state.refreshToken += 1
                state.showToast("Moved \(Fmt.plural(removed.count, "item")) to Trash", symbol: "trash")
            }
        } label: {
            Label("Move to Trash (⌘⌫)", systemImage: "trash")
        }
    }
}

// MARK: - File Interactions & Drag Modifiers

public struct FileInteractions: ViewModifier {
    public let item: FileItem
    public let list: [FileItem]
    public var onTap: (() -> Void)?
    @Environment(AppState.self) private var state
    @Environment(Player.self) private var player

    public init(item: FileItem, list: [FileItem], onTap: (() -> Void)? = nil) {
        self.item = item
        self.list = list
        self.onTap = onTap
    }

    public func body(content: Content) -> some View {
        content
            .onTapGesture(count: 2) {
                if item.category == .folders {
                    state.openFolder(item.url)
                } else if item.category == .music {
                    player.play(item, in: list.filter { $0.category == .music })
                } else {
                    FileActions.openExternally([item])
                }
            }
            .simultaneousGesture(
                TapGesture(count: 1).onEnded {
                    guard state.hoveredCheckbox != item.url else { return }
                    if let onTap {
                        onTap()
                    } else {
                        state.select(item, in: list)
                    }
                }
            )
            .contextMenu {
                FileContextMenu(items: state.targets(for: item, in: list), list: list)
            }
            .onDrag {
                NSItemProvider(object: item.url as NSURL)
            }
    }
}
