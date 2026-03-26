import SwiftUI

struct GenerateView: View {
    @Bindable var viewModel: GenerateViewModel
    var onComplete: (URL, URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Media Directory") {
                    HStack {
                        Text(viewModel.mediaDirectory?.path ?? "No directory selected")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Browse...") {
                            viewModel.pickMediaDirectory()
                        }
                    }
                }

                Section("Video") {
                    if !viewModel.availableVideos.isEmpty {
                        Picker("From directory", selection: $viewModel.selectedVideo) {
                            Text("Select a video...").tag(nil as URL?)
                            ForEach(viewModel.availableVideos, id: \.self) { url in
                                Text(url.lastPathComponent).tag(url as URL?)
                            }
                        }
                    }

                    HStack {
                        if let video = viewModel.selectedVideo {
                            Label(video.lastPathComponent, systemImage: "film")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No video selected")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose File...") {
                            viewModel.pickVideoFile()
                        }
                    }
                }

                Section("Script (.docx)") {
                    if !viewModel.availableScripts.isEmpty {
                        Picker("From directory", selection: $viewModel.selectedScript) {
                            Text("Select a script...").tag(nil as URL?)
                            ForEach(viewModel.availableScripts, id: \.self) { url in
                                Text(url.lastPathComponent).tag(url as URL?)
                            }
                        }
                    }

                    HStack {
                        if let script = viewModel.selectedScript {
                            Label(script.lastPathComponent, systemImage: "doc.text")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No script selected")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose File...") {
                            viewModel.pickScriptFile()
                        }
                    }
                }

                Section("Text Filters") {
                    Toggle(isOn: $viewModel.filterStageDirections) {
                        VStack(alignment: .leading) {
                            Text("[Stage directions]")
                            Text("Skip lines wrapped in [square brackets]")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $viewModel.filterSlideNumbers) {
                        VStack(alignment: .leading) {
                            Text("(Slide numbers)")
                            Text("Strip slide references like (1), (2) or 1:, 2: from text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Custom patterns (comma or newline separated)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $viewModel.customFilterPatternsText)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 60)
                    }
                }
            }
            .formStyle(.grouped)

            Spacer()

            // Status / Progress area
            VStack(spacing: 12) {
                switch viewModel.alignmentService.state {
                case .idle:
                    EmptyView()
                case .running(let currentStep):
                    if let section = viewModel.alignmentService.matchedSection {
                        Label("Matched section: \(section)", systemImage: "doc.text.magnifyingglass")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    alignmentChecklist(currentStep: currentStep)
                case .complete(let srtURL):
                    alignmentChecklist(currentStep: nil)
                    Label("Complete: \(srtURL.lastPathComponent)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }

                Button(action: {
                    Task {
                        await viewModel.runAlignment()
                        if case .complete(let srtURL) = viewModel.alignmentService.state,
                           let video = viewModel.selectedVideo {
                            onComplete(video, srtURL)
                        }
                    }
                }) {
                    Label("Run Alignment", systemImage: "waveform.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canRun)
            }
            .padding()
        }
        .alert("Alignment Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Alignment Checklist

    /// Shows all alignment steps as a checklist. Steps before `currentStep` are done,
    /// `currentStep` is in-progress (spinner), and steps after are pending.
    /// If `currentStep` is nil, all steps are shown as done (completion state).
    private func alignmentChecklist(currentStep: AlignmentStep?) -> some View {
        let allSteps = AlignmentStep.allCases

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(allSteps, id: \.self) { step in
                let status = stepStatus(step: step, currentStep: currentStep)
                HStack(spacing: 8) {
                    switch status {
                    case .done:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    case .inProgress:
                        ProgressView()
                            .controlSize(.small)
                    case .pending:
                        Image(systemName: "circle")
                            .foregroundColor(.gray)
                    }
                    Text(step.rawValue)
                        .font(.callout)
                        .foregroundStyle(status == .pending ? .secondary : .primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private enum StepStatus {
        case done, inProgress, pending
    }

    private func stepStatus(step: AlignmentStep, currentStep: AlignmentStep?) -> StepStatus {
        guard let current = currentStep else { return .done } // all done
        let allSteps = AlignmentStep.allCases
        guard let stepIndex = allSteps.firstIndex(of: step),
              let currentIndex = allSteps.firstIndex(of: current) else { return .pending }
        if stepIndex < currentIndex { return .done }
        if stepIndex == currentIndex { return .inProgress }
        return .pending
    }
}
