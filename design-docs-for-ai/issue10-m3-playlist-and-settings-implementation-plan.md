# Issue #10 M3（プレイリストと設定） 実装計画

対象Issue: https://github.com/5cd8/vlc-chat-ios/issues/10 （アシスタントが起票したIssue。要件の正式な情報源はIssue本文であり、本計画は要約・言い換えをしない。**「ユーザーが確定した事項」9件と「既定」「受け入れ条件」を、そのまま実装の根拠にする**。親Issue: https://github.com/5cd8/vlc-chat-ios/issues/1 ）
前提: M1（Issue #3、PR #5）とM2（Issue #6、PR #7。`main` の `1bd9da7`）が `main` に入っていること。
スコープ: M3のみ（フォルダ指定の追加、プレイリストの複数保存、シャッフル・リピート、チャット解析結果の保存、再生位置の記憶の手動削除、iCloud同期は含まない。#8・#9は別Issue）
依頼プロンプト: `user-prompt/202610161700_issue10_m3.md`（git管理しない）
作業ブランチ: `feature/issue-10-m3-playlist-and-settings`（`origin/main` から切る）

本書は、本セッションの文脈を持たない別のAIがそのまま実装に使うことを想定している。

## 0. 前提・読み替え

- **ビルドも実行もできない開発環境：** 開発機はWindowsで、Mac・Xcode・シミュレーター・`swift` コマンドは無い。**コンパイルとテストの確認はGitHub Actions（`macos-26`）だけ、実行の確認はユーザーのiPhone 16（iOS 26.6.2）の実機だけ**。pushしてCIのログ（`gh run view <id> --log-failed`、警告は成果物の `xcodebuild.log`）を読んで直す、を回す前提で進める。M2では、文字列リテラルの誤りなどをCIで見つけて直した。
- **読み替え（00 項目30）：** 「ブラウザ確認」「実行ファイルのフォルダを開く」は、**iPhone実機**に読み替える。ユーザーに実機確認を頼むときは、署名なしipaの入手先（GitHub Releasesのタグのページ）と、使うファイルを依頼文に書く。インストールは、PCのiloader v2.3.7の「Import IPA」で行う。タグ `m3-<n>` を切るのは、ユーザーの指示があってから。
- **M1・M2の土台（`main` にある）：** `App/`（`AppModel`・`Player/{PlayerModel,RemoteControlController,AudioSessionController,ScopedFile}`・`Chat/{ChatModel,EmojiLibrary,EmojiStore}`・`Views/{PlayerScreen,ControlsView,ChatPanelView,ChatRowView,DiagnosticsView}`・`Diagnostics/*`）と `Packages/VLCChatCore`（`PlaybackClock`・`NowPlayingState`・`SupportedVideo`・`PickedFileKind`・`ChatStore` ほか）。M3は、これに足す。
- 設計判断の理由は、コードのコメントとPR本文にその場で直接書く。**`docs/adr/` はgit管理しないので参照しない。この計画書もマージ前に削除されるので、コードのコメントやREADMEから参照しない。**
- コメントの方針：コードにHow、テストにWhat、コミットログにWhy、コードコメントにWhy not（`code-comments`・`code-naming` スキルに従う）。
- **ファイルの書き方の注意（M2で踏んだ）：** Python/シェルの文字列で、バックスラッシュや改行を含むSwiftのコードを書き換えると、`\n` が実際の改行になって「unterminated string literal」になる。書き込みは `Write`／`Edit` ツールで行い、書いた後にCIで確かめる。

## 1. スコープ・非ゴール・受け入れ条件との対応

Issue #10 の「範囲」（親Issue #1 の機能要件 2（前へ・次へ）・6・7・8、9（シート）と、ロック画面の前へ・次へ）を満たす。**非ゴール**は、Issue #10 の「非ゴール」のとおり。

| Issue #10 の受け入れ条件 | 確かめる手段 |
|---|---|
| 1 動画を複数選ぶとプレイリストになり、自然順に並び、先頭から再生される | 自然順・選択の振り分けの単体テスト＋実機（チェックA） |
| 2 再起動をまたいで残り、動画とチャットが再び開ける | 保存・復元の単体テスト＋実機（チェックC） |
| 3 動画とチャットが自動（規則6）と手動で対応づく。実データの名前が自動で対応づく | 対応づけの単体テスト（実データの名前）＋実機（チェックB） |
| 4 置き換え・追記・削除・並べ替え。再生中の項目の削除、並べ替えで現在位置が動画を指し続ける | プレイリストの状態遷移の単体テスト＋実機（チェックD） |
| 5 自動進行、「前へ」「次へ」が画面・ロック画面・コントロールセンターで同じ規則 | 単体テスト（次へ・前への規則）＋実機（チェックE） |
| 6 無効な項目は警告表示、自動進行・次へ・前へは飛ばして通知 | 単体テスト（飛ばす規則）＋実機（チェックF） |
| 7 再生位置が記憶され、続きから再生される（終わりの30秒以内は先頭から。最後まで再生した動画は消える） | 記憶の規則の単体テスト＋実機（チェックG） |
| 8 設定（自動進行、絵文字の入れ替え、ライセンス表示） | 実機（チェックH） |
| 9 M1・M2の機能が壊れていない | 実機（チェックI） |

## 2. 確認済みの一次情報

