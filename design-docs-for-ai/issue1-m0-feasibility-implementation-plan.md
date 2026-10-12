# Issue #1 M0（実現性の確認） 実装計画

対象Issue: https://github.com/5cd8/vlc-chat-ios/issues/1（アシスタントが起票したIssue。要件の正式な情報源はIssue本文であり、本計画は要約・言い換えをしない。「M0（実現性の確認）」の節が本計画の対象）
スコープ: M0のみ（Issueの機能要件の本実装は含まない）
依頼プロンプト: `user-prompt/202610121500_m0_issue1.md`（git管理しない）

本書は、本セッションの文脈を持たない別のAIがそのまま実装に使うことを想定している。

## 0. 前提・読み替え

- **ビルドも実行もできない開発環境**：開発機はWindowsで、Mac・Xcode・シミュレーターは無い。ローカルで `swift` も `xcodebuild` も動かせない。**コンパイルの確認はGitHub Actions（macOSランナー）だけで行い、実行の確認はユーザーのiPhone 16（iOS 26.6.2）の実機だけで行う**。したがって、書いたSwiftは一度でコンパイルが通る保証が無い。pushしてCIのログ（`gh run view --log-failed`）を読んで直す、を回す前提で進める（ワークフロー規則「毎回ビルドする」の読み替え）。
- **読み替え（00 項目30）**：「ブラウザ確認」「実行ファイルのフォルダを開く」は、**iPhone実機とSideStore**に読み替える。ユーザーに実機確認を頼むときは、実行ファイルのフォルダではなく、**署名なしipaのダウンロード先（GitHub Releasesのタグのページ）**を書く。
- 実機の確認項目の質問・手順は8節。ユーザーの作業（SideStoreの導入、ipaの取り込み、確認と報告）は8節に分けて書く。
- 確認済みの一次情報（調査日 2026-10-12）と、**未確認でM0の実機で確かめる事項**を区別する。未確認の事項を既定の前提にしない。
- PWA（リポジトリ vlc-chat-pwa）は凍結している。**コードは持ち込まない**。参考にしてよいのは、PC版の規則と、PWAの計画書3.1節の実機結果だけ。
- 設計判断の理由は、コードのコメントや文書にその場で直接書く（git管理していない文書を参照しない）。

## 1. スコープ・非ゴール

Issueの「M0」の4項目を確かめる。判断基準もIssueの通り（1と2が通れば本実装へ。3が外れたらPiPを諦め、4が外れたらバックグラウンド音声を仕様から外す。1が外れたら署名方式、2が外れたらライブラリを相談）。

1. 署名なしipaを、SideStoreが取り込んで署名・インストールできるか。
2. SwiftVLCで、ピッカーから選んだMKV（と、手元の実ファイルのH.264）を映像つきで再生できるか。
3. 無料のApple IDの署名で、PiPが起動するか。
4. 画面ロック中に、音声が続くか。

**M0のアプリは、本実装の骨組み（トレーサー弾）にする**：XcodeGenのプロジェクト、CI、Info.plist、Bundle ID、SwiftVLCの導入は、本実装（M1以降）でそのまま使う。M0の画面（確認用の1画面）と、診断・ログの仕組みの土台も、本実装で作り直す前提で小さく作る。

**非ゴール**：チャットの解析・同期・表示、プレイリスト、絵文字、設定画面、再生位置の記憶、本番の画面デザイン、アイコン、本番のSideStore「ソース」（JSON）配信、署名方式の最終決定。M0では、チャット・プレイリストのコードを書かない。

**M0で追加で確かめること**（本実装の設計に効く。Issueの「未確認事項」に対応）：

