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

Issueの「M0」の4項目を確かめる。判断基準もIssueの通り（1と2が通れば本実装へ。3が外れてもPiPは諦めず、署名かライブラリかを切り分けて相談する（ユーザーの決定）。4が外れたらバックグラウンド音声を仕様から外す。1が外れたら署名方式を相談し、2が外れたらライブラリの版や構成を見直す（SwiftVLC → VLCKit 4.0.0-a25 → VLCKit 3.7.4の順））。

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
| H | 4KのAV1/VP9（ソフトウェアデコード）が実用速度で再生できるか（Issueの未確認事項）。チェック2で4KのAV1またはVP9のファイルを1本含め、コマ落ち・CPU・発熱・音ずれを目視と体感で見る |
| G | 無料のApple IDで署名して、バックグラウンドモード（`audio`）が有効か。SwiftVLCの音声セッションの方針2つ（`.libraryManaged`／`.applicationManaged`）で、画面ロック中の挙動がどう違うか |

## 2. 確認済みの一次情報

| 事実 | 出典 |
|---|---|
| SwiftVLC：libVLC 4.0をSwiftから直接呼ぶラッパー。MIT。安定版は v1.0.0（2026-07-14）、最新は v1.1.0-beta.14（2026-09-21）。要件はSwift 6.3 / Xcode 26.4以降、iOS 18以降。メンテナ実質1人 | https://github.com/harflabs/SwiftVLC （`Package.swift`・README・Releases。`gh api` で確認） |
| `libvlc` は**静的**のxcframework（iOS arm64の `libvlc.a` は約73MB、zipは約382MB（beta.14））。アプリのターゲットが `SwiftVLC` に直接依存すれば、1つのバイナリにリンクされる。**libVLCのコピーがプロセス内に2つ以上あると未定義動作**になるので、`SwiftVLC` に依存するターゲットは**アプリ本体だけ**にする（ロジックを分けるSwift Packageは `SwiftVLC` に依存させない） | 同 `ARCHITECTURE.md`・`Sources/SwiftVLC/SwiftVLC.docc/IntegrationTopology.md` |
| `Player`（`@Observable @MainActor`）：`play(url:) throws(VLCError)`、`pause()`・`resume()`・`togglePlayPause()`（いずれも非throws）、`seek(to: Duration, fast:) throws`、`seek(to: PlaybackPosition) throws`、`seek(by: Duration, fast:) throws`、`jump(by:) -> Bool`、`setPlaybackRate(_ rate: PlaybackRate) throws`（`PlaybackRate(Float)` は 0.25〜4.0 に丸める。`.half`・`.normal`・`.double`）、`currentTime: Duration`、`duration: Duration?`、`isSeekable`、`state`、`isPlaying`、`videoTracks`/`audioTracks`（`Track.codecString`・`width`・`height`）、`events: AsyncStream<PlayerEvent>`（`nonisolated`。`.timeChanged(Duration)`・`.stateChanged`・`.endReached` ほか）。**上はタグ v1.1.0-beta.14 のソースで確認した宣言（2026-10-12）**。v1.0.0との差は実装前に再確認する | `gh api repos/harflabs/SwiftVLC/contents/Sources/SwiftVLC/Player/...?ref=<タグ>` |
| `VideoView(player)`（SwiftUI）と、iOSのPiP用の `PiPVideoView(_ player, controller: Binding<PiPController?>? = nil, startsAutomaticallyFromInline: Bool = true)`（beta.14。`managesAudioSession` 付きの初期化子は非推奨で、音声セッションの所有はプレイヤーの `appleAudioSessionPolicy` を引き継ぐ。v1.0.0には `managesAudioSession` 付きの初期化子だけがある）。**2つは同じプレイヤーで併用しない**。`PiPController` は `start()`・`stop()`・`toggle()`・`isPossible`・`isActive`。iOSでは、libVLCのネイティブdrawableがAVKitのPiPコントローラーを持つ。iOS Simulatorではネイティブ PiP が使えない（実機で確かめる） | `Sources/SwiftVLC/SwiftVLC.docc/PictureInPicture.md`・`DisplayingVideo.md` |
| PiPには、再生用の音声セッションと、Info.plistの `UIBackgroundModes` の `audio` が要る。**ロック・背面に回ったとき、PiPが有効でなければ、SwiftVLCの管理経路は再生を一時停止し（再生の意図は保つ）、前面に戻ったときだけ再開する**（main のドキュメント。v1.0.0でも同じかは未確認）。つまり**既定のままでは、画面ロック中の音声は続かない可能性が高い**。`try VLCInstance(appleAudioSessionPolicy: .applicationManaged)`（`throws(VLCError)`。`VLCInstance.shared` は `.libraryManaged` 固定）で作った**専用のインスタンス**を `Player(instance:)` に渡すと、アプリ側が音声セッションを持つ（この引数は、v1.0.0の `VLCInstance` には**無く**（grepで0件）、beta.14にある）。この方針でも、ロック時の一時停止が起きるかは、SwiftVLC側ではソースで答えが出る（`PiPController+AudioSession.swift` の `startAudioSessionObservers()` は、ライブラリ管理のときだけ `protectedDataWillBecomeUnavailable`・`didEnterBackground` を購読し、PiPが無効なら一時停止する。アプリ管理では購読しない）。残る未確認は、iOS・libVLCの音声出力側の挙動だけ | 同 `PictureInPicture.md`、`Core/AppleAudioSessionPolicy.swift`、`Player+AppleAudioSessionLifecycle.swift`（`gh api`） |
| XcodeGen（`project.yml` から `.xcodeproj` を生成）は、macOSランナーに `brew install xcodegen` で入れられる。署名なしipaは、`xcodebuild archive ... CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO AD_HOC_CODE_SIGNING_ALLOWED=YES` の後、`xcarchive/Products/Applications/X.app` を `Payload/` に入れて `zip` する。`-exportArchive` は署名が要るので使わない。SideStore自身のMakefileが実例 | https://github.com/SideStore/SideStore/blob/develop/Makefile （archiveは170〜200行付近、`ldid -S` による偽署名と `Payload` への詰め込みは250〜277行付近。`ldid` はCIで `brew install ldid` で入れる）。XcodeGenは https://github.com/yonaskolb/XcodeGen |
| GitHub Actionsのパブリックリポジトリでは、macOSの標準ランナーも無料。`macos-26`（Apple Silicon）にXcode 26.0.1〜26.6が入っている（既定は26.6、iOS SDK 26.5） | https://docs.github.com/en/billing/concepts/product-billing/github-actions 、https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md |
| ユーザーが選んだ巨大な動画は、`UIDocumentPickerViewController(forOpeningContentTypes:asCopy: false)` でコピーせずに開ける。得たURLはセキュリティスコープ付きで、`startAccessingSecurityScopedResource()` と `stopAccessingSecurityScopedResource()` を対にする。ブックマークは、アクセス中に `bookmarkData(options:...)` で作り、`URL(resolvingBookmarkData:bookmarkDataIsStale:)` で解決する。Appleのサンプル（Providing access to directories）は `bookmarkData(options: .minimalBookmark, ...)` を使っている。`isStale` が真のときにブックマークを作り直すかは、M0で挙動を見る | https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller 、https://developer.apple.com/documentation/uikit/providing-access-to-directories |
| SideStore：無料のApple IDで、署名7日・同時3アプリ（SideStore自身を含む）・1週間にApp ID 10個。**0.6.4は「DO NOT USE」（サインイン不能）。最新は0.7.0-alpha（サインインの503を修正）**。0.6.3のノートに「iOS 26.4以降でVPNエラーが出たらiloaderで再インストール」とある。署名なしipaを直接受け付けるかは、FAQ・前提条件のページに記載が無い（「アプリに改変は要らない」「個人の開発証明書で再署名する」とだけある）。無料のApple IDの制限（署名7日はバックグラウンドで更新、同時3アプリ、週にApp ID 10個）はFAQで再確認済み。初回セットアップ（Windows 8以降・64bit、Wi-Fi必須）：LocalDevVPN（iPhone）→iTunes→iloader。インストール・更新のたびにVPNをオンにする | https://docs.sidestore.io/docs/faq 、https://docs.sidestore.io/docs/installation/prerequisites 、https://github.com/SideStore/SideStore/releases （いずれも2026-10-12に取得して確認）。バックグラウンドモード（`audio`）とPiPに必要なのはInfo.plistの `UIBackgroundModes` と音声セッションで、entitlementは要らないはずだが（Appleの要件としての理解。一次情報は未取得）、無料署名での挙動は実機で確かめる |

