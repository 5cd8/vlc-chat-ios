import Foundation
import Testing
@testable import VLCChatCore

/// 実データの形を写した合成の1要素。投稿者名・本文は架空。
private func twitchComment(
  offset: String = "12",
  commenter: String = #"{"display_name":"表示名","name":"login"}"#,
  badges: String = "[]",
  body: String = "hello",
  fragments: String? = nil
) -> [String: Any] {
  let fragmentsField = fragments.map { #","fragments":\#($0)"# } ?? ""
  return jsonObject(
    #"""
    {"content_offset_seconds":\#(offset),"commenter":\#(commenter),
    "message":{"body":"\#(body)","user_badges":\#(badges)\#(fragmentsField)}}
    """#)
}

struct TwitchChatParserTests {
  @Test("秒は切り捨てる") func truncatesOffset() {
    #expect(TwitchChatParser.parse(comment: twitchComment(offset: "12.9"))?.timeSeconds == 12)
    #expect(TwitchChatParser.parse(comment: twitchComment(offset: "0"))?.timeSeconds == 0)
  }

  @Test("負・巨大・数値でない時刻は除く") func rejectsBadOffsets() {
    for offset in ["-1", "-0.5", "1e30", "\"5\"", "true", "null"] {
      #expect(TwitchChatParser.parse(comment: twitchComment(offset: offset)) == nil, "\(offset)")
    }
    #expect(TwitchChatParser.parse(comment: jsonObject(#"{"message":{"body":"x"}}"#)) == nil)
  }

  @Test("投稿者名はdisplay_name、無ければname") func authorFallsBackToName() {
    #expect(TwitchChatParser.parse(comment: twitchComment())?.author == "表示名")
    #expect(TwitchChatParser.parse(comment: twitchComment(commenter: #"{"name":"login"}"#))?.author == "login")
    #expect(TwitchChatParser.parse(comment: twitchComment(commenter: "{}"))?.author == "")
  }

  @Test("バッジはbroadcasterとmoderatorだけを完全一致で判定する") func detectsRoles() {
    func role(_ id: String) -> ChatRole? {
      TwitchChatParser.parse(comment: twitchComment(badges: #"[{"_id":"\#(id)","version":"1"}]"#))?.role
    }
    #expect(role("broadcaster") == .owner)
    #expect(role("moderator") == .moderator)
    #expect(role("subscriber") == .normal)
    #expect(role("vip") == .normal)
    #expect(role("Moderator") == .normal)
    let both = twitchComment(badges: #"[{"_id":"moderator"},{"_id":"broadcaster"}]"#)
    #expect(TwitchChatParser.parse(comment: both)?.role == .owner)
  }

  @Test("エモートは画像のURLと、名前の代替テキストにする") func parsesEmoticonFragments() {
    let fragments = #"""
      [{"text":"hi ","emoticon":null},
       {"text":"Kappa","emoticon":{"emoticon_id":"25"}},
       {"text":" bye","emoticon":null}]
      """#
    let message = TwitchChatParser.parse(comment: twitchComment(fragments: fragments))
    #expect(message?.runs == [
      .text("hi "),
      .emoji(url: "https://static-cdn.jtvnw.net/emoticons/v2/25/default/dark/2.0", alt: "Kappa"),
      .text(" bye"),
    ])
  }

  @Test("emoticon_idが空のfragmentはテキスト、空のテキストは除く") func emptyEmoticonIDFallsBackToText() {
    let fragments = #"[{"text":"a","emoticon":{"emoticon_id":""}},{"text":""}]"#
    #expect(TwitchChatParser.parse(comment: twitchComment(fragments: fragments))?.runs == [.text("a")])
  }

  @Test("fragmentsが無いか配列でなければ本文を使う") func fallsBackToBody() {
    #expect(TwitchChatParser.parse(comment: twitchComment(body: "plain"))?.runs == [.text("plain")])
    #expect(TwitchChatParser.parse(comment: twitchComment(body: "plain", fragments: "5"))?.runs == [.text("plain")])
  }

  @Test("サブスク通知は除く") func rejectsSubscriptionNotices() {
    for body in [
      "zakipan12 subscribed with Prime. They've subscribed for 13 months! ",
      "a resubscribed at Tier 1.",
      "a is gifting 5 Tier 1 Subs",
      "a gifted a sub",
    ] {
      #expect(TwitchChatParser.parse(comment: twitchComment(body: body)) == nil, "\(body)")
    }
  }

  @Test("通常の文は除かない（先頭が1語＋空白＋subscribedでないもの）") func keepsOrdinaryText() {
    #expect(TwitchChatParser.parse(comment: twitchComment(body: "subscribed to the channel")) != nil)
    #expect(TwitchChatParser.parse(comment: twitchComment(body: "gifted subs are nice")) != nil)
  }

  @Test("PC版と同じく、先頭が1語＋subscribedの通常の文も除かれる") func matchesDesktopBehaviorForFalsePositive() {
    // 通知と通常のコメントは構造で区別できず、PC版も同じ式で除く。挙動を揃えるための確認。
    #expect(TwitchChatParser.parse(comment: twitchComment(body: "I subscribed yesterday")) == nil)
  }

  @Test("本文が空のコメントは除く") func rejectsEmptyBody() {
    #expect(TwitchChatParser.parse(comment: twitchComment(body: "")) == nil)
  }
}
