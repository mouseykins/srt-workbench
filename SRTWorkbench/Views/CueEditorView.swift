import SwiftUI

struct CueEditorView: View {
    @Bindable var viewModel: ReviewViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Cues")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.cues.count) entries")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Cue list
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
                            onDelete: { viewModel.deleteCue(at: index) },
                            onStartChanged: { tc in viewModel.updateCueStart(at: index, timecode: tc) },
                            onEndChanged: { tc in viewModel.updateCueEnd(at: index, timecode: tc) },
                            onTextChanged: { text in viewModel.updateCueText(at: index, text: text) }
                        )
                        .id(cue.id)
                        .listRowBackground(
                            viewModel.activeCueIndex == index
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear
                        )
                    }
                }
                .listStyle(.plain)
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
