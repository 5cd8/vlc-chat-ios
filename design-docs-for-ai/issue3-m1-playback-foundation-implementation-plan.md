# Issue #3 M1（再生の土台） 実装計画

対象Issue: https://github.com/5cd8/vlc-chat-ios/issues/3 （アシスタントが起票したIssue。要件の正式な情報源はIssue本文であり、本計画は要約・言い換えをしない。親Issue: https://github.com/5cd8/vlc-chat-ios/issues/1 ）
スコープ: M1のみ（チャット・絵文字・プレイリスト・設定・ブックマークは含まない）
依頼プロンプト: `user-prompt/202610141800_issue3_m1.md`（git管理しない）
作業ブランチ: `feature/issue-3-m1-playback-foundation`（`origin/main` から切る）

本書は、本セッションの文脈を持たない別のAIがそのまま実装に使うことを想定している。

## 0. 前提・読み替え

- **ビルドも実行もできない開発環境：** 開発機はWindowsで、Mac・Xcode・シミュレーターは無い。**コンパイルの確認はGitHub Actions（`macos-26`）だけ、実行の確認はユーザーのiPhone 16（iOS 26.6.2）の実機だけ**。pushしてCIのログ（`gh run view <id> --log-failed`）を読んで直す、を回す前提で進める。
- **読み替え（00 項目30）：** 「ブラウザ確認」「実行ファイルのフォルダを開く」は、**iPhone実機**に読み替える。ユーザーに実機確認を頼むときは、署名なしipaの入手先（GitHub Releasesのタグのページ）と、使う動画ファイルを依頼文に書く。インストールは、PCのiloader v2.3.7の「Import IPA」で行う（SideStoreのAppleログインが障害中のため。M0で確認済み）。
- **M0の実機結果が前提：** 本計画は、M0の結果（Issue #1 のコメント https://github.com/5cd8/vlc-chat-ios/issues/1#issuecomment-6167298026 ）を確定事項として使う。**確認済みの一次情報**と、**M1の実機で確かめる未確認事項**を区別する。
- **開発の土台はM0のアプリ（`main` にある）：** `project.yml`（XcodeGen）、`.github/workflows/build-ipa.yml`、`scripts/make-ipa.sh`、`Packages/VLCChatCore`、`App/` の5ファイルを引き継ぎ、`App/` の中身を本実装の構成に作り替える。
- 設計判断の理由は、コードのコメントとPR本文にその場で直接書く。**`docs/adr/` はgit管理しないので、コメントやドキュメントから参照しない。この計画書もマージ前に削除されるので、コードのコメントやREADMEから参照しない。**
- コメントの方針：コードにHow、テストにWhat、コミットログにWhy、コードコメントにWhy not（`code-comments`・`code-naming` スキルに従う）。

## 1. スコープ・非ゴール

Issue #3 の「範囲」に書かれた機能要件 1・2（プレイリストの前へ・次へを除く）・3・10・11・12 と、受け入れ条件1〜9を満たす。

**非ゴール：** チャットの解析・表示、絵文字、プレイリスト・対応づけ・ブックマーク、再生位置の記憶、設定画面・ライセンス表示、アートワーク（サムネイル）、アイコン、SideStoreのソース配信、Swift 6への移行（アプリのSwift言語モードは5のまま）。**M1ではチャット・プレイリストのコードを書かない。**

### 1.1 受け入れ条件と、確かめる手段

| Issue #3 の受け入れ条件 | 確かめる手段 |
|---|---|
| 1 動画（MP4・MOV・WebM・MKV）を選んで再生できる（機内モードでも） | 実機（8節 チェックA） |
| 2 再生/一時停止・シークバー・10秒戻る・進む・速度変更（7段階、音程保持）・動画のタップ | 実機（チェックB） |
| 3 現在位置の表示が滑らか（補間）。一時停止・シーク・速度変更の直後に飛ばない | `PlaybackClock` の単体テスト＋実機（チェックB） |
| 4 ロック中・他アプリ使用中も音声が続く。一時停止したまま復帰しても再開しない | 実機（チェックC） |
| 5 PiPが起動する。PiP中の操作の後も、状態と表示が一致する | 実機（チェックD） |
| 6 ロック画面・コントロールセンターの操作。位置・速度が表示と一致する | `NowPlayingState` の単体テスト＋実機（チェックE） |
| 7 診断表示とログ共有。ログは5MBで退避される | `RotatingLog` の単体テスト＋実機（チェックF） |
| 8 再生が終わったら停止して先頭に戻り、再生ボタンで先頭から再生される | 実機（チェックB） |
| 9 CI（`swift test`・ビルド・ipa）が成功し、ロジックの単体テストが `VLCChatCore` にある | CI |

## 2. 確認済みの一次情報

