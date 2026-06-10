import SwiftUI

struct GenerateView: View {
    @Bindable var viewModel: GenerateViewModel
    var onComplete: (URL, URL) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                directoryBar

                HStack(alignment: .top, spacing: 14) {
                    videoCard
                    scriptCard
                }

                filtersCard
            }
            .padding(20)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .canvasBackground()
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.handleDroppedFiles(urls)
        }
        .sheet(isPresented: $viewModel.showScriptPreview) {
            ScriptPreviewSheet(
                heading: viewModel.previewHeading,
                lines: viewModel.previewLines,
                videoStem: viewModel.selectedVideo?.deletingPathExtension().lastPathComponent
            )
        }
        .alert("Alignment Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Directory bar

    private var directoryBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                if let dir = viewModel.mediaDirectory {
                    Text(dir.path)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(viewModel.availableVideos.count) videos · \(viewModel.availableScripts.count) scripts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No media folder selected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Pick a folder to choose videos and scripts from a list")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if viewModel.mediaDirectory != nil {
                Button {
                    viewModel.refreshFileLists()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Rescan the folder")
            }

            Button("Choose Folder…") {
                viewModel.pickMediaDirectory()
            }
        }
        .padding(12)
        .card()
    }

    // MARK: - File cards

    private var videoCard: some View {
        FileSlotCard(
            title: "Video",
            icon: "film",
            emptyHint: "Drop a video here",
            fileURL: viewModel.selectedVideo,
            metadata: videoMetadata,
            folderFiles: viewModel.availableVideos,
            allowedExtensions: GenerateViewModel.videoExtensions,
            onSelect: { viewModel.selectedVideo = $0 },
            onClear: { viewModel.selectedVideo = nil },
            onBrowse: { viewModel.pickVideoFile() }
        )
    }

    private var scriptCard: some View {
        FileSlotCard(
            title: "Script",
            icon: "doc.text",
            emptyHint: "Drop a .docx script here",
            fileURL: viewModel.selectedScript,
            metadata: viewModel.selectedScript.flatMap(Self.fileSizeString),
            folderFiles: viewModel.availableScripts,
            allowedExtensions: GenerateViewModel.scriptExtensions,
            onSelect: { viewModel.selectedScript = $0 },
            onClear: { viewModel.selectedScript = nil },
            onBrowse: { viewModel.pickScriptFile() }
        )
    }

    private var videoMetadata: String? {
        guard let url = viewModel.selectedVideo else { return nil }
        let size = Self.fileSizeString(url)
        switch (viewModel.videoDurationText, size) {
        case let (duration?, size?): return "\(duration) · \(size)"
        case let (duration?, nil): return duration
        case let (nil, size?): return size
        default: return nil
        }
    }

    static func fileSizeString(_ url: URL) -> String? {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        guard let bytes = attributes[.size] as? Int else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Filters card

    private var filtersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Text Filters", systemImage: "line.3.horizontal.decrease.circle")

            HStack(alignment: .top, spacing: 28) {
                Toggle(isOn: $viewModel.filterStageDirections) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("[Stage directions]")
                        Text("Skip lines wrapped in [brackets]")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Toggle(isOn: $viewModel.filterSlideNumbers) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("(Slide numbers)")
                        Text("Strip references like (1) or 1:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Custom patterns (comma or newline separated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("e.g.  ^Slide \\d+$", text: $viewModel.customFilterPatternsText, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)

                    Button {
                        Task { await viewModel.previewScriptExtraction() }
                    } label: {
                        if viewModel.isLoadingPreview {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 110)
                        } else {
                            Label("Preview", systemImage: "eye")
                                .frame(width: 110)
                        }
                    }
                    .disabled(!viewModel.canPreview)
                    .help("Show exactly which script lines will be aligned, without running alignment")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Bottom bar (status + run)

    private var bottomBar: some View {
        VStack(spacing: 12) {
            switch viewModel.alignmentService.state {
            case .idle:
                EmptyView()
            case .running(let currentStep):
                progressCard(currentStep: currentStep)
            case .complete(let srtURL):
                successCard(srtURL: srtURL)
            case .failed(let message):
                failureCard(message: message)
            }

            if !viewModel.isRunning {
                Button {
                    Task {
                        await viewModel.runAlignment()
                        if case .complete(let srtURL) = viewModel.alignmentService.state,
                           let video = viewModel.selectedVideo {
                            onComplete(video, srtURL)
                        }
                    }
                } label: {
                    Label("Run Alignment", systemImage: "waveform.badge.plus")
                }
                .buttonStyle(HeroButtonStyle())
                .disabled(!viewModel.canRun)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Progress card

    private func progressCard(currentStep: AlignmentStep) -> some View {
        VStack(spacing: 14) {
            StepIndicator(steps: AlignmentStep.allCases, currentStep: currentStep)

            VStack(spacing: 5) {
                HStack(spacing: 10) {
                    ProgressView(value: viewModel.alignmentService.progressPercent, total: 100)
                        .tint(Color.accentColor)

                    Button("Cancel") {
                        viewModel.cancelAlignment()
                    }
                    .controlSize(.small)
                }

                HStack {
                    Text(viewModel.alignmentService.stageText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    elapsedTimeText
                }
            }

            if viewModel.alignmentService.matchedSection != nil || viewModel.alignmentService.runInfo != nil {
                HStack(spacing: 8) {
                    if let section = viewModel.alignmentService.matchedSection {
                        Chip(text: section, systemImage: "doc.text.magnifyingglass", tint: .accentColor)
                            .lineLimit(1)
                    }
                    if let info = viewModel.alignmentService.runInfo {
                        Chip(text: info, systemImage: "waveform", tint: .secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .card()
    }

    /// Elapsed-time readout, ticking once per second while a run is active.
    @ViewBuilder
    private var elapsedTimeText: some View {
        if let startedAt = viewModel.alignmentService.startedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(startedAt))
                Text(String(format: "%d:%02d elapsed", elapsed / 60, elapsed % 60))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Success / failure cards

    private func successCard(srtURL: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 26))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Caption file ready")
                    .font(.headline)
                Text(srtURL.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Review Captions") {
                if let video = viewModel.selectedVideo {
                    onComplete(video, srtURL)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .card()
    }

    private func failureCard(message: String) -> some View {
        let firstLine = message.components(separatedBy: "\n").first ?? message
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alignment failed")
                        .font(.headline)
                    Text(firstLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            DisclosureGroup("Details") {
                ScrollView {
                    Text(message)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)

                HStack {
                    Button("Copy Details") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message, forType: .string)
                    }
                    Button("Copy Diagnostics") {
                        Task { await DiagnosticsService.copyReportToClipboard() }
                    }
                    .help("Copies app/Python versions, environment info, and recent log lines — paste into a bug report")
                    Spacer()
                }
                .padding(.top, 4)
            }
            .font(.callout)
        }
        .padding(14)
        .card()
    }
}

// MARK: - File slot card

/// A drop-target card for one input file (video or script). Shows a dashed
/// drop hint when empty and file metadata when filled; highlights while a
/// compatible file is dragged over it.
struct FileSlotCard: View {
    let title: String
    let icon: String
    let emptyHint: String
    let fileURL: URL?
    let metadata: String?
    let folderFiles: [URL]
    let allowedExtensions: Set<String>
    let onSelect: (URL) -> Void
    let onClear: () -> Void
    let onBrowse: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: title, systemImage: icon)

            if let url = fileURL {
                filledContent(url)
            } else {
                emptyContent
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { allowedExtensions.contains($0.pathExtension.lowercased()) }) else {
                return false
            }
            onSelect(url)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    private var emptyContent: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)

            Text(emptyHint)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Browse…", action: onBrowse)
                    .controlSize(.small)

                if !folderFiles.isEmpty {
                    folderMenu(label: "From Folder")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96)
    }

    private func filledContent(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let metadata {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear selection")
            }

            HStack(spacing: 8) {
                Button("Browse…", action: onBrowse)
                    .controlSize(.small)
                if !folderFiles.isEmpty {
                    folderMenu(label: "From Folder")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
    }

    private func folderMenu(label: String) -> some View {
        Menu(label) {
            ForEach(folderFiles, id: \.self) { url in
                Button(url.lastPathComponent) {
                    onSelect(url)
                }
            }
        }
        .controlSize(.small)
        .fixedSize()
    }
}

// MARK: - Script extraction preview

/// Shows the exact lines the aligner would receive — the fast way to check
/// filter patterns and section matching before a long alignment run.
struct ScriptPreviewSheet: View {
    let heading: String?
    let lines: [String]
    let videoStem: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Script Extraction Preview")
                        .font(.headline)
                    if let heading {
                        Label("Matched section: \(heading)", systemImage: "doc.text.magnifyingglass")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if videoStem != nil {
                        Label("No section matched — using whole document", systemImage: "doc.text")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Chip(text: "\(lines.count) lines · \(wordCount) words", tint: .accentColor)
            }
            .padding()

            Divider()

            if lines.isEmpty {
                ContentUnavailableView(
                    "No spoken lines found",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Check the filter patterns — they may be removing everything.")
                )
            } else {
                List(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 32, alignment: .trailing)
                        Text(line)
                            .textSelection(.enabled)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var wordCount: Int {
        lines.reduce(0) { $0 + $1.split(separator: " ").count }
    }
}
