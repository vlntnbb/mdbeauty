import SwiftUI

struct ContentView: View {
    @ObservedObject var state: DocumentState
    let onOpenMarkdownLink: ((URL) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
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
                )
            )
        }
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
