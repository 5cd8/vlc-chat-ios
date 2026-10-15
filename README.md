# vlc-chat-ios

動画の再生に同期してチャットリプレイを表示する、iPhone向けのネイティブアプリ（vlc-with-chat）。PC版 [vlc-chat](https://github.com/5cd8/vlc-chat) のiOS版にあたる。

- 要件：Issue #1
- 用語：[CONTEXT.md](CONTEXT.md)
- ブラウザ版（凍結）：[vlc-chat-pwa](https://github.com/5cd8/vlc-chat-pwa)

状態：M0（実現性の確認）が済み、M1（再生の土台：再生・シーク・速度・PiP・ロック画面の操作・診断ログ）を実装中。

## ビルド

Macが無い環境で開発しているため、ビルドはGitHub Actions（`.github/workflows/build-ipa.yml`、`macos-26`）で行う。

- `project.yml`（XcodeGen）から `VLCWithChat.xcodeproj` を生成する。`.xcodeproj` はコミットしない。
- `scripts/make-ipa.sh` が署名なしipa（`vlc-with-chat-unsigned.ipa`）と、`ldid -S` で偽署名をかけた同じビルド（`vlc-with-chat-fakesigned.ipa`）を作る。実機へは、iloader（PC）またはSideStoreが署名してインストールする。
- タグ `m<M>-<n>`（例：`m1-1`）をpushすると、2つのipaとLGPL-2.1の全文をReleaseに載せる。
- ロジックは `Packages/VLCChatCore` に分け、`swift test --package-path Packages/VLCChatCore` でテストする。このPackageは `SwiftVLC` に依存させない（libVLCのコピーがプロセス内に2つできると未定義動作になるため）。

