import SwiftUI
import AppKit

// MARK: - Theme Style & Settings

public enum ThemeStyle: String, CaseIterable, Identifiable, Sendable {
    case playful
    case minimal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .playful: return "Playful"
        case .minimal: return "Minimal"
        }
    }

    public var subtitle: String {
        switch self {
        case .playful: return "Colorful cards and warm gradients"
        case .minimal: return "Clean, quiet, neutral surfaces"
        }
    }
}

@Observable
public final class ThemeSettings {
    public static let shared = ThemeSettings()

    public var style: ThemeStyle {
        didSet {
            UserDefaults.standard.set(style.rawValue, forKey: "themeStyle")
        }
    }

    public init() {
        let raw = UserDefaults.standard.string(forKey: "themeStyle") ?? ThemeStyle.playful.rawValue
        self.style = ThemeStyle(rawValue: raw) ?? .playful
    }

    public func toggle() {
        style = (style == .playful) ? .minimal : .playful
    }
}

// MARK: - Theme Palette & Typography

public enum Theme {
    public static let green = Color(red: 0.18, green: 0.76, blue: 0.46)
    public static let star = Color(red: 0.96, green: 0.72, blue: 0.16)
    public static let accent = Color(red: 0.34, green: 0.46, blue: 0.96)
    public static let line = Color.primary.opacity(0.08)
    public static let ink = Color.primary

    public static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    public static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    public static func pastel(for seed: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.36, green: 0.62, blue: 0.96),
            Color(red: 0.96, green: 0.46, blue: 0.56),
            Color(red: 0.62, green: 0.44, blue: 0.96),
            Color(red: 0.24, green: 0.76, blue: 0.56),
            Color(red: 0.96, green: 0.62, blue: 0.26),
            Color(red: 0.24, green: 0.72, blue: 0.86)
        ]
        let hash = abs(seed.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) })
        return palette[hash % palette.count]
    }
}

extension FileCategory {
    public var tint: Color {
        gradient.first ?? Theme.accent
    }
}

// MARK: - App Icons & Safe Resource Helper

public enum AppResources {
    public static func logoImage() -> NSImage? {
        if let mainURL = Bundle.main.url(forResource: "Logo", withExtension: "png"),
           let img = NSImage(contentsOf: mainURL) {
            return img
        }
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Findy_Findy.bundle"),
            Bundle.main.bundleURL.appendingPathComponent("Findy_Findy.bundle"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("Findy_Findy.bundle")
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: candidate),
               let url = bundle.url(forResource: "Logo", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return nil
    }
}

public enum AppIcons {
    public static func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    public static func defaultApp(for item: FileItem) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: item.url) else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

// MARK: - Custom Folder Shape

public struct FolderShape: Shape {
    public var tabWidthFraction: CGFloat = 0.42
    public var tabHeight: CGFloat = 12
    public var radius: CGFloat = 14

    public init(tabWidthFraction: CGFloat = 0.42, tabHeight: CGFloat = 12, radius: CGFloat = 14) {
        self.tabWidthFraction = tabWidthFraction
        self.tabHeight = tabHeight
        self.radius = radius
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, rect.width * 0.2, rect.height * 0.2)
        let tabW = max(r * 2.5, rect.width * tabWidthFraction)
        let tabH = min(tabHeight, rect.height * 0.25)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + tabW - r * 0.6, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tabW + r * 0.4, y: rect.minY + tabH * 0.6),
            control: CGPoint(x: rect.minX + tabW, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tabW + r * 1.2, y: rect.minY + tabH),
            control: CGPoint(x: rect.minX + tabW + r * 0.6, y: rect.minY + tabH)
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY + tabH))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + tabH + r),
            control: CGPoint(x: rect.maxX, y: rect.minY + tabH)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Reusable UI Controls

public struct SectionTitle: View {
    public let title: String
    public var count: Int?
    public var loading: Bool = false

    public init(_ title: String, count: Int? = nil, loading: Bool = false) {
        self.title = title
        self.count = count
        self.loading = loading
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            if let count, count > 0 {
                Text("\(count.formatted())")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            if loading {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
        }
    }
}

public struct FilterPill<Content: View>: View {
    public let label: String
    public let value: String?
    public var active: Bool
    @ViewBuilder public let content: () -> Content

    public init(label: String, value: String? = nil, active: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.value = value
        self.active = active
        self.content = content
    }

    public var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 5) {
                Text(value ?? label)
                    .font(.system(size: 12, weight: active ? .semibold : .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(active ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule()
                    .strokeBorder(active ? Color.accentColor.opacity(0.4) : Theme.line, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

public struct DotsButton<MenuContent: View>: View {
    @ViewBuilder public let content: () -> MenuContent

    public init(@ViewBuilder content: @escaping () -> MenuContent) {
        self.content = content
    }

    public var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

public struct ThemeToggle: View {
    @Environment(ThemeSettings.self) private var settings

    public init() {}

    public var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                settings.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: settings.style == .playful ? "paintpalette.fill" : "circle.lefthalf.filled")
                    .font(.system(size: 12))
                    .foregroundStyle(settings.style == .playful ? Color.accentColor : .secondary)
                Text(settings.style.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .help(settings.style == .playful ? "Use Minimal Look (⌃⌘T)" : "Use Playful Look (⌃⌘T)")
    }
}

public struct WindowDragArea: NSViewRepresentable {
    public init() {}

    public final class DragView: NSView {
        public override var mouseDownCanMoveWindow: Bool { true }
        public override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    public func makeNSView(context: Context) -> DragView {
        DragView()
    }

    public func updateNSView(_ nsView: DragView, context: Context) {}
}

// MARK: - Findy Logo View

public struct FindyLogo: View {
    public var size: CGFloat = 32

    public init(size: CGFloat = 32) {
        self.size = size
    }

    public var body: some View {
        if let nsImage = AppResources.logoImage() {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.14, green: 0.16, blue: 0.42),
                                Color(red: 0.18, green: 0.56, blue: 0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: size * 0.52, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(red: 1.0, green: 0.82, blue: 0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: size, height: size)
        }
    }
}
