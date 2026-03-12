import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var generateVM = GenerateViewModel()
    @State private var reviewVM = ReviewViewModel()
    @State private var setupManager = SetupManager.shared

    var body: some View {
        Group {
            if setupManager.stage == .ready || setupManager.isReady {
                TabView(selection: $selectedTab) {
                    GenerateView(viewModel: generateVM, onComplete: { videoURL, srtURL in
                        reviewVM.loadVideo(from: videoURL)
                        reviewVM.loadSRT(from: srtURL)
                        selectedTab = 1
                    })
                    .tabItem {
                        Label("Generate", systemImage: "waveform")
                    }
                    .tag(0)

                    ReviewView(viewModel: reviewVM)
                        .tabItem {
                            Label("Review & Edit", systemImage: "play.rectangle")
                        }
                        .tag(1)
                }
            } else {
                FirstRunView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
