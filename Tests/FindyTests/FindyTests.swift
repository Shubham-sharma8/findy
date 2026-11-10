import XCTest
import UniformTypeIdentifiers
#if canImport(Findy)
@testable import Findy
#endif

final class FindyTests: XCTestCase {

    // MARK: - Models & Formatting Tests

    func testFileCategoryClassificationAndQueries() {
        XCTAssertEqual(FileCategory.classify(.png, isDirectory: false), .images)
        XCTAssertEqual(FileCategory.classify(.mpeg4Movie, isDirectory: false), .videos)
        XCTAssertEqual(FileCategory.classify(.mp3, isDirectory: false), .music)
        XCTAssertEqual(FileCategory.classify(.pdf, isDirectory: false), .documents)
        XCTAssertEqual(FileCategory.classify(.zip, isDirectory: false), .archives)
        XCTAssertEqual(FileCategory.classify(.applicationBundle, isDirectory: true), .apps)
        XCTAssertEqual(FileCategory.classify(.swiftSource, isDirectory: false), .code)
        XCTAssertEqual(FileCategory.classify(.folder, isDirectory: true), .folders)
        XCTAssertEqual(FileCategory.classify(nil, isDirectory: false), .other)

        for cat in FileCategory.allCases {
            XCTAssertFalse(cat.title.isEmpty)
            XCTAssertFalse(cat.symbol.isEmpty)
            XCTAssertFalse(cat.spotlightQuery.isEmpty)
            XCTAssertNotNil(NSPredicate(fromMetadataQueryString: cat.spotlightQuery), "Invalid Spotlight query for \(cat)")
            XCTAssertEqual(cat.gradient.count, 2)
        }

        for kind in CleanupKind.allCases {
            XCTAssertNotNil(NSPredicate(fromMetadataQueryString: kind.spotlightQuery), "Invalid Spotlight query for \(kind)")
        }
    }

    func testCardSizeSteppingAndColumns() {
        XCTAssertNil(CardSize.xsmall.smaller)
        XCTAssertEqual(CardSize.xsmall.bigger, .small)
        XCTAssertEqual(CardSize.medium.smaller, .small)
        XCTAssertEqual(CardSize.medium.bigger, .large)
        XCTAssertNil(CardSize.xlarge.bigger)

        let colsSmall = CardSize.columns(for: .small, in: 900, spacing: 14)
        let colsLarge = CardSize.columns(for: .large, in: 900, spacing: 14)
        XCTAssertGreaterThan(colsSmall, colsLarge)
    }

    func testFormattingHelpers() {
        XCTAssertEqual(Fmt.duration(65), "1:05")
        XCTAssertEqual(Fmt.duration(3661), "1:01:01")
        XCTAssertEqual(Fmt.plural(1, "file"), "1 file")
        XCTAssertEqual(Fmt.plural(5, "file"), "5 files")
    }

    // MARK: - Natural Language Search Parser Tests