| 事実 | 出典 |
|---|---|
| **SwiftVLC `Player` の宣言（v1.1.0-beta.14のソースで確認済み）：** `Player`（`@Observable @MainActor`）。`init(instance:)`。`state: PlayerState`（`.idle .opening .buffering .playing .paused .stopped .stopping .error`）、`isPlaybackRequestedActive: Bool`（ユーザーの再生意図。一時停止の要求が処理中でも、操作ボタンの表示を揃えるための値）、`currentTime: Duration`、`duration: Duration?`、`isSeekable`、`rate: Float`、`didReachEnd`、`activeVideoOutputs`、`videoTracks`/`audioTracks`。`play(url:) throws(VLCError)`、`pause()`、`resume()`、`togglePlayPause()`（`.idle`・`.stopped` なら `try? play()`＝**先頭から再生**、`.playing/.opening/.buffering/.paused` なら `isPlaybackRequestedActive` で `pause()` か `resume()`、`.stopping`・`.error` は何もしない）、`jump(by: Duration) -> Bool`、`seek(to: PlaybackPosition) throws(VLCError)`、`setPlaybackRate(_ rate: PlaybackRate) throws(VLCError)`（`PlaybackRate(Float)` は 0.25〜4.0 に丸める）、`events(policy:filter:) -> AsyncStream<PlayerEvent>`、`stateTransitions: AsyncStream<PlayerState>` | `Sources/SwiftVLC/Player/Player.swift`、`Player+PlaybackControl.swift`、`Player+Pause.swift`（104〜120行）、`Player+Seek.swift`、`Player+Typed.swift`、`Player+EventStreams.swift`。`gh api "repos/harflabs/SwiftVLC/contents/<path>?ref=v1.1.0-beta.14"` |
| **PiP：** `PiPVideoView(_ player, controller: Binding<PiPController?>? = nil, startsAutomaticallyFromInline: Bool = true)`。`PiPController`（`@Observable @MainActor`）の `isPossible`・`isActive`、`toggleReportingStartResult() -> PiPStartResult?`、`pipEventEnvelopes: AsyncStream<PiPEventEnvelope>`（`.event`・`.stopCause`）。PiPの窓の再生/一時停止・スキップは、SwiftVLCがプレイヤーを直接操作し、アプリの「操作」を通らない（状態の変化としてだけ観測できる） | `PiP/PiPVideoView.swift`、`PiP/PiPController*.swift`、M0のログ |
| **音声セッション：** `VLCInstance(appleAudioSessionPolicy: .applicationManaged)` を `Player(instance:)` に渡す。アプリ管理では、SwiftVLCもlibVLCも `AVAudioSession` を有効化せず、**中断明けにも再有効化しない**。ライブラリ管理は、PiPなしのロックで一時停止する（M0のログで確認済み）。`.shared` に触れると `.libraryManaged` のインスタンスが生成されてしまう | `Core/VLCInstance.swift`、`Core/AppleAudioSessionPolicy.swift`、`PiP/PiPController+AudioSession.swift`、M0のログ |
| **M0の実機（確認済み）：** 無料署名でPiP・バックグラウンド音声（アプリ管理）が動く／`timeChanged` は約260ms間隔（約4Hz）で、解像度に依存しない／`togglePlayPause` は終了後に先頭から再生する／再生を止めるとメモリが約20〜30MBに戻る／2560×1440のAV1、4KのVP9・AV1は問題なし／`PiPVideoView` を再生後に作り直すと、SwiftVLCが既存の描画面を引き継ぐ（作り直しは避ける） | Issue #1 のコメント、PR #2 |
| **M0のコード（`main`）：** `App/M0Model.swift`（419行。`play(_:)` 146行、`togglePlayPause` 184行、`jump` 190行、`seek` 197行、`setRate` 208行、`attachPiP` 226行、`startObserving` 314行、`stateDidChange` 365行、`observeSystemNotifications` 384行）、`App/M0View.swift`（161行）、`App/ScopedFile.swift`（66行。`ScopedFile` クラス＝セキュリティスコープの start/stop 対、`BookmarkVariant`＝M1では使わない）、`App/DiagnosticsLog.swift`（52行。`DiagnosticsLog.physFootprintMB()` は引き継ぐ）、`Packages/VLCChatCore/.../IntervalStats.swift`（引き継ぐ） | リポジトリ |
| **MediaPlayerフレームワーク（`MPRemoteCommandCenter`・`MPNowPlayingInfoCenter`）：** Appleの公式文書のページは取得できなかった（JavaScript描画）。以下は、実装者の知識による**未確認の一次情報**で、**型名・プロパティ名は、CIのコンパイルで確かめる**。`MPRemoteCommandCenter.shared()` の `playCommand`・`pauseCommand`・`togglePlayPauseCommand`・`skipForwardCommand`/`skipBackwardCommand`（`MPSkipIntervalCommand`。`preferredIntervals: [NSNumber]`。イベントは `MPSkipIntervalCommandEvent.interval`）・`changePlaybackPositionCommand`（`MPChangePlaybackPositionCommandEvent.positionTime`）・`nextTrackCommand`・`previousTrackCommand`。`isEnabled`、`addTarget(handler:) -> Any`（戻り値のトークンを `removeTarget(_:)` に渡す）、ハンドラは `MPRemoteCommandHandlerStatus`（`.success` ほか）を返す。**ハンドラがメインスレッドで呼ばれる保証は無い**ものとして書く。`MPNowPlayingInfoCenter.default().nowPlayingInfo`（`[String: Any]`。キーは `MPMediaItemPropertyTitle`・`MPMediaItemPropertyPlaybackDuration`・`MPNowPlayingInfoPropertyElapsedPlaybackTime`・`MPNowPlayingInfoPropertyPlaybackRate`・`MPNowPlayingInfoPropertyDefaultPlaybackRate`）、`playbackState`（`.playing .paused .stopped`）。コマンドを表示させるには、音声セッションが有効で、`nowPlayingInfo` が設定されている必要がある（実機で確かめる） | https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter 、`.../mpremotecommand` 、`.../mpnowplayinginfocenter` （取得できない場合は、Xcode 26.6のSDKヘッダーをCIのコンパイルエラーで確かめる） |

## 3. 未確認事項（M1の実機で必ず確かめる。計画の前提にしない）

| ID | 未確認事項 | 確かめ方 | 外れたとき |
|---|---|---|---|
| U1 | ロック画面に「10秒戻る・再生/一時停止・10秒進む」が出るか（`nextTrackCommand`・`previousTrackCommand` を無効にした状態で） | チェックE | 有効・無効の組み合わせを変えて、結果を報告して相談 |
| U2 | ロック画面のシークバーのドラッグ（`changePlaybackPositionCommand`）が効くか。位置・速度の表示が実際の再生と一致するか | チェックE | `nowPlayingInfo` の更新タイミングを見直す（9節 リスク） |
| U3 | PiPの窓の操作（再生/一時停止・スキップ）の後、アプリの再生状態・位置の表示・ロック画面の表示が一致するか | チェックD | `stateTransitions` の取りこぼしを調べる。状態の変化を監視して `nowPlayingInfo` を更新する経路を見直す |
| U4 | ロック画面の操作と、PiPの窓の操作が競合しないか | チェックD・E | 報告して相談 |
| U5 | 一時停止したまま背面→復帰しても、勝手に再開しないか | チェックC | 再現手順をログ（PiPの有無つき）とともに報告して相談 |
| U6 | `PlaybackClock` の補間と、シーク直後の位置の挙動（シーク先が遅い4K・AV1、一時停止中のシーク）が滑らかか | チェックB | 定数（6.1節の `seekSettleTolerance`・`seekSettleTimeout`・`backwardTolerance`）を調整 |
| U7 | `MPRemoteCommandCenter` のハンドラが呼ばれるスレッド | 実装時に `Thread.isMainThread` をログに出して確かめる（M1の実機のログで見る） | メインアクターへ渡す設計（7.2節）のまま。変更不要 |

## 4. ファイル構成

