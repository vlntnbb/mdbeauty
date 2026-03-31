import Foundation
import Darwin
import Combine
import AppKit

enum TabMode: String, CaseIterable, Identifiable {
    case preview
    case edit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview:
            return "Preview"
        case .edit:
            return "Edit"
        }
    }
}

enum SaveStatus: Equatable {
    case idle
    case saving
    case saved(Date)
    case error(String)

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .saving:
            return "Saving…"
        case .saved:
            return "Saved"
        case .error:
            return "Save failed"
        }
    }
}

enum ExternalChangeState: Equatable {
    case none
    case conflict
}

struct ProtectedBlock: Identifiable, Equatable {
    let id: String
    let label: String
    var rawMarkdown: String

    var title: String {
        "\(label) • \(id)"
    }
}

enum EditorCommand: String {
    case h1
    case h2
    case bold
    case italic
    case bulletList
    case orderedList
    case quote
    case code
    case insertLink
    case insertImage
    case undo
    case redo
}

struct EditorCommandRequest: Equatable {
    let id: UUID
    let command: EditorCommand
    let payload: String?
}

@MainActor
final class DocumentState: ObservableObject {
    private static let preserveLineBreaksDefaultsKey = "MDbeaty.PreserveParagraphLineBreaks"

    @Published var fileURL: URL?
    @Published var renderedHTML = MarkdownRenderer.welcomeHTML
    @Published var baseURL: URL?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasOpenedAnyFile = false

    @Published var mode: TabMode = .preview
    @Published var preserveParagraphLineBreaks: Bool {
        didSet {
            UserDefaults.standard.set(
                preserveParagraphLineBreaks,
                forKey: Self.preserveLineBreaksDefaultsKey
            )

            guard hasOpenedAnyFile else { return }
            renderCurrentMarkdown()
        }
    }
    @Published private(set) var markdownSource = ""
    @Published private(set) var editorMarkdown = ""
    @Published private(set) var saveStatus: SaveStatus = .idle
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var externalChangeState: ExternalChangeState = .none
    @Published private(set) var protectedBlocks: [ProtectedBlock] = []
    @Published private(set) var documentRevision = 0
    @Published private(set) var pendingEditorCommand: EditorCommandRequest?
    @Published private(set) var selectionSummary = ""
    @Published var isCompareSheetPresented = false

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var watchDebounceTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?

    private var isSavingToDisk = false
    private var incomingConflictMarkdown: String?
    private var protectedBlocksByID: [String: ProtectedBlock] = [:]
    private var protectedIDSeed = 0

    init() {
        let storedValue = UserDefaults.standard.object(
            forKey: Self.preserveLineBreaksDefaultsKey
        ) as? Bool
        preserveParagraphLineBreaks = storedValue ?? true
    }

    var canReload: Bool {
        fileURL != nil && !isLoading
    }

    var canSave: Bool {
        fileURL != nil && !isLoading
    }

    var hasConflict: Bool {
        externalChangeState == .conflict
    }

    var compareLocalMarkdown: String {
        markdownSource
    }

    var compareIncomingMarkdown: String {
        incomingConflictMarkdown ?? ""
    }

    var saveStatusLabel: String {
        if hasConflict {
            return "Conflict"
        }

        switch saveStatus {
        case .idle:
            return hasUnsavedChanges ? "Unsaved" : "Saved"
        case .saving:
            return "Saving…"
        case .saved:
            return "Saved"
        case .error:
            return "Save failed"
        }
    }

    func open(url: URL) {
        let normalizedURL = url.removingURLFragment()
        let requestedFragment = url.fragment?.removingPercentEncoding

        guard isMarkdownLikeFile(normalizedURL) else {
            renderError("Only Markdown files are supported.")
            return
        }

        hasOpenedAnyFile = true
        NSDocumentController.shared.noteNewRecentDocumentURL(normalizedURL)
        load(url: normalizedURL, initialFragment: requestedFragment)
    }

