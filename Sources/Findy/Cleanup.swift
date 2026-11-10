import Foundation
import SwiftUI

// MARK: - Cleanup Kind

public enum CleanupKind: String, CaseIterable, Identifiable, Sendable {
    case installers
    case oldDownloads
    case oldScreenshots
    case bigOldVideos
    case unusedApps

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .installers: return "Old Installers"
        case .oldDownloads: return "Forgotten Downloads"
        case .oldScreenshots: return "Old Screenshots"
        case .bigOldVideos: return "Big Old Videos"
        case .unusedApps: return "Unused Apps"
        }
    }

    public var symbol: String {
        switch self {
        case .installers: return "shippingbox.fill"
        case .oldDownloads: return "arrow.down.circle.fill"
        case .oldScreenshots: return "camera.viewfinder"
        case .bigOldVideos: return "film.stack.fill"
        case .unusedApps: return "app.dashed"
        }
    }

    public var detail: String {
        switch self {
        case .installers:
            return "Disk images and installer packages older than a week. Once an app is installed, these are just taking up space."
        case .oldDownloads:
            return "Loose files in Downloads you haven't opened or changed in 3 months. Folders inside Downloads are left alone."
        case .oldScreenshots:
            return "Screenshots older than 30 days. Most were only needed for a moment."
        case .bigOldVideos:
            return "Videos over 200 MB you haven't opened in 6 months."
        case .unusedApps:
            return "Apps you haven't opened in 6 months, or ever."
        }
    }

    public var tint: Color {
        switch self {
        case .installers: return Color(red: 0.94, green: 0.52, blue: 0.22)
        case .oldDownloads: return Color(red: 0.24, green: 0.58, blue: 0.96)
        case .oldScreenshots: return Color(red: 0.88, green: 0.34, blue: 0.62)
        case .bigOldVideos: return Color(red: 0.56, green: 0.36, blue: 0.94)
        case .unusedApps: return Color(red: 0.20, green: 0.72, blue: 0.78)
        }
    }

    public var spotlightQuery: String {
        switch self {
        case .installers:
            return "(kMDItemFSName == '*.dmg'c || kMDItemFSName == '*.pkg'c || kMDItemFSName == '*.mpkg'c) && kMDItemFSContentChangeDate < $time.today(-7)"
        case .oldDownloads:
            return "kMDItemContentTypeTree != 'public.folder' && kMDItemFSContentChangeDate < $time.today(-90) && (kMDItemLastUsedDate < $time.today(-90) || kMDItemLastUsedDate != *)"
        case .oldScreenshots:
            return "kMDItemIsScreenCapture == 1 && kMDItemFSContentChangeDate < $time.today(-30)"
        case .bigOldVideos:
            return "kMDItemContentTypeTree == 'public.movie' && kMDItemFSName != '*.ts'c && kMDItemFSSize > 200000000 && kMDItemFSContentChangeDate < $time.today(-180) && (kMDItemLastUsedDate < $time.today(-180) || kMDItemLastUsedDate != *)"
        case .unusedApps:
            return "kMDItemContentTypeTree == 'com.apple.application-bundle' && (kMDItemLastUsedDate < $time.today(-180) || kMDItemLastUsedDate != *)"
        }
    }
}

// MARK: - Cleanup Store

@Observable
public final class CleanupStore {
    public var results: [CleanupKind: SpotlightResult] = [:]
    public var loading: Bool = false
    private var loadedToken: Int = -1

    public init() {}

    public var totalReclaimable: Int64 {
        results.values.reduce(0) { $0 + $1.totalSize }
    }

    @MainActor
    public func load(scopes: [URL], token: Int) async {
        guard token != loadedToken || results.isEmpty else { return }
        loadedToken = token
        loading = true
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let apps = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]

        await withTaskGroup(of: (CleanupKind, SpotlightResult).self) { group in
            for kind in CleanupKind.allCases {
                let kindScopes: [URL]
                switch kind {
                case .installers, .oldDownloads:
                    kindScopes = [downloads]
                case .unusedApps:
                    kindScopes = apps
                default:
                    kindScopes = scopes
                }
                group.addTask { @MainActor in
                    let res = await Spotlight.run(kind.spotlightQuery, scopes: kindScopes, limit: 250, timeout: 3.5)
                    return (kind, res)
                }
            }
            for await (kind, res) in group {
                results[kind] = res
            }
        }
        loading = false
    }

    public func remove(_ urls: Set<URL>) {
        for (kind, var val) in results {
            val.items.removeAll { urls.contains($0.url) }
            val.totalCount = val.items.count
            val.totalSize = val.items.reduce(0) { $0 + $1.size }
            results[kind] = val
        }
    }
}

// MARK: - Cleanup Views

public struct SuggestionCard: View {
    public let symbol: String
    public let tint: Color
    public let title: String
    public let headline: String
    public let detail: String
    public var previews: [FileItem] = []
    public var busy: Bool = false
    @State private var hovering = false