| ID | 内容 |
|---|---|
| A | SwiftVLCの既知の不具合（上流 #250：一部のH.264で音だけ出て映像が出ない）が、`PiPVideoView` の描画経路で起きるか（ユーザーの実ファイルで） |
| B | 一時停止中のシーク、2.0倍速、0.5倍速で、再生が安定し、音程が保たれるか |
| C | `.timeChanged` イベントの間隔（最小・平均・最大）。チャット同期（秒単位）に足りるか |
| D | `fileImporter` で得たURLが、アプリのコンテナにコピーされず、元の場所のまま開かれているか（数GBのファイルで選択に時間がかからないか） |
| E | ブックマークで記憶したURLが、アプリの再起動後に解決でき、再生できるか（`isStale` の扱い。ブックマークのオプション） |
| F | 数GB・数時間のMKVの再生中のメモリ使用量（`phys_footprint`）が、増え続けないか |
| G | 無料のApple IDで署名して、バックグラウンドモード（`audio`）が有効か。SwiftVLCの音声セッションの方針2つ（`.libraryManaged`／`.applicationManaged`）で、画面ロック中の挙動がどう違うか |

## 2. 確認済みの一次情報

| 事実 | 出典 |
|---|---|
| SwiftVLC：libVLC 4.0をSwiftから直接呼ぶラッパー。MIT。安定版は v1.0.0（2026-07-14）、最新は v1.1.0-beta.14（2026-09-21）。要件はSwift 6.3 / Xcode 26.4以降、iOS 18以降。メンテナ実質1人 | https://github.com/harflabs/SwiftVLC （`Package.swift`・README・Releases。`gh api` で確認） |
| `libvlc` は**静的**のxcframework（iOS arm64の `libvlc.a` は約73MB、zipは約386MB）。アプリのターゲットが `SwiftVLC` に直接依存すれば、1つのバイナリにリンクされる。**libVLCのコピーがプロセス内に2つ以上あると未定義動作**になるので、`SwiftVLC` に依存するターゲットは**アプリ本体だけ**にする（ロジックを分けるSwift Packageは `SwiftVLC` に依存させない） | 同 `ARCHITECTURE.md`・`Sources/SwiftVLC/SwiftVLC.docc/IntegrationTopology.md` |
| `Player`（`@Observable @MainActor`）：`play(url:) throws(VLCError)`、`pause()`・`resume()`・`togglePlayPause()`（いずれも非throws）、`seek(to: Duration, fast:) throws`、`seek(to: PlaybackPosition) throws`、`seek(by: Duration, fast:) throws`、`jump(by:) -> Bool`、`setPlaybackRate(_ rate: PlaybackRate) throws`（`PlaybackRate(Float)` は 0.25〜4.0 に丸める。`.half`・`.normal`・`.double`）、`currentTime: Duration`、`duration: Duration?`、`isSeekable`、`state`、`isPlaying`、`videoTracks`/`audioTracks`（`Track.codecString`・`width`・`height`）、`events: AsyncStream<PlayerEvent>`（`nonisolated`。`.timeChanged(Duration)`・`.stateChanged`・`.endReached` ほか）。**上はタグ v1.1.0-beta.14 のソースで確認した宣言（2026-10-12）**。v1.0.0との差は実装前に再確認する | `gh api repos/harflabs/SwiftVLC/contents/Sources/SwiftVLC/Player/...?ref=<タグ>` |
| `VideoView(player)`（SwiftUI）と、iOSのPiP用の `PiPVideoView(_ player, controller: Binding<PiPController?>? = nil, startsAutomaticallyFromInline: Bool = true)`（beta.14。`managesAudioSession` 付きの初期化子は非推奨で、音声セッションの所有はプレイヤーの `appleAudioSessionPolicy` を引き継ぐ。v1.0.0には `managesAudioSession` 付きの初期化子だけがある）。**2つは同じプレイヤーで併用しない**。`PiPController` は `start()`・`stop()`・`toggle()`・`isPossible`・`isActive`。iOSでは、libVLCのネイティブdrawableがAVKitのPiPコントローラーを持つ。iOS Simulatorではネイティブ PiP が使えない（実機で確かめる） | `Sources/SwiftVLC/SwiftVLC.docc/PictureInPicture.md`・`DisplayingVideo.md` |
| PiPには、再生用の音声セッションと、Info.plistの `UIBackgroundModes` の `audio` が要る。**ロック・背面に回ったとき、PiPが有効でなければ、SwiftVLCの管理経路は再生を一時停止し（再生の意図は保つ）、前面に戻ったときだけ再開する**（main のドキュメント。v1.0.0でも同じかは未確認）。つまり**既定のままでは、画面ロック中の音声は続かない可能性が高い**。`try VLCInstance(appleAudioSessionPolicy: .applicationManaged)`（`throws(VLCError)`。`VLCInstance.shared` は `.libraryManaged` 固定）で作った**専用のインスタンス**を `Player(instance:)` に渡すと、アプリ側が音声セッションを持つ（この引数は、v1.0.0の `VLCInstance` には**無く**（grepで0件）、beta.14にある）。この方針でも、ロック時の一時停止が起きるかは**未確認** | 同 `PictureInPicture.md`、`Core/AppleAudioSessionPolicy.swift`、`Player+AppleAudioSessionLifecycle.swift`（`gh api`） |
| XcodeGen（`project.yml` から `.xcodeproj` を生成）は、macOSランナーに `brew install xcodegen` で入れられる。署名なしipaは、`xcodebuild archive ... CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO AD_HOC_CODE_SIGNING_ALLOWED=YES` の後、`xcarchive/Products/Applications/X.app` を `Payload/` に入れて `zip` する。`-exportArchive` は署名が要るので使わない。SideStore自身のMakefileが実例 | https://github.com/SideStore/SideStore/blob/develop/Makefile （170〜200行付近）。XcodeGenは https://github.com/yonaskolb/XcodeGen |
| GitHub Actionsのパブリックリポジトリでは、macOSの標準ランナーも無料。`macos-26`（Apple Silicon）にXcode 26.0.1〜26.6が入っている（既定は26.6、iOS SDK 26.5） | https://docs.github.com/en/billing/concepts/product-billing/github-actions 、https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md |
| ユーザーが選んだ巨大な動画は、`UIDocumentPickerViewController(forOpeningContentTypes:asCopy: false)` でコピーせずに開ける。得たURLはセキュリティスコープ付きで、`startAccessingSecurityScopedResource()` と `stopAccessingSecurityScopedResource()` を対にする。ブックマークは、アクセス中に `bookmarkData(options:...)` で作り、`URL(resolvingBookmarkData:bookmarkDataIsStale:)` で解決する。**iOSで使うオプション（`.minimalBookmark` か）は、Appleのサンプルを見ても確定できていない** | https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller 、https://developer.apple.com/documentation/uikit/providing-access-to-directories |
| SideStore：無料のApple IDで、署名7日・同時3アプリ・1週間にApp ID 10個。最近の安定版0.6.4にはサインインの障害の注記があり、修正版は0.7.0-alpha。iOS 26.7では更新の不具合が未解決との報告。署名なしipaを直接受け付けるかは、公式文書に記載が無い（AltStore由来の挙動としては知られている）。初回セットアップ（Windows）：iTunes・iloader・LocalDevVPN | https://docs.sidestore.io/docs/faq 、https://github.com/SideStore/SideStore/releases 、SideStore-Docs（`docs/installation/*`・`docs/troubleshooting/*`）。**サブエージェントの報告による。実装前に、最新の公式文書で確かめる** |