| 事実 | 出典 |
|---|---|
| **PC版のプレイリスト規則**（置き換え／追記／削除で現在位置の扱い／並べ替えで現在位置が追従／先頭・末尾で移動できない）。PC版は再起動をまたいで残さず、対応づけも持たない | `C:\Users\owner\source\repos\vlc-chat\Services\PlaylistService.cs`（`ReplaceWith`・`Append`・`RemoveAt`・`Reorder`・`TryMoveToNext/Previous`）、`Models/PlaylistItem.cs` |
| **ユーザーの確定事項**（チャットは毎回読み直す、無効な項目は飛ばす、前へは常に前の項目、記憶の同一判定＝名前＋サイズ、iOS標準のリスト、接尾辞を除く対応づけ、絵文字の取り込みは2経路、自然順、起動直後は復元のみ） | Issue #10 の「ユーザーが確定した事項」1〜9 |
| **実データのファイル名**（動画↔チャット）：`Clementia IS.mkv`↔`Clementia IS.live_chat.json`、`あぺっくす おれはよわい.mp4`↔`あぺっくす おれはよわい.chat_replay.json`、`2884500475.mp4`↔`2884500475_chat.json`。`E:\tube\surge\` に実物がある（動画とチャットが組になっているのは、Clementia IS・ゴールデンレトリバー・MARVEL・GTA5・遊戯王ほか） | `E:\tube\surge\` の一覧 |
| **再生が最後まで行ったことの検出**：SwiftVLCは `PlayerEvent.endReached` を、libVLCが「正常な終端」と判定したときだけ合成する（`stopped` への遷移の直後。明示的な `stop()` や動画の差し替えでは出ない）。`Player.didReachEnd` も同じ。現在 `PlayerModel` のイベントの絞り込み（`startObserving()`）は `.timeChanged`・`.lengthChanged`・`.voutChanged`・`.encounteredError` だけを通している | SwiftVLC v1.1.0-beta.14 の `Sources/SwiftVLC/Player/PlayerEvent.swift`・`PlaybackEndCoordinator.swift`（リポジトリの SwiftPM チェックアウト）。`App/Player/PlayerModel.swift` の `startObserving()` |
| **開始位置の指定**：`Media.addOption(":start-time=30")` は、タイムラインを切り詰める（長さから最初の30秒が除かれ、以後のシークがそのオフセットからの相対になる）ので**使わない**。ドキュメントは「オプション無しで読み込み、シークできるようになってから絶対位置へシークする」と書いている | SwiftVLC の `Media.addOption` のドキュメント |
| **M1のコード（`main`）**：`App/Player/PlayerModel.swift`（`open(url:)` 66行・`openCount`・`openError`・`displayPosition(at:)`・`isClockStopped`・`startObserving()`・`handle(_:)`・`stateDidChange(_:)`・`updateRemote()`）、`App/Player/RemoteControlController.swift`（`Handlers`・`update(_:)`・`setPlaybackCommands(enabled:)`・`install(handlers:)` が `nextTrackCommand`・`previousTrackCommand` を無効にしている）、`App/Player/ScopedFile.swift`（セキュリティスコープの start/stop 対。`fileSizeBytes`）、`Packages/VLCChatCore/.../NowPlayingState.swift` | リポジトリ |
| **M2のコード（`main`）**：`App/AppModel.swift`（`handlePicked(urls:)`・`notices`・`alertMessage`・`dismissAlert()`）、`App/Chat/ChatModel.swift`（`load(url:)`・`reset()`）、`App/Chat/EmojiStore.swift`（`importLibrary(from:)`・`hasLibrary`・`libraryCount`）、`App/Views/PlayerScreen.swift`（`.fileImporter`・`.alert`）、`App/Views/ControlsView.swift`（操作パネル） | リポジトリ |
| **ライセンス**：LGPL-2.1の全文は `licenses/LGPL-2.1.txt`（Releaseには載るが、アプリには同梱されていない）。SwiftVLC（MIT、Copyright (c) 2025 Omar Albeik）。libVLCのソースの入手先は、Releaseのノート（`.github/workflows/build-ipa.yml` の `NOTES`）に書いてある文言 | `licenses/`、`.github/workflows/build-ipa.yml`、SwiftVLC の `LICENSE` |

**Apple／Foundationの未確認の一次情報**（Appleの公式文書のページは取得できなかった。以下は実装者の知識で、**型名・挙動はCIのコンパイルと実機で確かめる**）：`URL.bookmarkData(options:includingResourceValuesForKeys:relativeTo:)`、`URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)`、`String.compare(_:options:)` の `.numeric`／`.caseInsensitive`、`precomposedStringWithCanonicalMapping`、`Array` の `move(fromOffsets:toOffset:)`（SwiftUI。Coreでは使わず手で書く）、`List` の `onMove`／`onDelete`／`EditButton`、`UserDefaults`、`MPRemoteCommandCenter.nextTrackCommand`／`previousTrackCommand`、XcodeGenの `sources` の `buildPhase: resources`。

## 3. 未確認事項（M3の実機で必ず確かめる。計画の前提にしない）

| ID | 未確認事項 | 確かめ方 | 外れたとき |
|---|---|---|---|
| U1 | ファイルピッカーで選んだURLから作ったブックマークが、アプリを終了して起動し直した後（できれば再インストール後）も解決でき、`startAccessingSecurityScopedResource()` で開けるか。対象：アプリ内 `Documents`（ファイル共有で入れたもの）・iCloud Drive・外部ストレージ | チェックC | iOSでは `bookmarkData` に `.withSecurityScope` が無い。`.minimalBookmark` を試す。それでも解決できない場所があれば、その場所の項目は無効扱いになる。ユーザーに報告して相談 |
| U2 | 再生が始まってから（`.playing`、長さ確定、`seekableChanged` が真）の絶対位置へのシークで、復元できるか。再生が始まってから跳ぶので、最初の一瞬だけ0秒付近が表示されないか（表示・チャット・ロック画面） | チェックG | 6.2節のとおり、`timeChanged` で最大5秒まで再試行する。それでも駄目な形式は、復元できない形式として報告 |
| U3 | `endReached` が、MP4・MOV・WebM・MKVの実ファイルで、最後まで再生したときに出るか（出ないと、自動進行と「最後まで再生した動画の記憶を消す」が動かない） | チェックE・G（短い動画を最後まで再生する） | `stopped` への遷移＋「位置が長さの近く」で代替判定する案を報告して相談 |
| U4 | ロック画面・コントロールセンター・PiPの窓の「前へ」「次へ」（`previousTrackCommand`／`nextTrackCommand`）が表示され、押せるか。再生速度・シークの表示、10秒送り・戻し（`skipForward`／`skipBackward`）と両立するか | チェックE | iOSは `skipForward`／`skipBackward` が有効だと、前へ・次への枠にスキップを出すことが多い。**両立しなければ10秒送り・戻しを優先する（ユーザー確定）。報告だけ** |
| U5 | シート内で `.fileImporter` が開けるか（プレイリストの「追加」・項目のチャット割り当て・設定の絵文字入れ替え）。SwiftUIでは、1つのビューに複数の `.fileImporter` を付けると、最後のものしか効かない既知の落とし穴がある | チェックD・H | 1つの ピッカーの置き場所を変える（6.4節の規則が前提。シート内で出ない場合は、シートを閉じてから `PlayerScreen` のピッカーを開く） |
| U6 | `List` の編集モード（並べ替え）・左スワイプ削除・行内のボタン（チャット割り当て）が、シートの中で期待どおりに動くか。行内のボタンと行全体のタップの競合 | チェックD | ボタンのスタイルを `.borderless` にする（6.4節に最初から採用）。それでも競合すれば、行の末尾のメニュー（`Menu`）に替える |
| U7 | 自然順（`.numeric`＋`.caseInsensitive`）が、日本語を含む名前で期待どおりに並ぶか | チェックA | 比較を `localizedStandardCompare` に替える（ロケール依存になるので、まず報告） |
| U8 | iCloud Drive上で、まだ端末にダウンロードされていないファイルを項目にしたとき、解決できるが開けない（読めない）。無効扱いと区別できるか | チェックF | 無効扱いのままにする（区別しない）。ユーザーに報告 |
| U9 | 数十項目のプレイリストで、保存・復元・シートの表示が遅くならないか | チェックD | 保存を間引く（0.5秒のデバウンス） |
| U10 | 署名なしipaをSideStoreが取り込めるか（Issue #1 の未確認事項。SideStoreのAppleログインが直っていれば） | M3の完了時に、ユーザーが試す | 直っていなければ保留のまま（M3の完了条件ではない） |

## 4. ファイル構成

```
vlc-chat-ios/
  App/
    AppModel.swift                       # 変更。playlist・resume・settings を束ね、選択の振り分け・項目の再生・自動進行
    Player/PlayerModel.swift             # 変更。endReached・再生位置の復元と記録・動画の識別・停止
    Player/RemoteControlController.swift # 変更。前へ・次へを有効にする
    Playlist/
      PlaylistModel.swift                # 新規。プレイリストの状態・保存・ブックマークの作成と解決・有効性の確認
      ResumeModel.swift                  # 新規。再生位置の記憶の保存
      SettingsModel.swift                # 新規。設定（自動進行）
    Views/
      PlayerScreen.swift                 # 変更。シートの表示、起動直後の2ボタン
      ControlsView.swift                 # 変更。前へ・次へ・プレイリスト・設定のボタン
      PlaylistView.swift                 # 新規。プレイリストのシート
      SettingsView.swift                 # 新規。設定のシート
      LicensesView.swift                 # 新規。ライセンス表示
  licenses/
    LGPL-2.1.txt                         # 既存
    SwiftVLC-MIT.txt                     # 新規。SwiftVLCのLICENSE全文（MIT）
  Packages/VLCChatCore/
    Sources/VLCChatCore/
      NaturalOrder.swift                 # 新規。ファイル名の自然順
      VideoChatPairing.swift             # 新規。チャット名の接尾辞と、動画とチャットの対応づけ
      SelectionPlanner.swift             # 新規。「ファイルを選択」の結果の振り分け（種類・自然順・対応づけ）
      PlaylistEntry.swift                # 新規。プレイリスト項目（Codable）
      Playlist.swift                     # 新規。プレイリストの状態遷移
      PlaylistFile.swift                 # 新規。保存形式と読み書き
      VideoIdentity.swift                # 新規。「同じ動画」の判定（名前＋サイズ）
      ResumeRules.swift                  # 新規。再生位置の記憶の規則（復元位置・記録の可否・復元待ち）
      ResumeStore.swift                  # 新規。再生位置の記憶の保存
      SettingsStore.swift                # 新規。設定のUserDefaults
    Tests/VLCChatCoreTests/
      NaturalOrderTests.swift  VideoChatPairingTests.swift  SelectionPlannerTests.swift
      PlaylistTests.swift  PlaylistFileTests.swift  VideoIdentityTests.swift
      ResumeRulesTests.swift  ResumeStoreTests.swift  SettingsStoreTests.swift   # すべて新規
  project.yml                            # 変更。licenses をアプリのリソースに入れる
  README.md                              # 状態の記述を更新
  CONTEXT.md                             # 変更。「対応づけ」の定義を確定事項6（接尾辞を除く）に合わせる。用語「プレイリスト項目」にコードの型名 `PlaylistEntry` を併記する理由（Swiftの `Entry` 慣習。PC版は `PlaylistItem`）を一言添える
