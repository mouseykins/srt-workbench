import SwiftUI

// Shared visual language for SRT Workbench: cards on a recessed canvas,
// capsule chips, a gradient hero button, and a horizontal step indicator.

// MARK: - Canvas + cards

extension View {
    /// The recessed window canvas that cards sit on.
    func canvasBackground() -> some View {
        background(Color(nsColor: .underPageBackgroundColor))
    }

    /// Elevated card surface.
    func card(cornerRadius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

/// Small-caps section header used above card content.
struct CardHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .kerning(0.6)
            Spacer()
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Chips

/// Compact capsule status chip.
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(tint)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

// MARK: - Hero button

/// Large gradient call-to-action used for Run Alignment.
struct HeroButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isEnabled
                                ? [Color.accentColor, Color.accentColor.opacity(0.72)]
                                : [Color.gray.opacity(0.45), Color.gray.opacity(0.35)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(isEnabled ? 0.18 : 0.05), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Step indicator

/// Horizontal pipeline steps with connectors: done ✓, current spinner, pending dot.
/// `currentStep == nil` renders every step as done.
struct StepIndicator: View {
    let steps: [AlignmentStep]
    let currentStep: AlignmentStep?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                stepView(step)
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(connectorDone(after: index) ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.25))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 16)
                }
            }
        }
    }

    private func stepView(_ step: AlignmentStep) -> some View {
        VStack(spacing: 5) {
            ZStack {
                switch status(of: step) {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                case .current:
                    ProgressView()
                        .controlSize(.small)
                case .pending:
                    Image(systemName: "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(width: 22, height: 22)

            Text(step.rawValue)
                .font(.caption2)
                .foregroundStyle(status(of: step) == .pending ? .tertiary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 86)
    }

    private enum Status { case done, current, pending }

    private func status(of step: AlignmentStep) -> Status {
        guard let current = currentStep else { return .done }
        guard let stepIndex = steps.firstIndex(of: step),
              let currentIndex = steps.firstIndex(of: current) else { return .pending }
        if stepIndex < currentIndex { return .done }
        if stepIndex == currentIndex { return .current }
        return .pending
    }

    private func connectorDone(after index: Int) -> Bool {
        guard let current = currentStep, let currentIndex = steps.firstIndex(of: current) else {
            return currentStep == nil
        }
        return index < currentIndex
    }
}
