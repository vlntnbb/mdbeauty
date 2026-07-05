import SwiftUI
import AppKit

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    let searchQuery: String
    let searchToken: Int
    let searchBackwards: Bool
    let searchReset: Bool
    let onSearchResult: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSearchResult: onSearchResult)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.usesFindPanel = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false

        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = text
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.textView = textView
        context.coordinator.onSearchResult = onSearchResult

        guard !context.coordinator.isApplyingProgrammaticUpdate else { return }
        if textView.string != text {
            context.coordinator.isApplyingProgrammaticUpdate = true
            textView.string = text
            context.coordinator.isApplyingProgrammaticUpdate = false
        }

        context.coordinator.performSearchIfNeeded(
            query: searchQuery,
            token: searchToken,
            backwards: searchBackwards,
            reset: searchReset
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var isApplyingProgrammaticUpdate = false
        var onSearchResult: (Int) -> Void
        private var lastSearchToken = -1

        init(text: Binding<String>, onSearchResult: @escaping (Int) -> Void) {
            _text = text
            self.onSearchResult = onSearchResult
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticUpdate else { return }
            guard let textView else { return }
            text = textView.string
        }

        @MainActor
        func performSearchIfNeeded(
            query: String,
            token: Int,
            backwards: Bool,
            reset: Bool
        ) {
            guard let textView else { return }
            let fullText = textView.string as NSString
            let count = query.isEmpty ? 0 : countMatches(in: fullText, query: query)
            onSearchResult(count)

            guard token != lastSearchToken else { return }
            lastSearchToken = token

            guard !query.isEmpty else { return }
            guard fullText.length > 0 else { return }
            guard count > 0 else { return }

            let options: NSString.CompareOptions = backwards ? [.caseInsensitive, .backwards] : [.caseInsensitive]
            let currentSelection = textView.selectedRange()

            let startLocation: Int
            if reset {
                startLocation = backwards ? fullText.length : 0
            } else {
                startLocation = backwards
                    ? currentSelection.location
                    : min(currentSelection.location + currentSelection.length, fullText.length)
            }

            let primaryRange: NSRange
            if backwards {
                primaryRange = NSRange(location: 0, length: max(0, startLocation))
            } else {
                primaryRange = NSRange(location: max(0, startLocation), length: max(0, fullText.length - startLocation))
            }

            var found = fullText.range(of: query, options: options, range: primaryRange)

            if found.location == NSNotFound {
                let wrappedRange = NSRange(location: 0, length: fullText.length)
                found = fullText.range(of: query, options: options, range: wrappedRange)
            }

            guard found.location != NSNotFound else { return }
            textView.setSelectedRange(found)
            textView.scrollRangeToVisible(found)
        }

        private func countMatches(in text: NSString, query: String) -> Int {
            var count = 0
            var searchRange = NSRange(location: 0, length: text.length)

            while searchRange.length > 0 {
                let match = text.range(of: query, options: .caseInsensitive, range: searchRange)
                guard match.location != NSNotFound else { break }
                count += 1

                let nextLocation = match.location + max(match.length, 1)
                guard nextLocation <= text.length else { break }
                searchRange = NSRange(location: nextLocation, length: text.length - nextLocation)
            }

            return count
        }
    }
}