```

`Packages/VLCChatCore` は `SwiftVLC` に依存させない（M1・M2と同じ）。保存・ブックマーク・UIKit・SwiftUIに依存する部分は `App/` に置く。Packageは `Foundation` だけを使い、`MediaPlayer`・`SwiftUI` は使わない。

## 5. 設計：ロジックのPackage（`VLCChatCore`）

### 5.1 `NaturalOrder`（確定事項8）

```swift
public enum NaturalOrder {
  /// 数字を数値として、大文字小文字を区別せずに比べる（Part2 < Part10）。
  public static func areInIncreasingOrder(_ lhs: String, _ rhs: String) -> Bool
  public static func sorted(_ names: [String]) -> [String]
}
```
`lhs.compare(rhs, options: [.numeric, .caseInsensitive])` が `.orderedAscending` なら真。`.orderedSame`（大文字小文字だけが違う）のときは、`lhs < rhs`（Swiftの標準の比較。Unicodeスカラー順）で決め、順序を毎回同じにする。

テスト（`NaturalOrderTests.swift`。手計算の期待値）：
1. `["Part10.mp4", "part2.mp4", "Part1.mp4"]` → `["Part1.mp4", "part2.mp4", "Part10.mp4"]`。
2. 大文字小文字だけが違う `["a.mp4", "A.mp4"]` → `["A.mp4", "a.mp4"]`（`"A" < "a"`）。入力の並びを逆にしても同じ結果。
3. 日本語：`["第10話.mkv", "第2話.mkv", "第1話.mkv"]` → `["第1話.mkv", "第2話.mkv", "第10話.mkv"]`。
4. 空の配列・1件の配列はそのまま。

### 5.2 `VideoChatPairing`（確定事項6と、Issue #10 の「既定」）

```swift
public enum VideoChatPairing {
  public static let chatSuffixes = [".live_chat", ".chat_replay", "_chat"]
  /// チャットのファイル名から、拡張子 `.json` と、末尾の定型の接尾辞を1つ除いた名前。
  public static func chatBaseName(ofFileName fileName: String) -> String
  public struct PairingResult: Equatable, Sendable {   // `Swift.Result` を隠さないための名前
    /// 動画の添字 → チャットの添字（無ければ nil）。`videoFileNames` と同じ長さ
    public let chatIndexForVideo: [Int?]
    /// どの動画にも対応づかなかったチャットの添字（昇順）
    public let unmatchedChats: [Int]
  }
  public static func pair(videoFileNames: [String], chatFileNames: [String]) -> PairingResult
}
```
規則：
- **名前の比較は、NFC（`precomposedStringWithCanonicalMapping`）にそろえてから行う**。大文字小文字は区別する。（Swiftの `String` の `==` は正準等価で比べるので、そろえなくても等しいが、保存するファイル名の形を一定にするために、そろえる。）
- `chatBaseName`：まず拡張子 `.json`（大文字小文字を区別しない）を除く。次に `chatSuffixes` の**順に**調べ、末尾が（`lowercased()` で比べて）一致した最初の接尾辞を**1つだけ**除く。除いた結果が空なら、除く前の名前を返す。
- 動画の名前は、拡張子（最後の1つ）を除いたもの（`SupportedVideo.title(fromFileName:)`）。チャットの「拡張子だけを除いた名前」は、`.json` を除いたもの。
- **動画が1本でチャットが1本だけ**のときは、名前によらず対応づける（M2の挙動を保つ。Issue #10 の「既定」）。
- それ以外は**2段**で対応づける。(1)動画を渡された順に見て、まだ使われていないチャットのうち、「拡張子だけを除いた名前」が動画の名前と一致する最初のもの（渡された順）を対応づける。(2)(1)で対応づかなかった動画を渡された順に見て、まだ使われていないチャットのうち `chatBaseName` が動画の名前と一致する最初のものを対応づける。1つのチャットは1本の動画にしか使わない。（1段だと、動画 `X.mp4`・`X_chat.mp4` とチャット `X_chat.json` で、`X.mp4` が先に取ってしまう。）
- 対応づかなかったチャットは `unmatchedChats` に入れる（昇順）。

テスト（`VideoChatPairingTests.swift`）：
1. `chatBaseName`：`"X.live_chat.json"`→`"X"`、`"X.chat_replay.json"`→`"X"`、`"2884500475_chat.json"`→`"2884500475"`、`"X.JSON"`→`"X"`、`"X.LIVE_CHAT.json"`→`"X"`、`"X.live_chat.live_chat.json"`→`"X.live_chat"`（1つだけ）、`"live_chat.json"`→`"live"`（`_chat` で終わるので除く。手計算の結果）、`"x.livechat.json"`→`"x.livechat"`（どの接尾辞でも終わらない）、`"_chat.json"`→`"_chat"`（除くと空になるので除かない）、`"プレイ.json"`→`"プレイ"`。
2. 実データの名前：動画 `["Clementia IS.mkv", "あぺっくす おれはよわい.mp4", "2884500475.mp4"]`、チャット `["2884500475_chat.json", "Clementia IS.live_chat.json", "あぺっくす おれはよわい.chat_replay.json"]` → `chatIndexForVideo == [1, 2, 0]`、`unmatchedChats == []`。
3. 対応づかないチャット：動画 `["A.mp4", "B.mp4"]`、チャット `["B.chat_replay.json", "A_chat.json", "C.live_chat.json"]` → `chatIndexForVideo == [1, 0]`、`unmatchedChats == [2]`。
4. 動画1本・チャット1本は名前によらず対応づく：`["A.mp4"]`・`["zzz.json"]` → `[0]`、`unmatchedChats == []`。
5. 動画1本・チャット2本で名前が一致するものが無い → `[nil]`、`unmatchedChats == [0, 1]`。動画1本・チャット2本で片方が一致 → 一致した方が対応づき、もう片方が未対応。
6. 動画2本・チャット1本で名前が一致しない → `[nil, nil]`、`unmatchedChats == [0]`（「1本ずつ」の規則は、動画が1本のときだけ）。
7. 同じ名前のチャットが2本 → 渡された順の最初だけが使われ、2本目は未対応。同じ名前の動画（`A.mp4`・`A.mkv`）が2本・チャット `A.json` → 最初の動画だけがチャットを得る。
8. NFDの名前でも対応づく（正規化そのものの担保は5.4のテスト）：動画 `"がぎ.mp4"`（NFC）、チャット `"がぎ.live_chat.json"`（濁点を分解したNFD）→ 対応づく。入力は `"か\u{3099}き\u{3099}"` のように明示的に作る。
9. 動画0本 → `chatIndexForVideo == []`、チャットはすべて未対応。
10. 接尾辞なしの一致（動画が複数）：動画 `["A.mp4", "B.mp4"]`・チャット `["B.json", "A.json"]` → `[1, 0]`。
11. 2段の優先：動画 `["X.mp4", "X_chat.mp4"]`・チャット `["X_chat.json"]` → `[nil, 0]`（(1)で `X_chat.mp4` が取る。`X.mp4` は(2)で取れない）。動画 `["X_chat.mp4", "Y.mp4"]`・チャット `["X_chat.json", "Y_chat.json"]` → `[0, 1]`。

### 5.3 `SelectionPlanner`（「ファイルを選択」「追加」の振り分け）

```swift
public struct SelectionPlan: Equatable, Sendable {
  /// 動画の入力添字（名前の自然順）
  public let videos: [Int]
  /// `videos` と同じ並びの、対応づいたチャットの入力添字（無ければ nil）
  public let pairs: [Int?]
  /// 動画に対応づかず無視するチャットの入力添字（名前の自然順）
  public let ignoredChats: [Int]
  /// 動画が1本も無いとき、チャットが1つ以上あれば、名前の自然順で先頭のチャットの入力添字
  public let soleChatIndex: Int?
  public let unsupported: [Int]      // 入力順
  public let emojiLibrary: Int?      // 最初の1つ
}
public enum SelectionPlanner {
  public static func plan(fileNames: [String]) -> SelectionPlan
}
```
`PickedFileKind.classify(pathExtension:)`（拡張子は、最後の `.` 以降。無ければ空）で分類し、動画・チャットをそれぞれ `NaturalOrder` で並べ、`VideoChatPairing.pair` を使う。動画が1本も無いときは、先頭のチャットを `soleChatIndex`、残りを `ignoredChats` に入れる（動画があるときの `ignoredChats` は `unmatchedChats`）。`AppModel` は、この結果でURLを引くだけにする。

テスト（`SelectionPlannerTests.swift`。添字は入力の位置。手計算）：
1. `["b2.mp4", "B10.mp4", "b1.mp4", "b2.live_chat.json", "b1_chat.json", "B10.chat_replay.json"]` → `videos == [2, 0, 1]`（b1 < b2 < B10）、`pairs == [4, 3, 5]`、`ignoredChats == []`、`soleChatIndex == nil`。
2. `["z.json", "a.json"]` → `videos == []`、`soleChatIndex == 1`、`ignoredChats == [0]`。
3. `["a.mp4", "zzz.json"]` → `videos == [0]`、`pairs == [1]`、`ignoredChats == []`。
4. `["e1.sqlite", "e2.sqlite"]` → `emojiLibrary == 0`、動画・チャット無し。
5. `["x.txt", "a.mp4"]` → `unsupported == [0]`、`videos == [1]`、`pairs == [nil]`。
6. `[]` → すべて空・nil。
7. `["a.mp4", "b.mp4", "c.json"]` → `pairs == [nil, nil]`、`ignoredChats == [2]`。

### 5.4 `VideoIdentity`（確定事項4）

```swift
public struct VideoIdentity: Hashable, Codable, Sendable {
  public let fileName: String        // 拡張子込み。NFC
  public let size: Int64
  public init(fileName: String, size: Int64)   // fileName を NFC にする
  public init(from decoder: Decoder) throws    // 手で書き、同じく NFC にそろえる（自動生成は init を通らない）
}
```
テスト（`VideoIdentityTests.swift`）：同じ名前・同じサイズは等しい。名前が同じでサイズが違うと異なる。**NFD の名前から作ると `fileName.unicodeScalars` が NFC の並びになる**（正規化の処理を消すと失敗する）。`Codable` の往復で等しく、NFD のJSONから読んでも NFC になる。

### 5.5 `PlaylistEntry` と `Playlist`

```swift
public struct PlaylistEntry: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  /// 拡張子込みの動画のファイル名（一覧の表示名。記憶の識別は、開いたURLから作る）
  public var videoFileName: String
  public var videoBookmark: Data
  public var chatFileName: String?
  public var chatBookmark: Data?
  public init(id: UUID = UUID(), videoFileName: String, videoBookmark: Data,
              chatFileName: String? = nil, chatBookmark: Data? = nil)
  /// 拡張子を除いた名前（PC版の `DisplayName` と同じ）
  public var title: String { get }
}

public struct Playlist: Equatable, Sendable {
  public private(set) var entries: [PlaylistEntry]
  public private(set) var currentID: UUID?
  public init(entries: [PlaylistEntry] = [], currentID: UUID? = nil)
  public var currentIndex: Int? { get }
  public var current: PlaylistEntry? { get }
  public var hasPrevious: Bool { get }   // currentIndex > 0
  public var hasNext: Bool { get }       // currentIndex + 1 < count

