//
//  ContentView.swift
//  LyricsWidget
//
//  Spotify login + Genius lyrics → Live Activity
//


import SwiftUI
import ActivityKit
import AuthenticationServices
import CryptoKit
import Foundation
import WidgetKit

// MARK: - Crypto helpers
extension String {
    func sha256() -> Data { Data(SHA256.hash(data: Data(self.utf8))) }
}
extension Data {
    func base64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Button style
struct LoginButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(10)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
//
// Spotify Playback Info Helper using Spotify Web API
//

/// Error type for Spotify playback operations
enum SpotifyPlaybackError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case noTrackPlaying
    case parseError
    case jsonError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let message):
            return "Network error: \(message)"
        case .noTrackPlaying:
            return "No track found or not playing (are you playing from another device?)"
        case .parseError:
            return "Failed to parse track info."
        case .jsonError(let message):
            return "JSON error: \(message)"
        }
    }
}

/// Spotify API Helper responsible for fetching the currently playing track
class SpotifyPlaybackHelper {
    /// Fetches the currently playing track for the given access token
    /// - Parameters:
    ///   - accessToken: Spotify OAuth access token
    ///   - completion: Closure called with (trackName, artistName) or error
    static func fetchCurrentPlayingTrack(accessToken: String, completion: @escaping (Result<(String, String), SpotifyPlaybackError>) -> Void) {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else {
            completion(.failure(.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }
            guard
                let httpURLResponse = response as? HTTPURLResponse,
                httpURLResponse.statusCode == 200,
                let data = data
            else {
                completion(.failure(.noTrackPlaying))
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let item = json["item"] as? [String: Any],
                   let name = item["name"] as? String,
                   let artists = item["artists"] as? [[String: Any]],
                   let firstArtist = artists.first,
                   let artistName = firstArtist["name"] as? String
                {
                    completion(.success((name, artistName)))
                } else {
                    completion(.failure(.parseError))
                }
            } catch {
                completion(.failure(.jsonError(error.localizedDescription)))
            }
        }
        task.resume()
    }
}
// MARK: - Main view
struct ContentView: View {
    @State private var songTitle      = ""
    @State private var artistName     = ""
    @State private var accessToken    = ""
    @State private var activity: Activity<LyricWidgetAttributes>?
    @State private var activityStarted = false
    @State private var authSession: ASWebAuthenticationSession?   // NEW
    private let contextProvider = ContextProvider()   // NEW – strong ref

    // In-app "widget" debug state
    @State private var showWidgetDebug = false
    @State private var debugLyrics: [String] = []
    @State private var debugCurrentIndex: Int = 0
    @State private var debugPlaybackMs: Int = 0
    @State private var debugDurationMs: Int = 240_000 // default 4 minutes
    @State private var debugTimer: Timer?
    @State private var debugStatus: String = ""

    // Credentials
    private let spotifyClientID = "1dfc9705a8f943e9a6774ea2307c488a"
    private let geniusToken     = "tsfrKGlg9pjvk0d3HlHms-Br6x9E7Pg3dooOBDDAJ5seZFxyKj7rtQNoPw8uAxBT"

    var body: some View {
        VStack(spacing: 20) {
            Text(songTitle.isEmpty ? "No song playing" : songTitle)
                .font(.title.bold())
            Text(artistName)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            Button("Login to Spotify") {
                startSpotifyAuth()
            }
            .buttonStyle(LoginButtonStyle(color: .green))

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("📱 Add Widget to Home Screen")
                    .font(.headline)
                Text("1. Long press on your home screen\n2. Tap the + button\n3. Search for 'Lyrics Widget'\n4. Select a size and add it")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)

            Button(activityStarted ? "Live Activity Started" : "Start Live Activity") {
                startLiveActivity()
            }
            .buttonStyle(LoginButtonStyle(color: activityStarted ? .gray : .blue))
            .disabled(activityStarted)

            // In-app widget debug toggle
            Button(showWidgetDebug ? "Hide In-App Widget Debug" : "Show In-App Widget Debug") {
                if showWidgetDebug {
                    stopWidgetDebug()
                    showWidgetDebug = false
                } else {
                    startWidgetDebug()
                }
            }
            .buttonStyle(LoginButtonStyle(color: .orange))

            if showWidgetDebug {
                InAppWidgetDebugView(
                    songTitle: songTitle.isEmpty ? "No song" : songTitle,
                    artistName: artistName.isEmpty ? "Unknown Artist" : artistName,
                    lyrics: debugLyrics,
                    currentIndex: debugCurrentIndex,
                    playbackMs: debugPlaybackMs,
                    statusText: debugStatus
                )
                .frame(maxHeight: 220)
            }
        }
        .padding()
    }

    // MARK: - Spotify PKCE auth
    // MARK: - Spotify PKCE auth
    private func startSpotifyAuth() {
        print("🔍 Login button tapped – entering startSpotifyAuth()")

        let redirectURI   = "lyricswidget://callback"
        let scopes        = "user-read-currently-playing user-read-playback-state"
        let codeVerifier  = randomString(length: 128)
        let codeChallenge = codeVerifier.sha256().base64URL()

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id",            value: spotifyClientID),
            URLQueryItem(name: "response_type",        value: "code"),
            URLQueryItem(name: "redirect_uri",         value: redirectURI),
            URLQueryItem(name: "scope",                value: scopes),
            URLQueryItem(name: "code_challenge_method",value: "S256"),
            URLQueryItem(name: "code_challenge",       value: codeChallenge)
        ]