## 3. 未確認事項（M0の実機で必ず確かめる。計画の前提にしない）

| ID | 未確認事項 | 確かめ方 | 外れたとき |
|---|---|---|---|
| U1 | 署名なしipaを、SideStoreがそのまま取り込み、署名してインストールできるか（SideStoreの公式文書に記載が無い） | 8節 チェック1 | 署名方式の相談（年$99のApple Developer Program、AltStoreなど） |
| U2 | CIが、SwiftVLC（xcframework約386MB）つきのiOSアプリを、`macos-26` でビルドできるか。Swift 6.3 / Xcode 26.4以降の要件を満たすか | 6節（push後のCI） | Xcodeのバージョン固定、SwiftVLCの版の変更（1.0.0⇔ベータ） |
| U3 | SwiftVLCでMKV（VP9/AV1+Opus、H.264+AAC）が映像つきで再生できるか。上流 #250（映像が出ない）が起きるか | チェック2（A） | VLCKit 4 → 3.7.4 の順に戻る |
| U4 | `.timeChanged` の間隔がチャット同期に足りるか | チェック2（C） | 補間（最後の通知時刻＋経過×rate）を本実装で入れる |
| U5 | `fileImporter` のURLが、コピーされずに開かれるか。ブックマークの再解決 | チェック2（D・E） | `asCopy: false` を使う `UIDocumentPickerViewController` を直接ラップする |
| U6 | 無料のApple IDで署名して、PiPが起動するか | チェック3 | PiPを諦める（Issueの判断基準） |
| U7 | 画面ロック中に音声が続くか。SwiftVLCの音声セッションの方針2つで違うか | チェック4 | バックグラウンド音声を仕様から外す（Issueの判断基準） |

