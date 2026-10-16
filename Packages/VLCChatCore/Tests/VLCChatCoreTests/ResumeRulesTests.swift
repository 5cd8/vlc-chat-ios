import Testing
@testable import VLCChatCore

struct ResumeRulesTests {
  @Test("終わりから30秒を超えて残っていれば、その位置から復元する") func startPositionBoundaries() {
    #expect(ResumeRules.startPosition(saved: 100, duration: 1000) == 100)
    #expect(ResumeRules.startPosition(saved: 969, duration: 1000) == 969)  // 残り31
    #expect(ResumeRules.startPosition(saved: 970, duration: 1000) == nil)  // 残り30は先頭から
    #expect(ResumeRules.startPosition(saved: 999, duration: 1000) == nil)
    #expect(ResumeRules.startPosition(saved: nil, duration: 1000) == nil)
    #expect(ResumeRules.startPosition(saved: 1200, duration: 1000) == nil)
    #expect(ResumeRules.startPosition(saved: 1000, duration: 1000) == nil)
  }

  @Test("1秒未満の位置は復元しない") func startPositionMinimum() {
    #expect(ResumeRules.startPosition(saved: 0.9, duration: 1000) == nil)
    #expect(ResumeRules.startPosition(saved: 1.0, duration: 1000) == 1.0)
  }

  @Test("短い動画は残りが30秒以内なので先頭から") func startPositionShortVideo() {
    #expect(ResumeRules.startPosition(saved: 5, duration: 20) == nil)
  }

  @Test("長さが不明なら復元しない") func startPositionWithoutDuration() {
    #expect(ResumeRules.startPosition(saved: 100, duration: nil) == nil)
    #expect(ResumeRules.startPosition(saved: 100, duration: 0) == nil)
  }

  @Test("復元待ちは再生開始から5秒未満の間だけ") func resumePending() {
    #expect(ResumeRules.isResumePending(secondsSincePlaying: nil, restoreCompleted: false))
    #expect(ResumeRules.isResumePending(secondsSincePlaying: 4.99, restoreCompleted: false))
    #expect(!ResumeRules.isResumePending(secondsSincePlaying: 5.0, restoreCompleted: false))
    #expect(!ResumeRules.isResumePending(secondsSincePlaying: 0, restoreCompleted: true))
    #expect(!ResumeRules.isResumePending(secondsSincePlaying: nil, restoreCompleted: true))
  }

  @Test("記録は4つの条件がすべて満たされたときだけ") func shouldRecord() {
    func record(
      position: Double = 1, stopped: Bool = false, pending: Bool = false, ended: Bool = false
    ) -> Bool {
      ResumeRules.shouldRecord(
        position: position, isClockStopped: stopped, isResumePending: pending, hasReachedEnd: ended)
    }
    #expect(record())
    #expect(!record(position: 0.99))
    #expect(!record(stopped: true))
    #expect(!record(pending: true))
    #expect(!record(ended: true))
  }
}
