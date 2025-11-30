//
//  LyricWidget.swift
//  LyricWidget
//
//  Created by Aiden Liu on 11/13/25.
//

import WidgetKit
import SwiftUI
import Foundation

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            configuration: ConfigurationAppIntent(),
            songTitle: "Billie Jean",
            artistName: "Michael Jackson",
            currentLyric: "She was more like a beauty queen from a movie scene",
            allLyrics: [],
            playbackPositionMs: nil,
            trackDurationMs: nil
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        // For snapshot, try to get current data quickly
        let entry = await fetchCurrentEntry()
        return entry
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let currentEntry = await fetchCurrentEntry()
        
        // Create timeline entries that update every 5 seconds to sync with playback
        var entries: [SimpleEntry] = []
        let now = Date()
        
        // Create entries for the next 2 minutes, updating every 5 seconds
        // Each entry will calculate the correct lyric based on playback position
        for i in 0..<24 { // 24 entries = 2 minutes at 5-second intervals
            let entryDate = now.addingTimeInterval(TimeInterval(i * 5))
            let estimatedProgressMs = (currentEntry.playbackPositionMs ?? 0) + (i * 5000) // Add 5 seconds per entry
            
            // Calculate which lyric line to show based on playback position
            let lyricIndex = calculateLyricIndex(
                progressMs: estimatedProgressMs,
                durationMs: currentEntry.trackDurationMs,
                totalLyrics: currentEntry.allLyrics.count
            )
            
            let entry = SimpleEntry(
                date: entryDate,
                configuration: configuration,
                songTitle: currentEntry.songTitle,
                artistName: currentEntry.artistName,
                currentLyric: getLyricForIndex(lyricIndex, lyrics: currentEntry.allLyrics),
                allLyrics: currentEntry.allLyrics,
                playbackPositionMs: estimatedProgressMs,
                trackDurationMs: currentEntry.trackDurationMs
            )
            entries.append(entry)
        }
        
        // Refresh every 10 seconds to keep synced with playback
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 10, to: now) ?? now
        return Timeline(entries: entries, policy: .after(nextUpdate))
    }
    
    // Calculate which lyric line should be shown based on playback position
    private func calculateLyricIndex(progressMs: Int, durationMs: Int?, totalLyrics: Int) -> Int {
        guard totalLyrics > 0 else { return 0 }
        guard let duration = durationMs, duration > 0 else {
            // If no duration, estimate 4 seconds per lyric line
            return min(progressMs / 4000, totalLyrics - 1)
        }
        
        // Calculate progress as a percentage
        let progressPercent = Double(progressMs) / Double(duration)
        
        // Map to lyric index (assuming lyrics are evenly distributed throughout the song)
        let lyricIndex = Int(progressPercent * Double(totalLyrics))
        
        return min(max(lyricIndex, 0), totalLyrics - 1)
    }
    
    // Get the lyric line for a given index, with bounds checking
    private func getLyricForIndex(_ index: Int, lyrics: [String]) -> String {
        guard !lyrics.isEmpty else { return "No lyrics available" }
        guard index >= 0 && index < lyrics.count else {
            return lyrics.last ?? "No lyrics available"
        }
        return lyrics[index]
    }
    
    private func fetchCurrentEntry() async -> SimpleEntry {
        guard let spotifyToken = SharedSpotifyToken.get() else {
            return SimpleEntry(
                date: Date(),
                configuration: ConfigurationAppIntent(),
                songTitle: "Not Playing",
                artistName: "Login to Spotify",
                currentLyric: "No song currently playing",
                allLyrics: [],
                playbackPositionMs: nil,
                trackDurationMs: nil
            )
        }
        
        // Fetch current playback info from Spotify (includes track and progress)
        guard let playbackInfo = await fetchSpotifyPlaybackInfo(token: spotifyToken),
              let track = playbackInfo.item else {
            return SimpleEntry(
                date: Date(),
                configuration: ConfigurationAppIntent(),
                songTitle: "Not Playing",
                artistName: "No track found",
                currentLyric: "Make sure music is playing on Spotify",
                allLyrics: [],
                playbackPositionMs: nil,
                trackDurationMs: nil
            )
        }
        
        // Fetch lyrics from Genius
        let lyrics = try? await GeniusLyrics.fetch(for: track.name, artist: track.artists.first?.name ?? "")
        let lyricLines = lyrics?.components(separatedBy: CharacterSet.newlines).filter { !$0.isEmpty } ?? []
        
        // Calculate which lyric line to show based on current playback position
        let lyricIndex = calculateLyricIndex(
            progressMs: playbackInfo.progressMs,
            durationMs: track.durationMs,
            totalLyrics: lyricLines.count
        )
        let currentLyric = getLyricForIndex(lyricIndex, lyrics: lyricLines)
        
        return SimpleEntry(
            date: Date(),
            configuration: ConfigurationAppIntent(),
            songTitle: track.name,
            artistName: track.artists.first?.name ?? "Unknown Artist",
            currentLyric: currentLyric,
            allLyrics: lyricLines,
            playbackPositionMs: playbackInfo.progressMs,
            trackDurationMs: track.durationMs
        )
    }
    
    private func fetchSpotifyPlaybackInfo(token: String) async -> SpotifyPlaybackInfo? {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            
            // Decode the full playback info (includes progress_ms and item)
            return try JSONDecoder().decode(SpotifyPlaybackInfo.self, from: data)
        } catch {
            print("Widget: Failed to fetch Spotify playback info: \(error)")
            return nil
        }
    }
    
    // Calculate which lyric line should be shown based on playback position
    private func calculateLyricIndex(progressMs: Int, durationMs: Int?, totalLyrics: Int) -> Int {
        guard totalLyrics > 0 else { return 0 }
        guard let duration = durationMs, duration > 0 else {
            // If no duration, estimate 4 seconds per lyric line
            return min(progressMs / 4000, totalLyrics - 1)
        }
        
        // Calculate progress as a percentage
        let progressPercent = Double(progressMs) / Double(duration)
        
        // Map to lyric index (assuming lyrics are evenly distributed throughout the song)
        let lyricIndex = Int(progressPercent * Double(totalLyrics))
        
        return min(max(lyricIndex, 0), totalLyrics - 1)
    }
    
    // Get the lyric line for a given index, with bounds checking
    private func getLyricForIndex(_ index: Int, lyrics: [String]) -> String {
        guard !lyrics.isEmpty else { return "No lyrics available" }
        guard index >= 0 && index < lyrics.count else {
            return lyrics.last ?? "No lyrics available"
        }
        return lyrics[index]
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let songTitle: String
    let artistName: String
    let currentLyric: String
    let allLyrics: [String]
    let playbackPositionMs: Int? // Current playback position in milliseconds
    let trackDurationMs: Int? // Total track duration
}

struct LyricWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Song info
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.songTitle)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)
                
                Text(entry.artistName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Divider()
            
            // Current lyric
            Text(entry.currentLyric)
                .font(.body)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LyricWidget: Widget {
    let kind: String = "LyricWidgetWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            LyricWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

#Preview(as: .systemSmall) {
    LyricWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        configuration: ConfigurationAppIntent(),
        songTitle: "Billie Jean",
        artistName: "Michael Jackson",
        currentLyric: "She was more like a beauty queen from a movie scene",
        allLyrics: ["She was more like a beauty queen from a movie scene", "I said don't mind, but what do you mean I am the one"],
        playbackPositionMs: 30000,
        trackDurationMs: 294000
    )
}
