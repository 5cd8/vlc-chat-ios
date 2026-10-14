import Testing
@testable import VLCChatCore

struct SupportedVideoTests {
  @Test("4種の拡張子は大文字でも対応") func acceptsFourExtensionsCaseInsensitively() {
    for ext in ["mp4", "mov", "webm", "mkv", "MP4", "WebM", "MKV"] {
      #expect(SupportedVideo.isSupported(pathExtension: ext), "\(ext)")
    }
  }

  @Test("動画以外と空文字は非対応") func rejectsOthers() {
    for ext in ["avi", "json", ""] {
      #expect(!SupportedVideo.isSupported(pathExtension: ext), "\(ext)")
    }
  }

  @Test("タイトルは最後の拡張子だけを除く") func titleDropsOnlyLastExtension() {
    #expect(SupportedVideo.title(fromFileName: "a.mkv") == "a")
    #expect(SupportedVideo.title(fromFileName: "a.b.mkv") == "a.b")
    #expect(SupportedVideo.title(fromFileName: "noext") == "noext")
    #expect(SupportedVideo.title(fromFileName: "日本語の動画.mp4") == "日本語の動画")
  }
}
