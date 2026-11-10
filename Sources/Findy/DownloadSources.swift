import Foundation
import SwiftUI

// MARK: - Download Source Model

public struct DownloadSource: Identifiable, Hashable, Sendable {
    public let name: String
    public let symbol: String
    public let domains: [String]
    public let keywords: [String]
    public var link: String?

    public var id: String { name }

    public init(name: String, symbol: String, domains: [String], keywords: [String], link: String? = nil) {
        self.name = name
        self.symbol = symbol
        self.domains = domains
        self.keywords = keywords
        self.link = link
    }

    public var spotlightClause: String {
        let clauses = domains.map { "kMDItemWhereFroms == '*\($0)*'c" }
        return "(" + clauses.joined(separator: " || ") + ")"
    }
}

// MARK: - Download Sources Classifier

public enum DownloadSources {
    public static let known: [DownloadSource] = [
        DownloadSource(name: "Google Drive", symbol: "externaldrive.fill", domains: ["drive.google.com", "drive.usercontent.google.com", "docs.google.com"], keywords: ["google drive", "gdrive", "drive"]),
        DownloadSource(name: "Slack", symbol: "bubble.left.and.bubble.right.fill", domains: ["slack.com", "slack-files.com", "slack-edge.com"], keywords: ["slack"]),
        DownloadSource(name: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", domains: ["github.com", "githubusercontent.com"], keywords: ["github"]),
        DownloadSource(name: "Dropbox", symbol: "shippingbox.fill", domains: ["dropbox.com", "dropboxusercontent.com"], keywords: ["dropbox"]),
        DownloadSource(name: "Notion", symbol: "doc.text.fill", domains: ["notion.so", "notion.site", "notion-static.com", "notionusercontent.com"], keywords: ["notion"]),
        DownloadSource(name: "ChatGPT", symbol: "sparkles", domains: ["chatgpt.com", "chat.openai.com", "oaiusercontent.com"], keywords: ["chatgpt", "openai"]),
        DownloadSource(name: "Claude", symbol: "sparkle", domains: ["claude.ai"], keywords: ["claude"]),
        DownloadSource(name: "Figma", symbol: "paintpalette.fill", domains: ["figma.com"], keywords: ["figma"]),
        DownloadSource(name: "Canva", symbol: "paintbrush.pointed.fill", domains: ["canva.com"], keywords: ["canva"]),
        DownloadSource(name: "Gmail", symbol: "envelope.fill", domains: ["mail.google.com"], keywords: ["gmail"]),
        DownloadSource(name: "Outlook", symbol: "envelope.badge.fill", domains: ["outlook.live.com", "outlook.office.com", "outlook.office365.com"], keywords: ["outlook", "hotmail"]),
        DownloadSource(name: "Discord", symbol: "gamecontroller.fill", domains: ["discord.com", "discordapp.com", "discordapp.net"], keywords: ["discord"]),
        DownloadSource(name: "WhatsApp", symbol: "message.fill", domains: ["whatsapp.com", "whatsapp.net"], keywords: ["whatsapp"]),
        DownloadSource(name: "Telegram", symbol: "paperplane.fill", domains: ["telegram.org", "t.me"], keywords: ["telegram"]),
        DownloadSource(name: "WeTransfer", symbol: "arrow.up.arrow.down", domains: ["wetransfer.com", "we.tl"], keywords: ["wetransfer"]),
        DownloadSource(name: "YouTube", symbol: "play.rectangle.fill", domains: ["youtube.com", "youtu.be", "googlevideo.com"], keywords: ["youtube"]),
        DownloadSource(name: "X / Twitter", symbol: "bird.fill", domains: ["x.com", "twitter.com", "twimg.com"], keywords: ["twitter", "x"]),
        DownloadSource(name: "Instagram", symbol: "camera.fill", domains: ["instagram.com", "cdninstagram.com"], keywords: ["instagram"]),
        DownloadSource(name: "Reddit", symbol: "bubble.left.fill", domains: ["reddit.com", "redd.it", "redditmedia.com"], keywords: ["reddit"]),
        DownloadSource(name: "LinkedIn", symbol: "briefcase.fill", domains: ["linkedin.com", "licdn.com"], keywords: ["linkedin"]),
        DownloadSource(name: "Pinterest", symbol: "pin.fill", domains: ["pinterest.com", "pinimg.com"], keywords: ["pinterest"]),
        DownloadSource(name: "Unsplash", symbol: "photo.fill", domains: ["unsplash.com"], keywords: ["unsplash"]),
        DownloadSource(name: "Facebook", symbol: "person.2.fill", domains: ["facebook.com", "fbcdn.net", "messenger.com"], keywords: ["facebook", "messenger"]),
        DownloadSource(name: "Zoom", symbol: "video.fill", domains: ["zoom.us"], keywords: ["zoom"]),
        DownloadSource(name: "iCloud", symbol: "icloud.fill", domains: ["icloud.com"], keywords: ["icloud"]),
        DownloadSource(name: "GoFullPage", symbol: "puzzlepiece.extension.fill", domains: ["fdpohaocaechififmbbbbbknoalclacl"], keywords: ["gofullpage"])
    ]

    public static func named(_ name: String) -> DownloadSource? {
        known.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public static func forKeyword(_ keyword: String) -> DownloadSource? {
        let lower = keyword.lowercased()
        return known.first { $0.keywords.contains(lower) || $0.name.lowercased() == lower }
    }

    public static func registrableDomain(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return urlString
        }
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return host }
        let sld = parts[parts.count - 2]
        let tld = parts[parts.count - 1]
        if ["co", "com", "org", "net", "edu", "gov", "ac"].contains(sld) && parts.count >= 3 {
            return "\(parts[parts.count - 3]).\(sld).\(tld)"
        }
        return "\(sld).\(tld)"
    }

