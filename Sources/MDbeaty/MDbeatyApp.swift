import SwiftUI
import AppKit

@main
struct MDbeatyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceState()
    @State private var didProcessLaunchArgument = false

    var body: some Scene {
        Window("MDbeaty", id: "main") {
            WorkspaceView(workspace: workspace)
                .onAppear {
                    appDelegate.workspaceState = workspace
                    appDelegate.expandMainWindowIfNeeded()
                    guard !didProcessLaunchArgument else { return }
                    didProcessLaunchArgument = true
                    openLaunchArgumentIfNeeded()
                }
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    workspace.openFromExternal(url: url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    workspace.openWithSystemPanel()
                }
                .keyboardShortcut("o")

                Menu("Recent") {
                    if workspace.recentMarkdownURLs.isEmpty {
                        Button("No Recent Files") {}
                            .disabled(true)
                    } else {
                        ForEach(workspace.recentMarkdownURLs, id: \.absoluteString) { url in
                            Button(url.lastPathComponent) {
                                workspace.openRecent(url: url)
                            }
                            .help(url.path)
                        }
                    }

                    Divider()

                    Button("Clear Menu") {
                        workspace.clearRecentFiles()
                    }
                    .disabled(workspace.recentMarkdownURLs.isEmpty)
                }

                Divider()

                Button("Reload") {
                    workspace.reloadSelectedTab()
                }
                .keyboardShortcut("r")
                .disabled(!workspace.canReloadSelectedTab)
            }
        }
    }

    private func openLaunchArgumentIfNeeded() {
        guard let path = CommandLine.arguments.dropFirst().first else { return }

        if let url = URL(string: path), url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            workspace.openAtLaunch(url: url)
            return
        }

        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        workspace.openAtLaunch(url: fileURL)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var workspaceState: WorkspaceState? {
        didSet {
            flushPendingOpenRequests()
        }
    }

    private var didExpandWindow = false
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        DispatchQueue.main.async { [weak self] in
            self?.expandMainWindowIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        expandMainWindowIfNeeded()
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openOrQueue(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        for name in filenames {
            openOrQueue(URL(fileURLWithPath: name))
        }
        application.reply(toOpenOrPrint: .success)
    }

    private func openOrQueue(_ url: URL) {
        guard let workspaceState else {
            pendingOpenURLs.append(url)
            return
        }
        workspaceState.openFromExternal(url: url)
    }

    private func flushPendingOpenRequests() {
        guard let workspaceState, !pendingOpenURLs.isEmpty else { return }
        pendingOpenURLs.forEach { workspaceState.openFromExternal(url: $0) }
        pendingOpenURLs.removeAll()
    }

    func expandMainWindowIfNeeded() {
        guard !didExpandWindow else { return }

        guard let window =
            NSApp.mainWindow ??
            NSApp.windows.first(where: { $0.isVisible }) ??
            NSApp.windows.first
        else {
            return
        }

        guard let screen = window.screen ?? NSScreen.main else {
            return
        }

        window.setFrame(screen.visibleFrame, display: true, animate: false)
        didExpandWindow = true
    }
}
