import Foundation

/// TwitchDownloader形式の `comments[]` の1要素を `ChatMessage` にする。規則は PC版（`TwitchChatParser.cs`）と同じ。
public enum TwitchChatParser {
  /// サブスクライブ通知（"X subscribed with Prime." など）は通常のコメントと構造では区別できないので、
  /// 本文の文言で除く。PC版と同じ式なので、"I subscribed yesterday" のような通常の文も除かれる。
  private static func isSubscriptionNotice(_ body: String) -> Bool {
    body.range(of: #"^\S+\s+(?:subscribed|resubscribed|is gifting|gifted)\b"#, options: .regularExpression) != nil
  }

  public static func parse(comment: [String: Any]) -> ChatMessage? {
    // 秒は切り捨て。負・巨大・数値でないものは出さない（真偽値は数値ではない）。
    guard
      let offset = JSONValue.number(comment["content_offset_seconds"]),
      offset >= 0, offset < Double(Int32.max)
    else { return nil }
    let seconds = Int(offset)

    var author = ""
    if let commenter = comment["commenter"] as? [String: Any] {
      if let displayName = commenter["display_name"] as? String {
        author = displayName
      } else if let name = commenter["name"] as? String {
        author = name
      }
    }

    var role = ChatRole.normal
    var runs: [ChatRun] = []
    if let message = comment["message"] as? [String: Any] {
      let body = message["body"] as? String ?? ""
      if isSubscriptionNotice(body) { return nil }

      // "broadcaster" と "moderator" は完全一致（大文字小文字を区別する）。他のバッジは無装飾。
      for badge in message["user_badges"] as? [[String: Any]] ?? [] {
        guard let id = badge["_id"] as? String else { continue }
        if id == "broadcaster" {
          role = .owner
        } else if id == "moderator", role != .owner {
          role = .moderator
        }
      }

      if let fragments = message["fragments"] as? [[String: Any]] {
        for fragment in fragments {
          let text = fragment["text"] as? String
          if let emoticon = fragment["emoticon"] as? [String: Any],
            let id = emoticon["emoticon_id"] as? String, !id.isEmpty
          {
            // サードパーティのエモート（BTTV/FFZ/7TV）は `emoticon` が null の通常テキストで来るので対象外になる。
            runs.append(.emoji(url: "https://static-cdn.jtvnw.net/emoticons/v2/\(id)/default/dark/2.0", alt: text ?? ""))
          } else if let text, !text.isEmpty {
            runs.append(.text(text))
          }
        }
      } else if !body.isEmpty {
        // `fragments` が無い（または配列でない）ときは本文を使う。
        runs.append(.text(body))
      }
    }
    if runs.isEmpty { return nil }
    return ChatMessage(timeSeconds: seconds, author: author, role: role, runs: runs)
  }
}
