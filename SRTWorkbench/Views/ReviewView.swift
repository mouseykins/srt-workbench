import SwiftUI

struct ReviewView: View {
    @Bindable var viewModel: ReviewViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar area
            HStack(spacing: 12) {
                Button("Video...") { viewModel.pickVideoFile() }
                Button("SRT...") { viewModel.pickSRTFile() }

                Spacer()

                if viewModel.document.isDirty {
                    Text("Unsaved changes")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else if !viewModel.saveStatusMessage.isEmpty {
                    Text(viewModel.saveStatusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button(action: { viewModel.togglePlaybackSpeed() }) {
                    Text(viewModel.playbackSpeed == 1.0 ? "1x" : "2x")
                        .font(.callout.weight(.medium).monospaced())
                        .frame(width: 32)
                }
                .buttonStyle(.bordered)
                .help("Toggle playback speed (\u{2318}D)")

                Button(action: { viewModel.save() }) {
                    Label("Save SRT", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!viewModel.document.isDirty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if viewModel.isLoaded {
                HSplitView {
                    // Video player (left)
                    VideoPlayerView(
                        videoURL: viewModel.videoURL!,
                        captionText: viewModel.activeCueText,
                        onTimeUpdate: { time in
                            viewModel.currentTime = time
                        }
                    )
                    .frame(minWidth: 400)

                    // Cue editor (right)
                    CueEditorView(viewModel: viewModel)
                        .frame(minWidth: 300, idealWidth: 400)
                }

                // Keyboard shortcut hint bar
                Divider()
                HStack(spacing: 20) {
                    shortcutHint("Play / Pause", keys: "\u{2318}\u{23CE}")
                    shortcutHint("Back 5s", keys: "\u{2318}\u{2190}")
                    shortcutHint("Forward 5s", keys: "\u{2318}\u{2192}")
                    shortcutHint("Speed 1x/2x", keys: "\u{2318}D")
                    shortcutHint("Save", keys: "\u{2318}S")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.bar)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Select a video and SRT file to begin")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Choose Video...") { viewModel.pickVideoFile() }
                        Button("Choose SRT...") { viewModel.pickSRTFile() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Hidden buttons to wire up keyboard shortcuts
            hiddenShortcutButtons
        }
        .alert("Save Error", isPresented: $viewModel.showSaveError) {
            Button("OK") {}
        } message: {
            Text(viewModel.saveErrorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .alignmentCompleted)) { notification in
            if let srtURL = notification.userInfo?["srtURL"] as? URL {
                viewModel.loadSRT(from: srtURL)
            }
            if let videoURL = notification.userInfo?["videoURL"] as? URL {
                viewModel.loadVideo(from: videoURL)
            }
        }
    }

    // MARK: - Shortcut Hint

    private func shortcutHint(_ label: String, keys: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.callout.monospaced().weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Hidden Shortcut Buttons

    @ViewBuilder
    private var hiddenShortcutButtons: some View {
        // Cmd+Return — Play/Pause
        Button("") {
            NotificationCenter.default.post(name: .togglePlayback, object: nil)
        }
        .keyboardShortcut(.return, modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)

        // Cmd+Left — Skip back 5s
        Button("") {
            NotificationCenter.default.post(name: .skipBackward, object: nil)
        }
        .keyboardShortcut(.leftArrow, modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)

        // Cmd+Right — Skip forward 5s
        Button("") {
            NotificationCenter.default.post(name: .skipForward, object: nil)
        }
        .keyboardShortcut(.rightArrow, modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)

        // Cmd+D — Toggle playback speed
        Button("") {
            viewModel.togglePlaybackSpeed()
        }
        .keyboardShortcut("d", modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}
