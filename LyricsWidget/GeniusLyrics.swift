//
//  GeniusLyrics.swift
//  LyricsWidget
//
//  Created by Aiden Liu on 11/14/25.
//
import Foundation

enum GeniusError: Error { case noPath, noLyrics }

struct GeniusLyrics {
    private static let token = "tsfrKGlg9pjvk0d3HlHms-Br6x9E7Pg3dooOBDDAJ5seZFxyKj7rtQNoPw8uAxBT"

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

    // Parse lyrics from Genius HTML - they're in <div data-lyrics-container>
    private static func parseLyricsDiv(_ html: String) -> String? {
        // Find the main lyrics container - match until the closing tag (greedy to get full content)
        let containerPattern = #"<div[^>]*data-lyrics-container[^>]*>(.*)</div>"#
        guard let containerRegex = try? NSRegularExpression(pattern: containerPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let containerMatch = containerRegex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        else { return nil }
        
        var containerContent = (html as NSString).substring(with: containerMatch.range(at: 1))
        
        // Remove script, style, and other non-content tags
        containerContent = containerContent.replacingOccurrences(of: #"<script[^>]*>.*?</script>"#, with: "", options: [.regularExpression, .caseInsensitive, .dotMatchesLineSeparators])
        containerContent = containerContent.replacingOccurrences(of: #"<style[^>]*>.*?</style>"#, with: "", options: [.regularExpression, .caseInsensitive, .dotMatchesLineSeparators])
        containerContent = containerContent.replacingOccurrences(of: #"<a[^>]*>.*?</a>"#, with: "", options: [.regularExpression, .caseInsensitive, .dotMatchesLineSeparators])
        
        // Extract text from divs that likely contain lyrics (not metadata)
        // Look for divs that don't have class attributes with "Contributor" or "Translation"
        var lyricLines: [String] = []
        
        // Split by <br> tags and div boundaries to get individual lines
        // First replace <br> and </div> with newlines, then split
        var textForSplitting = containerContent
        textForSplitting = textForSplitting.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        textForSplitting = textForSplitting.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        let parts = textForSplitting.components(separatedBy: "\n")
        
        for part in parts {
            let text = cleanHtmlText(part)
            // Strong filtering: must be substantial text, not metadata
            let isJustNumbers = text.range(of: #"^\d+\s*$"#, options: .regularExpression) != nil
            let hasMetadataKeywords = text.lowercased().contains("contributor") || 
                                     text.lowercased().contains("translation") ||
                                     text.lowercased().contains("embed") ||
                                     text.lowercased().contains("genius") ||
                                     text.lowercased().contains("about genius")
            
            if text.count > 5 && // Longer minimum to filter out short metadata
               !text.allSatisfy({ $0.isNumber || $0.isWhitespace || $0.isPunctuation }) &&
               !isJustNumbers &&
               !hasMetadataKeywords {
                lyricLines.append(text)
            }
        }
        
        // If we got too few lines, try a different approach - extract all text and split intelligently
        if lyricLines.count < 5 {
            // Remove all HTML tags and get pure text
            var allText = containerContent
            allText = allText.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
            allText = cleanHtmlText(allText)
            
            // Split by double newlines (verses) or single newlines (lines)
            let lines = allText.components(separatedBy: "\n\n")
                .flatMap { $0.components(separatedBy: "\n") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { line in
                    line.count > 5 &&
                    !line.lowercased().contains("contributor") &&
                    !line.lowercased().contains("translation") &&
                    !line.lowercased().contains("embed") &&
                    !line.lowercased().contains("genius")
                }
            
            if lines.count > lyricLines.count {
                lyricLines = lines
            }
        }
        
        // Join lines with newlines
        let result = lyricLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
    
    // Helper to clean HTML and extract text
    private static func cleanHtmlText(_ html: String) -> String {
        var text = html
        // Remove all HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode HTML entities
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#x27;", with: "'")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        // Clean up whitespace
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
