import XCTest
@testable import PhaseTraining

/// The Log-screen media card's state machine, against the fake player the
/// simulator and UI tests also use. The real MPMusicPlayerController only
/// exists on a device with the Music app, so this is where the rules live.
@MainActor
final class NowPlayingModelTests: XCTestCase {

    private let song = NowPlayingTrack(title: "Blinding Lights", artist: "The Weeknd", artwork: nil)

    func test_nothingPlaying_isHidden() {
        let model = NowPlayingModel(player: FakeMusicPlayer())
        XCTAssertEqual(model.state, .hidden)
    }

    func test_playingWithoutAuthorization_asksFirst() {
        let model = NowPlayingModel(player: FakeMusicPlayer(playbackState: .playing, track: song))
        XCTAssertEqual(model.state, .needsPermission)
    }

    func test_grantingAccess_showsTheTrack() async {
        let player = FakeMusicPlayer(playbackState: .playing, track: song)
        let model = NowPlayingModel(player: player)
        model.requestAccess()
        await Task.yield()
        // requestAccess hops through a Task; wait for the refresh it triggers.
        for _ in 0..<20 where model.state == .needsPermission { await Task.yield() }
        XCTAssertEqual(model.state, .track(song, isPlaying: true))
    }

    func test_denyingAccess_hidesAndStaysHidden() async {
        let player = FakeMusicPlayer(playbackState: .playing, track: song)
        player.grantOnRequest = false
        let model = NowPlayingModel(player: player)
        model.requestAccess()
        for _ in 0..<20 where model.state == .needsPermission { await Task.yield() }
        XCTAssertEqual(model.state, .hidden)
        player.emit()
        XCTAssertEqual(model.state, .hidden, "a denied library never asks again from the card")
    }

    func test_pauseAndStopFromTheMusicApp_followTheNotification() {
        let player = FakeMusicPlayer(playbackState: .playing, authorization: .authorized, track: song)
        let model = NowPlayingModel(player: player)
        XCTAssertEqual(model.state, .track(song, isPlaying: true))
        player.playbackState = .paused; player.emit()
        XCTAssertEqual(model.state, .track(song, isPlaying: false))
        player.playbackState = .stopped; player.emit()
        XCTAssertEqual(model.state, .hidden)
    }

    func test_togglePlayPause_callsTheRightCommand() {
        let player = FakeMusicPlayer(playbackState: .playing, authorization: .authorized, track: song)
        let model = NowPlayingModel(player: player)
        model.togglePlayPause()
        XCTAssertEqual(player.pauseCalls, 1)
        XCTAssertEqual(model.state, .track(song, isPlaying: false))
        model.togglePlayPause()
        XCTAssertEqual(player.playCalls, 1)
        XCTAssertEqual(model.state, .track(song, isPlaying: true))
    }

    func test_next_skips() {
        let player = FakeMusicPlayer(playbackState: .playing, authorization: .authorized, track: song)
        let model = NowPlayingModel(player: player)
        model.next()
        XCTAssertEqual(player.nextCalls, 1)
    }

    func test_authorizedAndPlayingWithNoItemYet_showsAnUntitledCard() {
        // Transport still works, and the title fills in on the next
        // notification; hiding here is what the owner hit right after
        // granting access on build 133.
        let player = FakeMusicPlayer(playbackState: .playing, authorization: .authorized, track: nil)
        let model = NowPlayingModel(player: player)
        XCTAssertEqual(model.state, .track(NowPlayingModel.untitled, isPlaying: true))
        player.track = song; player.emit()
        XCTAssertEqual(model.state, .track(song, isPlaying: true))
    }

    func test_stoppedAndAuthorized_isHidden() {
        let model = NowPlayingModel(player: FakeMusicPlayer(playbackState: .stopped, authorization: .authorized, track: song))
        XCTAssertEqual(model.state, .hidden)
    }
}
