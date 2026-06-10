import SwiftUI

struct ReviewView: View {
    @Bindable var viewModel: ReviewViewModel
    @State private var showIssuesPopover = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoaded {
                HSplitView {
                    // Video player (left), framed on the canvas
                    VStack {
                        VideoPlayerView(
                            videoURL: viewModel.videoURL!,
                            captionText: viewModel.activeCueText,
                            onTimeUpdate: { time in
                                viewModel.currentTime = time
                            }
                        )
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.quaternary, lineWidth: 1)
                        )
                        .padding(12)
                    }
                    .frame(minWidth: 420)
                    .canvasBackground()

                    // Cue editor (right)
                    CueEditorView(viewModel: viewModel)
                        .frame(minWidth: 320, idealWidth: 420)
                }

                // Keyboard shortcut hints + save status
                Divider()
                HStack(spacing: 18) {
                    shortcutHint("Play / Pause", keys: "\u{2318}\u{23CE}")
                    shortcutHint("Back 5s", keys: "\u{2318}\u{2190}")
                    shortcutHint("Forward 5s", keys: "\u{2318}\u{2192}")
                    shortcutHint("Speed", keys: "\u{2318}D")
                    shortcutHint("Save", keys: "\u{2318}S")

                    Spacer()

                    if viewModel.document.isDirty {
                        Chip(text: "Unsaved changes", systemImage: "circle.fill", tint: .orange)
                    } else if !viewModel.saveStatusMessage.isEmpty {
                        Text(viewModel.saveStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(.bar)
            } else {
                ContentUnavailableView {
                    Label("Nothing Loaded", systemImage: "play.rectangle.on.rectangle")
                } description: {
                    Text("Drop a video and SRT file anywhere in this window,\nor choose them manually.")
                } actions: {
                    HStack(spacing: 12) {
                        Button("Choose Video…") { viewModel.pickVideoFile() }
                        Button("Choose SRT…") { viewModel.pickSRTFile() }
                    }
                }
                .canvasBackground()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.pickVideoFile()
                } label: {
                    Label("Video", systemImage: "film")
                        .labelStyle(.titleAndIcon)
                }
                .help("Choose a video file")

                Button {
                    viewModel.pickSRTFile()
                } label: {
                    Label("SRT", systemImage: "captions.bubble")
                        .labelStyle(.titleAndIcon)
                }
                .help("Choose an SRT file")
            }

            ToolbarItemGroup {
                if viewModel.isLoaded {
                    complianceBadge

                    Button {
                        viewModel.reflowForCompliance()
                    } label: {
                        Label("Reflow", systemImage: "text.alignleft")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Re-wrap all cues to 32-char lines and split over-long cues for ADA/DCMP compliance")
                }

                Button {
                    viewModel.togglePlaybackSpeed()
                } label: {
                    Text(viewModel.playbackSpeed == 1.0 ? "1x" : "2x")
                        .font(.callout.weight(.medium).monospaced())
                        .frame(width: 28)
                }
                .help("Toggle playback speed (\u{2318}D)")

                Button {
                    viewModel.save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(!viewModel.document.isDirty)
                .help("Save the SRT file (\u{2318}S)")
            }
        }
        .alert("Save Error", isPresented: $viewModel.showSaveError) {
            Button("OK") {}
        } message: {
            Text(viewModel.saveErrorMessage)
        }
        // Menu-bar commands (File > Save SRT, Playback > Speed) arrive as
        // notifications so the App scene doesn't need a view-model reference.
        .onReceive(NotificationCenter.default.publisher(for: .saveSRTRequested)) { _ in
            if viewModel.document.isDirty {
                viewModel.save()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePlaybackSpeedRequested)) { _ in
            viewModel.togglePlaybackSpeed()
        }
    }

    // MARK: - Drop handling

    private func handleDrop(_ urls: [URL]) -> Bool {
        var accepted = false
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if GenerateViewModel.videoExtensions.contains(ext) {
                viewModel.loadVideo(from: url)
                accepted = true
            } else if ext == "srt" {
                viewModel.loadSRT(from: url)
                accepted = true
            }
        }
        return accepted
    }

    // MARK: - Compliance badge

    @ViewBuilder
    private var complianceBadge: some View {
        let issues = viewModel.complianceViolations
        if issues.isEmpty {
            Label("ADA compliant", systemImage: "checkmark.seal.fill")
                .labelStyle(.titleAndIcon)
                .font(.callout)
                .foregroundStyle(.green)
                .help("All cues fit 2 lines of 32 characters")
        } else {
            Button {
                showIssuesPopover.toggle()
            } label: {
                Label("\(issues.count) \(issues.count == 1 ? "issue" : "issues")",
                      systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .foregroundStyle(.yellow)
            }
            .help("Show formatting issues")
            .popover(isPresented: $showIssuesPopover, arrowEdge: .bottom) {
                ComplianceIssuesPopover(
                    violations: issues,
                    onJump: { cueIndex in
                        if let time = viewModel.jumpToCue(at: cueIndex) {
                            NotificationCenter.default.post(
                                name: .seekToTime,
                                object: nil,
                                userInfo: ["time": time]
                            )
                        }
                    }
                )
            }
        }
    }

    // MARK: - Shortcut Hint

    private func shortcutHint(_ label: String, keys: String) -> some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.caption.monospaced().weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Compliance issues popover

/// Lists each formatting violation with a jump button. Stays open while
/// stepping through issues; the video seeks and the cue list follows.
struct ComplianceIssuesPopover: View {
    let violations: [ComplianceViolation]
    let onJump: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Formatting Issues")
                    .font(.headline)
                Spacer()
                Chip(text: "\(violations.count)", tint: .orange)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(violations) { violation in
                        HStack(spacing: 8) {
                            Text("Cue \(violation.cueIndex + 1)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .leading)

                            Text(violation.message)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button {
                                onJump(violation.cueIndex)
                            } label: {
                                Image(systemName: "play.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Jump the video to this cue")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
            .frame(maxHeight: 280)

            Divider()

            Text("Reflow fixes these automatically")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
        }
        .frame(width: 340)
    }
}

extension Notification.Name {
    static let saveSRTRequested = Notification.Name("saveSRTRequested")
    static let togglePlaybackSpeedRequested = Notification.Name("togglePlaybackSpeedRequested")
}
