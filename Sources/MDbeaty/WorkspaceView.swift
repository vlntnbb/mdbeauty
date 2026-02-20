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

            Button {
                workspace.openEmptyTab()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .keyboardShortcut("t")
            .help("New Tab")
        }
        .clipped()
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        if let tab = workspace.selectedTab {
            ContentView(state: tab.state)
                .id(tab.id)
        } else {
            Color.clear
        }
    }
}

private struct TabButton: View {
    let tab: WorkspaceState.Tab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @ObservedObject private var state: ViewerState

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
