# Issue #6 M2（チャットと絵文字） 実装計画

対象Issue: https://github.com/5cd8/vlc-chat-ios/issues/6 （アシスタントが起票したIssue。要件の正式な情報源はIssue本文であり、本計画は要約・言い換えをしない。**規則・確定事項・実データの確認結果は、Issue #6 の「決定事項」「ユーザーが確定した事項」「実データの確認」を、そのまま実装の根拠にする**。親Issue: https://github.com/5cd8/vlc-chat-ios/issues/1 ）
前提: M1（Issue #3、PR #5。`main` の `eb50a11`）が `main` に入っていること。
スコープ: M2のみ（プレイリスト・対応づけ・チャットの保存・再生位置の記憶・設定画面・絵文字の入れ替えUIは含まない）
依頼プロンプト: `user-prompt/202610161200_issue6_m2.md`（git管理しない）
作業ブランチ: `feature/issue-6-m2-chat-and-emoji`（`origin/main` から切る）

本書は、本セッションの文脈を持たない別のAIがそのまま実装に使うことを想定している。

## 0. 前提・読み替え

- **ビルドも実行もできない開発環境：** 開発機はWindowsで、Mac・Xcode・シミュレーターは無い。**コンパイルの確認はGitHub Actions（`macos-26`）だけ、実行の確認はユーザーのiPhone 16（iOS 26.6.2）の実機だけ**。pushしてCIのログ（`gh run view <id> --log-failed`、警告は成果物の `xcodebuild.log`）を読んで直す、を回す前提で進める。
- **読み替え（00 項目30）：** 「ブラウザ確認」「実行ファイルのフォルダを開く」は、**iPhone実機**に読み替える。ユーザーに実機確認を頼むときは、署名なしipaの入手先（GitHub Releasesのタグのページ）と、使うファイル（チャットJSON・絵文字ライブラリ）を依頼文に書く。インストールは、PCのiloader v2.3.7の「Import IPA」で行う（M1と同じ）。タグ `m2-<n>` を切るのは、ユーザーの指示があってから。
- **M1の土台（`main` にある）：** `App/`（`AppModel`・`Player/PlayerModel`・`Views/PlayerScreen`・`Views/ControlsView`・`Views/DiagnosticsView`・`Diagnostics/*`・`Player/ScopedFile`）と `Packages/VLCChatCore`（`PlaybackClock`・`RotatingLog`・`SupportedVideo` ほか）。M2は、これに足す。
- 設計判断の理由は、コードのコメントとPR本文にその場で直接書く。**`docs/adr/` はgit管理しないので参照しない。この計画書もマージ前に削除されるので、コードのコメントやREADMEから参照しない。**
- コメントの方針：コードにHow、テストにWhat、コミットログにWhy、コードコメントにWhy not（`code-comments`・`code-naming` スキルに従う）。

## 1. スコープ・非ゴール・受け入れ条件

Issue #6 の「範囲」（機能要件 4・5 と、1 のうちチャット・絵文字ライブラリの選択）を満たす。**非ゴール**は、Issue #6 の「非ゴール」のとおり（プレイリスト・対応づけ・チャットの保存・設定画面・装飾色の設定・絵文字のネットワーク取得・検索・時刻オフセット・タイムスタンプ表示ほか）。

| Issue #6 の受け入れ条件 | 確かめる手段 |
|---|---|
| 1 YouTube／Twitch形式のチャットが読み込め、再生位置・速度変更・シークに同期する | パーサー・範囲計算の単体テスト＋実機（8節 チェックG・H） |
| 2 URLがリンクになり、タップで既定のブラウザが開く。末尾の句読点はURLに含まれない | `ChatLinks` の単体テスト＋実機（チェックJ） |
| 3 絵文字ライブラリを取り込むと絵文字が表示される。無い絵文字は代替テキスト | 実機（チェックI）。代替テキストの決定は単体テスト |
| 4 オーナー・モデレーターが装飾される | バッジ判定の単体テスト＋実機（チェックG） |
| 5 163MB級でアプリが落ちない（+60MB以内が目標） | 実機（チェックK）。診断ログのメモリ |

Issue #6 のテスト方針にある「前方シークの差分」は、設計D4（表示範囲を末尾の添字だけで決める）で差分処理自体を持たなくしたため、`ChatStore.window` と `endIndex` のテスト（5.2）に置き換える。

## 2. 確認済みの一次情報

| 事実 | 出典 |
|---|---|
| **PC版の規則**（形式判定・YouTube／Twitchのパース・バッジ・絵文字・並べ替え・同期・装飾・サブスク通知の正規表現） | Issue #6 の「決定事項」。一次情報はPC版 `Services/ChatFileLoader.cs`・`ChatParser.cs`・`TwitchChatParser.cs`・`ChatSyncService.cs`、`ViewModels/ChatViewModel.cs`、`Views/ChatBodyBehavior.cs`（`C:\Users\owner\source\repos\vlc-chat`、https://github.com/5cd8/vlc-chat ） |
| **実データ**（YouTube 136,786行・182.5MB、オーナー／モデレーターのバッジの形、Twitch 45,967件・31.4MB、エモート、サブスク通知176件ほか） | Issue #6 の「実データの確認」 |
| **ユーザーの確定事項10件**（代替テキスト・安定ソート・配色固定・高さ・選択とリンク・アニメーションなし・読み込み中の表示・+60MB・動画切り替えでキャンセル・オフセットなし） | Issue #6 の「ユーザーが確定した事項」 |
| **M1の実機の値**：7GBの動画を93分再生して、メモリは240〜261MB。`timeChanged` は約260ms間隔。補間した現在位置は `PlayerModel.displayPosition(at:)`（`PlaybackClock`）で得る | PR #5 |
| **M1のコード（`main`）**：`App/Views/PlayerScreen.swift`（67行。`ControlsView`は15〜17行、`Spacer`＝チャット欄の場所は18〜19行、`DiagnosticsView`は20行、`.fileImporter` は22〜29行、動画未選択のボタンは `video(_:)`）、`App/Player/PlayerModel.swift`（`open(url:)` 66行、成功で `openCount += 1`（117行付近）、`displayPosition(at:)`、`title`）、`App/AppModel.swift`（`diagnostics`・`playback`・`remote`）、`App/Player/ScopedFile.swift`（セキュリティスコープの start/stop 対）、`App/Diagnostics/{AppLog,DiagnosticsModel,MemoryProbe}.swift` | リポジトリ |
| **絵文字ライブラリの作り方**：`chat_json_to_emoji_cache.py` は、YouTubeは `emoji.image.thumbnails[0].url`、Twitchは `https://static-cdn.jtvnw.net/emoticons/v2/{emoticon_id}/default/dark/2.0` をキーにして画像を入れる。スキーマは `emoji_cache(url TEXT PRIMARY KEY, data BLOB NOT NULL)` | `C:\Users\owner\source\repos\chat_json_to_emoji_cache.py` |

**Apple／Foundationの未確認の一次情報**（Appleの公式文書のページは取得できなかった。以下は実装者の知識で、**型名・挙動はCIのコンパイルと実機で確かめる**）：`JSONSerialization.jsonObject(with:)`、`FileHandle.read(upToCount:)`、SQLite3のC API（`sqlite3_open_v2`・`sqlite3_prepare_v2`・`sqlite3_column_blob`）、`UIImage.preparingThumbnail(of:)`、SwiftUIの `Text` への `Image` の埋め込み（`Text("\(Image)")`）と `Text` の連結、`AttributedString` の `.link`、`.textSelection(.enabled)`、`onScrollGeometryChange`（iOS 18）、`ScrollViewReader`。

