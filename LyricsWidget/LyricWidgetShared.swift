//
//  LyricWidgetShared.swift
//  LyricsWidget
//

import Foundation
import ActivityKit

struct LyricWidgetHelper {
    static func updateActivity(_ activity: Activity<LyricWidgetAttributes>, geniusToken: String) async {
        guard let token = SharedSpotifyToken.get() else { return }

        let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!   // space removed
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let playbackInfo = try? JSONDecoder().decode(SpotifyPlaybackInfo.self, from: data),
                  let track = playbackInfo.item else { return }

            // Genius lyrics
            let lyrics = try await GeniusLyrics.fetch(for: track.name,
                                                      artist: track.artists.first?.name ?? "")
            let lyricLines = lyrics.components(separatedBy: .newlines).filter { !$0.isEmpty }

            for (index, line) in lyricLines.enumerated() {
                let newState = LyricWidgetAttributes.ContentState(
                    currentLyric: line,
                    elapsedTime: "0:\(5 * index + 5)"
                )
                let content = ActivityContent(state: newState, staleDate: nil)
                await activity.update(content)
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            }

        } catch {
            print("Error updating activity: \(error)")
        }
    }
}

// MARK: - Live Activity Attributes
struct LyricWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentLyric: String
        var elapsedTime: String
    }
    
    var songTitle: String
    var artistName: String
}

// MARK: - Spotify Track Model
struct SpotifyTrack: Codable {
    let name: String
    let artists: [Artist]
    let album: Album?
    let durationMs: Int?

    struct Artist: Codable { let name: String }

    struct Album: Codable {
        let images: [Image]
        struct Image: Codable { let url: String }
    }
    
    enum CodingKeys: String, CodingKey {
        case name, artists, album
        case durationMs = "duration_ms"
    }
}

// MARK: - Spotify Playback Info
struct SpotifyPlaybackInfo: Codable {
    let progressMs: Int
    let isPlaying: Bool
    let item: SpotifyTrack?
    
    enum CodingKeys: String, CodingKey {
        case progressMs = "progress_ms"
        case isPlaying = "is_playing"
        case item
    }
}

// MARK: - App Group Token Helper
struct SharedSpotifyToken {
    private static let suiteName = "group.com.WestL.LyricsWidget"
    private static let tokenKey  = "SpotifyAccessToken"
    
    static func save(_ token: String) {
        UserDefaults(suiteName: suiteName)?.set(token, forKey: tokenKey)
    }
    
    static func get() -> String? {
        UserDefaults(suiteName: suiteName)?.string(forKey: tokenKey)
    }
    
    static func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: tokenKey)
    }
}
