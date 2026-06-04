import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var generateVM = GenerateViewModel()
    @State private var reviewVM = ReviewViewModel()
    @State private var setupManager = SetupManager.shared

    var body: some View {
        VStack(spacing: 0) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            versionFooter
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: - Version Footer

    private var versionFooter: some View {
        HStack(spacing: 5) {
            Spacer()
            Image(systemName: "captions.bubble")
                .font(.caption2)
            Text("SRT Workbench \(Self.appVersionString)")
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(.bar)
        .help(Self.appVersionDetail)
    }

    /// Marketing version (e.g. "v1.3.0"), read from the app bundle.
    static var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(short)"
    }

    /// Full version + build, for the footer tooltip.
    static var appVersionDetail: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (build \(build))"
    }
}

#Preview {
    ContentView()
}