## 3. 未確認事項（M2の実機で必ず確かめる。計画の前提にしない）

| ID | 未確認事項 | 確かめ方 | 外れたとき |
|---|---|---|---|
| U1 | `Text` の連結（テキスト＋リンク付き `AttributedString`＋絵文字画像）が、折り返しと一緒にきれいに表示されるか。`.textSelection(.enabled)` を付けても、リンクがタップで開くか | チェックI・J | 選択を外す（Issue #6 確定事項5：リンクを優先）。絵文字の埋め込みが崩れる場合は、`UITextView`＋`NSTextAttachment` に切り替える案を報告して相談 |
| U2 | 163MB級の読み込み時間（目標：数十秒以内）とピークのメモリ（+60MB以内）。`JSONSerialization` の一時オブジェクトが `autoreleasepool` で解放されるか | チェックK | 1メッセージずつの解析を軽くする（必要なキーだけ取り出すデコーダーに替える）。それでも超える場合は報告して相談 |
| U3 | ファイルアプリのプロバイダー（iCloud Driveなど）上のファイルを、`FileHandle` で逐次読めるか | チェックK | 一度アプリの一時領域へコピーしてから読む（容量を確認してユーザーに相談） |
| U4 | チャット欄の自動スクロール（`ScrollViewReader.scrollTo`）が、高さの違う行でも最下部に揃うか | チェックH | `defaultScrollAnchor(.bottom)`、または行の高さを固定する案を試す |
| U5 | 絵文字画像のデコード（PNG／WebP）と、24×24の画像を18ptに拡大したときの見た目 | チェックI | 表示サイズを調整する（Issueの「実装計画で決める」項目） |
| U6 | 取り込んだ `.sqlite` が、WALモードなどで `.sqlite` 単体では読めない場合 | チェックI | 取り込み時に検証して、読めなければ「絵文字ライブラリを読み込めませんでした」と出す（6.3節） |
| U7 | 配色固定のダーク配色が、ライトモードの端末でも読みやすいか | チェックG | チャット欄に `.environment(\.colorScheme, .dark)` を付ける（`.preferredColorScheme` は画面全体に効くので使わない） |

## 4. ファイル構成

```
vlc-chat-ios/
  App/
    AppModel.swift                       # 変更。chat・emoji を束ねる。ファイル選択の振り分け・通知（alertMessage）
    Chat/
      ChatModel.swift                    # 新規。読み込み・世代管理・表示範囲・状態
      EmojiLibrary.swift                 # 新規。取り込み（コピー・検証）とSQLite読み取り（actor）
      EmojiStore.swift                   # 新規。デコード済み画像のキャッシュと、画面への通知（@Observable）
    Views/
      PlayerScreen.swift                 # 変更。チャット欄の配置、複数選択のファイルピッカー、alert
      ChatPanelView.swift                # 新規。状態の切り替え・一覧・自動スクロール
      ChatRowView.swift                  # 新規。1件のカード（装飾・本文）
      DiagnosticsView.swift              # 変更。シートにチャットの情報を足す
    Diagnostics/DiagnosticsModel.swift   # 変更しない（ログは AppLog.write を直接使う）
  Packages/VLCChatCore/
    Sources/VLCChatCore/
      ChatMessage.swift                  # 新規。ChatRole・ChatRun・ChatMessage
      ChatStore.swift                    # 新規。コンパクトな格納・二分探索・表示範囲、ChatStoreBuilder
      ChatByteSource.swift               # 新規。プロトコル、テスト用のDataByteSource、FileHandle版のFileByteSource
      ChatFormat.swift                   # 新規。ChatFormat と形式の判定
      LineSplitter.swift                 # 新規。バイト列を行に分ける（逐次）
      JSONObjectSplitter.swift           # 新規。Twitchの comments[] を1要素ずつ切り出す（逐次）
      YouTubeChatParser.swift            # 新規。1行（辞書）→ 解析結果
      TwitchChatParser.swift             # 新規。1コメント（辞書）→ 解析結果
      ChatLoader.swift                   # 新規。判定→分割→解析→ChatStore
      ChatLinks.swift                    # 新規。本文中のURLのリンク化
      PickedFileKind.swift               # 新規。選んだファイルの種類（拡張子）
    Tests/VLCChatCoreTests/
      ChatStoreTests.swift  LineSplitterTests.swift  JSONObjectSplitterTests.swift
      YouTubeChatParserTests.swift  TwitchChatParserTests.swift  ChatLoaderTests.swift
      ChatLinksTests.swift  PickedFileKindTests.swift   # すべて新規
  README.md                              # 状態の記述を更新
```

`Packages/VLCChatCore` は `SwiftVLC` に依存させない（M1と同じ。libVLCのコピーが2つできるのを避ける）。UIKit・SQLite・SwiftUIに依存する部分は `App/` に置く。`project.yml` は変更しない（`SQLite3` はiOS SDKのシステムモジュール。`import SQLite3` だけでリンクされる。CIで確かめる）。

## 5. 設計：ロジックのPackage（`VLCChatCore`）

### 5.1 `ChatMessage`

```swift
public enum ChatRole: UInt8, Sendable { case normal = 0, moderator = 1, owner = 2 }
public enum ChatRun: Equatable, Sendable {
  case text(String)
  case emoji(url: String, alt: String)       // alt はライブラリに無いときの代替テキスト（空文字もあり得る）
}
public struct ChatMessage: Equatable, Sendable {
  public let timeSeconds: Int                // 動画開始からの秒
  public let author: String
  public let role: ChatRole
  public let runs: [ChatRun]
  public init(timeSeconds: Int, author: String, role: ChatRole, runs: [ChatRun])
}
```

### 5.2 `ChatStore`（コンパクトな格納）

目的：約22万件でもメモリを +60MB 以内（目標は20MB前後）に収める。メッセージごとに `String` と配列を持つと1件あたり約250バイト（約55MB）になるので、**構造体の配列を避け、列ごとの配列と文字列の領域にまとめる**。

```swift
public final class ChatStore: Sendable {          // 不変。全プロパティは let
  public static let windowSize = 200
  public var count: Int { get }
  public func timeSeconds(at position: Int) -> Int
  public func message(at position: Int) -> ChatMessage         // position は時刻の昇順の位置
  public func endIndex(atSeconds seconds: Int) -> Int          // 「時刻 ≦ seconds」を満たす件数（0 … count）
  public func window(endIndex: Int) -> Range<Int>              // max(0, end−200) ..< end
}
public struct ChatStoreBuilder {
  public init()
  public mutating func append(timeSeconds: Int, author: String, role: ChatRole, runs: [ChatRun])
  public func finish() -> ChatStore          // 並べ替え（安定）を行う
}
```

