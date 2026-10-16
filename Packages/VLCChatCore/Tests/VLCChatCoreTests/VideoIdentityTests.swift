import Foundation
import Testing
@testable import VLCChatCore

struct VideoIdentityTests {
  @Test("名前とサイズが同じなら等しく、サイズが違えば別の動画") func equalityUsesNameAndSize() {
    #expect(VideoIdentity(fileName: "a.mp4", size: 10) == VideoIdentity(fileName: "a.mp4", size: 10))
    #expect(VideoIdentity(fileName: "a.mp4", size: 10) != VideoIdentity(fileName: "a.mp4", size: 11))
    #expect(VideoIdentity(fileName: "a.mp4", size: 10) != VideoIdentity(fileName: "b.mp4", size: 10))
  }

  @Test("NFDの名前から作ってもNFCの並びになる") func initNormalizesToNFC() {
    let identity = VideoIdentity(fileName: "か\u{3099}.mp4", size: 1)
    #expect(Array(identity.fileName.unicodeScalars) == Array("が.mp4".unicodeScalars))
  }

  @Test("Codableの往復で等しく、NFDのJSONから読んでもNFCになる") func codableRoundTripNormalizes() throws {
    let original = VideoIdentity(fileName: "日本語.mkv", size: 123)
    let decoded = try JSONDecoder().decode(VideoIdentity.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)

    let json = "{\"fileName\":\"か\u{3099}.mp4\",\"size\":5}"
    let fromNFD = try JSONDecoder().decode(VideoIdentity.self, from: Data(json.utf8))
    #expect(Array(fromNFD.fileName.unicodeScalars) == Array("が.mp4".unicodeScalars))
  }
}
