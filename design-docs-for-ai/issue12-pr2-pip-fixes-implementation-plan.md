# Issue #12 第2段階（対策） PiP中の先行切り替えと、不可のときの自動の開き直し 実装計画

対象Issue: https://github.com/5cd8/vlc-chat-ios/issues/12 （アシスタントが起票したIssue。要件の情報源はIssue本文とコメントであり、本計画は要約・言い換えをしない。**コメント https://github.com/5cd8/vlc-chat-ios/issues/12#issuecomment-6222848409 （実機ログの結果と対策案）と https://github.com/5cd8/vlc-chat-ios/issues/12#issuecomment-6222899718 （ユーザー確定の方針）を実装の根拠にする**）
前提: 第1段階（PR #15）が `main` に入っていること。このブランチ（`feature/issue-12-pip-experiments`）には、診断のコミット（継続イベントのログ `PiP継続 …`、実験ボタン、`pipViewID`、`PiPExperiment`）が既にある。
スコープ: ①PiP中の自動進行を、動画の終わりの手前で先行して次へ進める ②切り替えの後に `isPossible` が偽なら、同じ動画を自動で1回だけ開き直す ③実験ボタン等の暫定の診断を消す（継続イベントのログは残す）。非ゴール: PiPでない通常の自動進行の変更、README・CONTEXT.mdの変更、SwiftVLCの変更。
PRは `Closes #12`（症状1・2とも対策が入るため）。実機で直らなければ、PR本文を `Refs #12` に直す。
依頼プロンプト: `user-prompt/202610171000_issue12_phase2_pr2.md`（git管理しない）
作業ブランチ: `feature/issue-12-pip-experiments`（診断のコミットを含むので、このブランチで続ける）

本書は、本セッションの文脈を持たない別のAIがそのまま実装に使うことを想定している。

## 0. 前提・読み替え

- 開発機はWindowsで、Mac・Xcodeは無い。コンパイルの確認はGitHub Actions（`macos-26`）、実行の確認はユーザーのiPhone 16（iOS 26.6.2）の実機だけ。pushしてCIのログを読む。
- 読み替え（00 項目30）：「ブラウザ確認」は**iPhone実機での確認**に読み替える。ipaはReleasesのタグ `m3-<n>`（直近は `m3-6`、次は `m3-7`）。使うファイルは `vlc-with-chat-unsigned.ipa`（入らなければ `vlc-with-chat-fakesigned.ipa`）。インストールはPCのiloaderの「Import IPA」。タグを切るのは、ユーザーの指示があってから。
- 設計判断の理由は、コードのコメントとPR本文に直接書く。この計画書はマージ前に削除するので、コードのコメントから参照しない。

## 1. 確認済みの一次情報（実機ログ m3-6、build=105）

| 事実 | 出典 |
|---|---|
| 手で「次へ」「前へ」（再生の途中の差し替え）では、PiP中でも `PiP継続 rebuilding → restored` が、40回以上すべて 0.02〜0.36秒で成功し、PiPは保たれた | Issue #12 のコメント https://github.com/5cd8/vlc-chat-ios/issues/12#issuecomment-6222848409 |
| 自動進行（動画の終わり）では、4/4回、PiPが止まった。順序：`映像 トラック なし 契機=voutChanged`（終端でlibVLCが映像出力を壊す）→ 1〜3ms後に `PiPイベント willStop … cause=userClosed`／`mediaEnded` → `再生 終了`（`endReached`）→ 次を開く → `cause=controllerReplaced`。終端で映像出力が壊れた後の差し替えは、SwiftVLCの保持の対象外 | 同上 |
| 不可（`isPossible=false`）のとき、「一時停止→再開」（3回）と「PiPControllerを作り直す」（2回）は戻らず、**「同じ動画を開き直す」は3回とも0.2〜0.6秒で `isPossible=true` に戻り、その後PiPが開始できた** | 同上 |
| 不可になるのは、PiPが止まっている状態からVP9／AV1に切り替えたとき。H.264へは必ず可 | 同上 |
| `PlayerModel` は `recordTask`（5秒ごと）が `init` で動く。`clock.mode`・`clock.position(at:)`・`duration` を持つ。`pip: PiPController?`（`isActive`／`isPossible`）。`onEnded` は `endReached` から呼ばれ、`AppModel.handlePlaybackEnded` が記憶を消して `advance(stopsWhenNone: true)` を呼ぶ | `App/Player/PlayerModel.swift`、`App/AppModel.swift` |