## 3. 未確認事項（M0の実機で必ず確かめる。計画の前提にしない）

| ID | 未確認事項 | 確かめ方 | 外れたとき |
|---|---|---|---|
| （B） | 一時停止中のシークが安定するか | チェック2 | v1.0.0に下げて比べる（4.1節） |
| （F） | 1時間再生してメモリが増え続けないか | チェック2 | 増える場合は、原因（libVLCのキャッシュ設定、ファイル読み込み）を調べて相談 |
| （H） | 4KのAV1/VP9が実用速度か | チェック2 | 実用でなければ、対応する解像度・コーデックの範囲を相談 |
| U1 | 署名なしipaを、SideStoreがそのまま取り込み、署名してインストールできるか（SideStoreの公式文書に記載が無い） | 8節 チェック1 | まず、同じビルドで一緒に作った偽署名のipa（`ldid -S`。SideStore自身のMakefileの手順）を試す。それでも外れたら、署名方式の相談（年$99のApple Developer Program、AltStoreなど） |
| U2 | CIが、SwiftVLC（xcframework約382MB）つきのiOSアプリを、`macos-26` でビルドできるか。Swift 6.3 / Xcode 26.4以降の要件を満たすか | 6節（push後のCI） | Xcodeのバージョン固定、SwiftVLCの版の変更（1.0.0⇔ベータ） |
| U3 | SwiftVLCでMKV（VP9/AV1+Opus、H.264+AAC）が映像つきで再生できるか。上流 #250（映像が出ない）が起きるか | チェック2（A） | 戻り先の順序は、beta.14 → v1.0.0 → VLCKit 4.0.0-a25 → VLCKit 3.7.4（PiPなし）。1.0.0に下げる条件は4.1節 |
| U4 | `.timeChanged` の間隔がチャット同期に足りるか | チェック2（C） | 補間（最後の通知時刻＋経過×rate）を本実装で入れる |
| U5 | `fileImporter` と `UIDocumentPickerViewController(asCopy: false)`（どちらもM0の画面に置く）のURLが、コピーされずに開かれるか。ブックマークの再解決 | チェック2（D・E） | 開かれない方式は本実装で使わない。両方外れたら、ファイルの取り込み方を相談する |
| U6 | 無料のApple IDで署名して、PiPが起動するか | チェック3 | 諦めない。原因（署名／ライブラリ）を切り分けて相談（ユーザーの決定） |
| U7 | 画面ロック中に音声が続くか。SwiftVLCの音声セッションの方針2つで違うか。**合格基準：「アプリ管理(a)」（PiPなしでロック）で音声が続けば、4は通ったとする（Issueの受け入れ条件6は、PiPを前提にしない）。PiP中(b)だけで続く場合は「PiP中のみ続く」という結果として報告し、仕様をどうするかをユーザーに相談する（計画では決めない）。ライブラリ管理(a)の停止は、ソース上の設計どおりで、外れではない** | チェック4 | バックグラウンド音声を仕様から外す（Issueの判断基準） |