```
vlc-chat-ios/
  project.yml                            # 変更なし（ターゲット・依存・Info.plistはM0のまま）
  App/
    VLCWithChatApp.swift                 # @main。AppModel を作る（書き換え）
    AppModel.swift                       # 新規。PlayerModel・DiagnosticsModel・RemoteControl・AudioSession を束ねる
    Player/
      PlayerModel.swift                  # 新規。Player・PlaybackClock・開く・操作・PiP・状態の監視（M0Model.swift を置き換え）
      AudioSessionController.swift       # 新規。アプリ管理の有効化・中断明け
      RemoteControlController.swift      # 新規。MPRemoteCommandCenter・MPNowPlayingInfoCenter
      ScopedFile.swift                   # 移動（BookmarkVariant を削除。ScopedFile だけ残す）
    Diagnostics/
      AppLog.swift                       # 新規。RotatingLog を Documents/app-log.txt に結ぶ共有インスタンス（DiagnosticsLog.swift を置き換え）
      DiagnosticsModel.swift             # 新規。1秒ごとの計測（メモリ・間隔）、60秒ごとのログ、直近のエラー
      MemoryProbe.swift                  # 新規。phys_footprint（DiagnosticsLog.physFootprintMB() を移す）
    Views/
      PlayerScreen.swift                 # 新規。再生画面（M0View.swift を置き換え）
      ControlsView.swift                 # 新規。操作パネル（再生・シーク・速度）
      DiagnosticsView.swift              # 新規。画面端の表示と、タップで開くシート（詳細・共有）
  Packages/VLCChatCore/
    Sources/VLCChatCore/
      IntervalStats.swift                # 変更なし
      PlaybackClock.swift                # 新規
      PlaybackSpeed.swift                # 新規
      NowPlayingState.swift              # 新規
      RotatingLog.swift                  # 新規
      SupportedVideo.swift               # 新規
    Tests/VLCChatCoreTests/
      IntervalStatsTests.swift           # 変更なし
      PlaybackClockTests.swift           # 新規
      PlaybackSpeedTests.swift           # 新規
      NowPlayingStateTests.swift         # 新規
      RotatingLogTests.swift             # 新規
      SupportedVideoTests.swift          # 新規
  .github/workflows/build-ipa.yml        # タグの条件とReleaseのnotesの文言を変更（9.1節）
  README.md                              # 状態の記述を更新
```

M0の `App/M0Model.swift`・`App/M0View.swift`・`App/DiagnosticsLog.swift` は削除する。`BookmarkVariant`・ブックマークの保存・解決は、M3で必要になったとき、M0のコード（`git show 674e367:App/ScopedFile.swift`）から取り出す。**`Packages/VLCChatCore` は `SwiftVLC` に依存させない**（libVLCのコピーが2つできると未定義動作になるため。D6）。`MediaPlayer`・`AVFoundation` を使う部分は `App/` に置く。

## 5. 設計：ロジックのPackage（`VLCChatCore`）

すべて、SwiftVLC・UIKit・MediaPlayerに依存しない。時計は内部に持たない（`at: TimeInterval` は `ProcessInfo.processInfo.systemUptime` など単調増加の秒を、呼び出し側が渡す）。

### 5.1 `PlaybackClock`（現在位置の補間）

目的：libVLCの `timeChanged`（約260ms間隔）から、UIとロック画面とM2のチャット同期が使う「滑らかな現在位置」を作る。

```swift
public struct PlaybackClock: Sendable {
  public enum Mode: Sendable, Equatable { case stopped, paused, playing }
  public init(seekSettleTolerance: TimeInterval = 1.0,
              seekSettleTimeout: TimeInterval = 2.0,
              backwardTolerance: TimeInterval = 0.5)
  public private(set) var mode: Mode        // 初期値 .stopped
  public private(set) var rate: Double      // 初期値 1.0
  public private(set) var duration: TimeInterval?
  public mutating func setDuration(_ duration: TimeInterval?)
  public mutating func noteMediaTime(_ mediaTime: TimeInterval, at: TimeInterval)
  public mutating func play(at: TimeInterval)
  public mutating func pause(at: TimeInterval)
  public mutating func stop()
  public mutating func seek(to target: TimeInterval, at: TimeInterval)
  public mutating func setRate(_ rate: Double, at: TimeInterval)
  public func position(at: TimeInterval) -> TimeInterval
}
```

内部状態：`anchorMedia`（基準のメディア時刻）、`anchorUptime`（基準の受信時刻）、`pendingSeek: (target: TimeInterval, requestedAt: TimeInterval)?`。

規則（`position(at:)` の定義）：
- `.stopped` なら `0`。
- `.paused` なら `anchorMedia`。
- `.playing` なら `anchorMedia + max(0, at - anchorUptime) * rate`。
- いずれも、`duration` が分かっていれば `min(…, duration)`、下限は `0`。

規則（変更操作）：
- `noteMediaTime(t, at:)`：
  - `pendingSeek` がある間：`abs(t - target) <= seekSettleTolerance`、または `at - requestedAt >= seekSettleTimeout` なら、**下の通常の規則を通さず**、`anchorMedia = t`、`anchorUptime = at`、`pendingSeek = nil` にする（シーク直後の位置は、通知が権威のある値）。それ以外は**捨てる**（シーク前に溜まっていた通知）。
  - `.stopped` では何もしない。
  - `.paused` では `anchorMedia = t`、`anchorUptime = at`（一時停止中に届く時刻通知は、権威のある値）。
  - `.playing` では、`current = position(at: at)` と比べる。`t < current` かつ `current - t <= backwardTolerance` なら、**基準を変えない**（表示が一瞬戻るのを防ぐ）。それ以外は `anchorMedia = t`、`anchorUptime = at`（実際の後方への移動・前方への遅れは、そのまま反映する）。
- `play(at:)`：`mode = .playing`、`anchorUptime = at`（`anchorMedia` は保つ）。
- `pause(at:)`：`anchorMedia = position(at: at)`、`mode = .paused`。
- `stop()`：`mode = .stopped`、`anchorMedia = 0`、`pendingSeek = nil`。
- `seek(to:at:)`：`anchorMedia = min(max(target, 0), duration ?? .infinity)`、`anchorUptime = at`、`pendingSeek = (anchorMedia, at)`。`mode` は変えない。
- `setRate(r, at:)`：`anchorMedia = position(at: at)`、`anchorUptime = at`、`rate = r`。

