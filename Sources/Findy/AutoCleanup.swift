import Foundation
import SwiftUI

// MARK: - Automatic Cleanup Engine

@Observable
public final class AutoCleanup {
    public static let shared = AutoCleanup()

    public struct Entry: Identifiable, Codable, Hashable, Sendable {
        public var id: UUID = UUID()
        public let date: Date
        public let message: String

        public init(id: UUID = UUID(), date: Date = Date(), message: String) {
            self.id = id
            self.date = date
            self.message = message
        }
    }

    public var trashesInstallers: Bool {
        didSet {
            UserDefaults.standard.set(trashesInstallers, forKey: "autoTrashInstallers")
            if trashesInstallers { run() }
        }
    }

    public var installerDays: Int {
        didSet {
            UserDefaults.standard.set(installerDays, forKey: "autoTrashInstallerDays")
            if trashesInstallers { run() }
        }
    }

    public var filesScreenshots: Bool {
        didSet {
            UserDefaults.standard.set(filesScreenshots, forKey: "autoFileScreenshots")
            if filesScreenshots { run() }
        }
    }

    public var log: [Entry] = []
    public var isRunning: Bool = false
    private var timer: Timer?

    public init() {
        self.trashesInstallers = UserDefaults.standard.bool(forKey: "autoTrashInstallers")
        let savedDays = UserDefaults.standard.integer(forKey: "autoTrashInstallerDays")
        self.installerDays = savedDays > 0 ? savedDays : 7
        self.filesScreenshots = UserDefaults.standard.bool(forKey: "autoFileScreenshots")
        self.log = Self.loadLog()
    }

    deinit {
        timer?.invalidate()
    }

    private static func loadLog() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: "autoCleanupLog"),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return decoded
    }

    private func saveLog() {
        if let data = try? JSONEncoder().encode(Array(log.prefix(50))) {
            UserDefaults.standard.set(data, forKey: "autoCleanupLog")
        }
    }

    public static var screenshotFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots")
    }

    public static var screenshotSources: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent("Desktop"), home.appendingPathComponent("Downloads")]
    }

    public func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.run()
        }
        run()
    }

    public func run() {
        guard trashesInstallers || filesScreenshots else { return }
        guard !isRunning else { return }
        isRunning = true
        let days = trashesInstallers ? installerDays : nil
        let organizeShots = filesScreenshots

        Task { @MainActor in
            let messages = await Self.apply(installerDays: days, filesScreenshots: organizeShots)
            for msg in messages {
                log.insert(Entry(message: msg), at: 0)
            }
            if !messages.isEmpty {
                saveLog()
            }
            isRunning = false
        }
    }

    private static func apply(installerDays: Int?, filesScreenshots: Bool) async -> [String] {
        await Task.detached {
            var messages: [String] = []
            let now = Date()
            if let days = installerDays {
                let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                let res = trashInstallers(in: downloads, olderThan: days, now: now, remove: moveToTrash)
                if res.count > 0 {
                    messages.append("Moved \(Fmt.plural(res.count, "old installer")) (\(Fmt.bytes(res.size))) to Trash")
                }
            }
            if filesScreenshots {
                let count = fileScreenshots(from: screenshotSources, into: screenshotFolder, now: now)
                if count > 0 {
                    messages.append("Filed \(Fmt.plural(count, "screenshot")) into Pictures › Screenshots")
                }
            }
            return messages
        }.value
    }

    public static func moveToTrash(_ url: URL) -> Bool {
        (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
    }

    public static func trashInstallers(
        in folder: URL,
        olderThan days: Int,
        now: Date = Date(),
        remove: (URL) -> Bool
    ) -> (count: Int, size: Int64) {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let installerExts: Set<String> = ["dmg", "pkg", "mpkg"]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }

        var count = 0
        var totalSize: Int64 = 0
        for url in urls where installerExts.contains(url.pathExtension.lowercased()) {
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mod = vals?.contentModificationDate ?? now
            let sz = Int64(vals?.fileSize ?? 0)
            if mod < cutoff && remove(url) {
                count += 1
                totalSize += sz
            }
        }
        return (count, totalSize)
    }

    public static func isScreenshot(_ url: URL) -> Bool {
        let attrName = "com.apple.metadata:kMDItemIsScreenCapture"
        if getxattr(url.path, attrName, nil, 0, 0, 0) > 0 {
            return true
        }
        let lower = url.lastPathComponent.lowercased()
        let imgExts: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]
        guard imgExts.contains(url.pathExtension.lowercased()) else { return false }
        return lower.hasPrefix("screenshot ") || lower.hasPrefix("screen shot ") || lower.hasPrefix("cleanshot ")
    }

    public static func fileScreenshots(from sources: [URL], into destination: URL, now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-86_400)
        let monthFmt = DateFormatter()
        monthFmt.locale = Locale(identifier: "en_US_POSIX")
        monthFmt.dateFormat = "yyyy-MM MMMM"

        var moved = 0
        let fm = FileManager.default
        for srcDir in sources {
            guard let urls = try? fm.contentsOfDirectory(
                at: srcDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where isScreenshot(url) {
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
                guard mod < cutoff else { continue }
                let folderName = monthFmt.string(from: mod)
                let monthFolder = destination.appendingPathComponent(folderName, isDirectory: true)
                try? fm.createDirectory(at: monthFolder, withIntermediateDirectories: true)
                let target = freeName(for: url.lastPathComponent, in: monthFolder)
                if (try? fm.moveItem(at: url, to: target)) != nil {
                    moved += 1
                }
            }
        }
        return moved
    }

    private static func freeName(for filename: String, in folder: URL) -> URL {
        let fm = FileManager.default
        let candidate = folder.appendingPathComponent(filename)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let ext = (filename as NSString).pathExtension
        let stem = (filename as NSString).deletingPathExtension
        for i in 2...999 {
            let nextName = ext.isEmpty ? "\(stem) \(i)" : "\(stem) \(i).\(ext)"
            let nextURL = folder.appendingPathComponent(nextName)
            if !fm.fileExists(atPath: nextURL.path) { return nextURL }
        }
        return candidate
    }
}

// MARK: - Auto Cleanup Settings View

public struct AutoCleanupSettings: View {
    @State private var rules = AutoCleanup.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Automatic Clean Up")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Findy checks once an hour while it's open. Files only ever go to the Trash.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Move old installers to the Trash")
                            .font(.system(size: 13, weight: .medium))
                        Text("Disk images (.dmg) and installer packages (.pkg) in Downloads after \(rules.installerDays) days.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $rules.installerDays) {
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                    .frame(width: 100)
                    Toggle("", isOn: $rules.trashesInstallers)
                        .labelsHidden()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("File screenshots by month")
                            .font(.system(size: 13, weight: .medium))
                        Text("Screenshots older than a day move from Desktop & Downloads into Pictures › Screenshots.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $rules.filesScreenshots)
                        .labelsHidden()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            }

            if !rules.log.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Activity")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(rules.log.prefix(5)) { entry in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.green)
                                .font(.system(size: 11))
                            Text(entry.message)
                                .font(.system(size: 12))
                            Spacer()
                            Text(Fmt.date(entry.date))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
