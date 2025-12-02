import SwiftUI

/// A simple in-app replica of the widget view, used only for debugging.
struct InAppWidgetDebugView: View {
    let songTitle: String
    let artistName: String
    let lyrics: [String]
    let currentIndex: Int
    let playbackMs: Int
    let statusText: String

    // Format milliseconds into m:ss
    private func formatTime(_ ms: Int) -> String {
        guard ms >= 0 else { return "--:--" }
        let totalSeconds = ms / 1_000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // Returns up to 5 visible lines around the current index
    private var visibleLyrics: [(text: String, isCurrent: Bool)] {
        guard !lyrics.isEmpty else {
            return [(statusText.isEmpty ? "No lyrics loaded" : statusText, true)]
        }

        let safeIndex = min(max(currentIndex, 0), lyrics.count - 1)
        let startIndex = max(0, safeIndex - 2)
        let endIndex = min(lyrics.count, safeIndex + 3)

        var result: [(String, Bool)] = []
        for i in startIndex..<endIndex {
            result.append((lyrics[i], i == safeIndex))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Song info + time
            VStack(alignment: .leading, spacing: 2) {
                Text(songTitle)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)

                Text(artistName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("Debug widget")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatTime(playbackMs))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            Divider()
                .padding(.vertical, 2)

            // Scrolling lyrics-like view
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(visibleLyrics.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(line.isCurrent ? .body.bold() : .subheadline)
                        .foregroundColor(line.isCurrent ? .primary : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}