  public mutating func replace(with newEntries: [PlaylistEntry])           // 現在＝先頭（空なら nil）
  public mutating func append(_ newEntries: [PlaylistEntry])               // 現在は変えない
  public enum Removal: Equatable, Sendable { case notCurrent, current }
  public mutating func remove(at index: Int) -> Removal                    // 現在を消したら、同じ添字の項目が現在（末尾だったら nil）
  public mutating func move(fromOffsets: IndexSet, toOffset: Int)          // SwiftUIの onMove と同じ意味。現在は同じ項目を指し続ける
  public mutating func setCurrent(id: UUID?)                               // entries に無い id は無視する（現在を変えない）
  public mutating func updateEntry(id: UUID, _ change: (inout PlaylistEntry) -> Void)
  public struct Step: Equatable, Sendable { public let target: Int?; public let skipped: [Int] }
  public func nextStep(isPlayable: (PlaylistEntry) -> Bool) -> Step
  public func previousStep(isPlayable: (PlaylistEntry) -> Bool) -> Step
  /// 現在の項目そのものから探し始める（現在の項目が有効ならそれが target）。現在の項目を削除した直後に使う
  public func stepFromCurrent(isPlayable: (PlaylistEntry) -> Bool) -> Step
}
```
- **現在の項目は添字ではなく `id` で持つ**。並べ替えや削除で添字がずれても、同じ項目を指し続ける。`currentIndex` は `entries` から引く。
- `remove(at:)`：`index` が範囲外なら何もせず `.notCurrent`。現在の項目を消したときは、消した後の同じ添字の項目（元の「次」）を現在にし、無ければ `currentID = nil`。`.current` を返す。現在が nil のときは常に `.notCurrent`。
- `move(fromOffsets:toOffset:)`：動かす項目を昇順に取り出し、残りの並びの `toOffset - (toOffset より前にある動かす項目の数)` の位置に挿入する（`Array.move(fromOffsets:toOffset:)` と同じ結果）。範囲外の添字は無視する。
- `nextStep`：現在の次から末尾へ向かって、`isPlayable` が真の最初の項目を `target` にし、通り過ぎた（飛ばした）添字を `skipped` に入れる。現在が無い、または有効な項目が無ければ `target = nil`（`skipped` は調べた無効な添字のすべて）。`previousStep` は逆向き。`stepFromCurrent` は、現在の添字から末尾へ向かう（現在が nil なら `target = nil`、`skipped = []`）。
- `isPlayable` は、App側がブックマークの解決で行う。Coreは判定の方法を知らない。

テスト（`PlaylistTests.swift`。**特記なき限り、各ケースは項目 `a, b, c, d, e`・現在 `c`（添字2）から始める**。手計算）：
1. `replace`：新しい `[x, y]` → 現在 `x`。空の配列で置き換えると現在 nil。
2. `append`：`[f]` を追記 → 末尾が `f`、現在は `c` のまま。現在が nil のときに追記しても nil のまま。
3. `remove(at: 0)` → `.notCurrent`、`entries == [b, c, d, e]`、現在 `c`（添字1）。`remove(at: 3)`（`d`）→ `.notCurrent`、現在 `c`。
4. `remove(at: 2)`（現在）→ `.current`、`entries == [a, b, d, e]`、現在 `d`（添字2＝元の次）。
5. `[a, b, c]`・現在 `c` で `remove(at: 2)` → `.current`、現在 nil。現在が nil のときの `remove(at:)` は `.notCurrent`。
6. 範囲外の `remove(at: 9)` → 何も変わらず `.notCurrent`。
7. `move(fromOffsets: [0], toOffset: 3)` → `[b, c, a, d, e]`、現在 `c`（添字1）。`move(fromOffsets: [4], toOffset: 0)` → `[e, a, b, c, d]`、現在 `c`（添字3）。`move(fromOffsets: [1, 3], toOffset: 5)` → `[a, c, e, b, d]`。`move(fromOffsets: [2], toOffset: 2)` → 変わらない。`move(fromOffsets: [2], toOffset: 0)`（現在そのものを動かす）→ `[c, a, b, d, e]`、現在 `c`（添字0）。
8. `nextStep`（`d` を偽、他は真）→ `target == 4`、`skipped == [3]`。`d`・`e` を偽 → `target == nil`、`skipped == [3, 4]`。現在が末尾なら `target == nil`、`skipped == []`。
9. `previousStep`（`b` を偽、他は真）→ `target == 0`、`skipped == [1]`。現在が先頭なら `target == nil`、`skipped == []`。現在が nil なら両方 `target == nil`。
10. `stepFromCurrent`（現在 `c` が有効）→ `target == 2`、`skipped == []`。`c` を偽、他は真 → `target == 3`、`skipped == [2]`。`c`・`d`・`e` を偽 → `target == nil`、`skipped == [2, 3, 4]`。
11. `hasPrevious`・`hasNext`：先頭で `hasPrevious == false`、末尾で `hasNext == false`、現在 nil で両方偽、1件だけなら両方偽。
12. `updateEntry`：チャットの割り当てを更新しても、並びと現在は変わらない。存在しない `id` は何もしない。
13. `stepFromCurrent` で現在が nil → `target == nil`、`skipped == []`。`move` に範囲外の添字（`[9]`）・`toOffset > count`（`[0]` を `toOffset: 9`）→ 範囲外の添字は無視、`toOffset` は末尾に丸める（`[b,c,d,e,a]`）。`PlaylistEntry.title`：`"a.b.mp4"` → `"a.b"`。
14. `setCurrent`：存在する `id` で現在が変わる。存在しない `id` は無視（現在は変わらない）。`nil` で現在が nil。

### 5.6 `PlaylistFile`（保存形式）

```swift
public struct PlaylistSnapshot: Codable, Equatable, Sendable {
  public static let currentVersion = 1
  public var version: Int
  public var entries: [PlaylistEntry]
  public var currentID: UUID?
}
public enum PlaylistFile {
  public enum LoadError: Error, Equatable { case unreadable }
  /// ファイルが無ければ nil。読めない（壊れている・版が新しい）ときは `unreadable` を投げる。
  public static func load(from url: URL) throws -> Playlist?
  public static func save(_ playlist: Playlist, to url: URL) throws   // atomic に書く
}
```
`JSONEncoder` の既定（`Data` は Base64）。`version` が `currentVersion` より大きいときは `unreadable`。`currentID` が `entries` に無ければ、読み込み時に nil にする。

テスト（`PlaylistFileTests.swift`）：
1. 保存→読み戻しで、`entries`（`chatBookmark` が nil の項目と有る項目・日本語の名前）と `currentID` が等しい。
2. ファイルが無ければ `load` は nil。
3. 壊れたJSON（`"{"`）、版が2のJSON → `unreadable`。
4. `currentID` が `entries` に無いJSON → 読み込むと `currentID == nil`。
5. 上書き保存（2回）で、2回目の内容になる。

### 5.7 `ResumeRules` と `ResumeStore`（再生位置の記憶。確定事項4と、Issue #10 の「既定」）

```swift
public enum ResumeRules {
  public static let endMargin: TimeInterval = 30        // 終わりからこの秒数以内まで見ていたら、先頭から再生する
  public static let minimumPosition: TimeInterval = 1   // これ未満の位置は、記録も復元もしない
  public static let pendingTimeout: TimeInterval = 5    // 再生開始からこの秒数を過ぎたら、復元待ちでも記録を始める
  /// 復元する位置。nil なら先頭から再生する。
  public static func startPosition(saved: TimeInterval?, duration: TimeInterval?) -> TimeInterval?
  /// 復元待ちか。`secondsSincePlaying` は最初の `.playing` からの秒数（まだ再生していなければ nil）
  public static func isResumePending(secondsSincePlaying: TimeInterval?, restoreCompleted: Bool) -> Bool
  /// 記録してよいか
  public static func shouldRecord(position: TimeInterval, isClockStopped: Bool, isResumePending: Bool, hasReachedEnd: Bool) -> Bool
}
public struct ResumeStore: Codable, Equatable, Sendable {
  public init()
  public mutating func set(_ position: TimeInterval, for identity: VideoIdentity, at date: Date)
  public func position(for identity: VideoIdentity) -> TimeInterval?
  public mutating func remove(_ identity: VideoIdentity)
  public var count: Int { get }
  public static func load(from url: URL) throws -> ResumeStore?    // 無ければ nil、壊れていれば throws
  public func save(to url: URL) throws
}
```
- `startPosition`：`saved` が nil、または `saved < minimumPosition` → nil。`duration` が nil または 0 以下 → nil（長さ不明では復元しない。`seek(toSeconds:)` が長さを必要とするため）。`saved >= duration` → nil。`duration - saved <= endMargin` → nil。それ以外 → `saved`。
- `isResumePending`：`restoreCompleted` が真 → 偽。`secondsSincePlaying` が nil → 真。`secondsSincePlaying < pendingTimeout` → 真。それ以外 → 偽。
- `shouldRecord`：`position >= minimumPosition` かつ `!isClockStopped` かつ `!isResumePending` かつ `!hasReachedEnd`。
- `ResumeStore`：内部は `[VideoIdentity: Entry]`、保存は `entries: [{fileName, size, position, updatedAt}]` の配列。件数に上限は設けない（Issue #10 の既定）。`updatedAt` は持つ（将来の整理用。保存形式をここで確定させる）。

テスト（`ResumeRulesTests.swift`・`ResumeStoreTests.swift`。手計算）：
1. `startPosition`（長さ1000）：`saved` 100 → 100。969 → 969（残り31）。970 → nil（残り30＝境界は先頭から）。999 → nil。nil → nil。保存1200（長さ超過）→ nil。1000 → nil。
2. `saved` 0.9 → nil、1.0 → 1.0（長さ1000）。
3. 長さ20で `saved` 5 → nil（残り15 ≤ 30）。
4. 長さ nil または 0 で `saved` 100 → nil。
5. `isResumePending`：(nil, false) → 真、(4.99, false) → 真、(5.0, false) → 偽、(0, true) → 偽、(nil, true) → 偽。
6. `shouldRecord`：4つの条件のうち**1つだけを崩したケース**を各1件（position 0.99／時計停止／復元待ち／終端に達した、いずれも偽）と、すべて満たすケース（position 1）が真。
7. `ResumeStore`：`set`→`position` で取れる。同じ動画に上書き。`remove` で消える。サイズだけが違う動画は別物。NFD の名前の `VideoIdentity` でも、NFC で記録した位置が取れる。保存→読み戻しで等しい（`Date` は `Date(timeIntervalSinceReferenceDate: 1000)` の固定値）。ファイルが無ければ `load` は nil。壊れたファイルは throws。

**単体テストできない部分**（Issue のテスト方針の「5秒ごとの記録」「最後まで再生したら消す」）：5秒ごとのループ（`Task` の周期）と、`endReached` から `resume.remove` を呼ぶ配線は、`PlayerModel`／`AppModel` の中にあり、SwiftVLCのイベントに依存する。**判定の規則（記録してよいか・復元待ちか）をCoreに出してテストし、周期と配線は実機のチェックG・Eで確かめる**。

### 5.8 `SettingsStore`

```swift
public struct SettingsStore {
  public init(defaults: UserDefaults = .standard)
  /// 既定オン
  public var autoAdvance: Bool { get nonmutating set }
}
```
キー `"autoAdvance"`。未設定のとき真を返す（`object(forKey:) == nil` を見る）。テスト（`SettingsStoreTests.swift`）：専用の `UserDefaults(suiteName:)` を作り、終わったら `removePersistentDomain`。既定は真、偽にして新しい `SettingsStore` で読み直しても偽、真に戻せる。

## 6. 設計：アプリ（`App/`）

### 6.1 ブックマークと有効性（`PlaylistModel`）

`@Observable @MainActor final class PlaylistModel`。
- 状態：`private(set) var playlist: Playlist`、`private(set) var validity: [UUID: EntryValidity]`（`struct EntryValidity { var video: Bool; var chat: Bool? }`。`chat` は割り当てが無ければ nil）。
- 保存先：`playlist.json` は `FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)`（`EmojiLibrary.swift` と同じ。`create: true` でフォルダが無くても作る）の下。変更のたびに保存する（数十項目の小さいファイルなので間引かない。U9）。起動時に1回読む。`unreadable` のときは、壊れたファイルを `playlist.broken-<yyyyMMddHHmmss>.json` に改名して（既存を上書きしない）空で始め、ログに残す。保存に失敗したらログに残し、アプリは動かし続ける（00 項目8）。
- **ブックマークの作成**：選ばれたURLを `ScopedFile` でアクセスしている間に、`try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)` を呼ぶ（U1。オプションが合わなければ CI／実機で直す）。動画のブックマークが作れなければ項目にせず、`failedNames` に名前を入れる。**チャットのブックマークだけが作れなかったときは、動画だけを項目にし**、チャット名を `failedChatNames` に入れる。
- **ブックマークの解決**：`func resolve(_ data: Data) -> ResolvedFile?`（`struct ResolvedFile { let url: URL; let wasStale: Bool }`）。`URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)`。解決できなければ nil。`stale` が真なら、アクセスしている間に新しいブックマークを作って項目を更新する（保存する）。
- **有効性**：`func isVideoPlayable(_ entry: PlaylistEntry) -> Bool`＝解決でき、`startAccessingSecurityScopedResource()` した上で `FileManager.default.isReadableFile(atPath:)` が真（終わったら `stop`）。同期の軽い処理なので、自動進行の飛ばす判定からそのまま呼ぶ。`func refreshValidity()` は、全項目の動画とチャットの有効性を求めて `validity` に入れる（シートを開くとき・アプリが前面に戻るとき・追加／削除の後に呼ぶ）。数十項目なので、メインアクターで同期に行ってよい。飛ばした項目・開けなかった項目は、その場で `validity` を偽に更新する。
- **次・前の探索**：`func nextStep(excluding: Set<UUID> = []) -> Playlist.Step`／`previousStep(excluding:)`／`stepFromCurrent(excluding:)` が、`playlist.nextStep { !excluding.contains($0.id) && isVideoPlayable($0) }` などを包む（`AppModel` は `playlist.playlist.nextStep` と書かない）。**`playItem` が失敗しても現在の項目は動かないので、失敗した項目の `id` は呼び出し側が `excluding` に溜めて再探索する**（溜めないと、読めるのに `open` が失敗する項目を `nextStep` が返し続けて無限ループになる）。再探索は、候補が無くなるまでで必ず終わる。`validity` に無い項目（まだ確かめていない）は、有効として表示する。`resolve` の stale 更新（`updateEntry`＋保存）は、探索・`refreshValidity` の走査の**後**にまとめて行う。
- **操作**：
  - `func replace(videos: [URL], chats: [URL?]) -> ReplaceResult`（`struct ReplaceResult { var failedNames: [String]; var failedChatNames: [String] }`）。**置き換えの前の `Playlist` と `validity` をスナップショットとして保持**し、`func restoreSnapshot()` で戻して保存する（`commit()` でスナップショットを捨てる）。試行中の内容も変更のたびに保存する（巻き戻したときに保存し直す）。
  - `func append(videos: [URL], chats: [URL?]) -> ReplaceResult`、`remove(at:)`、`move(fromOffsets:toOffset:)`、`setCurrent(id:)`、`assignChat(entryID:url:)`。それぞれ `Playlist` の対応する操作を呼び、保存する。
- ログ：`プレイリスト 置き換え n件`、`追記 n件`、`削除 <名前>`、`並べ替え`、`チャット割り当て <項目> <名前>`、`ブックマーク 失効 <名前>`、`保存 失敗: …`。

### 6.2 `PlayerModel` の変更（再生位置の復元・記録・終了の検出・停止）

**状態**（すべて `PlayerModel` の内部。`open` が成功した後の `title` を設定する所で初期化する。失敗したときは再生中の古い動画の状態を上書きしない）：

| 変数 | 意味 | 立つ／立ち下がる |
|---|---|---|
| `currentIdentity: VideoIdentity?` | 開いた動画の識別（`fileSizeBytes`（`Int?`）を `Int64` にして、`url.lastPathComponent` と組む。取れなければ nil＝記憶しない） | `open` 成功で設定。`stop()` で nil |
| `savedPosition: TimeInterval?` | `resumeLookup(identity)` で得た保存済みの位置 | `open` 成功で設定。復元を試し終えたら nil |
| `restoreCompleted: Bool` | 復元が済んだ（またはしないと決まった） | `open` で偽。`savedPosition == nil`／`startPosition` が nil／シークが `true` を返したとき真 |
| `playingSince: Date?` | 最初の `.playing` になった時刻 | `open` で nil。最初の `.playing` で設定 |
| `isSeekable: Bool` | `.seekableChanged(let seekable)` のイベントの値 | `open` で偽。イベントで更新（`player.isSeekable` は読まない。内部値の更新とイベント配送の順が保証されないため） |
| `hasReachedEnd: Bool` | `endReached` を受けた | `endReached` で真。`open` で偽（**`recordPosition()` を呼んだ後に**下ろす）。次の `.playing` への遷移でも偽 |

- **復元**：`@ObservationIgnored var resumeLookup: ((VideoIdentity) -> TimeInterval?)?`。**復元のシークは、時計が `.playing` になってから行う**（`PlaybackClock.seek(to:at:)` は時計が `.stopped` だと何もしない（`PlaybackClock.swift` 105〜107行の `guard mode != .stopped`）ので、`open` の途中や `lengthChanged` の時点で呼ぶと時計に反映されない）。`stateDidChange(.playing)` と、その後の `timeChanged` のたびに、`restoreCompleted` が偽で `duration > 0` かつ `isSeekable` なら試す：`ResumeRules.startPosition(saved: savedPosition, duration: duration)` が nil → `restoreCompleted = true`（先頭から）。位置があれば `seek(toSeconds:)`、`true` なら `restoreCompleted = true`、`false` なら次の `timeChanged` で再試行する。`isResumePending` が偽になった（5秒を過ぎた）ら試すのをやめる。
  - **`seek(toSeconds:)`（`PlayerModel.swift:174`）に `@discardableResult` を付け、受け付けられたら `true` を返す**。`true` は「受け付けられた」であって「その位置に着地した」ではない（コメントに書く）。既存の呼び出し側（`ControlsView`、リモートの `seek` ハンドラ）は影響を受けない。
  - **`:start-time` オプションは使わない**（タイムラインが切り詰められる。2節）。復元したら `記憶 復元 <名前> <位置>s` をログに残す。再生が始まってから跳ぶので、最初の一瞬は0秒付近が表示され得る（U2で観察）。
  - `startObserving()` のイベントの絞り込みに `.seekableChanged` と `.endReached` を足す。
- **記録**：`@ObservationIgnored var positionRecorder: ((VideoIdentity, TimeInterval) -> Void)?`。再生中（`clock.mode == .playing`）に5秒ごと（`init` で起動する `Task` のループ。M1の他のポーリングと同じ作り）、一時停止したとき（`stateDidChange(.paused)`）、前面から離れるとき（`sceneDidChange` で `isActive == false`）、別の動画に替える前（`open` の冒頭）、停止の前に、`recordPosition()` を呼ぶ。`recordPosition()` は、`currentIdentity` が有り、`ResumeRules.shouldRecord(position: clock.position(at: now), isClockStopped: clock.mode == .stopped, isResumePending: ResumeRules.isResumePending(secondsSincePlaying: playingSince.map { now.timeIntervalSince($0) }, restoreCompleted: restoreCompleted), hasReachedEnd: hasReachedEnd)` が真のときだけ `positionRecorder` に渡す。
- **終了の検出**：`handle(_:)` に `case .endReached:` を足し、`hasReachedEnd = true`、ログ（`再生 終了 <名前>`）、`onEnded?(currentIdentity)`（`@ObservationIgnored var onEnded: ((VideoIdentity?) -> Void)?`）の順で処理する。`playbackGeneration` の確認（`handle` の冒頭）は、そのまま効く。
- **停止**：2つの操作を持つ。
  - `stopKeepingTitle()`：再生中でも停止中でも、`recordPosition()` の後に `player.stop()` を呼び、時計を停止して位置を0に戻し、`syncClockState()`・`updateRemote()` を呼ぶ。`title`・`duration`・`currentFile`・`currentIdentity` は残す（M1の「終端で停止して先頭に戻る」状態と同じ。`PlayerModel.play()` は `.stopping` では何もしない（145〜146行）ので、停止の後に再生ボタンで同じ動画をやり直せるかを実機で確かめる）。
  - `stop()`：動画を閉じる。`recordPosition()` の後に `player.stop()`、時計の停止、`duration`・`title`・`currentFile`・`currentIdentity` を nil、`remote?.update(nil)`。M1の `open` の失敗時の後始末と共通の処理にする。`chat.reset()` は `PlayerModel` が `chat` を持たないので、`AppModel` 側で呼ぶ。
- **ナビゲーションの状態**：`@ObservationIgnored var navigationState: (() -> (canGoPrevious: Bool, canGoNext: Bool))?` を、`updateRemote()` が読んで `remote?.update(_, canGoPrevious:, canGoNext:)` に渡す。`func refreshRemote()`（`updateRemote()` を呼ぶだけ）を公開する。
- `open(url:)` の戻り値・エラー処理・`openCount` は変えない。

### 6.3 `RemoteControlController` の変更（確定事項3）

- `Handlers` に `next`・`previous`（`@MainActor @Sendable () -> Void`）を足す。
- `install(handlers:)` に `add(commands.nextTrackCommand, name: "nextTrack") { _ in handlers.next }`、`previousTrackCommand` も同様に足す。現在 `isEnabled = false` にしている2行（98〜99行）は消す。
- `update(_ state: NowPlayingState?, canGoPrevious: Bool = false, canGoNext: Bool = false)`（既定値で既存の `update(nil)` を通す）：`state == nil` のときは、2つとも無効。そうでなければ `previousTrackCommand.isEnabled = canGoPrevious`、`nextTrackCommand.isEnabled = canGoNext`。`setPlaybackCommands(enabled:)` の既存の一覧には含めない。
- `NowPlayingState`（Core）は変えない。
- **ロック画面で前へ・次へと10秒送り・戻しが両立しない場合（U4）：ユーザーが確定（2026-10-16）。10秒送り・戻しを優先する**。`previousTrackCommand`／`nextTrackCommand` は有効にして登録するが、両立せずロック画面・コントロールセンターに出ないなら、それを受け入れる（`skipForward`／`skipBackward` は無効にしない。画面のボタンとPiPの窓は前へ・次へが使える）。実機で出るかを報告するだけでよい。

### 6.4 `AppModel` の変更（選択の振り分け・項目の再生・自動進行）

`AppModel` に `let playlist: PlaylistModel`、`let resume: ResumeModel`、`let settings: SettingsModel` を足す。生成順は既存（診断→音声セッション→再生→ロック画面）に、`playlist`・`resume`・`settings` を足し、`playback.resumeLookup`・`positionRecorder`・`onEnded`・`navigationState` を配線する。`RemoteControlController` は `AppModel` の全プロパティの初期化前に作られ、`next`／`previous` で `self` を捕まえられないので、`@MainActor final class NavigationRelay { weak var model: AppModel? }` を先に作ってハンドラに渡し、`init` の最後で `relay.model = self` とする。**起動しても再生は始めない**（確定事項9）。

**ファイルピッカーとアラートの置き場所（U5）**：SwiftUIは、シートを表示している間、その下のビューからは別の画面（ピッカー・アラート）を重ねて出せない。そこで**表示を行うビューごとに、`.fileImporter` を1つ、`.alert`（`app.alertMessage`）を1つずつ付ける**。
- `PlayerScreen`：`.fileImporter`（`open`：`[.item]` 複数）と `.alert`（M2のまま）。
- `PlaylistView`：`.fileImporter` を1つ。用途は `@State enum ImportPurpose { case append, assignChat(UUID) }`（`append`：`[.item]` 複数／`assignChat`：`[.json]` 1つ）で切り替える。`.alert` も付ける。
- `SettingsView`：`.fileImporter` を1つ（`[.item]` 1つ。絵文字ライブラリの入れ替え）。`.alert` も付ける。
- 3つの `.alert` は同じ `app.alertMessage` を見るので、**シートが表示されている間は、シート側だけが `isPresented` を真にし、`PlayerScreen` 側は偽にする**（`showsPlaylist || showsSettings` のとき `PlayerScreen` の `.alert` を出さない）。閉じる処理（Binding の `set`）は、M2と同じく各 `.alert` の1箇所だけで `dismissAlert()` を呼ぶ。診断シートの表示中は `PlayerScreen` の `.alert` が出せないが、通知は閉じるまで待たせる（M2と同じ。許容）。
- 結果は `AppModel` の用途ごとのメソッド（`handlePicked`／`appendPicked`／`assignChatPicked`／`replaceEmojiPicked`）に渡す。

**`handlePicked(urls:)`（`open` の用途）** — M2の関数を置き換える：
1. `SelectionPlanner.plan(fileNames: urls.map(\.lastPathComponent))` で振り分ける。`unsupported` があれば通知「対応していない形式です」。`emojiLibrary` があれば `emoji.importLibrary(from:)`（失敗は通知。M2のとおり）。
2. 動画があるとき（`videos` が空でない）：`PlaylistModel.replace(videos:chats:)` で置き換える（`ScopedFile` でアクセスしながらブックマークを作る）。`failedNames` があれば通知「開けないファイルがありました: …」、`failedChatNames` があれば通知「チャットを開けませんでした: …」、`ignoredChats` があれば通知「対応する動画が無いチャットを無視しました: …」。
3. 置き換えの確定：新しいプレイリストの先頭から順に `playlist.stepFromCurrent()`（現在は先頭）で有効な項目を探し、`playItem(at:byUser: false)` で再生する。失敗（`false`）したら、その項目の `id` を `excluding` に加えて `validity` を偽にし、`stepFromCurrent(excluding:)` 相当で次の有効な項目へ進む（現在は動かないので、`excluding` で進める）。**1つでも成功したら `commit()`**。全部失敗したら `restoreSnapshot()` で元に戻し、通知「再生できる項目がありません」。失敗した項目の名前は集めて、通知「開けない項目を飛ばしました: …」を1件にまとめる（`open` は冒頭で `openError = nil` にするので、途中の失敗理由は残らず、最後の `openError` のアラートだけが出る。通知とアラートは別の行として並ぶ）。
4. 動画が無くチャットだけのとき（`soleChatIndex`）：**`playback.title == nil` なら通知「先に動画を開いてください」**（起動直後に復元された `currentID` があっても、再生中ではない）。`title != nil` なら、現在の項目に割り当て（`assignChat`）、`chat.load(url:)` で読み込む。`ignoredChats`（2つ目以降）があれば通知で知らせる。

**`appendPicked(urls:)`**：同じ `SelectionPlanner` を使い（`ignoredChats` は通知「対応する動画が無いチャットを無視しました: …」、`assignChat` でブックマークを作れなければ通知「チャットを開けませんでした: 名前」）、動画があれば `PlaylistModel.append`（再生位置は変えない）。`emojiLibrary` は取り込まず通知「絵文字ライブラリは設定から入れ替えてください」。動画が無ければ通知「追加は動画を選んでください。チャットは項目のチャットの欄から割り当てられます」。追加の後に `playback.refreshRemote()`。

**`playItem(at index: Int, byUser: Bool) -> Bool`**（プレイリスト画面のタップ、自動進行、前へ・次へ、置き換えから呼ぶ。成功＝`openCount` が増えた）：
1. `playback.recordPosition()`。
2. 項目の動画を `PlaylistModel.resolve` で解決し、`isVideoPlayable` を確かめる。落ちたら `validity` を偽にし、`byUser` なら通知「開けませんでした: 名前」。何も変えず `false`。
3. `playback.open(url:)`。
4. `openCount` が増えていなければ失敗：**現在の項目は変えない**。`playback.title == nil`（差し替えに失敗して古い動画も外れた）なら `chat.reset()`（M2の `if opened || playback.title == nil { chat.reset() }` と同じ）。`false`。
5. 成功：`playlist.setCurrent(id:)`、`chat.reset()`、項目にチャットのブックマークがあれば解決して `chat.load(url:)`（解決できなければ通知「チャットを開けませんでした: 名前」と `validity` の更新）、`playback.refreshRemote()`。`true`。
- 再生中の項目をシートでタップした場合も、同じ手順で開き直す（位置を記録して、同じ位置から再生する。何もしない案は採らない）。

**自動進行・前へ・次へ**：
- `nextItem()`／`previousItem()`（ボタン、ロック画面）：`playlist.nextStep()`／`previousStep()`。`skipped` があれば `validity` を更新して通知「開けない項目を飛ばしました: 名前, …」。`target` があれば `playItem(at: target, byUser: false)`、失敗したら、その項目の `id` を `excluding` に加えて再探索する（上の「次・前の探索」のとおり）。`target == nil` のとき、`skipped` が空なら何もしない（ボタンは無効表示のはず）。`skipped` が空でなければ（有効な項目が無い）、`playback.stopKeepingTitle()` と通知「再生できる項目がありません」（Issue 確定事項2「有効な項目が無ければ停止する」）。
- `handlePlaybackEnded(_ identity: VideoIdentity?)`（`onEnded`）：`resume.remove(identity)`（最後まで再生した動画の記憶を消す）。`settings.autoAdvance` が偽なら何もしない（M1の終端の状態。`hasReachedEnd` が立っているので、`playItem` の `recordPosition()` が記録し直すことはない）。真なら `nextStep` を求め、`nextItem()` と同じ規則で進む。末尾（`target == nil`、`skipped` が空）では何もしない。
- 停止中の「次へ」「前へ」も、同じ `nextItem()`／`previousItem()` で動く。

**プレイリスト画面の操作**（`PlaylistView` から呼ぶ）：
- 項目のタップ → `playItem(at:byUser: true)`。
- 左スワイプの削除 → `IndexSet` の添字を**大きい方から**1つずつ `remove(at:)` し、**すべて消し終えてから**、現在が消えたかを1回だけ判断する。現在が消えたとき：`playback.title == nil`（起動直後など、再生中でない）なら何もしない（再生は始めない）。`title != nil` なら、`playlist.stepFromCurrent()` で有効な項目を探し（現在の項目＝元の次自身が無効なら、`validity` を更新して通知に加える）、`target` があれば `playItem(byUser: false)`（失敗したら `excluding` に加えて再探索）、無ければ、または全部失敗したら `playback.stop()` と `chat.reset()`（削除した動画や、現在の項目と食い違う動画を再生し続けない）。
- 並べ替え → `playlist.move(fromOffsets:toOffset:)`。
- 「追加」→ 用途 `append` のピッカー → `appendPicked`。
- 項目のチャットの欄のタップ → 用途 `assignChat(entryID)` のピッカー。割り当てた後、**その項目が現在の項目で、`playback.title != nil` のときだけ** `chat.load(url:)` する。
- 追記・削除・並べ替え・現在の項目の変更の後は、`playback.refreshRemote()` を呼ぶ（ロック画面の前へ・次への有効・無効を更新する）。

**再生位置の記憶の保存**：`ResumeModel` が `ResumeStore` を持ち、`resume.json`（`playlist.json` と同じフォルダ）に保存する。`set`／`remove` のたびに書く（1ファイルが数KBなので間引かない。失敗はログだけ）。起動時に1回読む。壊れていれば `resume.broken-<日時>.json` に改名して空で始める。

**`SettingsModel`**：`@Observable @MainActor`、`var autoAdvance: Bool`（`init` で `SettingsStore` から1回読み、`didSet` で書く）。

### 6.5 画面

**`PlayerScreen`**：
- 動画を開いていない（`title == nil`）とき、動画領域に「ファイルを選択」を出す（M2のとおり）。**プレイリストが空でなければ**、その横に「プレイリスト」ボタンも出す（確定事項9）。右上に設定（歯車）の小さいボタンも出す（歯車は常に出す。ユーザー確定で、Issue #10 の「画面の入口」も更新済み）。
- `@State var showsPlaylist`、`showsSettings`。`.sheet` を2つ付ける（`PlaylistView`・`SettingsView`。`presentationDetents([.medium, .large])`）。

**`ControlsView`**：`ControlsView(model:playlist:onPickFile:onShowPlaylist:onShowSettings:onPrevious:onNext:)`。
- 再生の行を `[前へ][10秒戻る][再生/一時停止][10秒進む][次へ]` にする。前へ・次へは `backward.end.fill`／`forward.end.fill`、`.accessibilityLabel("前の項目")`／`("次の項目")`、`playlist.playlist.hasPrevious`／`hasNext` が偽なら `.disabled`。
- 下の行を `[ファイルを選択][プレイリスト][Spacer][速度][PiP][設定]` にする（M2の下の行の `Spacer` で左右に分ける作りを保つ）。プレイリストと設定はアイコンだけなので、`accessibilityLabel` を付ける（00 項目9）。

**`PlaylistView`**（`NavigationStack` ＋ `List`）：
- 各行：現在の項目はハイライトし、`playback.title != nil` のときだけ先頭に再生中のアイコンを付ける（起動直後はハイライトだけ）。無効な動画は警告アイコン（`exclamationmark.triangle`）と、文字を薄くする。タイトルは `PlaylistEntry.title`（保存した `videoFileName` から）。チャットの欄（アイコン `text.bubble`／割り当てなしは薄い `text.bubble`、チャットが無効なら警告色）。行全体のタップで再生、チャットの欄は `.buttonStyle(.borderless)` で別のタップにする（U6）。
- ツールバー：「編集」（`EditButton`）、「追加」（`plus`）、「閉じる」。`onDelete`・`onMove` を付ける。
- 空のときは案内文（「ファイルを選択して動画を追加してください」）。
- 表示時と `scenePhase == .active` に変わったとき、`playlist.refreshValidity()`。

**`SettingsView`**（`Form`）：
- 「再生」：`Toggle("自動で次の動画を再生")`（`settings.autoAdvance`）。
- 「絵文字ライブラリ」：状態（「あり（○件）」／「なし」。`emoji.hasLibrary`・`emoji.libraryCount`）と、「入れ替え」ボタン（ピッカー → `replaceEmojiPicked`。失敗は通知。確認は挟まない＝確定事項7）。
- 「このアプリについて」：「ライセンス」（`NavigationLink` → `LicensesView`）、バージョン（`diagnostics.versionText`）。

**`LicensesView`**：2つのライブラリを並べる。
- SwiftVLC：MIT、Copyright (c) 2025 Omar Albeik、使用版 1.1.0-beta.14、入手先 `https://github.com/harflabs/SwiftVLC`。全文はアプリに同梱した `SwiftVLC-MIT.txt`。
- libVLC：LGPL-2.1以降、VideoLAN。SwiftVLC が同梱するxcframeworkは、VideoLAN の vlc（`https://code.videolan.org/videolan/vlc`）に SwiftVLC 独自のパッチを当てたもの。固定したコミットとパッチは、SwiftVLC の v1.1.0-beta.14 タグの `scripts/build-libvlc.sh` と `scripts/patches/`。再ビルドの手順はこのアプリのリポジトリの `.github/workflows/build-ipa.yml` と `scripts/make-ipa.sh`（`https://github.com/5cd8/vlc-chat-ios`）。LGPL-2.1の全文は同梱した `LGPL-2.1.txt`。
- 全文は、`Bundle.main.url(forResource:withExtension:)` で読んで、スクロールできるテキストで出す（読めなければ「全文を読み込めませんでした」）。URLは `Link` で出す（タップで既定のブラウザ。オフラインでは開けない）。
- 文言は `.github/workflows/build-ipa.yml` の `NOTES` と同じ内容に揃える。

