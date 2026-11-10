import Foundation
import SwiftUI
import AppKit
import Carbon

// MARK: - HotKey Model & Global Carbon HotKey Registration

public struct HotKey: Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public static let defaultHotKey = HotKey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonMods: UInt32 = 0
        if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if flags.contains(.control) { carbonMods |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        guard carbonMods != 0 else { return nil }
        self.keyCode = UInt32(event.keyCode)
        self.modifiers = carbonMods
    }

    public var display: String {
        var out = ""
        if (modifiers & UInt32(controlKey)) != 0 { out += "⌃" }
        if (modifiers & UInt32(optionKey)) != 0 { out += "⌥" }
        if (modifiers & UInt32(shiftKey)) != 0 { out += "⇧" }
        if (modifiers & UInt32(cmdKey)) != 0 { out += "⌘" }
        out += Self.keyName(for: keyCode)
        return out
    }

    public static func keyName(for code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        default: return "Key \(code)"
        }
    }
}

public final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

    public init(hotKey: HotKey, handler: @escaping () -> Void) {
        self.handler = handler
        register(hotKey)
    }

    deinit {
        unregister()
    }

    private func register(_ hotKey: HotKey) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    instance.handler()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x464E4459), id: 1) // 'FNDY'
        RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

// MARK: - Quick Search Controller & Panel

@Observable
public final class QuickSearch {
    @MainActor public static let shared = QuickSearch()

    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "findy.quickSearch.enabled")
            Task { @MainActor in
                self.rebind()
            }
        }
    }

    public var hotKey: HotKey {
        didSet {
            UserDefaults.standard.set(Int(hotKey.keyCode), forKey: "findy.quickSearch.keyCode")
            UserDefaults.standard.set(Int(hotKey.modifiers), forKey: "findy.quickSearch.modifiers")
            Task { @MainActor in
                self.rebind()
            }
        }
    }

    private var globalHotKey: GlobalHotKey?
    private var panel: QuickSearchPanel?
    private let model = QuickSearchModel()
    private weak var appState: AppState?
    private weak var store: LibraryStore?
    private weak var textIndex: TextIndex?

    public init() {
        let enabled = UserDefaults.standard.object(forKey: "findy.quickSearch.enabled") as? Bool ?? true
        let code = UserDefaults.standard.object(forKey: "findy.quickSearch.keyCode") as? Int
        let mods = UserDefaults.standard.object(forKey: "findy.quickSearch.modifiers") as? Int
        self.isEnabled = enabled
        if let code, let mods {
            self.hotKey = HotKey(keyCode: UInt32(code), modifiers: UInt32(mods))
        } else {
            self.hotKey = .defaultHotKey
        }
    }

    @MainActor
    public func start(state: AppState, store: LibraryStore, textIndex: TextIndex) {
        self.appState = state
        self.store = store
        self.textIndex = textIndex
        rebind()
    }

    @MainActor
    public func resetHotKey() {
        hotKey = .defaultHotKey
    }

    @MainActor
    private func rebind() {
        globalHotKey?.unregister()
        globalHotKey = nil
        guard isEnabled else { return }
        globalHotKey = GlobalHotKey(hotKey: hotKey) { [weak self] in
            Task { @MainActor in
                self?.toggle()
            }
        }
    }

    @MainActor
    public func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    @MainActor
    public func show() {
        if panel == nil {
            let p = QuickSearchPanel(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            p.contentView = NSHostingView(
                rootView: QuickSearchView(
                    model: model,
                    onOpen: { [weak self] item in
                        NSWorkspace.shared.open(item.url)
                        self?.hide()
                    },
                    onReveal: { [weak self] item in
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        self?.hide()
                    },
                    onShowInApp: { [weak self] query in
                        guard let self else { return }
                        self.appState?.searchText = query
                        NSApp.activate(ignoringOtherApps: true)
                        self.hide()
                    },
                    onClose: { [weak self] in
                        self?.hide()
                    }
                )
            )
            self.panel = p
        }

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - 320
            let y = frame.midY + 80
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    public func hide() {
        panel?.orderOut(nil)
    }
}

public final class QuickSearchPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
    }

    public override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }

    public override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

@Observable
public final class QuickSearchModel {
    public var query: String = ""
    public var results: [FileItem] = []
    public var chips: [String] = []
    public var selectedIndex: Int = 0
    public var isSearching: Bool = false

    private let store = LibraryStore()

    public init() {}

    public func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }

    @MainActor
    public func performSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            results = RecentDownloads.load(limit: 8)
            chips = []
            selectedIndex = 0
            isSearching = false
            return
        }
        isSearching = true
        let (res, parsed, _) = await store.find(q, textIndex: nil, limit: 25)
        results = res.items
        chips = parsed.chips
        selectedIndex = 0
        isSearching = false
    }
}

public struct QuickSearchView: View {
    @Bindable public var model: QuickSearchModel
    public let onOpen: (FileItem) -> Void
    public let onReveal: (FileItem) -> Void
    public let onShowInApp: (String) -> Void
    public let onClose: () -> Void
    @FocusState private var focused: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Find anything on your Mac…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .focused($focused)
                    .onSubmit {
                        if model.results.indices.contains(model.selectedIndex) {
                            let item = model.results[model.selectedIndex]
                            if NSEvent.modifierFlags.contains(.command) {
                                onReveal(item)
                            } else {
                                onOpen(item)
                            }
                        }
                    }
                    .onKeyPress(.downArrow) {
                        model.move(1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        model.move(-1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        onClose()
                        return .handled
                    }

                if model.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Esc") {
                    onClose()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(14)

            if !model.chips.isEmpty {
                UnderstoodChips(chips: model.chips)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { idx, item in
                        QuickResultRow(
                            item: item,
                            isSelected: idx == model.selectedIndex,
                            onOpen: { onOpen(item) },
                            onReveal: { onReveal(item) }
                        )
                    }
                }
                .padding(8)
            }

            Divider()

            HStack {
                Text("↩ Open · ⌘↩ Show in Finder")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.query.isEmpty {
                    Button("See all in Findy →") {
                        onShowInApp(model.query)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .task(id: model.query) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await model.performSearch()
        }
        .onAppear {
            focused = true
        }
    }
}

private struct QuickResultRow: View {
    let item: FileItem
    let isSelected: Bool
    let onOpen: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(item: item, cornerRadius: 6)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onReveal) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
        .onTapGesture(perform: onOpen)
    }
}

// MARK: - Shortcut Recorder for Settings

public struct ShortcutRecorder: View {
    @Environment(QuickSearch.self) private var quickSearch
    @State private var recording = false
    @State private var monitor: Any?

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            Button {
                if recording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(recording ? "Press shortcut…" : quickSearch.hotKey.display)
                    .font(Theme.mono(12, .semibold))
                    .frame(minWidth: 95)
            }
            .buttonStyle(.bordered)

            if quickSearch.hotKey != .defaultHotKey {
                Button("Reset") {
                    quickSearch.resetHotKey()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            if let hk = HotKey(event: event) {
                quickSearch.hotKey = hk
                stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
