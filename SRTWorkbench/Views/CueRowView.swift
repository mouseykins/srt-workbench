import SwiftUI

struct CueRowView: View {
    let index: Int
    let cue: SRTCue
    let isActive: Bool
    let onJump: () -> Void
    let onStartChanged: (String) -> Void
    let onEndChanged: (String) -> Void
    let onTextChanged: (String) -> Void

    @State private var startText: String = ""
    @State private var endText: String = ""
    @State private var bodyText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row: index badge + jump button
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isActive ? .white : .secondary)
                    .frame(width: 32, height: 24)
                    .background(isActive ? Color.accentColor : Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Button("Jump", action: onJump)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Spacer()

                let duration = cue.endTime - cue.startTime
                let durationOutOfRange = duration < CaptionCompliance.minDuration
                    || duration > CaptionCompliance.maxDuration
                HStack(spacing: 4) {
                    if durationOutOfRange {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(formatDuration(duration))
                        .font(.callout)
                        .foregroundStyle(durationOutOfRange ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                }
                .help(durationOutOfRange
                      ? String(format: "On-screen duration should be %.1f–%.1fs",
                               CaptionCompliance.minDuration, CaptionCompliance.maxDuration)
                      : "")
            }

            // Timecode fields
            HStack(spacing: 8) {
                TimecodeField(label: "Start", text: $startText, isValid: TimecodeFormatter.isValid(startText))
                    .onChange(of: startText) { _, newValue in
                        onStartChanged(newValue)
                    }

                Text("-->")
                    .font(.callout.monospaced())
                    .foregroundStyle(.tertiary)

                TimecodeField(label: "End", text: $endText, isValid: TimecodeFormatter.isValid(endText))
                    .onChange(of: endText) { _, newValue in
                        onEndChanged(newValue)
                    }
            }

            // Subtitle text
            TextEditor(text: $bodyText)
                .font(isActive ? .title3 : .body)
                .frame(minHeight: isActive ? 60 : 40, maxHeight: isActive ? 120 : 80)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.2),
                                lineWidth: isActive ? 2 : 1)
                )
                .onChange(of: bodyText) { _, newValue in
                    onTextChanged(newValue)
                }

            // Per-line character counts (ADA/DCMP: ≤32 chars, ≤2 lines)
            let textLines = bodyText.components(separatedBy: "\n")
            HStack(spacing: 8) {
                ForEach(Array(textLines.enumerated()), id: \.offset) { idx, line in
                    Text("L\(idx + 1) \(line.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(line.count > CaptionCompliance.maxCharsPerLine ? .red : .green)
                }
                if textLines.count > CaptionCompliance.maxLinesPerCue {
                    Text("· \(textLines.count) lines")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
                Spacer()
            }
        }
        .padding(.vertical, isActive ? 8 : 4)
        .padding(.horizontal, isActive ? 4 : 0)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .onAppear {
            startText = cue.startTimecode
            endText = cue.endTimecode
            bodyText = cue.text
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        String(format: "%.1fs", seconds)
    }
}

struct TimecodeField: View {
    let label: String
    @Binding var text: String
    let isValid: Bool

    var body: some View {
        TextField(label, text: $text)
            .font(.body.monospaced())
            .textFieldStyle(.roundedBorder)
            .frame(width: 145)
            .foregroundColor(isValid ? .primary : .red)
    }
}
