import SwiftUI

struct ContentView: View {
    @ObservedObject var state: DocumentState
    let onOpenMarkdownLink: ((URL) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if state.mode == .edit {
                editorToolbar
                if !state.protectedBlocks.isEmpty {
                    protectedBlocksBar
                }
                Divider()
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
        .frame(minWidth: 880, minHeight: 600)
    }

    private var previewView: some View {
        MarkdownWebView(
            html: state.renderedHTML,
            baseURL: state.baseURL,
            onOpenMarkdownLink: onOpenMarkdownLink
        )
    }

    @ViewBuilder
    private var editView: some View {
        if state.fileURL == nil {
            VStack(spacing: 10) {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("Open a Markdown file to start editing")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            MarkdownEditorWebView(state: state)
        }
    }

    private var protectedBlocksBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.protectedBlocks) { block in
                    Button {
                        state.openProtectedBlockEditor(id: block.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 11, weight: .semibold))
                            Text(block.title)
                                .lineLimit(1)
                            Text("Edit as Markdown")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.thinMaterial)
    }

    private var editorToolbar: some View {
        HStack(spacing: 6) {
            EditorToolbarButton(symbol: "textformat.size.larger", action: { state.issueEditorCommand(.h1) })
            EditorToolbarButton(symbol: "textformat.size", action: { state.issueEditorCommand(.h2) })
            Divider().frame(height: 18)
            EditorToolbarButton(symbol: "bold", action: { state.issueEditorCommand(.bold) })
            EditorToolbarButton(symbol: "italic", action: { state.issueEditorCommand(.italic) })
            Divider().frame(height: 18)
            EditorToolbarButton(symbol: "list.bullet", action: { state.issueEditorCommand(.bulletList) })
            EditorToolbarButton(symbol: "list.number", action: { state.issueEditorCommand(.orderedList) })
            EditorToolbarButton(symbol: "text.quote", action: { state.issueEditorCommand(.quote) })
            EditorToolbarButton(symbol: "curlybraces", action: { state.issueEditorCommand(.code) })
            Divider().frame(height: 18)
            EditorToolbarButton(symbol: "link", action: { state.beginInsertLinkFlow() })
            EditorToolbarButton(symbol: "photo", action: { state.beginInsertImageFlow() })
            Divider().frame(height: 18)
            EditorToolbarButton(symbol: "arrow.uturn.backward", action: { state.issueEditorCommand(.undo) })
            EditorToolbarButton(symbol: "arrow.uturn.forward", action: { state.issueEditorCommand(.redo) })
            Spacer(minLength: 0)
            if !state.selectionSummary.isEmpty {
                Text(state.selectionSummary)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial)
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

private struct EditorToolbarButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
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
