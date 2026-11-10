import SwiftUI
import AppKit

// MARK: - Settings View

public struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(ThemeSettings.self) private var theme
    @Environment(QuickSearch.self) private var quickSearch
    @Environment(AutoCleanup.self) private var autoCleanup
    @AppStorage("showMenuBarDownloads") private var showMenuBarDownloads: Bool = true

    public init() {}

    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape.fill")
                }

            AutoCleanupSettings()
                .tabItem {
                    Label("Auto Clean Up", systemImage: "sparkles")
                }

            shortcutsTab
                .tabItem {
                    Label("Shortcuts", systemImage: "square.stack.3d.up.fill")
                }

            aboutTab
                .tabItem {
                    Label("About Findy", systemImage: "info.circle.fill")
                }
        }
        .frame(width: 540, height: 420)
    }

    private var generalTab: some View {
        Form {
            Section("Appearance") {
                @Bindable var bindableTheme = theme
                Picker("Theme Style", selection: $bindableTheme.style) {
                    ForEach(ThemeStyle.allCases) { style in
                        Text("\(style.title) — \(style.subtitle)").tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Quick Search Bar") {
                @Bindable var bindableQS = quickSearch
                Toggle("Enable Global Quick Search", isOn: $bindableQS.isEnabled)
                HStack {
                    Text("Keyboard Shortcut")
                    Spacer()
                    ShortcutRecorder()
                }
            }

            Section("Menu Bar") {
                Toggle("Show Recent Downloads in Menu Bar", isOn: $showMenuBarDownloads)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutsTab: some View {
        Form {
            Section("Apple Shortcuts & Siri Integration") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Findy registers native App Intents so you can automate file discovery in macOS Shortcuts and Siri:")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)

                    shortcutCard("Find Files with Findy", "Run natural-language queries like “pdfs from last week” and pipe matching files into any Shortcut action.")
                    shortcutCard("Get Latest Download", "Instantly grab the newest file in your Downloads folder for quick sharing or archiving.")
                    shortcutCard("Open Search in Findy", "Launch Findy directly to a saved or dynamic search phrase.")

                    HStack {
                        Spacer()
                        Button("Open Shortcuts App") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutCard(_ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
            Text(desc)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer()
            if let nsImg = AppResources.logoImage() {
                Image(nsImage: nsImg)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 84, height: 84)
            } else {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Findy")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("Version 2.0.0 (Pro Unlocked · 100% Local & Private)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Re-engineered native macOS file companion with Natural-Language Spotlight + Disk Search, On-Device Vision OCR, Space Lens Storage Analyzer, Smart Batch Rename Studio, Finder Color Tags, and Duplicate & Clutter Clean Up.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 8) {
                Label("No Telemetry", systemImage: "lock.shield.fill")
                Text("·")
                Label("No License Gate", systemImage: "checkmark.seal.fill")
                Text("·")
                Label("Native SwiftUI", systemImage: "bolt.fill")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.green)

            Spacer()
        }
        .padding(24)
    }
}