## 4. 設計

### 4.1 構成と方針

- **アプリ**：Swift / SwiftUI、iOS 18以降、iPhoneのみ、縦のみ。Bundle ID `com.5cd8.vlcchatios`、表示名 `vlc-with-chat`、プロダクト名 `VLCWithChat`。
- **プロジェクト生成**：`project.yml`（XcodeGen）を置き、CIで `xcodegen generate` して `VLCWithChat.xcodeproj` を作る。**`.xcodeproj` はコミットしない**（`.gitignore`）。Macが無く `.xcodeproj` を手で保守できないため。
- **SwiftVLCの版**：M0は **`1.1.0-beta.14` を `exactVersion` で固定**する。理由：(1) `.applicationManaged`（G）が、安定版 v1.0.0 には無い。(2) 一時停止中のシークなどの修正（`beta.12`〜`14`）が入っている。ビルドが通らない・動かない場合に限り、`1.0.0` に下げて、`.applicationManaged` なしで確認する（判断の理由は本書10節に書く）。
- **Swift言語モードは5**（`SWIFT_VERSION: 5.0`）。Swift 6のstrict concurrencyは、ローカルでコンパイルできない状況ではCI往復を増やすだけなので、M0は5で始め、M1で6への移行を検討する。SwiftVLCのパッケージ自体はSwift 6モードでコンパイルされる（アプリの設定とは独立）。
- **ロジックのSwift Package**：`Packages/VLCChatCore`（`SwiftVLC` に**依存させない**）。M0では、実機計測の集計 `IntervalStats` だけを入れ、Swift Testingで単体テストする。目的は、本実装で使う「ロジックをPackageに分け、CIで `swift test` する」仕組みを、M0で通しておくこと。
- **コメントの方針**：コードにHow、テストにWhat、コミットログにWhy、コードコメントにWhy not（`code-comments`・`code-naming` スキルに従う）。

### 4.2 M0の画面（1画面。確認用）

縦に、上=動画（`PiPVideoView`。幅いっぱい、16:9）、中=操作、下=情報パネル（スクロール）。装飾は最小限でよい。

