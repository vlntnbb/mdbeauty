import SwiftUI
import WebKit
import AppKit
import Foundation
import UniformTypeIdentifiers

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let onOpenMarkdownLink: ((URL) -> Void)?
    let printRequest: DocumentPrintRequest?
    let suggestedPDFFileName: String
    let searchQuery: String
    let searchToken: Int
    let searchBackwards: Bool
    let searchReset: Bool
    let onSearchResult: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenMarkdownLink: onOpenMarkdownLink, onSearchResult: onSearchResult)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.preferredContentMode = .desktop

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenMarkdownLink = onOpenMarkdownLink
        context.coordinator.onSearchResult = onSearchResult

        if context.coordinator.shouldReload(html: html, baseURL: baseURL) {
            webView.loadHTMLString(html, baseURL: baseURL)
        }

        context.coordinator.performSearchIfNeeded(
            in: webView,
            query: searchQuery,
            token: searchToken,
            backwards: searchBackwards,
            reset: searchReset
        )

        context.coordinator.performPrintRequestIfNeeded(
            in: webView,
            request: printRequest,
            suggestedPDFFileName: suggestedPDFFileName
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private struct SearchRequest {
            let query: String
            let backwards: Bool
            let reset: Bool
        }

        private struct PendingPrintRequest {
            let request: DocumentPrintRequest
            let suggestedPDFFileName: String
        }

        private var lastHTML = ""
        private var lastBaseURL: URL?
        private var lastSearchToken = -1
        private var lastPrintRequestID: UUID?
        private var isContentLoaded = false
        private var isRunningPrintOperation = false
        private var pendingSearchRequest: SearchRequest?
        private var pendingPrintRequest: PendingPrintRequest?
        var onOpenMarkdownLink: ((URL) -> Void)?
        var onSearchResult: (Int) -> Void

        init(onOpenMarkdownLink: ((URL) -> Void)?, onSearchResult: @escaping (Int) -> Void) {
            self.onOpenMarkdownLink = onOpenMarkdownLink
            self.onSearchResult = onSearchResult
        }

        func shouldReload(html: String, baseURL: URL?) -> Bool {
            let changed = html != lastHTML || baseURL != lastBaseURL
            if changed {
                lastHTML = html
                lastBaseURL = baseURL
                lastSearchToken = -1
                isContentLoaded = false
                pendingSearchRequest = nil
            }
            return changed
        }

        func performSearchIfNeeded(
            in webView: WKWebView,
            query: String,
            token: Int,
            backwards: Bool,
            reset: Bool
        ) {
            guard token != lastSearchToken else { return }
            lastSearchToken = token

            let request = SearchRequest(query: query, backwards: backwards, reset: reset)
            guard isContentLoaded else {
                pendingSearchRequest = request
                onSearchResult(0)
                return
            }

            executeSearch(request, in: webView)
        }

        func performPrintRequestIfNeeded(
            in webView: WKWebView,
            request: DocumentPrintRequest?,
            suggestedPDFFileName: String
        ) {
            guard let request else { return }
            guard request.id != lastPrintRequestID else { return }
            lastPrintRequestID = request.id

            let pending = PendingPrintRequest(
                request: request,
                suggestedPDFFileName: suggestedPDFFileName
            )

            guard isContentLoaded, !isRunningPrintOperation else {
                pendingPrintRequest = pending
                return
            }

            executePrintRequest(pending, in: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isContentLoaded = true
            if let request = pendingSearchRequest {
                pendingSearchRequest = nil
                executeSearch(request, in: webView)
            }

            if let printRequest = pendingPrintRequest {
                pendingPrintRequest = nil
                executePrintRequest(printRequest, in: webView)
            }
        }

        private func executeSearch(_ request: SearchRequest, in webView: WKWebView) {
            let queryLiteral = javaScriptStringLiteral(request.query)
            let backwardsLiteral = request.backwards ? "true" : "false"
            let resetLiteral = request.reset ? "true" : "false"

            let script = """
            (function() {
              const query = \(queryLiteral);
              const backwards = \(backwardsLiteral);
              const reset = \(resetLiteral);
              const stateKey = "__mdbeatySearchState";
              const styleId = "mdbeaty-search-style";

              const ensureStyle = () => {
                if (document.getElementById(styleId)) return;
                const style = document.createElement("style");
                style.id = styleId;
                style.textContent = `
                  mark[data-mdbeaty-search="1"] {
                    background: rgba(255, 209, 102, 0.55);
                    color: inherit;
                    padding: 0;
                    border-radius: 2px;
                  }
                  mark[data-mdbeaty-search="1"].mdbeaty-search-current {
                    background: rgba(247, 148, 29, 0.85);
                  }
                  @media print {
                    mark[data-mdbeaty-search="1"],
                    mark[data-mdbeaty-search="1"].mdbeaty-search-current {
                      background: transparent !important;
                      color: inherit !important;
                    }
                  }
                `;
                document.head.appendChild(style);
              };

              const clearMarks = () => {
                const marks = Array.from(document.querySelectorAll('mark[data-mdbeaty-search="1"]'));
                if (marks.length === 0) return;
                const touchedParents = new Set();
                for (const mark of marks) {
                  const parent = mark.parentNode;
                  if (!parent) continue;
                  touchedParents.add(parent);
                  const textNode = document.createTextNode(mark.textContent || "");
                  parent.replaceChild(textNode, mark);
                }
                touchedParents.forEach((parent) => parent.normalize());
              };

              const getState = () => {
                if (!window[stateKey]) {
                  window[stateKey] = { query: "", nodes: [], index: -1 };
                }
                return window[stateKey];
              };

              const escapeRegExp = (value) =>
                value
                  .replaceAll("\\\\", "\\\\\\\\")
                  .replaceAll(".", "\\\\.")
                  .replaceAll("*", "\\\\*")
                  .replaceAll("+", "\\\\+")
                  .replaceAll("?", "\\\\?")
                  .replaceAll("^", "\\\\^")
                  .replaceAll("$", "\\\\$")
                  .replaceAll("{", "\\\\{")
                  .replaceAll("}", "\\\\}")
                  .replaceAll("(", "\\\\(")
                  .replaceAll(")", "\\\\)")
                  .replaceAll("|", "\\\\|")
                  .replaceAll("[", "\\\\[")
                  .replaceAll("]", "\\\\]");

              const collectMatches = (value) => {
                clearMarks();
                const state = getState();
                state.query = value;
                state.nodes = [];
                state.index = -1;

                if (!value) {
                  return state;
                }

                const root = document.body;
                if (!root) {
                  return state;
                }

                ensureStyle();
                const regex = new RegExp(escapeRegExp(value), "gi");
                const walker = document.createTreeWalker(
                  root,
                  NodeFilter.SHOW_TEXT,
                  {
                    acceptNode(node) {
                      const parent = node.parentNode;
                      if (!parent || !node.nodeValue || !node.nodeValue.trim()) {
                        return NodeFilter.FILTER_REJECT;
                      }
                      const parentTag = parent.nodeName;
                      if (parentTag === "SCRIPT" || parentTag === "STYLE" || parentTag === "NOSCRIPT") {
                        return NodeFilter.FILTER_REJECT;
                      }
                      return NodeFilter.FILTER_ACCEPT;
                    }
                  }
                );

                const textNodes = [];
                while (walker.nextNode()) {
                  textNodes.push(walker.currentNode);
                }

                for (const node of textNodes) {
                  const text = node.nodeValue || "";
                  regex.lastIndex = 0;
                  let match = regex.exec(text);
                  if (!match) continue;

                  const fragment = document.createDocumentFragment();
                  let cursor = 0;
                  do {
                    const start = match.index;
                    const end = start + match[0].length;
                    if (start > cursor) {
                      fragment.appendChild(document.createTextNode(text.slice(cursor, start)));
                    }
                    const mark = document.createElement("mark");
                    mark.dataset.mdbeatySearch = "1";
                    mark.textContent = text.slice(start, end);
                    fragment.appendChild(mark);
                    state.nodes.push(mark);
                    cursor = end;

                    if (match[0].length === 0) {
                      regex.lastIndex += 1;
                    }
                    match = regex.exec(text);
                  } while (match);

                  if (cursor < text.length) {
                    fragment.appendChild(document.createTextNode(text.slice(cursor)));
                  }

                  node.parentNode.replaceChild(fragment, node);
                }

                return state;
              };

              let state = getState();
              if (reset || state.query !== query || !state.nodes || state.nodes.length === 0) {
                state = collectMatches(query);
              }

              const total = state.nodes ? state.nodes.length : 0;
              if (total === 0) {
                state.index = -1;
                return { count: 0, index: -1 };
              }

              if (reset || state.index < 0 || state.index >= total) {
                state.index = backwards ? total - 1 : 0;
              } else {
                state.index = backwards
                  ? (state.index - 1 + total) % total
                  : (state.index + 1) % total;
              }

              for (let i = 0; i < total; i += 1) {
                if (i === state.index) {
                  state.nodes[i].classList.add("mdbeaty-search-current");
                } else {
                  state.nodes[i].classList.remove("mdbeaty-search-current");
                }
              }

              const activeNode = state.nodes[state.index];
              if (activeNode) {
                activeNode.scrollIntoView({ block: "center", inline: "nearest", behavior: "smooth" });
              }

              return { count: total, index: state.index };
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self else { return }
                self.onSearchResult(self.matchCount(from: result))
            }
        }

        private func executePrintRequest(_ pending: PendingPrintRequest, in webView: WKWebView) {
            waitForPrintableContent(in: webView) { [weak self, weak webView] in
                guard let self, let webView else { return }

                switch pending.request.action {
                case .print:
                    self.printDocument(
                        from: webView,
                        suggestedPDFFileName: pending.suggestedPDFFileName
                    )
                case .exportPDF:
                    self.presentPDFExportPanel(
                        for: webView,
                        suggestedPDFFileName: pending.suggestedPDFFileName
                    )
                }
            }
        }

        private func waitForPrintableContent(in webView: WKWebView, completion: @escaping () -> Void) {
            let script = """
            (function() {
              const timeout = new Promise((resolve) => setTimeout(resolve, 2500));
              const imagePromises = Array.from(document.images || []).map((image) => {
                if (image.complete) return Promise.resolve(null);
                return new Promise((resolve) => {
                  image.addEventListener("load", resolve, { once: true });
                  image.addEventListener("error", resolve, { once: true });
                });
              });
              const fontPromise = document.fonts && document.fonts.ready
                ? document.fonts.ready.catch(() => null)
                : Promise.resolve(null);

              return Promise.race([
                Promise.all([fontPromise, ...imagePromises]).then(() => true),
                timeout.then(() => false)
              ]).then((result) => new Promise((resolve) => {
                requestAnimationFrame(() => resolve(result));
              }));
            })();
            """

            webView.evaluateJavaScript(script) { _, _ in
                completion()
            }
        }

        private func printDocument(from webView: WKWebView, suggestedPDFFileName: String) {
            let printInfo = configuredPrintInfo()
            printInfo.jobDisposition = .spool

            let operation = webView.printOperation(with: printInfo)
            operation.jobTitle = printJobTitle(from: suggestedPDFFileName)
            operation.showsPrintPanel = true
            operation.showsProgressPanel = true
            runPrintOperation(operation, in: webView, reportFailure: false)
        }

        private func presentPDFExportPanel(
            for webView: WKWebView,
            suggestedPDFFileName: String
        ) {
            let panel = NSSavePanel()
            panel.title = "Export PDF"
            panel.prompt = "Export"
            panel.nameFieldStringValue = suggestedPDFFileName
            panel.allowedContentTypes = [.pdf]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false

            let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak webView] response in
                guard response == .OK, let url = panel.url, let webView else { return }
                self?.savePDF(from: webView, to: url, suggestedPDFFileName: suggestedPDFFileName)
            }

            if let window = webView.window {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }

        private func savePDF(
            from webView: WKWebView,
            to url: URL,
            suggestedPDFFileName: String
        ) {
            let printInfo = configuredPrintInfo()
            printInfo.jobDisposition = .save
            printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

            let operation = webView.printOperation(with: printInfo)
            operation.jobTitle = printJobTitle(from: suggestedPDFFileName)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = true
            runPrintOperation(operation, in: webView, reportFailure: true)
        }

        private func runPrintOperation(
            _ operation: NSPrintOperation,
            in webView: WKWebView,
            reportFailure: Bool
        ) {
            guard !isRunningPrintOperation else { return }

            isRunningPrintOperation = true
            let succeeded = operation.run()
            isRunningPrintOperation = false

            if !succeeded, reportFailure {
                presentPDFExportError()
            }

            guard let next = pendingPrintRequest else { return }
            pendingPrintRequest = nil
            executePrintRequest(next, in: webView)
        }

        private func configuredPrintInfo() -> NSPrintInfo {
            let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
            printInfo.topMargin = 36
            printInfo.bottomMargin = 36
            printInfo.leftMargin = 42
            printInfo.rightMargin = 42
            printInfo.isHorizontallyCentered = true
            printInfo.isVerticallyCentered = false
            return printInfo
        }

        private func printJobTitle(from suggestedPDFFileName: String) -> String {
            if suggestedPDFFileName.lowercased().hasSuffix(".pdf") {
                return String(suggestedPDFFileName.dropLast(4))
            }
            return suggestedPDFFileName
        }

        private func presentPDFExportError() {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Unable to export PDF"
            alert.informativeText = "MDbeaty could not write the PDF file."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }

        private func matchCount(from result: Any?) -> Int {
            if let dictionary = result as? [String: Any] {
                if let count = dictionary["count"] as? Int {
                    return count
                }
                if let count = dictionary["count"] as? NSNumber {
                    return count.intValue
                }
            }

            if let count = result as? Int {
                return count
            }
            if let count = result as? NSNumber {
                return count.intValue
            }
            return 0
        }

        private func javaScriptStringLiteral(_ value: String) -> String {
            let payload = [value]
            guard
                let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                let json = String(data: data, encoding: .utf8),
                json.count >= 2
            else {
                return "\"\""
            }

            return String(json.dropFirst().dropLast())
        }

        @MainActor
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if isMarkdownLikeFileURL(url) {
                onOpenMarkdownLink?(url)
                decisionHandler(.cancel)
                return
            }

            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }

        private func isMarkdownLikeFileURL(_ url: URL) -> Bool {
            guard url.isFileURL else { return false }
            let ext = url.pathExtension.lowercased()
            return ext == "md" || ext == "markdown" || ext == "mdown"
        }
    }
}
