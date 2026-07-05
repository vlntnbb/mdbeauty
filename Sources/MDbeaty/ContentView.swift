import SwiftUI

struct ContentView: View {
    @ObservedObject var state: DocumentState
    let onOpenMarkdownLink: ((URL) -> Void)?
    @State private var isSearchPresented = false
    @State private var searchQuery = ""
    @State private var searchMatchCount = 0
    @State private var searchToken = 0
    @State private var searchBackwards = false
    @State private var searchReset = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isSearchPresented {
                searchBar
            }

            if state.mode == .preview {
                previewView
            } else {
                editView
            }

            if state.hasConflict {
                conflictBanner
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            state.open(url: url)
            return true
        }
        .sheet(isPresented: $state.isCompareSheetPresented) {
            ConflictCompareSheet(
                localMarkdown: state.compareLocalMarkdown,
                incomingMarkdown: state.compareIncomingMarkdown
            )
        }
        .onChange(of: state.findRequestToken) { _ in
            presentSearchBar()
        }
        .onChange(of: state.mode) { _ in
            triggerSearch(reset: true, backwards: false)
        }
        .frame(minWidth: 880, minHeight: 600)
    }

    private var previewView: some View {
        MarkdownWebView(
            html: state.renderedHTML,
            baseURL: state.baseURL,
            onOpenMarkdownLink: onOpenMarkdownLink,
            printRequest: state.printRequest,
            suggestedPDFFileName: state.suggestedPDFFileName,
            searchQuery: searchQuery,
            searchToken: searchToken,
            searchBackwards: searchBackwards,
            searchReset: searchReset,
            onSearchResult: { matchCount in
                searchMatchCount = matchCount
            }
        )
    }

    @ViewBuilder
    private var editView: some View {
        if state.fileURL == nil {
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("Open a Markdown file to start editing")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            MarkdownTextEditor(
                text: Binding(
                    get: { state.editorMarkdown },
                    set: { state.receiveEditorMarkdown($0) }
                ),
                searchQuery: searchQuery,
                searchToken: searchToken,
                searchBackwards: searchBackwards,
                searchReset: searchReset,
                onSearchResult: { matchCount in
                    searchMatchCount = matchCount
                }
            )
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find in document", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    triggerSearch(reset: false, backwards: false)
                }
                .onChange(of: searchQuery) { newValue in
                    if newValue.isEmpty {
                        hideSearchBar(clearQuery: false)
                        return
                    }
                    triggerSearch(reset: true, backwards: false)
                }

            Text(searchMatchCount > 0 ? "\(searchMatchCount) matches" : "No matches")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .leading)

            Button {
                triggerSearch(reset: false, backwards: true)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(searchQuery.isEmpty)
            .help("Find Previous")

            Button {
                triggerSearch(reset: false, backwards: false)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(searchQuery.isEmpty)
            .help("Find Next")

            Button {
                hideSearchBar()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Search")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private func triggerSearch(reset: Bool, backwards: Bool) {
        searchBackwards = backwards
        searchReset = reset
        searchToken &+= 1
    }

    private func presentSearchBar() {
        if !isSearchPresented {
            isSearchPresented = true
        }
        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }

    private func hideSearchBar(clearQuery: Bool = true) {
        if clearQuery {
            searchQuery = ""
        }
        searchMatchCount = 0
        isSearchPresented = false
        isSearchFieldFocused = false
        triggerSearch(reset: true, backwards: false)
    }

    private var conflictBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("File changed on disk while you had local edits.")
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 0)
            Button("Reload") {
                state.resolveConflictByReloadingFromDisk()
            }
            Button("Keep Mine") {
                state.resolveConflictKeepMine()
            }
            Button("Compare") {
                state.openConflictComparison()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .overlay(
            Rectangle()
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct ConflictCompareSheet: View {
    @Environment(\.dismiss) private var dismiss

    let localMarkdown: String
    let incomingMarkdown: String

    var body: some View {
        VStack(spacing: 10) {
            Text("Compare local vs disk")
                .font(.headline)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Local")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(localMarkdown)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("From Disk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(incomingMarkdown)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(minWidth: 840, minHeight: 460)
    }
}