テスト（`PlaybackClockTests.swift`。手計算で検算した期待値で書く。`Swift Testing`）：
1. 初期状態：`mode == .stopped`、`position(at: 5) == 0`。
2. 再生中の補間：`play(at: 0)` の後 `noteMediaTime(10, at: 0)`、`position(at: 0.5) == 10.5`（rate 1）。
3. 倍速：`setRate(2, at: 0)` の後に `noteMediaTime(10, at: 0)`（`play(at: 0)` 済み）で、`position(at: 0.5) == 11.0`。
4. 速度変更の再基準：`noteMediaTime(10, at: 0)`、`position(at: 1) == 11`、`setRate(0.5, at: 1)` 後に `position(at: 3) == 12`（11 + 2×0.5）。
5. 一時停止で止まる：`noteMediaTime(10, at: 0)`、`pause(at: 2)` で `position(at: 100) == 12`。
6. 一時停止中の時刻通知を受け入れる：`pause(at: 2)` の後 `noteMediaTime(12.3, at: 3)`、`position(at: 9) == 12.3`。
7. 前方へのずれを受け入れる：再生中、`noteMediaTime(10, at: 0)`、`noteMediaTime(11, at: 0.5)`（`current == 10.5` より進んでいる）で `position(at: 0.5) == 11`。
8. わずかな後退は無視する：`noteMediaTime(10, at: 0)`、`noteMediaTime(10.4, at: 0.5)`（`current == 10.5`、差0.1 ≤ 0.5）で `position(at: 0.5) == 10.5`（基準を変えない）。
9. 大きな後退は受け入れる：`noteMediaTime(10, at: 0)`、`noteMediaTime(5, at: 0.5)`（差5.5 > 0.5）で `position(at: 0.5) == 5`。
10. シーク直後の古い通知を捨てる：`play(at: 0)` 済みで `noteMediaTime(10, at: 0)`、`seek(to: 100, at: 1)`、`noteMediaTime(11, at: 1.1)`（|11−100|>1.0 かつ 経過0.1<2.0）は捨てて `position(at: 1.5) == 100.5`。
11. シーク先に近い通知を受け入れる：上の続きで `noteMediaTime(100.2, at: 1.3)`（|100.2−100|=0.2 ≤ 1.0）を受け入れ、通常の規則（わずかな後退の無視）を通さず `position(at: 1.3) == 100.2`。
12. シークのタイムアウト：`play(at: 0)` 済みで `seek(to: 100, at: 0)` の後、`noteMediaTime(50, at: 2.0)`（|50−100|>1.0 だが経過2.0 ≥ 2.0）を受け入れて `position(at: 2.0) == 50`。
13. 長さでの上限：`setDuration(60)`、`noteMediaTime(59.9, at: 0)` の後 `position(at: 5) == 60`。
14. 停止で0に戻る：`stop()` の後 `position(at: 5) == 0`、`mode == .stopped`。停止中の `noteMediaTime` は無視される。
15. シークの目標のクランプ：`play(at: 0)` と `setDuration(60)` の後、`seek(to: 100, at: 0)` で `position(at: 0) == 60`、`seek(to: -5, at: 0)` で `0`（`.stopped` では位置が常に0なので、`play` を先に呼ぶ）。

### 5.2 `PlaybackSpeed`

```swift
public enum PlaybackSpeed {
  public static let steps: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
  public static let normal: Double = 1.0
  public static func label(_ speed: Double) -> String   // 例: 0.5 → "0.5x"、1.0 → "1x"、1.25 → "1.25x"
}
```

`label` は、整数なら小数点なし（`1x`・`2x`）、それ以外は末尾の0を落とした小数（`0.5x`・`0.75x`・`1.25x`）。テスト：7段階の各値の表示、`steps` が7要素で昇順で `1.0` を含むこと。

### 5.3 `NowPlayingState`（ロック画面に出す情報）

```swift
public struct NowPlayingState: Equatable, Sendable {
  public let title: String
  public let duration: TimeInterval?   // nil なら長さを出さない
  public let position: TimeInterval
  public let rate: Double              // ユーザーが選んだ再生速度
  public let isPlaying: Bool
  public init(title: String, duration: TimeInterval?, position: TimeInterval, rate: Double, isPlaying: Bool)
  public var elapsedForSystem: TimeInterval   // 0 以上、duration があれば duration 以下
  public var rateForSystem: Double            // isPlaying なら rate、そうでなければ 0
}
```

テスト：`rateForSystem`（再生中は `rate`、一時停止は `0`）、`elapsedForSystem` のクランプ（負は0、`duration` 超過は `duration`、`duration == nil` なら下限だけ）。

### 5.4 `RotatingLog`

目的：`Documents/app-log.txt` を、1ファイル最大5MB、1世代（`app-log.1.txt`）に退避する。

```swift
public final class RotatingLog: @unchecked Sendable {
  public init(fileURL: URL, maxBytes: Int = 5 * 1024 * 1024, fileManager: FileManager = .default)
  public var fileURL: URL { get }
  public var backupURL: URL { get }            // 例: …/app-log.1.txt（拡張子の前に ".1"）
  public func append(_ line: String)           // 1行ごとに同期して書く。NSLock で直列化
  public var existingFileURLs: [URL] { get }   // 存在するものだけ（共有シート用。現在→退避の順）
}
```

規則：`append` は、`line + "\n"` を UTF-8 にして、現在のファイルのサイズ＋書き込みサイズ が `maxBytes` を超えるなら、先に**退避**する（`backupURL` が既にあれば削除 → 現在のファイルを `backupURL` へ移動 → 新しい空ファイルを作る）。初期化時に、ファイルが無ければ作り、あれば末尾へ追記（`seekToEnd`）。書き込みの失敗は握りつぶす（ログがアプリを落とさない）。**1行が `maxBytes` より大きい場合も、その行は新しいファイルに書く**（無限に退避しない）。

テスト（一時ディレクトリで。`RotatingLogTests.swift`）：
1. 初期化でファイルが作られる。
2. `append` した行が順に読める。
3. 上限を超える追記で、退避ファイルができ、現在のファイルは新しい行から始まる（`maxBytes: 100`、1行約30バイトを5行）。
4. 2回目の退避で、古い退避ファイルが置き換わる（退避ファイルは常に1つ）。
5. 現在＋退避のサイズ合計が、`maxBytes` の約2倍を超えない。
6. `existingFileURLs` が、存在するファイルだけを、現在→退避の順で返す。
7. 既存ファイルがあるとき、再初期化しても追記される（消えない）。
8. `maxBytes` より大きい1行でも、落ちずに新しいファイルへ書かれる。

