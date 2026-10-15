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

struct PickedFileKindTests {
  @Test("拡張子で種類を決める（大文字小文字を区別しない）") func classifiesByExtension() {
    #expect(PickedFileKind.classify(pathExtension: "MP4") == .video)
    #expect(PickedFileKind.classify(pathExtension: "webm") == .video)
    #expect(PickedFileKind.classify(pathExtension: "JSON") == .chat)
    #expect(PickedFileKind.classify(pathExtension: "SQLite") == .emojiLibrary)
    for ext in ["txt", "db", ""] {
      #expect(PickedFileKind.classify(pathExtension: ext) == .unsupported, "\(ext)")
    }
  }
}

struct ChatByteSourceTests {
  @Test("FileByteSourceはDataByteSourceと同じチャンク列を返す") func fileSourceMatchesDataSource() throws {
    let data = Data((0..<23).map { UInt8($0) })
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-byte-source-\(UUID().uuidString).bin")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    var file = try FileByteSource(url: url, chunkSize: 5)
    var memory = DataByteSource(data, chunkSize: 5)
    var fileChunks: [[UInt8]] = []
    var memoryChunks: [[UInt8]] = []
    while let chunk = try file.nextChunk() { fileChunks.append(chunk) }
    while let chunk = try memory.nextChunk() { memoryChunks.append(chunk) }
    #expect(fileChunks == memoryChunks)
    #expect(fileChunks.map(\.count) == [5, 5, 5, 5, 3])
  }

  @Test("開けないファイルは投げる") func throwsForMissingFile() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
    #expect(throws: (any Error).self) { try FileByteSource(url: url) }
  }
}
