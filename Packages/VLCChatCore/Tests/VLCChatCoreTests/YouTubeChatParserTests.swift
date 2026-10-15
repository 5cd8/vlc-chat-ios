import Foundation
import Testing
@testable import VLCChatCore

/// 実データの形を写した合成の1行。投稿者名・本文は架空。
func youTubeLine(
  renderer: String = "liveChatTextMessageRenderer",
  timestamp: String = "12:34",
  author: String = "投稿者",
  badges: String = "[]",
  runs: String = #"[{"text":"hi"}]"#
) -> [String: Any] {
  let json = #"""
    {"replayChatItemAction":{"actions":[{"addChatItemAction":{"item":{"\#(renderer)":{
    "message":{"runs":\#(runs)},"authorName":{"simpleText":"\#(author)"},"authorBadges":\#(badges),
    "timestampText":{"simpleText":"\#(timestamp)"}}}}}]}}
    """#
  return jsonObject(json)
}

func jsonObject(_ json: String) -> [String: Any] {
  // 失敗はテストの入力の誤りなので、落として気づく。
  try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}

private func badge(icon: String? = nil, tooltip: String? = nil) -> String {
  var fields: [String] = []
  if let icon { fields.append(#""icon":{"iconType":"\#(icon)"}"#) }
  if let tooltip { fields.append(#""tooltip":"\#(tooltip)""#) }
  return #"{"liveChatAuthorBadgeRenderer":{\#(fields.joined(separator: ","))}}"#
}

struct YouTubeChatParserTests {
  @Test("時刻は MM:SS と H:MM:SS を秒にする") func parsesTimestamps() {
    #expect(YouTubeChatParser.parse(line: youTubeLine(timestamp: "12:34"))?.timeSeconds == 754)
    #expect(YouTubeChatParser.parse(line: youTubeLine(timestamp: "1:02:03"))?.timeSeconds == 3723)
  }

  @Test("読めない時刻とプレチャットは除く") func rejectsBadTimestamps() {
    for timestamp in ["-0:05", "12", "a:b", "1:2:3:4", "", "99999999:00"] {
      #expect(YouTubeChatParser.parse(line: youTubeLine(timestamp: timestamp)) == nil, "\(timestamp)")
    }
  }

  @Test("投稿者名と本文を取り出す") func parsesAuthorAndText() {
    let message = YouTubeChatParser.parse(line: youTubeLine(author: "太郎", runs: #"[{"text":"こんに"},{"text":"ちは"}]"#))
    #expect(message == ChatMessage(timeSeconds: 754, author: "太郎", role: .normal, runs: [.text("こんにちは")]))
  }

  @Test("スーパーチャットは本文があれば出し、無ければ除く") func paidMessageRequiresBody() {
    let withBody = youTubeLine(renderer: "liveChatPaidMessageRenderer", runs: #"[{"text":"応援"}]"#)
    let withoutBody = youTubeLine(renderer: "liveChatPaidMessageRenderer", runs: "[]")
    #expect(YouTubeChatParser.parse(line: withBody)?.runs == [.text("応援")])
    #expect(YouTubeChatParser.parse(line: withoutBody) == nil)
  }

  @Test("メンバー加入は本文が無ければ除く") func membershipRequiresBody() {
    #expect(YouTubeChatParser.parse(line: youTubeLine(renderer: "liveChatMembershipItemRenderer", runs: "[]")) == nil)
    let withBody = youTubeLine(renderer: "liveChatMembershipItemRenderer", runs: #"[{"text":"よろしく"}]"#)
    #expect(YouTubeChatParser.parse(line: withBody)?.runs == [.text("よろしく")])
  }

  @Test("通常のメッセージは本文が空でも残す") func textMessageWithoutRunsIsKept() {
    #expect(YouTubeChatParser.parse(line: youTubeLine(runs: "[]"))?.runs == [])
  }

  @Test("対象外のレンダラーと形の違う行は除く") func rejectsOtherRenderersAndShapes() {
    #expect(YouTubeChatParser.parse(line: youTubeLine(renderer: "liveChatTickerPaidMessageItemRenderer")) == nil)
    #expect(YouTubeChatParser.parse(line: youTubeLine(renderer: "liveChatPlaceholderItemRenderer")) == nil)
    #expect(YouTubeChatParser.parse(line: youTubeLine(renderer: "liveChatPaidStickerRenderer")) == nil)
    #expect(YouTubeChatParser.parse(line: jsonObject(#"{"other":1}"#)) == nil)
    #expect(YouTubeChatParser.parse(line: jsonObject(#"{"replayChatItemAction":{"actions":[]}}"#)) == nil)
  }

  @Test("バッジでオーナーとモデレーターを判定する") func detectsRolesFromBadges() {
    func role(_ badges: String) -> ChatRole? {
      YouTubeChatParser.parse(line: youTubeLine(badges: badges))?.role
    }
    #expect(role("[\(badge(icon: "OWNER", tooltip: "Owner"))]") == .owner)
    #expect(role("[\(badge(icon: "MODERATOR", tooltip: "Moderator"))]") == .moderator)
    #expect(role("[\(badge(tooltip: "owner"))]") == .owner)
    #expect(role("[\(badge(tooltip: "Moderator (x)"))]") == .moderator)
    #expect(role("[\(badge(icon: "VERIFIED", tooltip: "認証済み"))]") == .normal)
    #expect(role("[\(badge(tooltip: "メンバー（1 か月）"))]") == .normal)
    #expect(role("[\(badge(icon: "MODERATOR")),\(badge(icon: "OWNER"))]") == .owner)
    #expect(role("[]") == .normal)
  }

  @Test("画像の絵文字の前でテキストを確定する") func splitsTextAtEmoji() {
    let runs = #"""
      [{"text":"a"},{"text":"b"},
       {"emoji":{"emojiId":"x","isCustomEmoji":true,"shortcuts":[":_x:"],"image":{"thumbnails":[{"url":"https://e/1"}]}}},
       {"text":"c"}]
      """#
    #expect(YouTubeChatParser.parse(line: youTubeLine(runs: runs))?.runs
      == [.text("ab"), .emoji(url: "https://e/1", alt: ":_x:"), .text("c")])
  }

  @Test("絵文字のテキストは前後のテキストと結合しない") func emojiTextStaysSeparate() {
    let runs = #"[{"text":"a"},{"emoji":{"emojiId":"☺","isCustomEmoji":false}},{"text":"b"}]"#
    #expect(YouTubeChatParser.parse(line: youTubeLine(runs: runs))?.runs == [.text("a"), .text("☺"), .text("b")])
  }

  @Test("画像にもテキストにもならない絵文字でも、前後のテキストは別のrunになる") func emptyEmojiStillSplitsText() {
    let runs = #"[{"text":"a"},{"emoji":{}},{"text":"b"}]"#
    #expect(YouTubeChatParser.parse(line: youTubeLine(runs: runs))?.runs == [.text("a"), .text("b")])
  }

  @Test("カスタム絵文字の代替テキストはショートカット、次にラベル、絵文字ID") func customEmojiAltFallsBack() {
    func alt(_ emoji: String) -> ChatRun? {
      YouTubeChatParser.parse(line: youTubeLine(runs: "[{\"emoji\":\(emoji)}]"))?.runs.first
    }
    let image = #""image":{"thumbnails":[{"url":"https://e/1"}],"accessibility":{"accessibilityData":{"label":"ラベル"}}}"#
    #expect(alt(#"{"emojiId":"id","isCustomEmoji":true,"shortcuts":[":s:"],\#(image)}"#) == .emoji(url: "https://e/1", alt: ":s:"))
    #expect(alt(#"{"emojiId":"id","isCustomEmoji":true,\#(image)}"#) == .emoji(url: "https://e/1", alt: "ラベル"))
    #expect(alt(#"{"emojiId":"id","isCustomEmoji":true,"image":{"thumbnails":[{"url":"https://e/1"}]}}"#)
      == .emoji(url: "https://e/1", alt: "id"))
  }

  @Test("Unicode絵文字（isCustomEmojiが無い）は絵文字そのものが代替テキスト") func unicodeEmojiUsesEmojiIDAsAlt() {
    let emoji = #"{"emoji":{"emojiId":"☺","shortcuts":[":smile:"],"image":{"thumbnails":[{"url":"https://g/1"}]}}}"#
    #expect(YouTubeChatParser.parse(line: youTubeLine(runs: "[\(emoji)]"))?.runs == [.emoji(url: "https://g/1", alt: "☺")])
  }

  @Test("isCustomEmojiがfalseか、画像のURLが無い絵文字はテキストにする") func emojiWithoutImageBecomesText() {
    let withUrlButNotCustom = #"{"emoji":{"emojiId":"😀","isCustomEmoji":false,"image":{"thumbnails":[{"url":"https://g/1"}]}}}"#
    let withoutUrl = #"{"emoji":{"emojiId":"😁"}}"#
    #expect(YouTubeChatParser.parse(line: youTubeLine(runs: "[\(withUrlButNotCustom)]"))?.runs == [.text("😀")])
    #expect(YouTubeChatParser.parse(line: youTubeLine(runs: "[\(withoutUrl)]"))?.runs == [.text("😁")])
  }

  @Test("isCustomEmojiが真偽値でない値は、キーが無いのと同じ扱い") func nonBooleanCustomFlagIsTreatedAsAbsent() {
    // 数値の0は `as? Bool` では false になるが、PC版と同じく「無い」扱いなので、画像になる。
    let emoji = #"{"emoji":{"emojiId":"☺","isCustomEmoji":0,"image":{"thumbnails":[{"url":"https://g/1"}]}}}"#
    #expect(YouTubeChatParser.parse(line: youTubeLine(runs: "[\(emoji)]"))?.runs == [.emoji(url: "https://g/1", alt: "☺")])
  }
}
