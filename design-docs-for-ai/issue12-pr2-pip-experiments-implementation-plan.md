# Issue #12 第2段階（最初のPR） PiP継続イベントのログと実験ボタン 実装計画

対象Issue: https://github.com/5cd8/vlc-chat-ios/issues/12 （アシスタントが起票したIssue。要件の情報源はIssue本文とコメントであり、本計画は要約・言い換えをしない。**本文の「段階的な進め方」と「第2段階の確定事項」「第2段階の最初のPR（案）」を実装の根拠にする**）
前提: 第1段階（PR #15、`main` の `613cd69`）が `main` に入っていること。
スコープ: ①`pipContinuityEvents` の購読とログ ②診断シートの暫定の実験ボタン（一時停止→再開、同じ動画を開き直す、PiPの描画面を作り直す、今の `isPossible` を測る）と、押した2秒後の結果のログ。**対策そのものは入れない**（原因が分かってから別のPRで行う）。非ゴール: PiPが不可になる原因の修正、自動進行でPiPを保つ修正（次のPR）、README・CONTEXT.mdの変更。
PRは `Refs #12`（`Closes` にしない）。
依頼プロンプト: `user-prompt/202610161700_issue12_phase2_pr1.md`（git管理しない）
作業ブランチ: `feature/issue-12-pip-experiments`（`origin/main` から切る）

本書は、本セッションの文脈を持たない別のAIがそのまま実装に使うことを想定している。

## 0. 前提・読み替え

- 開発機はWindowsで、Mac・Xcodeは無い。コンパイルの確認はGitHub Actions（`macos-26`）、実行の確認はユーザーのiPhone 16（iOS 26.6.2）の実機だけ。pushしてCIのログ（`gh run view <id> --log-failed`）を読む。
- 読み替え（00 項目30）：「ブラウザ確認」は**iPhone実機での確認**に読み替える。実機確認を頼むときは、署名なしipaの入手先（Releasesのタグ `m3-<n>`。直近は `m3-5` なので、次は `m3-6`）と使うファイル（`vlc-with-chat-unsigned.ipa`、入らなければ `vlc-with-chat-fakesigned.ipa`）を書く。インストールはPCのiloaderの「Import IPA」。タグを切るのは、ユーザーの指示があってから。
- 設計判断の理由は、コードのコメントとPR本文に直接書く。この計画書はマージ前に削除するので、コードのコメントから参照しない。
- 追加するボタン・購読・`pipViewID` は**暫定の診断**。原因と対策が決まったら配線ごと消す（00 項目27）。コメントにそう書く。

## 1. 確認済みの一次情報

| 事実 | 出典 |
|---|---|
| 同じ `Player` で `load(_:)` してメディアを差し替えると、PiP中は `AVPictureInPictureController` を保ったまま、後続の映像出力に付け替える。後続が3秒以内に表示層を出さなければ `timedOut` で止める。**通常の停止やビューの破棄は保持されない**。進捗は `PiPController.pipContinuityEvents` で見える | SwiftVLC v1.1.0-beta.14 `Sources/SwiftVLC/SwiftVLC.docc/PictureInPicture.md`（「Same-player media replacement」） |
| `PiPContinuityEvent`（iOSのみ）は、`previousMediaGeneration`・`mediaGeneration`（`PlaybackGeneration`）、`controllerGeneration: UInt64`、`outcome: PiPContinuityOutcome`（`.rebuilding`／`.restored`／`.timedOut`）、`elapsed: Duration`（`.rebuilding` では0）を持つ。`PiPController.pipContinuityEvents: AsyncStream<PiPContinuityEvent>`。Direct PiP（libVLC所有でないコントローラ）では値が出ない | `Sources/SwiftVLC/PiP/PiPContinuityEvent.swift` |
| `PiPController.isPossible` はAVKitの `isPictureInPicturePossible` を写した値で、偽の理由はログに出ない | `PiPController.swift` の `updatePiPPossible` |
| 実機ログ（build=97）：PiPの可否は、動画ファイルの特性ではなく切り替えの履歴で変わる。同じ遊戯王の動画が、起動直後は可、「次へ」「前へ」の後は不可。H.264への切り替えは必ず可、VP9／AV1への切り替えは9回中7回が不可 | Issue #12 のコメント https://github.com/5cd8/vlc-chat-ios/issues/12#issuecomment-6208595547 |
| 現在のコード：`PlayerModel.attachPiP(_:)`（393行）が `pipTask`（PiPイベントのログ）と `possibleTask`（`isPossible` の変化のログ）を作る。`PlayerScreen` は `PiPVideoView(player, controller: $pip)`（64行）を動画を選ぶ前から常に置き、`.onChange(of: pip.map { ObjectIdentifier($0) })`（54行）で `attachPiP` を呼ぶ。**`PiPVideoView` を再生の後に作り直すと、SwiftVLCが既存の描画面を引き継いで自動PiPの設定が反映されないことがあった**（M1。`PlayerScreen.swift` のコメント） | `App/Player/PlayerModel.swift`、`App/Views/PlayerScreen.swift` |

## 2. 変更内容

### 2.1 継続イベントのログ（`App/Player/PlayerModel.swift`）
1. `@ObservationIgnored private var continuityTask: Task<Void, Never>?` を足す。
2. `attachPiP(_:)` の先頭の `pipTask?.cancel()`・`possibleTask?.cancel()` に並べて `continuityTask?.cancel()`。`guard let controller` の後に、`pipTask` と同じ形で購読する：
   `for await event in controller.pipContinuityEvents { AppLog.write("PiP継続 \(event.outcome) 経過=\(event.elapsed) 前世代=\(event.previousMediaGeneration) 後世代=\(event.mediaGeneration) 制御世代=\(event.controllerGeneration)") }`。型の値は `String(describing:)` 相当の補間で出す（`PlaybackGeneration` の公開プロパティに依存しない）。`self` は `[weak self]` で受ける。
