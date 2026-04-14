// Bend Fly Shop

import AVFoundation
import SwiftUI

// MARK: - UIKit wrapper for AVPlayerLayer (no default controls)

private class PlayerUIView: UIView {
    private let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}
}

// MARK: - Availability-gated modifier to hide system overlays

private struct HideOverlaysModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.persistentSystemOverlays(.hidden)
        } else {
            content
        }
    }
}

// MARK: - Fullscreen splash video view

struct SplashVideoView: View {
    let videoURL: URL
    let onComplete: () -> Void

    private static var maxPlayDuration: TimeInterval { AppEnvironment.shared.splashVideoMaxDuration }

    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var maxDurationTimer: Timer?
    @State private var didFinish = false
    @State private var fadeOverlayOpacity: Double = 0.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                GeometryReader { geo in
                    PlayerLayerView(player: player)
                        .frame(width: geo.size.width, height: geo.size.height * 0.95)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .mask(
                            RadialGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .white, location: 0.0),
                                    .init(color: .white, location: 0.475),
                                    .init(color: .clear, location: 0.85)
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: max(geo.size.width, geo.size.height) * 0.6
                            )
                        )
                }
                .ignoresSafeArea()
            }

            // Skip button — top-right, Loading text — bottom
            VStack {
                HStack {
                    Spacer()
                    Button(action: finish) {
                        Text("Skip")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 12)
                }
                Spacer()

            }

            // Fade-to-black overlay
            Color.black
                .ignoresSafeArea()
                .opacity(fadeOverlayOpacity)
                .allowsHitTesting(false)
        }
        .modifier(HideOverlaysModifier())
        .onAppear(perform: setupPlayer)
        .onDisappear(perform: tearDown)
    }

    // MARK: - Playback

    private func setupPlayer() {
        let item = AVPlayerItem(url: videoURL)
        let avPlayer = AVPlayer(playerItem: item)

        // Apply mute setting from configuration
        let isMuted = AppEnvironment.shared.splashVideoMuted
        avPlayer.isMuted = isMuted
        AppLogging.log("[SplashVideo] Audio muted: \(isMuted)", level: .debug, category: .ui)

        // Observe end of playback
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            finish()
        }

        // Observe error so we don't get stuck on a bad file
        statusObserver = item.observe(\.status, options: [.new]) { item, _ in
            if item.status == .failed {
                AppLogging.log("[SplashVideo] Playback failed, skipping", level: .warn, category: .ui)
                DispatchQueue.main.async { finish() }
            }
        }

        player = avPlayer
        avPlayer.play()
        AppLogging.log("[SplashVideo] Playing \(videoURL.lastPathComponent)", level: .debug, category: .ui)

        // Set max play duration timer
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: Self.maxPlayDuration, repeats: false) { _ in
            DispatchQueue.main.async {
                AppLogging.log("[SplashVideo] Max duration reached, finishing", level: .debug, category: .ui)
                finish()
            }
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true

        // Fade to black overlay
        withAnimation(.easeOut(duration: 0.6)) {
            fadeOverlayOpacity = 1.0
        }

        // Wait for fade to complete, then tear down and notify
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            tearDown()
            onComplete()
        }
    }

    private func tearDown() {
        player?.pause()
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        player = nil
    }
}
