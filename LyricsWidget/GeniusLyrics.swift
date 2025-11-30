//
//  GeniusLyrics.swift
//  LyricsWidget
//
//  Created by Aiden Liu on 11/14/25.
//
import Foundation

enum GeniusError: Error { case noPath, noLyrics }

struct GeniusLyrics {
    private static let token = "YOUR_GENIUS_TOKEN"   // <-- paste here

    /// - Returns: plain-text lyrics or nil
    static func fetch(for track: String, artist: String) async throws -> String {
        // 1. Search for the song
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

        // 2. Scrape the lyrics page (Genius does not expose timed lyrics via API)
        let pageURL = URL(string: "https://genius.com\(path)")!
        let (html, _) = try await URLSession.shared.data(from: pageURL)
        guard let htmlString = String(data: html, encoding: .utf8),
              let lyrics = parseLyricsDiv(htmlString)
        else { throw GeniusError.noLyrics }

        return lyrics
    }

    // Very small helper – Genius puts lyrics in <div data-lyrics-container>
    private static func parseLyricsDiv(_ html: String) -> String? {
        let pattern = #"<div[^>]*data-lyrics-container[^>]*>(.*?)</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        else { return nil }

        let substring = (html as NSString).substring(with: match.range(at: 1))
        // Strip remaining tags & html entities
        return substring.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
                   .replacingOccurrences(of: "&quot;", with: "\"")
                   .replacingOccurrences(of: "&#x27;", with: "'")
                   .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
