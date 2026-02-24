import SwiftUI
import WebKit
import AppKit

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let onOpenMarkdownLink: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenMarkdownLink: onOpenMarkdownLink)
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
        guard context.coordinator.shouldReload(html: html, baseURL: baseURL) else { return }
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var lastHTML = ""
        private var lastBaseURL: URL?
        var onOpenMarkdownLink: ((URL) -> Void)?

        init(onOpenMarkdownLink: ((URL) -> Void)?) {
            self.onOpenMarkdownLink = onOpenMarkdownLink
        }

        func shouldReload(html: String, baseURL: URL?) -> Bool {
            let changed = html != lastHTML || baseURL != lastBaseURL
            if changed {
                lastHTML = html
                lastBaseURL = baseURL
            }
            return changed
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