    public static func whereFroms(_ url: URL) -> [String] {
        let attrName = "com.apple.metadata:kMDItemWhereFroms"
        let length = getxattr(url.path, attrName, nil, 0, 0, 0)
        guard length > 0 else { return [] }
        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes { ptr in
            getxattr(url.path, attrName, ptr.baseAddress, length, 0, 0)
        }
        guard result >= 0,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] else {
            return []
        }
        return plist.filter { !$0.isEmpty }
    }

    public static func classify(_ urls: [String]) -> DownloadSource? {
        guard !urls.isEmpty else { return nil }
        for raw in urls {
            let lower = raw.lowercased()
            for source in known {
                if source.domains.contains(where: { lower.contains($0) }) {
                    return source
                }
            }
            if lower.hasPrefix("chrome-extension://") || lower.hasPrefix("moz-extension://") || lower.hasPrefix("safari-web-extension://") {
                return DownloadSource(name: "Browser Extension", symbol: "puzzlepiece.extension.fill", domains: [raw], keywords: ["extension"])
            }
        }
        if let first = urls.first {
            let domain = registrableDomain(first)
            if !domain.isEmpty && domain.contains(".") {
                return DownloadSource(name: domain, symbol: "globe", domains: [domain], keywords: [domain], link: first)
            }
        }
        return nil
    }

    public static func source(for url: URL) -> DownloadSource? {
        classify(whereFroms(url))
    }
}

// MARK: - Source Store

@Observable
public final class SourceStore {
    public struct Group: Identifiable, Hashable, Sendable {
        public let source: DownloadSource
        public var items: [FileItem]
        public var id: String { source.name }
    }

    public var groups: [Group] = []
    public var loading: Bool = false
    public var hasLoaded: Bool = false
    private var loadedToken: Int = -1

    public init() {}

