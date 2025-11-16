//
//  ShareViewController.swift
//  shareextension
//
//  Created by Zachary Upstone on 16/11/2025.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        handleSharedContent()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        statusLabel.text = "Processing..."
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 18, weight: .medium)
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    private func handleSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProviders = extensionItem.attachments else {
            showError("No content found")
            return
        }

        // Look for URL
        for provider in itemProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
                    DispatchQueue.main.async {
                        if let url = item as? URL {
                            self?.processURL(url)
                        } else {
                            self?.showError("Could not load URL")
                        }
                    }
                }
                return
            }
        }

        showError("No URL found")
    }

    private func processURL(_ url: URL) {
        let urlString = url.absoluteString

        var spotifyURI: String?

        if urlString.contains("open.spotify.com") {
            let components = url.pathComponents
            if components.count >= 3 {
                let type = components[1]
                var id = components[2]
                if let questionMark = id.firstIndex(of: "?") {
                    id = String(id[..<questionMark])
                }
                spotifyURI = "spotify:\(type):\(id)"
            }
        } else if urlString.hasPrefix("spotify:") {
            spotifyURI = urlString
        }

        if let uri = spotifyURI {
            saveAndComplete(uri: uri)
        } else {
            showError("Not a Spotify link")
        }
    }

    private func saveAndComplete(uri: String) {
        // Store in shared UserDefaults
        if let defaults = UserDefaults(suiteName: "group.zach.songshare") {
            defaults.set(uri, forKey: "sharedSongURI")
            defaults.set(Date(), forKey: "sharedSongTimestamp")
            defaults.synchronize()
        }

        statusLabel.text = "✓ Song saved!\n\nOpen SongShare to send it to nearby devices."

        // Auto-close after a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.completeRequest()
        }
    }

    private func showError(_ message: String) {
        statusLabel.text = "Error: \(message)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.completeRequest()
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