3. コメント：なぜ残すか（自動進行・手動の差し替えで、SwiftVLCがPiPを保つ仕組みが働いたかを知るため。Issue #12 第2段階）と、暫定の診断で、原因と対策が決まったら配線ごと消すこと。

### 2.2 実験ボタン（暫定）
1. **`App/Diagnostics/PiPExperiment.swift`（新規）**：`enum PiPExperiment: String, CaseIterable { case pauseResume, reopenCurrent, recreateView, measure }`。表示名（日本語）を持つ（`pauseResume` = 「一時停止→再開」、`reopenCurrent` = 「同じ動画を開き直す」、`recreateView` = 「PiPの描画面を作り直す」、`measure` = 「今の可否を測る」）。
2. **`App/AppModel.swift`**：
   - `private(set) var pipViewID = UUID()`（`recreateView` が書き換える。`PlayerScreen` が `PiPVideoView` の `.id` に使う）。
   - `func runPiPExperiment(_ experiment: PiPExperiment)`：
     1. `AppLog.write("実験 \(experiment.title) 開始 \(playback.pipProbe)")`（`pipProbe` は 2.3）。
     2. 実験を実行する。`pauseResume`：`playback.pause()` → 0.5秒後に `playback.play()`。`reopenCurrent`：`playlist.playlist.currentIndex` があれば `playItem(at:byUser:false)`、無ければ `実験 対象なし` をログに出して終了。`recreateView`：`pipViewID = UUID()`。`measure`：何もしない。
     3. 2秒後に `AppLog.write("実験 \(experiment.title) 2秒後 \(playback.pipProbe)")`。
   - `Task { try? await Task.sleep(for: …) }` で待つ（メインアクターで）。実験は同時に1つだけ走らせる（`private var runningExperiment: Task<Void, Never>?` を持ち、新しく押したら前のを取り消す）。
3. **`App/Player/PlayerModel.swift`**：`var pipProbe: String`（`"isPossible=\(pip?.isPossible ?? false) isActive=\(pip?.isActive ?? false) \(stateDescription) 映像=\(videoSummary)"`）。
4. **`App/Views/PlayerScreen.swift`**：`PiPVideoView(player, controller: $pip)`（64行）に `.id(app.pipViewID)` を付ける。
5. **`App/Views/DiagnosticsView.swift`**：`detail`（`ScrollView` の中、`line(...)` の並びの後）に、`Section` 風の見出し「PiP実験（暫定）」と `ForEach(PiPExperiment.allCases)` の `Button(experiment.title) { app.runPiPExperiment(experiment) }` を足す。動画を開いていない（`app.playback.title == nil`）ときは、ボタンを `.disabled`。コメントに「暫定。原因と対策が決まったら消す」。

## 3. 設計判断

| 判断 | 採用案と理由 | 採らなかった案 |
|---|---|---|
| 実験の置き場所 | 診断シートの暫定ボタン（ユーザー確定）。1回の実機確認で全部試せ、結果が時刻つきでログに残る | 自動で順に試す（勝手に再生が止まる・開き直される）。ログだけ |
| `PiPVideoView` の作り直しを実験に含める | 「切り替え後の不可から戻るか」を試す手段として有力。ただしM1で自動PiPの設定が反映されない問題があったので、**実験専用**とし、挙動は `PiP継続` のログと合わせて見る | 含めない（有力な手段を試せない） |
| 継続イベントの値の出し方 | 補間で出す（公開プロパティの有無に依存しない） | `PlaybackGeneration.value` を直接読む（公開かが未確認） |
| 単体テストを書かない | SwiftVLCの型とUIの診断で、`VLCChatCore` に出せる規則が無い | — |

## 4. 品質管理・動作確認

- CIの `test`・`build` が成功すること。アプリのコードに起因する警告は残さない（`xcodebuild.log` の `warning:`）。
- **実機確認（ユーザーの作業）**。入れるipaは Releases の `vlc-with-chat-unsigned.ipa`。ログの `起動` 行に、新しいビルド番号が出れば入っている。
  - (a) **手で「次へ」**：遊戯王（AV1のWebM）など、不可になりやすい動画を含むプレイリストで、PiPを出した状態で「次へ」を押す。ログに `PiP継続 rebuilding` → `restored`（または `timedOut`）が出るか。PiPが保たれるか。
  - (b) **自動進行**：短い動画を最後まで再生し、PiPのまま次へ進む。`PiP継続` が出るか。`PiPイベント … cause=controllerReplaced` が出るか。
  - (c) **不可になったとき**：「次へ」「前へ」で不可になる動画（mkv_vp9_4k_10min、遊戯王）に切り替えた直後、診断シートで「今の可否を測る」「一時停止→再開」「同じ動画を開き直す」「PiPの描画面を作り直す」を、1つずつ押す。押すたびにログの `実験 … 開始` と `2秒後` の `isPossible` を見て、**何を押すと真に戻るか**を記録する。ボタンを押す前に、PiPが使えないことを確かめる（PiPのボタンを押して `notPossible`）。
  - ログ（診断→ログを共有）を共有する。
- 結果は #12 にコメントで記録し、対策（次のPR）を決める材料にする。

## 5. リスク

- `PiPVideoView` を作り直すと、自動PiP（ホームへ戻ったときに開始）が効かなくなることがある。実験が終わったら、アプリを再起動して元に戻す。
- `pipContinuityEvents` が一度も出ない場合（Direct PiPの扱い、または保持の対象外）は、それ自体が手がかり。「出なかった」ことをログの根拠として #12 に記録する。