    public func group(named name: String) -> Group? {
        groups.first { $0.source.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public static func grouped(_ items: [FileItem]) -> [Group] {
        var map: [DownloadSource: [FileItem]] = [:]
        for item in items {
            if let src = DownloadSources.source(for: item.url) {
                map[src, default: []].append(item)
            }
        }
        return map.map { Group(source: $0.key, items: $0.value.sorted { $0.modified > $1.modified }) }
            .sorted { $0.items.count > $1.items.count }
    }

    @MainActor
    public func load(scopes: [URL], token: Int) async {
        guard token != loadedToken || !hasLoaded else { return }
        loadedToken = token
        loading = true
        let result = await Spotlight.run(
            "kMDItemWhereFroms == '*'",
            scopes: scopes,
            limit: 600,
            timeout: 4.0
        )
        let computed = await Task.detached {
            var seen = Set(result.items.map(\.url))
            var merged = result.items
            let downloadsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            if let urls = try? FileManager.default.contentsOfDirectory(
                at: downloadsURL,
                includingPropertiesForKeys: [.nameKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .contentTypeKey, .isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            ) {
                for url in urls.prefix(400) where !seen.contains(url) {
                    if !DownloadSources.whereFroms(url).isEmpty, let item = FileItem(url: url) {
                        seen.insert(url)
                        merged.append(item)
                    }
                }
            }
            return Self.grouped(merged)
        }.value
        self.groups = computed
        self.loading = false
        self.hasLoaded = true
    }

    public func remove(_ urls: Set<URL>) {
        groups = groups.compactMap { group in
            let remaining = group.items.filter { !urls.contains($0.url) }
            return remaining.isEmpty ? nil : Group(source: group.source, items: remaining)
        }
    }
}

// MARK: - Source Views

public struct SourceBadge: View {
    public let source: DownloadSource
    public var size: CGFloat = 12

    public init(source: DownloadSource, size: CGFloat = 12) {
        self.source = source
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: source.symbol)
                .font(.system(size: size * 0.85, weight: .semibold))
                .foregroundStyle(Theme.pastel(for: source.name))
            Text(source.name)
                .font(.system(size: size, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.pastel(for: source.name).opacity(0.12)))
    }
}

public struct SourceCard: View {
    public let group: SourceStore.Group
    @State private var hovering = false

    public init(group: SourceStore.Group) {
        self.group = group
    }

    public var body: some View {
        let tint = Theme.pastel(for: group.source.name)
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: group.source.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(group.source.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(Fmt.plural(group.items.count, "file"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(hovering ? 1.0 : 0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(hovering ? tint.opacity(0.45) : Theme.line, lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }
}

public struct SourcesSection: View {
    public var limit: Int = 6
    @Environment(AppState.self) private var state
    @Environment(SourceStore.self) private var sources

    public init(limit: Int = 6) {
        self.limit = limit
    }

    public var body: some View {
        if !sources.groups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle("Downloaded From", count: sources.groups.count, loading: sources.loading)
                    if sources.groups.count > limit {
                        Button("See All") {
                            state.selection = .sources
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                    ForEach(sources.groups.prefix(limit)) { group in
                        Button {
                            state.selection = .source(group.source.name)
                        } label: {
                            SourceCard(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

public struct SourcesHubView: View {
    @Environment(SourceStore.self) private var sources
    @Environment(LibraryStore.self) private var store
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloaded From")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Files you download in a browser remember where they came from.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                if sources.loading && sources.groups.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking at where your downloads came from…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else if sources.groups.isEmpty {
                    ContentUnavailableView(
                        "No Downloads Found",
                        systemImage: "arrow.down.circle",
                        description: Text("Files you download in a browser remember where they came from. None were found in your home folders.")
                    )
                    .frame(minHeight: 260)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(sources.groups) { group in
                            Button {
                                state.selection = .source(group.source.name)
                            } label: {
                                SourceCard(group: group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
        }
        .task(id: state.refreshToken) {
            await sources.load(scopes: store.scopes, token: state.refreshToken)
        }
    }
}

public struct SourceView: View {
    public let name: String
    @Environment(AppState.self) private var state
    @Environment(SourceStore.self) private var sources
    @Environment(LibraryStore.self) private var store

    public init(name: String) {
        self.name = name
    }

    public var body: some View {
        let items = sources.group(named: name)?.items ?? []
        FileBrowser(
            title: name,
            subtitle: "\(Fmt.plural(items.count, "file")) downloaded from \(name)",
            items: items,
            isLoading: sources.loading,
            totalCount: items.count,
            showsKindFilter: true,
            emptyTitle: "No downloaded files from \(name)",
            emptySymbol: "arrow.down.circle",
            emptyMessage: "Nothing from \(name) was found in your home folders.",
            onBack: { state.selection = .sources }
        )
        .task(id: state.refreshToken) {
            await sources.load(scopes: store.scopes, token: state.refreshToken)
        }
    }
}
