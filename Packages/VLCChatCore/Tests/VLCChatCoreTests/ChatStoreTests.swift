import Testing
@testable import VLCChatCore

struct ChatStoreTests {
  private func message(_ time: Int, _ body: String, author: String = "a") -> ChatMessage {
    ChatMessage(timeSeconds: time, author: author, role: .normal, runs: [.text(body)])
  }

  private func makeStore(_ messages: [ChatMessage]) -> ChatStore {
    var builder = ChatStoreBuilder()
    for message in messages {
      builder.append(
        timeSeconds: message.timeSeconds, author: message.author, role: message.role, runs: message.runs)
    }
    return builder.finish()
  }

  private func texts(_ store: ChatStore) -> [String] {
    (0..<store.count).map { position in
      if case .text(let text) = store.message(at: position).runs.first { return text }
      return "?"
    }
  }

  @Test("追加した内容がそのまま復元できる") func roundTripsMessages() {
    let original = [
      ChatMessage(timeSeconds: 1, author: "投稿者A", role: .owner, runs: [.text("こんにちは🙂"), .emoji(url: "https://e/1", alt: ":x:")]),
      ChatMessage(timeSeconds: 2, author: "投稿者A", role: .moderator, runs: []),
      ChatMessage(timeSeconds: 3, author: "b", role: .normal, runs: [.emoji(url: "https://e/1", alt: ""), .text("終")]),
    ]
    let store = makeStore(original)
    #expect(store.count == 3)
    for (position, expected) in original.enumerated() {
      #expect(store.message(at: position) == expected)
    }
  }

  @Test("追加順がすでに昇順なら並べ替えの表を持たない") func keepsIdentityOrderWhenAscending() {
    let store = makeStore([message(1, "A"), message(3, "B"), message(3, "C"), message(7, "D")])
    #expect(store.usesIdentityOrder)
    #expect(texts(store) == ["A", "B", "C", "D"])
  }

  @Test("非昇順の入力は時刻で並び、同じ時刻は追加順を保つ") func sortsStably() {
    let store = makeStore([message(5, "A"), message(1, "B"), message(5, "C"), message(1, "D")])
    #expect(!store.usesIdentityOrder)
    #expect(texts(store) == ["B", "D", "A", "C"])
    #expect((0..<4).map { store.timeSeconds(at: $0) } == [1, 1, 5, 5])
  }

  @Test("endIndexは時刻が秒以下の件数") func endIndexCountsMessagesAtOrBeforeSeconds() {
    let store = makeStore([message(1, "A"), message(3, "B"), message(3, "C"), message(7, "D")])
    let expected: [(Int, Int)] = [(0, 0), (1, 1), (2, 1), (3, 3), (6, 3), (7, 4), (100, 4)]
    for (seconds, end) in expected {
      #expect(store.endIndex(atSeconds: seconds) == end, "seconds=\(seconds)")
    }
  }

  @Test("空のストアのendIndexは常に0") func emptyStoreHasNoMessages() {
    let store = makeStore([])
    #expect(store.count == 0)
    #expect(store.endIndex(atSeconds: 100) == 0)
    #expect(store.window(endIndex: 5) == 0..<0)
  }

  @Test("windowは末尾200件で、countに丸める") func windowIsLast200AndClamped() {
    let store = makeStore((0..<450).map { message($0, "m\($0)") })
    let expected: [(Int, Range<Int>)] = [
      (900, 250..<450), (450, 250..<450), (100, 0..<100), (0, 0..<0), (200, 0..<200), (201, 1..<201), (-5, 0..<0),
    ]
    for (end, range) in expected {
      #expect(store.window(endIndex: end) == range, "end=\(end)")
    }
  }

  @Test("同じ文字列は1つにまとめる") func deduplicatesStrings() {
    var builder = ChatStoreBuilder()
    for time in 0..<1000 {
      builder.append(timeSeconds: time, author: "同じ人", role: .normal, runs: [.emoji(url: "https://e/1", alt: ":x:")])
    }
    let store = builder.finish()
    #expect(store.count == 1000)
    #expect(store.uniqueStringCount == 3)
  }

  @Test("Int32に収まらない時刻は追加されない") func dropsOutOfRangeTime() {
    var builder = ChatStoreBuilder()
    builder.append(timeSeconds: Int(Int32.max) + 1, author: "a", role: .normal, runs: [.text("x")])
    builder.append(timeSeconds: Int(Int32.max), author: "a", role: .normal, runs: [.text("y")])
    #expect(builder.count == 1)
    #expect(builder.finish().count == 1)
  }
}