## 4. 設計

### 4.1 構成と方針

- **アプリ**：Swift / SwiftUI、iOS 18以降、iPhoneのみ、縦のみ。Bundle ID `com.5cd8.vlcchatios`、表示名 `vlc-with-chat`、プロダクト名 `VLCWithChat`。
- **プロジェクト生成**：`project.yml`（XcodeGen）を置き、CIで `xcodegen generate` して `VLCWithChat.xcodeproj` を作る。**`.xcodeproj` はコミットしない**（`.gitignore`。`project.yml` の先頭に `name: VLCWithChat`）。Macが無く `.xcodeproj` を手で保守できないため。
- **SwiftVLCの版**：M0は **`1.1.0-beta.14` を `exactVersion` で固定**する。理由：(1) `.applicationManaged`（G）が、安定版 v1.0.0 には無い。(2) 一時停止中のシークなどの修正（`beta.12`〜`14`）が入っている。下げる条件は、(a) ビルドが通らない・動かない、(b) チェック2のB（一時停止中のシーク）が外れた、のとき（Issueと同じ。比べるために `1.0.0` でも試す）。**`1.0.0` に下げると使えなくなるもの**：`VLCInstance(appleAudioSessionPolicy:)`（Gの2つ目の方針）、`PiPController.requestStart()`・`toggleReportingStartResult()`・`PiPStartResult`・`pipEventEnvelopes`（PiPの結果表示は `start()` と `isPossible`／`isActive`、非同期の失敗は v1.0.0 にもある `pipEvents`（`.failedToStart`）で代用する）。下げるときは、画面・モデルの該当部分を書き換えて対応する（判断の理由は本書10節に書く。計画書はマージ前に消すので、残すべき理由はコードのコメントかPR本文へ移す（squashマージのため、featureブランチのコミットログは `main` に残らない））。
- **Swift言語モードは5**（`SWIFT_VERSION: 5.0`）。Swift 6のstrict concurrencyは、ローカルでコンパイルできない状況ではCI往復を増やすだけなので、M0は5で始め、M1で6への移行を検討する。SwiftVLCのパッケージ自体はSwift 6モードでコンパイルされる（アプリの設定とは独立）。
- **ロジックのSwift Package**：`Packages/VLCChatCore`（`SwiftVLC` に**依存させない**）。M0では、実機計測の集計 `IntervalStats` だけを入れ、Swift Testingで単体テストする。目的は、本実装で使う「ロジックをPackageに分け、CIで `swift test` する」仕組みを、M0で通しておくこと。
- **project.yml の要点**（XcodeGenの `ProjectSpec.md` で確認）：
  - `packages:` に `SwiftVLC: {url: https://github.com/harflabs/SwiftVLC, exactVersion: 1.1.0-beta.14}` と `VLCChatCore: {path: Packages/VLCChatCore}`。ターゲットの `dependencies:` に `- package: SwiftVLC`・`- package: VLCChatCore`。
  - ターゲット `VLCWithChat`（`type: application`、`platform: iOS`、`deploymentTarget: "18.0"`、`sources: [App]`）。`scheme: {}` で共有スキームを生成する（`xcodebuild -scheme VLCWithChat` が確実に見つかるように）。
  - `settings.base`：`PRODUCT_BUNDLE_IDENTIFIER: com.5cd8.vlcchatios`、`PRODUCT_NAME: VLCWithChat`、`TARGETED_DEVICE_FAMILY: "1"`、`SWIFT_VERSION: "5.0"`、`MARKETING_VERSION: "0.1.0"`、`CURRENT_PROJECT_VERSION`（CIでは `$GITHUB_RUN_NUMBER` を渡す。既定は `"1"`）。
  - `info:` は `path: App/Info.plist` が必須で、生成のたびに書き出される。**生成物なので `.gitignore` に入れる**。`properties:` に4.3節のキーを書く。
  - `Packages/VLCChatCore/Package.swift` はパッケージ名・ライブラリproduct名とも `VLCChatCore`、`// swift-tools-version: 6.0`、`platforms: [.iOS(.v18), .macOS(.v15)]`、テストターゲットは Swift Testing（`import Testing`）。