**`project.yml`**：`VLCWithChat` の `sources` に `- path: licenses` を `buildPhase: resources` で足す（`LGPL-2.1.txt` と `SwiftVLC-MIT.txt` がアプリのバンドルに入る）。`licenses/SwiftVLC-MIT.txt` は、SwiftVLC の v1.1.0-beta.14 タグの `LICENSE`（`https://raw.githubusercontent.com/harflabs/SwiftVLC/v1.1.0-beta.14/LICENSE`。タグ名に `v` が必要）の全文をそのまま写す。

### 6.6 診断・ログ

`DiagnosticsView` の詳細シートに「プレイリスト：○件 現在 ○番目」「再生位置の記憶：○件」の行を足す。追加するログは6.1〜6.4のとおり。語彙は `プレイリスト…`・`記憶…`・`再生 …` で始める。

### 6.7 その他の注意

- `RemoteControlController.swift` 23行付近の「nextTrack などは常に無効」というコメントは、前へ・次へを有効にした後は事実と合わないので、書き換える。
- `minimumPosition`（1秒）により、先頭近く（1秒未満）まで戻して別の動画へ移ると古い位置が残り、次に開いたときそこから再生される。意図した挙動（先頭付近は記録しない）なので、`ResumeRules` のコメントにその旨を残す。
- チェックGの「プレイリストに無い動画を『ファイルを選択』で開き直す」はプレイリストを置き換えるので、チェックの最後に行う。