### 5.5 `SupportedVideo`

```swift
public enum SupportedVideo {
  public static let extensions: Set<String> = ["mp4", "mov", "webm", "mkv"]
  public static func isSupported(pathExtension: String) -> Bool   // 大文字小文字を区別しない
}
```

テスト：4種の拡張子（大文字も）が真、`avi`・`json`・空文字が偽。

## 6. 設計：アプリ（`App/`）

### 6.1 起動と全体（`VLCWithChatApp.swift`・`AppModel.swift`）

`AppModel`（`@Observable @MainActor final class`）が、`PlayerModel`・`DiagnosticsModel`・`RemoteControlController`・`AudioSessionController` を作って束ねる。`VLCWithChatApp` は `@State private var app = AppModel()` を持ち、`PlayerScreen(app: app)` を出す。**生成の順序（循環を避ける）：** ① `DiagnosticsModel`・`AudioSessionController` を作る → ② `PlayerModel(diagnostics:audioSession:)` を作る → ③ `RemoteControlController(handlers:)` を、`[weak player]` で `PlayerModel` の操作を呼ぶ `Handlers` で作る → ④ `player.remote = remote`（`PlayerModel` が `remote.update(_:)` を呼ぶための後付けの参照。`weak` ではなく `AppModel` が両方を保持する）→ ⑤ `audioSession.startObservingInterruptions()`、`diagnostics.start()`。

- **VLCInstance：** `try VLCInstance(appleAudioSessionPolicy: .applicationManaged)` を1回だけ作る。**失敗しても `.shared` に戻さない**（M0と同じ。エラーを画面に出して再生を無効にする）。`VLCInstance.shared` には、アプリ全体で一度も触れない。
- **Info.plist・`project.yml`：** M0のまま（`UIBackgroundModes: audio`、`UIFileSharingEnabled`、`LSSupportsOpeningDocumentsInPlace` など）。`MediaPlayer` フレームワークは、`import MediaPlayer` だけでリンクされる（`project.yml` の変更は不要。CIで確かめる）。

### 6.2 `PlayerModel`

`@Observable @MainActor final class PlayerModel`。M0の `M0Model` から、再生・PiP・状態の監視を引き継ぎ、ブックマーク・音声セッションの切り替え・2系統のピッカーを削除する。

公開する状態（`private(set)`）：`player: Player?`、`title: String?`（ファイル名から拡張子を除いたもの）、`mode: PlaybackClock.Mode`（UIの切り替え用）、`isPlaybackRequestedActive: Bool`（ボタンの表示用。`player.isPlaybackRequestedActive` を読む）、`rate: Double`、`duration: TimeInterval?`、`openError: String?`、`pip: PiPController?`。
内部（`@ObservationIgnored`）：`clock: PlaybackClock`、`currentFile: ScopedFile?`、`pipTask`。

操作（すべて `@MainActor` のメソッド。画面・ロック画面・PiP後の同期が、同じ経路を使う）：
- `open(url: URL)`：`ScopedFile(url:)` を作る → 拡張子が `SupportedVideo.isSupported` でなければ、`openError = "対応していない形式です"` にして終了（ログ）→ `title` 設定、`clock.stop()`、`clock.setDuration(nil)`、`audioSession.activate()`、`try player.play(url: file.url)`。成功したら古い `currentFile` を解放して `currentFile = file`。失敗したら `openError` に理由、ログ。
- `togglePlayPause()`：`audioSession.activateLoggingFailure()` の後 `player.togglePlayPause()`。
- `play()`・`pause()`：ロック画面の再生・一時停止用。`play()` は、`isPlaybackRequestedActive` が真なら何もしない。偽なら、`audioSession.activateLoggingFailure()` の後、**`.stopped`/`.idle` なら `try? player.play()`、それ以外なら `player.resume()`**（`player.togglePlayPause()` は、すでに再生中のときに一時停止してしまうため使わない）。`pause()` は、`isPlaybackRequestedActive` が偽なら何もしない。真なら `player.pause()`。
- `skip(seconds: Int)`：`player.jump(by: .seconds(seconds))` を呼び、戻り値が `true` のときだけ `clock.seek(to: clock.position(at: now) + Double(seconds), at: now)`（戻り値をログ。`false` は、停止中・シーク不可）。範囲外へは `PlaybackClock` がクランプ。
- `seek(toSeconds: Double)`：`duration` が無ければ何もしない。`player.seek(to: PlaybackPosition(seconds / duration))` が成功したときだけ `clock.seek(to:at:)`（失敗はログ）。
- `setRate(_ speed: Double)`：`try player.setPlaybackRate(PlaybackRate(Float(speed)))` が成功したときだけ `clock.setRate(speed, at: now)`、`rate = speed`（失敗はログ）。
- `displayPosition(at: TimeInterval) -> Double`：`clock.position(at:)`。UIの `TimelineView` が呼ぶ。
- `startPiP()`：M0の `startPiP()` と同じ（`toggleReportingStartResult()`。結果をログ）。
- `attachPiP(_ controller: PiPController?)`・`sceneDidChange(isActive:name:)`：M0の同名メソッド（226行・270行）を引き継ぐ。`attachPiP` は、PiPのイベント（`pipEventEnvelopes`）をログに書き、`diagnostics.pipActive` を更新する。

状態の監視（M0の `startObserving` を引き継ぐ）：
- `player.events(policy: .unbounded, filter:)` で `.timeChanged`・`.lengthChanged`・`.endReached`・`.voutChanged`・`.encounteredError` だけを通す（`timeChanged` の取りこぼしを避けるため `.unbounded`）。`.timeChanged(d)` で `clock.noteMediaTime(seconds(d), at: now)` と、`diagnostics.recordTime(...)`（`IntervalStats` 用）。`.lengthChanged(d)` で `clock.setDuration`。`.encounteredError` で `diagnostics.lastError` を更新。
- `player.stateTransitions`：状態の変化ごとに、①ログ（`状態 <state> PiP=<表示中|なし>`）、②`clock` を更新（`.playing` → `clock.play(at:)`、`.paused` → `clock.pause(at:)`、`.stopped`/`.idle`/`.error` → `clock.stop()`）、③`UIApplication.shared.isIdleTimerDisabled = (state == .playing)`、④`remote.update(nowPlayingState)`。**PiPの窓の操作・ロック画面の操作・SwiftVLC内部の再開は、すべてこの経路で `clock` と `nowPlayingInfo` に反映される**（操作の出どころによらない。U3）。
- 再生中でない（`.playing` 以外）ときの `.timeChanged` は、`clock` にも間隔の集計にも入れない（M0と同じ）。`.playing` に戻るたびに `IntervalStats` を `reset`（M0の `resetStats` と同じ）。