    func reload() {
        guard let fileURL else { return }

        if hasUnsavedChanges {
            promptReloadWithUnsavedChanges(url: fileURL)
            return
        }

        load(url: fileURL, initialFragment: nil)
    }

    func saveNow() {
        Task {
            await flushAutosaveNow()
        }
    }

    func prepareForClose() {
        autosaveTask?.cancel()
        autosaveTask = nil
        stopWatching()
    }

    func receiveEditorMarkdown(_ markdown: String) {
        let normalized = normalizeLineEndings(markdown)
        guard normalized != editorMarkdown else { return }

        editorMarkdown = normalized
        if normalized != markdownSource {
            markdownSource = normalized
            renderCurrentMarkdown()
            hasUnsavedChanges = true
            if !hasConflict {
                saveStatus = .idle
            }
            scheduleAutosave()
        }
    }

    func updateSelectionSummary(_ summary: String) {
        selectionSummary = summary
    }

    func issueEditorCommand(_ command: EditorCommand, payload: String? = nil) {
        pendingEditorCommand = EditorCommandRequest(
            id: UUID(),
            command: command,
            payload: payload
        )
    }

    func beginInsertLinkFlow() {
        guard mode == .edit else { return }
        let url = promptForSingleLineInput(
            title: "Insert Link",
            message: "Enter URL",
            placeholder: "https://example.com"
        )
        guard let url, !url.isEmpty else { return }
        issueEditorCommand(.insertLink, payload: url)
    }

    func beginInsertImageFlow() {
        guard mode == .edit else { return }
        let url = promptForSingleLineInput(
            title: "Insert Image",
            message: "Enter image URL or relative path",
            placeholder: "images/diagram.png"
        )
        guard let url, !url.isEmpty else { return }
        issueEditorCommand(.insertImage, payload: url)
    }

