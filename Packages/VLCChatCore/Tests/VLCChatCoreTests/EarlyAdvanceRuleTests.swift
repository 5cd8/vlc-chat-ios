import Testing
@testable import VLCChatCore

struct EarlyAdvanceRuleTests {
  @Test("残りが0.5秒以内になったら先行する（境界を含む）") func advancesWithinMargin() {
    #expect(!EarlyAdvanceRule.shouldAdvance(position: 99.4, duration: 100, rate: 1))  // 残り0.6
    #expect(EarlyAdvanceRule.shouldAdvance(position: 99.5, duration: 100, rate: 1))  // 残り0.5＝境界
    #expect(EarlyAdvanceRule.shouldAdvance(position: 99.9, duration: 100, rate: 1))
    #expect(EarlyAdvanceRule.shouldAdvance(position: 100, duration: 100, rate: 1))  // 時計が長さで切り詰めた
    #expect(!EarlyAdvanceRule.shouldAdvance(position: 100.1, duration: 100, rate: 1))  // 残りが負
  }

  @Test("速度が速いほど、メディアの秒では早く先行する") func scalesWithRate() {
    #expect(!EarlyAdvanceRule.shouldAdvance(position: 98.9, duration: 100, rate: 2))  // 残り1.1 > 1.0
    #expect(EarlyAdvanceRule.shouldAdvance(position: 99.0, duration: 100, rate: 2))  // 残り1.0＝境界
  }

  @Test("長さが不明、速度が0以下なら先行しない") func rejectsUnknownDurationOrRate() {
    #expect(!EarlyAdvanceRule.shouldAdvance(position: 5, duration: nil, rate: 1))
    #expect(!EarlyAdvanceRule.shouldAdvance(position: 5, duration: 0, rate: 1))
    #expect(!EarlyAdvanceRule.shouldAdvance(position: 99.9, duration: 100, rate: 0))
  }

  @Test("再生が始まって1秒未満は、残りが閾値の内側でも先行しない") func requiresMinimumPlayed() {
    #expect(!EarlyAdvanceRule.shouldAdvance(position: 0.8, duration: 1.2, rate: 1))  // 残り0.4
    #expect(EarlyAdvanceRule.shouldAdvance(position: 1.0, duration: 1.4, rate: 1))  // 残り0.4
  }
}
