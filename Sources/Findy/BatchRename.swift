import Foundation
import SwiftUI

// MARK: - Smart Batch Rename Studio (Improved Feature)

public enum CaseTransform: String, CaseIterable, Identifiable, Sendable {
    case none = "Keep Case"
    case lowercase = "lowercase"
    case uppercase = "UPPERCASE"
    case titleCase = "Title Case"
    case kebabCase = "kebab-case"

    public var id: String { rawValue }

    public func apply(_ input: String) -> String {
        switch self {
        case .none:
            return input
        case .lowercase:
            return input.lowercased()
        case .uppercase:
            return input.uppercased()
        case .titleCase:
            return input.capitalized
        case .kebabCase:
            return input
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "_", with: "-")
        }
    }
}

public struct BatchRenameRule: Equatable, Sendable {
    public var findText: String
    public var replaceText: String
    public var useRegex: Bool
    public var prefix: String
    public var suffix: String
    public var newExtension: String
    public var addSequence: Bool
    public var sequenceStart: Int
    public var sequenceDigits: Int
    public var caseTransform: CaseTransform
    public var addDateStamp: Bool

    public init(
        findText: String = "",
        replaceText: String = "",
        useRegex: Bool = false,
        prefix: String = "",
        suffix: String = "",
        newExtension: String = "",
        addSequence: Bool = false,
        sequenceStart: Int = 1,
        sequenceDigits: Int = 2,
        caseTransform: CaseTransform = .none,
        addDateStamp: Bool = false
    ) {
        self.findText = findText
        self.replaceText = replaceText
        self.useRegex = useRegex
        self.prefix = prefix
        self.suffix = suffix
        self.newExtension = newExtension
        self.addSequence = addSequence
        self.sequenceStart = sequenceStart
        self.sequenceDigits = sequenceDigits
        self.caseTransform = caseTransform
        self.addDateStamp = addDateStamp
    }
}

public struct BatchRenamePreview: Identifiable, Equatable, Sendable {
    public let item: FileItem
    public let newName: String
    public let destinationURL: URL
    public let hasConflict: Bool

    public var id: URL { item.url }

    public init(item: FileItem, newName: String, destinationURL: URL, hasConflict: Bool) {
        self.item = item
        self.newName = newName
        self.destinationURL = destinationURL
        self.hasConflict = hasConflict
    }
}

public enum BatchRenamer {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var lastAppliedPairs: [(original: URL, renamed: URL)] = []

    public static var canUndo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !lastAppliedPairs.isEmpty
    }

    public static func preview(items: [FileItem], rule: BatchRenameRule) -> [BatchRenamePreview] {
        var seenDestinations = Set<String>()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let compiledRegex: NSRegularExpression? = {
            guard rule.useRegex, !rule.findText.isEmpty else { return nil }
            return try? NSRegularExpression(pattern: rule.findText)
        }()
        let trimmedExt = rule.newExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return items.enumerated().map { idx, item in
            let ext = trimmedExt.isEmpty ? item.url.pathExtension : trimmedExt
            var stem = item.url.deletingPathExtension().lastPathComponent

            if !rule.findText.isEmpty {
                if rule.useRegex {
                    if let regex = compiledRegex {
                        let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)
                        stem = regex.stringByReplacingMatches(in: stem, options: [], range: range, withTemplate: rule.replaceText)
                    }
                } else {
                    stem = stem.replacingOccurrences(of: rule.findText, with: rule.replaceText)
                }
            }

            stem = "\(rule.prefix)\(stem)\(rule.suffix)"

            if rule.addDateStamp {
                let ds = dateFormatter.string(from: item.modified)
                stem = "\(stem)_\(ds)"
            }

            if rule.addSequence {
                let num = rule.sequenceStart + idx
                let format = "%0\(max(1, rule.sequenceDigits))d"
                let seq = String(format: format, num)
                stem = "\(stem)_\(seq)"
            }

            stem = rule.caseTransform.apply(stem)

            let finalName = ext.isEmpty ? stem : "\(stem).\(ext)"
            let dest = item.url.deletingLastPathComponent().appendingPathComponent(finalName)
            let destKey = dest.path.lowercased()
            let conflict = seenDestinations.contains(destKey)
                || (dest.standardizedFileURL != item.url.standardizedFileURL && FileManager.default.fileExists(atPath: dest.path))
            seenDestinations.insert(destKey)

            return BatchRenamePreview(
                item: item,
                newName: finalName,
                destinationURL: dest,
                hasConflict: conflict
            )
        }
    }

    public static func apply(previews: [BatchRenamePreview]) throws -> [URL] {
        var renamed: [URL] = []
        var pairs: [(original: URL, renamed: URL)] = []
        let fm = FileManager.default
        for preview in previews where !preview.hasConflict {
            if preview.destinationURL.standardizedFileURL == preview.item.url.standardizedFileURL {
                renamed.append(preview.item.url)
                continue
            }
            try fm.moveItem(at: preview.item.url, to: preview.destinationURL)
            renamed.append(preview.destinationURL)
            pairs.append((original: preview.item.url, renamed: preview.destinationURL))
        }
        lock.lock()
        lastAppliedPairs = pairs
        lock.unlock()
        return renamed
    }

    @discardableResult
    public static func undoLastRename() throws -> Int {
        lock.lock()
        let pairs = lastAppliedPairs
        lastAppliedPairs = []
        lock.unlock()

        guard !pairs.isEmpty else { return 0 }
        let fm = FileManager.default
        var restored = 0
        for pair in pairs.reversed() {
            if fm.fileExists(atPath: pair.renamed.path) && !fm.fileExists(atPath: pair.original.path) {
                try fm.moveItem(at: pair.renamed, to: pair.original)
                restored += 1
            }
        }
        return restored
    }
}

