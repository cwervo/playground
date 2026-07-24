import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DNSViewModel()
    
    var body: some View {
        TabView {
            NodeNetworkView(viewModel: viewModel)
                .tabItem {
                    Label("Network", systemImage: "network")
                }
            
            BookView(viewModel: viewModel)
                .tabItem {
                    Label("Phonebook", systemImage: "book.closed.fill")
                }
            
            DNSTimelineView(viewModel: viewModel)
                .tabItem {
                    Label("Timeline", systemImage: "clock.fill")
                }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
