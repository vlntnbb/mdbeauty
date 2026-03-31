import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class WorkspaceState: ObservableObject {
    private static let maxRecentFiles = 10

    struct Tab: Identifiable {
        let id: UUID
        let state: DocumentState
    }

    @Published private(set) var tabs: [Tab] = []
    @Published var selectedTabID: UUID?

    private let allowedContentTypes: [UTType] = {
        var types: [UTType] = [.plainText]
        if let md = UTType(filenameExtension: "md") {
            types.append(md)
        }
        if let markdown = UTType(filenameExtension: "markdown") {
            types.append(markdown)
        }
        if let mdown = UTType(filenameExtension: "mdown") {
            types.append(mdown)
        }
        return types
    }()

    init() {
        UserDefaults.standard.set(Self.maxRecentFiles, forKey: "NSRecentDocumentsLimit")
        let tab = Tab(id: UUID(), state: DocumentState())
        tabs = [tab]
        selectedTabID = tab.id
    }

    var selectedTab: Tab? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    var canReloadSelectedTab: Bool {
        selectedTab?.state.canReload ?? false
    }

    var canSaveSelectedTab: Bool {
        selectedTab?.state.canSave ?? false
    }

    var selectedMode: TabMode {
        selectedTab?.state.mode ?? .preview
    }

    var selectedSaveStatusLabel: String {
        selectedTab?.state.saveStatusLabel ?? ""
    }

    var selectedPreserveParagraphLineBreaks: Bool {
        selectedTab?.state.preserveParagraphLineBreaks ?? true
    }

    var recentMarkdownURLs: [URL] {
        Array(NSDocumentController.shared.recentDocumentURLs.filter { url in
            isMarkdownLikeFileURL(url) && FileManager.default.fileExists(atPath: url.path)
        }.prefix(Self.maxRecentFiles))
    }

    func openAtLaunch(url: URL) {
        openInTabOrFocusExisting(url: url)
    }

    func openFromExternal(url: URL) {
        openInTabOrFocusExisting(url: url)
    }

    func openWithSystemPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedContentTypes
        panel.prompt = "Open"
        panel.title = "Open Markdown File"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        openInTabOrFocusExisting(url: url)
    }

    func openRecent(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        openInTabOrFocusExisting(url: url)
    }

    func clearRecentFiles() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        objectWillChange.send()
    }

    func reloadSelectedTab() {
        selectedTab?.state.reload()
    }

    func saveSelectedTab() {
        selectedTab?.state.saveNow()
    }

    func toggleSelectedTabMode() {
        guard let state = selectedTab?.state else { return }
        state.mode = state.mode == .preview ? .edit : .preview
    }

    func setSelectedTabMode(_ mode: TabMode) {
        selectedTab?.state.mode = mode
    }

    func setSelectedPreserveParagraphLineBreaks(_ enabled: Bool) {
        selectedTab?.state.preserveParagraphLineBreaks = enabled
    }

    func openEmptyTab() {
        let tab = Tab(id: UUID(), state: DocumentState())
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func openInNewTab(url: URL) {
        let tab = Tab(id: UUID(), state: DocumentState())
        tabs.append(tab)
        selectedTabID = tab.id
        tab.state.open(url: url)
    }

    func select(tabID: UUID) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }
        selectedTabID = tabID
    }

    func close(tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }

        let state = tabs[index].state
        if state.hasUnsavedChanges {
            let action = promptForUnsavedCloseAction()
            switch action {
            case .cancel:
                return
            case .saveAndClose:
                state.saveNow()
            case .discardAndClose:
                break
            }
        }

        let removed = tabs.remove(at: index)
        removed.state.prepareForClose()

        if tabs.isEmpty {
            let fallback = Tab(id: UUID(), state: DocumentState())
            tabs = [fallback]
            selectedTabID = fallback.id
            return
        }

        if selectedTabID == tabID {
            let newIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[newIndex].id
        }
    }

    private enum UnsavedCloseAction {
        case saveAndClose
        case discardAndClose
        case cancel
    }

    private func promptForUnsavedCloseAction() -> UnsavedCloseAction {
        let alert = NSAlert()
        alert.messageText = "Unsaved changes"
        alert.informativeText = "Save changes before closing this tab?"
        alert.addButton(withTitle: "Save & Close")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .saveAndClose
        case .alertSecondButtonReturn:
            return .discardAndClose
        default:
            return .cancel
        }
    }

    private func singleEmptyTab() -> Tab? {
        guard tabs.count == 1, let only = tabs.first else {
            return nil
        }

        guard !only.state.hasOpenedAnyFile else {
            return nil
        }

        return only
    }

    private func isMarkdownLikeFileURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown" || ext == "mdown"
    }

    private func openInTabOrFocusExisting(url: URL) {
        if let existing = tab(containing: url) {
            selectedTabID = existing.id
            existing.state.open(url: url)
            return
        }

        if let empty = singleEmptyTab() {
            selectedTabID = empty.id
            empty.state.open(url: url)
            return
        }

        openInNewTab(url: url)
    }

    private func tab(containing url: URL) -> Tab? {
        let targetPath = normalizedPath(for: url)
        return tabs.first { tab in
            guard let fileURL = tab.state.fileURL else { return false }
            return normalizedPath(for: fileURL) == targetPath
        }
    }

    private func normalizedPath(for url: URL) -> String {
        removingFragment(from: url).standardizedFileURL.path
    }

    private func removingFragment(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        return components.url ?? url
    }
}