// MARK: - Batch Rename Sheet UI

public struct BatchRenameSheet: View {
    public let items: [FileItem]
    public let onComplete: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rule = BatchRenameRule()
    @State private var errorMessage: String?

    public init(items: [FileItem], onComplete: @escaping (Int) -> Void) {
        self.items = items
        self.onComplete = onComplete
    }

    private var previews: [BatchRenamePreview] {
        BatchRenamer.preview(items: items, rule: rule)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Smart Batch Rename Studio", systemImage: "pencil.and.list.clipboard")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Renaming \(Fmt.plural(items.count, "file")) with live preview")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Find & Replace")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField(rule.useRegex ? "Regex pattern (e.g. IMG_(\\d+))…" : "Find text…", text: $rule.findText)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField(rule.useRegex ? "Template (e.g. Photo-$1)…" : "Replace with…", text: $rule.replaceText)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Regex", isOn: $rule.useRegex)
                            .help("Use Regular Expression pattern and $1, $2 capture groups")
                    }
                }

                GridRow {
                    Text("Prefix / Suffix")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("Prefix…", text: $rule.prefix)
                            .textFieldStyle(.roundedBorder)
                        TextField("Suffix…", text: $rule.suffix)
                            .textFieldStyle(.roundedBorder)
                        TextField("Ext (optional)", text: $rule.newExtension)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 105)
                    }
                }

                GridRow {
                    Text("Formatting")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Picker("Case", selection: $rule.caseTransform) {
                            ForEach(CaseTransform.allCases) { ct in
                                Text(ct.rawValue).tag(ct)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)

                        Toggle("Add Sequence (01, 02…)", isOn: $rule.addSequence)
                        Toggle("Add Date Stamp", isOn: $rule.addDateStamp)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))

            // Preview Table
            VStack(alignment: .leading, spacing: 6) {
                Text("LIVE PREVIEW")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(previews) { p in
                            HStack(spacing: 10) {
                                Text(p.item.name)
                                    .font(Theme.mono(11.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.tertiary)

                                Text(p.newName)
                                    .font(Theme.mono(11.5, .semibold))
                                    .foregroundStyle(p.hasConflict ? .red : Color.accentColor)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.04)))
                        }
                    }
                }
                .frame(height: 200)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                if BatchRenamer.canUndo {
                    Button {
                        do {
                            let count = try BatchRenamer.undoLastRename()
                            onComplete(count)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Undo Last Rename", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Rename \(Fmt.plural(previews.count, "File"))") {
                    do {
                        let urls = try BatchRenamer.apply(previews: previews)
                        onComplete(urls.count)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600)
    }
}
