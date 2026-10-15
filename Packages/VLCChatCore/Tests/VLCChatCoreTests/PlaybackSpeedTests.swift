import Testing
@testable import VLCChatCore

struct PlaybackSpeedTests {
  @Test("7段階の表示") func labelsEachStep() {
    let labels = PlaybackSpeed.steps.map(PlaybackSpeed.label)
    #expect(labels == ["0.5x", "0.75x", "1x", "1.25x", "1.5x", "1.75x", "2x"])
  }

  @Test("7段階以外も同じ規則で整形する") func labelsOtherValues() {
    #expect(PlaybackSpeed.label(3.0) == "3x")
    #expect(PlaybackSpeed.label(1.1) == "1.1x")
  }

  @Test("stepsは7要素で昇順、1.0を含む") func stepsAreSortedAndContainNormal() {
    #expect(PlaybackSpeed.steps.count == 7)
    #expect(PlaybackSpeed.steps == PlaybackSpeed.steps.sorted())
    #expect(PlaybackSpeed.steps.contains(PlaybackSpeed.normal))
  }
}
