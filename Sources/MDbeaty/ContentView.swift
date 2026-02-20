import SwiftUI

struct ContentView: View {
    @ObservedObject var state: ViewerState

    var body: some View {
        MarkdownWebView(html: state.renderedHTML, baseURL: state.baseURL)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                state.open(url: url)
                return true
            }
        .frame(minWidth: 880, minHeight: 600)
    }
}
