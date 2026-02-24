import Foundation
import Darwin
import Combine
import AppKit

@MainActor
final class ViewerState: ObservableObject {
    @Published var fileURL: URL?
    @Published var renderedHTML = MarkdownRenderer.welcomeHTML
    @Published var baseURL: URL?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasOpenedAnyFile = false

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var debounceTask: Task<Void, Never>?

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
        load(url: fileURL, initialFragment: nil)
    }

    func prepareForClose() {
        stopWatching()
    }

    private func load(url: URL, initialFragment: String?) {
        isLoading = true
        errorMessage = nil

        Task(priority: .userInitiated) {
            let result: Result<(String, URL), Error> = Result {
                var usedEncoding = String.Encoding.utf8
                let markdown = try String(contentsOf: url, usedEncoding: &usedEncoding)
                let folderURL = url.deletingLastPathComponent()
                let html = MarkdownRenderer.render(
                    markdown: markdown,
                    baseFolderURL: folderURL,
                    initialFragment: initialFragment
                )
                return (html, folderURL)
            }

            await MainActor.run {
                self.isLoading = false

                switch result {
                case .success(let payload):
                    self.fileURL = url
                    self.renderedHTML = payload.0
                    self.baseURL = payload.1
                    self.startWatching(url: url)
                case .failure(let error):
                    self.renderError(error.localizedDescription)
                }
            }
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

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await self?.reloadAfterChange(fileURL)
        }
    }

    private func reloadAfterChange(_ url: URL) async {
        guard FileManager.default.fileExists(atPath: url.path) else {
            renderError("The file was removed.")
            return
        }
        load(url: url, initialFragment: nil)
    }

    private func stopWatching() {
        debounceTask?.cancel()
        debounceTask = nil

        source?.cancel()
        source = nil

        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
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