- **ファイルを選択**ボタン：`.fileImporter(isPresented:allowedContentTypes:[.item]...)`（拡張子での絞り込みはしない。MKVのUTIを当てにしない）。選ばれたURLについて、`startAccessingSecurityScopedResource()` を呼び、**再生が終わる・別のファイルを選ぶまで保持する**。選択直後に、`url.path`、ファイルサイズ、選択に要した時間をログへ出す（D）。
- **再生操作**：再生/一時停止（`togglePlayPause()`）、10秒戻る・進む（`seek(by:)` または `jump(by:)`）、シークバー（`Slider`。離したとき1回だけ `seek(to: PlaybackPosition)`）、再生速度（0.5・1.0・2.0のボタン。`setPlaybackRate`）。
- **PiP**：`PiPVideoView(player, controller: $pip)` を使い、「PiP開始」ボタン（`pip?.toggle()`）、`isPossible`・`isActive` の表示。`startsAutomaticallyFromInline` は既定の `true`（ホームへ戻ると自動でPiPになるかも見る）。
- **音声セッションの方針**：「ライブラリ管理／アプリ管理」の切り替え（`UserDefaults` に保存し、**次の起動から**有効。`appleAudioSessionPolicy` は `VLCInstance` の不変の属性のため）。ライブラリ管理は `VLCInstance.shared`、アプリ管理は `try VLCInstance(appleAudioSessionPolicy: .applicationManaged)` を作り、どちらも `Player(instance:)` に渡す（インスタンスはプロセスで1つだけ作る）。アプリ管理のときは、アプリが `AVAudioSession` を `.playback`・`.moviePlayback` にして `setActive(true)` する。
- **ブックマーク**：選択に成功したら、ブックマークデータを `UserDefaults` に保存する（オプションは `.minimalBookmark` を第一候補に試し、失敗したら `[]`）。「ブックマークから再生」ボタンで、保存したデータを解決して再生する。`isStale` の結果、解決したパス、`startAccessing...` の戻り値を表示する（E）。
- **情報パネル**：`state`、`currentTime`/`duration`、`rate`、`isSeekable`、映像・音声トラックの `codecString`・解像度、`.timeChanged` の間隔の最小・平均・最大（直近30秒。`IntervalStats`）（C）、`phys_footprint`（MB。1秒ごと）（F）、PiPの状態、アプリのバージョンとSwiftVLCの版（`VLCInstance.shared.version`）。
- **ログ**：`Documents/m0-log.txt` に追記（時刻つき）。アプリのイベント（選択・再生・シーク・状態変化・`.timeChanged` の間隔の外れ値・PiPの開始/終了・前面/背面・音声セッションの中断）を残す。画面から「ログを共有」（`ShareLink`）で取り出せる。Info.plistに `UIFileSharingEnabled`・`LSSupportsOpeningDocumentsInPlace` を入れて、「ファイル」アプリからも見えるようにする。

### 4.3 Info.plist（XcodeGenの `info.properties`）

`CFBundleDisplayName: vlc-with-chat`、`UIBackgroundModes: [audio]`、`UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]`、`UIApplicationSceneManifest`（SwiftUIの既定）、`UILaunchScreen: {}`、`UIFileSharingEnabled: true`、`LSSupportsOpeningDocumentsInPlace: true`、`ITSAppUsesNonExemptEncryption: false`。

## 5. ファイル構成

```
vlc-chat-ios/
  project.yml                         # XcodeGen。SwiftVLC（exactVersion）と、ローカルPackage VLCChatCore
  App/
    VLCWithChatApp.swift              # @main。VLCInstance の準備、診断ログの初期化
    M0View.swift                      # 確認用の1画面
    M0Model.swift                     # @Observable @MainActor。Player・選択URL・ブックマーク・PiP・計測
    ScopedFile.swift                  # セキュリティスコープ付きURLの保持（start/stop対）とブックマークの作成・解決
    DiagnosticsLog.swift              # Documents/m0-log.txt への追記、phys_footprint の取得
  Packages/VLCChatCore/
    Package.swift                     # iOS 18 / macOS 15。SwiftVLCに依存しない
    Sources/VLCChatCore/IntervalStats.swift
    Tests/VLCChatCoreTests/IntervalStatsTests.swift
  scripts/make-ipa.sh                 # 署名なしipaを作る
  .github/workflows/build-ipa.yml     # テスト・ビルド・ipaの成果物・（手動で）Release
  .gitignore                          # VLCWithChat.xcodeproj/・build/ を追加
```

`design-docs-for-ai/` は、feature ブランチにだけ載せ、マージ前の最後のコミットで `git rm` する（`CLAUDE.md` の運用）。

## 6. CI（`.github/workflows/build-ipa.yml`）

