import SwiftUI
import AppKit
import QuickLookThumbnailing

// MARK: - Thumbnail Model & Loader

public struct Thumbnail: Sendable {
    public let url: URL
    public let image: NSImage
    public let isIcon: Bool
}

public final class Thumbnails: @unchecked Sendable {
    public static let shared = Thumbnails()

    private final class Box: NSObject {
        let thumb: Thumbnail
        init(_ thumb: Thumbnail) { self.thumb = thumb }
    }

    private let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 450
        return c
    }()

    private init() {}

    private func key(for url: URL, side: CGFloat) -> NSString {
        let bucket = Int((side / 64.0).rounded(.up)) * 64
        return "\(url.path)#\(bucket)" as NSString
    }

    public func cached(_ url: URL, side: CGFloat) -> Thumbnail? {
        cache.object(forKey: key(for: url, side: side))?.thumb
    }

    public func load(_ url: URL, side: CGFloat) async -> Thumbnail? {
        if let existing = cached(url, side: side) {
            return existing
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let size = CGSize(width: max(64, side), height: max(64, side))
        let req = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: [.thumbnail, .icon]
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
                if let rep {
                    let thumb = Thumbnail(
                        url: url,
                        image: rep.nsImage,
                        isIcon: rep.type != .thumbnail
                    )
                    if let self {
                        self.cache.setObject(Box(thumb), forKey: self.key(for: url, side: side))
                    }
                    continuation.resume(returning: thumb)
                } else {
                    let icon = AppIcons.icon(for: url)
                    let fallback = Thumbnail(url: url, image: icon, isIcon: true)
                    continuation.resume(returning: fallback)
                }
            }
        }
    }
}

// MARK: - Thumbnail Views

public struct ThumbnailView: View {
    public let item: FileItem
    public var cornerRadius: CGFloat = 10
    @State private var thumb: Thumbnail?

    public init(item: FileItem, cornerRadius: CGFloat = 10) {
        self.item = item
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height, 80)
            content(thumb ?? Thumbnails.shared.cached(item.url, side: side), size: geo.size)
                .task(id: item.url) {
                    if thumb == nil {
                        thumb = await Thumbnails.shared.load(item.url, side: side)
                    }
                }
        }
    }

    @ViewBuilder
    private func content(_ t: Thumbnail?, size: CGSize) -> some View {
        if let t, !t.isIcon {
            Image(nsImage: t.image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            PlaceholderCover(
                item: item,
                icon: t?.image ?? AppIcons.icon(for: item.url),
                height: size.height
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

public struct FitThumbnail: View {
    public let item: FileItem
    public var isPlaying: Bool = false
    public var hovering: Bool = false
    @State private var thumb: Thumbnail?

    public init(item: FileItem, isPlaying: Bool = false, hovering: Bool = false) {
        self.item = item
        self.isPlaying = isPlaying
        self.hovering = hovering
    }

    public var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height, 140)
            let resolved = thumb ?? Thumbnails.shared.cached(item.url, side: side)
            ZStack {
                if let resolved, !resolved.isIcon {
                    Image(nsImage: resolved.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    PlaceholderCover(
                        item: item,
                        icon: resolved?.image ?? AppIcons.icon(for: item.url),
                        height: geo.size.height
                    )
                }

                if item.category == .videos || item.category == .music {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 34, height: 34)
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    .opacity(hovering || isPlaying ? 1.0 : 0.85)
                }
            }
            .task(id: item.url) {
                if thumb == nil {
                    thumb = await Thumbnails.shared.load(item.url, side: side)
                }
            }
        }
    }
}

public struct PlaceholderCover: View {
    public let item: FileItem
    public let icon: NSImage
    public let height: CGFloat

    public init(item: FileItem, icon: NSImage, height: CGFloat) {
        self.item = item
        self.icon = icon
        self.height = height
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    item.category.tint.opacity(0.14),
                    item.category.tint.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: min(64, height * 0.55), height: min(64, height * 0.55))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct PreviewStack: View {
    public let items: [FileItem]
    public var extra: Int = 0
    public var tint: Color = .accentColor

    public init(items: [FileItem], extra: Int = 0, tint: Color = .accentColor) {
        self.items = items
        self.extra = extra
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(items.prefix(3).enumerated()), id: \.element.url) { idx, file in
                ThumbnailView(item: file, cornerRadius: 7)
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(.background, lineWidth: 2)
                    )
                    .rotationEffect(.degrees(Double(idx - 1) * 4))
                    .zIndex(Double(3 - idx))
            }
        }
    }
}

public struct CategoryTile: View {
    public let category: FileCategory
    public let count: Int?
    public let size: Int64?
    @Environment(ThemeSettings.self) private var theme
    @State private var hovering = false

    public init(category: FileCategory, count: Int?, size: Int64?) {
        self.category = category
        self.count = count
        self.size = size
    }

    public var body: some View {
        let isPlayful = theme.style == .playful
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle()
                        .fill(isPlayful ? .white.opacity(0.22) : Color.primary.opacity(0.08))
                        .frame(width: 34, height: 34)
                    Image(systemName: category.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isPlayful ? .white : .primary)
                }
                Spacer()
                if let count {
                    Text("\(count.formatted())")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(isPlayful ? .white.opacity(0.9) : .secondary)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(isPlayful ? .white : .primary)
                Text(size.map { Fmt.bytes($0) } ?? "Scanning…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isPlayful ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(14)
        .frame(height: 102)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    isPlayful
                        ? AnyShapeStyle(LinearGradient(colors: category.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isPlayful ? .white.opacity(hovering ? 0.35 : 0.15) : Theme.line, lineWidth: 1)
        )
        .scaleEffect(hovering ? 1.015 : 1.0)
        .animation(.snappy(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }
}