    func testNaturalSearchParsesKindDateAndSize() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_762_700_000) // fixed reference date

        let q1 = NaturalSearch.parse("pdfs from last week over 5 mb", now: now, calendar: cal)
        XCTAssertEqual(q1.category, .documents)
        XCTAssertTrue(q1.extensions.contains("pdf"))
        XCTAssertNotNil(q1.after)
        XCTAssertEqual(q1.minSize, 5 * 1_000_000)
        XCTAssertTrue(q1.isStructured)
        XCTAssertFalse(q1.chips.isEmpty)
        XCTAssertTrue(q1.spotlightQuery.contains("kMDItemFSSize >="))
        XCTAssertNotNil(NSPredicate(fromMetadataQueryString: q1.spotlightQuery))

        let q2 = NaturalSearch.parse("screenshots from yesterday under 10 mb", now: now, calendar: cal)
        XCTAssertTrue(q2.screenshotsOnly)
        XCTAssertNotNil(q2.after)
        XCTAssertEqual(q2.maxSize, 10 * 1_000_000)

        let q3 = NaturalSearch.parse("videos from slack in downloads", now: now, calendar: cal)
        XCTAssertEqual(q3.category, .videos)
        XCTAssertEqual(q3.source?.name, "Slack")
        XCTAssertEqual(q3.folder?.title, "Downloads")

        let q4 = NaturalSearch.parse("photos shot on iphone in 2025 tagged red", now: now, calendar: cal)
        XCTAssertEqual(q4.category, .images)
        XCTAssertEqual(q4.camera?.lowercased(), "iphone")
        XCTAssertNotNil(q4.after)
        XCTAssertNotNil(q4.before)
        XCTAssertEqual(q4.tag, .red)
    }

    func testParsedQueryMatchingAgainstFileItems() {
        let now = Date()
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/invoice_2026.pdf"),
            name: "invoice_2026.pdf",
            size: 8_000_000,
            modified: now,
            created: now,
            contentType: .pdf,
            category: .documents,
            tags: ["Red"]
        )

        let matching = NaturalSearch.parse("invoice pdfs over 5 mb tagged red", now: now)
        XCTAssertTrue(matching.matches(item))

        let nonMatchingSize = NaturalSearch.parse("invoice pdfs under 1 mb", now: now)
        XCTAssertFalse(nonMatchingSize.matches(item))
    }

    // MARK: - Download Sources Classification Tests

    func testDownloadSourcesClassification() {
        XCTAssertEqual(DownloadSources.registrableDomain("https://drive.usercontent.google.com/download?id=123"), "google.com")
        XCTAssertEqual(DownloadSources.classify(["https://files.slack.com/files-pri/T1/report.pdf"])?.name, "Slack")
        XCTAssertEqual(DownloadSources.classify(["https://raw.githubusercontent.com/org/repo/main/README.md"])?.name, "GitHub")
        XCTAssertEqual(DownloadSources.classify(["https://www.figma.com/file/abc"])?.name, "Figma")
        XCTAssertEqual(DownloadSources.classify(["chrome-extension://fdpohaocaechififmbbbbbknoalclacl/capture.png"])?.name, "GoFullPage")
        XCTAssertNotNil(DownloadSources.named("Google Drive"))
        XCTAssertEqual(DownloadSources.forKeyword("chatgpt")?.name, "ChatGPT")
    }

    // MARK: - Duplicate Scanner Tests

    func testDuplicateScannerExactDuplicatesAndKeeperSelection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let payload = Data(repeating: 0x42, count: 64_000) // >= 51200 bytes
        let originalURL = tempDir.appendingPathComponent("Budget.pdf")
        let copyURL = tempDir.appendingPathComponent("Budget (1).pdf")
        let uniqueURL = tempDir.appendingPathComponent("Unique.pdf")

        try payload.write(to: originalURL)
        try payload.write(to: copyURL)
        try Data(repeating: 0x99, count: 64_000).write(to: uniqueURL)

        let items = [originalURL, copyURL, uniqueURL].compactMap { FileItem(url: $0) }
        XCTAssertEqual(items.count, 3)

        let groups = DuplicateScanner.exactDuplicates(items) { _, _ in }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 2)
        // Keeper should prefer "Budget.pdf" over "Budget (1).pdf"
        XCTAssertEqual(groups[0].keep.lastPathComponent, "Budget.pdf")
        XCTAssertEqual(groups[0].extras.count, 1)
        XCTAssertEqual(groups[0].extras.first?.url.lastPathComponent, "Budget (1).pdf")
    }

    // MARK: - AutoCleanup Logic Tests

    func testAutoCleanupTrashInstallersAndFileScreenshots() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloadsDir = tempDir.appendingPathComponent("Downloads")
        let screenshotsDest = tempDir.appendingPathComponent("Screenshots")
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: screenshotsDest, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let now = Date()
        let tenDaysAgo = now.addingTimeInterval(-10 * 86_400)
        let oldDmg = downloadsDir.appendingPathComponent("OldInstaller.dmg")
        let newDmg = downloadsDir.appendingPathComponent("FreshInstaller.dmg")
        try Data("dmg-old".utf8).write(to: oldDmg)
        try Data("dmg-new".utf8).write(to: newDmg)
        try FileManager.default.setAttributes([.modificationDate: tenDaysAgo], ofItemAtPath: oldDmg.path)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: newDmg.path)

        var removedURLs: [URL] = []
        let res = AutoCleanup.trashInstallers(in: downloadsDir, olderThan: 7, now: now) { url in
            removedURLs.append(url)
            return true
        }
        XCTAssertEqual(res.count, 1)
        XCTAssertEqual(removedURLs.first?.lastPathComponent, "OldInstaller.dmg")

        let shot = downloadsDir.appendingPathComponent("Screenshot 2026-01-15 at 10.00.00.png")
        try Data("png".utf8).write(to: shot)
        try FileManager.default.setAttributes([.modificationDate: tenDaysAgo], ofItemAtPath: shot.path)
        XCTAssertTrue(AutoCleanup.isScreenshot(shot))

        let movedCount = AutoCleanup.fileScreenshots(from: [downloadsDir], into: screenshotsDest, now: now)
        XCTAssertEqual(movedCount, 1)
    }

    // MARK: - Improved Feature: Batch Renamer Tests

    func testBatchRenamerPreviewAndApply() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let f1 = tempDir.appendingPathComponent("IMG 01.jpg")
        let f2 = tempDir.appendingPathComponent("IMG 02.jpg")
        try Data("1".utf8).write(to: f1)
        try Data("2".utf8).write(to: f2)

        let items = [f1, f2].compactMap { FileItem(url: $0) }
        let rule = BatchRenameRule(
            findText: "IMG ",
            replaceText: "Trip_",
            prefix: "2026_",
            suffix: "_final",
            addSequence: true,
            sequenceStart: 1,
            sequenceDigits: 2,
            caseTransform: .lowercase
        )

        let previews = BatchRenamer.preview(items: items, rule: rule)
        XCTAssertEqual(previews.count, 2)
        XCTAssertEqual(previews[0].newName, "2026_trip_01_final_01.jpg")
        XCTAssertEqual(previews[1].newName, "2026_trip_02_final_02.jpg")

        let renamedURLs = try BatchRenamer.apply(previews: previews)
        XCTAssertEqual(renamedURLs.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURLs[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURLs[1].path))
    }

    // MARK: - Improved Feature: Space Lens Analyzer Tests

    func testSpaceLensBreakdown() {
        let now = Date()
        let items = [
            FileItem(url: URL(fileURLWithPath: "/Users/test/Movies/film.mp4"), name: "film.mp4", size: 500_000_000, modified: now, created: now, contentType: .mpeg4Movie, category: .videos),
            FileItem(url: URL(fileURLWithPath: "/Users/test/Pictures/photo.png"), name: "photo.png", size: 100_000_000, modified: now, created: now, contentType: .png, category: .images),
            FileItem(url: URL(fileURLWithPath: "/Users/test/Documents/spec.pdf"), name: "spec.pdf", size: 25_000_000, modified: now, created: now, contentType: .pdf, category: .documents)
        ]

        let summary = SpaceLensAnalyzer.analyze(items: items)
        XCTAssertEqual(summary.totalBytes, 625_000_000)
        XCTAssertEqual(summary.categorySlices.first?.category, .videos)
        XCTAssertEqual(summary.largestFiles.first?.name, "film.mp4")
        XCTAssertGreaterThan(summary.categorySlices.first?.fraction ?? 0, 0.75)
        XCTAssertFalse(summary.folderSlices.isEmpty)
        XCTAssertEqual(summary.folderSlices.first?.folderName, "Movies")
    }

    // MARK: - Bug Fix & New Feature Tests (Round 2)

    func testNaturalSearchSpotlightQueryUsesISODatesForBothAttributes() {
        let now = Date(timeIntervalSince1970: 1_762_700_000)
        let parsed = NaturalSearch.parse("pdfs from yesterday", now: now)
        let query = parsed.spotlightQuery
        XCTAssertTrue(query.contains("kMDItemFSContentChangeDate >= $time.iso("))
        XCTAssertTrue(query.contains("kMDItemContentCreationDate >= $time.iso("))
        XCTAssertTrue(query.contains("kMDItemContentCreationDate < $time.iso("))
        XCTAssertNotNil(NSPredicate(fromMetadataQueryString: query))
    }

    func testBatchRenamerRegexExtensionAndUndo() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let f1 = tempDir.appendingPathComponent("Screen_2026_01_A.jpeg")
        let f2 = tempDir.appendingPathComponent("Screen_2026_02_B.jpeg")
        try Data("a".utf8).write(to: f1)
        try Data("b".utf8).write(to: f2)

        let items = [f1, f2].compactMap { FileItem(url: $0) }
        let rule = BatchRenameRule(
            findText: #"Screen_(\d{4})_(\d{2})_"#,
            replaceText: "Shot-$1-$2-",
            useRegex: true,
            newExtension: "jpg"
        )

        let previews = BatchRenamer.preview(items: items, rule: rule)
        XCTAssertEqual(previews[0].newName, "Shot-2026-01-A.jpg")
        XCTAssertEqual(previews[1].newName, "Shot-2026-02-B.jpg")

        let renamed = try BatchRenamer.apply(previews: previews)
        XCTAssertEqual(renamed.count, 2)
        XCTAssertTrue(BatchRenamer.canUndo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Shot-2026-01-A.jpg").path))

        let undoneCount = try BatchRenamer.undoLastRename()
        XCTAssertEqual(undoneCount, 2)
        XCTAssertFalse(BatchRenamer.canUndo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f2.path))
    }

    func testCompressToZipSingleAndMultipleFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileA = tempDir.appendingPathComponent("Alpha.txt")
        let fileB = tempDir.appendingPathComponent("Beta.txt")
        try Data("alpha-content".utf8).write(to: fileA)
        try Data("beta-content".utf8).write(to: fileB)

        let items = [fileA, fileB].compactMap { FileItem(url: $0) }
        let zipURL = try FileActions.createZipArchive(from: items, archiveName: "BundleTest")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))
        XCTAssertEqual(zipURL.pathExtension, "zip")
        let attrs = try FileManager.default.attributesOfItem(atPath: zipURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    func testFileShelfAddCopyMoveAndClear() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let srcDir = tempDir.appendingPathComponent("Source")
        let destDir = tempDir.appendingPathComponent("Destination")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let f1 = srcDir.appendingPathComponent("Note1.txt")
        let f2 = srcDir.appendingPathComponent("Note2.txt")
        try Data("note1".utf8).write(to: f1)
        try Data("note2".utf8).write(to: f2)

        let shelf = FileShelf(storageKey: "test.shelf.\(UUID().uuidString)")
        let items = [f1, f2].compactMap { FileItem(url: $0) }
        shelf.add(items)
        XCTAssertEqual(shelf.items.count, 2)

        // Adding duplicates shouldn't duplicate URLs
        shelf.add(items)
        XCTAssertEqual(shelf.items.count, 2)

        // Copy all to destDir
        let copied = try shelf.copyAll(to: destDir)
        XCTAssertEqual(copied.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("Note1.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f1.path))

        // Move all to destDir (should resolve name collision or move into subfolder)
        let moveDest = tempDir.appendingPathComponent("MovedDestination")
        try FileManager.default.createDirectory(at: moveDest, withIntermediateDirectories: true)
        let moved = try shelf.moveAll(to: moveDest)
        XCTAssertEqual(moved.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moveDest.appendingPathComponent("Note1.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f1.path))
        XCTAssertTrue(shelf.items.isEmpty)
    }
}