## 2. 変更内容

### 2.1 Core：先行切り替えの規則（`Packages/VLCChatCore`）
新規 `EarlyAdvanceRule.swift`：

    public enum EarlyAdvanceRule {
      /// 終わりまで残りこの実時間（秒）になったら、先行して次へ進む。値は実機の `先行切り替え 残り=` のログで削れるか確かめる。
      public static let marginSeconds: TimeInterval = 0.5
      /// 再生が始まってすぐの誤発火を防ぐ。
      public static let minimumPlayed: TimeInterval = 1.0
      public static func shouldAdvance(position: TimeInterval, duration: TimeInterval?, rate: Double) -> Bool
    }

- `duration` が nil または 0 以下 → 偽。`rate <= 0` → 偽。
- 残り（`duration - position`）が 0 以上 かつ `marginSeconds * rate` 以下 かつ `position >= minimumPlayed` → 真。残りが負（長さを超えた）なら偽（`endReached` に任せる）。

テスト（`EarlyAdvanceRuleTests.swift`。手計算）：長さ100・rate 1・margin 0.5 で、position 99.4 → 偽（残り0.6）、99.5 → 真（残り0.5＝境界）、99.9 → 真、100.1 → 偽（残り負）。rate 2 → 閾値1.0（position 98.9 → 偽、99.0 → 真）。長さ nil／0 → 偽。rate 0 → 偽。position 0.5・長さ1.2 → 偽（minimumPlayed 未満）。

### 2.2 `PlayerModel`：先行切り替えの検知と、不可のときの判定
1. **先行切り替え**：`@ObservationIgnored var earlyAdvanceEnabled: (() -> Bool)?`、`@ObservationIgnored var onEarlyAdvance: ((VideoIdentity?) -> Void)?`、`private var earlyAdvanceFired = false`（`open` の成功時の初期化で偽に戻す）、`@ObservationIgnored private var earlyAdvanceTask: Task<Void, Never>?`（`init` で起動。`recordTask` と同じ作り）。0.1秒ごとに、次がすべて真なら発火する：`clock.mode == .playing`、`pip?.isActive == true`、`!earlyAdvanceFired`、`earlyAdvanceEnabled?() == true`、`EarlyAdvanceRule.shouldAdvance(position: clock.position(at: now), duration: duration, rate: clock.rate)`。発火したら、`earlyAdvanceFired = true`、`hasReachedEnd = true`（`open` 冒頭の `recordPosition()` が終端の位置を記録し直さないため。`open` の成功時に偽に戻る）、`AppLog.write("先行切り替え 残り=\(String(format: "%.2f", duration - position))s \(title ?? "-")")`、`onEarlyAdvance?(currentIdentity)` の順。
2. **不可のときの判定**：`func pipUnavailableAfterSettling() -> Bool`＝`pip != nil`、`pip?.isActive == false`、`pip?.isPossible == false`、`clock.mode == .playing`（再生中でなければ偽。一時停止中は開き直さない）。
3. **暫定の診断を消す**：`pipProbe` を削除する。`continuityTask`（継続イベントのログ）は**残す**（対策の効果を実機で確かめるため。コメントを「対策の確認用。不要になれば消す」に直す）。

### 2.3 `AppModel`
1. 配線（`init`）：`playback.earlyAdvanceEnabled = { [playlist, settings] in settings.autoAdvance && playlist.playlist.hasNext }`、`playback.onEarlyAdvance = { [relay] identity in relay.model?.handleEarlyAdvance(identity) }`。
2. `func handleEarlyAdvance(_ identity: VideoIdentity?)`：`resume.remove(identity)`（最後まで再生した扱い）→ `advance(stopsWhenNone: false) { self.playlist.nextStep(excluding: $0) }`（手で押した「次へ」と同じ経路。PiP中の差し替えは `PiP継続` で保たれる。開ける項目が無ければ何もせず、`endReached` に任せる）。
3. **開き直し**：`playItem(at:byUser:)` に引数 `isPiPRecovery: Bool = false` を足す。成功したら（`return true` の直前）、`!isPiPRecovery` のときだけ `schedulePiPRecovery(index:)`。
   - `@ObservationIgnored private var pipRecoveryTask: Task<Void, Never>?`。`schedulePiPRecovery` は前のタスクを `cancel()` して、新しい `Task { }`（メインアクター）を作る：`do { try await Task.sleep(for: .seconds(1.5)) } catch { return }` → `guard playlist.playlist.currentIndex == index, playback.pipUnavailableAfterSettling() else { return }` → `AppLog.write("PiP回復 開き直し …")` → `playItem(at: index, byUser: false, isPiPRecovery: true)`。1.5秒は、実機ログで不可が出るまでの時間（0.2〜0.6秒）に余裕を足した値。
   - 手でまた切り替えたとき（`playItem` の再呼び出し）は、`schedulePiPRecovery` が前のタスクを取り消すので、古い動画を開き直さない。
   - **開き直しは1回だけ**（`isPiPRecovery: true` の `playItem` は、次の開き直しを予約しない）。開き直しの2秒後に `playback.pipUnavailableAfterSettling()` を調べて、ログに結果を残す（`PiP回復 結果 …`）。
