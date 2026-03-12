import SwiftUI

struct FirstRunView: View {
    @State private var setupManager = SetupManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("SRT Workbench")
                .font(.largeTitle.weight(.medium))

            VStack(spacing: 16) {
                switch setupManager.stage {
                case .checking:
                    statusRow("Checking environment...", icon: "magnifyingglass", spinning: true)

                case .findingPython:
                    statusRow("Finding Python...", icon: "terminal", spinning: true)

                case .creatingVenv(let detail):
                    statusRow(detail, icon: "shippingbox", spinning: true)

                case .installingDependencies(let detail):
                    VStack(spacing: 8) {
                        statusRow(detail, icon: "arrow.down.circle", spinning: true)
                        Text("This is a one-time setup")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }

                case .downloadingModel(let progress):
                    VStack(spacing: 8) {
                        statusRow("Downloading speech model...", icon: "arrow.down.doc", spinning: false)
                        ProgressView(value: progress)
                            .frame(width: 300)
                        Text("\(Int(progress * 100))% of ~1.2 GB")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                case .ready:
                    statusRow("Ready!", icon: "checkmark.circle.fill", spinning: false)
                        .foregroundStyle(.green)

                case .failed(let message):
                    VStack(spacing: 12) {
                        Label("Setup failed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.headline)

                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                            .textSelection(.enabled)

                        Button("Retry") {
                            Task { await setupManager.runSetup() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            // Setup checklist
            VStack(alignment: .leading, spacing: 6) {
                checklistRow("Python environment", isDone: PythonEnvironmentManager.shared.isPythonAvailable)
                checklistRow("Speech alignment model", isDone: PythonEnvironmentManager.shared.isModelDownloaded)
            }
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await setupManager.runSetup()
        }
    }

    private func statusRow(_ text: String, icon: String, spinning: Bool) -> some View {
        HStack(spacing: 8) {
            if spinning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
            }
            Text(text)
                .font(.body)
        }
    }

    private func checklistRow(_ label: String, isDone: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isDone ? .green : .gray)
                .font(.callout)
            Text(label)
                .font(.callout)
                .foregroundStyle(isDone ? .primary : .secondary)
        }
    }
}
