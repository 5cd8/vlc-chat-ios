import Foundation
import Testing
@testable import VLCChatCore

private func chunks(_ bytes: [UInt8], size: Int) -> [[UInt8]] {
  stride(from: 0, to: bytes.count, by: max(1, size)).map { Array(bytes[$0..<min($0 + size, bytes.count)]) }
}

private func splitLines(_ text: String, size: Int) -> [String] {
  var splitter = LineSplitter()
  var lines: [String] = []
  for chunk in chunks(Array(text.utf8), size: size) {
    splitter.feed(chunk) { lines.append(String(decoding: $0, as: UTF8.self)) }
  }
  splitter.finish { lines.append(String(decoding: $0, as: UTF8.self)) }
  return lines
}

private struct SplitResult {
  var elements: [String] = []
  var outcome: JSONObjectSplitter.Outcome = .undetermined
}

private func splitObjects(_ bytes: [UInt8], size: Int) -> SplitResult {
  var splitter = JSONObjectSplitter()
  var result = SplitResult()
  for chunk in chunks(bytes, size: size) {
    let status = splitter.feed(chunk) { result.elements.append(String(decoding: $0, as: UTF8.self)) }
    if status == .finished { break }
  }
  result.outcome = splitter.outcome
  return result
}

private func splitObjects(_ text: String, size: Int) -> SplitResult {
  splitObjects(Array(text.utf8), size: size)
}

struct LineSplitterTests {
  @Test("チャンクの境界で結果が変わらない") func isIndependentOfChunkSize() {
    for size in [1, 2, 3, 100] {
      #expect(splitLines("a\nb\r\nc", size: size) == ["a", "b", "c"], "size=\(size)")
    }
  }

  @Test("末尾に改行の無い行はfinishで渡る") func emitsLastLineOnFinish() {
    #expect(splitLines("a\nb", size: 1) == ["a", "b"])
  }

  @Test("空行と空白だけの行は渡さない") func skipsBlankLines() {
    for size in [1, 4, 100] {
      #expect(splitLines("a\n\nb\n \t\nc\n", size: size) == ["a", "b", "c"], "size=\(size)")
    }
  }

  @Test("先頭のBOMは読み飛ばす") func skipsLeadingBOM() {
    var bytes: [UInt8] = [0xEF, 0xBB, 0xBF]
    bytes += Array("a\nb".utf8)
    for size in [1, 2, 100] {
      var splitter = LineSplitter()
      var lines: [String] = []
      for chunk in chunks(bytes, size: size) {
        splitter.feed(chunk) { lines.append(String(decoding: $0, as: UTF8.self)) }
      }
      splitter.finish { lines.append(String(decoding: $0, as: UTF8.self)) }
      #expect(lines == ["a", "b"], "size=\(size)")
    }
  }
}

struct JSONObjectSplitterTests {
  @Test("文字列中の括弧を深さに数えず、チャンクの境界で結果が変わらない") func splitsElementsIgnoringStringContents() {
    let json = #"{"x":1,"comments":[{"a":"}"},{"b":[1,2]}],"y":2}"#
    for size in [1, 5, 1000] {
      let result = splitObjects(json, size: size)
      #expect(result.elements == [#"{"a":"}"}"#, #"{"b":[1,2]}"#], "size=\(size)")
      #expect(result.outcome == .arrayFound)
    }
  }

  @Test("エスケープされた引用符は文字列を閉じない") func escapedQuoteDoesNotCloseString() {
    let json = #"{"comments":[{"a":"x\"}"}]}"#
    for size in [1, 3, 1000] {
      #expect(splitObjects(json, size: size).elements == [#"{"a":"x\"}"}"#], "size=\(size)")
    }
  }

  @Test("エスケープされたバックスラッシュの直後の引用符は文字列を閉じる") func escapedBackslashThenQuoteClosesString() {
    let json = #"{"comments":[{"a":"\\"},{"b":1}]}"#
    for size in [1, 2, 1000] {
      #expect(splitObjects(json, size: size).elements == [#"{"a":"\\"}"#, #"{"b":1}"#], "size=\(size)")
    }
  }

  @Test("commentsより前の大きな別プロパティは読み飛ばす") func skipsEarlierProperties() {
    let json = #"{"video":{"title":"[}","list":[1,{"c":2}]},"comments":[{"a":1}]}"#
    let result = splitObjects(json, size: 4)
    #expect(result.elements == [#"{"a":1}"#])
    #expect(result.outcome == .arrayFound)
  }

  @Test("配列が閉じた後のバイトは読まない") func stopsAfterArrayCloses() {
    var splitter = JSONObjectSplitter()
    var elements: [String] = []
    let first = splitter.feed(Array(#"{"comments":[{"a":1}]"#.utf8)) { elements.append(String(decoding: $0, as: UTF8.self)) }
    #expect(first == .finished)
    // 壊れた後続（要素に見えるもの）が来ても、渡さない。
    let second = splitter.feed(Array(#"{"b":2}"#.utf8)) { elements.append(String(decoding: $0, as: UTF8.self)) }
    #expect(second == .finished)
    #expect(elements == [#"{"a":1}"#])
  }

  @Test("オブジェクトでない要素は読み飛ばす") func skipsNonObjectElements() {
    let result = splitObjects(#"{"comments":[1,"a]",[2,{"z":3}],{"k":4}]}"#, size: 3)
    #expect(result.elements == [#"{"k":4}"#])
  }

  @Test("BOM付きでも読める") func readsWithBOM() {
    var bytes: [UInt8] = [0xEF, 0xBB, 0xBF]
    bytes += Array(#"{"comments":[{"a":1}]}"#.utf8)
    for size in [1, 2, 1000] {
      let result = splitObjects(bytes, size: size)
      #expect(result.elements == [#"{"a":1}"#], "size=\(size)")
      #expect(result.outcome == .arrayFound)
    }
  }

  @Test("途中で終わるファイルは、それまでの要素が有効") func keepsElementsBeforeTruncation() {
    let result = splitObjects(#"{"comments":[{"a":1},{"b""#, size: 3)
    #expect(result.elements == [#"{"a":1}"#])
    #expect(result.outcome == .arrayFound)
  }

  @Test("commentsに似たキーや値では配列に入らない") func ignoresLookalikeKeys() {
    let json = #"{"commentsX":[{"a":1}],"k":"comments","comments2":[{"b":2}]}"#
    let result = splitObjects(json, size: 5)
    #expect(result.elements.isEmpty)
    #expect(result.outcome == .commentsMissing)
  }

  @Test("キー・コロン・括弧の間に空白や改行があっても配列に入る") func readsPrettyPrintedJSON() {
    let json = "{
  \"comments\" :
  [
    {\"a\": 1},
    {\"b\": 2}
  ]
}"
    for size in [1, 4, 1000] {
      let result = splitObjects(json, size: size)
      #expect(result.elements == [#"{"a": 1}"#, #"{"b": 2}"#], "size=\(size)")
      #expect(result.outcome == .arrayFound)
    }
  }

  @Test("配列に入れない入力の結果") func reportsWhyArrayWasNotFound() {
    #expect(splitObjects("[1]", size: 1000).outcome == .rootNotObject)
    #expect(splitObjects(#"{"x":1}"#, size: 1000).outcome == .commentsMissing)
    #expect(splitObjects(#"{"comments":5}"#, size: 1000).outcome == .commentsNotArray)
    #expect(splitObjects("", size: 1000).outcome == .undetermined)
    #expect(splitObjects(#"{"x":1"#, size: 1000).outcome == .undetermined)
  }
}
