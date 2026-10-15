import Testing
@testable import VLCChatCore

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