## 7. 設計判断の記録（採用案・理由・採らなかった案）

| # | 判断 | 理由 | 採らなかった案 |
|---|---|---|---|
| D1 | 現在の項目を添字ではなく `id` で持つ | 並べ替え・削除で添字がずれても、同じ動画を指し続ける（受け入れ条件4）。PC版の `Reorder` の場合分け（4通り）が要らない | PC版と同じ添字。場合分けが増えて、テストの組み合わせが増える |
| D2 | 保存はJSONファイル（`Codable`）。Application Support に `playlist.json`・`resume.json` | 数十項目・数百件の小さいデータ。Coreで読み書きをテストできる。壊れたときに改名して残せる | SwiftData／Core Data（Macが無く、スキーマの移行を手で確かめられない）。UserDefaults（プレイリストのブックマークが大きい） |
| D3 | 記憶の「同じ動画」は、名前（NFC）＋サイズ | 確定事項4。ファイルを入れ直しても続きが効く。内容のハッシュは数GBを読むので採らない | ブックマークのID。入れ直すと記憶が切れる |
| D4 | 復元は「読み込んでから絶対位置へシーク」。`:start-time` は使わない | `:start-time` はタイムラインを切り詰める（SwiftVLCのドキュメント）。表示の位置・長さ・シークバーが全部ずれる | `:start-time` オプション。実装は簡単だが、M1の時計・ロック画面の表示と整合しない |
| D5 | 復元が済むまで位置を記録しない（ただし再生開始から5秒で打ち切る） | 動画を開いた直後の0秒付近で、保存済みの位置を上書きしてしまうため。復元できない動画（長さ不明・シーク不可）で永久に記録が止まらないよう、打ち切る | 常に記録（復元前の0を保存する）。打ち切りなし（復元できない動画の位置が一切記録されない） |
| D6 | 終了の検出は `PlayerEvent.endReached` | 正常な終端のときだけ出る（明示的な停止・差し替えでは出ない）。自動進行と「最後まで再生した動画の記憶を消す」を、誤って発火させない | `stopped` への遷移だけで判定。ユーザーの停止や差し替えでも発火する |
| D7 | ファイルピッカーとアラートを、表示を行うビュー（`PlayerScreen`・`PlaylistView`・`SettingsView`）ごとに1つずつ付け、ビュー内の用途は enum で切り替える（U5） | SwiftUIは、1つのビューに複数の `.fileImporter` を付けると最後のものしか効かない。また、シートの表示中は下のビューからピッカー・アラートを出せない | `PlayerScreen` だけに1つ置く（シート表示中に出ない見込み） |
| D8 | 有効性の確認は同期（ブックマークの解決＋読み取り可否） | 数十項目で軽い。自動進行の飛ばす判定からそのまま呼べる。非同期にすると、判定の結果を待つ状態遷移が増える | 先に全項目の有効性を非同期に求めて保持。自動進行の時点で古くなる |
| D9 | 「前へ」「次へ」のボタンの有効・無効は、添字（先頭・末尾）で決める。無効な項目だけが残っているときは、押したときに通知 | 全項目の有効性を毎回調べるとシートを開かなくても重くなる。確定事項3は「先頭では何もしない（ボタンを無効表示）」 | 有効な項目の有無でボタンを無効表示。判定の費用と、画面の更新の頻度が増える |
| D10 | 動画を開けたら `setCurrent`（開く前ではなく後） | 開けなかったときに、現在の項目と再生が変わらないようにする（M1・M2の失敗時の扱いと揃える） | 先に `setCurrent`。失敗時に現在の項目だけが進んでしまう |
| D11 | 起動時はプレイリストを復元するだけで再生しない（確定事項9） | 起動で勝手に音が出ない。起動時に大きいファイルを開く・チャットを読む処理が走らない。失効したアクセス権の扱いを起動時に持ち込まない | 最後の項目を一時停止で開く |
| D12 | チャットの解析結果は保存しない（確定事項1） | 保存形式・容量・古い保存の整理が要る。M2の実測で182MBでも約8秒、再生は止まらない | 解析結果を端末に保存 |
| D13 | Coreは `MediaPlayer`・`SwiftUI` を使わない | `swift test` をmacOSのCIで動かすため、依存を `Foundation` に絞る（M1・M2と同じ） | `Array.move(fromOffsets:toOffset:)` を使う（SwiftUI依存）。手で書く |

