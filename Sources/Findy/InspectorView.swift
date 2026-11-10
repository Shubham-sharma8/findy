import SwiftUI
import AppKit
import QuickLookUI

// MARK: - Metadata Details Helper

public struct DetailRow: Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let value: String
}

public enum Metadata {
    public static func details(for item: FileItem) -> [DetailRow] {
        var rows: [DetailRow] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty {
                rows.append(DetailRow(label: label, value: value))
            }
        }
        add("Kind", item.kindDescription)
        add("Size", "\(item.sizeText) (\(item.size.formatted()) bytes)")
        add("Date Modified", Fmt.date(item.modified))
        add("Created", Fmt.date(item.created))
        if let uti = item.contentType?.identifier {
            add("UTI", uti)
        }
        if let w = item.pixelWidth, let h = item.pixelHeight, w > 0 && h > 0 {
            add("Dimensions", "\(w) × \(h)")
        }
        if let dur = item.duration, dur > 0 {
            add("Duration", Fmt.duration(dur))
        }
        if let artist = item.artist {
            add("Artist", artist)
        }
        if let album = item.album {
            add("Album", album)
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: item.url.path),
           let perms = attrs[.posixPermissions] as? NSNumber {
            add("Permissions", String(format: "0%o", perms.intValue))
        }
        add("Location", Fmt.displayPath(item.url.deletingLastPathComponent()))
        return rows
    }
}

// MARK: - Inspector View (⌘I)

public struct InspectorView: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        Group {
            if let item = state.focusedItem {
                ItemInspector(item: item)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "sidebar.right",
                    description: Text("Select a file to see a preview, OCR text, SHA-256 checksum, and details.")
                )
            }
        }
        .frame(width: 285)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

public struct ItemInspector: View {
    public let item: FileItem
    @Environment(AppState.self) private var state
    @Environment(TextIndex.self) private var textIndex
    @State private var rows: [DetailRow] = []
    @State private var sha256Hash: String?
    @State private var computingHash = false

    public init(item: FileItem) {
        self.item = item
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Preview
                ThumbnailView(item: item, cornerRadius: 12)
                    .frame(height: 175)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
                    .onTapGesture(count: 2) {
                        state.preview(item, in: [item])
                    }

                // Title & Quick Actions
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .bold))
                        .textSelection(.enabled)

                    HStack(spacing: 6) {
                        Button {
                            FileActions.openExternally([item])
                        } label: {
                            Label("Open", systemImage: "arrow.up.forward.app")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            FileActions.reveal([item])
                        } label: {
                            Label("Finder", systemImage: "folder")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            FileActions.openInTerminal(item.url)
                        } label: {
                            Image(systemName: "terminal")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Open Folder in Terminal")
                    }
                }

                // Finder Color Tags
                VStack(alignment: .leading, spacing: 6) {
                    Text("Finder Tag")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(FinderTag.allCases) { tag in
                            let active = item.tags.contains { $0.caseInsensitiveCompare(tag.rawValue) == .orderedSame }
                            Button {
                                FileActions.setFinderTag(active ? nil : tag, on: [item])
                                state.focusedItem = FileItem(url: item.url)
                                state.refreshToken += 1
                            } label: {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(active ? Color.primary : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(tag.rawValue)
                        }
                    }
                }

                // Download Source Provenance
                if let src = DownloadSources.source(for: item.url) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Downloaded From")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack {
                            SourceBadge(source: src, size: 12)
                            Spacer()
                            Button("Show all") {
                                state.selection = .source(src.name)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                // Recognized OCR Text Section
                RecognizedTextSection(item: item)

                Divider()

                // Information Table
                VStack(alignment: .leading, spacing: 8) {
                    Text("Information")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                            Text(row.value)
                                .font(.system(size: 11.5, weight: .medium))
                                .textSelection(.enabled)
                        }
                    }

                    // Improved Feature: On-demand SHA-256 Checksum
                    if item.category != .folders && item.category != .apps {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SHA-256 Checksum")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                            if let sha256Hash {
                                HStack {
                                    Text(sha256Hash)
                                        .font(Theme.mono(10))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(sha256Hash, forType: .string)
                                        state.showToast("Copied SHA-256 checksum")
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Button(computingHash ? "Computing…" : "Compute SHA-256") {
                                    computingHash = true
                                    let url = item.url
                                    Task {
                                        let h = await Task.detached { FileActions.sha256(for: url) }.value
                                        await MainActor.run {
                                            sha256Hash = h
                                            computingHash = false
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .disabled(computingHash)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .task(id: item.url) {
            rows = Metadata.details(for: item)
            sha256Hash = nil
            computingHash = false
        }
    }
}

// MARK: - Quick Look View & Preview Sheet

public struct QuickLookView: NSViewRepresentable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    public func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as NSURL
    }
}

public struct PreviewSheet: View {
    @Environment(AppState.self) private var state
    @Environment(TextIndex.self) private var textIndex
    @State private var selectText: Bool = false

    public init() {}

    public var body: some View {
        if let item = state.previewItem {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button {
                        state.stepPreview(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(state.previewList.first == item)

                    Button {
                        state.stepPreview(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(state.previewList.last == item)

                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    if TextRecognizer.canRead(item) {
                        Toggle(isOn: $selectText) {
                            Label("Live Text", systemImage: "text.viewfinder")
                                .font(.system(size: 12))
                        }
                        .toggleStyle(.button)

                        Button {
                            CopyText.run([item], index: textIndex, state: state)
                        } label: {
                            Label("Copy Text", systemImage: "doc.on.clipboard")
                        }
                    }

                    Button("Open") {
                        FileActions.openExternally([item])
                    }

                    Button("Close (Esc)") {
                        state.previewItem = nil
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding(12)

                Divider()

                if selectText && item.category == .images {
                    LiveTextImage(url: item.url)
                        .frame(minWidth: 720, minHeight: 480)
                } else {
                    QuickLookView(url: item.url)
                        .id(item.url)
                        .frame(minWidth: 720, minHeight: 480)
                }
            }
        }
    }
}