**`mode` と `isPlaybackRequestedActive` の使い分け：** 再生/一時停止ボタンの表示（再生中なら「一時停止」）は `player.isPlaybackRequestedActive`（要求が処理中でも画面が揃う）。位置の補間とロック画面の `rateForSystem` は `clock.mode`。

### 6.3 `AudioSessionController`

```swift
@MainActor final class AudioSessionController {
  func activate() throws                    // setCategory(.playback, mode: .moviePlayback) → setActive(true)
  func activateLoggingFailure()             // 失敗をログに書いて握りつぶす
  func startObservingInterruptions()        // AVAudioSession.interruptionNotification。ended のとき activateLoggingFailure
}
```

M0の `activateAudioSessionIfAppManaged`・中断の監視を移す。**アプリ管理に固定**なので、方針の分岐は無い。呼ぶ箇所：`PlayerModel.open`・`togglePlayPause`・`play`（ロック画面）、中断明け。`AVAudioSession.interruptionNotification` の `AVAudioSessionInterruptionTypeKey` は `UInt` で取り、`AVAudioSession.InterruptionType.ended.rawValue` と比べる（M0と同じ）。

### 6.4 `RemoteControlController`

```swift
@MainActor final class RemoteControlController {
  struct Handlers {
    var play: @MainActor () -> Void
    var pause: @MainActor () -> Void
    var toggle: @MainActor () -> Void
    var skip: @MainActor (Int) -> Void          // 秒（負で戻る）
    var seek: @MainActor (Double) -> Void       // 秒
  }
  init(handlers: Handlers)
  func update(_ state: NowPlayingState?)        // nil なら nowPlayingInfo = nil、再生系コマンドを無効にする
}
```

- 初期化で `MPRemoteCommandCenter.shared()` に、`playCommand`・`pauseCommand`・`togglePlayPauseCommand`・`skipForwardCommand`（`preferredIntervals = [10]`）・`skipBackwardCommand`（`[10]`）・`changePlaybackPositionCommand` のハンドラを登録する。**`nextTrackCommand`・`previousTrackCommand`・`seekForwardCommand`・`seekBackwardCommand` は `isEnabled = false`**。トークンは保持する（`deinit` で `removeTarget`）。
- ハンドラは、**メインスレッドの保証が無い**ので、`Task { @MainActor in handlers.xxx() }` で渡し、すぐ `.success` を返す。`changePlaybackPositionCommand` のハンドラは `event as? MPChangePlaybackPositionCommandEvent` で `positionTime` を取り、取れなければ `.commandFailed`。スキップは `MPSkipIntervalCommandEvent.interval` を使い、`Int(event.interval)` を渡す（取れなければ10）。`Thread.isMainThread` をログに1回出す（U7）。
- `update(_ state:)`：`state` があれば、`nowPlayingInfo = [MPMediaItemPropertyTitle: title, MPMediaItemPropertyPlaybackDuration: duration（あれば）, MPNowPlayingInfoPropertyElapsedPlaybackTime: state.elapsedForSystem, MPNowPlayingInfoPropertyPlaybackRate: state.rateForSystem, MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0]` を設定し、`playbackState = state.isPlaying ? .playing : .paused`、各コマンドを `isEnabled = true`。`nil` なら `nowPlayingInfo = nil`、`playbackState = .stopped`。
- **更新のタイミング：** 状態が変わるとき（`stateTransitions`）、シーク・速度変更・スキップの直後、動画を開いたとき、`.lengthChanged`（長さが分かったとき）。**`timeChanged` ごとには更新しない**（システムが経過時間を `elapsed` と `rate` から自分で進めるため）。位置のずれが大きくなる場合（U2）は、60秒ごとの再同期を `DiagnosticsModel` の1秒タイマーに乗せて追加する。
- `PlayerModel` は `NowPlayingState` を `makeNowPlayingState()` で作る（`title` が無ければ `nil`）。

### 6.5 診断とログ

- `AppLog`：`enum AppLog { static let shared = RotatingLog(fileURL: <Documents>/app-log.txt); static func write(_ message: String) }`。時刻のプレフィックス（ISO8601、端末のタイムゾーン。M0の `DiagnosticsLog` と同じ書式）を付けて `append` する。**ログの語彙は、M0を引き継ぐ**（「状態 …」「操作 …」「画面 …」「PiPイベント …」「phys_footprint …」「timeChanged間隔 …」）。`起動` の行に `build`・SwiftVLCの版・libVLCの版を書く。
- `MemoryProbe.physFootprintMB() -> Double?`：M0の `DiagnosticsLog.physFootprintMB()` をそのまま移す（`task_info(mach_task_self_, TASK_VM_INFO)`）。
- `DiagnosticsModel`（`@Observable @MainActor`）：`footprintMB`、`timeStats: IntervalStats.Snapshot?`、`lastError: String?`、`pipActive: Bool`（`PlayerModel` が更新）。1秒ごとのタイマーで、`footprintMB` と `timeStats` を更新し、**60秒ごと**に `phys_footprint` と `timeChanged間隔` の行をログへ（M0と同じ）。`recordTime` は M0 の `recordTime`/`resetStats` と同じ（`IntervalStats`・外れ値（受信間隔1.0秒超）のログ）。`lastError` は、`openError`・`encounteredError`・再生開始の失敗で更新する。
- ロック・背面のログ：M0の `observeSystemNotifications`（`protectedDataWillBecomeUnavailable`・`protectedDataDidBecomeAvailable`・`AVAudioSession.interruptionNotification`）と、`sceneDidChange`（`画面 <phase> 状態=… 時間=…`）を引き継ぐ。

### 6.6 画面