内部（`ChatStore`）：
- メッセージ列（追加順）：`times: [Int32]`、`authorIDs: [UInt32]`、`roles: [UInt8]`、`runStarts: [UInt32]`（このメッセージのrunが `runs` の何番目から始まるか）、`runCounts: [UInt16]`（1メッセージのrunが65535を超えたら、超えた分は捨てる。実データでは起こらない想定）。`FileByteSource(url:)` の初期化は `throws`（開けない場合）、`nextChunk()` も読み込みエラーを投げる。
- run列：`runKinds: [UInt8]`（0=テキスト、1=絵文字）、`runA: [UInt32]`、`runB: [UInt32]`。テキストは `runA`＝`textArena` 内のバイト位置、`runB`＝バイト数。絵文字は `runA`＝文字列表のID（URL）、`runB`＝文字列表のID（代替テキスト）。
- `textArena: [UInt8]`（本文のUTF-8を連結）。`strings: [String]`（投稿者名・URL・代替テキストの文字列表。同じ文字列は1つにまとめる＝`ChatStoreBuilder` が `[String: UInt32]` で重複を除く）。
- **容量：** Swiftの配列は倍々で伸びて縮まない（旧＋新の2本分が一時的に必要になり、完成後も最大2倍の容量が残る）。`finish()` で各配列を正確なサイズにコピーして作り直す（`Array(x)` はバッファを共有しコピーにならないので、`[T](unsafeUninitializedCapacity:)` か `reserveCapacity` ＋ `append(contentsOf:)` で新しい領域に写す）。`textArena` は特に大きいので、読み込み中も `reserveCapacity` で概算して伸ばす。見積もり（22万件）：列3.3MB＋run2.3MB＋本文9〜13MB＋文字列表1〜2MB＝約16〜21MB。これに、伸長中の一時的な2本分（最大約20MB）、重複除去用の辞書（読み込み中だけ）、絵文字キャッシュ（18pt×3倍＝54×54×4B≒11.7KB×最大1000件＝約12MB）を足したピークは30〜45MB程度で、+60MBに収まる見込み。
- `order: [UInt32]?`：追加順の添字を、時刻の昇順（**同じ時刻はファイルの並びを保つ＝安定**）に並べた表。追加順がすでに「時刻の昇順（同じ時刻を含む）」なら `nil`（恒等）にして、メモリを使わない。`finish()` は、まず昇順かを1回の走査で調べ、そうでなければ `(時刻, 追加順)` の組で添字を並べ替える（`sort` は不安定なので、比較に追加順を含める）。
- `message(at:)`：`order` で追加順の添字に直し、runを1つずつ復元する。`textArena` からの `String` の復元は `String(decoding: arena[a..<a+b], as: UTF8.self)`。
- `endIndex(atSeconds:)`：二分探索で「時刻 ≦ seconds」の最後の位置＋1。PC版は秒の整数同士の比較（`TimeSeconds <= timeSec`）。
- `Int32` に収まらない時刻（約68年）、`UInt32` に収まらないバイト数は、`ChatStoreBuilder.append` が `precondition` ではなく**捨てる**（時刻が `Int32` 範囲外なら追加しない）。テキストの合計が4GBを超えることは、ファイル全体で数百MBの前提では起きない（ただし超えたら以降の追加を止めて、`finish()` までに積んだ分で完了する）。

テスト（`ChatStoreTests.swift`。手計算の期待値）：
1. 往復：追加した `ChatMessage`（日本語・絵文字run・空のrun配列・同じ投稿者名の重複）が `message(at:)` で同じ値に戻る。
2. 昇順の入力：`times=[1,3,3,7]` で、`order == nil`（内部）でも位置と値が追加順どおり。
3. 非昇順の入力：時刻 `[5,1,5,1]`、本文 `A,B,C,D` → 位置0..3は `B(1),D(1),A(5),C(5)`（同じ時刻は追加順＝安定）。
4. `endIndex`（`times=[1,3,3,7]`）：`atSeconds` が 0→0、1→1、2→1、3→3、6→3、7→4、100→4。空の `ChatStore` は常に0。
5. `window`：`count=450` で `end=450`→`250..<450`、`end=100`→`0..<100`、`end=0`→`0..<0`、`end=200`→`0..<200`、`end=201`→`1..<201`。
6. 文字列表の重複除去：同じ投稿者名・同じURL・同じ代替テキストを持つ絵文字run付きのメッセージを1000件追加しても、内部の文字列表は3件（投稿者名・URL・代替テキスト）のまま増えない。
7. 範囲外の時刻（`Int(Int32.max) + 1`）は追加されない（`count` が増えない）。

### 5.3 入力の逐次読み込み

```swift
public protocol ChatByteSource {
  mutating func nextChunk() throws -> [UInt8]?     // nil で終端。1回で最大 1MiB 程度
}
public struct DataByteSource: ChatByteSource {     // テスト用。chunkSize ごとに返す
  public init(_ data: Data, chunkSize: Int)
}
```
`FileHandle`（`read(upToCount: 1 << 20)`）を使う実装 `FileByteSource(url:)` も同じファイル（Package内。Foundationだけで書ける）に置く。テストは一時ファイルで、`DataByteSource` と同じチャンクを返すことを確かめる。

**`LineSplitter`**：チャンクを順に `feed(_:handler:)` し、改行（`\n`）で区切った1行を（末尾の `\r` を除いて）`handler(ArraySlice<UInt8>)` に渡す。チャンクをまたぐ行は内部のバッファに持ち越す。`finish(handler:)` で、末尾に改行の無い最後の行を渡す。空行は渡さない。

