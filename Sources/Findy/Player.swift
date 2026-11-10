import Foundation
import SwiftUI
import AVFoundation

// MARK: - Audio Player

@Observable
public final class Player {
    public var queue: [FileItem] = []
    public var index: Int = 0
    public var isPlaying: Bool = false
    public var currentTime: Double = 0
    public var duration: Double = 0
    public var volume: Float = 0.85 {
        didSet { avPlayer.volume = volume }
    }
    public var shuffle: Bool = false
    public var repeatOne: Bool = false

    private let avPlayer = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    public init() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
            if let dur = self.avPlayer.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
                self.duration = dur
            }
        }
    }

    deinit {
        if let timeObserver {
            avPlayer.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    public var current: FileItem? {
        guard queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    public func play(_ item: FileItem, in list: [FileItem]) {
        let tracks = list.isEmpty ? [item] : list
        self.queue = tracks
        self.index = tracks.firstIndex(of: item) ?? 0
        loadCurrent(autoPlay: true)
    }

    public func togglePlay() {
        guard current != nil else { return }
        if isPlaying {
            avPlayer.pause()
            isPlaying = false
        } else {
            avPlayer.play()
            isPlaying = true
        }
    }

    public func stop() {
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        isPlaying = false
        queue = []
        index = 0
        currentTime = 0
        duration = 0
    }

    public func next() {
        guard !queue.isEmpty else { return }
        if shuffle && queue.count > 1 {
            index = Int.random(in: 0..<queue.count)
        } else {
            index = (index + 1) % queue.count
        }
        loadCurrent(autoPlay: true)
    }

    public func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
        } else {
            index = (index - 1 + queue.count) % queue.count
            loadCurrent(autoPlay: true)
        }
    }

    public func seek(to seconds: Double) {
        let cm = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        avPlayer.seek(to: cm)
        currentTime = max(0, seconds)
    }

    private func loadCurrent(autoPlay: Bool) {
        guard let item = current else { return }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        let playerItem = AVPlayerItem(url: item.url)
        avPlayer.replaceCurrentItem(with: playerItem)
        avPlayer.volume = volume
        currentTime = 0
        duration = item.duration ?? 0

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.repeatOne {
                self.seek(to: 0)
                self.avPlayer.play()
            } else {
                self.next()
            }
        }

        if autoPlay {
            avPlayer.play()
            isPlaying = true
        }
    }
}

// MARK: - Sidebar MiniPlayer

public struct MiniPlayer: View {
    @Environment(Player.self) private var player

    public init() {}

    public var body: some View {
        if let track = player.current {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    ThumbnailView(item: track, cornerRadius: 8)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title ?? track.displayTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist ?? "Audio Track")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(1, player.duration)
                )
                .controlSize(.mini)

                HStack {
                    Text(Fmt.duration(player.currentTime))
                        .font(Theme.mono(9.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 14) {
                        Button { player.previous() } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)

                        Button { player.togglePlay() } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)

                        Button { player.next() } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text(Fmt.duration(player.duration))
                        .font(Theme.mono(9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.regularMaterial)
        }
    }
}
