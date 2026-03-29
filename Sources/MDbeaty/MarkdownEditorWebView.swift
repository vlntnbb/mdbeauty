import SwiftUI
import WebKit

struct MarkdownEditorWebView: NSViewRepresentable {
    @ObservedObject var state: DocumentState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.messageHandlerName)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true

        context.coordinator.attach(webView)
        context.coordinator.loadEditorDocument()

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.state = state
        context.coordinator.applyStateIfNeeded()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageHandlerName
        )
        coordinator.detach()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageHandlerName = "mdbeatyEditor"

        var state: DocumentState

        private weak var webView: WKWebView?
        private var isReady = false
        private var lastAppliedRevision = -1
        private var lastHandledCommandID: UUID?

        init(state: DocumentState) {
            self.state = state
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
        }

        func detach() {
            webView?.navigationDelegate = nil
            webView = nil
        }

        func loadEditorDocument() {
            guard let webView else { return }

            guard let htmlURL = Bundle.module.url(
                forResource: "editor",
                withExtension: "html",
                subdirectory: "WebEditor"
            ) else {
                webView.loadHTMLString(
                    "<html><body><h3>Editor assets are missing.</h3></body></html>",
                    baseURL: nil
                )
                return
            }

            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        func applyStateIfNeeded() {
            guard isReady else { return }
            applyDocumentIfNeeded()
            applyCommandIfNeeded()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            applyStateIfNeeded()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.messageHandlerName else { return }
            guard let body = message.body as? [String: Any] else { return }

            Task { @MainActor [weak self] in
                self?.handleEditorMessage(body)
            }
        }

        @MainActor
        private func handleEditorMessage(_ body: [String: Any]) {
            guard let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                isReady = true
                applyStateIfNeeded()

            case "documentChanged":
                guard let markdown = body["markdown"] as? String else { return }
                state.receiveEditorMarkdown(markdown)

            case "selectionChanged":
                let summary = body["summary"] as? String ?? ""
                state.updateSelectionSummary(summary)

            case "requestInsertLink":
                state.beginInsertLinkFlow()

            case "requestInsertImage":
                state.beginInsertImageFlow()

            case "openProtectedBlock":
                guard let id = body["id"] as? String else { return }
                state.openProtectedBlockEditor(id: id)

            default:
                break
            }
        }

        private func applyDocumentIfNeeded() {
            guard let webView else { return }
            guard state.documentRevision != lastAppliedRevision else { return }

            let payload: [String: Any] = [
                "markdown": state.editorMarkdown
            ]

            guard let jsObject = serializedJavaScriptObject(payload) else { return }

            webView.evaluateJavaScript("window.MDbeatyEditor?.setDocument(\(jsObject));", completionHandler: nil)
            lastAppliedRevision = state.documentRevision
        }

        private func applyCommandIfNeeded() {
            guard let request = state.pendingEditorCommand else { return }
            guard request.id != lastHandledCommandID else { return }
            guard let webView else { return }

            var payload: [String: Any] = [
                "name": request.command.rawValue
            ]

            if let commandPayload = request.payload {
                payload["payload"] = commandPayload
            } else {
                payload["payload"] = NSNull()
            }

            guard let jsObject = serializedJavaScriptObject(payload) else { return }

            webView.evaluateJavaScript("window.MDbeatyEditor?.runCommand(\(jsObject));", completionHandler: nil)
            lastHandledCommandID = request.id
        }

        private func serializedJavaScriptObject(_ payload: [String: Any]) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
    }
}
