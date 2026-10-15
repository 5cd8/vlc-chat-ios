import Foundation
import Testing
@testable import VLCChatCore

struct ChatLinksTests {
  private func link(_ text: String) -> ChatTextSegment {
    .link(label: text, url: URL(string: text)!)
  }

  @Test("末尾の句読点はURLに含めない") func trimsTrailingPunctuation() {
    #expect(ChatLinks.segments(in: "見て https://example.com/a. すごい")
      == [.text("見て "), link("https://example.com/a"), .text(". すごい")])
  }

  @Test("末尾の句読点は複数でも外す") func trimsRepeatedPunctuation() {
    #expect(ChatLinks.segments(in: "https://example.com/x?!)") == [link("https://example.com/x"), .text("?!)")])
  }

  @Test("末尾の ) は対応する ( があっても外す（PC版と同じ簡易な規則）") func trimsClosingParenthesisLikeDesktop() {
    #expect(ChatLinks.segments(in: "(https://example.com/a_(b))")
      == [.text("("), link("https://example.com/a_(b"), .text("))")])
  }

  @Test("リンクにならないものはテキストのまま") func leavesNonLinksAsText() {
    for text in ["https://", "a https://. b", "http://:80", "ただの文"] {
      #expect(ChatLinks.segments(in: text) == [.text(text)], "\(text)")
    }
  }

  @Test("複数のURLは間のテキストを保つ") func splitsMultipleLinks() {
    #expect(ChatLinks.segments(in: "http://a.com https://b.org")
      == [link("http://a.com"), .text(" "), link("https://b.org")])
  }

  @Test("空文字は何も返さない") func emptyTextHasNoSegments() {
    #expect(ChatLinks.segments(in: "").isEmpty)
  }
}