- **トリガー**：`push`（`main`・`feature/**`）、`workflow_dispatch`（入力 `release`: `true`/`false`、`tag`）。
- **ジョブ `test`**：`macos-26`。`swift test --package-path Packages/VLCChatCore`。
- **ジョブ `build`**（`test` の後）：`macos-26`。手順：(1) checkout、(2) `xcodebuild -version` と `swift --version` をログに出す、(3) `brew install xcodegen`、(4) SwiftPMのキャッシュ（`actions/cache`：`~/Library/Caches/org.swift.swiftpm` と `build/SourcePackages`。キーは `project.yml` のハッシュ。xcframeworkが約386MBあるので必須）、(5) `xcodegen generate`、(6) `scripts/make-ipa.sh`、(7) `actions/upload-artifact`（ipaとビルドログ）、(8) `release` が真のとき、`gh release create <tag> build/vlc-with-chat-unsigned.ipa --prerelease --notes ...`（`permissions: contents: write`）。
- **`scripts/make-ipa.sh`**：`xcodebuild archive -project VLCWithChat.xcodeproj -scheme VLCWithChat -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -archivePath build/VLCWithChat.xcarchive -clonedSourcePackagesDirPath build/SourcePackages CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO AD_HOC_CODE_SIGNING_ALLOWED=YES`、続けて `Payload/` に `.app` をコピーして `zip -qry`。`set -euo pipefail`。出力は `build/vlc-with-chat-unsigned.ipa`。
- ビルドに失敗したら、`gh run view <id> --log-failed` でログを読み、直して再pushする。

## 7. テスト方針

- ビジネスロジックをUIから分離する：計測の集計（`IntervalStats`）はPackageに分け、Swift Testingで単体テストする（観点：空・1件・複数件の最小/平均/最大、直近N秒の窓から古い値が落ちること、時刻が逆行した入力の扱い）。UI・Player・ファイル・PiPの配線はテストしない（実機で確かめる）。
- 実際の再生・PiP・ロック・SideStoreは、8節の実機の手順で確かめる。

## 8. 動作確認手順（読み替え：iPhone実機。ユーザーの作業）

**前提のユーザー作業（SideStoreの導入）**：未導入。M0のチェック1の前に、最新の公式文書（https://docs.sidestore.io/docs/installation/prerequisites ・ `install`）に従って導入する。**導入時に、実装者（アシスタント）が手順を案内する**（Windows：iTunes→iloader→SideStore→LocalDevVPN）。iOS 26.6で動かない場合は、AltStoreでチェック1を代替できる（署名なしipaの取り込みの可否を確かめる目的は同じ）。

ipaは、GitHub Releases の `m0-<n>` のページ（`https://github.com/5cd8/vlc-chat-ios/releases`）から、iPhoneのSafariでダウンロードし、「ファイル」アプリ経由でSideStoreに取り込む。

| ID | 内容 | 報告してほしいこと |
|---|---|---|
| チェック1（U1） | ipaをSideStoreで取り込み、署名・インストールして、アプリが起動するか | 成功/失敗、エラーメッセージ（スクリーンショット） |
| チェック2（U3〜U5、A〜F） | **MKV（VP9+Opus・AV1+Opus・H.264+AAC）、MP4（H.264）、WebM** を1本ずつ選んで再生。映像が出るか。シーク、一時停止中のシーク、0.5/1.0/2.0倍速（音程が保たれるか）、`.timeChanged` の間隔（情報パネルのmin/avg/max）。選択にかかった時間と、パス（アプリ内か）。アプリを終了して再起動し、「ブックマークから再生」。数GB・数時間のMKVを1時間再生して、メモリ（MB）が増え続けないか | 各ファイルの結果（映像・音声・シーク）、情報パネルの数値、ログファイル（「ログを共有」） |
| チェック3（U6） | 再生中に、PiP開始ボタンを押す。ホームへ戻って、自動でPiPになるか。PiP中の再生/一時停止・スキップ | PiPが出たか、`isPossible`、PiP中の操作の結果 |
| チェック4（U7） | 音声セッションの方針を「ライブラリ管理」にして（既定）、(a) PiPなしで再生中にロックする (b) PiPが出ている状態でロックする。次に「アプリ管理」へ切り替えて再起動し、(a)(b)を繰り返す | 4通りそれぞれで、ロック中に音が続くか、前面に戻ったときの状態 |

**ユーザーが実機確認する前に**：ipaのダウンロードURL（Releasesのタグ）と、確認に使うファイル（ファイル名・形式）を、依頼文に書く（00 項目32）。確認の回数を減らすため、チェック1〜4は、同じビルドで続けて行う。

## 9. 品質管理