- **phys_footprint の取り方**：`task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), ...)` で `task_vm_info_data_t` を取り、`phys_footprint` を使う。個数は `mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)`（`TASK_VM_INFO_COUNT` マクロはSwiftに取り込まれないため）。
- **コメントの方針**：コードにHow、テストにWhat、コミットログにWhy、コードコメントにWhy not（`code-comments`・`code-naming` スキルに従う）。

### 4.2 M0の画面（1画面。確認用）

縦に、上=動画（`PiPVideoView`。幅いっぱい、16:9）、中=操作、下=情報パネル（スクロール）。装飾は最小限でよい。

- **ファイルを選択**ボタン：`.fileImporter(isPresented:allowedContentTypes:[.item]...)`（拡張子での絞り込みはしない。MKVのUTIを当てにしない）。選ばれたURLについて、`startAccessingSecurityScopedResource()` を呼び、**再生が終わる・別のファイルを選ぶまで保持する**。選択直後に、`url.path`、ファイルサイズ、再生開始までの時間（ピッカーのコールバックが返ってから、`play(url:)` 後に `.playing` になるまで。参考値。ピッカーがコピーするならコールバックより前なので、この時間では測れない）をログへ出す。**コピーされたかの判定は `url.path` がアプリのコンテナ内かどうか**（D）。アプリの `Documents` は「ファイル」アプリに見える（4.3節）ので、ユーザーはテスト動画を**このアプリ以外の場所（「このiPhone内」の別フォルダ）**に置いて選ぶ（`Documents` に置くと、コピーされていなくてもコンテナ内と判定される）。iCloudにだけあってダウンロードされていないファイルも避ける。
- **再生操作**：再生/一時停止（`togglePlayPause()`）、10秒戻る・進む（`jump(by: .seconds(±10))`。戻り値 `Bool` をログに出す）、シークバー（`Slider`。離したとき1回だけ `seek(to: PlaybackPosition)`）、再生速度（0.5・1.0・2.0のボタン。`setPlaybackRate`）。
- **PiP**：`PiPVideoView(player, controller: $pip)` を使い、「PiP開始」ボタン（`pip?.toggleReportingStartResult()` または `requestStart() -> PiPStartResult`（`.accepted`・`.noMedia`・`.notPossible`・`.backendUnavailable`）で**結果を画面とログに出す**。`toggle()`・`start()` は結果を捨てるため、チェック3が外れたときの切り分けの材料にならない。非同期の失敗は `pipEventEnvelopes` で拾う）、`isPossible`・`isActive` の表示。`startsAutomaticallyFromInline` は画面のスイッチで切り替える（既定 `true`。`PiPVideoView` の作成時にしか効かないので、次の再生から有効。「PiPなしで他アプリに切り替えたときの音声」を試せるようにするため）（ホームへ戻ると自動でPiPになるかも見る）。
- **音声セッションの方針**：「ライブラリ管理／アプリ管理」の切り替え（`UserDefaults` に保存し、**次の起動から**有効。`appleAudioSessionPolicy` は `VLCInstance` の不変の属性のため）。ライブラリ管理は `VLCInstance.shared`、アプリ管理は `try VLCInstance(appleAudioSessionPolicy: .applicationManaged)` を作り、どちらも `Player(instance:)` に渡す（インスタンスはプロセスで1つだけ作る）。アプリ管理のときは、アプリが `AVAudioSession` を `.playback`・`.moviePlayback` にして、**`play(url:)` の前に** `setActive(true)` する（アプリ管理ではSwiftVLCが有効化しない）。`Media.parse(timeout:instance:)` などは `instance` の既定が `.shared` なので、使う場合は必ずインスタンスを明示する。
- **ブックマーク**：選択に成功したら、ブックマークデータを `UserDefaults` に保存する（`.minimalBookmark` と `[]`（オプションなし）の**2つを別々のキーで保存**し、再起動後に**両方を解決して結果（パス・`isStale`・再生可否）を並べて表示する**。どちらのピッカーで選んだ結果も、直近の1件を保存する（上書き））。「ブックマークから再生」ボタンで、保存したデータを解決して再生する。`isStale` の結果、解決したパス、`startAccessing...` の戻り値を表示する（E）。
- **情報パネル**：`state`、`currentTime`/`duration`、`rate`、`isSeekable`、映像・音声トラックの `codecString`（`String?`。nilなら「不明」と表示）・解像度、`activeVideoOutputs`（`Player.activeVideoOutputs`。上流 #250 は `state` が `playing` のまま映像だけ出ない症状なので、Aの判定に要る）と `.voutChanged` のログ、`.timeChanged` の間隔の最小・平均・最大（直近30秒。`IntervalStats`）（C。測り方は下の「timeChanged計測の定義」）、`phys_footprint`（MB。1秒ごと）（F）、PiPの状態、アプリのバージョン（`CFBundleVersion`）とlibVLCの版（**実際に使うインスタンスの `.version`**。これは `libvlc_get_version()` の値でSwiftVLCの版ではない。SwiftVLCの版は定数で別に持つ。`VLCInstance.shared` に触れると、アプリ管理のときも `.libraryManaged` のインスタンスが生成されてしまい、チェック4を汚す）。
- **timeChanged計測の定義**：`IntervalStats` は時計を内部に持たず、`record(at: TimeInterval, mediaTime: TimeInterval)`（`at` は `ProcessInfo.processInfo.systemUptime` など単調増加の秒。呼び出し側が渡す）、`snapshot(now: TimeInterval) -> Snapshot?`、`reset(at:)` を持つ。`Snapshot` は `wall: Stat`（受信時刻の差）と `media: Stat`（メディア時刻の差）と `samples: Int`（窓内の記録件数。間隔の数は `samples - 1`）で、`Stat` は `min`・`avg`・`max`（秒）。窓は `at > now - 30` の記録（境界は含まない。窓の長さはイニシャライザの引数）。窓内に2件未満なら `nil`。期待値の目安は約30Hz（約33ms。SwiftVLCのソースのコメント）。`state` が `.playing` でない間は `record` を呼ばず、シーク・速度変更・一時停止からの復帰のたびに `reset()` する（空白がmaxに入らないように）。ログに出す外れ値の閾値は、受信間隔が1.0秒を超えたとき。受信時刻が逆行した入力（`at` が前回以前）は、その1件を捨てる。
- **取りこぼしを避ける**：シーク直後は、シーク前に溜まっていた `.timeChanged` が `reset()` の後に届くので、`reset()` から0.5秒間の記録は捨てる。`.timeChanged`・`.voutChanged`・`.encounteredError` は、`filter` でこの3種を通す1本の `player.events(policy: .unbounded, filter: ...)`、状態変化のログは `stateTransitions` で受ける（既定の `events` は `.newest(64)` で取りこぼし得る）。`try VLCInstance(appleAudioSessionPolicy: .applicationManaged)` が失敗したら、`.shared` に戻さず、エラーを画面に出して再生を無効にする（チェック4の結果を汚さないため）。`IntervalStats` は `record` 時に窓より古い記録を捨てる。メディア時刻の差が負のとき（アプリを経由しない後方シーク。PiPのスキップなど）は、その記録を捨てず、**新しい基準にして窓をリセットする**（捨てると、元の位置を追い越すまで全件が捨てられる）。`reset()` から0.5秒間の破棄は、Package側（`reset(at:)` が時刻を覚える）に置く。外れ値（受信間隔1.0秒超）の判定とログ出力は、Package側ではなくModel側に置く。
- **画面を消さない**：再生中は `UIApplication.shared.isIdleTimerDisabled = true`（1時間の再生確認（F）が自動ロックで途切れないため。Issueの機能要件2の先取り）。一時停止中・背面に回るときは `false` に戻す。
- **選択の2系統**：`fileImporter` のボタンと、`UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)` をラップしたボタンを並べ、同じビルドで両方の結果（パス・選択時間・再生可否）を比べる（実機の往復を増やさない）。
- **ログ**：`Documents/m0-log.txt` に追記（時刻つき。**1行ごとに同期して書き込む**。背面で落ちたとき、直前の手がかりが残るように）。`phys_footprint` を60秒ごとに1行（Fの推移を取り出すため）、アプリのイベント（ロックの検知（`protectedDataWillBecomeUnavailable`・`protectedDataDidBecomeAvailable`。パスコード設定時のみ届く）、選択・再生・シーク・状態変化・`.timeChanged` の間隔の外れ値・PiPの開始/終了・前面/背面・音声セッションの中断）を残す。画面から「ログを共有」（`ShareLink`）で取り出せる。Info.plistに `UIFileSharingEnabled`・`LSSupportsOpeningDocumentsInPlace` を入れて、「ファイル」アプリからも見えるようにする。

