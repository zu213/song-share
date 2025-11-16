//
//  ContentView.swift
//  songshare
//
//  Created by Zachary Upstone on 23/03/2025.
//

import SwiftUI
import MultipeerConnectivity
import UserNotifications
import Combine

struct Song: Codable, Identifiable {
    var id = UUID()
    let title: String
    let artist: String
    let uri: String
}

class PeerSession: NSObject, ObservableObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    private let serviceType = "spotify-share"

    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    @Published var receivedSong: Song?
    @Published var connectedPeers: [MCPeerID] = []
    @Published var pendingSongToShare: Song?

    override init() {
        super.init()

        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()

        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
    }

    func send(song: Song) {
        if !session.connectedPeers.isEmpty {
            if let data = try? JSONEncoder().encode(song) {
                try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
            }
        }
    }

    func restart() {
        print("Restarting peer session...")
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()

        // Recreate session
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        // Restart advertising and browsing
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()

        DispatchQueue.main.async {
            self.connectedPeers = []
        }
    }

    // MARK: - MCSessionDelegate

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
        }
        switch state {
        case .connected:
            print("Connected to: \(peerID.displayName)")
        case .connecting:
            print("Connecting to: \(peerID.displayName)")
        case .notConnected:
            print("Disconnected from: \(peerID.displayName)")
        @unknown default:
            print("Unknown state for: \(peerID.displayName)")
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let song = try? JSONDecoder().decode(Song.self, from: data) {
          DispatchQueue.main.async {
              let content = UNMutableNotificationContent()
              content.title = "New Song from \(peerID.displayName)"
              content.body = "\(song.title) by \(song.artist)"
              content.sound = UNNotificationSound.default

              // Convert spotify:track:xxx to spotify://track/xxx
              let spotifyURL = song.uri.replacingOccurrences(of: ":", with: "/").replacingOccurrences(of: "spotify", with: "spotify:/")
              if let url = URL(string: spotifyURL) {
                  content.userInfo = ["uri": url.absoluteString]
              }

              let request = UNNotificationRequest(
                  identifier: UUID().uuidString,
                  content: content,
                  trigger: nil
              )

              UNUserNotificationCenter.current().add(request)
          }
        }
    }


    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // MARK: - Advertiser & Browser

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Received invitation from: \(peerID.displayName)")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to advertise: \(error.localizedDescription)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("Found peer: \(peerID.displayName)")
        // Only invite if not already connected
        if !session.connectedPeers.contains(peerID) {
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost peer: \(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Failed to browse: \(error.localizedDescription)")
    }
}

struct ContentView: View {
    @ObservedObject var peerSession: PeerSession
    @State private var customURI: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("🎵 Spotify Song Share")
                .font(.title)

            Text("Connected Peers: \(peerSession.connectedPeers.count)")
                .font(.subheadline)
                .foregroundColor(peerSession.connectedPeers.isEmpty ? .red : .green)

            if peerSession.connectedPeers.isEmpty {
                Button("Restart Discovery") {
                    peerSession.restart()
                }
                .buttonStyle(.bordered)
            }

            // Show pending song from Share Extension
            if let pending = peerSession.pendingSongToShare {
                VStack(spacing: 8) {
                    Text("Ready to Share")
                        .font(.headline)
                    Text(pending.uri)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Share to Nearby Devices") {
                        peerSession.send(song: pending)
                        peerSession.pendingSongToShare = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(peerSession.connectedPeers.isEmpty)

                    Button("Cancel") {
                        peerSession.pendingSongToShare = nil
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            }

            TextField("Spotify URI (e.g. spotify:track:...)", text: $customURI)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .autocorrectionDisabled()

            Button("Send Song") {
                let uri = customURI.isEmpty ? "spotify:track:4vpeKl0vMGdAXpZiQB2Dtd" : customURI
                let song = Song(title: "Shared Song", artist: "Via SongShare", uri: uri)
                peerSession.send(song: song)
            }
            .buttonStyle(.borderedProminent)
            .disabled(peerSession.connectedPeers.isEmpty)
          
          Button("Simulate Song Receive") {
              let fakeSong = Song(title: "Debug Song", artist: "Test Artist", uri: "spotify:track:4vpeKl0vMGdAXpZiQB2Dtd")
              
              let content = UNMutableNotificationContent()
              content.title = "New Song (Test)"
              content.body = "\(fakeSong.title) by \(fakeSong.artist)"
              content.sound = UNNotificationSound.default

            print(fakeSong.uri)
            let temp = fakeSong.uri.replacingOccurrences(of: ":", with: "/").replacingOccurrences(of: "spotify", with: "spotify:/")
              if let url = URL(string: temp)
            {
                  content.userInfo = ["uri": url.absoluteString]
              }

              let request = UNNotificationRequest(
                  identifier: UUID().uuidString,
                  content: content,
                  trigger: nil
              )

              UNUserNotificationCenter.current().add(request)
          }

            if let received = peerSession.receivedSong {
                VStack(spacing: 8) {
                    Text("Received Song")
                        .font(.headline)
                    Text("\(received.title) - \(received.artist)")
                        .multilineTextAlignment(.center)
                    Button("Open in Spotify") {
                        if let url = URL(string: received.uri) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
            }
        }
        .padding()
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onAppear {
            checkForSharedSong()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkForSharedSong()
        }
    }

    private func handleIncomingURL(_ url: URL) {
        print("Received URL: \(url)")
        guard url.scheme == "songshare",
              url.host == "share",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let uriParam = components.queryItems?.first(where: { $0.name == "uri" })?.value else {
            return
        }

        // Populate the URI text field
        customURI = uriParam
    }

    private func checkForSharedSong() {
        guard let defaults = UserDefaults(suiteName: "group.zach.songshare"),
              let uri = defaults.string(forKey: "sharedSongURI"),
              let timestamp = defaults.object(forKey: "sharedSongTimestamp") as? Date else {
            return
        }

        // Only use if shared within last 5 minutes
        if Date().timeIntervalSince(timestamp) < 300 {
            // Populate the URI text field
            customURI = uri

            // Clear it so we don't show it again
            defaults.removeObject(forKey: "sharedSongURI")
            defaults.removeObject(forKey: "sharedSongTimestamp")
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        print(response.notification.request.content.userInfo)
        if let uri = response.notification.request.content.userInfo["uri"] as? String,
           let url = URL(string: uri) {
            UIApplication.shared.open(url)
        }
        completionHandler()
    }
}

@main
struct SpotifyPeerShareApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var peerSession = PeerSession()

    init() {
        requestNotificationPermission()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(peerSession: peerSession)
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }
}