4. 暫定の診断を消す：`pipViewID`、`isExperimentRunning`、`runPiPExperiment`、`PiPExperiment.swift`、`DiagnosticsView` の実験ボタン、`PlayerScreen` の `.id(app.pipViewID)` を削除する。

## 3. 設計判断

| 判断 | 採用案と理由 | 採らなかった案 |
|---|---|---|
| 先行切り替えはPiP中だけ | PiPでないときは、今までどおり最後まで再生して次へ進む（最後の0.5秒を削らない） | 常に先行する（PiPでない通常の再生で、最後を削る） |
| 先行は残り0.5秒（実時間）、0.1秒間隔で検知 | ユーザーの要望（約1秒をもっと短く）。0.1秒間隔なので、最悪でも残り0.4秒で発火する。`timeChanged` の通知（約0.26秒）ではなく、補間した時計で見る。値はログ（`先行切り替え 残り=`）で実機で削れるか確かめる | 1秒（長い）。通知で検知（0.26秒の粗さで取りこぼす） |
| 開き直しの契機 | 切り替え後1.5秒の時点で `isPossible` が偽（PiP非表示・再生中）なら1回だけ | 常に開き直す（H.264でも映像が途切れる）。PiPボタンを押したときだけ（自動PiPに効かない。ユーザー確定の(a)ではない） |
| 継続イベントのログを残す | 対策が効いたかを実機のログで確かめるため | 消す（確認できない） |

## 4. 品質管理・動作確認

- CIの `test`・`build` が成功すること。アプリのコードに起因する警告は残さない。`swift test` に `EarlyAdvanceRuleTests` が入ること。
- **実機確認（ユーザーの作業）**：
  1. **症状1**：PiPを出した状態で、短い動画を最後まで再生して自動進行する。ログに `先行切り替え 残り=…s` → `PiP継続 rebuilding → restored` が出て、PiPが保たれる。`残り=` が0.5秒前後か（削れるか）を記録する。最後まで再生した動画の記憶が消えている（先頭から再生される）。
  2. **症状1の非PiP**：PiPなしの自動進行は、今までどおり最後まで再生してから次へ進む（`先行切り替え` が出ない）。
  3. **症状2**：PiPなしで、H.264 → VP9／AV1 の動画（mkv_vp9_4k_10min、遊戯王）へ「次へ」「前へ」で切り替える。不可になったときは、約1.5秒後に `PiP回復 開き直し` が出て、`isPossible=true` に戻る。ホームへ戻って自動PiPが開始する。
  4. 不可にならない動画（H.264）では、`PiP回復` が出ない。一時停止中は開き直さない。
  5. ログ（診断→ログを共有）を共有する。
- 直らない場合は、`先行切り替え` の残りと `PiP継続` を見て、閾値か契機を調整する。

## 5. リスク

- 動画の `duration`（libVLCの長さ）が実際の終端より長いと、先行の発火前に終端で映像出力が壊れる（従来どおりPiPが止まる）。ログの `先行切り替え` が出ない動画は、`duration` の誤差を疑う。
- 開き直しで映像が約0.5秒途切れる（VP9・AV1への切り替えで、よく起きる）。ユーザー確定の挙動。
- 開き直しは再生位置を復元する（`resumeLookup`）。直前の位置の記録は `open` 冒頭の `recordPosition()` が行うので、位置はほぼ変わらない（約1.5秒より前の動画では先頭付近に戻る）。