### 4.3 Info.plist（XcodeGenの `info.properties`）

`CFBundleDisplayName: vlc-with-chat`、`LSRequiresIPhoneOS: true`、`UIApplicationSceneManifest: {UIApplicationSupportsMultipleScenes: false}`（XcodeGenは既定でこれらを書かない。これらが無くてもSwiftUIの `@main App` が起動するかは未確認なので、念のため足す）、`CFBundleShortVersionString: $(MARKETING_VERSION)`、`CFBundleVersion: $(CURRENT_PROJECT_VERSION)`（XcodeGenは指定しないと固定値 `1.0`・`1` を書くため）、`UIBackgroundModes: [audio]`、`UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]`、`UILaunchScreen: {}`、`UIFileSharingEnabled: true`、`LSSupportsOpeningDocumentsInPlace: true`、`ITSAppUsesNonExemptEncryption: false`。

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
  licenses/LGPL-2.1.txt               # Releaseに添えるLGPL全文
  .gitattributes                      # *.sh text eol=lf
  .gitignore                          # VLCWithChat.xcodeproj/・App/Info.plist（生成物）・build/ を追加
```

`design-docs-for-ai/` は、feature ブランチにだけ載せ、マージ前の最後のコミットで `git rm` する（`CLAUDE.md` の運用）。

## 6. CI（`.github/workflows/build-ipa.yml`）

- **トリガー**：`push`（`main`・`feature/**`のブランチ）と、`push` のタグ `m0-*`。**`workflow_dispatch` は使わない**（ワークフローがデフォルトブランチ `main` にあるときしか実行できず、M0の間は `main` に載らないため）。Releaseの作成は、タグ `m0-<n>` をpushしたときだけ走らせる。
- **ジョブ `test`**：`macos-26`。`build` ジョブと同じXcode固定（`sudo xcode-select -s /Applications/Xcode_26.6.app`）の後、`swift test --package-path Packages/VLCChatCore`。
- **ジョブ `build`**（`test` の後）：`macos-26`。手順（番号は実行順）：
  1. checkout（`actions/checkout`）。
  2. Xcodeを固定する（`sudo xcode-select -s /Applications/Xcode_26.6.app`。`macos-26` の既定は26.6だが、ランナーイメージの更新で変わり得るため）。`xcodebuild -version` と `swift --version` をログに出す。
  3. `HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen ldid`。
  4. SwiftPMのキャッシュのrestore（`actions/cache/restore`、`id: cache`）。パスは `~/Library/Caches/org.swift.swiftpm` と `build/SourcePackages`、キーは `${{ runner.os }}-xcode26.6-` ＋ `project.yml` のハッシュ。xcframeworkが約382MBあるので必須。（タグ `m0-*` の実行は、featureブランチのキャッシュを復元できない可能性が高く、その場合は毎回取り直す。動作は壊れない。）
  5. `xcodegen generate`。
  6. 独立した手順 `xcodebuild -resolvePackageDependencies -project VLCWithChat.xcodeproj -clonedSourcePackagesDirPath build/SourcePackages`（`id: resolve`）。
  7. `bash scripts/make-ipa.sh`（実行権限に依存しないよう `bash` で呼ぶ。改行がLFで固定されるよう、`.gitattributes` に `*.sh text eol=lf` を置く）。
  8. キャッシュのsave（`actions/cache/save`。`key` は `steps.cache.outputs.cache-primary-key`、条件は `if: always() && steps.cache.outputs.cache-hit != 'true' && steps.resolve.outcome == 'success'`。`actions/cache` 単体はジョブ成功時にしか保存しないので、restoreとsaveに分け、失敗が続いても毎回取り直さないようにする。解決に失敗した不完全なキャッシュは保存しない）。
  9. `actions/upload-artifact`（ipa2つとビルドログ。`if: always()`、`if-no-files-found: warn`。失敗時も `xcodebuild.log` を残す）。
  10. タグ `m0-*` のpushのときだけ、`gh release create "$GITHUB_REF_NAME" build/vlc-with-chat-unsigned.ipa build/vlc-with-chat-fakesigned.ipa licenses/LGPL-2.1.txt --prerelease --notes ...`（`permissions: contents: write`、`env: GH_TOKEN: ${{ github.token }}`。タグが既に存在するので `--target` は不要。同じタグの再実行はReleaseが既にあって失敗するので、タグを切り直す。notesの内容は11.2節）。
  - actionsのメジャー版は、実装時に最新の安定版を確認して固定する。
- **`scripts/make-ipa.sh`**：`xcodebuild archive -project VLCWithChat.xcodeproj CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" -scheme VLCWithChat -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -archivePath build/VLCWithChat.xcarchive -clonedSourcePackagesDirPath build/SourcePackages CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO AD_HOC_CODE_SIGNING_ALLOWED=YES`、続けて `mkdir -p build/ipa/Payload`、`cp -R build/VLCWithChat.xcarchive/Products/Applications/VLCWithChat.app build/ipa/Payload/`、`(cd build/ipa && zip -qry ../vlc-with-chat-unsigned.ipa Payload)`（ipaのルートが `Payload/` になるよう、`build/ipa` の中で実行する）。`set -euo pipefail`。**冒頭で `mkdir -p build`**（`tee` の出力先が無いと、キャッシュなしの初回で `pipefail` により失敗する）。`xcodebuild` は `2>&1 | tee build/xcodebuild.log` でログを残す（`pipefail` で失敗を拾う）。出力は `build/vlc-with-chat-unsigned.ipa`。**続けて、`build/ipa` を別の場所（`build/ipa-fake`）にコピーし、そちらの `Payload/VLCWithChat.app/VLCWithChat`（`.app` ではなく中の実行ファイル）に `ldid -S`（entitlementsなし。`brew install ldid` をCIの手順に入れる）をかけて、`build/vlc-with-chat-fakesigned.ipa` を作る**（unsigned側を汚さない。SideStoreのMakefileは `ldid -S<entitlements>` を実行ファイルにかけている）。**Releaseに載せるのは、`vlc-with-chat-unsigned.ipa`・`vlc-with-chat-fakesigned.ipa`・`licenses/LGPL-2.1.txt`（実装時に https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt から取得してコミットする）の3つ**（チェック1が外れたときの往復を1回減らす）。**最後に、できたipaを機械的に確かめる**：`unzip -l` でルートが `Payload/VLCWithChat.app/` であること、`plutil -p`（`.app` 内の `Info.plist`）で `UIBackgroundModes` に `audio` があり `CFBundleVersion` が実行番号であること。どれかが外れたらスクリプトを失敗させる。
- ビルドに失敗したら、`gh run view <id> --log-failed` でログを読み、直して再pushする。

## 7. テスト方針

- ビジネスロジックをUIから分離する：計測の集計（`IntervalStats`）はPackageに分け、Swift Testingで単体テストする（観点：2件未満（空・1件）は `nil`、2件以上の最小/平均/最大（wall・mediaの両方）、窓の境界（`at == now - 30` は含まない）、直近N秒の窓から古い値が落ちること、`at` が前回以前の入力は捨てる（等しい場合も含む）、メディア時刻の差が負なら窓をリセットして新しい基準にする、`reset(at:)` から0.5秒間の記録は捨てる、`record` 時に、新しい記録の `at` を基準に窓より古い記録を捨てる、`reset()` 後は空）。UI・Player・ファイル・PiPの配線はテストしない（実機で確かめる）。
- 実際の再生・PiP・ロック・SideStoreは、8節の実機の手順で確かめる。

## 8. 動作確認手順（読み替え：iPhone実機。ユーザーの作業）

**前提のユーザー作業（SideStoreの導入）**：未導入。M0のチェック1の前に、最新の公式文書（https://docs.sidestore.io/docs/installation/prerequisites ・ `install`）に従って導入する。**導入時に、実装者（アシスタント）が手順を案内する**（Windows：LocalDevVPN（iPhone）→iTunes→iloader→SideStore。公式の前提条件ページの順）。iOS 26.6で動かない場合は、AltStoreでチェック1を代替できる（署名なしipaの取り込みの可否を確かめる目的は同じ）。

ipaは、タグ `m0-<n>`（`<n>` は1から連番）をpushして作る GitHub Releases の `m0-<n>` のページ（`https://github.com/5cd8/vlc-chat-ios/releases`）から、iPhoneのSafariでダウンロードし、「ファイル」アプリ経由でSideStoreに取り込む。

| ID | 内容 | 報告してほしいこと |
|---|---|---|
| チェック1（U1） | ipaをSideStoreで取り込み、署名・インストールして、アプリが起動するか | 成功/失敗、エラーメッセージ（スクリーンショット） |
| チェック2（U3〜U5、A〜F、H） | **MKV（VP9+Opus・AV1+Opus・H.264+AAC）、MP4（H.264）、WebM、正方形でないSAR（ピクセルの縦横比）の動画、4KのAV1と4KのVP9（H。iPhone 16はAV1のハードウェアデコードを持つ可能性があり、VP9のソフトウェアデコードの代わりにならないため、両方1本ずつ）** を1本ずつ選んで再生（上流 #250 の実態はSARの判定でvmem経路が弾かれる件で、Aの検証にSAR違いの動画を含める）。映像が出るか。シーク、一時停止中のシーク、0.5/1.0/2.0倍速（音程が保たれるか）、`.timeChanged` の間隔（情報パネルのmin/avg/max）。選択にかかった体感（ファイルをタップしてからピッカーが閉じるまで）と、再生開始までの時間（情報パネル）と、パス（アプリ内か）。アプリを終了して再起動し、「ブックマークから再生」。数GB・数時間のMKVを1時間再生して、メモリ（MB）が増え続けないか | 各ファイルの結果（映像・音声・シーク）、情報パネルの数値、ログファイル（「ログを共有」） |
| チェック3（U6） | 再生中に、PiP開始ボタンを押す。ホームへ戻って、自動でPiPになるか。PiP中の再生/一時停止・スキップ | PiPが出たか、`isPossible`、PiP中の操作の結果 |
| チェック4（U7） | 音声セッションの方針を「ライブラリ管理」にして（既定）、(a) PiPなしで再生中にロックする (b) PiPが出ている状態でロックする。次に「アプリ管理」へ切り替えて再起動し、(a)(b)を繰り返す。**(c) 自動PiPのスイッチをオフにして、他アプリに切り替える（ロックせず背面に回す）も、ライブラリ管理・アプリ管理の両方で試す。** **合否は3節U7の基準で判断する（ライブラリ管理(a)の停止は想定どおり）。アプリ管理で止まったときは、原因が映像出力（背面でも映像が動き続ける）かもしれないが、M0では切り分けず、ログ（ロックの検知・前面復帰時の状態）を持って相談する** | 4通りそれぞれで、ロック中に音が続くか、前面に戻ったときの状態 |

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
| D3 | SwiftVLCは `1.1.0-beta.14` を固定（ユーザー決定。12節） | `.applicationManaged`（G）が安定版に無い（grepで確認）。シークの修正が入っている | v1.0.0（Issueの記載通り。Gの2つ目の方針を試せない。外れたときの戻り先として残す） |
| D4 | アプリのSwift言語モードは5 | ローカルでコンパイルできず、strict concurrencyの修正でCI往復が増える | Swift 6（M1で移行を検討） |
| D5 | `fileImporter` に `[.item]` を渡す（拡張子で絞らない） | MKVなどに対応するUTIがiOSに無い可能性があり、絞ると選べない。PWAでも `accept` を付けない判断をした | `.movie` などで絞る |
| D6 | ロジックのPackageは `SwiftVLC` に依存させない | libVLCのコピーが2つできると未定義動作（IntegrationTopology） | PackageからSwiftVLCを使う（本実装でも、アプリ本体だけが依存する） |
| D7 | 計測値はアプリ内とログファイルで取り出す | Macが無く、Console・Instrumentsを使えない | Xcodeのデバッガー |

## 11. リスク

- **コンパイルの往復**：書いたSwiftが、CIで何度も落ちる可能性が高い（ローカルにコンパイラが無い）。SwiftVLCの宣言をタグのソースで確かめ、小さく作って、push→CIを素早く回す。
- **SwiftVLCは若く、メンテナは実質1人**。ベータを固定するので、不具合は自分で回避する必要がある。
- **SideStoreの不安定さ**：0.6.4はサインイン不能で、0.7.0-alphaを使う必要がある（アルファ版）。iOS 26.4以降のVPNエラーの報告もある。チェック1が外れたときの代替（AltStore）を用意しておく。
- **画面ロック中の音声**：SwiftVLCの既定では、PiPなしのロックで一時停止する可能性が高い（2節）。外れたら、本実装でバックグラウンド音声を仕様から外す（Issueの判断基準）。
- **PiPの無料署名での可否**：未確認。**外れても諦めずに原因を切り分ける**（ユーザーの決定。署名の制限かライブラリの実装かを調べ、結果を持って改めて相談する）。PiPが有効だとロック中も音声が続くため、バックグラウンド音声の見込みにも直結する。
- **ブックマークのオプション**：iOSで正しい値が確定できていない。実機で `.minimalBookmark` と `[]` を試す。
- M0の結果が、Issueの前提（SwiftVLC・SideStore）を変える場合は、計画を作り直す（ステップ2〜4に戻る）。

## 11.1 ブランチの起点とM0の終わり方（ユーザーに確認する）

- `feature/issue-1-m0-feasibility` は、未マージの `docs/repo-conventions`（CLAUDE.md）の上に積んでいる。実装セッションでこのブランチをそのまま使うか、`docs/repo-conventions` を先にPR・マージして `origin/main` から切り直すかを、実装に入る前に決める。
- M0の完了時に、`main` へPR・squashマージするか（骨組みをM1に引き継ぐなら、する）、実機の結果をIssueのコメントに残すかも、そのときに決める。
- Issueは「M0は使い捨てに近い最小のアプリ」と書くが、本計画は骨組みを引き継ぐ形（D1）にしている。また、ブックマーク経由の再生（U5）が外れたときは、Issueの判断（2が外れたらライブラリを見直す）ではなく、ファイルの取り込み方を相談する（ライブラリの問題ではないため）。この2点がIssueと違うので、計画のレビュー後にユーザーに確認する。

## 11.2 M0の後始末（ユーザーに確認する）

- タグ `m0-*` とReleaseは、featureブランチのコミットに付くため、squashマージ後も計画書（`design-docs-for-ai/`）を含む履歴が公開リポジトリに残る。M0が終わったら、タグとReleaseを消すか残すかをユーザーに確認する。
- 公開Releaseにlibvlc（LGPL-2.1+、静的リンク）入りのipaを置くので、LGPLの全文はReleaseのアセットに添える（notesには名称と入手先）。**ユーザーの決定（2026-10-13）：M0は公開Releaseのまま進める**。notesには、LGPL全文の同梱、SwiftVLCとlibVLCのソースの入手先、再ビルドの手順（CI定義 `.github/workflows/build-ipa.yml` と `scripts/make-ipa.sh`）を明記する。アプリ内表示など、それ以上の条件は本実装（M1以降）に入る前に、Issueの要件（設定画面のライセンス表示）に沿って詰め直す（LGPLの再リンクの手段を含む）。法的な確定判断ではない（アシスタントは法律の専門家ではない）。

## 11.3 作業ブランチ

`feature/issue-1-m0-feasibility`（`docs/repo-conventions` の上に積んでいる）。

## 12. 確定した事項（ユーザーの決定。2026-10-12）

- SwiftVLCは **1.1.0-beta.14** で始める（Issueの「M0は安定版 v1.0.0 で始める」は更新済み）。
- PiPは、チェック3が外れても**諦めない**。原因を切り分けて相談する（Issueの判断基準は更新済み）。
- SideStore周りの情報は、最新の公式文書で確認する（2節に反映済み。署名なしipaの直接取り込みだけは、文書に記載が無く、チェック1で確かめる）。
- ブランチ：実装セッションでも `feature/issue-1-m0-feasibility` をそのまま使う（`docs/repo-conventions` の上に積んだまま。11.1節）。
- Issueとの差（M0を骨組みを引き継ぐ形にすること、ブックマーク経由の再生が外れたときは「ファイルの取り込み方を相談」とすること）は、ユーザーが了承した（2026-10-13）。
- M0の公開Releaseのまま進める（11.2節）。
