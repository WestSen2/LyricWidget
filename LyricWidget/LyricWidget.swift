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
            allLyrics: []
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        // For snapshot, try to get current data quickly
        let entry = await fetchCurrentEntry()
        return entry
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let currentEntry = await fetchCurrentEntry()
        
        // Create entries for the next few minutes, updating lyrics every 5 seconds
        var entries: [SimpleEntry] = [currentEntry]
        
        // If we have lyrics, create timeline entries for the next 2 minutes
        if !currentEntry.allLyrics.isEmpty {
            let startDate = Date()
            for (index, lyric) in currentEntry.allLyrics.enumerated() {
                if index >= 24 { break } // Limit to 24 entries (2 minutes at 5 sec intervals)
                let entryDate = startDate.addingTimeInterval(TimeInterval(index * 5))
                let entry = SimpleEntry(
                    date: entryDate,
                    configuration: configuration,
                    songTitle: currentEntry.songTitle,
                    artistName: currentEntry.artistName,
                    currentLyric: lyric,
                    allLyrics: currentEntry.allLyrics
                )
                entries.append(entry)
            }
        }
        
        // Refresh every 30 seconds to check for new songs
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 30, to: Date()) ?? Date()
        return Timeline(entries: entries, policy: .after(nextUpdate))
    }
    
    private func fetchCurrentEntry() async -> SimpleEntry {
        guard let spotifyToken = SharedSpotifyToken.get() else {
            return SimpleEntry(
                date: Date(),
                configuration: ConfigurationAppIntent(),
                songTitle: "Not Playing",
                artistName: "Login to Spotify",
                currentLyric: "No song currently playing",
                allLyrics: []
            )
        }
        
        // Fetch current track from Spotify
        guard let track = await fetchSpotifyTrack(token: spotifyToken) else {
            return SimpleEntry(
                date: Date(),
                configuration: ConfigurationAppIntent(),
                songTitle: "Not Playing",
                artistName: "No track found",
                currentLyric: "Make sure music is playing on Spotify",
                allLyrics: []
            )
        }
        
        // Fetch lyrics from Genius
        let lyrics = try? await GeniusLyrics.fetch(for: track.name, artist: track.artists.first?.name ?? "")
        let lyricLines = lyrics?.components(separatedBy: CharacterSet.newlines).filter { !$0.isEmpty } ?? []
        
        return SimpleEntry(
            date: Date(),
            configuration: ConfigurationAppIntent(),
            songTitle: track.name,
            artistName: track.artists.first?.name ?? "Unknown Artist",
            currentLyric: lyricLines.first ?? "Loading lyrics...",
            allLyrics: lyricLines
        )
    }
    
    private func fetchSpotifyTrack(token: String) async -> SpotifyTrack? {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            
            // Parse the nested JSON structure
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let item = json["item"] as? [String: Any] else { return nil }
            
            // Convert to SpotifyTrack format
            let itemData = try JSONSerialization.data(withJSONObject: item)
            return try JSONDecoder().decode(SpotifyTrack.self, from: itemData)
        } catch {
            print("Widget: Failed to fetch Spotify track: \(error)")
            return nil
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let songTitle: String
    let artistName: String
    let currentLyric: String
    let allLyrics: [String]
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
        allLyrics: ["She was more like a beauty queen from a movie scene", "I said don't mind, but what do you mean I am the one"]
    )
}