    public init(symbol: String, tint: Color, title: String, headline: String, detail: String, previews: [FileItem] = [], busy: Bool = false) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.headline = headline
        self.detail = detail
        self.previews = previews
        self.busy = busy
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.16))
                        .frame(width: 36, height: 36)
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Spacer()
                if busy {
                    ProgressView().controlSize(.small)
                } else if !previews.isEmpty {
                    PreviewStack(items: previews, tint: tint)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(headline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(hovering ? tint.opacity(0.5) : Theme.line, lineWidth: 1)
        )
        .scaleEffect(hovering ? 1.01 : 1.0)
        .animation(.snappy(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }
}

public struct CleanupSection: View {
    public var showsHeader: Bool = true
    @Environment(AppState.self) private var state
    @Environment(CleanupStore.self) private var cleanup
    @Environment(DuplicateFinder.self) private var finder

    public init(showsHeader: Bool = true) {
        self.showsHeader = showsHeader
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                HStack {
                    SectionTitle("Clean Up", loading: cleanup.loading)
                    if cleanup.totalReclaimable + finder.exactReclaimable > 0 {
                        Text("Free up to \(Fmt.bytes(cleanup.totalReclaimable + finder.exactReclaimable))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.green)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                Button {
                    state.selection = .duplicates
                } label: {
                    SuggestionCard(
                        symbol: "square.on.square",
                        tint: Color(red: 0.34, green: 0.56, blue: 0.96),
                        title: "Duplicates",
                        headline: finder.exactReclaimable > 0
                            ? "\(Fmt.bytes(finder.exactReclaimable)) · \(finder.extraCopies) copies"
                            : "Find identical files",
                        detail: "Identical copies and look-alike photos across your home folders",
                        previews: finder.exact.flatMap(\.files),
                        busy: finder.phase == .gathering || finder.phase == .hashing
                    )
                }
                .buttonStyle(.plain)

                ForEach(CleanupKind.allCases) { kind in
                    let res = cleanup.results[kind]
                    Button {
                        state.selection = .cleanup(kind)
                    } label: {
                        SuggestionCard(
                            symbol: kind.symbol,
                            tint: kind.tint,
                            title: kind.title,
                            headline: (res?.totalSize ?? 0) > 0
                                ? "\(Fmt.bytes(res?.totalSize ?? 0)) · \(Fmt.plural(res?.totalCount ?? 0, "file"))"
                                : "All Clean",
                            detail: kind.detail,
                            previews: res?.items ?? [],
                            busy: cleanup.loading && res == nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

public struct CleanupHubView: View {
    @Environment(CleanupStore.self) private var cleanup
    @Environment(DuplicateFinder.self) private var finder
    @Environment(LibraryStore.self) private var store
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clean Up")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    let total = cleanup.totalReclaimable + finder.exactReclaimable
                    Text(total > 0 ? "You could free up to \(Fmt.bytes(total)). Nothing is deleted without asking." : "Your Mac looks tidy. Files only ever go to the Trash.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                CleanupSection(showsHeader: false)

                Divider()

                AutoCleanupSettings()
            }
            .padding(24)
        }
        .task(id: state.refreshToken) {
            await cleanup.load(scopes: store.scopes, token: state.refreshToken)
        }
    }
}

public struct CleanupReviewView: View {
    public let kind: CleanupKind
    @Environment(AppState.self) private var state
    @Environment(LibraryStore.self) private var store
    @Environment(CleanupStore.self) private var cleanup
    @Environment(DuplicateFinder.self) private var finder
    @Environment(TextIndex.self) private var textIndex

    @State private var confirm = false

    public init(kind: CleanupKind) {
        self.kind = kind
    }

    public var body: some View {
        let items = cleanup.results[kind]?.items ?? []
        let selected = items.filter { state.selectedFiles.contains($0.url) }
        let targets = selected.isEmpty ? items : selected
        let targetBytes = targets.reduce(Int64(0)) { $0 + $1.size }

        FileBrowser(
            title: kind.title,
            subtitle: kind.detail,
            items: items,
            isLoading: cleanup.loading,
            totalCount: items.count,
            showsKindFilter: false,
            emptyTitle: "Nothing to clean up here.",
            emptySymbol: "checkmark.seal.fill",
            emptyMessage: "Your Mac looks tidy.",
            onBack: { state.selection = .cleanupHub },
            accessory: {
                if !items.isEmpty {
                    Button(role: .destructive) {
                        confirm = true
                    } label: {
                        Label(
                            selected.isEmpty
                                ? "Trash All (\(Fmt.bytes(targetBytes)))"
                                : "Trash Selected (\(Fmt.bytes(targetBytes)))",
                            systemImage: "trash"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        )
        .confirmationDialog(
            "Move \(Fmt.plural(targets.count, "item")) to the Trash?",
            isPresented: $confirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash (\(Fmt.bytes(targetBytes)))", role: .destructive) {
                FileActions.trash(targets) { removed in
                    cleanup.remove(removed)
                    store.remove(removed)
                    finder.remove(removed)
                    textIndex.forget(removed)
                    state.clearSelection()
                    state.showToast("Moved \(removed.count) items to Trash")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Files go to the Trash, so you can always put them back.")
        }
        .task(id: state.refreshToken) {
            await cleanup.load(scopes: store.scopes, token: state.refreshToken)
        }
    }
}
