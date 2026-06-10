import SwiftUI

struct FirstRunView: View {
    @State private var setupManager = SetupManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)

            VStack(spacing: 4) {
                Text("SRT Workbench")
                    .font(.largeTitle.weight(.semibold))
                Text("Perfectly timed captions from your scripts")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 18) {
                statusContent

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    checklistRow("Python environment", isDone: PythonEnvironmentManager.shared.isSetupComplete)
                    checklistRow("Speech alignment model", isDone: PythonEnvironmentManager.shared.isModelDownloaded)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .frame(maxWidth: 440)
            .card()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .canvasBackground()
        .task {
            await setupManager.runSetup()
        }
    }

    // MARK: - Stage content

    @ViewBuilder
    private var statusContent: some View {
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
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

        case .downloadingModel(let progress):
            VStack(spacing: 8) {
                statusRow("Downloading speech model...", icon: "arrow.down.doc", spinning: false)
                ProgressView(value: progress)
                    .tint(Color.accentColor)
                Text("\(Int(progress * 100))% of ~1.2 GB")
                    .font(.caption)
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
                    .textSelection(.enabled)

                Button("Retry") {
                    Task { await setupManager.runSetup() }
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 12) {
                    Button("Copy Diagnostics") {
                        Task { await DiagnosticsService.copyReportToClipboard() }
                    }
                    Button("Open Log Folder") {
                        DiagnosticsService.openLogFolder()
                    }
                }
                .controlSize(.small)
            }
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
        HStack(spacing: 7) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? Color.green : Color.secondary)
                .font(.callout)
            Text(label)
                .font(.callout)
                .foregroundStyle(isDone ? .primary : .secondary)
        }
    }
}
