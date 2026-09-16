// NowPlayingCard.swift — the media card above the tab bar on the Log screen.
//
// Artwork, title, artist, play/pause, next: what is playing in Apple Music,
// controllable without leaving the workout. Renders nothing for `.hidden`;
// the parent decides whether to reserve space (LogScreen uses a
// safeAreaInset that comes and goes with the card).

import SwiftUI

struct NowPlayingCard: View {
    @ObservedObject var model: NowPlayingModel

    var body: some View {
        switch model.state {
        case .hidden:
            EmptyView()
        case .needsPermission:
            row {
                artworkSlot(nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Music is playing")
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                    Text("Allow access to see the track and control it here")
                        .styled(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button("Show controls") { model.requestAccess() }
                    .styled(.monoXS)
                    .foregroundStyle(Color.accentInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.accent)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("now-playing-allow")
            }
        case .track(let track, let isPlaying):
            row {
                artworkSlot(track.artwork)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .styled(.body)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    if !track.artist.isEmpty {
                        Text(track.artist)
                            .styled(.monoXS)
                            .foregroundStyle(Color.ink3)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Now playing, \(track.title), \(track.artist)")
                Spacer(minLength: 8)
                control(isPlaying ? "pause.fill" : "play.fill",
                        label: isPlaying ? "Pause" : "Play",
                        id: "now-playing-toggle") { model.togglePlayPause() }
                control("forward.fill", label: "Next track", id: "now-playing-next") { model.next() }
            }
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12, content: content)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.line, lineWidth: 0.5))
    }

    private func artworkSlot(_ image: UIImage?) -> some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.elevated
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.ink3)
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    private func control(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

#Preview("Now playing") {
    let fake = FakeMusicPlayer(playbackState: .playing, authorization: .authorized,
                               track: NowPlayingTrack(title: "Blinding Lights", artist: "The Weeknd", artwork: nil))
    return VStack(spacing: 12) {
        NowPlayingCard(model: NowPlayingModel(player: fake))
        NowPlayingCard(model: NowPlayingModel(player: FakeMusicPlayer(playbackState: .playing)))
    }
    .padding(20)
    .background(Color.bg.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
