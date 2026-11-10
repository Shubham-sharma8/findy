import Foundation
import AppIntents
import AppKit

// MARK: - Siri & Shortcuts AppIntents

public struct FindFilesIntent: AppIntent {
    public static let title: LocalizedStringResource = "Find Files with Findy"
    public static let description = IntentDescription("Search your Mac using plain-English queries like 'pdfs from last week' or 'screenshots over 5 mb'.")

    @Parameter(title: "Search Query")
    public var query: String

    @Parameter(title: "Maximum Results", default: 20)
    public var limit: Int

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let store = LibraryStore()
        let (res, _, _) = await store.find(query, textIndex: nil, limit: max(1, min(100, limit)))
        let files = res.items.map { IntentFile(fileURL: $0.url, filename: $0.name) }
        return .result(value: files)
    }
}

public struct LatestDownloadIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Latest Download"
    public static let description = IntentDescription("Returns the most recently added file in your Downloads folder.")

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<IntentFile?> {
        let latest = RecentDownloads.load(limit: 1).first
        let file = latest.map { IntentFile(fileURL: $0.url, filename: $0.name) }
        return .result(value: file)
    }
}

public struct SearchInFindyIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Search in Findy"
    public static let description = IntentDescription("Opens Findy and searches for your query.")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "Query")
    public var query: String

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .findyOpenQuery, object: query)
        return .result()
    }
}

public struct FindyShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindFilesIntent(),
            phrases: [
                "Find files in \(.applicationName)",
                "Search \(.applicationName)"
            ],
            shortTitle: "Find Files",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: LatestDownloadIntent(),
            phrases: [
                "Get latest download with \(.applicationName)"
            ],
            shortTitle: "Latest Download",
            systemImageName: "arrow.down.circle"
        )
    }
}

extension Notification.Name {
    public static let findyOpenQuery = Notification.Name("FindyOpenQueryNotification")
}
