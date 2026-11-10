# Contributing to Findy

Thank you for contributing to **Findy**! Findy is an open-source, 100% local and private macOS file companion built with Swift 5.9, SwiftUI, and AppKit.

## Prerequisites

- **macOS 14.0 (Sonoma)** or later
- **Xcode 15.4+** or Swift 5.9+ toolchain

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/Findy.git
   cd Findy
   ```

2. Run the test suite:
   ```bash
   swift test
   ```

3. Build and install `Findy.app` to `/Applications`:
   ```bash
   ./build-app.sh --install
   ```

## Project Structure

```text
Findy/
├── Assets/
│   ├── AppIcon.icns           # Multi-resolution macOS application icon
│   └── FindyIcon1024.png      # 1024x1024 master icon artwork
├── Sources/Findy/
│   ├── FindyApp.swift         # App entry point, TopBar, ContentView, Menu Commands
│   ├── Models.swift           # FileItem, FileCategory, FinderTag, formatting helpers
│   ├── Library.swift          # Spotlight NSMetadataQuery engine, DiskSearch, AppState
│   ├── NaturalSearch.swift    # Plain-English query parser -> ParsedQuery
│   ├── TextRecognition.swift  # On-device Vision OCR & PDF text indexer
│   ├── DownloadSources.swift  # kMDItemWhereFroms provenance classifier (40+ sources)
│   ├── SpaceLens.swift        # Visual storage treemap & largest-files analyzer
│   ├── BatchRename.swift      # Multi-file regex/token/sequence rename studio
│   ├── Duplicates.swift       # Multi-stage SHA-256 + Vision perceptual photo deduplicator
│   ├── Cleanup.swift          # Smart clutter rules & reclaimable storage hub
│   ├── AutoCleanup.swift      # Background installer & screenshot organizer
│   ├── QuickSearch.swift      # Global Carbon hotkey (⌥Space) floating search panel
│   ├── QuickLook.swift        # Native QLPreviewPanel controller
│   ├── Player.swift           # Built-in AVPlayer & sidebar MiniPlayer
│   ├── InspectorView.swift    # File details inspector (⌘I) with SHA-256 & Live Text
│   ├── HomeView.swift         # Dashboard shelves, categories & Spotlight health check
│   ├── BrowserView.swift      # Grid/List browser, filter pills, multi-selection bar
│   ├── SidebarView.swift      # Navigation sidebar, saved searches & Finder tags
│   ├── Cards.swift            # Gallery cards, file rows & custom FolderShape
│   ├── Theme.swift            # Playful & Minimal themes, Safe AppResources loader
│   ├── FileActions.swift      # Context menu, Finder tags, Terminal & Trash actions
│   ├── SavedSearches.swift    # Persistent sidebar search bookmarks
│   ├── MenuBarDownloads.swift # MenuBarExtra recent downloads popover
│   ├── Intents.swift          # Apple Shortcuts & Siri AppIntents
│   └── SettingsView.swift     # Preferences window
└── Tests/FindyTests/
    └── FindyTests.swift       # Unit tests for search, deduplication, rename & Space Lens
```

## Coding Guidelines

- **Privacy First**: Never add telemetry, analytics, or external network calls. All indexing, OCR, and deduplication must happen strictly on-device.
- **Safe File Operations**: Destructive actions must move files to the macOS Trash (`FileManager.default.trashItem`) rather than permanently unlinking files.
- **Value Semantics**: Prefer immutable `Sendable` structs (`FileItem`, `ParsedQuery`, `BatchRenameRule`, `SpaceLensSummary`) for data models.
- **Tests Required**: Every new parser rule, file operation, or analyzer must include unit tests in `Tests/FindyTests/FindyTests.swift`.

## Pull Request Process

1. Create a feature branch (`git checkout -b feat/your-feature`).
2. Ensure all tests pass (`swift test`).
3. Verify the release app bundle builds cleanly (`./build-app.sh`).
4. Open a Pull Request with a clear summary of changes.
