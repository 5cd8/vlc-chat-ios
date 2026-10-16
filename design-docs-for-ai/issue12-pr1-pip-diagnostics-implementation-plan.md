# Issue #12 第1段階 映像トラック情報のログ（PiP診断） 実装計画

対象Issue: https://github.com/5cd8/vlc-chat-ios/issues/12 （アシスタントが起票したIssue。要件の情報源はIssue本文とコメントであり、本計画は要約・言い換えをしない。**本文の「段階的な進め方（2026-10-16 確定）」の第1段階だけを実装する**）
スコープ: 動画を開いたときの映像トラックの情報（コーデック・解像度・フレームレート）をログに残し、`PiP可 変化` のログにも添える。**挙動は変えない。** 非ゴール: PiPが使えない原因の特定・対策、症状1（PiP中の自動進行でPiPが消える）の対策、診断シートの表示追加。
PRは `Refs #12`（`Closes` にしない。第2段階が残る）。
依頼プロンプト: `user-prompt/202610161500_issue12_phase1.md`（git管理しない）
作業ブランチ: `feature/issue-12-pip-diagnostics`（`origin/main` から切る）

本書は、本セッションの文脈を持たない別のAIがそのまま実装に使うことを想定している。

## 0. 前提・読み替え

- 開発機はWindowsで、Mac・Xcodeは無い。コンパイルの確認はGitHub Actions（`macos-26`）、実行の確認はユーザーのiPhone 16（iOS 26.6.2）の実機だけ。pushしてCIのログ（`gh run view <id> --log-failed`）を読む。
- 読み替え（00 項目30）：「ブラウザ確認」は**iPhone実機での確認**に読み替える。実機確認を頼むときは、署名なしipaの入手先（Releasesのタグ `m3-<n>` のページ。このIssueはどのマイルストーンにも属さないので、直近の `m3-4` の次の `m3-5` にする）と使うファイル（`vlc-with-chat-unsigned.ipa`、入らなければ `vlc-with-chat-fakesigned.ipa`）を書く。インストールはPCのiloaderの「Import IPA」。タグを切るのは、ユーザーの指示があってから。
- 設計判断の理由は、コードのコメントとPR本文に直接書く。この計画書はマージ前に削除するので、コードのコメントから参照しない。

## 1. 確認済みの一次情報

| 事実 | 出典 |
|---|---|
| 動画ごとのPiPの可否に偏りがある。遊戯王のWebM（7GB）は `PiP toggle` が 56/56 で `notPossible`（build=90）。短いWebMは 31/35、GTA5のMP4は 12/15、あぺっくすのMP4は 1/15、VP9のMKVは 0/2。ログに映像のコーデック・解像度が無く、原因を特定できない | Issue #12 のコメント https://github.com/5cd8/vlc-chat-ios/issues/12#issuecomment-6207960910 |
| `PiPController.isPossible` は、AVKitの `AVPictureInPictureController.isPictureInPicturePossible` を写した値。偽の理由はアプリのログに出ない | SwiftVLC v1.1.0-beta.14 `Sources/SwiftVLC/PiP/PiPController.swift` の `updatePiPPossible` |
| `Player.videoTracks: [Track]`（`public internal(set) var`）が取れる。`Track` に `codecString: String?`（FourCC）、`width: Int?`、`height: Int?`、`frameRate: Double?`、`isSelected: Bool`、`bitrate: Int` がある | SwiftVLC `Sources/SwiftVLC/Player/Player.swift`（107行）、`Sources/SwiftVLC/Media/Track.swift` |
| `PlayerEvent.tracksChanged`（引数なし）がある。SwiftVLCの内部は、このイベントの処理で `videoTracks` を更新する。**アプリが同じイベントを受けた時点で、`videoTracks` が更新済みかは保証されない**（内部の更新とイベント配送の順序は不定） | SwiftVLC `Player+Events.swift`（`.tracksChanged` の処理）、`PlayerEvent.swift` |
| 現在、`PlayerModel.startObserving()`（423行付近）のイベントの絞り込みに `.tracksChanged` は無い。`.voutChanged` は通る | `App/Player/PlayerModel.swift` |

## 2. 変更内容

変更するファイルは `App/Player/PlayerModel.swift` のみ。

