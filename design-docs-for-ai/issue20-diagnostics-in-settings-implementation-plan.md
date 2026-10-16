# Issue #20 実装計画：診断を設定メニューへ移し、チャット欄を広げる

- 対象Issue: https://github.com/5cd8/vlc-chat-ios/issues/20 （アシスタントが対話で要件を確定して起票したIssue。要件はIssue本文を正とし、ここでは言い換えない）
- スコープ: Issue全体（PRは1本）。非ゴール: Issue本文の「非ゴール」のとおり。
- ユーザーの指示（2026-10-17、チャットで明示）: 図解（ワークフローのステップ3）は省略。このIssueのPRのマージに、事前の許可は不要（CLAUDE.md の「マージはユーザーが行う」は、この指示で満たされる）。マージはsquashだけ。マージ前の最後のコミットで、この計画書を `git rm` する。

## 現状（読んだコード）

- `App/Views/PlayerScreen.swift:29` が `DiagnosticsView(app: app)` を、`VStack` の最下部に置く。
- `App/Views/DiagnosticsView.swift`（全体）：`Button`（1行の要約。`summary`）＋ `.sheet(isPresented: $showsSheet) { detail }`。`detail` は `NavigationStack { ScrollView { ... } }`、タイトル「診断」、右上に `ShareLink(items: AppLog.shared.existingFileURLs) { Text("ログを共有") }`、`.presentationDetents([.medium, .large])`。`line(_:_:)` が1行を作る。
- `App/Views/SettingsView.swift`：シート。`NavigationStack { Form { Section("再生") / Section("絵文字ライブラリ") / Section("このアプリについて") { NavigationLink("ライセンス") { LicensesView() }; LabeledContent("バージョン", ...) } } }`。
- `App/Views/ControlsView.swift:19` `VStack(spacing: 12)`、`:63` `.padding(12)`。
- `DiagnosticsView` の参照は `PlayerScreen.swift:29` の1箇所だけ（`grep -rn DiagnosticsView App project.yml`）。

## 変更

### 1. `App/Views/DiagnosticsView.swift`
設定の `NavigationLink` の行き先になる、診断の中身だけのビューに作り替える。
- 構造体名は `DiagnosticsView` のまま。`@State showsSheet`、`Button` の1行、`summary`、`.sheet`、`NavigationStack`、`.presentationDetents` を削除する。
- `body` は `return` を書かずに、現在の `detail` の `ScrollView { VStack { ... } }` に、`.navigationTitle("診断")`・`.navigationBarTitleDisplayMode(.inline)`・右上の `ShareLink`（`.toolbar` の `ToolbarItem(placement: .topBarTrailing)`）をそのまま付ける。表示する項目と順序は変えない。
- `let model = app.playback` と `diagnostics` のローカル変数は、`body` の先頭に移す。
- 先頭のドキュメントコメントを「設定から開く診断。メモリ・状態・エラー・間隔・ログの共有」に直す。

### 2. `App/Views/SettingsView.swift`
- `Section("このアプリについて")` の `NavigationLink("ライセンス")` の下に `NavigationLink("診断") { DiagnosticsView(app: app) }` を足す。
- 診断を開いたあとの右上は、診断画面の「ログを共有」になる。設定の「閉じる」ボタンは `NavigationStack` のルートの画面でのみ出るので、診断画面の中では出ない（戻るは標準の「戻る」）。この挙動は `LicensesView` と同じ。
- シートの高さは今のまま（`.medium, .large`）。診断は項目が多く縦に長いので、`.medium` のままだとスクロールになる。許容する。

### 3. `App/Views/PlayerScreen.swift`
- 29行目の `DiagnosticsView(app: app)` を削除する。`VStack(spacing: 0)` の残りは変えない。