**`JSONObjectSplitter`**（Twitch用）：チャンクを順に `feed` し、トップレベルのオブジェクトの `"comments"` 配列の**各要素のオブジェクト**を、バイト列（`[UInt8]`）として `handler` に渡す。状態機械：
- 深さ（`{` `[` で+1、`}` `]` で−1）、文字列の中か、直前が `\` か、を1バイトずつ追う。
- 深さ1で、文字列トークンが `comments` に一致し、続く空白の後に `:`、さらにその後の空白の後に `[` が来たら、配列の中に入る（それまでのトップレベルのプロパティは読み飛ばす）。
- 配列の中では、深さ2（配列の要素のオブジェクト）の `{` から対応する `}` までを1要素として蓄積し、閉じたら渡す。配列が閉じたら**以降のバイトは読まずに終了**（`embeddedData` などの大きなデータを読まない）。
- 要素がオブジェクトでない（数値・文字列など）場合は読み飛ばす。UTF-8のBOM（`EF BB BF`）は先頭で読み飛ばす（`LineSplitter` も同様に先頭のBOMを読み飛ばす。PC版は `StreamReader` が除くため）。ファイルが途中で終わっても、それまでに渡した要素は有効。構文が壊れていて状態が決まらないとき（深さが負になるなど）は、そこで終了する（それまでの結果を使う）。

テスト（`LineSplitterTests.swift`・`JSONObjectSplitterTests.swift`）：
1. `LineSplitter`：`"a\nb\r\nc"` を、チャンクサイズ1・2・3・全体で与えて、いずれも `["a","b","c"]`（チャンク境界で結果が変わらない）。末尾に改行が無い行が `finish` で渡る。空行（`"a\n\nb\n"`）は渡らない。
2. `JSONObjectSplitter`：`{"x":1,"comments":[{"a":"}"},{"b":[1,2]}],"y":2}` が、チャンクサイズ1・5・全体のいずれでも `[{"a":"}"}, {"b":[1,2]}]` の2要素になる（文字列中の `}` を深さに数えない）。エスケープされた引用符（`"a\"}"`）が文字列を閉じない。
3. `comments` より前に大きな別プロパティ（`"video":{"title":"[}"}`）があっても読み飛ばせる。`comments` が無ければ要素0件。配列が閉じた後のバイト（壊れたJSON）は読まない（`handler` が呼ばれない）。
4. BOM付き、途中で終わるファイル（`{"comments":[{"a":1},{"b"` → 1要素だけ渡る）。
5. 「最も紛らわしいペア」：キー名が `comments` に似た `commentsX`・`"comments"` を値に持つ別キーでは、配列に入らない。

### 5.4 パーサー

```swift
public struct ParsedChatMessage { timeSeconds: Int; author: String; role: ChatRole; runs: [ChatRun] }
public enum YouTubeChatParser { public static func parse(line: [String: Any]) -> ParsedChatMessage? }
public enum TwitchChatParser { public static func parse(comment: [String: Any]) -> ParsedChatMessage? }
```
入力は、`JSONSerialization.jsonObject(with:)` の結果（辞書）。**規則は Issue #6 の「PC版を読んで確認した規則」のとおり**（ここに再掲しない）。実装上の決めごと：
- **YouTube**：`replayChatItemAction.actions[0].addChatItemAction.item` 以下をたどり、キーが無ければ `nil`。レンダラーは `liveChatTextMessageRenderer`・`liveChatPaidMessageRenderer`・`liveChatMembershipItemRenderer` だけ。`timestampText.simpleText` が無い／`-` を含む／パースできない → `nil`。バッジは、`liveChatAuthorBadgeRenderer.icon.iconType`（`OWNER`／`MODERATOR`、大文字小文字を区別しない）または `tooltip` に `Owner`／`Moderator` を含む（大文字小文字を区別しない）。`VERIFIED` やメンバーのバッジは無装飾。オーナー優先。課金・メンバー加入は、runsが空なら `nil`。
- **YouTubeの絵文字run**：`emoji.image.thumbnails[0].url` を取る。`isCustomEmoji` が `true`（`as? Bool` で判定。`NSNumber` の1は `true` になる。`null` や文字列など Bool にならない値は「キーが無い」と同じ扱い。PC版 `ChatParser.cs` も Bool 以外は無い扱い）なら**カスタム**、キー自体が無ければ**Unicode**、`false` なら画像にしない。画像にする条件（URLがあり、`isCustomEmoji` が true または無い）のとき `.emoji(url:alt:)`。`alt`：カスタム＝`shortcuts[0]` → `image.accessibility.accessibilityData.label` → `emojiId` → `""`。Unicode＝`emojiId` → `label` → `shortcuts[0]` → `""`（Issue #6 確定事項1の順序「label → emojiId」の前に、Unicodeでは emojiId＝絵文字そのものを置く）。画像にしないとき（`isCustomEmoji == false`、または画像URLが無い）は、`emojiId` が空でなければ `.text(emojiId)`。連続する `text`（`isCustomEmoji:false` などで出した `.text(emojiId)` も含む）は1つの `.text` に結合し、画像のemojiの前で確定する。
- **時刻の変換は範囲を確かめてから行う**（壊れた入力で落ちないように）：Twitchは `offset` が `0 ..< Double(Int32.max)` に入るときだけ `Int(offset)`、YouTubeは時・分・秒の各値が上限（時は10万未満）以内のときだけ掛け算・足し算する。範囲外は `nil`。
- **Twitch**：`content_offset_seconds`（`as? Double`）が無い／負／有限でない → `nil`。`Int(offset)`（切り捨て）。投稿者名＝`commenter.display_name`（文字列）→ `commenter.name` → `""`。`message.body` がサブスク通知の正規表現（`^\S+\s+(?:subscribed|resubscribed|is gifting|gifted)\b`、`NSRegularExpression`）に一致 → `nil`。バッジ＝`message.user_badges[]._id` が `broadcaster`／`moderator`（完全一致）。`fragments` があれば、`emoticon.emoticon_id`（文字列で空でない）→ `.emoji(url: "https://static-cdn.jtvnw.net/emoticons/v2/\(id)/default/dark/2.0", alt: fragment.text)`、それ以外で `text` が空でなければ `.text`。`fragments` が無く `body` が空でなければ `.text(body)`。runsが空 → `nil`。

テスト（`YouTubeChatParserTests.swift`・`TwitchChatParserTests.swift`。入力は**合成のJSON文字列**。実データの形（Issue #6 の確認結果）を写し、投稿者名・本文は架空のものにする。実データのファイルはリポジトリに入れない）：
- YouTube：①テキスト1件（`MM:SS`＝`"12:34"`→754、`H:MM:SS`＝`"1:02:03"`→3723）、②プレチャット（`"-0:05"`）→`nil`、③課金（本文あり→通常、本文なし→`nil`）、④メンバー加入（本文なし→`nil`）、⑤ティッカー・プレースホルダー・課金ステッカー・配信終了メッセージ→`nil`、⑥バッジ（`OWNER`→owner、`MODERATOR`→moderator、tooltipだけ `Owner`、`VERIFIED`・メンバー→normal、両方→owner）、⑦runsの結合（`text,text,emoji,text` → `.text("ab"),.emoji,.text("c")`）、⑧カスタム絵文字（`isCustomEmoji:true`、`shortcuts[0]`＝`:_x:`）→`.emoji(url: thumbnails[0], alt: ":_x:")`、⑨Unicode絵文字（`isCustomEmoji` 無し、`emojiId:"☺"`、URLあり）→`.emoji(url:, alt:"☺")`、⑩`isCustomEmoji:false` と、URLが無い絵文字→`.text(emojiId)`、⑪`shortcuts` が無いカスタム絵文字の `alt` が `label`→`emojiId` の順、⑫`replayChatItemAction` が無い辞書・`actions` が空→`nil`。
- Twitch：①整数・小数のオフセット（`12.9`→12）、負→`nil`、②`display_name` 無しで `name`、③`user_badges`（`broadcaster`→owner、`moderator`→moderator、`subscriber` 等→normal、`Moderator`（大文字）→normal）、④エモートのURL（`emoticon_id:"307636"`→`https://static-cdn.jtvnw.net/emoticons/v2/307636/default/dark/2.0`、`alt`＝fragmentの `text`）、⑤`emoticon:null` のfragment→`.text`、⑥`fragments` 無しで `body` を使う、⑦サブスク通知（`"zakipan12 subscribed with Prime. They've subscribed for 13 months! "`、`"a resubscribed at Tier 1."`、`"a is gifting 5 Tier 1 Subs"`、`"a gifted a sub"`）→`nil`。**通常の文を誤って除外しない**（`"subscribed to the channel"` は先頭が1語＋`subscribed` でないので通常、`"I subscribed yesterday"` は先頭が `I` ＋空白＋`subscribed`… に**一致してしまう**ため、PC版と同じ結果＝除外されることを期待値にして、PC版と同じ挙動であることをコメントに書く）、⑧本文が空→`nil`。

### 5.5 `ChatLoader`

```swift
public enum ChatFormat: Sendable { case youTube, twitch }
public struct ChatLoadResult: Sendable { public let store: ChatStore; public let format: ChatFormat; public let skipped: Int }
public enum ChatLoaderError: Error { case cancelled, unreadable }
public enum ChatLoader {
  public static let formatPeekLength = 4096
  public static func detectFormat(head: [UInt8]) -> ChatFormat      // 引用符込みの `"replayChatItemAction"`（22バイト）を含めば youTube（PC版 `ChatFileLoader.cs` と `chat_json_to_emoji_cache.py` も引用符込みで探す）
  public static func load(
    from source: some ChatByteSource,   // 値渡し。内部で `var` にコピーして `nextChunk()` を呼ぶ
    isCancelled: () -> Bool,
    progress: (Int) -> Void          // 5000件ごと。追加済みの件数
  ) throws -> ChatLoadResult
}
```
流れ：先頭チャンクから最大4096バイトを取り（足りなければ次のチャンクも読んで足す）、`detectFormat`（先頭4096バイトを UTF-8 として、**`String(decoding:)` ではなくバイト列の探索**で引用符込みの `"replayChatItemAction"`（22バイト）を探す。先頭4096バイトにBOMは数えに含めない（PC版は `StreamReader` がBOMを除いた後の4096文字を見るため、BOM付きは先頭の3バイトを読み飛ばしてから4096バイトを見る）。PC版は文字列にしてから `Contains` するが、バイト列で同じ結果になる）。YouTubeは `LineSplitter`、Twitchは `JSONObjectSplitter` に、**先頭の読み込み済みのバイトも含めて**全チャンクを渡す。1行／1要素ごとに、`autoreleasepool { JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any] }` → パーサー → `ChatStoreBuilder.append`。解析できない行は `skipped` に数える。`isCancelled()` を256件ごと、およびチャンクを読むたびに確認して、真なら `ChatLoaderError.cancelled`。**`unreadable` を投げる条件**（Issue #6「読み込めない形式のJSONは「チャットを読み込めませんでした」と表示」）：Twitchは、ルートがオブジェクトでない、`comments` が無い、`comments` の値が配列でない（`JSONObjectSplitter` が配列に入れなかった）。YouTubeは、JSONとして読めた行が0。この条件を満たさず対象のメッセージが0件のときは、空の `ChatStore`（画面は「メッセージがありません」）。`ChatModel` は `unreadable` を `.failed` にする。**ファイルが読めない（`nextChunk` が投げる）場合は、そのエラーを伝える**。

テスト（`ChatLoaderTests.swift`）：
1. `detectFormat`：先頭に `{"replayChatItemAction":…` → youTube、Twitch風 `{"FileInfo":…` → twitch。引用符込みのキー（22バイト）が4096バイトの範囲に完全に収まる位置（先頭4074バイトの空白の後に置く）→ youTube。1バイトでも範囲からはみ出す位置（先頭4075バイトの空白の後）→ twitch。BOM付きで同じ位置関係（BOM＋4074バイトの空白）→ youTube（PC版も先頭4096文字だけを見る。本テストは全てASCIIなので、バイトと文字の差は生じない）。
2. YouTubeの合成ファイル（3行：テキスト、対象外のティッカー、壊れた行）を、チャンクサイズ1・7・全体で読んで、結果の `store` が同じ（件数1、`skipped`＝2）。
3. Twitchの合成ファイル（BOM付き、`comments` に3件：通常・サブスク通知・負のオフセット）を、チャンクサイズ1・7・全体で読んで、同じ結果（件数1、`skipped`＝2）。
4. `isCancelled` が真を返すと `cancelled` を投げる。
5. 時刻が非昇順の入力で、`store` が安定に並ぶ（5.2のテスト3と同じ観点を、読み込み経由で）。
6. 空のデータ、`{"x":1}`（`comments` 無し）、`[1,2]`（ルートが配列）、`{"comments":5}` → いずれも `unreadable`。`{"comments":[]}` は件数0の `ChatStore`（`unreadable` ではない）。YouTubeでは、全行が壊れたJSON → `unreadable`、JSONとして読める行が1つあり対象外（ティッカー）なら件数0の `ChatStore`。
7. キャンセルの確認はチャンクごとにも行う（`comments` を含まない巨大なファイルでも効く）。`isCancelled` が最初から真のとき、1チャンク目で `cancelled`。

### 5.6 `ChatLinks`（本文中のURL）

```swift
public enum ChatTextSegment: Equatable, Sendable { case text(String); case link(label: String, url: URL) }
public enum ChatLinks { public static func segments(in text: String) -> [ChatTextSegment] }
```
規則（PC版 `ChatBodyBehavior.cs` と同じ）：`NSRegularExpression("https?://\\S+")` の一致ごとに、末尾の `.,;:!?)` を（1文字ずつ、なくなるまで）URLから外す。外した後が空なら、リンクにしない。`URL(string:)` が `nil`、または `host` が空のときは、リンクにせず通常のテキスト。リンクの前後は `.text`。連続する通常のテキストは1つにまとめる。

テスト（`ChatLinksTests.swift`）：
1. `"見て https://example.com/a. すごい"` → `[.text("見て "), .link("https://example.com/a", url), .text(". すごい")]`。
2. 末尾の複数の句読点：`"https://example.com/x?!)"` → リンクは `https://example.com/x`、後ろに `.text("?!)")`。
3. 末尾の `)` を落とす（PC版と同じ簡易な規則）：`"(https://example.com/a_(b))"` → `.text("(")`、リンク `https://example.com/a_(b`、`.text("))")` となることを期待値にして、PC版と同じであることをコメントに書く。
4. リンクにならない：`"https://"`（`\S+` の一致なし）、`"https://."`（末尾の `.` を外すと `https://` になり、`URL(string:)` は作れても `host` が無い）。リンクにしない判定は「`URL(string:)` が `nil`、または `host` が `nil`／空」の1本（PC版の「外した後が空」の分岐は、一致が必ず `http` で始まるので通らない）、`"https://exa%mple"`（`URL(string:)` が `nil` ならテキスト。`nil` にならない場合は、この例を外して、`host` が空になる別の例（`"http://:80"`）に差し替える。期待値は実装時に `swift test` で確認して固定）。
5. 複数のURL：`"http://a.com https://b.org"` → 2つのリンクと、間の `.text(" ")`。
6. URLが無い文 → `[.text(全体)]`。空文字 → `[]`。

### 5.7 `PickedFileKind`

```swift
public enum PickedFileKind: Equatable, Sendable { case video, chat, emojiLibrary, unsupported
  public static func classify(pathExtension: String) -> PickedFileKind }
```
`SupportedVideo.isSupported` なら `video`、`json`（大文字小文字を区別しない）なら `chat`、`sqlite` なら `emojiLibrary`、他は `unsupported`。テスト：`MP4`・`webm`→video、`JSON`→chat、`SQLite`→emojiLibrary、`txt`・`db`・空→unsupported。

## 6. 設計：アプリ（`App/`）

### 6.1 ファイル選択の振り分け（`AppModel`・`PlayerScreen`）

- `.fileImporter(isPresented:allowedContentTypes: [.item], allowsMultipleSelection: true)` に変える。結果は `app.handlePicked(urls: [URL])`。失敗は従来どおり `diagnostics.reportError`。
- `AppModel`：`let chat: ChatModel`、`let emoji: EmojiStore`、`var notice: String?`、`var alertMessage: String? { playback.openError ?? notice }`、`func dismissAlert()`（両方を `nil` に）。`PlayerScreen` の `.alert` は `alertMessage` を使う（見出しは「確認してください」に変える。M1の「動画を開けませんでした」は、`openError` の中身が理由を含むので見出しを一般化する）。
- `handlePicked(urls:)`：
  1. 各URLを `PickedFileKind.classify`。`unsupported` が含まれていたら `notice = "対応していない形式です"`（拡張子）を出す（他のファイルは処理を続ける）。
  2. `video` が1つ以上あれば、**最初の1つ**だけを `playback.open(url:)`（複数あれば、残りは無視してログに書く。プレイリストはM3）。`playback.open` は同期で完了する（`await` を挟まない。`PlayerModel.swift` の `open(url:)`）ので、呼ぶ前後の `openCount` を比べる。増えたら（成功）`chat.reset()`。失敗したら、**この回のチャットの読み込みは行わない**（`openError` が出る）。差し替えの失敗で古い動画が外れた場合（`playback.title == nil` になる）は、チャット欄も消えるので `chat.reset()` も呼ぶ。
  3. `chat`（`.json`）が1つ以上あれば、**最初の1つ**を読み込む。動画が開いていない（`playback.title == nil`）なら、`notice = "先に動画を開いてください"` を出して読み込まない。
  4. `emojiLibrary`（`.sqlite`）が1つ以上あれば、最初の1つを `emoji.importLibrary(from:)`（`Task` で。失敗は `notice = "絵文字ライブラリを読み込めませんでした"`）。動画の有無には依存しない。
- ログ：動画の「選択 …」は `PlayerModel.open` が既に書くので、`handlePicked` は動画では書かない。チャット・絵文字ライブラリ・未対応のファイルについてだけ、`選択 <種類> <パス> サイズ=…` を書く。
- 通知の表示：`notice` は文字列1つではなく、順に表示する待ち行列（`[String]`）にする。`openError` と同時に立っても、片方が消えない。絵文字の取り込み失敗のように、非同期で後から立つ通知も待ち行列に積む。`alertMessage` は、`openError` があればそれ、なければ待ち行列の先頭。`dismissAlert()` は表示中の1件だけを消す。

### 6.2 `ChatModel`

`@Observable @MainActor final class ChatModel`。
- 状態：`enum LoadState { case none, loading, loaded(count: Int, format: ChatFormat), failed }`、`private(set) var state`、`private(set) var store: ChatStore?`、`private(set) var endIndex: Int`（表示の末尾。`store.window(endIndex:)` が表示範囲）、`private(set) var loadSummary: String?`（診断シート用）。
- 内部（`@ObservationIgnored`）：`generation: Int`、`loadTask: Task<Void, Never>?`。
- `load(url: URL)`：
  - `loadTask?.cancel()`、`generation += 1`、`let gen = generation`、`store = nil`、`endIndex = 0`、`state = .loading`。
  - `ScopedFile(url:)` を作り、`Task.detached(priority: .utility)` の中で（ファイルの寿命をタスクが持つ）：メモリ（`MemoryProbe.physFootprintMB()`）と時刻を記録 → `ChatLoader.load(from: FileByteSource(url: file.url), isCancelled: { Task.isCancelled }, progress: { …ピークのメモリを更新… })` → 終了。結果は `MainActor` へ戻して、`gen == generation` のときだけ `store`・`state` を更新（**世代が違う結果は捨てる**）。`cancelled` は何もしない。他のエラー・読めない場合は `state = .failed` とログ。
  - `loadTask` には、`Task.detached` が返すタスク自身を持つ（`cancel()` が `Task.isCancelled` に届く）。
  - ログ（`AppLog.write`）：`チャット読み込み 開始 <ファイル名> サイズ=…MB`、完了 `チャット読み込み 完了 形式=… 件数=… 除外=… 所要=…s メモリ=<前>→<後>MB（ピーク<ピーク>MB）`、失敗 `チャット読み込み 失敗: …`。`loadSummary` に完了の文を入れる。
- `reset()`：`loadTask?.cancel()`、`generation += 1`、`store = nil`、`endIndex = 0`、`state = .none`、`loadSummary = nil`。
- `updatePosition(seconds: Int)`：`guard let store`、`let end = store.endIndex(atSeconds: seconds)`、`end != endIndex` のときだけ代入（変化したときだけ画面が更新される）。

### 6.3 `EmojiLibrary`（actor）と `EmojiStore`

**`EmojiLibrary`（`actor`）**：
- `libraryURL`：`Application Support/emoji_cache.sqlite`（`FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)`）。
- `importLibrary(from source: URL) throws -> Int`（取り込んだ行数）：`ScopedFile(url: source)` でアクセス権を持つ → 一時ファイルへコピー（`Application Support/emoji_cache.import.tmp`）→ **検証**：`sqlite3_open_v2(…, SQLITE_OPEN_READONLY)` で開き、`SELECT count(*) FROM emoji_cache` が実行でき、列に `url`・`data` があること（`PRAGMA table_info(emoji_cache)`）→ 検証に通ったら、開いている読み取り接続を閉じ、`libraryURL` を置き換え（置き換え先が無い初回は `FileManager.replaceItemAt` が失敗し得るので、無ければ `moveItem`、あれば `replaceItemAt`。前回の失敗で一時ファイルが残っていたら、コピーの前に消す）→ キャッシュ（デコード済みの画像・「無い」の記録）を消す → 件数を返す。検証に失敗したら、一時ファイルを消して投げる（**既存のライブラリは変えない**）。`.sqlite-wal`・`.sqlite-shm` は取り込まない（未確認事項U6）。
- `imageData(for url: String) -> Data?`：読み取り専用の接続（`sqlite3_open_v2`、初回に開く。ファイルが無ければ `nil`）。`SELECT length(data) FROM emoji_cache WHERE url = ?` が5MBを超えるなら `nil`（PC版と同じ上限）。そうでなければ `SELECT data FROM emoji_cache WHERE url = ?` の BLOB を `Data` に。**URLは一字一句そのまま**バインドする（`sqlite3_bind_text` の破棄関数は `SQLITE_TRANSIENT`。これはCのマクロでSwiftから見えないので、`let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)` を自前で定義する）。加工（`trim`・正規化）しない。
- ライブラリの有無と件数は、`MainActor` 側（`EmojiStore`）が `hasLibrary: Bool`・`libraryCount: Int?` として持つ。アプリ起動時に1回、`EmojiLibrary` に問い合わせて入れ（件数は `SELECT count(*)`）、取り込み成功時にも更新する。`lookup` は actor を同期では呼べないので、この `MainActor` 側のフラグで判定する。

**`EmojiStore`（`@Observable @MainActor`）**：
- `revision: Int`（読み込みが終わった絵文字が増えたときに、まとめて（100ms以内の分を1回で）増やす。行はこれを読んで再描画される）。
- `enum Lookup { case image(UIImage), pending, missing }`、`func lookup(url: String) -> Lookup`（`View` の `body` から呼ばれる。`revision` 以外の保持物（`NSCache`・`missing`・`inFlight`・世代）はすべて `@ObservationIgnored` にして、描画中の状態変更で再描画がループしないようにする。読み込みの開始は `Task { }` に逃がす）：メモリのキャッシュ（`NSCache<NSString, UIImage>`、`countLimit = 1000`）にあれば `.image`、「無い」の記録（`Set<String>`）にあれば `.missing`、ライブラリが無ければ `.missing`、どちらでもなければ読み込みを始めて（同じURLの読み込みは1回にまとめる＝`inFlight: Set<String>`）`.pending`。
- 読み込み：`EmojiLibrary.imageData(for:)` → `UIImage(data:)` → 高さ18ptに描き直す。`Text(Image(uiImage:))` は `UIImage.size`（pt＝px÷scale）で描かれ、`preparingThumbnail(of:)` は拡大を保証しないので、`UIGraphicsImageRenderer`（`format.scale = 3`、iPhoneのみの前提でコメントに書く。サイズは高さ18pt、幅は縦横比から計算）で描き直したものを使う→ キャッシュへ。デコードできない／データが無い → 「無い」の記録。
- `libraryChanged()`：キャッシュと記録を消し、`generation += 1`、`revision += 1`（取り込み後に呼ぶ）。読み込みを始めたときの `generation` を持っておき、完了時に違っていたら結果を捨てる（取り込み前に始めた読み込みの古い画像を、キャッシュに入れない）。
- ログ：取り込み `絵文字ライブラリ取り込み 件数=… サイズ=…MB 所要=…s`、失敗 `絵文字ライブラリ取り込み失敗: …`。ライブラリに無かったURLの最初の20件を `絵文字なし url=…` でログに残す。

### 6.4 画面

**`PlayerScreen`**：`VStack` の `Spacer(minLength: 0)`（18〜19行）を、`if model.title != nil { ChatPanelView(app: app) } else { Spacer(minLength: 0) }` に変える。`ChatPanelView` は、残りの高さをすべて使う（`frame(maxHeight: .infinity)`）。診断の行（`DiagnosticsView`）はその下に残す（Issue #6 確定事項4：正式版で出さない形への変更は別Issue）。

**`ChatPanelView`**（`let app: AppModel`、`@Environment(\.scenePhase)`、`@State isAtBottom = true`）：
- 背景は黒。`app.chat.state` で切り替える：
  - `.none`：薄い文字で「チャットを読み込むには、「ファイルを選択」で .json を選んでください」。
  - `.loading`：`ProgressView()` と「読み込み中」だけ（件数・進行は出さない）。
  - `.failed`：「チャットを読み込めませんでした」。
  - `.loaded` で `store.count == 0`：「メッセージがありません」。
  - `.loaded`：一覧。
- 一覧：`ScrollViewReader { proxy in ScrollView { LazyVStack(spacing: 6) { ForEach(range, id: \.self) { ChatRowView(message: store.message(at: $0), emoji: app.emoji) } } } }`。`range = store.window(endIndex: chat.endIndex)`。切り替えにアニメーションは付けない（`.transaction { $0.animation = nil }`。確定事項6）。
- 最下部の判定：`.onScrollGeometryChange(for: Bool.self)`（iOS 18。コンテンツの下端と表示領域の下端の差が2pt以内なら真）で `isAtBottom` を更新。`chat.endIndex` が変わったとき、`isAtBottom` なら `proxy.scrollTo(range.upperBound − 1, anchor: .bottom)`（アニメーションなし）。過去を遡っている間は動かさない。
- **遡り中に表示がずれない工夫（Issue #6「過去を遡って見ているときは、スクロール位置を動かさない」）**：新着で表示範囲の先頭の行が消えると、見ている行が上にずれる。`.scrollPosition(id: $viewedID, anchor: .bottom)`（iOS 17）で、見ている行のID（`ForEach` の `id`＝位置）を固定する。範囲外に出た行は固定できないので、最下部に戻るまで先頭は最大200件前から動かない前提とする。自動スクロールは、第一案として `.defaultScrollAnchor(.bottom, for: .sizeChanges)`（iOS 18）を試し、行の高さが揃わないなど崩れるときは `scrollTo` に切り替える。`onScrollGeometryChange` が新着でコンテンツが伸びた瞬間に `isAtBottom` を偽にしてしまう競合を避けるため、`isAtBottom` の判定には、直前の更新から0.3秒以内は前の値を保つ。実機で必ず確かめる（U4）。
- 位置の更新：`.task(id: scenePhase)` で、`scenePhase != .background` の間、0.25秒ごとに `app.chat.updatePosition(seconds: Int(max(0, app.playback.displayPosition(at: ProcessInfo.processInfo.systemUptime)).rounded(.down)))`（M1の `ControlsView` のシークバーと同じ作り。背面では回さない）。
- 見た目の固定（U7）：チャット欄は `.environment(\.colorScheme, .dark)`。

**`ChatRowView`**（`let message: ChatMessage`、`let emoji: EmojiStore`）：
- 配色（Issue #6 の値）：オーナー＝文字 `#4CD97B`・背景 `#16301F`・太字（**投稿者名と本文の両方**。PC版 `MainWindow.xaml` と同じ）・左端のバー（文字色）、モデレーター＝文字 `#4DA3FF`・背景 `#16283A`・太字・左端のバー（文字色）、通常＝文字 `#F1F1F6`・背景 `#1C1C25`・バーなし（透明）。角丸8、内側の余白は横10・縦8、左端のバーの幅3。色は `Color(red:green:blue:)` の定数にまとめる（`ChatStyle`）。
- 上段：投稿者名（`.caption`、不透明度0.9）。下段：本文（`.callout`）。
- **本文の組み立て**：`message.runs` を順に、`Text` を連結する。`.text(s)` は `ChatLinks.segments(in: s)` で分けて、`.text` は `Text(String)`、`.link` は `AttributedString`（`link` 属性＋下線）を `Text(attributed)` に。`.emoji(url, alt)` は、`emoji.lookup(url:)` が `.image(ui)` なら `Text(Image(uiImage: ui))`、`.pending` なら幅だけを確保する空白の `Text("　")`、`.missing` なら `Text(alt)`（薄い色）。`emoji.revision` を読んで、読み込み完了で再描画されるようにする。
- `.textSelection(.enabled)` を付ける。**リンクのタップが効かなくなる場合は、選択を外す**（U1。確定事項5）。リンクは `Link`/`AttributedString.link` の標準の動作で、既定のブラウザ（Safari）で開く。確認は挟まない。

**`DiagnosticsView`**（シート）：行を足す：`チャット: <loadSummary または なし>`、`絵文字ライブラリ: あり／なし（<件数>）`。1行の要約は変えない。

### 6.5 診断・ログ

- 追加するログは6.2・6.3のとおり。語彙は `チャット…`・`絵文字…` で始め、M1の語彙（`状態`・`操作`・`画面` …）と並べて読めるようにする。
- メモリのピークは、`progress` が呼ばれるたび（5000件ごと）に `MemoryProbe.physFootprintMB()` を読んで最大値を持つ。

## 7. 設計判断の記録（採用案・理由・採らなかった案）

| # | 判断 | 理由 | 採らなかった案 |
|---|---|---|---|
| D1 | 全メッセージを列ごとの配列＋文字列の領域に持つ（5.2） | 約22万件で20MB前後に収まる見込み（Issueの+60MB以内）。表示する200件の復元だけで済み、シークのたびにファイルを読み直さない | メッセージごとに `String` と配列（約55MB。予算に近い）。時刻とファイル上の位置だけを持ち、表示時に読み直す方式（Issue確定事項8の「超えそうなら」の退避先。実機で+60MBを超えたときに切り替える。U2） |
| D2 | JSONの逐次読み込みは、`FileHandle` で1MiBずつ読み、自前の分割器で1行／1要素に切り出す。1つずつ `JSONSerialization` で辞書にする | Foundationに逐次JSONパーサーが無い。ファイル全体を `JSONSerialization` に渡すと数倍のメモリになる（Twitchは数百MBが1行）。分割器はバイトの状態機械で単純 | `Data(contentsOf:options:.mappedIfSafe)` でファイル全体をメモリマップ（プロバイダー上のファイルでは、全体を読み込むことがある。U3）。SwiftPMの外部JSONパーサー（依存を増やさない） |
| D3 | 並べ替えは添字の表（`order`）で行い、追加順がすでに昇順なら表を持たない | 実データは昇順なので、メモリを使わない。安定ソートの要件（確定事項2）を、比較に追加順を含めて満たす | 配列そのものを並べ替える（列が多く、複雑） |
| D4 | 表示範囲は「末尾の添字」だけで決める（`window(endIndex:)`）。差分の追加・削除は持たない | 前進・後退・シークを同じ計算で扱える。PC版の「大きく前へシークすると全件を追加してから捨てる」を避けられる。SwiftUIの `ForEach(id: \.self)` が差分を取る | PC版と同じ差分の追加・削除 |
| D5 | 位置の取得は、0.25秒ごとの `.task` ループ（`scenePhase != .background`）。`timeChanged` の通知には結びつけない | M1で、`TimelineView` が `Slider` を作り直して固まった経験。チャットは秒単位の比較なので0.25秒で十分。背面では回さない | `timeChanged` ごとに更新（約4Hz。ほぼ同じだが `PlayerModel` に結びつきが増える）、`TimelineView`（M1の不具合） |
| D6 | 絵文字は、`EmojiStore` が `revision` を増やして、行を再描画させる | 行ごとの `@State` や `.task` だと、行の出入りのたびに読み込みが走る。キャッシュ（1000件）をまとめて持つ | 行ごとに非同期で画像を取る |
| D7 | 絵文字の見た目は、画像を18ptの高さに揃えて `Text(Image(uiImage:))` に埋め込む | 折り返しがテキストと一緒になる。選択・リンクと両立する見込み（U1） | `UITextView`＋`NSTextAttachment`（確実だが実装が重い。U1が外れたときの退避先） |
| D8 | 動画を開くのに成功したときだけチャットを外す（`openCount` の増加で判定） | 開くのに失敗したときは、前の動画とチャットがそのまま続く（M1の失敗時の扱いと揃える） | 常に外す |
| D9 | チャットは動画が開いているときだけ読み込む（選択のみで動画なしなら通知） | チャット欄は動画の下にあり、M2では保存もしない（M3） | 動画なしでも読み込んで保持（動画を開くと外れるので無意味） |
| D10 | `PickedFileKind` を `VLCChatCore` に置く | 拡張子の振り分けをテストできる（M1の `SupportedVideo` と同じ考え） | `AppModel` に直接書く |

## 8. 実機での確認手順（ユーザーの作業）

**インストール：** PCで、GitHub Releasesのタグ `m2-<n>`（`<n>` は1から連番）のページから `vlc-with-chat-unsigned.ipa` をダウンロードし、iloader v2.3.7の「Import IPA」で入れる。**依頼文には、ipaのダウンロード先（Releasesのタグのページ）と、使うファイルを書く**（00 項目32）。使うファイル：YouTube＝`【GTA5】 多摩NEWTOWN 【まったりもげる】.live_chat.json`（182.5MB）、`〖 ゴールデンレトリバーと過ごす日々 〗….live_chat.json`（オーナー・モデレーターあり）、Twitch＝`あぺっくすおれはよわい.chat_replay.json`（31.4MB）、163MB級のチャット（ユーザーが用意するファイル。依頼のときにファイル名を確認する）、絵文字ライブラリ＝`emoji_cache.sqlite`（`chat_json_to_emoji_cache.py` で作ったもの）。動画は、各チャットに対応する動画（または、長さが十分な任意の動画）。

| チェック | 内容 | 報告してほしいこと |
|---|---|---|
| G（受け入れ1・4） | 動画を開き、YouTubeの `.json` を選ぶ。チャットが出る。オーナー・モデレーターが装飾される（緑・水色の太字とバー）。Twitchも同様（モデレーターは多い）。ライトモードの端末でも読みやすいか | 表示の不具合、装飾の漏れ |
| H（受け入れ1） | 再生に合わせてチャットが追加される。倍速、シーク（前・後ろ）、10秒スキップ、一時停止中のシークで、表示が追従する。自動スクロールは最下部のときだけ。過去を遡っている間は動かない（遡り中に新着が来ても、見ている行が上にずれない）。再生が最後まで進んで停止したとき、チャット欄がどうなるか（`PlaybackClock` は停止中に位置0を返すので、先頭に戻って空になる可能性がある。意図した挙動かを見て報告） | 乱れた場面（操作と時刻）、終了時の表示 |
| I（受け入れ3） | `.sqlite` を選ぶと取り込まれ、絵文字が画像で表示される。ライブラリに無い絵文字は代替テキスト（`:_x:`・エモート名・絵文字そのもの）。壊れた `.sqlite` は「絵文字ライブラリを読み込めませんでした」 | 画像の見た目（サイズ・解像度）、代替テキスト |
| J（受け入れ2） | チャット本文のURLがリンクになり、タップでSafariが開く。末尾の句読点がURLに含まれない。長押しで選択・コピーができるか（できなければ、できない旨） | リンクが開かない場面 |
| K（受け入れ5） | 163MB級のチャットを読み込む。読み込み中は「読み込み中」が出て、動画の再生が止まらない。読み込み時間とメモリ（診断シートのチャット行・ログ）。落ちない | 読み込み時間、メモリ（前→後・ピーク）、ログファイル |
| L | 読み込み中に別の動画を開くと、チャットが外れ、古い読み込みの結果が反映されない。動画を開き直すとチャットが外れる。チャット単独（動画なし）を選ぶと「先に動画を開いてください」 | 挙動 |

## 9. CI・品質管理

- CIの `test`・`build` が成功すること。警告は、成果物の `xcodebuild.log` で確認し、アプリのコードに起因する警告は残さない（`grep -nE "warning:|error:" | grep -v AppIntents`）。
- ローカルでビルドできないので、**コミットの前に、Swiftのコードを、使うAppleのAPIの宣言と、1行ずつ突き合わせる**。2節の未確認のAPIは、CIのコンパイルエラーで確かめる。
- `VLCChatCore` のテストは、手計算で期待値を検算してから書く。テスト名・コメントは、評価している条件に合わせる（00 項目15）。**演算子や分岐を変えるとテストが失敗するか**を確かめる。
- 実装の順序（毎回CIを通す）：①`ChatMessage`・`ChatStore`・`ChatByteSource`・分割器とテスト → ②パーサー・`ChatLoader`・`PickedFileKind`・`ChatLinks` とテスト → ③`App/Chat`（`ChatModel`・`EmojiLibrary`・`EmojiStore`）→ ④画面（`ChatPanelView`・`ChatRowView`・`PlayerScreen` の変更・`AppModel` の振り分け）→ ⑤診断（`DiagnosticsView` の行・ログ）・README。
- `README.md` の状態の記述を「M2（チャットと絵文字）を実装中」に更新する。

## 10. リスク

- **コンパイルの往復：** SwiftUIの `Text` の連結・`onScrollGeometryChange`・SQLite3のC APIは、書いた後にCIで初めて確かめられる。
- **メモリ（U2）：** `JSONSerialization` が一時オブジェクトをため込むと、ピークが+60MBを超える。`autoreleasepool` を1行ごとに付ける。超えたら、必要なキーだけを取り出す方式、またはD1の退避先（ファイルの位置だけを持つ方式）を報告して相談。
- **表示（U1）：** `Text` の連結に絵文字画像・リンク・選択を同居させる見た目が崩れる可能性。退避先は `UITextView`＋`NSTextAttachment`。
- **Swiftの言語モード：** `project.yml` の `SWIFT_VERSION` は `"5.0"` なので、`App/` はSwift 5モード（`UIImage` を `Sendable` にする包みは不要）。Swift 6モードなのは `Packages/VLCChatCore`（tools 6.0）だけ。Packageの `static let` の `NSRegularExpression`（`ChatLinks`・`TwitchChatParser`）は並行性のエラーになり得る。CIで確かめ、ダメなら `nonisolated(unsafe)` にして理由をコメントに書く（または呼ぶたびに作る）。
- **自動スクロール（U4）：** 高さの違う行で最下部に揃わない可能性。
- M2の結果が、Issue #6 の前提を変える場合は、計画を作り直す。

## 11. 確定した事項（ユーザーの決定）

- Issue #6 の「ユーザーが確定した事項」10件（2026-10-16）。代替テキストは、Unicode絵文字は `emojiId`（絵文字そのもの）、カスタム絵文字は `shortcuts[0]` を優先する（実データを見て確定）。
- ユーザーの指示（2026-10-14）：ステップごとの確認は不要。レビューの指摘の採否はClaudeが判断して自動で回す。
