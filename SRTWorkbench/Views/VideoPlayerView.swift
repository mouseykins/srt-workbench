import AVKit
import SwiftUI

struct VideoPlayerView: NSViewRepresentable {
    let videoURL: URL
    var captionText: String?
    var onTimeUpdate: (TimeInterval) -> Void

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let playerView = AVPlayerView()
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.controlsStyle = .inline
        container.addSubview(playerView)

        // Caption label
        let captionLabel = NSTextField(labelWithString: "")
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.alignment = .center
        captionLabel.font = .systemFont(ofSize: 18, weight: .medium)
        captionLabel.textColor = .white
        captionLabel.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        captionLabel.isBezeled = false
        captionLabel.drawsBackground = true
        captionLabel.maximumNumberOfLines = 3
        captionLabel.lineBreakMode = .byWordWrapping
        captionLabel.isHidden = true
        container.addSubview(captionLabel)

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: container.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            captionLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            captionLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -60),
            captionLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.9),
        ])

        context.coordinator.playerView = playerView
        context.coordinator.captionLabel = captionLabel
        context.coordinator.setupPlayer(url: videoURL, onTimeUpdate: onTimeUpdate)

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update caption text
        if let label = context.coordinator.captionLabel {
            if let text = captionText, !text.isEmpty {
                label.stringValue = text
                label.isHidden = false
            } else {
                label.isHidden = true
            }
        }

        // Update video URL if changed
        if context.coordinator.currentURL != videoURL {
            context.coordinator.setupPlayer(url: videoURL, onTimeUpdate: onTimeUpdate)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var playerView: AVPlayerView?
        var captionLabel: NSTextField?
        var currentURL: URL?
        var timeObserver: Any?
        var rateObserver: NSKeyValueObservation?
        var notificationObservers: [Any] = []
        var currentSpeed: Float = 1.0

        func setupPlayer(url: URL, onTimeUpdate: @escaping (TimeInterval) -> Void) {
            // Remove old observers
            if let observer = timeObserver, let player = playerView?.player {
                player.removeTimeObserver(observer)
            }
            rateObserver?.invalidate()
            rateObserver = nil
            for obs in notificationObservers {
                NotificationCenter.default.removeObserver(obs)
            }
            notificationObservers.removeAll()

            currentURL = url
            let player = AVPlayer(url: url)
            playerView?.player = player

            // Observe rate changes to enforce desired speed.
            // This catches spacebar play (AVPlayerView built-in controls)
            // which always resumes at rate 1.0.
            rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, change in
                guard let self = self else { return }
                let newRate = change.newValue ?? 0
                if newRate > 0 && newRate != self.currentSpeed {
                    DispatchQueue.main.async {
                        player.rate = self.currentSpeed
                    }
                }
            }

            // Add periodic time observer at 10Hz
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                onTimeUpdate(time.seconds)
            }

            // Seek to time (from Jump buttons)
            notificationObservers.append(
                NotificationCenter.default.addObserver(
                    forName: .seekToTime, object: nil, queue: .main
                ) { [weak self] notification in
                    guard let time = notification.userInfo?["time"] as? TimeInterval else { return }
                    self?.playerView?.player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
                    self?.playerView?.player?.pause()
                }
            )

            // Play/Pause toggle (KVO rate observer auto-corrects to currentSpeed)
            notificationObservers.append(
                NotificationCenter.default.addObserver(
                    forName: .togglePlayback, object: nil, queue: .main
                ) { [weak self] _ in
                    guard let player = self?.playerView?.player else { return }
                    if player.timeControlStatus == .playing {
                        player.pause()
                    } else {
                        player.play()
                    }
                }
            )

            // Skip backward 5s
            notificationObservers.append(
                NotificationCenter.default.addObserver(
                    forName: .skipBackward, object: nil, queue: .main
                ) { [weak self] _ in
                    guard let player = self?.playerView?.player else { return }
                    let current = player.currentTime().seconds
                    player.seek(to: CMTime(seconds: max(0, current - 5), preferredTimescale: 600))
                }
            )

            // Skip forward 5s
            notificationObservers.append(
                NotificationCenter.default.addObserver(
                    forName: .skipForward, object: nil, queue: .main
                ) { [weak self] _ in
                    guard let player = self?.playerView?.player else { return }
                    let current = player.currentTime().seconds
                    player.seek(to: CMTime(seconds: current + 5, preferredTimescale: 600))
                }
            )

            // Set playback speed (KVO rate observer enforces it when playing)
            notificationObservers.append(
                NotificationCenter.default.addObserver(
                    forName: .setPlaybackSpeed, object: nil, queue: .main
                ) { [weak self] notification in
                    guard let speed = notification.userInfo?["speed"] as? Double else { return }
                    self?.currentSpeed = Float(speed)
                    // If currently playing, setting rate triggers KVO which is a no-op
                    // since currentSpeed already matches. Just set it directly.
                    if let player = self?.playerView?.player,
                       player.timeControlStatus == .playing {
                        player.rate = Float(speed)
                    }
                }
            )
        }

        deinit {
            if let observer = timeObserver, let player = playerView?.player {
                player.removeTimeObserver(observer)
            }
            rateObserver?.invalidate()
            for obs in notificationObservers {
                NotificationCenter.default.removeObserver(obs)
            }
        }
    }
}