- CIの `test`・`build` が成功すること（警告は、ビルドログで確認し、アプリのコードに起因する警告は残さない）。ローカルでビルドできないので、CIの成功が唯一のゲート。
- コミットの前に、Swiftのコードを既存のSwiftVLCの宣言（使う版のタグのソース）と1行ずつ突き合わせる（存在しないAPI・引数ラベルの違いは、CI往復の最大の原因）。
- SwiftVLCの宣言は、`gh api "repos/harflabs/SwiftVLC/contents/<path>?ref=v1.1.0-beta.14"` で読む。

## 10. 設計判断の記録（採用案・理由・採らなかった案）

| # | 判断 | 理由 | 採らなかった案 |
|---|---|---|---|
| D1 | M0をトレーサー弾にする（骨組みを本実装に引き継ぐ） | CI・署名なしipa・SwiftVLCの導入は、本実装で必ず要る。使い捨てにすると二度手間 | 使い捨てのスパイク（PWAのPhase 0と同じ）。画面とロジックは作り直すので、M0では小さく作る |
| D2 | XcodeGenで `.xcodeproj` を生成し、コミットしない | Macが無く、`.xcodeproj` を手で保守できない。`project.yml` はテキストで、私が書ける | `.xcodeproj` をコミット（手で直せない）、Swift Playgrounds形式（`xcodebuild` でのCIが標準でない） |
| D3 | SwiftVLCは `1.1.0-beta.14` を固定 | `.applicationManaged`（G）が安定版に無い（grepで確認）。シークの修正が入っている。**Issueの「M0は安定版 v1.0.0 で始める」とは食い違うため、ユーザーの確認待ち（12節）** | v1.0.0（Issueの記載通り。Gの2つ目の方針を試せない。外れたときの戻り先として残す） |
| D4 | アプリのSwift言語モードは5 | ローカルでコンパイルできず、strict concurrencyの修正でCI往復が増える | Swift 6（M1で移行を検討） |
| D5 | `fileImporter` に `[.item]` を渡す（拡張子で絞らない） | MKVなどに対応するUTIがiOSに無い可能性があり、絞ると選べない。PWAでも `accept` を付けない判断をした | `.movie` などで絞る |
| D6 | ロジックのPackageは `SwiftVLC` に依存させない | libVLCのコピーが2つできると未定義動作（IntegrationTopology） | PackageからSwiftVLCを使う（本実装でも、アプリ本体だけが依存する） |
| D7 | 計測値はアプリ内とログファイルで取り出す | Macが無く、Console・Instrumentsを使えない | Xcodeのデバッガー |

## 11. リスク

- **コンパイルの往復**：書いたSwiftが、CIで何度も落ちる可能性が高い（ローカルにコンパイラが無い）。SwiftVLCの宣言をタグのソースで確かめ、小さく作って、push→CIを素早く回す。
- **SwiftVLCは若く、メンテナは実質1人**。ベータを固定するので、不具合は自分で回避する必要がある。
- **SideStoreの不安定さ**：iOS 26での更新・サインインの障害が報告されている。チェック1が外れたときの代替（AltStore）を用意しておく。
- **画面ロック中の音声**：SwiftVLCの既定では、PiPなしのロックで一時停止する可能性が高い（2節）。外れたら、本実装でバックグラウンド音声を仕様から外す（Issueの判断基準）。
- **PiPの無料署名での可否**：未確認。外れたらPiPを諦める（Issueの判断基準）。
- **ブックマークのオプション**：iOSで正しい値が確定できていない。実機で `.minimalBookmark` と `[]` を試す。
- M0の結果が、Issueの前提（SwiftVLC・SideStore）を変える場合は、計画を作り直す（ステップ2〜4に戻る）。

## 12. ユーザーに確認が要る点

- **SwiftVLCの版**：Issue本文は「M0は安定版 v1.0.0 で始める」「一時停止中のシークが不安定ならベータに上げる」とするが、画面ロック中の音声（チェック4）で `.applicationManaged` を試すにはベータが要る。本計画は beta.14 を既定にした。Issueの記載（v1.0.0から始める）に合わせるか、本計画（beta.14）で進めるかを決めてもらう。決まり次第、Issueの記述と本計画をそろえる。
