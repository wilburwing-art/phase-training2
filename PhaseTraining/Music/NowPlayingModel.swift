// NowPlayingModel.swift — what Apple Music is playing, and play / pause / next.
//
// The Log screen shows a media card while a workout is running so a track
// change does not mean leaving the app (the Google Maps card during
// navigation). Backed by MPMusicPlayerController.systemMusicPlayer, which
// "controls the Music app's state": transport commands need no
// authorisation; reading the now-playing item needs media-library access
// and NSAppleMusicUsageDescription, so the first time music is playing the
// card asks before it shows a title. Denied means hidden, nothing else.
//
// Same seam shape as HealthKitImporter's HKHealthStoreInterface: the model
// talks to a protocol, production passes the MediaPlayer wrapper, tests and
// the --ui-test-fake-now-playing launch flag pass a fake.

import Combine
import Foundation
import MediaPlayer
import UIKit

/// The fields the card shows. Artwork is resolved at a fixed size up front
/// so the view never touches MediaPlayer.
struct NowPlayingTrack: Equatable {
    let title: String
    let artist: String
    let artwork: UIImage?
}

enum MusicPlaybackState: Equatable {
    case stopped, playing, paused
}

enum MusicLibraryAuthorization: Equatable {
    case notDetermined, authorized, denied
}

/// Minimal surface of the system music player the model touches.
protocol SystemMusicPlayerInterface: AnyObject {
    var playbackState: MusicPlaybackState { get }
    var authorization: MusicLibraryAuthorization { get }
    /// nil when nothing is queued or the library is not authorised.
    func nowPlaying() -> NowPlayingTrack?
    func requestAuthorization() async -> Bool
    func play()
    func pause()
    func skipToNext()
    /// Fires on every now-playing-item or playback-state change.
    var changes: AnyPublisher<Void, Never> { get }
}

/// Production adapter over MPMusicPlayerController.systemMusicPlayer.
final class MPMusicPlayerWrapper: SystemMusicPlayerInterface {
    private let player = MPMusicPlayerController.systemMusicPlayer
    private let subject = PassthroughSubject<Void, Never>()
    private var observers: [NSObjectProtocol] = []

    /// Artwork edge in points; the card draws it at 40pt.
    static let artworkSize = CGSize(width: 80, height: 80)

    init() {
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
                     Notification.Name.MPMusicPlayerControllerPlaybackStateDidChange] {
            observers.append(center.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                self?.subject.send()
            })
        }
        // The system player "takes on the current Music app state" on
        // instantiation and then follows notifications; a track started in
        // the Music app while this app was in the background can arrive
        // late or not at all, so coming back to the foreground re-reads.
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.subject.send()
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        player.endGeneratingPlaybackNotifications()
    }

    var playbackState: MusicPlaybackState {
        switch player.playbackState {
        case .playing, .seekingForward, .seekingBackward: return .playing
        case .paused, .interrupted: return .paused
        default: return .stopped
        }
    }

    var authorization: MusicLibraryAuthorization {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func nowPlaying() -> NowPlayingTrack? {
        guard authorization == .authorized, let item = player.nowPlayingItem else { return nil }
        return NowPlayingTrack(
            title: item.title ?? "Unknown track",
            artist: item.artist ?? item.albumArtist ?? "",
            artwork: item.artwork?.image(at: Self.artworkSize)
        )
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            MPMediaLibrary.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }
    func skipToNext() { player.skipToNextItem() }

    var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
}

/// The card's state, derived from the player on every change.
@MainActor
final class NowPlayingModel: ObservableObject {
    enum State: Equatable {
        /// Nothing playing, or access denied: no card.
        case hidden
        /// Music is playing but the library is not yet authorised, so the
        /// title cannot be read. The card offers "Show controls".
        case needsPermission
        case track(NowPlayingTrack, isPlaying: Bool)
    }

    @Published private(set) var state: State = .hidden

    private let player: SystemMusicPlayerInterface
    private var subscription: AnyCancellable?

    init(player: SystemMusicPlayerInterface) {
        self.player = player
        refresh()
        // No queue hop: the wrapper already delivers on main (its observers
        // are registered with `queue: .main`), and a synchronous refresh is
        // what lets a notification and the card agree within one run loop.
        subscription = player.changes
            .sink { [weak self] in self?.refresh() }
    }

    /// Shown while music is playing but the player has no item to report
    /// yet: transport works regardless, and the title fills in on the next
    /// notification. (Build 133 hid the card in that state, which is what
    /// the owner saw right after granting access.)
    static let untitled = NowPlayingTrack(title: "Apple Music", artist: "", artwork: nil)

    func refresh() {
        let playback = player.playbackState
        guard playback != .stopped else { state = .hidden; return }
        switch player.authorization {
        case .denied:
            state = .hidden
        case .notDetermined:
            state = .needsPermission
        case .authorized:
            state = .track(player.nowPlaying() ?? Self.untitled, isPlaying: playback == .playing)
        }
    }

    func requestAccess() {
        Task {
            _ = await player.requestAuthorization()
            refresh()
            // The item can lag the grant by a beat; read once more.
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }

    func togglePlayPause() {
        guard case .track(_, let isPlaying) = state else { return }
        if isPlaying { player.pause() } else { player.play() }
        refresh()
    }

    func next() {
        player.skipToNext()
        refresh()
    }
}

/// Stand-in for the simulator and UI tests, which have no Music app.
/// `--ui-test-fake-now-playing` builds one that is playing and authorised.
final class FakeMusicPlayer: SystemMusicPlayerInterface {
    var playbackState: MusicPlaybackState
    var authorization: MusicLibraryAuthorization
    var track: NowPlayingTrack?
    var grantOnRequest = true
    private(set) var playCalls = 0
    private(set) var pauseCalls = 0
    private(set) var nextCalls = 0
    let subject = PassthroughSubject<Void, Never>()

    init(playbackState: MusicPlaybackState = .stopped,
         authorization: MusicLibraryAuthorization = .notDetermined,
         track: NowPlayingTrack? = nil) {
        self.playbackState = playbackState
        self.authorization = authorization
        self.track = track
    }

    func nowPlaying() -> NowPlayingTrack? { authorization == .authorized ? track : nil }

    func requestAuthorization() async -> Bool {
        authorization = grantOnRequest ? .authorized : .denied
        return grantOnRequest
    }

    func play() { playCalls += 1; playbackState = .playing }
    func pause() { pauseCalls += 1; playbackState = .paused }
    func skipToNext() { nextCalls += 1 }
    var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    /// Simulate the Music app changing state underneath the card.
    func emit() { subject.send() }
}
