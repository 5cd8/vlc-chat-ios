import Testing
@testable import VLCChatCore

struct NowPlayingStateTests {
  private func state(position: Double, duration: Double? = nil, rate: Double = 1.5, isPlaying: Bool = true)
    -> NowPlayingState
  {
    NowPlayingState(title: "t", duration: duration, position: position, rate: rate, isPlaying: isPlaying)
  }

  @Test("再生中は選んだ速度、一時停止は0") func rateForSystem() {
    #expect(state(position: 0, isPlaying: true).rateForSystem == 1.5)
    #expect(state(position: 0, isPlaying: false).rateForSystem == 0)
  }

  @Test("経過時間は0以上、長さ以下") func elapsedIsClamped() {
    #expect(state(position: -3, duration: 60).elapsedForSystem == 0)
    #expect(state(position: 70, duration: 60).elapsedForSystem == 60)
    #expect(state(position: 30, duration: 60).elapsedForSystem == 30)
  }

  @Test("長さが無ければ下限だけ") func elapsedWithoutDuration() {
    #expect(state(position: 1000, duration: nil).elapsedForSystem == 1000)
    #expect(state(position: -1, duration: nil).elapsedForSystem == 0)
  }

  @Test("titleがnilならmakeもnil") func makeReturnsNilWithoutTitle() {
    #expect(NowPlayingState.make(title: nil, clock: PlaybackClock(), at: 0) == nil)
  }

  @Test("再生中のmake") func makeWhilePlaying() throws {
    var clock = PlaybackClock()
    clock.play(at: 0)
    clock.noteMediaTime(10, at: 0)
    let made = try #require(NowPlayingState.make(title: "a", clock: clock, at: 0.5))
    #expect(made.position == 10.5)
    #expect(made.isPlaying)
    #expect(made.rateForSystem == 1)
  }

  @Test("makeは選んだ速度と長さを引き継ぐ") func makeCarriesRateAndDuration() throws {
    var clock = PlaybackClock()
    clock.play(at: 0)
    clock.setRate(1.5, at: 0)
    clock.setDuration(60)
    let made = try #require(NowPlayingState.make(title: "a", clock: clock, at: 0))
    #expect(made.rate == 1.5)
    #expect(made.duration == 60)
  }

  @Test("一時停止後のmakeは止まった位置と速度0") func makeWhilePaused() throws {
    var clock = PlaybackClock()
    clock.play(at: 0)
    clock.noteMediaTime(10, at: 0)
    clock.pause(at: 2)
    let made = try #require(NowPlayingState.make(title: "a", clock: clock, at: 100))
    #expect(made.position == 12)
    #expect(!made.isPlaying)
    #expect(made.rateForSystem == 0)
  }

  @Test("停止後のmakeは位置0") func makeAfterStop() throws {
    var clock = PlaybackClock()
    clock.play(at: 0)
    clock.noteMediaTime(10, at: 0)
    clock.stop()
    let made = try #require(NowPlayingState.make(title: "a", clock: clock, at: 5))
    #expect(made.position == 0)
    #expect(!made.isPlaying)
  }
}
