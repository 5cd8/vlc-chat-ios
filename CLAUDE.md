# vlc-chat-ios

iPhone向けのチャットリプレイ付き動画プレーヤー（vlc-with-chat）。要件は Issue #1、用語は [CONTEXT.md](CONTEXT.md)。Swift / SwiftUI ＋ SwiftVLC。Macは無く、ビルドはGitHub Actions（macOSランナー）、配布は署名なしipa＋SideStore、動作確認はiPhone実機（人の手）で行う。

## 作業の運用（このリポジトリ固有）

- **実装計画（`design-docs-for-ai/`）は feature ブランチにだけ載せる。** 独立レビュアー・新しいセッションが読むため、ブランチ上ではコミットする。**マージ前の最後のコミットで `git rm` する。** `main` には載せない。
- **マージは squash だけ**（設定で、マージコミットとrebaseマージは無効）。計画書が `main` の履歴に残らないようにするため。squash後のコミットメッセージはPR本文から作るので、PR本文に「なぜ」（変更の意図・見つけた不具合と修正・動作確認結果）を書く。
- **計画書の判断理由のうち残すべきものは、コードコメントかPR本文へ移す。** 計画書はマージ前に消えるので、コードのコメントやREADMEから計画書を参照しない。
- `docs/adr/`・`docs/issue-draft.md`・`user-prompt/` はgit管理しない（`.gitignore`）。ADRの内容をコメントやドキュメントから参照せず、理由はその場に直接書く。
- マージはユーザーが行う。PRの作成は、ユーザーの指示があってから。

## 実機確認

- 確認項目は、計画にまとめて回数を減らす。診断表示とログの共有（アプリ内）を手がかりにする。
- 署名なしipaは、GitHub Actionsが作ってReleasesに載せ、PCのiloader（v2.3.7）の「Import IPA」で入れる（SideStoreのAppleログインが障害中のため。直れば「ファイルから取り込み」でもよい）。無料のApple IDなので、署名は7日で切れ、同時に入れられるアプリは3つまで。
