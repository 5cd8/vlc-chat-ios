import Foundation

/// YouTubeのライブチャットのリプレイ（1行1JSON）の、1行ぶんを `ChatMessage` にする。
/// 規則は PC版（`ChatParser.cs`）と同じ。対象外の行・壊れた行は `nil`。
public enum YouTubeChatParser {
  /// 時・分・秒の各値の上限。壊れた入力で掛け算があふれて落ちないようにする。
  private static let componentLimit = 100_000

  public static func parse(line: [String: Any]) -> ChatMessage? {
    guard
      let action = line["replayChatItemAction"] as? [String: Any],
      let actions = action["actions"] as? [[String: Any]],
      let first = actions.first,
      let add = first["addChatItemAction"] as? [String: Any],
      let item = add["item"] as? [String: Any]
    else { return nil }

    // 対象は通常のメッセージ・スーパーチャット・メンバー加入だけ。ティッカー・プレースホルダー・
    // ステッカー・配信終了などは対象外。スーパーチャットとメンバー加入は、本文が無ければ出さない。
    let renderer: [String: Any]
    let bodyRequired: Bool
    if let value = item["liveChatTextMessageRenderer"] as? [String: Any] {
      renderer = value
      bodyRequired = false
    } else if let value = item["liveChatPaidMessageRenderer"] as? [String: Any] {
      renderer = value
      bodyRequired = true
    } else if let value = item["liveChatMembershipItemRenderer"] as? [String: Any] {
      renderer = value
      bodyRequired = true
    } else {
      return nil
    }

    guard
      let timestamp = (renderer["timestampText"] as? [String: Any])?["simpleText"] as? String,
      // 配信開始前のチャット（"-0:05"）は出さない。
      !timestamp.contains("-"),
      let seconds = parseTimestamp(timestamp)
    else { return nil }

    let author = (renderer["authorName"] as? [String: Any])?["simpleText"] as? String ?? ""
    let role = badgeRole(of: renderer["authorBadges"] as? [[String: Any]] ?? [])
    let runs = parseRuns((renderer["message"] as? [String: Any])?["runs"] as? [[String: Any]] ?? [])
    if bodyRequired && runs.isEmpty { return nil }
    return ChatMessage(timeSeconds: seconds, author: author, role: role, runs: runs)
  }

  /// `H:MM:SS` または `MM:SS`。読めなければ `nil`。
  static func parseTimestamp(_ timestamp: String) -> Int? {
    let parts = timestamp.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2 || parts.count == 3 else { return nil }
    var values: [Int] = []
    for part in parts {
      guard let value = Int(part), (0..<componentLimit).contains(value) else { return nil }
      values.append(value)
    }
    return values.count == 2
      ? values[0] * 60 + values[1]
      : values[0] * 3600 + values[1] * 60 + values[2]
  }

  /// バッジの `icon.iconType`（OWNER／MODERATOR）か、`tooltip` の文言で判定する。
  /// メンバーや認証のバッジは無装飾。オーナーが優先。
  private static func badgeRole(of badges: [[String: Any]]) -> ChatRole {
    var isOwner = false
    var isModerator = false
    for badge in badges {
      guard let renderer = badge["liveChatAuthorBadgeRenderer"] as? [String: Any] else { continue }
      let iconType = (renderer["icon"] as? [String: Any])?["iconType"] as? String
      let tooltip = renderer["tooltip"] as? String
      // 大文字小文字を区別しない比較。Foundation の `range(of:options:)` は呼ぶたびに NSString を作るので使わない。
      let icon = iconType?.lowercased()
      let tip = tooltip?.lowercased()
      if icon == "owner" || tip?.contains("owner") == true {
        isOwner = true
      } else if icon == "moderator" || tip?.contains("moderator") == true {
        isModerator = true
      }
    }
    return isOwner ? .owner : (isModerator ? .moderator : .normal)
  }

  private static func parseRuns(_ rawRuns: [[String: Any]]) -> [ChatRun] {
    var result: [ChatRun] = []
    var pending = ""
    func flush() {
      if !pending.isEmpty {
        result.append(.text(pending))
        pending = ""
      }
    }
    for run in rawRuns {
      if let text = run["text"] as? String {
        pending += text
      } else if let emoji = run["emoji"] as? [String: Any] {
        // 絵文字の前で、それまでのテキストを確定する。
        flush()
        append(emoji: emoji, to: &result)
      }
      // 上のどちらでもないrunは読み飛ばす。
    }
    flush()
    return result
  }

  private static func append(emoji: [String: Any], to result: inout [ChatRun]) {
    let image = emoji["image"] as? [String: Any]
    let thumbnails = image?["thumbnails"] as? [[String: Any]]
    let url = thumbnails?.first?["url"] as? String
    let emojiID = emoji["emojiId"] as? String
    // `isCustomEmoji` が無いとき（Unicode絵文字）は、画像があれば画像にする。`false` と明記されたら画像にしない。
    let isCustom = JSONValue.bool(emoji["isCustomEmoji"])
    if let url, !url.isEmpty, isCustom != false {
      let shortcut = (emoji["shortcuts"] as? [String])?.first
      let accessibility = (image?["accessibility"] as? [String: Any])?["accessibilityData"] as? [String: Any]
      let label = accessibility?["label"] as? String
      // 代替テキスト：カスタム絵文字はショートカット（`:_x:`）を優先。Unicode絵文字は絵文字そのもの。
      let candidates = isCustom == true ? [shortcut, label, emojiID] : [emojiID, label, shortcut]
      let alt = candidates.compactMap { $0 }.first { !$0.isEmpty } ?? ""
      result.append(.emoji(url: url, alt: alt))
    } else if let emojiID, !emojiID.isEmpty {
      // 前後のテキストと結合しない独立したrun（結合すると、直前のURLが絵文字まで取り込む）。
      result.append(.text(emojiID))
    }
  }
}