1. **状態を足す**：`@ObservationIgnored private(set) var videoSummary = "-"`（直近の映像トラックの要約。`PiP可 変化` のログに添える）。
2. **要約の関数を足す**：`private func refreshVideoSummary(trigger: String)`。
   - `player.videoTracks` から文字列を作る。トラックごとに `"\(codecString ?? "?") \(width)x\(height) \(fps)fps"`（`width`・`height` が `nil` なら `?`。`fps` は `frameRate` を `String(format: "%.2f", …)`、`nil` なら `?`）。選択中のトラック（`isSelected`）には先頭に `*` を付ける。複数あれば ` / ` で連結。トラックが0本なら `"なし"`。
   - 前回と同じ文字列なら何もしない（重複ログを出さない）。違えば `videoSummary` を更新し、`AppLog.write("映像 トラック \(summary) 契機=\(trigger)")`。
3. **呼ぶ契機**：
   - `handle(_:)` の `.voutChanged(let count)`（472行付近）で、`count > 0` のとき `refreshVideoSummary(trigger: "voutChanged")`。トラックの確定後に映像出力が始まるため、更新が済んでいる可能性が高い。
   - イベントの絞り込み（428行付近）に `.tracksChanged` を足し、`handle(_:)` に `case .tracksChanged: refreshVideoSummary(trigger: "tracksChanged")` を足す。
   - 2つの契機のどちらでも、更新が済んでいない（古い要約になる）可能性があるので、**2つとも入れる**。同じ文字列は重複しないので、後から更新された値だけがログに出る。
4. **動画を開くとき**：`open(url:)` の成功時の初期化（`currentIdentity = …` の付近、132行）で `videoSummary = "-"` と、重複判定用の前回値の消去を行う（前の動画の要約が、新しい動画のログに混ざらないようにする）。失敗した経路と `resetAfterDetach()`（247行）でも同じく消す。
5. **`PiP可 変化` のログに添える**（382行）：`… \(self.stateDescription) 映像=\(self.videoSummary)`。
6. **コメント**：`videoSummary` の宣言に、**なぜ残すか**（PiPが使える動画・使えない動画を、コーデック・解像度で突き合わせるため。Issue #12 の第1段階）と、原因の対策が決まったら配線ごと消す暫定の診断であることを書く（00 項目27）。

## 3. 設計判断

| 判断 | 採用案と理由 | 採らなかった案 |
|---|---|---|
| 契機を `voutChanged` と `tracksChanged` の2つにする | `videoTracks` の更新とイベント配送の順序が保証されないため。同じ文字列は出さないので、重複しない | `tracksChanged` だけ（古い値を読む恐れ）。`Task.sleep` で待ってから読む（根拠のない待ち時間） |
| 要約を `PiP可 変化` のログに添える | ログの突き合わせを1行で済ませるため（`選択` 行と時刻で探し合わなくてよい） | 別の行を探して突き合わせる（手間が増え、ミスしやすい） |
| 診断シートに表示を足さない | スコープ外。ログで足りる | 診断シートの行を足す |
| 単体テストを書かない | 文字列の組み立てだけで、SwiftVLCの `Track` はアプリ側の型で、`VLCChatCore` に出せる規則が無い | `Track` を写す型をCoreに作る（ログ1行のために型を増やす過剰設計） |

## 4. 品質管理・動作確認

- CIの `test`・`build` が成功すること。アプリのコードに起因する警告は残さない（成果物の `xcodebuild.log` で `warning:` を確認）。
- **実機確認（ユーザーの作業）**：
  1. 動画を開く。次のログが出る：`映像 トラック <コーデック> <幅>x<高さ> <fps>fps 契機=…`。
  2. 遊戯王のWebM、短いWebM、成功するMP4（あぺっくす）、GTA5のMP4を、順に開いて再生し、PiPのボタンを押す。結果が `PiP toggle 結果=accepted/notPossible` で残る。
  3. ログ（診断→ログを共有）を共有する。`PiP可 変化` の行の末尾に `映像=…` が付いている。
  4. 動画を開き直したとき、前の動画の要約が混ざらない。
- 第2段階（原因と対策の決定）は、このログの突き合わせの結果を見てから別の計画で行う。

## 5. リスク

- `videoTracks` の更新が遅く、どちらの契機でも古い値（空）になると、`映像 トラック なし` と出る。そのときは、契機に `.lengthChanged` を足すか、PiPのボタンを押したときにも読む（`PiP toggle` のログに添える）ことを検討する。
