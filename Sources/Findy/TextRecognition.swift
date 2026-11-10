import Foundation
import SwiftUI
import AppKit
import Vision
import PDFKit

// MARK: - On-Device Text Recognizer (Vision + PDFKit)

public enum TextRecognizer {
    public static func canRead(_ item: FileItem) -> Bool {
        if item.category == .images { return true }
        if item.url.pathExtension.lowercased() == "pdf" { return true }
        return false
    }

    public static func recognize(_ cgImage: CGImage) -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([req])
        let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    public static func text(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf", let doc = PDFDocument(url: url) {
            var pages: [String] = []
            let pageCount = min(doc.pageCount, 25)
            for i in 0..<pageCount {
                if let pageText = doc.page(at: i)?.string, !pageText.isEmpty {
                    pages.append(pageText)
                }
            }
            let combined = pages.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !combined.isEmpty { return combined }
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return ""
        }
        return recognize(cg)
    }
}

// MARK: - Persistent Text Index

@Observable
public final class TextIndex {
    public struct Entry: Codable, Sendable {
        public var modified: TimeInterval
        public var text: String
    }

    public var isIndexing: Bool = false
    public var done: Int = 0
    public var total: Int = 0
    public var indexedCount: Int = 0

    private var entries: [String: Entry] = [:]
    private var worker: Task<Void, Never>?
    private var dirty: Bool = false

    public init() {
        loadFromDisk()
    }

    private static var indexFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("Findy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("text-index.json")
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: Self.indexFileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        self.entries = decoded
        self.indexedCount = decoded.count
    }

    private func saveToDisk() {
        guard dirty else { return }
        dirty = false
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: Self.indexFileURL, options: .atomic)
        }
    }

    @MainActor
    public func text(for item: FileItem) async -> String {
        let key = item.url.path
        let mod = item.modified.timeIntervalSince1970
        if let cached = entries[key], abs(cached.modified - mod) < 1.0 {
            return cached.text
        }
        let url = item.url
        let recognized = await Task.detached {
            TextRecognizer.text(for: url)
        }.value
        store(recognized, for: item)
        saveToDisk()
        return recognized
    }

    public func matchingURLs(for terms: [String]) -> [URL] {
        guard !terms.isEmpty else { return [] }
        let lowerTerms = terms.map { $0.lowercased() }
        var matches: [URL] = []
        for (path, entry) in entries where !entry.text.isEmpty {
            let lowerText = entry.text.lowercased()
            if lowerTerms.allSatisfy({ lowerText.contains($0) }) {
                matches.append(URL(fileURLWithPath: path))
            }
        }
        return matches
    }

    @MainActor
    public func index(_ items: [FileItem]) {
        let candidates = items.filter { item in
            guard TextRecognizer.canRead(item) else { return false }
            let key = item.url.path
            let mod = item.modified.timeIntervalSince1970
            if let existing = entries[key], abs(existing.modified - mod) < 1.0 {
                return false
            }
            return true
        }
        guard !candidates.isEmpty else { return }
        worker?.cancel()
        total = candidates.count
        done = 0
        isIndexing = true

        worker = Task { @MainActor in
            for item in candidates {
                if Task.isCancelled { break }
                let url = item.url
                let recognized = await Task.detached(priority: .utility) {
                    TextRecognizer.text(for: url)
                }.value
                store(recognized, for: item)
                done += 1
            }
            finish()
        }
    }

    @MainActor
    private func store(_ text: String, for item: FileItem) {
        entries[item.url.path] = Entry(modified: item.modified.timeIntervalSince1970, text: text)
        indexedCount = entries.count
        dirty = true
    }

    @MainActor
    private func finish() {
        isIndexing = false
        saveToDisk()
    }

    public func forget(_ urls: Set<URL>) {
        for url in urls {
            entries.removeValue(forKey: url.path)
        }
        indexedCount = entries.count
        dirty = true
        saveToDisk()
    }
}

// MARK: - Copy Text Action & UI

public enum CopyText {
    @MainActor
    public static func run(_ items: [FileItem], index: TextIndex, state: AppState) {
        guard let first = items.first else { return }
        Task { @MainActor in
            state.showToast("Reading text in \(first.name)…", symbol: "text.viewfinder")
            let text = await index.text(for: first)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                state.showToast("No text found in “\(first.name)”", symbol: "text.badge.xmark")
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(trimmed, forType: .string)
                state.showToast("Copied text from \(first.name)", symbol: "doc.on.clipboard")
            }
        }
    }
}

public struct RecognizedTextSection: View {
    public let item: FileItem
    @Environment(TextIndex.self) private var index
    @Environment(AppState.self) private var state
    @State private var text: String = ""
    @State private var loading: Bool = false

    public init(item: FileItem) {
        self.item = item
    }

    public var body: some View {
        if TextRecognizer.canRead(item) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Text in Image", systemImage: "text.viewfinder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !text.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            state.showToast("Copied text", symbol: "doc.on.clipboard")
                        } label: {
                            Label("Copy Text", systemImage: "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
                if loading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Reading text…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if text.isEmpty {
                    Text("No text found.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        Text(text)
                            .font(.system(size: 11))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 110)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }
            }
            .task(id: item.url) {
                loading = true
                text = await index.text(for: item)
                loading = false
            }
        }
    }
}

public struct LiveTextImage: NSViewRepresentable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public final class Coordinator {
        var url: URL?
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.allowsCutCopyPaste = true
        return view
    }

    public func updateNSView(_ nsView: NSImageView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            nsView.image = NSImage(contentsOf: url)
        }
    }
}
