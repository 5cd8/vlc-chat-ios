import Foundation

public enum ChatTextSegment: Equatable, Sendable {
  case text(String)
  case link(label: String, url: URL)
}

/// 本文中のURLをリンクにする。規則は PC版（`ChatBodyBehavior.cs`）と同じ。
public enum ChatLinks {
  /// 末尾から外す句読点。`)` を1文字ずつ外すだけの簡易な規則で、`a_(b)` の `)` も外れる（PC版と同じ）。
  private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", ")"]

  public static func segments(in text: String) -> [ChatTextSegment] {
    guard let regex = try? NSRegularExpression(pattern: #"https?://\S+"#) else { return text.isEmpty ? [] : [.text(text)] }
    let nsText = text as NSString
    var result: [ChatTextSegment] = []
    var pending = ""
    var consumed = 0  // ここまでを処理済み（UTF-16の位置）
    func flush() {
      if !pending.isEmpty {
        result.append(.text(pending))
        pending = ""
      }
    }
    for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
      var candidate = nsText.substring(with: match.range)
      while let last = candidate.last, trailingPunctuation.contains(last) {
        candidate.removeLast()
      }
      // リンクにならないときは、`consumed` を進めず、通常のテキストのまま残す。
      guard !candidate.isEmpty, let url = URL(string: candidate), let host = url.host, !host.isEmpty else { continue }
      pending += nsText.substring(with: NSRange(location: consumed, length: match.range.location - consumed))
      flush()
      result.append(.link(label: candidate, url: url))
      consumed = match.range.location + (candidate as NSString).length
    }
    pending += nsText.substring(from: consumed)
    flush()
    return result
  }
}
