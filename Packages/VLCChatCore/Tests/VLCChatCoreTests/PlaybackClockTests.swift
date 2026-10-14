import Testing
@testable import VLCChatCore

/// 期待値は5.1節の規則から手計算したもの。値はすべて2進で正確に表せる（`==` で比べてよい）。
/// 特に断らない限り、各テストは `play(at: 0)` を呼んだ状態から始める（停止中は時刻通知を無視するため）。
struct PlaybackClockTests {
  private func playingClock() -> PlaybackClock {
    var clock = PlaybackClock()
    clock.play(at: 0)
    return clock
  }

  @Test("初期状態は停止で位置0") func initialState() {
    let clock = PlaybackClock()
    #expect(clock.mode == .stopped)
    #expect(clock.position(at: 5) == 0)
  }

  @Test("再生中は通知の位置から補間する") func interpolatesWhilePlaying() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    #expect(clock.position(at: 0.5) == 10.5)
  }

  @Test("倍速では経過の2倍進む") func interpolatesAtDoubleRate() {
    var clock = playingClock()
    clock.setRate(2, at: 0)
    clock.noteMediaTime(10, at: 0)
    #expect(clock.position(at: 0.5) == 11.0)
  }

  @Test("速度変更で基準を取り直す") func setRateRebases() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    #expect(clock.position(at: 1) == 11)
    clock.setRate(0.5, at: 1)
    #expect(clock.position(at: 3) == 12)  // 11 + 2×0.5
  }

  @Test("一時停止で位置が止まる") func pauseFreezesPosition() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.pause(at: 2)
    #expect(clock.position(at: 100) == 12)
  }

  @Test("一時停止中の時刻通知は権威のある値") func acceptsNoteWhilePaused() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.pause(at: 2)
    clock.noteMediaTime(12.3, at: 3)
    #expect(clock.position(at: 9) == 12.3)
  }

  @Test("前方へのずれは受け入れる") func acceptsForwardDrift() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.noteMediaTime(11, at: 0.5)  // current は 10.5
    #expect(clock.position(at: 0.5) == 11)
  }

  @Test("わずかな後退は無視し、基準を変えない") func ignoresSmallBackwardJump() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    let jumped = clock.noteMediaTime(10.4, at: 0.5)  // current 10.5、後退0.1 ≤ 0.5
    #expect(clock.position(at: 0.5) == 10.5)
    #expect(!jumped)
  }

  @Test("大きな後退は受け入れ、跳びとして知らせる") func acceptsLargeBackwardJump() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    let jumped = clock.noteMediaTime(5, at: 0.5)  // 後退5.5 > 0.5
    #expect(clock.position(at: 0.5) == 5)
    #expect(jumped)
  }

  @Test("シーク直後の古い通知を捨てる") func discardsStaleNotesAfterSeek() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.seek(to: 100, at: 1)
    let accepted = clock.noteMediaTime(11, at: 1.1)  // |11−100| > 1.0、経過0.1 < 2.0
    #expect(!accepted)
    #expect(clock.position(at: 1.5) == 100)  // シーク待ちの間は補間しない
  }

  @Test("シーク先に近い通知を受け入れる") func acceptsNoteNearSeekTarget() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.seek(to: 100, at: 1)
    clock.noteMediaTime(100.2, at: 1.3)  // |100.2−100| = 0.2 ≤ 1.0
    #expect(clock.position(at: 1.3) == 100.2)
  }

  @Test("シークのタイムアウト後は遠い通知も受け入れる") func acceptsAnyNoteAfterSeekTimeout() {
    var clock = playingClock()
    clock.seek(to: 100, at: 0)
    let jumped = clock.noteMediaTime(50, at: 2.0)  // |50−100| > 1.0 だが経過 2.0 ≥ 2.0
    #expect(clock.position(at: 2.0) == 50)
    #expect(jumped)  // 受け入れ前の位置100との差50
  }

  @Test("長さで位置を打ち切る") func clampsToDuration() {
    var clock = playingClock()
    clock.setDuration(60)
    clock.noteMediaTime(59.9, at: 0)
    #expect(clock.position(at: 5) == 60)  // 5 + 59.9 を60で打ち切る
  }

  @Test("停止で0に戻り、停止中の通知は無視される") func stopResetsAndIgnoresNotes() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.stop()
    #expect(clock.mode == .stopped)
    #expect(clock.position(at: 5) == 0)
    let accepted = clock.noteMediaTime(20, at: 1)
    #expect(!accepted)
    clock.play(at: 2)
    #expect(clock.position(at: 3) == 0)  // 通知を取り込んでいれば 20 になる
  }

  @Test("シーク目標のクランプは後続の動きで確かめる") func seekTargetIsClamped() {
    var clock = playingClock()
    clock.setDuration(60)
    clock.seek(to: 100, at: 0)
    #expect(clock.position(at: 0) == 60)
    // 目標が60にクランプされていれば |59.8−60| ≤ 1.0 で受け入れられる。されていなければ捨てられる。
    clock.noteMediaTime(59.8, at: 0.1)
    #expect(clock.position(at: 0.1) == 59.8)
    clock.seek(to: -5, at: 1)
    // 目標が0にクランプされていれば |0.25−0| ≤ 1.0 で受け入れられ 0.25 + 5。されていなければ捨てられ0のまま。
    clock.noteMediaTime(0.25, at: 1.25)
    #expect(clock.position(at: 6.25) == 5.25)
  }

  @Test("再生中のplayは位置を変えない") func playWhilePlayingKeepsPosition() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.play(at: 5)
    #expect(clock.position(at: 5) == 15)  // 基準を更新すると10に戻る
  }

  @Test("一時停止中・停止中のpauseは何もしない") func pauseOutsidePlayingIsNoOp() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.pause(at: 2)
    clock.pause(at: 100)
    #expect(clock.position(at: 100) == 12)
    clock.stop()
    clock.pause(at: 1)
    #expect(clock.mode == .stopped)  // 変異の検出はこちらが担う（前半はガードが無くても同じ値）
  }

  @Test("最初の通知までは補間しない") func doesNotInterpolateBeforeFirstNote() {
    var clock = playingClock()
    #expect(clock.position(at: 3) == 0)

    clock.noteMediaTime(10, at: 0)
    clock.pause(at: 2)
    clock.play(at: 20)
    #expect(clock.position(at: 21) == 12)
  }

  @Test("最初の通知は無条件に受け入れる") func adoptsFirstNoteUnconditionally() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.pause(at: 2)
    clock.play(at: 20)
    clock.noteMediaTime(11.8, at: 20.3)  // 12との差0.2は、通常なら無視される範囲
    #expect(clock.position(at: 20.3) == 11.8)
  }

  @Test("位置の跳びの検出（戻り値）") func reportsDiscontinuities() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    let result1 = clock.noteMediaTime(30, at: 0.5)
    #expect(result1)
    #expect(clock.position(at: 0.5) == 30)
    let result2 = clock.noteMediaTime(30.2, at: 0.75)
    #expect(!result2)  // current 30.25、差0.05（無視）
    let result3 = clock.noteMediaTime(29.9, at: 1.0)
    #expect(!result3)  // current 30.5、後退0.6で受け入れるが差 ≤ 1.0
  }

  @Test("後退の許容幅の境界：ちょうど0.5は無視") func backwardToleranceBoundaryIgnored() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.noteMediaTime(10.0, at: 0.5)  // current 10.5、後退ちょうど0.5
    #expect(clock.position(at: 0.5) == 10.5)
  }

  @Test("後退の許容幅の境界：0.6は受け入れ") func backwardToleranceBoundaryAccepted() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.noteMediaTime(9.9, at: 0.5)  // 後退0.6
    #expect(clock.position(at: 0.5) == 9.9)
  }

  @Test("シークの待ちが解けたあとは通常の規則") func normalRulesApplyAfterSeekSettles() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.seek(to: 100, at: 1)
    clock.noteMediaTime(100.2, at: 1.3)
    clock.noteMediaTime(30, at: 1.4)  // 目標から遠いが、待ちは解けている
    #expect(clock.position(at: 1.4) == 30)
  }

  @Test("停止中のシークは何もしない") func seekWhileStoppedIsNoOp() {
    var clock = playingClock()
    clock.stop()
    clock.seek(to: 50, at: 1)
    clock.play(at: 2)
    clock.noteMediaTime(0.3, at: 2.1)
    #expect(clock.position(at: 2.1) == 0.3)  // seekが効いていれば pendingSeek が残り、50のまま
  }

  @Test("一時停止中のシークでも待ちの間の古い通知を捨てる") func pendingSeekPrecedesPausedRule() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.pause(at: 2)
    clock.seek(to: 50, at: 3)
    let accepted = clock.noteMediaTime(12, at: 3.1)
    #expect(!accepted)
    #expect(clock.position(at: 3.1) == 50)  // 順序が逆なら 12 になる
  }

  @Test("待ちは最初の通知の規則より先に判定される") func pendingSeekPrecedesFirstNoteRule() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.pause(at: 2)
    clock.seek(to: 50, at: 3)
    clock.play(at: 3.2)
    clock.noteMediaTime(12, at: 3.3)  // 捨てる
    #expect(clock.position(at: 3.3) == 50)
    clock.noteMediaTime(50.25, at: 3.5)  // 受け入れ
    #expect(clock.position(at: 3.5) == 50.25)
    #expect(clock.position(at: 4.5) == 51.25)  // 受け入れで awaitingFirstNote が解けて補間が再開している
  }

  @Test("長さ0や負は不明扱い") func nonPositiveDurationIsUnknown() {
    var clock = playingClock()
    clock.setDuration(0)
    clock.noteMediaTime(10, at: 0)
    #expect(clock.position(at: 1) == 11)  // 0に張り付かない
    #expect(clock.duration == nil)
    clock.setDuration(-1)
    #expect(clock.duration == nil)
  }

  @Test("stopは待ち中のシークを解く") func stopClearsPendingSeek() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.seek(to: 100, at: 1)
    clock.stop()
    clock.play(at: 2)
    clock.noteMediaTime(0.3, at: 2.1)
    #expect(clock.position(at: 2.1) == 0.3)  // pendingSeek が残っていれば捨てられて0のまま
  }

  @Test("一時停止中の跳びも検出する") func detectsJumpWhilePaused() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.pause(at: 2)
    let result4 = clock.noteMediaTime(30, at: 3)
    #expect(result4)  // PiPの窓のスキップ
    #expect(clock.position(at: 3) == 30)
  }

  @Test("閾値の境界：差ちょうど1.0は跳びではない") func thresholdBoundaryIsNotJump() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    let result5 = clock.noteMediaTime(11.5, at: 0.5)
    #expect(!result5)  // current 10.5、差ちょうど1.0
  }

  @Test("閾値の境界：差1.1は跳び") func thresholdExceededIsJump() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    let result6 = clock.noteMediaTime(11.6, at: 0.5)
    #expect(result6)  // current 10.5、差1.1
  }

  @Test("シークの許容幅の境界：差ちょうど1.0は受け入れ") func seekToleranceBoundaryIsAccepted() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.seek(to: 100, at: 1)
    clock.noteMediaTime(101.0, at: 1.1)
    #expect(clock.position(at: 1.1) == 101)
  }

  @Test("最初の通知での大きな跳びも検出する") func detectsJumpOnFirstNote() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.pause(at: 2)
    clock.play(at: 20)
    let result7 = clock.noteMediaTime(30, at: 20.3)
    #expect(result7)  // 12との差18
  }

  @Test("動き出す最初の通知・シークの着地は差が小さくてもtrue") func reportsStartOfMotion() {
    var clock = playingClock()
    let result8 = clock.noteMediaTime(0.25, at: 0.25)
    #expect(result8)
    let result9 = clock.noteMediaTime(0.5, at: 0.5)
    #expect(!result9)

    var seeking = playingClock()
    seeking.noteMediaTime(10, at: 0)
    seeking.seek(to: 100, at: 1)
    let result10 = seeking.noteMediaTime(100.25, at: 1.25)
    #expect(result10)
  }

  @Test("lastNoteDeltaは受け入れと無視した通知で更新され、捨てた通知ではnil") func tracksLastNoteDelta() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    #expect(clock.lastNoteDelta == 10)  // 止まっていた位置0との差
    clock.noteMediaTime(10.25, at: 0.5)  // current 10.5、小さな後退として無視
    #expect(clock.lastNoteDelta == -0.25)
    clock.seek(to: 100, at: 1)
    clock.noteMediaTime(11, at: 1.1)  // 捨てる
    #expect(clock.lastNoteDelta == nil)
    clock.stop()
    clock.noteMediaTime(1, at: 2)
    #expect(clock.lastNoteDelta == nil)
  }

  @Test("modeの遷移") func modeTransitions() {
    var clock = PlaybackClock()
    #expect(clock.mode == .stopped)
    clock.play(at: 0)
    #expect(clock.mode == .playing)
    clock.pause(at: 1)
    #expect(clock.mode == .paused)
    clock.seek(to: 5, at: 2)
    #expect(clock.mode == .paused)
  }

  @Test("待ち中のpauseは待ちを保つ") func pauseKeepsPendingSeek() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.seek(to: 50, at: 1)
    clock.pause(at: 1.5)
    clock.noteMediaTime(12, at: 1.6)  // 捨てる
    #expect(clock.position(at: 1.6) == 50)
    clock.noteMediaTime(50.25, at: 1.7)  // 受け入れ
    #expect(clock.position(at: 1.7) == 50.25)
  }

  @Test("一時停止中のsetRateの後に再開すると新しい速度で補間される") func setRateWhilePausedAppliesOnResume() {
    var clock = playingClock()
    clock.noteMediaTime(10, at: 0)
    clock.pause(at: 2)
    clock.setRate(2, at: 3)
    clock.play(at: 4)
    clock.noteMediaTime(12.5, at: 4.2)
    #expect(clock.position(at: 4.7) == 13.5)  // 12.5 + 0.5×2
  }
}
