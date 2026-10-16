import Testing
@testable import VLCChatCore

struct SelectionPlannerTests {
  @Test("動画は自然順に並び、チャットは対応づく") func ordersVideosAndPairsChats() {
    let plan = SelectionPlanner.plan(
      fileNames: ["b2.mp4", "B10.mp4", "b1.mp4", "b2.live_chat.json", "b1_chat.json", "B10.chat_replay.json"])
    #expect(plan.videos == [2, 0, 1])
    #expect(plan.pairs == [4, 3, 5])
    #expect(plan.ignoredChats == [])
    #expect(plan.soleChatIndex == nil)
  }

  @Test("動画が無いときは自然順で先頭のチャットだけを使う") func picksFirstChatWhenNoVideo() {
    let plan = SelectionPlanner.plan(fileNames: ["z.json", "a.json"])
    #expect(plan.videos == [])
    #expect(plan.soleChatIndex == 1)
    #expect(plan.ignoredChats == [0])
  }

  @Test("動画1本・チャット1本は名前によらず組になる") func singlePair() {
    let plan = SelectionPlanner.plan(fileNames: ["a.mp4", "zzz.json"])
    #expect(plan.videos == [0])
    #expect(plan.pairs == [1])
    #expect(plan.ignoredChats == [])
  }

  @Test("絵文字ライブラリは最初の1つ") func picksFirstEmojiLibrary() {
    let plan = SelectionPlanner.plan(fileNames: ["e1.sqlite", "e2.sqlite"])
    #expect(plan.emojiLibrary == 0)
    #expect(plan.videos == [])
    #expect(plan.soleChatIndex == nil)
  }

  @Test("非対応の形式は入力順に集める") func collectsUnsupported() {
    let plan = SelectionPlanner.plan(fileNames: ["x.txt", "a.mp4"])
    #expect(plan.unsupported == [0])
    #expect(plan.videos == [1])
    #expect(plan.pairs == [nil])
  }

  @Test("空の選択") func emptySelection() {
    let plan = SelectionPlanner.plan(fileNames: [])
    #expect(plan.videos == [])
    #expect(plan.pairs == [])
    #expect(plan.ignoredChats == [])
    #expect(plan.unsupported == [])
    #expect(plan.soleChatIndex == nil)
    #expect(plan.emojiLibrary == nil)
  }

  @Test("動画2本・チャット1本で一致しなければチャットは無視する") func ignoresUnmatchedChat() {
    let plan = SelectionPlanner.plan(fileNames: ["a.mp4", "b.mp4", "c.json"])
    #expect(plan.pairs == [nil, nil])
    #expect(plan.ignoredChats == [2])
  }

  @Test("拡張子は大文字でも判定し、拡張子なしは非対応") func classifiesExtensionsCaseInsensitively() {
    let plan = SelectionPlanner.plan(fileNames: ["A.MP4", "README", "B.JSON"])
    #expect(plan.videos == [0])
    #expect(plan.unsupported == [1])
    #expect(plan.pairs == [2])
  }
}
