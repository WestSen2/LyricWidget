//
//  LyricWidgetLiveActivity.swift
//  LyricsWidget
//
//  Live-Activity + Dynamic Island UI  (Genius lyrics version)
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live-Activity Widget
struct LyricWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricWidgetAttributes.self) { context in
            //  Lock-screen / banner UI
            VStack(spacing: 8) {
                Text(context.attributes.songTitle)
                    .font(.headline).bold()
                Text(context.attributes.artistName)
                    .font(.subheadline).foregroundColor(.secondary)
                Text(context.state.currentLyric)
                    .font(.body).multilineTextAlignment(.center)
                Text(context.state.elapsedTime)
                    .font(.caption).foregroundColor(.gray)
            }
            .padding()
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.songTitle).font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.artistName).font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.currentLyric)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            } compactLeading: {
                Text("🎵")
            } compactTrailing: {
                Text(context.state.elapsedTime)
            } minimal: {
                Text("🎶")
            }
            .widgetURL(URL(string: "lyricswidget://"))
            .keylineTint(Color.red)
        }
    }
}

// MARK: - Lyrics updater (Genius)
extension LyricWidgetLiveActivity {
    static func updateActivity(_ activity: Activity<LyricWidgetAttributes>, geniusToken: String) async {
        guard let spotifyToken = SharedSpotifyToken.get() else { return }

        do {
            // 1. Currently-playing from Spotify
            let spotifyURL = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!
            var spotifyReq = URLRequest(url: spotifyURL)
            spotifyReq.setValue("Bearer \(spotifyToken)", forHTTPHeaderField: "Authorization")
            let (spotifyData, _) = try await URLSession.shared.data(for: spotifyReq)
            guard let track = try? JSONDecoder().decode(SpotifyTrack.self, from: spotifyData) else { return }

            // 2. Plain-text lyrics from Genius
            let lyrics = try await GeniusLyrics.fetch(for: track.name,
                                                      artist: track.artists.first?.name ?? "")
            let lines = lyrics.components(separatedBy: .newlines).filter { !$0.isEmpty }

            // 3. Push line-by-line to Live Activity
            for (index, line) in lines.enumerated() {
                let state = LyricWidgetAttributes.ContentState(
                    currentLyric: line,
                    elapsedTime: "0:\(5 * index + 5)"
                )
                let content = ActivityContent(state: state, staleDate: nil)
                await activity.update(content)
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            }

        } catch {
            print("Live-Activity update failed: \(error)")
        }
    }
}

// MARK: - Sample data for Xcode previews
extension LyricWidgetAttributes {
    static var preview: LyricWidgetAttributes {
        LyricWidgetAttributes(songTitle: "Imagine", artistName: "John Lennon")
    }
}

extension LyricWidgetAttributes.ContentState {
    static var sample: LyricWidgetAttributes.ContentState {
        LyricWidgetAttributes.ContentState(currentLyric: "Imagine all the people...", elapsedTime: "0:05")
    }
}