        guard let url = components.url else { return }
        print("🔍 Opening Spotify auth URL: \(url)")

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "lyricswidget") { callback, error in
            guard let callback = callback, error == nil,
                  let code = URLComponents(string: callback.absoluteString)?
                    .queryItems?.first(where: { $0.name == "code" })?.value
            else {
                if let error = error { print("❌ Auth error: \(error)") }
                return
            }
            print("✅ Received auth code")
            self.exchangeCodeForToken(code: code, codeVerifier: codeVerifier)
            self.authSession = nil
        }
        session.presentationContextProvider = contextProvider   // use property
        authSession = session
        session.start()
    }

    // MARK: - Exchange code for tokens
    private func exchangeCodeForToken(code: String, codeVerifier: String) {
        let redirectURI = "lyricswidget://callback"
        var request     = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)  // ← space removed
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = """
        grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI)&client_id=\(spotifyClientID)&code_verifier=\(codeVerifier)
        """.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String
            else { return }

            DispatchQueue.main.async {
                self.accessToken = token
                SharedSpotifyToken.save(token)
                print("🎉 Spotify access-token obtained")
                // Reload widget timeline immediately after saving token
                WidgetCenter.shared.reloadTimelines(ofKind: "LyricWidgetWidget")
                self.fetchCurrentlyPlaying()
            }
        }.resume()
    }
   

    // MARK: - Fetch currently-playing
    private func fetchCurrentlyPlaying() {
        print("🔍 Fetching currently-playing track…")
        guard !accessToken.isEmpty else { return }

        SpotifyPlaybackHelper.fetchCurrentPlayingTrack(accessToken: accessToken) { result in
            DispatchQueue.main.async {
                switch result {
                case .success((let trackName, let artistName)):
                    print("🎵 Now playing: \(trackName) – \(artistName)")
                    self.songTitle = trackName
                    self.artistName = artistName
                    SharedSpotifyToken.save(self.accessToken)
                    // Reload widget to show the new track
                    WidgetCenter.shared.reloadTimelines(ofKind: "LyricWidgetWidget")
                    print("📱 Widget timeline reloaded")
                case .failure(let error):
                    print("⚠️  Failed to fetch track: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - In-app widget debug helpers

    private func startWidgetDebug() {
        guard !songTitle.isEmpty, !artistName.isEmpty else {
            debugStatus = "Play a song first, then try again."
            showWidgetDebug = true
            return
        }

        debugStatus = "Loading lyrics…"
        showWidgetDebug = true
        debugLyrics = []
        debugCurrentIndex = 0
        debugPlaybackMs = 0

        // Fetch lyrics once using the same Genius helper as the widget
        Task {
            do {
                let lyrics = try await GeniusLyrics.fetch(for: songTitle, artist: artistName)
                let lines = lyrics
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

                await MainActor.run {
                    self.debugLyrics = lines
                    self.debugStatus = lines.isEmpty ? "No lyrics found." : "Debug view running…"
                    self.startDebugTimer()
                }
            } catch {
                await MainActor.run {
                    self.debugStatus = "Failed to load lyrics."
                }
            }
        }
    }

    private func startDebugTimer() {
        debugTimer?.invalidate()
        debugPlaybackMs = 0
        debugCurrentIndex = 0

        // For debugging, just advance time locally every second.
        debugTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            debugPlaybackMs += 1_000

            let idx = calculateDebugLyricIndex(
                progressMs: debugPlaybackMs,
                durationMs: debugDurationMs,
                totalLyrics: debugLyrics.count
            )
            debugCurrentIndex = idx
        }
    }

    private func stopWidgetDebug() {
        debugTimer?.invalidate()
        debugTimer = nil
        debugStatus = ""
    }

    // Same logic as the widget's calculateLyricIndex, but local to this view
    private func calculateDebugLyricIndex(progressMs: Int, durationMs: Int?, totalLyrics: Int) -> Int {
        guard totalLyrics > 0 else { return 0 }

        let offsetMs = 3_000
        let adjusted = max(progressMs - offsetMs, 0)

        guard let duration = durationMs, duration > 0 else {
            return min(adjusted / 4_000, totalLyrics - 1)
        }

        let percent = Double(adjusted) / Double(duration)
        let idx = Int(percent * Double(totalLyrics))
        return min(max(idx, 0), totalLyrics - 1)
    }

    private func formatDebugTime(_ ms: Int) -> String {
        guard ms >= 0 else { return "--:--" }
        let totalSeconds = ms / 1_000
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Live Activity (Genius)
    private func startLiveActivity() {
        print("🎯 Start Live Activity button tapped")          // ← ADD
        guard !songTitle.isEmpty else {
            print("⚠️  No song title – aborting")             // ← ADD
            return
        }
        let attributes = LyricWidgetAttributes(songTitle: songTitle, artistName: artistName)
        let initial = LyricWidgetAttributes.ContentState(currentLyric: "Fetching lyrics…", elapsedTime: "0:00")

        do {
            print("📦 Requesting Live Activity…")              // ← ADD
            let content = ActivityContent(state: initial, staleDate: nil)
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            activityStarted = true
            print("✅ Live Activity started – updating lyrics…")
            Task {
                if let activity = activity {
                    await LyricWidgetLiveActivity.updateActivity(activity, geniusToken: geniusToken)
                }
            }
        } catch {
            print("❌ Live Activity failed: \(error)")         // ← ADD
        }
    }

    // MARK: - Utils
    private func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<length).compactMap { _ in letters.randomElement() })
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
final class ContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Get the first available window scene and its window
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            if let window = windowScene.windows.first {
                return window
            }
            // If no window exists, create one using the window scene
            return ASPresentationAnchor(windowScene: windowScene)
        }
        // Fallback: create a basic window with a window scene (should rarely happen)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return UIWindow(windowScene: windowScene)
        }
        // Last resort fallback
        return UIWindow(frame: UIScreen.main.bounds)
    }
}
