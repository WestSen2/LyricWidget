//
//  LyricWidget.swift
//  LyricWidget
//
//  Created by Aiden Liu on 11/13/25.
//

import WidgetKit
import SwiftUI
import Foundation

// MARK: - Shared Types (needed by widget extension)
struct SpotifyTrack: Codable {
    let name: String
    let artists: [Artist]
    let album: Album?
    
    struct Artist: Codable { let name: String }
    
    struct Album: Codable {
        let images: [Image]
        struct Image: Codable { let url: String }
    }
}

struct SharedSpotifyToken {
    private static let suiteName = "group.com.WestL.LyricsWidget"
    private static let tokenKey  = "SpotifyAccessToken"
    
    static func get() -> String? {
        UserDefaults(suiteName: suiteName)?.string(forKey: tokenKey)
    }
}

enum GeniusError: Error { case noPath, noLyrics }

struct GeniusLyrics {
    private static let token = "tsfrKGlg9pjvk0d3HlHms-Br6x9E7Pg3dooOBDDAJ5seZFxyKj7rtQNoPw8uAxBT"
    
    static func fetch(for track: String, artist: String) async throws -> String {
        let searchURLString = "https://api.genius.com/search?q=\(track.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")%20\(artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        guard let url = URL(string: searchURLString) else { throw GeniusError.noPath }
        
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let response = json["response"] as? [String: Any],
            let hits = response["hits"] as? [[String: Any]],
            let first = hits.first,
            let result = first["result"] as? [String: Any],
            let path = result["path"] as? String
        else { throw GeniusError.noPath }
        
        let pageURL = URL(string: "https://genius.com\(path)")!
        let (html, _) = try await URLSession.shared.data(from: pageURL)
        guard let htmlString = String(data: html, encoding: .utf8),
              let lyrics = parseLyricsDiv(htmlString)
        else { throw GeniusError.noLyrics }
        
        return lyrics
    }
    
    private static func parseLyricsDiv(_ html: String) -> String? {
        let pattern = #"<div[^>]*data-lyrics-container[^>]*>(.*?)</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        else { return nil }
        
        let substring = (html as NSString).substring(with: match.range(at: 1))
        return substring.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
                   .replacingOccurrences(of: "&quot;", with: "\"")
                   .replacingOccurrences(of: "&#x27;", with: "'")
                   .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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
        let lyricLines = lyrics?.components(separatedBy: .newlines).filter { !$0.isEmpty } ?? []
        
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
