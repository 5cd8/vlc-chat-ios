# vlc-chat-ios

動画の再生に同期してチャットリプレイを表示する、iPhone向けのネイティブアプリ（vlc-with-chat）。PC版 [vlc-chat](https://github.com/5cd8/vlc-chat) のiOS版にあたる。

- 要件：Issue #1
- 用語：[CONTEXT.md](CONTEXT.md)
- ブラウザ版（凍結）：[vlc-chat-pwa](https://github.com/5cd8/vlc-chat-pwa)

状態：M0（実現性の確認）、M1（再生の土台）、M2（チャットと絵文字）、M3（プレイリストと設定）が済み。

## 動画・チャットを置く場所

- 動画とチャットは、アプリの `Documents`（「ファイル」アプリのこのアプリのフォルダ。ファイル共有で入れる）に置くことを想定している。M3の実機確認も、この場所だけで行った。
- iCloud Drive・外部ストレージ上のファイルを開くことは想定していない。選べて再生できる場合もあるが、再起動後にプレイリストの項目を開き直せるか（ブックマークの解決）、iCloud上でまだ端末に無いファイルの扱いは未確認で、動作を保証しない。

## 大きい動画とメモリ

大きい動画を開くだけで、アプリのメモリ（`phys_footprint`）が増える。チャットの有無には関係しない。実機（iPhone 16）で、動画だけを開いて約1分後に測った値：

| 動画 | サイズ | `phys_footprint` |
|---|---|---|
| mp4 | 32GB | 約676〜690MB |
| mp4 | 7.6GB | 約387〜430MB |
| mkv/webm（M1の長時間試験） | 7GB級 | 240〜261MB |
| mkv | 1GB級 | 約20MB増 |

- 32GBでも落ちずに再生できた。再生を続けても増え続けず、ほぼ横ばい（M1の93分試験）。
- 増加量は動画のサイズと並ぶ。libVLC（SwiftVLC 1.1.0-beta.14、libVLC 4.0.0-dev）が、大きなファイルのインデックス（mp4のmoovなど）や先読みに使う分と推測しているが、未確認。
- 50GB超の動画や、libVLCの先読みのオプションで抑えられるかは確かめていない。メモリ不足で落ちるときは、まず動画のサイズを疑う。

## ビルド

Macが無い環境で開発しているため、ビルドはGitHub Actions（`.github/workflows/build-ipa.yml`、`macos-26`）で行う。

- `project.yml`（XcodeGen）から `VLCWithChat.xcodeproj` を生成する。`.xcodeproj` はコミットしない。
- `scripts/make-ipa.sh` が署名なしipa（`vlc-with-chat-unsigned.ipa`）と、`ldid -S` で偽署名をかけた同じビルド（`vlc-with-chat-fakesigned.ipa`）を作る。実機へは、iloader（PC）またはSideStoreが署名してインストールする。
- タグ `m<M>-<n>`（例：`m1-1`）をpushすると、2つのipaとLGPL-2.1の全文をReleaseに載せる。
- ロジックは `Packages/VLCChatCore` に分け、`swift test --package-path Packages/VLCChatCore` でテストする。このPackageは `SwiftVLC` に依存させない（libVLCのコピーがプロセス内に2つできると未定義動作になるため）。

