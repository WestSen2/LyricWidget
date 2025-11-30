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

            Button(activityStarted ? "Live Activity Started" : "Start Live Activity") {
                startLiveActivity()
            }
            .buttonStyle(LoginButtonStyle(color: activityStarted ? .gray : .blue))
            .disabled(activityStarted)
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