### 4. `App/Views/ControlsView.swift`
- 19行目 `VStack(spacing: 12)` → `VStack(spacing: 8)`、63行目 `.padding(12)` → `.padding(.horizontal, 12).padding(.vertical, 8)`。左右は今のまま（シークバーの幅とボタンの位置を変えない）。ボタンの大きさ・配置・フォントも変えない。
- 見積り：行間2か所で8pt、上下の余白で8pt、合計16pt。最下部の1行（`caption2` 約13pt ＋ `padding(.vertical, 6)` で約25pt）と合わせ、チャット欄は約40pt高くなる。

### 5. `App/Views/ChatPanelView.swift`
- 最下部の1行が無くなると、チャット欄の下端がホームインジケータの領域（セーフエリア）に接する。背景の `Color.black`（18行目）が下のセーフエリアに食い込まないと、下に端末の背景色（ライトモードでは白）の帯が出る。`Color.black` に `.ignoresSafeArea(.container, edges: .bottom)` を付け、内容（一覧）は今のままセーフエリアの内側に置く。
- 現状でも、診断の1行の下（セーフエリア）は端末の背景色が見える。今回の変更でチャット欄の下端がセーフエリアに接するため、ここで直す。
- 採らなかった案：一覧ごとセーフエリアの外に出す。最後の行がホームインジケータに重なって読みにくくなるため。

## 設計判断

| 判断 | 採用 | 採らなかった案と理由 |
|---|---|---|
| 診断の置き場 | 設定の `NavigationLink` の先（Issueで確定） | 設定のフォームに直接並べる：設定が長くなる（Issueで確定） |
| `DiagnosticsView` の扱い | 同じ名前で中身だけにする | 別名の新しい型を作る：参照が1箇所だけで、旧型を残す理由が無い |
| エラーの印 | 付けない（Issueで確定） | 歯車に点を付ける：Issueで却下済み |

## テスト方針

- 変更はビューの構成だけで、`VLCChatCore` に置くべきビジネスロジックは無い。新しい単体テストは足さない。既存の `swift test`（214件）が通ることを確認する。
- 実機が無い環境のため、ビルドはCI（警告0・エラー0）で確かめる。

## 品質管理

- CI（`build-ipa`）が成功し、警告が0であること（`appintentsmetadataprocessor` の既存の警告を除く）。
- `grep -n "showsSheet\|private var summary\|presentationDetents\|NavigationStack" App/Views/DiagnosticsView.swift` が何も返さないこと（`summaryText` は残すので `summary` だけでは検索しない）。

## 動作確認（実機・人の手。タグ `m3-9` 以降のReleaseのipaをiloaderで入れる）

実行ファイルは、Releasesの `vlc-with-chat-unsigned.ipa`（ローカルにビルド出力は無い）。
1. 動画を開いた状態で、画面の最下部に診断の1行が出ないこと。チャット欄が、動画の下の操作パネルから画面の下端まで広がること。下端に白い帯が出ないこと（ライトモードの端末で確認）。
2. 歯車→設定→「診断」で、診断の項目が見え、右上の「ログを共有」で共有シートが出ること。診断を閉じて設定に戻れること。
3. 動画を開いていない状態でも、歯車（動画領域の右上）→設定→診断が開けること。
4. 操作パネルのボタン（前へ・10秒戻る・再生・10秒進む・次へ、ファイルを選択・プレイリスト・速度・PiP・設定）が押しにくくないこと。
5. チャット欄の下端：(a) 新着が来たとき最下部に追従し続け、最後の行がホームインジケータに隠れないこと。(b) 上へ遡ると追従が止まり、最下部まで戻ると再開すること。(c) チャット下端のスクロールと、ホームへ戻るスワイプがぶつからないこと。ダークモードの端末でも、下端の見た目を1回確認する。一覧の下端が初めてセーフエリアに接するための確認（`defaultScrollAnchor(.bottom)`・`onScrollGeometryChange`・`scrollTo(anchor: .bottom)` の挙動が変わり得る）。
6. 診断を開いたまま動画を再生しても、メモリや状態の表示が更新され続けること（`TimelineView` と1秒更新の `@Observable`）。
