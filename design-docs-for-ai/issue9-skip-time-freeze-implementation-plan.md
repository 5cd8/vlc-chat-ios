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

1. **解除の関数を足す**。`private func releaseStuckScrubbing(reason: String)`：`isScrubbing` が真のときだけ、`isScrubbing = false` にして `AppLog.write("操作 シークバー 掴んだままを解除 理由=\(reason) 掴んだ位置=\(scrubPosition)s 表示=\(shownPosition)s 時計=\(model.displayPosition(at: ProcessInfo.processInfo.systemUptime))s")` を残す（Issueの「確認したいこと」の、表示している位置と `displayPosition` の値）。偽のときは何もしない（ログを出さない）。
2. **10秒送り／戻りのボタン**（25・31行）の処理で、`model.skip(seconds:)` の前に `releaseStuckScrubbing(reason: "10秒送り")`／`("10秒戻り")` を呼ぶ。ボタンを押したということは、つまみのドラッグは終わっているはずなので、押した操作を優先して解除する。
3. **画面の状態が変わったとき**：`.task(id: scenePhase)`（96行付近）の先頭、`guard scenePhase != .background` の**前**で `releaseStuckScrubbing(reason: "scenePhase")`。背面に入るときも解除する。
4. **既存の `.onChange(of: model.openCount) { isScrubbing = false }`（106行）も `releaseStuckScrubbing(reason: "開き直し")` に置き換える**。解除の経路を1つにして、ログも同じ形で出す。
5. **解除の後に遅れて届く「離した」通知は捨てる**。`Slider` の `onEditingChanged`（75〜82行）の先頭で `let wasScrubbing = isScrubbing` を取り、`!editing` のとき `wasScrubbing` が偽なら、`shownPosition` の更新も `model.seek` もしない（解除した後に古い `scrubPosition` へシークして、ボタンで進めた位置から戻されるのを防ぐ）。通常のドラッグでは、離す時点で `isScrubbing` は必ず真なので、挙動は変わらない。
6. **コメント**：`isScrubbing` の宣言（13行）か `seekBar` の説明コメント（60〜66行）に、**なぜ解除を足したか**（「離した」通知が失われると真のまま残り、時刻とつまみが固まる。M1で実際に起きた。10秒送り連打の固まりも同じ原因と疑っているが未確認）を数行で書く。60〜64行の既存コメント（`TimelineView` の中の `Slider`）とは重複させず、解除の関数の説明に置く。

## 3. 設計判断

| 判断 | 採用案と理由 | 採らなかった案 |
|---|---|---|
| 解除の契機 | ボタン押下と `scenePhase` の変化。原因が未確認でも、ユーザーが次に取る操作で復帰でき、実際に働いたときだけログに残るので、原因が `isScrubbing` だったかを後から確かめられる | 一定時間で自動解除（長いドラッグを途中で切る危険）。`DragGesture` で掴んでいる状態を自前で追う（`Slider` と二重になり、M1で外した作りに戻る） |
| `PlaybackClock` | 変えない。通知が届いている限り2秒で追従する（上の表） | シーク待ち中も補間を進める（連打中の表示は滑らかになるが、Issueの症状と別。非ゴール） |
| 単体テスト | 書かない。状態は `ControlsView` の `@State` で、`VLCChatCore` に出せる規則が無い。Issueの「再現手順が分かれば `PlaybackClock` で再現できるか検討」は、再現手順が未確定のため今回の対象外 | 状態をCoreの型に切り出す（解除の1行のために型を増やす過剰設計） |

解除は**再発の防止ではなく、次の操作での復帰**である。最後の1回のタップの直後に掴みが残れば、もう1回ボタンを押すまで固まったままになり得る（防ぐには、固まる原因そのものを特定する必要があり、ログで確かめる）。

## 4. 品質管理・動作確認

- CIの `test`・`build` が成功すること。アプリのコードに起因する警告は残さない（成果物の `xcodebuild.log` で `warning:` を確認）。
- **実機確認（ユーザーの作業）**。入れるipaは Releases の `vlc-with-chat-unsigned.ipa`（入らなければ `vlc-with-chat-fakesigned.ipa`）。PCのiloaderの「Import IPA」で入れる。
  1. 動画を再生し、10秒進む・戻るを速く20回ほど連打する。時刻とつまみが、連打中も連打後も実際の位置に追従するか見る。**この変更では「起きない」を保証しない**。連打後に固まったら、次の切り分けを先にする。
     - チャット欄が流れているか、診断シートの「時間」が進んでいるか。**進んでいれば時計は正常**で、原因は `ControlsView` の中（`isScrubbing`、または更新ループ（`.task(id: scenePhase)`）の停止）に絞れる。どちらも止まっていれば、時計側。
     - 止まった時刻が 0:00 か、途中の時刻かを記録する（0:00 なら時計が `.stopped`）。
     - その後、もう1回ボタンを押して復帰するか。
  2. ログ（診断→ログを共有）を共有する。`操作 シークバー 掴んだままを解除` が出れば、原因は `isScrubbing`。出ずに止まっていたなら、原因は別（更新ループの停止など）。
  3. 手順1・2の後で、**わざと**つまみを掴んだままボタンを押す（指2本）。時刻とつまみが追従に戻り、つまみを離しても古い位置へ戻されない。このときも解除のログが出るので、手順2の判定とは混ぜない（ログの時刻で見分ける）。
  4. 通常のシーク（つまみのドラッグ）、一時停止中のシーク、背面から戻った後の表示に退行が無い。
- 再現手順が確定していないため、**この変更で直ると断言しない**。PR本文にもそう書く。

## 5. リスク

- 原因が `isScrubbing` でなければ、症状は直らない。ログの行が出ないことで判別できる。
- `isScrubbing` 以外にも、時刻とつまみが同時に固まり映像が進む経路がある：`ControlsView` の更新ループだけが止まる場合（ループが抜けるのは、キャンセルされたときか、開始時点で `.background` のときだけ。再開は `scenePhase` が変わったときだけ）。今回の解除では直らない。手順1の切り分け（チャット欄・診断の時間が進んでいる）と、解除のログが出ないことの組み合わせで見分ける。
- 時計側の原因は可能性が低い（`.stopped` 以外では、届いた通知が最大2秒で採用される）。ただし、n=41・n=19 のログが「固まった回のもの」かは特定できていないので、断定はしない。
