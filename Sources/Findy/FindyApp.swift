import SwiftUI
import AppKit
import Quartz

// MARK: - App Delegate

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconImage = AppResources.logoImage() {
            NSApp.applicationIconImage = iconImage
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc public override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    @objc public override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        Task { @MainActor in
            panel?.dataSource = QuickLook.shared
            panel?.delegate = QuickLook.shared
        }
    }

    @objc public override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel?.dataSource = nil
        panel?.delegate = nil
    }
}

// MARK: - Top Bar & Toast View

public struct TopBar: View {
    @Environment(AppState.self) private var state
    @Environment(LibraryStore.self) private var store
    @Environment(ThemeSettings.self) private var theme
    @FocusState private var searchFocused: Bool

    public init() {}

    private var librarySize: String {
        let count = FileCategory.allCases.reduce(0) { $0 + (store.collections[.category($1)]?.totalCount ?? 0) }
        let bytes = FileCategory.allCases.reduce(Int64(0)) { $0 + (store.collections[.category($1)]?.totalSize ?? 0) }
        guard count > 0 else { return "" }
        return "\(count.formatted()) files · \(Fmt.bytes(bytes))"
    }

    public var body: some View {
        @Bindable var bindableState = state
        HStack(spacing: 12) {
            if state.sidebarCollapsed {
                Spacer()
                    .frame(width: 62)

                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        state.sidebarCollapsed = false
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help("Show Sidebar")
            }

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("Search files, “pdfs from last week”, “screenshots over 5 mb”, or text inside images…", text: $bindableState.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)

                if !state.searchText.isEmpty {
                    Button {
                        state.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else if !searchFocused {
                    Text("⌘F")
                        .font(Theme.mono(10.5, .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: 520)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(searchFocused ? Color.accentColor : Theme.line, lineWidth: searchFocused ? 1.5 : 1)
            )

            Spacer()

            if !librarySize.isEmpty {
                Text(librarySize)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            // Card Size Controls (when in Grid mode)
            if state.viewMode == .grid {
                HStack(spacing: 4) {
                    Button {
                        if let smaller = state.cardSize.smaller {
                            state.cardSize = smaller
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.cardSize.smaller == nil)
                    .help("Smaller Cards (⌘-)")

                    Button {
                        if let bigger = state.cardSize.bigger {
                            state.cardSize = bigger
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.cardSize.bigger == nil)
                    .help("Larger Cards (⌘+)")
                }
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }

            // Refresh Button
            Button {
                state.refreshToken += 1
                state.showToast("Refreshed library", symbol: "arrow.clockwise")
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help("Refresh Library (⌘R)")

            // Theme Toggle
            ThemeToggle()

            // Inspector Toggle
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    state.showInspector.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(state.showInspector ? Color.accentColor : .secondary)
                    .frame(width: 30, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(state.showInspector ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle File Details Inspector (⌘I)")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                WindowDragArea()
            }
        )
        .onChange(of: state.focusSearchToken) { _, _ in
            searchFocused = true
        }
    }
}

public struct ToastView: View {
    public let toast: AppState.Toast

    public init(toast: AppState.Toast) {
        self.toast = toast
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(toast.message)
                .font(.system(size: 12.5, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        )
        .overlay(
            Capsule()
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }
}

// MARK: - Main Content View

public struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(LibraryStore.self) private var store
    @Environment(TextIndex.self) private var textIndex
    @Environment(CleanupStore.self) private var cleanup
    @Environment(DuplicateFinder.self) private var duplicates
    @Environment(SourceStore.self) private var sources
    @State private var keyMonitor: Any?

    public init() {}

    private var selectedFileItems: [FileItem] {
        let urls: [URL]
        if !state.selectedFiles.isEmpty {
            urls = Array(state.selectedFiles)
        } else if let focused = state.focusedItem {
            urls = [focused.url]
        } else {
            return []
        }
        return urls
            .compactMap { FileItem(url: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var body: some View {
        @Bindable var bindableState = state
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                if !state.sidebarCollapsed {
                    SidebarView()
                    Divider()
                }

                VStack(spacing: 0) {
                    TopBar()
                    Divider()
                    DetailView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if state.showInspector {
                    Divider()
                    InspectorView()
                }
            }

            if let toast = state.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 960, minHeight: 620)
        .sheet(isPresented: $bindableState.showBatchRename) {
            BatchRenameSheet(items: selectedFileItems) { count in
                state.clearSelection()
                state.refreshToken += 1
                state.showToast("Renamed \(Fmt.plural(count, "file"))", symbol: "pencil.and.list.clipboard")
            }
        }
        .sheet(
            isPresented: Binding(
                get: { state.previewItem != nil },
                set: { if !$0 { state.previewItem = nil } }
            )
        ) {
            PreviewSheet()
        }
        .task(id: state.searchText) {
            let q = state.searchText
            if q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await store.search("", textIndex: textIndex)
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await store.search(q, textIndex: textIndex)
        }
        .onAppear {
            installKeyboardHandler()
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findyOpenQuery)) { note in
            if let q = note.object as? String {
                state.searchText = q
            }
        }
    }

    private func installKeyboardHandler() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Never intercept keys when typing inside an NSText field editor
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSText {
                return event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Spacebar -> Toggle Preview Sheet / Quick Look
            if event.keyCode == 49 && flags.isEmpty {
                if state.previewItem != nil {
                    state.previewItem = nil
                    return nil
                } else if let focused = state.focusedItem {
                    state.preview(focused, in: selectedFileItems.isEmpty ? [focused] : selectedFileItems)
                    return nil
                }
            }

            // Escape -> Close preview or clear multi-selection
            if event.keyCode == 53 && flags.isEmpty {
                if state.previewItem != nil {
                    state.previewItem = nil
                    return nil
                } else if state.isSelecting || !state.selectedFiles.isEmpty {
                    state.clearSelection()
                    return nil
                }
            }

            // Command + Delete (⌘⌫) -> Move selected files to Trash
            if event.keyCode == 51 && flags == .command {
                let targets = selectedFileItems
                if !targets.isEmpty {
                    FileActions.trash(targets) { removed in
                        store.remove(removed)
                        cleanup.remove(removed)
                        duplicates.remove(removed)
                        sources.remove(removed)
                        FileShelf.shared.remove(removed)
                        textIndex.forget(removed)
                        state.clearSelection()
                        state.refreshToken += 1
                        state.showToast("Moved \(Fmt.plural(removed.count, "item")) to Trash", symbol: "trash")
                    }
                    return nil
                }
            }

            return event
        }
    }
}

// MARK: - Application Menu Commands

public struct FindyCommands: Commands {
    public let state: AppState
    public let theme: ThemeSettings
    public let textIndex: TextIndex

    public init(state: AppState, theme: ThemeSettings, textIndex: TextIndex) {
        self.state = state
        self.theme = theme
        self.textIndex = textIndex
    }

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Find Files…") {
                state.focusSearchToken += 1
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Quick Search Bar") {
                Task { @MainActor in
                    QuickSearch.shared.toggle()
                }
            }
            .keyboardShortcut(" ", modifiers: [.option])

            Button("Refresh Library") {
                state.refreshToken += 1
            }
            .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button("Copy Text from Image") {
                if let focused = state.focusedItem, TextRecognizer.canRead(focused) {
                    CopyText.run([focused], index: textIndex, state: state)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(state.focusedItem == nil)

            Button("Smart Batch Rename…") {
                if !state.selectedFiles.isEmpty || state.focusedItem != nil {
                    state.showBatchRename = true
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Add to File Shelf") {
                let urls: [URL] = !state.selectedFiles.isEmpty
                    ? Array(state.selectedFiles)
                    : (state.focusedItem.map { [$0.url] } ?? [])
                if !urls.isEmpty {
                    FileShelf.shared.addURLs(urls)
                    state.showToast("Added \(Fmt.plural(urls.count, "item")) to File Shelf", symbol: "tray.and.arrow.down.fill")
                }
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Button("Undo Last Batch Rename") {
                if let count = try? BatchRenamer.undoLastRename(), count > 0 {
                    state.refreshToken += 1
                    state.showToast("Undid rename of \(Fmt.plural(count, "file"))", symbol: "arrow.uturn.backward")
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .option])
        }

        CommandMenu("View") {
            Button(state.showInspector ? "Hide File Details" : "Show File Details") {
                state.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button("Open Space Lens") {
                state.searchText = ""
                state.selection = .spaceLens
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Divider()

            Button("Switch Theme (\(theme.style == .playful ? "Minimal" : "Playful"))") {
                theme.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .control])

            Divider()

            Button("Larger Cards") {
                if let bigger = state.cardSize.bigger {
                    state.cardSize = bigger
                }
            }
            .keyboardShortcut("+", modifiers: [.command])

            Button("Smaller Cards") {
                if let smaller = state.cardSize.smaller {
                    state.cardSize = smaller
                }
            }
            .keyboardShortcut("-", modifiers: [.command])
        }

        CommandMenu("Go") {
            Button("Home") {
                state.searchText = ""
                state.selection = .home
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Recents") {
                state.searchText = ""
                state.selection = .smart(.recents)
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Space Lens") {
                state.searchText = ""
                state.selection = .spaceLens
            }
            .keyboardShortcut("3", modifiers: [.command])

            Button("Clean Up") {
                state.searchText = ""
                state.selection = .cleanupHub
            }
            .keyboardShortcut("4", modifiers: [.command])

            Button("Duplicates") {
                state.searchText = ""
                state.selection = .duplicates
            }
            .keyboardShortcut("5", modifiers: [.command])

            Button("Downloaded From") {
                state.searchText = ""
                state.selection = .sources
            }
            .keyboardShortcut("6", modifiers: [.command])

            Button("File Shelf") {
                state.searchText = ""
                state.selection = .fileShelf
            }
            .keyboardShortcut("7", modifiers: [.command])
        }
    }
}

// MARK: - Findy App Entry Point

@main
public struct FindyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()
    @State private var store = LibraryStore()
    @State private var player = Player()
    @State private var textIndex = TextIndex()
    @State private var duplicates = DuplicateFinder()
    @State private var cleanup = CleanupStore()
    @State private var sources = SourceStore()
    @State private var shelf = FileShelf.shared
    @State private var theme = ThemeSettings.shared
    @State private var quickSearch = QuickSearch.shared
    @State private var autoCleanup = AutoCleanup.shared
    @AppStorage("showMenuBarDownloads") private var showMenuBarDownloads: Bool = true

    public init() {}

    public var body: some Scene {
        WindowGroup("Findy") {
            ContentView()
                .environment(state)
                .environment(store)
                .environment(player)
                .environment(textIndex)
                .environment(duplicates)
                .environment(cleanup)
                .environment(sources)
                .environment(shelf)
                .environment(theme)
                .environment(quickSearch)
                .environment(autoCleanup)
                .task {
                    quickSearch.start(state: state, store: store, textIndex: textIndex)
                    autoCleanup.start()
                    await MarketingTour.runIfRequested(
                        state: state,
                        store: store,
                        cleanup: cleanup,
                        duplicates: duplicates,
                        sources: sources,
                        shelf: shelf,
                        theme: theme
                    )
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            FindyCommands(state: state, theme: theme, textIndex: textIndex)
        }

        Settings {
            SettingsView()
                .environment(state)
                .environment(theme)
                .environment(quickSearch)
                .environment(autoCleanup)
        }

        MenuBarExtra("Findy Downloads", systemImage: "arrow.down.circle.fill", isInserted: $showMenuBarDownloads) {
            MenuBarDownloadsView(state: state)
                .environment(theme)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Automated Marketing Screenshot Tour

@MainActor
public enum MarketingTour {
    public static func runIfRequested(
        state: AppState,
        store: LibraryStore,
        cleanup: CleanupStore,
        duplicates: DuplicateFinder,
        sources: SourceStore,
        shelf: FileShelf,
        theme: ThemeSettings
    ) async {
        let args = CommandLine.arguments
        guard let flagIdx = args.firstIndex(of: "--marketing-tour"),
              flagIdx + 1 < args.count else { return }
        let outDir = URL(fileURLWithPath: args[flagIdx + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        try? await Task.sleep(for: .milliseconds(600))
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.center()
        window.makeKeyAndOrderFront(nil)

        // 1. Home Overview
        theme.style = .playful
        state.showInspector = false
        state.searchText = ""
        state.selection = .home
        try? await Task.sleep(for: .milliseconds(2800))
        capture(window: window, to: outDir.appendingPathComponent("01-findy-home-overview.png"))

        // 2. Natural-Language Search
        state.searchText = "images from this year"
        try? await Task.sleep(for: .milliseconds(2000))
        capture(window: window, to: outDir.appendingPathComponent("02-findy-natural-search.png"))

        // 3. Space Lens Storage Analyzer
        state.searchText = ""
        state.selection = .spaceLens
        try? await Task.sleep(for: .milliseconds(2200))
        capture(window: window, to: outDir.appendingPathComponent("03-findy-space-lens.png"))

        // 4. Smart Clean Up Hub
        state.selection = .cleanupHub
        try? await Task.sleep(for: .milliseconds(1800))
        capture(window: window, to: outDir.appendingPathComponent("04-findy-smart-cleanup.png"))

        // 5. Duplicate & Similar Photo Scanner
        state.selection = .duplicates
        try? await Task.sleep(for: .milliseconds(2400))
        capture(window: window, to: outDir.appendingPathComponent("05-findy-duplicate-finder.png"))

        // 6. Downloaded From Provenance
        state.selection = .sources
        try? await Task.sleep(for: .milliseconds(1800))
        capture(window: window, to: outDir.appendingPathComponent("06-findy-downloaded-from.png"))

        // 7. File Shelf / Drop Basket
        let savedShelfItems = shelf.items
        if shelf.items.isEmpty {
            let sampleItems = Array((store.collections[.smart(.recents)]?.items ?? []).prefix(5))
            shelf.add(sampleItems)
        }
        state.selection = .fileShelf
        try? await Task.sleep(for: .milliseconds(1400))
        capture(window: window, to: outDir.appendingPathComponent("07-findy-file-shelf.png"))
        if savedShelfItems.isEmpty {
            shelf.clear()
        }

        // 8. Recents + Developer File Inspector (SHA-256, UTI, POSIX, Finder Tags)
        state.selection = .smart(.recents)
        try? await Task.sleep(for: .milliseconds(1000))
        if let firstRecent = store.collections[.smart(.recents)]?.items.first {
            state.focusedItem = firstRecent
            state.selectedFiles = [firstRecent.url]
        }
        state.showInspector = true
        try? await Task.sleep(for: .milliseconds(1400))
        capture(window: window, to: outDir.appendingPathComponent("08-findy-file-inspector.png"))

        // Return to Home
        state.showInspector = false
        state.clearSelection()
        state.selection = .home
    }

    private static func capture(window: NSWindow, to url: URL) {
        guard let targetView = window.contentView?.superview ?? window.contentView else { return }
        targetView.layoutSubtreeIfNeeded()
        let bounds = targetView.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = targetView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        targetView.cacheDisplay(in: bounds, to: rep)
        if let pngData = rep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: url)
        }
    }
}