- **`PlayerScreen`：** `VStack`（縦のみ）。上：動画（`ZStack`：黒背景＋`PiPVideoView(player, controller: $pip)`。**`startsAutomaticallyFromInline` は既定の `true` のまま。`.id()` で作り直さない**。`aspectRatio(16/9)`）。動画の上に、透明な `Color.clear` を重ねて `onTapGesture { model.togglePlayPause() }`（動画のタップで再生/一時停止）。中：`ControlsView`。下：空白（M2のチャット欄の場所）。最下部：`DiagnosticsView` の1行。動画が未選択のときは、「ファイルを選択」ボタンだけを出す（初回起動時。動画の領域には何も出さない）。`.fileImporter(isPresented:allowedContentTypes: [.item])` の結果で `model.open(url:)`。`openError` があれば `.alert`。`.onChange(of: pip.map { ObjectIdentifier($0) })` で `model.attachPiP(pip)`（M0と同じ）。`scenePhase` の変化で `model.sceneDidChange`。
- **`ControlsView`：** 再生/一時停止（`isPlaybackRequestedActive` で `pause.fill`／`play.fill`）、10秒戻る（`gobackward.10`）・10秒進む（`goforward.10`）、「ファイルを選択」（開き直し）、速度（`Menu` に `PlaybackSpeed.steps` の7段階。現在値を表示）、PiPボタン（`pip.enter`。`startPiP()`）、シークバー（`Slider`。つまみを掴んだ瞬間に現在位置から動き出す。離したとき1回だけ `seek`。M0の `M0View` の方式）、現在位置/長さ（`mm:ss` または `h:mm:ss`）。**現在位置とシークバーの位置は、`TimelineView(.periodic(from: .now, by: 0.1))` の中で `model.displayPosition(at: ProcessInfo.processInfo.systemUptime)` を読んで描画する**（`TimelineView` の `Date` ではなく、`PlaybackClock` に渡す `at` と同じ単調増加の秒を使う。`mode == .playing` のときだけ。それ以外は静的に描画）。`duration` が `nil` の間は、シークバーを無効にする。これで、`timeChanged` の通知頻度に画面全体が引きずられない。全ボタンに `accessibilityLabel` を付ける（00 項目9）。
- **`DiagnosticsView`：** 最下部に小さい1行（`状態 playing ・ 295MB ・ PiP`）。タップで `.sheet`：状態・メモリ・時刻通知の間隔（`IntervalStats.Snapshot` の整形は M0 の `summaryText`）・PiPの有無・直近のエラー・バージョン（build・SwiftVLC・libVLC）と、`ShareLink(items: AppLog.shared.existingFileURLs)`（「ログを共有」）。
- **画面を消さない：** 再生中のみ `isIdleTimerDisabled = true`（6.2節の状態の監視で更新）。背面に回るとき（`scenePhase != .active`）は `false`、前面に戻って再生中なら `true`（M0の `sceneDidChange` と同じ）。

### 6.7 動画を終わりまで再生したとき

SwiftVLCは `.stopping` → `.stopped` に遷移する。`stateTransitions` の `.stopped` で `clock.stop()`（位置0）、`isIdleTimerDisabled = false`、ロック画面は `update(...)` で `isPlaying == false`・`position == 0` のまま残す（再生ボタンで先頭から再生できる）。`togglePlayPause()` は `.stopped` なら `try? play()`（先頭から。M0で確認済み）。画面のシークバーと現在位置は0に戻る。

## 7. 設計判断の記録（採用案・理由・採らなかった案）

| # | 判断 | 理由 | 採らなかった案 |
|---|---|---|---|
| D1 | 現在位置は `PlaybackClock` で補間し、画面は `TimelineView`（0.1秒）で描く | `timeChanged` は約4Hz（M0実機）。`Player.currentTime` を直接読むと、位置が約260msごとに跳び、`@Observable` の更新で画面全体が再評価される（M0のレビューで指摘）。M2のチャット同期も、同じ補間値を使う | `Player.currentTime` を直接表示（跳ぶ）、`CADisplayLink`（UIKit依存が増え、テストしにくい） |
| D2 | 補間のロジックを、SwiftVLCに依存しない `VLCChatCore` に置く | CIの `swift test` で、実機なしに期待値を検算できる。libVLCのコピーが2つできる事故も避ける | アプリ側に置く（テストできない） |
| D3 | ロック画面の更新は、状態の変化・シーク・速度変更・長さ確定のときだけ。`timeChanged` ごとには更新しない | システムが `elapsed` と `rate` から自分で進める設計のため。更新頻度を増やすと、ロック画面の表示がちらつく可能性がある | 毎秒更新（無駄。U2で必要になったら60秒ごとの再同期を足す） |
| D4 | 再生・一時停止・位置の更新を、`stateTransitions` と各操作の1経路に集める | PiPの窓の操作・ロック画面の操作・SwiftVLC内部の再開は、画面のボタンを通らない。状態の変化を一次情報にすれば、出どころによらず一致する（U3） | 操作ごとに個別に更新（PiPの窓の操作が漏れる） |
| D5 | ボタンの表示は `isPlaybackRequestedActive`、位置の補間とロック画面は `clock.mode` | 前者は、一時停止の要求が処理中でも画面が揃う（SwiftVLCの設計）。後者は、実際の再生の進みを表す | `player.state` だけを見る（要求が処理中のとき、ボタンが遅れる） |
| D6 | `VLCChatCore` は `SwiftVLC` に依存させない | libVLCのコピーが2つできると未定義動作（M0から引き継ぎ） | PackageからSwiftVLCを使う |
| D7 | `PiPVideoView` を作り直さない（`.id` を付けない）。自動PiPは既定の `true` | 再生後の作り直しでは、SwiftVLCが既存の描画面を引き継ぐため、値が反映されない（M0のレビュー）。PiPをオフにする使い方は想定しない（ユーザーの決定） | スイッチ（撤去済み） |
| D8 | ログは `RotatingLog`（5MB、1世代）、ファイル名を `app-log.txt` に変更 | Issue #3 の既定。M0の `m0-log.txt` は、M1の実機に残るが、読まれない | 無制限（M0。長期運用で肥大） |
| D9 | アプリのSwift言語モードは5のまま | M0と同じ理由（ローカルでコンパイルできず、strict concurrencyの修正でCI往復が増える）。移行は別のIssue | M1で6に移行 |
| D10 | `MPRemoteCommandCenter` のハンドラはメインスレッドの保証が無いものとして、`Task { @MainActor }` で渡す | Appleの公式文書でスレッドの保証を確かめられていない（2節）。M0以来、メインアクターのクラスを非メインから呼ぶ誤りがCIの往復を増やす | ハンドラ内で直接 `PlayerModel` を呼ぶ |

