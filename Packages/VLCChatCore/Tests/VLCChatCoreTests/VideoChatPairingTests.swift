import Testing
@testable import VLCChatCore

struct VideoChatPairingTests {
  @Test("チャット名から拡張子と接尾辞を1つだけ除く") func stripsExtensionAndOneSuffix() {
    let cases: [(String, String)] = [
      ("X.live_chat.json", "X"),
      ("X.chat_replay.json", "X"),
      ("2884500475_chat.json", "2884500475"),
      ("X.JSON", "X"),
      ("X.LIVE_CHAT.json", "X"),
      ("X.live_chat.live_chat.json", "X.live_chat"),
      ("live_chat.json", "live"),
      ("x.livechat.json", "x.livechat"),
      ("_chat.json", "_chat"),
      ("プレイ.json", "プレイ"),
    ]
    for (input, expected) in cases {
      #expect(VideoChatPairing.chatBaseName(ofFileName: input) == expected, "\(input)")
    }
  }

  @Test("実データの名前が自動で対応づく") func pairsRealWorldNames() {
    let result = VideoChatPairing.pair(
      videoFileNames: ["Clementia IS.mkv", "あぺっくす おれはよわい.mp4", "2884500475.mp4"],
      chatFileNames: ["2884500475_chat.json", "Clementia IS.live_chat.json", "あぺっくす おれはよわい.chat_replay.json"])
    #expect(result.chatIndexForVideo == [1, 2, 0])
    #expect(result.unmatchedChats == [])
  }

  @Test("対応づかないチャットは未対応に残る") func reportsUnmatchedChats() {
    let result = VideoChatPairing.pair(
      videoFileNames: ["A.mp4", "B.mp4"],
      chatFileNames: ["B.chat_replay.json", "A_chat.json", "C.live_chat.json"])
    #expect(result.chatIndexForVideo == [1, 0])
    #expect(result.unmatchedChats == [2])
  }

  @Test("動画1本・チャット1本は名前によらず対応づく") func pairsSingleVideoWithSingleChat() {
    let result = VideoChatPairing.pair(videoFileNames: ["A.mp4"], chatFileNames: ["zzz.json"])
    #expect(result.chatIndexForVideo == [0])
    #expect(result.unmatchedChats == [])
  }

  @Test("動画1本・チャット2本は名前が一致するものだけ") func singleVideoWithTwoChats() {
    let none = VideoChatPairing.pair(videoFileNames: ["A.mp4"], chatFileNames: ["x.json", "y.json"])
    #expect(none.chatIndexForVideo == [nil])
    #expect(none.unmatchedChats == [0, 1])
    let one = VideoChatPairing.pair(videoFileNames: ["A.mp4"], chatFileNames: ["x.json", "A.live_chat.json"])
    #expect(one.chatIndexForVideo == [1])
    #expect(one.unmatchedChats == [0])
  }

  @Test("動画2本・チャット1本で名前が一致しなければ対応づけない") func twoVideosWithUnrelatedChat() {
    let result = VideoChatPairing.pair(videoFileNames: ["A.mp4", "B.mp4"], chatFileNames: ["zzz.json"])
    #expect(result.chatIndexForVideo == [nil, nil])
    #expect(result.unmatchedChats == [0])
  }

  @Test("同じ名前が複数あれば、渡された順の最初だけを使う") func duplicateNamesUseFirstOnly() {
    let chats = VideoChatPairing.pair(
      videoFileNames: ["A.mp4", "B.mp4"], chatFileNames: ["A.json", "A.live_chat.json"])
    #expect(chats.chatIndexForVideo == [0, nil])
    #expect(chats.unmatchedChats == [1])
    let videos = VideoChatPairing.pair(videoFileNames: ["A.mp4", "A.mkv"], chatFileNames: ["A.json"])
    #expect(videos.chatIndexForVideo == [0, nil])
  }

  @Test("NFDの名前でも対応づく") func normalizesUnicode() {
    let nfd = "か\u{3099}き\u{3099}.live_chat.json"
    let result = VideoChatPairing.pair(
      videoFileNames: ["がぎ.mp4", "other.mp4"], chatFileNames: [nfd])
    #expect(result.chatIndexForVideo == [0, nil])
  }

  @Test("動画0本ならチャットはすべて未対応") func noVideos() {
    let result = VideoChatPairing.pair(videoFileNames: [], chatFileNames: ["a.json", "b.json"])
    #expect(result.chatIndexForVideo == [])
    #expect(result.unmatchedChats == [0, 1])
  }

  @Test("名前の比較は大文字小文字を区別する") func comparesNamesCaseSensitively() {
    let result = VideoChatPairing.pair(
      videoFileNames: ["a.mp4", "b.mp4"], chatFileNames: ["A.live_chat.json", "B.live_chat.json"])
    #expect(result.chatIndexForVideo == [nil, nil])
  }

  @Test("接尾辞なしの名前も一致する") func pairsWithoutSuffix() {
    let result = VideoChatPairing.pair(videoFileNames: ["A.mp4", "B.mp4"], chatFileNames: ["B.json", "A.json"])
    #expect(result.chatIndexForVideo == [1, 0])
  }

  @Test("拡張子だけを除いた名前の一致が、接尾辞を除いた一致に先立つ") func plainNameMatchWinsFirst() {
    let first = VideoChatPairing.pair(videoFileNames: ["X.mp4", "X_chat.mp4"], chatFileNames: ["X_chat.json"])
    #expect(first.chatIndexForVideo == [nil, 0])
    let second = VideoChatPairing.pair(
      videoFileNames: ["X_chat.mp4", "Y.mp4"], chatFileNames: ["X_chat.json", "Y_chat.json"])
    #expect(second.chatIndexForVideo == [0, 1])
  }
}
