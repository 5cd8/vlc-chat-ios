# Issue #9 10秒送り／戻りの連打で時刻表示が止まる 実装計画

対象Issue: https://github.com/5cd8/vlc-chat-ios/issues/9 （アシスタントが起票したIssue。要件の情報源はIssue本文であり、本計画は要約・言い換えをしない。**末尾の「ヒアリングで確定した事項」「方針（確定）」を実装の根拠にする**）
スコープ: `ControlsView` の `isScrubbing` の解除のみ。非ゴール: `PlaybackClock` の変更、連打中の表示を滑らかにすること、診断表示の追加。
依頼プロンプト: `user-prompt/202610161200_issue9.md`（git管理しない）
作業ブランチ: `feature/issue-9-skip-time-freeze`（`origin/main` から切る）

本書は、本セッションの文脈を持たない別のAIがそのまま実装に使うことを想定している。

## 0. 前提・読み替え

- 開発機はWindowsで、Mac・Xcodeは無い。コンパイルの確認はGitHub Actions（`macos-26`）、実行の確認はユーザーのiPhone 16（iOS 26.6.2）の実機だけ。pushしてCIのログ（`gh run view <id> --log-failed`）を読む。
- 読み替え（00 項目30）：「ブラウザ確認」は **iPhone実機での確認**に読み替える。実機確認を頼むときは、署名なしipaの入手先（GitHub Releasesのタグ `m<M>-<n>` のページ）と使うファイルを書く。インストールはPCのiloaderの「Import IPA」。タグを切るのは、ユーザーの指示があってから（直近は `m3-3`）。
- 設計判断の理由は、コードのコメントとPR本文に直接書く。この計画書はマージ前に削除するので、コードのコメントから参照しない。

## 1. 原因の整理（一次情報：実機ログと現在のコード）

| 事実 | 出典 |
|---|---|
| 止まったとき、映像・音声は進み、時刻の文字とつまみだけが止まる。連打をやめても戻らない | Issue #9 の「ヒアリングで確定した事項」 |
| 連打（`jump(10)` が約0.2秒間隔で15〜20回）の後も `timeChanged` は約0.26秒間隔で届いている。連打後の集計 n=41（最後の連打から約11秒後）、n=19（約5.4秒後）は、経過時間÷0.26秒と一致する | `app-log.txt`（2026-10-16 02:41:44、02:42:46）。M3実機ログ |
| `PlaybackClock` は、通知を受けると、シーク待ち（`pendingSeek`）があっても `at - requestedAt >= 2秒` で必ず採用する（`noteMediaTime`）。通知が届いている限り、2秒以内に追従する | `Packages/VLCChatCore/Sources/VLCChatCore/PlaybackClock.swift` の `noteMediaTime` |
| 時刻の文字（`Text(Self.format(isScrubbing ? scrubPosition : shownPosition))`、`ControlsView.swift` 87行付近）とつまみ（`Slider` の `get: { isScrubbing ? scrubPosition : shownPosition }`、70行付近）は、**同じ `isScrubbing` で表示を切り替える**。更新ループ（`.task(id: scenePhase)`、97行付近）も `if !isScrubbing` のときしか `shownPosition` を更新しない | `App/Views/ControlsView.swift` |

結論：`isScrubbing` が真のまま残ると、時刻とつまみが同時に固まり、映像・音声は進む。報告された症状と一致する。時計側の原因は、ログから可能性が低い。`isScrubbing` を真にするのは `Slider` の `onEditingChanged(true)` だけで、偽に戻すのは `onEditingChanged(false)` と `.onChange(of: model.openCount)`（動画を開き直したとき）だけ（`ControlsView.swift` 75・106行付近）。「離した」通知が届かないと、真のまま残る。**連打で `Slider` が掴まれたのか、再描画で通知が失われたのかは未確認**。

## 2. 変更内容

変更するファイルは `App/Views/ControlsView.swift` のみ。

1. **解除の関数を足す**。`private func releaseStuckScrubbing(reason: String)`：`isScrubbing` が真のときだけ、`isScrubbing = false` にして `AppLog.write("操作 シークバー 掴んだままを解除 理由=\(reason)")` を残す。偽のときは何もしない（ログを出さない）。
2. **10秒送り／戻りのボタン**（25・31行）の処理で、`model.skip(seconds:)` の前に `releaseStuckScrubbing(reason: "10秒送り")`／`("10秒戻り")` を呼ぶ。ボタンを押したということは、つまみのドラッグは終わっているはずなので、押した操作を優先して解除する。
3. **画面の状態が変わったとき**：`.task(id: scenePhase)`（97行付近）の先頭で `releaseStuckScrubbing(reason: "scenePhase")`。背面に回る・戻るときに、掴んだままの状態は持ち越さない。
4. **コメント**：`isScrubbing` の宣言（13行）か `seekBar` の説明コメント（60〜66行）に、**なぜ解除を足したか**（「離した」通知が失われると真のまま残り、時刻とつまみが固まる。M1と10秒送り連打の実機で起きた）を数行で書く。

## 3. 設計判断

| 判断 | 採用案と理由 | 採らなかった案 |
|---|---|---|
| 解除の契機 | ボタン押下と `scenePhase` の変化。原因が未確認でも、ユーザーが次に取る操作で復帰でき、実際に働いたときだけログに残るので、原因が `isScrubbing` だったかを後から確かめられる | 一定時間で自動解除（長いドラッグを途中で切る危険）。`DragGesture` で掴んでいる状態を自前で追う（`Slider` と二重になり、M1で外した作りに戻る） |
| `PlaybackClock` | 変えない。通知が届いている限り2秒で追従する（上の表） | シーク待ち中も補間を進める（連打中の表示は滑らかになるが、Issueの症状と別。非ゴール） |
| 単体テスト | 書かない。状態は `ControlsView` の `@State` で、`VLCChatCore` に出せる規則が無い | 状態をCoreの型に切り出す（解除の1行のために型を増やす過剰設計） |

## 4. 品質管理・動作確認

- CIの `test`・`build` が成功すること。アプリのコードに起因する警告は残さない（成果物の `xcodebuild.log` で `warning:` を確認）。
- **実機確認（ユーザーの作業）**：
  1. 動画を再生し、10秒進む・戻るを速く20回ほど連打する。時刻とつまみが、連打中も連打後も実際の位置に追従する。
  2. 連打の途中でつまみに触れてしまったとき（掴んだまま離さない、指を滑らせる）も、次にボタンを押すと時刻とつまみが追従に戻る。
  3. 通常のシーク（つまみのドラッグ）、一時停止中のシーク、背面から戻った後の表示に退行が無い。
  4. 症状が再発したとき、ログ（診断→ログを共有）に `操作 シークバー 掴んだままを解除` が出るか。出れば原因は `isScrubbing`。出ずに止まるなら、原因は別なので報告する（診断を足して調べ直す）。
- 再現手順が確定していないため、**この変更で直ると断言しない**。PR本文にもそう書く。

## 5. リスク

- 原因が `isScrubbing` でなければ、症状は直らない。ログの行が出ないことで判別できる。そのときは、表示している位置と `displayPosition` の値を診断ログに足す（Issueの「確認したいこと」）。
