import Foundation

public enum ChatTextSegment: Equatable, Sendable {
  case text(String)
  case link(label: String, url: URL)
}

/// 本文中のURLをリンクにする。規則は PC版（`ChatBodyBehavior.cs`）と同じ。
///
/// `https?://\S+` の正規表現は使わず、手で探す。行の描画のたびに呼ばれ、呼ぶたびに `NSRegularExpression`
/// を作ると、再生中にメモリがじわじわ増えた（M2実機）。`static let` に1回だけ作る手もあるが、Swift 6 の
/// Package では並行性のエラーになり得て `nonisolated(unsafe)` が要るため、手で探すほうが単純だった。
public enum ChatLinks {
  /// 末尾から外す句読点。`)` を1文字ずつ外すだけの簡易な規則で、`a_(b)` の `)` も外れる（PC版と同じ）。
  private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", ")"]
  private static let prefixes = ["https://", "http://"]

  public static func segments(in text: String) -> [ChatTextSegment] {
    var result: [ChatTextSegment] = []
    var pending = ""
    var consumed = text.startIndex  // ここまでを処理済み
    var index = text.startIndex
    func flush() {
      if !pending.isEmpty {
        result.append(.text(pending))
        pending = ""
      }
    }
    while index < text.endIndex {
      let rest = text[index...]
      guard let prefix = prefixes.first(where: { rest.hasPrefix($0) }) else {
        index = text.index(after: index)
        continue
      }
      // `\S+`：空白でない文字が続く限り。`http://` の後ろに1文字も無ければ一致しない。
      var end = text.index(index, offsetBy: prefix.count)
      guard end < text.endIndex, !text[end].isWhitespace else {
        index = text.index(after: index)
        continue
      }
      while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
      var candidate = String(text[index..<end])
      while let last = candidate.last, trailingPunctuation.contains(last) {
        candidate.removeLast()
      }
      // リンクにならないときは、`consumed` を進めず、通常のテキストのまま残す。
      if !candidate.isEmpty, let url = URL(string: candidate), let host = url.host, !host.isEmpty {
        pending += text[consumed..<index]
        flush()
        result.append(.link(label: candidate, url: url))
        consumed = text.index(index, offsetBy: candidate.count)
      }
      index = end
    }
    pending += text[consumed...]
    flush()
    return result
  }
}