## 8. 実機での確認手順（ユーザーの作業）

**インストール：** PCで、GitHub Releasesのタグ `m3-<n>`（`<n>` は1から連番）のページから `vlc-with-chat-unsigned.ipa` をダウンロードし、iloader v2.3.7の「Import IPA」で入れる。**依頼文には、ipaのダウンロード先（Releasesのタグのページ）と、使うファイルを書く**（00 項目32）。使うファイル（`E:\tube\surge\` と、M0のテスト動画）：
- 組になった動画とチャット：`Clementia IS.mkv`＋`Clementia IS.live_chat.json`、`〖 ゴールデンレトリバー…〗.mkv`＋同名の `.live_chat.json`、`MARVEL Tōkon_ …#PR.mp4`＋`.chat_replay.json`。3組を一度にまとめて選ぶ。
- 最後まで再生する短い動画：M0のテスト動画（`mkv_h264_aac.mkv`、`mp4_h264_sar32-27.mp4`、`webm_vp9_opus.webm`、`mov_h264_aac.mov` ほか。いずれも数MB・数十秒）。チャットが無い項目の確認にも使う。
- 絵文字ライブラリ：`emoji_cache.sqlite`（M2で使ったもの）。
- **準備：iOSのファイルピッカーの複数選択は、1つのフォルダの中でしかできない。チェックAで使う8ファイル（3組の動画とチャット6つ＋M0の短い動画2本）を、iPhoneの同じフォルダ（アプリの Documents、またはiCloud Drive の1フォルダ）に入れておく**。M0のテスト動画の置き場所はM0のPR・Releaseのメモに従う（無ければリポジトリ外のM0用フォルダから、ユーザーが用意する）。