## 8. 実機での確認手順（ユーザーの作業）

**インストール：** PCで、GitHub Releasesのタグ `m1-<n>`（`<n>` は1から連番）のページから `vlc-with-chat-unsigned.ipa` をダウンロードし、iloader v2.3.7の「Import IPA」で入れる（SideStoreのAppleログインが直るまで）。更新するときは、同じ手順で上書きする（`Documents` のログは残る）。**依頼文には、ipaのダウンロード先（Releasesのタグのページ）と、使う動画ファイルを書く**（00 項目32）。使う動画：M0で作ったテスト動画（`mkv_vp9_opus.mkv`・`webm_vp9_opus.webm`・`mov_h264_aac.mov` など）と、長めの動画。

| チェック | 内容 | 報告してほしいこと |
|---|---|---|
| A（受け入れ1） | 動画を選んで再生（MP4・MOV・WebM・MKV）。機内モードでも。`.json` など動画以外を選ぶと「対応していない形式です」と出る | 各形式の結果。エラー表示 |
| B（2・3・8） | 再生/一時停止、シークバー、10秒戻る・進む、速度7段階（音程）、動画のタップ。現在位置の表示が滑らか（0.1秒刻みで進む）。一時停止中のシーク、速度変更の直後に、位置が飛ばない。動画を最後まで再生すると、停止して先頭に戻り、再生ボタンで先頭から再生される | 位置が飛んだ場面（操作と動画）、終了時の挙動 |
| C（4） | PiPなしで、画面ロック・他アプリへ切り替え：音声が続くか。**一時停止したまま背面→復帰して、勝手に再開しないか**（複数回） | 結果。再開した場合は時刻 |
| D（5） | PiPをボタンと自動（ホームへ戻る）で起動。PiPの窓の再生/一時停止・スキップの後、アプリの再生状態・位置・ロック画面の表示が一致するか | 不一致の場面 |
| E（6） | ロック画面とコントロールセンターに、10秒戻る・再生/一時停止・10秒進むが出るか。各操作が効くか。シークバーのドラッグ。位置と速度の表示（倍速で再生して確認）。PiPの窓の操作との競合 | スクリーンショット。効かない操作 |
| F（7） | 診断表示がタップで開き、メモリ・状態・エラー・間隔が出る。「ログを共有」で取り出せる。長時間再生のメモリ（数時間は、M0と同じく、60秒ごとのログで見る） | ログファイル |

## 9. CI・品質管理

### 9.1 CIの変更（`.github/workflows/build-ipa.yml`）

- タグの条件（`on.push.tags`）を、`m0-*` から `m[0-9]-*` に変える（`m1-1` などを通す。GitHubのタグのglobで `[0-9]` が使える）。**「Releaseを作る」ステップの `if: startsWith(github.ref, 'refs/tags/m0-')` も、`startsWith(github.ref, 'refs/tags/m')` に変える**（変えないと、`m1-*` ではReleaseが作られない）。**この変更を最初のコミットにして、動作確認用のタグを切る前に、CIでYAMLの構文を確かめる。**
- Releaseのnotesの1行目「M0（実現性の確認）用のビルドです。」を「iPhone実機での確認用のビルドです。一般向けの配布ではありません。」に変える。LGPLの記述は、そのまま残す（公開Release。libvlc入りのipaを置くため）。
- それ以外（Xcodeの固定、キャッシュ、`make-ipa.sh`）は変更しない。

### 9.2 品質管理

- CIの `test`・`build` が成功すること。警告は、ビルドログで確認し、アプリのコードに起因する警告は残さない（`grep -nE "warning:|error:" | grep -v AppIntents`）。
- ローカルでビルドできないので、**コミットの前に、Swiftのコードを、使うSwiftVLCの宣言（タグ `v1.1.0-beta.14` のソース）と、使うAppleのAPIの宣言と、1行ずつ突き合わせる**（存在しないAPI・引数ラベルの違いが、CI往復の最大の原因）。SwiftVLCは `gh api "repos/harflabs/SwiftVLC/contents/<path>?ref=v1.1.0-beta.14"` で読む。
- `VLCChatCore` のテストは、手計算で期待値を検算してから書く。テスト名・コメントは、評価している条件に合わせる（00 項目15）。**演算子や分岐を変えるとテストが失敗するか**を確かめる。
- 小さく作ってpush→CIを素早く回す。一度に全部書かず、①Package（5節）とテスト → ②`App/` の骨格（6.1〜6.3節・画面の最小）→ ③ロック画面（6.4節）→ ④診断・ログ（6.5節）の順にコミットし、毎回CIを通す。

## 10. リスク

- **コンパイルの往復：** `MediaPlayer` のAPI（2節の未確認）は、書いた後にCIで初めて確かめられる。型名・ラベルの違いは、ログから直す。
- **ロック画面の表示（U1・U2）：** 「10秒戻る・進む」が出ない、位置がずれる、可能性がある。ずれが出たら、`nowPlayingInfo` を、60秒ごと・復帰時に再同期する。
- **PiPとの競合（U3・U4）：** PiPの窓の操作とロック画面の操作が、状態をずらす可能性がある。`stateTransitions` を一次情報にする設計（D4）で吸収する。
- **シークの補間（U6）：** 4K・AV1でシークが遅いとき、シーク直後の古い通知で位置が戻る可能性がある。`seekSettleTimeout`（2.0秒）で吸収するが、足りなければ調整する。
- **SwiftVLCは若く、メンテナは実質1人。** ベータを固定しているので、不具合は自分で回避する必要がある（M0から）。
- M1の結果が、Issue #1・#3 の前提を変える場合は、計画を作り直す。

## 11. 確定した事項（ユーザーの決定・Issue #3 の「決定事項」）

- 音声セッションはアプリ管理。自動PiPは常にオン。
- SwiftVLCは `1.1.0-beta.14` で固定のまま。アプリのSwift言語モードは5のまま。
- 位置の補間は、「最後の通知のメディア時刻＋経過時間×再生速度」。
- ブックマークはM1では使わない（M3）。
- AV1・VP9はCPUデコードのみ。M1では、解像度・コーデックによる制限や警告は入れない。
- ユーザーの指示（2026-10-14）：ステップごとの確認は不要。レビューの指摘の採否はClaudeが判断して回す。
