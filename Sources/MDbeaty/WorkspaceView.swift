import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var workspace: WorkspaceState

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider()
            selectedTabContent
        }
        .frame(minWidth: 980, minHeight: 680)
    }

    private var tabStrip: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(workspace.tabs) { tab in
                    TabButton(
                        tab: tab,
                        isSelected: tab.id == workspace.selectedTabID,
                        onSelect: { workspace.select(tabID: tab.id) },
                        onClose: { workspace.close(tabID: tab.id) }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)

            modeAndStatusControls

            Button {
                workspace.openEmptyTab()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("t")
            .help("New Tab")
            .padding(.trailing, 10)
        }
        .clipped()
        .frame(height: 48)
        .background(.ultraThinMaterial)
    }

    private var modeAndStatusControls: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { workspace.selectedMode },
                set: { workspace.setSelectedTabMode($0) }
            )) {
                ForEach(TabMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)

            Text(workspace.selectedSaveStatusLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 68, alignment: .leading)
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        ZStack {
            ForEach(workspace.tabs) { tab in
                ContentView(
                    state: tab.state,
                    onOpenMarkdownLink: { url in
                        workspace.openFromExternal(url: url)
                    }
                )
                .opacity(tab.id == workspace.selectedTabID ? 1 : 0)
                .allowsHitTesting(tab.id == workspace.selectedTabID)
                .accessibilityHidden(tab.id != workspace.selectedTabID)
            }
        }
    }
}

private struct TabButton: View {
    let tab: WorkspaceState.Tab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @ObservedObject private var state: DocumentState

    init(
        tab: WorkspaceState.Tab,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.tab = tab
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onClose = onClose
        _state = ObservedObject(wrappedValue: tab.state)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if state.mode == .edit {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    isSelected
                        ? Color.accentColor.opacity(0.35)
                        : Color.secondary.opacity(0.25),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    private var displayTitle: String {
        state.fileURL?.lastPathComponent ?? "Welcome"
    }
}