| チェック | 内容 | 報告してほしいこと |
|---|---|---|
| A（受け入れ1） | 「ファイルを選択」で、3組の動画とチャット（6ファイル）と、M0の短い動画2本を一度に選ぶ。プレイリストになり、動画が自然順に並び、先頭から再生される。`Part2` と `Part10` のような名前があれば順序も見る | 並び順、先頭の再生、通知 |
| B（受け入れ3） | プレイリストを開き、3組が自動でチャットに対応づいている（チャットの欄が埋まっている）。チャットが対応づかないM0の短い動画は欄が薄い。項目をタップして再生すると、その項目のチャットが読み込まれる。短い動画の項目の欄をタップしてチャットを手動で割り当てられる | 対応づかなかった動画、手動割り当ての挙動 |
| C（受け入れ2） | アプリを終了して起動し直す。プレイリストが残っている。起動しても再生は始まらず、「ファイルを選択」と「プレイリスト」が出る。項目をタップして再生でき、チャットも読み込まれる。できれば、アプリを入れ直した後にも試す（U1）。ファイルの置き場所（アプリ内 Documents／iCloud Drive）ごとに。数GB〜30GB台の動画も、コピーせずに再起動後に開き直せるか（Issue #10 の未確認事項。#8のメモリ増も見る） | 再起動後に開けなくなった項目と、その置き場所 |
| D（受け入れ4） | シートで、「追加」（末尾に追記され、再生は続く）、左スワイプの削除、「編集」で並べ替え（現在の項目が同じ動画を指し続ける）。再生中の項目を削除すると次の項目が再生され、末尾なら停止してチャット欄が空になる。項目が数十あるときの動き | 並べ替え・削除の挙動、遅さ |
| E（受け入れ5） | 短い動画を最後まで再生し、自動進行で次の項目へ進む（設定でオンのとき）。画面・ロック画面・コントロールセンターの「前へ」「次へ」が同じ動き。先頭で前へ、末尾で次へが無効表示。設定でオフにすると、最後まで再生しても次へ進まず停止する。**画面が見えない状態（ロック中・背面・PiP表示中）でも、自動進行とロック画面の「次へ」が動く**（動画の差し替え、チャットの読み込み、ロック画面の表示の更新）。有効な項目が無いとき、停止して先頭に戻る（動画は閉じない）。停止した後に再生ボタンで同じ動画をやり直せる。PiPの窓の前へ・次へ。ログに、自動進行の直後に前の動画の `停止` が遅れて届いていないか（`状態` の行の順序） | ロック画面の「前へ」「次へ」の表示（U4）、自動進行の挙動、画面が見えないときの動き |
| F（受け入れ6） | 項目の動画をファイルアプリで削除して、プレイリストを開くと警告表示になる。自動進行・次へ・前へで、その項目を飛ばして通知が出る。タップすると「開けませんでした」。チャットだけを削除したときの表示 | 警告表示、通知の文言 |
| G（受け入れ7） | 動画を途中（例：1分）まで見て別の動画へ移り、戻ると続きから再生される。終わりの30秒以内で止めた動画は先頭から。最後まで再生した動画は、開き直すと先頭から。プレイリストに無い動画を「ファイルを選択」で開き直しても続きから。一時停止・背面に回ったときの位置の記憶 | 続きから再生されなかった動画（形式）と、位置のずれ（U2・U3） |
| H（受け入れ8） | 設定シートで、自動進行のオン／オフ、絵文字ライブラリの入れ替え（件数が出る。壊れたファイルは「絵文字ライブラリを読み込めませんでした」）、ライセンス表示（SwiftVLC・libVLC・LGPL全文・入手先のリンクがSafariで開く） | ライセンスの表示の崩れ、リンク |
| I（受け入れ9） | M1・M2の機能が壊れていない：再生・シーク・速度・PiP・ロック画面の操作、チャットの同期と装飾、絵文字、リンク、動画の切り替え | M1・M2で動いていたのに動かなくなったもの |
| J（任意） | SideStoreのAppleログイン（-80045）が直っていれば、署名なしipaを取り込めるかを試す（U10） | 取り込めたか |

## 9. CI・品質管理

- CIの `test`・`build` が成功すること。警告は、成果物の `xcodebuild.log` で確認し、アプリのコードに起因する警告は残さない（`grep -nE "warning:|error:" | grep -v AppIntents`）。
- ローカルでビルドできないので、**コミットの前に、Swiftのコードを、使うAppleのAPIの宣言と、1行ずつ突き合わせる**。2節の未確認のAPIは、CIのコンパイルエラーで確かめる。
- `VLCChatCore` のテストは、手計算で期待値を検算してから書く。テスト名・コメントは、評価している条件に合わせる（00 項目15）。**演算子や分岐を変えるとテストが失敗するか**を確かめる。Swift 6モードのPackageでは、`#expect(throws:)` の中で外の変数を書き換えるテストがコンパイルを通るかをCIで確かめる（M2では通った）。
- 実装の順序（毎回CIを通す）：①Coreの `NaturalOrder`・`VideoChatPairing`・`SelectionPlanner`・`VideoIdentity`・`PlaylistEntry`/`Playlist`・`PlaylistFile`・`ResumeRules`/`ResumeStore`・`SettingsStore` とテスト → ②`App/Playlist`（`PlaylistModel`・`ResumeModel`・`SettingsModel`）と `PlayerModel` の変更（`endReached`・復元・記録・`stop()`・ナビゲーションの状態）、`RemoteControlController` の変更 → ③`AppModel` の変更（選択の振り分け・`playItem`・自動進行・前へ/次へ）→ ④画面（`PlaylistView`・`SettingsView`・`LicensesView`・`ControlsView`・`PlayerScreen`・`project.yml`・`licenses/SwiftVLC-MIT.txt`）→ ⑤診断・README。
- 追加する診断ログは、PR作成前に棚卸しし、暫定のものは消す（00 項目27）。
- `README.md` の状態の記述を「M3（プレイリストと設定）を実装中」に更新する。

## 10. リスク

- **コンパイルの往復：** `List` の `onMove`／`onDelete`、ピッカーの用途の切り替え、`MPRemoteCommandCenter` の前へ・次へ、ブックマークのAPIは、書いた後にCIで初めて確かめられる。
- **ブックマーク（U1）：** 置き場所によっては、再起動後に解決できない可能性。その場合は項目が無効扱いになり、ユーザーが選び直すことになる。
- **再生位置の復元（U2・U3）：** 形式によっては、シークが受け付けられない、または `endReached` が出ない。出ない形式では、自動進行が動かない（その形式は報告して相談）。
- **ロック画面の前へ・次へ（U4）：** 端末・OSの組み合わせで表示されない可能性。
- **M1・M2の退行：** `PlayerModel`・`AppModel`・`RemoteControlController`・`ControlsView`・`PlayerScreen` を触るので、チェックIで確認する。
- M3の結果が、Issue #10 の前提を変える場合は、計画を作り直す。

## 11. 確定した事項（ユーザーの決定）

- Issue #10 の「ユーザーが確定した事項」1〜9（2026-10-16）。「既定」は、ユーザーが違うと言わない限り採用する。
- ユーザーの指示（2026-10-14）：ステップごとの確認は不要。レビューの指摘の採否はClaudeが判断して自動で回す。
