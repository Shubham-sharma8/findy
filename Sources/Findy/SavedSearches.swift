import Foundation
import SwiftUI

// MARK: - Saved Search Model

public struct SavedSearch: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var query: String

    private static let storageKey = "findy.savedSearches"

    public init(id: UUID = UUID(), name: String, query: String) {
        self.id = id
        self.name = name
        self.query = query
    }

    public static func load() -> [SavedSearch] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data) else {
            return []
        }
        return decoded
    }

    public static func save(_ searches: [SavedSearch]) {
        if let data = try? JSONEncoder().encode(searches) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - AppState Saved Search Helpers

extension AppState {
    public var isCurrentSearchSaved: Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return false }
        return savedSearches.contains { $0.query.caseInsensitiveCompare(q) == .orderedSame }
    }

    public func saveCurrentSearch() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if let idx = savedSearches.firstIndex(where: { $0.query.caseInsensitiveCompare(q) == .orderedSame }) {
            savedSearches.remove(at: idx)
            SavedSearch.save(savedSearches)
            showToast("Removed saved search", symbol: "bookmark.slash.fill")
        } else {
            let item = SavedSearch(name: q, query: q)
            savedSearches.append(item)
            SavedSearch.save(savedSearches)
            showToast("Saved search to sidebar", symbol: "bookmark.fill")
        }
    }

    public func removeSavedSearch(_ search: SavedSearch) {
        savedSearches.removeAll { $0.id == search.id }
        SavedSearch.save(savedSearches)
    }

    public func renameSavedSearch(_ search: SavedSearch, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = savedSearches.firstIndex(where: { $0.id == search.id }) else { return }
        savedSearches[idx].name = trimmed
        SavedSearch.save(savedSearches)
    }

    public func run(_ search: SavedSearch) {
        searchText = search.query
    }
}

// MARK: - Save Search Button & Sidebar Section

public struct SaveSearchButton: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        let saved = state.isCurrentSearchSaved
        Button {
            state.saveCurrentSearch()
        } label: {
            Label(saved ? "Saved" : "Save Search", systemImage: saved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.bordered)
    }
}

public struct SavedSearchesSection: View {
    @Environment(AppState.self) private var state
    @State private var renaming: SavedSearch?
    @State private var draftName: String = ""

    public init() {}

    public var body: some View {
        if !state.savedSearches.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("SAVED SEARCHES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)

                ForEach(state.savedSearches) { saved in
                    let active = state.searchText.caseInsensitiveCompare(saved.query) == .orderedSame
                    SidebarRow(isSelected: active) {
                        state.run(saved)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(active ? Color.accentColor : .secondary)
                                .frame(width: 18)
                            Text(saved.name)
                                .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .contextMenu {
                        Button("Rename…") {
                            draftName = saved.name
                            renaming = saved
                        }
                        Button("Remove Saved Search", role: .destructive) {
                            state.removeSavedSearch(saved)
                        }
                    }
                }
            }
            .alert(
                "Rename Saved Search",
                isPresented: Binding(
                    get: { renaming != nil },
                    set: { if !$0 { renaming = nil } }
                )
            ) {
                TextField("Name", text: $draftName)
                Button("Save") {
                    if let target = renaming {
                        state.renameSavedSearch(target, to: draftName)
                    }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) {
                    renaming = nil
                }
            }
        }
    }
}
