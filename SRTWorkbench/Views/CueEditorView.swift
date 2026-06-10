import SwiftUI

struct CueEditorView: View {
    @Bindable var viewModel: ReviewViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Cues")
                    .font(.headline)

                Chip(text: "\(viewModel.cues.count)", tint: .secondary)

                Spacer()

                let issues = viewModel.complianceViolations.count
                if issues > 0 {
                    Chip(text: "\(issues) \(issues == 1 ? "issue" : "issues")",
                         systemImage: "exclamationmark.triangle.fill",
                         tint: .orange)
                        .help(viewModel.complianceSummary)
                } else if !viewModel.cues.isEmpty {
                    Chip(text: "Compliant", systemImage: "checkmark.seal.fill", tint: .green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.bar)

            Divider()

            // Cue list — card-style rows on the recessed canvas
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(viewModel.cues.enumerated()), id: \.element.id) { index, cue in
                        CueRowView(
                            index: index,
                            cue: cue,
                            isActive: viewModel.activeCueIndex == index,
                            onJump: {
                                if let time = viewModel.jumpToCue(at: index) {
                                    NotificationCenter.default.post(
                                        name: .seekToTime,
                                        object: nil,
                                        userInfo: ["time": time]
                                    )
                                }
                            },
                            onStartChanged: { tc in viewModel.updateCueStart(at: index, timecode: tc) },
                            onEndChanged: { tc in viewModel.updateCueEnd(at: index, timecode: tc) },
                            onTextChanged: { text in viewModel.updateCueText(at: index, text: text) }
                        )
                        .id(cue.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .canvasBackground()
                .onChange(of: viewModel.activeCueIndex) { _, newIndex in
                    if let idx = newIndex, viewModel.cues.indices.contains(idx) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(viewModel.cues[idx].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

extension Notification.Name {
    static let seekToTime = Notification.Name("seekToTime")
    static let togglePlayback = Notification.Name("togglePlayback")
    static let skipBackward = Notification.Name("skipBackward")
    static let skipForward = Notification.Name("skipForward")
    static let setPlaybackSpeed = Notification.Name("setPlaybackSpeed")
}
