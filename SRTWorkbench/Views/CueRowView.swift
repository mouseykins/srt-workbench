import SwiftUI

/// One editable cue, rendered as a card. The active cue gets an accent
/// leading bar and border; per-line character counts render as capsules.
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
        HStack(spacing: 0) {
            // Active-cue accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 8) {
                // Header: index, jump, duration
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isActive ? Color.white : Color.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
                        )

                    Button(action: onJump) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.borderless)
                    .help("Jump the video to this cue")

                    Spacer()

                    Chip(text: String(format: "%.1fs", cue.endTime - cue.startTime), tint: .secondary)
                        .help("On-screen duration")
                }

                // Timecode fields
                HStack(spacing: 6) {
                    TimecodeField(label: "Start", text: $startText, isValid: TimecodeFormatter.isValid(startText))
                        .onChange(of: startText) { _, newValue in
                            onStartChanged(newValue)
                        }

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    TimecodeField(label: "End", text: $endText, isValid: TimecodeFormatter.isValid(endText))
                        .onChange(of: endText) { _, newValue in
                            onEndChanged(newValue)
                        }

                    Spacer()
                }

                // Subtitle text
                TextEditor(text: $bodyText)
                    .font(isActive ? .title3 : .body)
                    .frame(minHeight: isActive ? 54 : 38, maxHeight: isActive ? 110 : 76)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                    .onChange(of: bodyText) { _, newValue in
                        onTextChanged(newValue)
                    }

                // Per-line character counts (ADA/DCMP: ≤32 chars, ≤2 lines)
                let textLines = bodyText.components(separatedBy: "\n")
                HStack(spacing: 6) {
                    ForEach(Array(textLines.enumerated()), id: \.offset) { idx, line in
                        Chip(
                            text: "L\(idx + 1) · \(line.count)",
                            tint: line.count > CaptionCompliance.maxCharsPerLine ? .red : .green
                        )
                    }
                    if textLines.count > CaptionCompliance.maxLinesPerCue {
                        Chip(text: "\(textLines.count) lines", systemImage: "exclamationmark.triangle.fill", tint: .red)
                    }
                    Spacer()
                }
            }
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isActive ? AnyShapeStyle(Color.accentColor.opacity(0.6)) : AnyShapeStyle(.quaternary),
                    lineWidth: 1
                )
        )
        .onAppear {
            startText = cue.startTimecode
            endText = cue.endTimecode
            bodyText = cue.text
        }
        // Keep the editable fields in sync when the cue changes underneath us
        // (e.g. Reflow rewrites text while this row is on screen). Guarded so
        // the user's in-progress typing is never clobbered by its own echo.
        .onChange(of: cue) { _, newCue in
            if newCue.text != bodyText {
                bodyText = newCue.text
            }
            if TimecodeFormatter.seconds(from: startText) != newCue.startTime {
                startText = newCue.startTimecode
            }
            if TimecodeFormatter.seconds(from: endText) != newCue.endTime {
                endText = newCue.endTimecode
            }
        }
    }
}

struct TimecodeField: View {
    let label: String
    @Binding var text: String
    let isValid: Bool

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.plain)
            .font(.callout.monospaced())
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isValid ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.red), lineWidth: 1)
            )
            .foregroundColor(isValid ? .primary : .red)
            .frame(width: 132)
    }
}