    func openProtectedBlockEditor(id: String) {
        guard var block = protectedBlocksByID[id] else { return }

        let alert = NSAlert()
        alert.messageText = "Edit Protected Markdown"
        alert.informativeText = "This block is preserved 1:1 in the source file."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 260))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .bezelBorder

        let textView = NSTextView(frame: scroll.bounds)
        textView.minSize = NSSize(width: 0, height: 240)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = block.rawMarkdown

        scroll.documentView = textView
        alert.accessoryView = scroll

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let updated = normalizeLineEndings(textView.string)
        guard updated != block.rawMarkdown else { return }

        block.rawMarkdown = updated
        protectedBlocksByID[id] = block
        protectedBlocks = protectedBlocksByID.values.sorted { $0.id < $1.id }

        let restored = restoreProtectedBlocks(in: editorMarkdown)
        if restored != markdownSource {
            markdownSource = restored
            renderCurrentMarkdown()
            hasUnsavedChanges = true
            saveStatus = .idle
            scheduleAutosave()
        }
    }

    func resolveConflictByReloadingFromDisk() {
        guard let incoming = incomingConflictMarkdown else { return }

        applyLoadedMarkdown(
            rawMarkdown: incoming,
            sourceURL: fileURL,
            initialFragment: nil,
            clearConflict: true
        )
    }

    func resolveConflictKeepMine() {
        externalChangeState = .none
        incomingConflictMarkdown = nil
        if hasUnsavedChanges {
            scheduleAutosave()
        }
    }

    func openConflictComparison() {
        guard hasConflict else { return }
        isCompareSheetPresented = true
    }

    private func promptReloadWithUnsavedChanges(url: URL) {
        let alert = NSAlert()
        alert.messageText = "Unsaved changes"
        alert.informativeText = "Reloading will discard unsaved editor changes."
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        load(url: url, initialFragment: nil)
    }

    private func promptForSingleLineInput(
        title: String,
        message: String,
        placeholder: String
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        textField.placeholderString = placeholder
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func load(url: URL, initialFragment: String?) {
        isLoading = true
        errorMessage = nil

        Task(priority: .userInitiated) {
            let result: Result<String, Error> = Result {
                var usedEncoding = String.Encoding.utf8
                return try String(contentsOf: url, usedEncoding: &usedEncoding)
            }

            await MainActor.run {
                self.isLoading = false

                switch result {
                case .success(let markdown):
                    self.applyLoadedMarkdown(
                        rawMarkdown: markdown,
                        sourceURL: url,
                        initialFragment: initialFragment,
                        clearConflict: true
                    )
                    self.startWatching(url: url)
                case .failure(let error):
                    self.renderError(error.localizedDescription)
                }
            }
        }
    }

    private func applyLoadedMarkdown(
        rawMarkdown: String,
        sourceURL: URL?,
        initialFragment: String?,
        clearConflict: Bool
    ) {
        let normalizedRaw = normalizeLineEndings(rawMarkdown)

        fileURL = sourceURL
        baseURL = sourceURL?.deletingLastPathComponent()

        protectedBlocks = []
        protectedBlocksByID = [:]
        editorMarkdown = normalizedRaw
        markdownSource = normalizedRaw

        hasUnsavedChanges = false
        saveStatus = .saved(Date())

        if clearConflict {
            externalChangeState = .none
            incomingConflictMarkdown = nil
        }

        renderCurrentMarkdown(initialFragment: initialFragment)

        documentRevision &+= 1
    }

    private func renderCurrentMarkdown(initialFragment: String? = nil) {
        let folderURL = fileURL?.deletingLastPathComponent()
        renderedHTML = MarkdownRenderer.render(
            markdown: markdownSource,
            baseFolderURL: folderURL,
            initialFragment: initialFragment,
            preserveParagraphLineBreaks: preserveParagraphLineBreaks
        )
    }

    private func flushAutosaveNow() async {
        autosaveTask?.cancel()
        autosaveTask = nil

        guard hasUnsavedChanges, let fileURL else { return }
        if isSavingToDisk { return }

        let markdownToSave = markdownSource
        saveStatus = .saving
        isSavingToDisk = true

        let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            try markdownToSave.write(to: fileURL, atomically: true, encoding: .utf8)
        }.result

        isSavingToDisk = false

        switch result {
        case .success:
            hasUnsavedChanges = false
            saveStatus = .saved(Date())
            if hasConflict {
                resolveConflictKeepMine()
            }
        case .failure(let error):
            saveStatus = .error(error.localizedDescription)
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard fileURL != nil else { return }

        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushAutosaveNow()
        }
    }

    private func isMarkdownLikeFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown" || ext == "mdown"
    }

    private func renderError(_ message: String) {
        errorMessage = message
        renderedHTML = MarkdownRenderer.errorHTML(message: message)
    }

    private func startWatching(url: URL) {
        stopWatching()

        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.main
        )

        src.setEventHandler { [weak self] in
            let eventData = src.data
            self?.handleFileEvent(eventData)
        }

        src.resume()
        source = src
    }

    private func handleFileEvent(_ data: DispatchSource.FileSystemEvent) {
        guard let fileURL else { return }

        if data.contains(.delete) || data.contains(.rename) {
            stopWatching()
            renderError("The file was moved or removed.")
            return
        }

        watchDebounceTask?.cancel()
        watchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            await self?.reloadAfterExternalChange(fileURL)
        }
    }

    private func reloadAfterExternalChange(_ url: URL) async {
        guard !isSavingToDisk else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            renderError("The file was removed.")
            return
        }

        let result: Result<String, Error> = await Task.detached(priority: .utility) {
            var encoding = String.Encoding.utf8
            return try String(contentsOf: url, usedEncoding: &encoding)
        }.result

        switch result {
        case .success(let diskRaw):
            let normalized = normalizeLineEndings(diskRaw)
            if normalized == markdownSource {
                return
            }

            if hasUnsavedChanges {
                externalChangeState = .conflict
                incomingConflictMarkdown = normalized
                return
            }

            applyLoadedMarkdown(
                rawMarkdown: normalized,
                sourceURL: url,
                initialFragment: nil,
                clearConflict: true
            )
        case .failure(let error):
            renderError(error.localizedDescription)
        }
    }

    private func stopWatching() {
        watchDebounceTask?.cancel()
        watchDebounceTask = nil

        source?.cancel()
        source = nil

        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func normalizeLineEndings(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private struct ProtectedExtraction {
        let editorMarkdown: String
        let blocks: [ProtectedBlock]
    }

    private func extractProtectedBlocks(from markdown: String) -> ProtectedExtraction {
        protectedIDSeed = 0
        var working = markdown
        var blocks: [ProtectedBlock] = []

        if let frontMatterRange = frontMatterRange(in: working) {
            let raw = String(working[frontMatterRange])
            let id = nextProtectedID()
            let block = ProtectedBlock(id: id, label: "Front matter", rawMarkdown: raw)
            blocks.append(block)
            working.replaceSubrange(frontMatterRange, with: placeholderMarkdown(for: block))
        }

        working = replaceProtectedMatches(
            in: working,
            pattern: #"(?ms)^:::[^\n]*\n[\s\S]*?\n:::\s*$"#,
            label: "Directive block",
            blocks: &blocks
        )

        working = replaceProtectedMatches(
            in: working,
            pattern: #"(?ms)^<!--\s*[\s\S]*?\s*-->\s*$"#,
            label: "HTML comment",
            blocks: &blocks
        )

        working = replaceProtectedMatches(
            in: working,
            pattern: #"(?ms)^<([A-Za-z][A-Za-z0-9-]*)(?:\s[^>]*)?>[\s\S]*?</\1>\s*$"#,
            label: "HTML block",
            blocks: &blocks
        )

        let normalizedEditor = normalizeLineEndings(working)
        return ProtectedExtraction(editorMarkdown: normalizedEditor, blocks: blocks)
    }

    private func replaceProtectedMatches(
        in text: String,
        pattern: String,
        label: String,
        blocks: inout [ProtectedBlock]
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return text
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return text }

        var updated = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: updated) else { continue }
            let raw = String(updated[range])
            let id = nextProtectedID()
            let block = ProtectedBlock(id: id, label: label, rawMarkdown: raw)
            blocks.append(block)
            updated.replaceSubrange(range, with: placeholderMarkdown(for: block))
        }

        return updated
    }

    private func frontMatterRange(in markdown: String) -> Range<String.Index>? {
        guard markdown.hasPrefix("---\n") else { return nil }

        let start = markdown.index(markdown.startIndex, offsetBy: 4)
        guard let terminator = markdown.range(of: "\n---\n", range: start..<markdown.endIndex) ??
            markdown.range(of: "\n---", range: start..<markdown.endIndex)
        else {
            return nil
        }

        let end = terminator.upperBound
        return markdown.startIndex..<end
    }

    private func nextProtectedID() -> String {
        protectedIDSeed += 1
        return "pb-\(protectedIDSeed)"
    }

    private func placeholderMarkdown(for block: ProtectedBlock) -> String {
        """
        ```mdbeaty-protected:\(block.id)
        \(block.title)
        ```
        """
    }

    private func restoreProtectedBlocks(in editorMarkdown: String) -> String {
        let pattern = #"(?ms)```mdbeaty-protected:([A-Za-z0-9_-]+)\n[\s\S]*?\n```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return editorMarkdown
        }

        var output = editorMarkdown
        let nsRange = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = regex.matches(in: output, options: [], range: nsRange)

        for match in matches.reversed() {
            guard
                let full = Range(match.range, in: output),
                let idRange = Range(match.range(at: 1), in: output)
            else {
                continue
            }

            let id = String(output[idRange])
            guard let raw = protectedBlocksByID[id]?.rawMarkdown else { continue }
            output.replaceSubrange(full, with: raw)
        }

        return normalizeLineEndings(output)
    }
}

private extension URL {
    func removingURLFragment() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.fragment = nil
        return components.url ?? self
    }
}
