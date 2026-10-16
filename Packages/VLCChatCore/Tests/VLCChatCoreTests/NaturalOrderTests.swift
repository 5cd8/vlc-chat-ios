import Testing
@testable import VLCChatCore

struct NaturalOrderTests {
  @Test("数字は数値として、大文字小文字を区別せずに並ぶ") func ordersNumbersNumerically() {
    #expect(NaturalOrder.sorted(["Part10.mp4", "part2.mp4", "Part1.mp4"]) == ["Part1.mp4", "part2.mp4", "Part10.mp4"])
  }

  @Test("大文字小文字だけが違う名前は、入力の並びによらず同じ順") func breaksCaseTiesDeterministically() {
    #expect(NaturalOrder.sorted(["a.mp4", "A.mp4"]) == ["A.mp4", "a.mp4"])
    #expect(NaturalOrder.sorted(["A.mp4", "a.mp4"]) == ["A.mp4", "a.mp4"])
  }

  @Test("日本語を含む名前でも数字は数値として並ぶ") func ordersJapaneseNames() {
    #expect(NaturalOrder.sorted(["第10話.mkv", "第2話.mkv", "第1話.mkv"]) == ["第1話.mkv", "第2話.mkv", "第10話.mkv"])
  }

  @Test("空と1件はそのまま") func keepsTrivialInputs() {
    #expect(NaturalOrder.sorted([]) == [])
    #expect(NaturalOrder.sorted(["x.mp4"]) == ["x.mp4"])
  }
}
