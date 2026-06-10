import SwiftUI

enum AppScreen: String, Hashable {
    case generate
    case review
}

struct ContentView: View {
    @State private var screen: AppScreen = .generate
    @State private var generateVM = GenerateViewModel()
    @State private var reviewVM = ReviewViewModel()
    @State private var setupManager = SetupManager.shared

    var body: some View {
        Group {
            if setupManager.stage == .ready || setupManager.isReady {
                mainInterface
            } else {
                FirstRunView()
            }
        }
        .frame(minWidth: 1000, minHeight: 660)
    }

    // MARK: - Main shell

    private var mainInterface: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Manual selection: button rows driving `screen` directly.
                // (List selection / NavigationLink value-routing both fail to
                // switch the detail pane in this NavigationSplitView setup.)
                List {
                    Section("Workflow") {
                        sidebarRow(.generate, title: "Generate", icon: "waveform.badge.plus")
                        sidebarRow(.review, title: "Review & Edit", icon: "play.rectangle.on.rectangle",
                                   badgeCount: reviewVM.isLoaded ? reviewVM.complianceViolations.count : 0)
                    }
                }
                .listStyle(.sidebar)

                versionFooter
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
        } detail: {
            switch screen {
            case .generate:
                GenerateView(viewModel: generateVM, onComplete: { videoURL, srtURL in
                    reviewVM.loadVideo(from: videoURL)
                    reviewVM.loadSRT(from: srtURL)
                    screen = .review
                })
                .navigationTitle("Generate")

            case .review:
                ReviewView(viewModel: reviewVM)
                    .navigationTitle("Review & Edit")
                    .navigationSubtitle(reviewVM.videoURL?.lastPathComponent ?? "")
            }
        }
    }

    // MARK: - Sidebar rows

    private func sidebarRow(_ target: AppScreen, title: String, icon: String, badgeCount: Int = 0) -> some View {
        Button {
            screen = target
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(screen == target ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                Text(title)
                Spacer()
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(screen == target ? Color.accentColor.opacity(0.22) : Color.clear)
                .padding(.horizontal, 6)
        )
    }

    // MARK: - Version Footer

    private var versionFooter: some View {
        HStack(spacing: 5) {
            Image(systemName: "captions.bubble")
                .font(.caption2)
            Text("SRT Workbench \(Self.appVersionString)")
                .font(.caption2)
            Spacer()
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .help(Self.appVersionDetail)
    }

    /// Marketing version (e.g. "v2.0.0"), read from the app bundle.
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
