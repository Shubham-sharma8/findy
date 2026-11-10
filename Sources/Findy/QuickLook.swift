import Foundation
import AppKit
import Quartz

// MARK: - Native macOS Quick Look Controller

public final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    @MainActor public static let shared = QuickLook()

    private var urls: [URL] = []
    private var currentIndex: Int = 0

    public override init() {
        super.init()
    }

    @MainActor
    public func follow(_ item: FileItem?, in list: [FileItem], columns: Int = 4) {
        guard let item else {
            if QLPreviewPanel.sharedPreviewPanelExists(),
               let panel = QLPreviewPanel.shared(),
               panel.isVisible {
                panel.orderOut(nil)
            }
            return
        }

        let validList = list.isEmpty ? [item] : list
        self.urls = validList.map(\.url)
        self.currentIndex = validList.firstIndex(of: item) ?? 0

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = currentIndex
        if !panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }

    public func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        switch event.keyCode {
        case 123, 126: // Left / Up
            if currentIndex > 0 {
                currentIndex -= 1
                panel.currentPreviewItemIndex = currentIndex
            }
            return true
        case 124, 125: // Right / Down
            if currentIndex + 1 < urls.count {
                currentIndex += 1
                panel.currentPreviewItemIndex = currentIndex
            }
            return true
        default:
            return false
        }
    }
}
