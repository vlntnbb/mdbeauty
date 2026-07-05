import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class WorkspaceState: ObservableObject {
    private static let maxRecentFiles = 10
    private static let applicationSupportFolderName = "MDbeaty"
    private static let recentFilesName = "recent-files.json"

    struct Tab: Identifiable {
        let id: UUID
        let state: DocumentState
    }

    @Published private(set) var tabs: [Tab] = []
    @Published private(set) var recentMarkdownURLs: [URL] = []
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
        let hasStoredRecentFiles = Self.recentFilesStoreExists
        recentMarkdownURLs = Self.loadRecentMarkdownURLs()
        let tab = Tab(id: UUID(), state: DocumentState())
        tabs = [tab]
        selectedTabID = tab.id

        if !hasStoredRecentFiles {
            mergeSystemRecentDocumentsIfNeeded()
        }
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

    var canPrintSelectedTab: Bool {
        selectedTab?.state.canPrint ?? false
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
        guard FileManager.default.fileExists(atPath: url.path) else {
            removeRecent(url: url)
            return
        }
        openInTabOrFocusExisting(url: url)
    }

    func clearRecentFiles() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        recentMarkdownURLs = []
        saveRecentMarkdownURLs()
        objectWillChange.send()
    }

    func reloadSelectedTab() {
        selectedTab?.state.reload()
    }

    func saveSelectedTab() {
        selectedTab?.state.saveNow()
    }

    func printSelectedTab() {
        selectedTab?.state.requestPrint()
    }

    func exportSelectedTabToPDF() {
        selectedTab?.state.requestPDFExport()
    }

    func findInSelectedTab() {
        selectedTab?.state.requestFindInDocument()
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
        recordRecentIfNeeded(url: url)
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

    private func openInTabOrFocusExisting(url: URL) {
        if let existing = tab(containing: url) {
            selectedTabID = existing.id
            existing.state.open(url: url)
            recordRecentIfNeeded(url: url)
            return
        }

        if let empty = singleEmptyTab() {
            selectedTabID = empty.id
            empty.state.open(url: url)
            recordRecentIfNeeded(url: url)
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
        Self.normalizedPath(for: url)
    }

    private func recordRecentIfNeeded(url: URL) {
        let normalizedURL = Self.normalizedFileURL(for: url)
        guard Self.isMarkdownLikeFileURL(normalizedURL) else { return }
        guard FileManager.default.fileExists(atPath: normalizedURL.path) else { return }

        recentMarkdownURLs.removeAll { Self.normalizedPath(for: $0) == normalizedURL.path }
        recentMarkdownURLs.insert(normalizedURL, at: 0)
        recentMarkdownURLs = Array(recentMarkdownURLs.prefix(Self.maxRecentFiles))
        saveRecentMarkdownURLs()
    }

    private func removeRecent(url: URL) {
        let normalizedPath = Self.normalizedPath(for: url)
        recentMarkdownURLs = recentMarkdownURLs.filter {
            Self.normalizedPath(for: $0) != normalizedPath
        }
        saveRecentMarkdownURLs()
    }

    private func mergeSystemRecentDocumentsIfNeeded() {
        let systemURLs = Self.normalizedRecentMarkdownURLs(
            from: NSDocumentController.shared.recentDocumentURLs
        )
        guard !systemURLs.isEmpty else { return }

        recentMarkdownURLs = Self.deduplicatedRecentMarkdownURLs(
            recentMarkdownURLs + systemURLs
        )
        saveRecentMarkdownURLs()
    }

    private func saveRecentMarkdownURLs() {
        guard let fileURL = Self.recentFilesURL else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let paths = recentMarkdownURLs.map(\.path)
            let data = try JSONEncoder().encode(paths)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("MDbeaty failed to save recent files: \(error.localizedDescription)")
        }
    }

    private static func loadRecentMarkdownURLs() -> [URL] {
        guard
            let fileURL = recentFilesURL,
            let data = try? Data(contentsOf: fileURL),
            let paths = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        let urls = paths.map { URL(fileURLWithPath: $0) }
        return deduplicatedRecentMarkdownURLs(urls)
    }

    private static func normalizedRecentMarkdownURLs(from urls: [URL]) -> [URL] {
        deduplicatedRecentMarkdownURLs(urls)
    }

    private static func deduplicatedRecentMarkdownURLs(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var normalizedURLs: [URL] = []

        for url in urls {
            let normalizedURL = normalizedFileURL(for: url)
            let path = normalizedURL.path
            guard isMarkdownLikeFileURL(normalizedURL) else { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard seenPaths.insert(path).inserted else { continue }
            normalizedURLs.append(normalizedURL)

            if normalizedURLs.count >= maxRecentFiles {
                break
            }
        }

        return normalizedURLs
    }

    private static var recentFilesURL: URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent(applicationSupportFolderName, isDirectory: true)
            .appendingPathComponent(recentFilesName, isDirectory: false)
    }

    private static var recentFilesStoreExists: Bool {
        guard let recentFilesURL else { return false }
        return FileManager.default.fileExists(atPath: recentFilesURL.path)
    }

    private static func isMarkdownLikeFileURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown" || ext == "mdown"
    }

    private static func normalizedPath(for url: URL) -> String {
        normalizedFileURL(for: url).path
    }

    private static func normalizedFileURL(for url: URL) -> URL {
        removingFragment(from: url).standardizedFileURL
    }

    private static func removingFragment(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        return components.url ?? url
    }
}
