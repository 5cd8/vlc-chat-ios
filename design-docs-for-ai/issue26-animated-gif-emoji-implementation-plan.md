# Issue #26 GIF絵文字をアニメーション表示する 実装計画

- 対象Issue: https://github.com/5cd8/vlc-chat-ios/issues/26 （アシスタントがヒアリング `/grill-with-docs` を経て起票したIssue。要件はIssue本文が唯一の情報源で、この計画は要約・言い換えをしない。迷ったらIssueを読む）
- スコープ: Issue全体（PRは分割しない）
- 読み替え（00 項目30）: 汎用テンプレートの「ブラウザ確認」は、このリポジトリでは「iPhone実機での確認」に当たる。Macは無く、ビルドはGitHub Actions、確認は人の手で行う（`CLAUDE.md`）。

## 1. ゴールと非ゴール

ゴール: チャット欄に出るGIFの絵文字を、行の途中でアニメーションさせる（Issue「範囲」「受け入れ条件」の全項目）。

Issue起票の後、計画のレビュー中にユーザーが確定（または了承）した次の3点も、ゴールに含める（Issue本文にも追記した）:
- 同じGIFが複数の行にあるとき、行ごとに独立して動かす（同期させない）。PC版 vlc-chat の Issue #21 の要件3と同じ（D-12）。
- 設定・プレイリスト・ファイル選択のシートがチャット欄を覆っている間は、背後のGIFを止める（D-05）。
- フレームの遅延が10ms以下のものは100msとして扱う（D-04）。

非ゴール（Issue「非ゴール」「未対策のリスク」と同じ）:
- アニメWebP・APNGの対応。PC版の変更。
- アニメの有効/無効スイッチ。メモリ上限の仕組み。

## 2. 実データの調査結果（設計の根拠）

PC版 `vlc-chat/publish/VLC-Chat-Replay-win-x64-single-20261006/emoji_cache.sqlite`（1,909件）を、先頭バイトとGIFのヘッダ・ブロックを読むPythonで集計した（Pillowは無いので自前のパーサー。読み取り専用で、コピーに対して実行）。

| 項目 | 結果 | 設計への影響 |
|---|---|---|
| 形式 | PNG 1,431／GIF 474／JPEG 4。**WebPは0、APNG（`acTL`チャンク）も0** | 範囲をGIFのみにする判断（Issue）は、実データでも妥当 |
| GIF | アニメーション473・1フレーム1 | 1フレームのGIFは静止画の経路に流す（D-02） |
| サイズ | アニメ473件すべて56×56px（URL末尾 `2.0`） | デコード後は高さ18pt×3＝54pxに描き直すので1フレーム約11.7KB。最大120フレームでも約1.4MB（D-07） |
| フレーム数 | 最小2・中央値22・最大120 | — |
| ループ回数 | 無限（`0`）471・`65535`2 | 常に無限ループにする判断（Issue）と矛盾しない |
| 最短の遅延 | 10ms以下のフレームを持つGIFが8件（該当フレームは全12,796枚中127枚。0msを含む） | 遅延の正規化が必要（D-04） |
| 部分フレーム | キャンバスより小さいフレームを持つGIFが34件。処分方法は 1（そのまま）・2（背景に戻す）・3（直前に戻す）が混在 | **合成済みのフレームが得られるかが正しさの要**（R-01）。実機で確認する |

実機確認用の代表GIF（`static-cdn.jtvnw.net/emoticons/` 以下、URL末尾 `/default/dark/2.0`）:
- 部分フレーム＋処分方法3: `v2/emotesv2_31e265da2f2f42cca348d617e2777546`（8フレーム）、`v2/emotesv2_61065789da5f49439398d349232ffcb9`（9フレーム）
- 部分フレーム＋処分方法2: `v2/emotesv2_c3c41154604c4b2c8d941b1d0b7b0c82`（63フレーム）
- 遅延0ms: `v2/emotesv2_4d5ecfb747d0408793d6da4632e757c2`（13フレーム）
- 最大120フレーム: `v2/emotesv2_f3607c515be64f7c876919a62d5e3326`

## 3. 現状のコード（行番号は `main` の 63d3bc7 時点）

- `App/Views/ChatRowView.swift:66-95` `bodyText`: 本文を1つの `Text` に連結。絵文字は `emoji.lookup(url:)` の結果で分岐し、`.image` は `Text(Image(uiImage: image))`（:84-85）。`.textSelection(.enabled)`（:62）が行全体にかかる。呼び出し元は `ChatPanelView.swift:100` の1か所だけ。
- `App/Chat/EmojiStore.swift`: `lookup`（:77）が `Lookup`（:12）を返す。キャッシュは `NSCache<NSString, UIImage>`（:28）、`countLimit = 1000`（:37）。読み込みは `startLoad`（:87）で `Task.detached` から `EmojiStore.makeImage(from:)`（:127）を呼ぶ。`makeImage` は `UIImage(data:)`（GIFは先頭1フレームのみ）→高さ18pt・scale 3に描き直す。`lookup` の呼び出し元は `ChatRowView` だけ（grepで確認）。
- `App/Views/ChatPanelView.swift`: `scenePhase`（:7）と `scrollPhase`（:13）を持つ。`scrollPhase` は `.onScrollPhaseChange`（:121）で更新される。一覧は `LazyVStack`（:98）。
- `App/Diagnostics/DiagnosticsModel.swift`: `pipActive`（:14）と `scenePhaseName`（:16）は `@Observable`。20秒ごとの負荷ログ `writeLoadLog`（宣言:79、ログの書式:98）が、CPU・熱・低電力モード・場面（PiP／背面／前面）を出す。`playbackStateText` のクロージャで再生状態を足す仕組み（:18、配線は `PlayerModel.swift:79`）。
- `Packages/VLCChatCore` は SwiftVLC に依存しない純Swiftのパッケージ（`Package.swift` のコメント）。CIの `swift test --package-path Packages/VLCChatCore` で、macOSランナー上でテストされる。アプリ本体にはテストターゲットが無い。
- 最小OSは iOS 18（`project.yml`）。`onScrollVisibilityChange` を使える。

## 4. 設計判断

各判断は「採用／理由／採らなかった案」。**★は、ユーザーから見える挙動に関わる判断。「Issue」はIssueで確定済みの要件の実現方法、「計画で決定」はIssueに書かれておらず、この計画が決めた挙動。ユーザーに確認して了承されたものは「確認済み」とした**。

### D-01 アニメの描き方: `Text` に連結した画像のフレームを差し替える ★（Issue）

- 採用: 絵文字をこれまでどおり `Text(Image(uiImage:))` で本文に連結したまま、再描画のたびに現在時刻に対応するフレームの `UIImage` に差し替える。
- 理由: Issueの「守る既存の挙動」（行内の折り返し・長押しの選択とコピー・URLのタップ）は、絵文字がテキストの一部であることに依存している。この方式なら3つとも仕組みを変えない。
- 採らなかった案:
  - 絵文字を別のViewにして行に並べる: 折り返しと選択が崩れる。
  - `UITextView` ＋ `NSTextAttachment` への作り直し: 規模が大きい。
  - `UIImage.animatedImage` を `Image` に渡す: SwiftUIの `Image` は先頭フレームしか描かない。
- **未検証の前提（R-02）**: 毎フレームの再描画で、長押しの選択が解除されないか。実機で確かめる。解除される場合は、自分で設計を変えず、実装を止めてユーザーに報告する（Issueの「守れる実装方式が見つからなければ再度相談」）。

### D-02 GIFの判定とデコード: ImageIO（`CGImageSource`）

- 採用: `CGImageSourceCreateWithData` で開き、`CGImageSourceGetType` が `UTType.gif` のときだけアニメの候補にする。フレーム数が2以上ならアニメ、1以下は既存の静止画の経路（`makeImage`）に流す。
- 理由: Appleの標準APIだけで済み、依存を足さない（ImageIOはiOSにもmacOSにもあるので、`VLCChatCore` に置いてCIでテストできる）。先頭バイトの手判定より、形式の判定をOSに任せるほうが堅い。
- 遅延: フレームごとに `kCGImagePropertyGIFUnclampedDelayTime` を読む。無ければ `kCGImagePropertyGIFDelayTime`、それも無ければ0として扱う。[Apple: kCGImagePropertyGIFUnclampedDelayTime](https://developer.apple.com/documentation/imageio/kcgimagepropertygifunclampeddelaytime)（`DelayTime` と違い、下限でクランプされない値）。
- 採らなかった案: `CGAnimateImageDataWithBlock`（ImageIO、iOS 13以降）。GIFごと・行ごとに独自のタイミングで動くので、1つの時計とD-12の行ごとの開始時刻に合わない。R-01で合成が崩れたときの比較対象として挙げておく。
- 合成: フレームは `CGImageSourceCreateImageAtIndex` で取る。GIFの部分フレームと処分方法がImageIO側で合成されるかは、一次情報で確かめられていない。そこでテストの代わりに、2章の代表GIFを実機で目視する（R-01）。崩れるGIFが見つかったら、自分で合成する案を計画に足すためにユーザーへ報告する。

### D-03 時計: アプリ全体で1つの `EmojiAnimationClock`（最大60Hz）

- 採用: `@Observable` の `EmojiAnimationClock` が `time`（アニメの経過秒）を持ち、`CADisplayLink` で進める。`preferredFrameRateRange` は最小30・最大60・希望60。動いている間だけ `time` が進み、止まっている間は値が変わらない（行は再描画されない）。
- 理由: 実データの全12,796フレームの遅延は、中央値40ms・10ms以下が127枚（1%）・最大1,600ms。中央値の40msを30Hz（約33ms刻み）で描くと、5フレーム（200ms）のうち4枚が33ms、1枚が67msで表示されて、動きが不揃いに見える。60Hz（約17ms刻み）なら、40msのフレームの表示時間の誤差は17ms以内に収まる。時計を1つにして、各行は登録した時点の`time`からの経過で自分のフレームを選ぶ（D-12。行・GIFごとのタイマーを持たない）。
- コスト: 再描画されるのは、画面に見えていてGIFを含む行だけ（D-06）で、時計はその行が1つ以上あるときだけ回る（D-11）。負荷が重ければ、希望を30に下げる1行の変更で済む（R-03）。
- 低電力モード: [Apple: preferredFrameRateRange](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange)によると、システムは低電力モードなどで間隔を広げることがある。Issueは「低電力モードでも動かす」なので、止めはしない（頻度が下がるのは許容）。
- 時間の進め方: 前回との差を足す。停止からの再開直後に大きく飛ばないよう、1回の差は0.1秒までにする。再開時の最初の呼び出しは基準を取るだけにする。
- 採らなかった案: `TimelineView(.animation)` を行ごとに置く。PiP・スクロール・背面の停止をまとめて制御しにくく、時計が行の数だけ増える。

### D-04 遅延の正規化: 10ms以下は100msとして扱う ★（確認済み。Issueに追記）

- 採用: 遅延が0.01秒以下なら0.1秒にする。他の値はそのまま。
- 理由: 10ms以下を100msにするのは、WebKitとFirefoxが採る慣習（[WebKit Bugzilla 36082](https://bugs.webkit.org/show_bug.cgi?id=36082)、[Mozilla Bugzilla 139677](https://bugzilla.mozilla.org/show_bug.cgi?id=139677)）で、Chromiumも同様と報じられている（二次情報）。正規化しないと、実データの8件のGIF（127フレーム。0msを含む）が最大速度で回って見える。
- 境界は「0.01以下」。ImageIOが返すDoubleの誤差を避けるため、比較は `<= 0.01 + 1e-6`。

### D-05 動かす条件: 4つの入力から1つの真偽を決める ★（Issue。`.inactive`・`.tracking`・`.animating`・シート表示中でも止める点は確認済み）

- 採用: `EmojiAnimationGate.shouldAnimate(isForeground:isPiPActive:isScrolling:isCovered:) -> Bool` を `VLCChatCore` に置く。`isForeground && !isPiPActive && !isScrolling && !isCovered` のときだけ真。`ChatPanelView` が `scenePhase == .active`、`app.diagnostics.pipActive`、`scrollPhase != .idle`、`PlayerScreen`から受け取った`isCovered`（5.14）を渡し、結果で `EmojiAnimationClock.setGateOpen(_:)` を呼ぶ（実際に回すかは、D-11の登録数と合わせて決まる）。
- 理由: Issueの条件（バックグラウンドで止める／PiP中は止める／スクロール中は止める／動画の一時停止では止めない）と、確認済みの「シートが覆っている間は止める」を1か所の式にする。動画の再生状態は入力に含めない（一時停止しても動かし続ける）。
- `scrollPhase != .idle`: `.tracking`（指が触れた）・`.interacting`・`.decelerating`・`.animating`のどれでも止める。
- `scenePhase`: `.inactive`（通知センターを引き下げたときなど）でも止める。`.active` だけ動かす。
- `isCovered`: 設定シート・プレイリストシート・ファイル選択（`.fileImporter`）のどれかが開いている間は真。シートは`scenePhase`を変えないので、`PlayerScreen`の`showsSettings`・`showsPlaylist`・`showsFileImporter`から作る。確認ダイアログ（`.alert`）は小さいので含めない。
- 「視差効果を減らす」（`accessibilityReduceMotion`）と低電力モード（`isLowPowerModeEnabled`）は**読まない**（Issueの決定。入力に含めない）。
- `scrollPhase`が`.animating`になるのは、利用者の操作以外（`proxy.scrollTo`など）でもあり得る。最下部追従中に新着でGIFが途切れて見えるかは、実機で確かめる（8章の手順14）。ただし`ChatPanelView.swift:125-127`の`scrollTo`は`disablesAnimations`付きなので、`.animating`にならない可能性が高い（それも手順14で確かめる）。Issueは「プログラムによる自動スクロール中も止める」と決めているので、途切れて見えても実装者は条件を変えず、実装を止めてユーザーに報告する。
- 「PiPがアクティブ」は `diagnostics.pipActive`（`PlayerModel.attachPiP` が更新、:420-432）を使う。PiPが始まっても前面のままのとき（アプリ内のPiPボタン）に止めるため、`scenePhase` だけでは足りない。

### D-06 画面に見えている行だけを動かす ★（Issue）

- 採用: `ChatRowView` が `@State private var isVisible = false` を持ち、`.onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }` で更新する。時計への登録（D-11）が済んでいる行（`isRegistered`＝画面に出ていて、見えていて、アニメ絵文字を含む）だけが`bodyText`で`clock.time`を読んでフレームを選ぶ。そうでない行は`clock.time`を読まず、先頭フレームを使う。
- 理由: Observationは、`body` の評価中に実際に読んだプロパティだけを追跡する。画面外の行は `clock.time` を読まないので、時計が進んでも再描画されない。`LazyVStack` が画面外の行を保持するかどうかは、実装の都合で変わり得る。保持されていても再描画されないよう、この明示的な読み分けで保証する。
- 一次情報: [Apple: onScrollVisibilityChange(threshold:_:)](https://developer.apple.com/documentation/swiftui/view/onscrollvisibilitychange(threshold:_:))（iOS 18.0+。「画面に出た時点で既に閾値を満たしていれば、アクションが呼ばれる」）。
- （計画で決定）初回の挙動: 行が作られてからアクションが呼ばれるまでの一瞬は、先頭フレームの静止画で描かれる。許容する。
- （計画で決定）閾値0.1: 行が10%でも見えていれば動かす。

### D-07 メモリ: Issueどおり上限を設けない ★（Issue）

- 採用: デコード済みの全フレームを `UIImage` の配列として `NSCache`（既存、`countLimit = 1000`）に入れる。GIF専用の上限は設けない。
- 見積もり（実データ）: 1フレーム＝高さ54px（18pt×3）×幅54px（56×56の元画像）×4バイト≒11.7KB（4バイト/pxの前提。`UIGraphicsImageRendererFormat`の既定の色域で実際に何バイトになるかは、D-10のログの`1枚=`で実機で確かめる）。中央値22フレームで約260KB、最大120フレームで約1.4MB。473種類すべてを一度に読み込む最悪ケースでも、全フレーム12,796枚×約11.7KB≒150MB。1つのチャットで実際に使う種類数は、この一部にとどまる。
- 元画像が大きいGIF（ライブラリの上限は1個5MB）でも、保持するのは描き直した後のフレームだけ（高さは常に54px）。デコード中の元のフレームは1枚ずつ描き直して手放し、`CGImageSource`にもデコード結果を溜めさせない（`kCGImageSourceShouldCache: false`、5.2）。
- リスクは Issue の「未対策のリスク」のとおり。メモリ不足が実機で出たら、別Issueで上限を検討する。

### D-08 キャッシュの型: `NSCache` の値を `CachedEmoji`（静止画かアニメ）にする

- 採用: `NSCache<NSString, CachedEmoji>`。`CachedEmoji` は `enum Kind { case still(UIImage), animated(AnimatedEmoji) }` を持つ`final class`（`NSCache` の値は参照型にする）。`Lookup` に `.animated(AnimatedEmoji)` を足す。
- 理由: 既存の世代管理（`generation`）・`inFlight`・`missing`・`revision` の仕組みをそのまま使え、読み込み経路が1本で済む。
- 採らなかった案: アニメ用のキャッシュを別に持つ。読み込みの完了通知・世代管理が二重になる。

### D-09 静止画の経路は変えない ★（Issue）

- `makeImage(from:)` はそのまま残し、1フレームのGIF・PNG・JPEG・アニメの途中でデコードに失敗したGIF（先頭フレームの静止画にフォールバック）に使う。Issue受け入れ条件6（静止画の見た目と高さが同じ）を、コードを共有して担保する。描き直しの部分は `redraw(_ source: UIImage, size: CGSize) -> UIImage` として切り出し、静止画とアニメの各フレームで同じ関数を通す。

### D-10 診断ログ（恒久）

- 負荷ログ（20秒ごと）に、アニメの状態を足す: `GIF=動作中(行=<登録数>)`／`GIF=停止(行=<登録数>)`。登録数は、動かす行の数（D-11）。登録と解除が対になっているかを実機で確かめる手がかりにもなる。`DiagnosticsModel` に `animationStateText` のクロージャを足し、`AppModel` が `EmojiAnimationClock.isRunning` を結ぶ（`playbackStateText` と同じ作り）。場面（前面／PiP／背面）と並べて、受け入れ条件3をCPU使用率で確かめるため。
- アニメの読み込み時に、最初の20件だけ `GIF絵文字 url=<url> フレーム=<n> 周期=<秒>s 1枚=<バイト> 所要=<ms>` をログに残す（`loggedMissing` と同じ上限の考え方。`url=`は既存の`絵文字なし url=`と同じ書式）。`1枚`は先頭フレームの`cgImage`の`bytesPerRow × height`、`所要`はデコードと描き直しの全体の時間。遅延の正規化・フレーム数・1フレームのバイト数を、実機で代表GIFと突き合わせる手がかりになる。

### D-11 時計は、動かすGIFを含む行が1つ以上あるときだけ回す

- 採用: `EmojiAnimationClock`は、D-05のゲートが開いていて、かつ「画面に見えていて、アニメ絵文字を含む行」が1つ以上あるときだけ`CADisplayLink`を動かす。行は、その条件が変わるたび（出現・消失・読み込み完了）に時計へ登録・解除する。
- 理由: GIFが画面内に無いチャット（ライブラリが無い、GIFが出ない配信）でも60Hzで主スレッドを起こし続けると、行は再描画されなくても電力を使い、ProMotion機で画面のリフレッシュレートが下がるのを妨げ得る。実機確認の手順5のCPU比較も、時計が回ること自体の負荷が混ざらないようにする。
- 状態遷移（ゲート×登録数→動かす／止める）は、テストできるよう`VLCChatCore`の`AnimationRunState`（5.13）に置く。
- 採らなかった案: ゲートだけで回す。上の理由で採らない。

### D-12 同じGIFは、行ごとに独立して動かす ★（確認済み。Issueに追記）

- 採用: 各行は、時計に登録した時点の`time`を`@State private var startTime`に保存し、`clock.time - startTime`（0未満は0）を`AnimatedEmoji.frame(at:)`に渡す。行が見え始めるたびに、その行のGIFは先頭フレームから動き出す。1つの行に複数のGIFがあるときは、同じ`startTime`を共有する。
- 「独立」の意味: 各行が自分の見え始めた時点から動き出す、ということ。チャットを開いた直後や、スクロールを止めた瞬間のように、複数の行が同時に見え始めたときは、それらの行が揃って動き出す（時計がスクロール中は止まっているため）。PC版も、各行がそれぞれの読み込み完了から動き出すので、同じ性質を持つ。
- 初回読み込みの例外: 読み込みの完了は100msごとにまとめて通知される（`EmojiStore.scheduleRevision`）ので、別々の時点で見え始めた行でも、未読み込みのGIFを含む行は同じ瞬間に登録されて揃う。起きるのは各GIFの初回表示だけ。
- （計画で決定）後から読み込みが終わったGIFは、`startTime`が行の登録時点のままなので、行の途中のフレームから動き出す（1つの行の中で、先に動いていたGIFと位相が揃う）。
- チャットを切り替えるときは、必ず`ChatModel.reset()`か`load()`を通って`ChatPanelView.content`が一覧ごと作り直されるので、行の`@State`（`isRegistered`・`startTime`）は引き継がれない。
- 理由: PC版 vlc-chat の Issue #21 の要件3（同じGIFが複数の行にあるとき、行ごとに独立して動かす）と同じ挙動にする（`CONTEXT.md`は、チャットの装飾の規則はPC版を一次情報とする）。時計は1つのままで、行ごとの状態は`startTime`だけで済む。
- 採らなかった案: 全行を時計の`time`で同期させる。同じGIFが全行で同じフレームになり、途中のフレームから始まる。PC版と挙動が違う。

## 5. 変更するファイル

### 5.1 `Packages/VLCChatCore/Sources/VLCChatCore/AnimationTiming.swift`（新規）

```swift
import Foundation

/// アニメーション画像の各フレームの表示時間と、時刻から表示するフレームを選ぶ規則。
/// 遅延は、10ms以下を100msとして扱う（WebKit・Firefoxの慣習。D-04）。常に無限ループする。
public struct AnimationTiming: Equatable, Sendable {
  public let delays: [TimeInterval]      // 正規化後
  public let loopDuration: TimeInterval  // delays の合計

  public init(rawDelays: [TimeInterval])
  public static func normalizedDelay(_ raw: TimeInterval) -> TimeInterval
  /// `time`（0以上）が属するフレームの添字。周期で折り返す。負の値・非有限（NaN・無限大）は0。フレームが無ければ0。
  public func frameIndex(at time: TimeInterval) -> Int
}
```

各フレームの終了時刻の累積は、初期化時に`private let ends: [TimeInterval]`として作る。`loopDuration` は、その最後の値そのものにする（別の足し算で求めて、浮動小数点の誤差で食い違わせない）。`frameIndex` は、各フレームの終了時刻の累積を作っておき、`time.truncatingRemainder(dividingBy: loopDuration)` に対して二分探索（`end > t` となる最初の添字）で選び、結果は`min(index, delays.count - 1)`に丸める（範囲外を読まない保険）。境界の時刻ちょうどは次のフレームに属する。`loopDuration` は正規化により常に0より大きい（フレームがあれば）。

### 5.2 `Packages/VLCChatCore/Sources/VLCChatCore/GifSource.swift`（新規）

```swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// GIFのフレームと遅延を、ImageIOで1枚ずつ読む窓口。デコード済みの全フレームを保持しない
/// （呼び出し側が1枚ずつ取り出して縮め、元の大きさのフレームを溜めないため）。
public struct GifSource {
  public let frameCount: Int
  /// GIFでない・開けない・`frameCount == 0` のときは nil。
  public init?(data: Data)
  /// `CGImageSourceCopyPropertiesAtIndex` の結果の `kCGImagePropertyGIFDictionary` の中から、
  /// Unclamped → DelayTime → 0 の順に読む。範囲外の添字は 0。
  public func rawDelay(at index: Int) -> TimeInterval
  /// 範囲外の添字は nil。
  public func frame(at index: Int) -> CGImage?
}
```

`init?` は、`CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)` が成功し、`CGImageSourceGetType(source)` が `UTType.gif.identifier` に等しいときだけ成功する。`frame(at:)`の`CGImageSourceCreateImageAtIndex`の options にも`[kCGImageSourceShouldCache: false]`を渡す。`CGImageSource` は`Sendable`ではないので、`GifSource` も`Sendable`にしない（1つの `Task.detached` の中で使い切る）。

### 5.3 `Packages/VLCChatCore/Sources/VLCChatCore/EmojiAnimationGate.swift`（新規）

```swift
/// GIF絵文字のアニメを動かしてよいか（Issue #26の条件を1か所にまとめたもの）。
/// `isCovered` は、シート（設定・プレイリスト・ファイル選択）がチャット欄を覆っているか。
/// 動画の再生状態は条件に含めない（一時停止中も動かし続ける）。
public enum EmojiAnimationGate {
  public static func shouldAnimate(isForeground: Bool, isPiPActive: Bool, isScrolling: Bool, isCovered: Bool) -> Bool {
    isForeground && !isPiPActive && !isScrolling && !isCovered
  }
}
```

### 5.4 `App/Chat/AnimatedEmoji.swift`（新規）

```swift
import UIKit
import VLCChatCore

/// 高さ18ptに描き直した全フレームと、その表示時間。作った後は変えない。
final class AnimatedEmoji: Sendable {
  let frames: [UIImage]
  let timing: AnimationTiming   // frames.count == timing.delays.count
  init(frames: [UIImage], timing: AnimationTiming)
  func frame(at time: TimeInterval) -> UIImage { frames[timing.frameIndex(at: time)] }
}
```

### 5.5 `App/Chat/EmojiAnimationClock.swift`（新規）

```swift
import Observation
import QuartzCore
import VLCChatCore

/// GIF絵文字のアニメの時計。動いている間だけ `time` が進む（D-03・D-11）。
@Observable
@MainActor
final class EmojiAnimationClock {
  private(set) var time: TimeInterval = 0
  /// `CADisplayLink` が動いているか（ゲートが開いていて、動かす行が1つ以上ある）。診断ログが読む。
  var isRunning: Bool { runState.isRunning }
  /// 登録中の行の数。診断ログが読む。
  var demandCount: Int { runState.demand }
  @ObservationIgnored private var runState = AnimationRunState()
  @ObservationIgnored private var accumulator = AnimationClockAccumulator()
  @ObservationIgnored private var link: CADisplayLink?
  @ObservationIgnored private var ticker: Ticker?
  /// D-05のゲート。`ChatPanelView` が渡す。
  func setGateOpen(_ open: Bool)
  /// 動かす行の登録・解除（D-11）。`ChatRowView` が呼ぶ。登録した行は、必ず解除する。
  func addDemand()
  func removeDemand()
}
```

実装の要点:
- 状態遷移は`VLCChatCore`の`AnimationRunState`（5.13）が決める。`setGateOpen`・`addDemand`・`removeDemand`はそれを呼び、戻り値が`.start`／`.stop`のときだけ`CADisplayLink`を作る／`invalidate()`する。`isRunning`は`runState.isRunning`、`demandCount`は`runState.demand`を返す。
- 時間の進め方は`VLCChatCore`の`AnimationClockAccumulator`（5.12）に任せる。`fire`は`accumulator.advance(to: link.timestamp)`を呼び、**値が変わったときだけ**`time = accumulator.time`を代入する（`@Observable`が同じ値の代入を通知するかに依存しないよう、基準を取るだけの呼び出しでは代入しない）。止めるときは`accumulator.pause()`。
- `CADisplayLink` は`NSObject`のターゲットが要るので、`@objc func fire(_:)` を持つ小さな`@MainActor private final class Ticker: NSObject`を内部に置き、クロージャで`EmojiAnimationClock`に通知する（`self`を強参照しないよう`weak`で受ける）。`link.add(to: .main, forMode: .common)`なので呼び出しはメインスレッドで、`@MainActor`と整合する。`deinit` ではなく、止めるときに`invalidate()`する。
- 起動: `link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)`。
- 追跡するのは`time`だけ。`runState`・`accumulator`・`CADisplayLink`は`@ObservationIgnored`にする（`EmojiStore`と同じ理由）。`isRunning`・`demandCount`は`runState`から計算するので、保存プロパティにしない。

### 5.6 `App/Chat/EmojiStore.swift`（変更）

- `import VLCChatCore`を足す（`GifSource`・`AnimationTiming`を使う）。
- `Lookup` に `case animated(AnimatedEmoji)` を足す。
- `cache` を `NSCache<NSString, CachedEmoji>` にする。`CachedEmoji` は`final class`（`enum Kind { case still(UIImage), animated(AnimatedEmoji) }`を持つ。`Sendable`）。
- `lookup`: キャッシュにあれば`kind`に応じて`.image`／`.animated`を返す。
- `isAnimated(url: String) -> Bool` を足す。`revision`を読み、キャッシュだけを見る（読み込みは始めない）。キャッシュに`.animated`があれば真。`ChatRowView`が、行にアニメ絵文字が含まれるかを調べるために使う（5.7）。
- `startLoad`: `Task.detached` の中で `EmojiStore.makeEmoji(from: data)` を呼び、前後の時刻から `decodeSeconds: TimeInterval` を測る。`finishLoad` の引数を`UIImage?`から`CachedEmoji?`に替え、`decodeSeconds: TimeInterval`を足す（D-10のログの`所要=`に使う）。
- `makeEmoji(from: Data) -> CachedEmoji?`（`nonisolated static`）:
  1. `GifSource(data:)` が成功し`frameCount > 1`のとき、各フレームについて `autoreleasepool { frame(at:) → UIImage(cgImage:) → redraw }` を行い、`frames`と`rawDelay`を集める（`autoreleasepool`で、描き直しの中間オブジェクトをループ中に溜めない。D-07）。描き直す大きさは、**先頭フレームの大きさから1回だけ決め、全フレームに同じ大きさを使う**（フレームごとに幅がぶれて行が揺れるのを避ける）。部分フレームが合成されずに先頭フレームがキャンバスより小さい場合は、R-01の確認で見つかるので、そのとき見直す。1枚でも失敗したら、アニメをあきらめて手順2へ。
  2. それ以外は`makeImage(from:)`の結果を`.still`で包む（失敗なら`nil`）。
- `makeImage(from:)` は、`UIImage(data:)` の後の描き直しを`redraw(_:size:)`に切り出す以外は変えない（静止画は従来どおり`size`を元画像から計算して渡す）。`redraw`は`nonisolated static func`にする（`Task.detached`から呼ぶため。`EmojiStore`は`@MainActor`）。中身は元の`makeImage`の本体（`UIGraphicsImageRenderer`・`scale = 3`・`opaque = false`）をそのまま移す。
- `loggedAnimated` を足し、最初の20件の読み込みを`finishLoad`の中（`@MainActor`上）でログに残す（D-10）。`loggedMissing`と同じく`libraryChanged()`で0に戻す。

### 5.7 `App/Views/ChatRowView.swift`（変更）

- `let clock: EmojiAnimationClock` を足す。`@State private var isVisible = false`、`@State private var isAppeared = false`、`@State private var isRegistered = false`、`@State private var startTime: TimeInterval = 0` を足す。
- 行の最外側（`.textSelection(.enabled)` の後）に `.onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }` を足す。
- 時計への登録（D-11）:
  ```swift
  /// 画面に出ていて、見えていて、アニメ絵文字を含む。
  private var needsClock: Bool {
    isAppeared && isVisible && message.runs.contains { run in
      if case .emoji(let url, _) = run { return emoji.isAnimated(url: url) }
      return false
    }
  }
  // 最外側の修飾子に足す
  .onAppear { isAppeared = true }   // `isAppeared`が変われば`needsClock`も変わり、`onChange`が登録する
  .onDisappear {
    isAppeared = false
    isVisible = false             // 古い可視の値を残さない（再表示で、画面外のまま登録されないように）
    syncClockDemand(false)        // 行が消えると `onChange` が届かないことがあるので、ここで直接解除する
  }
  .onChange(of: needsClock, initial: true) { _, needs in syncClockDemand(needs) }

  private func syncClockDemand(_ needs: Bool) {
    guard needs != isRegistered else { return }
    isRegistered = needs
    if needs {
      startTime = clock.time   // この行のGIFは、ここから先頭フレームで動き出す（D-12）
      clock.addDemand()
    } else {
      clock.removeDemand()
    }
  }
  ```
  登録は`onChange`の1本だけで、`isAppeared`が真の間にしか起きない（`onAppear`は`isAppeared`を真にするだけで、登録は呼ばない。状態の更新は`onAppear`の中ではまだ反映されず、古い値を読むため）（`LazyVStack`が画面外の行を保持していても、`onDisappear`の後は登録されない）。解除は`onChange`と`onDisappear`の2経路。どれも`syncClockDemand`を通り、`isRegistered`が真の間だけ`addDemand`済みなので、登録と解除は必ず対になり、二重にならない（`syncClockDemand`は同じ値なら何もしない）。
- `bodyText` の`switch`に`case .animated(let animated)`を足す:
  ```swift
  let image = isRegistered ? animated.frame(at: max(0, clock.time - startTime)) : animated.frames[0]
  result = result + Text(Image(uiImage: image))
  ```
  `clock.time`は`isRegistered`が真の分岐の中でだけ読む（D-06）。`startTime`への代入は`onChange`の中なので、`body`の追跡には入らない。

### 5.8 `App/Views/ChatPanelView.swift`（変更）

- `ChatRowView(message:emoji:)`（:100）に`clock: app.emojiClock`を足す。
- 動かす条件を計算プロパティにまとめる:
  ```swift
  private var shouldAnimate: Bool {
    EmojiAnimationGate.shouldAnimate(
      isForeground: scenePhase == .active, isPiPActive: app.diagnostics.pipActive,
      isScrolling: scrollPhase != .idle, isCovered: isCovered)
  }
  ```
  `isCovered`は`ChatPanelView`の新しい引数（`let isCovered: Bool`）で、`PlayerScreen`が渡す（5.14）。
- `body`の修飾子に`.onChange(of: shouldAnimate, initial: true) { app.emojiClock.setGateOpen(shouldAnimate) }`と、`.onDisappear { app.emojiClock.setGateOpen(false) }`を足す（チャット欄が無くなったらゲートを閉じる）。
- 既存の`.onChange(of: chat.store.map { ObjectIdentifier($0) })`（:40）の中に`scrollPhase = .idle`を足す。チャットが替わって一覧のScrollViewが作り直されても、`scrollPhase`が操作中のまま残ってGIFが止まり続けないようにするため（`.onScrollPhaseChange`は変化があったときしか呼ばれない）。

### 5.9 `App/AppModel.swift`（変更）

- `let emojiClock = EmojiAnimationClock()` を`emoji`（:23）の隣に足す。
- `init`の中で、`playback.navigationState = …`（:73付近）の後に `diagnostics.animationStateText = { [emojiClock] in "GIF=\(emojiClock.isRunning ? "動作中" : "停止")(行=\(emojiClock.demandCount))" }` を足す（隣の`playback.earlyAdvanceEnabled = { [settings, playlist] in … }`と同じ、`[プロパティ]`で捕まえる書き方）。

### 5.10 `App/Diagnostics/DiagnosticsModel.swift`（変更）

- `@ObservationIgnored var animationStateText: @MainActor () -> String = { "GIF=-" }` を`playbackStateText`（:18）の隣に足す。
- `writeLoadLog`（:98）の書式の末尾に`%@`を足し、`animationStateText()`を渡す（`"… 場面=%@ %@ %@"`）。

### 5.11 `CONTEXT.md`（変更）

用語に1項目を足す。既存の項目と同じ書式（`**用語 (English)**:` の次の行に定義）にする:

    **アニメーション絵文字 (Animated Emoji)**:
    絵文字ライブラリの画像のうち、2フレーム以上のGIF。チャット欄で、見えている間だけアニメーションする。1フレームのGIFと、PNG・JPEGは静止画の絵文字として扱う。

### 5.12 `Packages/VLCChatCore/Sources/VLCChatCore/AnimationClockAccumulator.swift`（新規）

```swift
import Foundation

/// 表示のタイムスタンプ（`CADisplayLink.timestamp`）の列から、止まっている間を除いた経過秒を作る。
/// 1回の進みは `maxStep` までにする（停止からの再開や、主スレッドの停滞で、アニメが飛ばないように）。
public struct AnimationClockAccumulator: Sendable {
  public private(set) var time: TimeInterval = 0
  public init()
  /// 最初の呼び出し（または`pause()`の後の最初）は、基準を取るだけで`time`を進めない。
  /// 差が0未満（時刻が逆戻りした）ときも進めず、基準だけを更新する。
  public mutating func advance(to timestamp: TimeInterval, maxStep: TimeInterval = 0.1)
  /// 止める。次の`advance`は基準を取り直す。`time`は保つ。
  public mutating func pause()
}
```

### 5.13 `Packages/VLCChatCore/Sources/VLCChatCore/AnimationRunState.swift`（新規）

```swift
/// 時計を動かすかどうか: ゲート（D-05）が開いていて、動かす行が1つ以上ある（D-11）。
public struct AnimationRunState: Equatable, Sendable {
  public enum Transition: Equatable, Sendable { case none, start, stop }
  public private(set) var gateOpen = false
  public private(set) var demand = 0
  public var isRunning: Bool { gateOpen && demand > 0 }
  public init()
  /// 以下の3つは、動かす／止めるが変わったときだけ `.start`／`.stop` を返し、変わらなければ `.none`。
  /// 3つとも `@discardableResult`（戻り値を見ない呼び出しで、未使用の警告を出さないため）。
  @discardableResult public mutating func setGateOpen(_ open: Bool) -> Transition
  @discardableResult public mutating func addDemand() -> Transition
  @discardableResult public mutating func removeDemand() -> Transition   // demand が 0 のときは何もしない（.none）
}
```

### 5.14 `App/Views/PlayerScreen.swift`（変更）

- `ChatPanelView(app: app)`（:25）を`ChatPanelView(app: app, isCovered: showsPlaylist || showsSettings || showsFileImporter)`にする（D-05）。`showsPlaylist`・`showsSettings`・`showsFileImporter`は既存の`@State`（:8-11）。

## 6. テスト方針

テストは`Packages/VLCChatCore/Tests/VLCChatCoreTests/`に置き、既存に合わせてSwift Testing（`import Testing`・`@Test`・`#expect`、`@testable import VLCChatCore`）で書く。

ビジネスロジックは`VLCChatCore`に置いて`swift test`（CI、macOSランナー）で検証する。アプリ本体にテストターゲットは無く、今回は足さない（`Text`の描画・`CADisplayLink`・SwiftUIの可視判定は実機の人手確認で見る）。期待値は規則から手計算する。比較は、2進で正確に表せる値（0.25・0.5・0.0625）を使って`==`で行うか、それ以外の値（0.01・0.02・0.1、周期0.6など）は`abs(a - b) < 1e-9`で行い、浮動小数点の誤差を避ける。

### 6.1 `AnimationTimingTests.swift`（新規）

- `normalizedDelay`: 0→0.1、0.01→0.1（境界）、0.02→0.02、0.1→0.1。
- `frameIndex`（遅延 [0.25, 0.5, 0.25]、周期1.0）: 時刻0→0、0.25→1（境界は次のフレーム）、0.5→1、0.75→2、1.0→0（折り返し）、2.5→1（2.5を1.0で割った余り0.5）。負の時刻→0、NaN→0、+∞→0。
- 遅延に0.0が含まれるとき（[0.0, 0.5]）は正規化で0.1になるので、周期0.6・時刻0.1→1。
- フレームが無い（空配列）→ `frameIndex`は0、`loopDuration`は0。
- 遅延 [0.25, 0.5, 0.25]: `loopDuration == 1.0`（`==`で比べる）。周期の直前の時刻0.9375 → 2（0.9375は2進で正確に表せる）。

### 6.2 `GifSourceTests.swift`（新規）

テスト内で`CGImageDestination`（`UTType.gif`）を使い、2×2pxの単色GIF（赤・緑・青の3フレーム、`kCGImagePropertyGIFDelayTime`は0.25・0.5・0.25）を作る。
- `frameCount == 3`、各`rawDelay`が0.25・0.5・0.25（0.001以内）。
- `frame(at: 1)`を1×1の`CGContext`（sRGB・RGBA8・`premultipliedLast`）に縮めて描き、G ≥ 200 かつ R・B ≤ 55（GIFのパレットと色空間の変換で値が多少ずれても通る許容幅）。
- `kCGImagePropertyGIFDelayTime`と`kCGImagePropertyGIFUnclampedDelayTime`の**両方**に0.02と0を書いたGIFで、`rawDelay`が0.02と0（クランプされた`DelayTime`の0.1を読んでいない）。GIF形式の遅延は1つ（センチ秒）なので、見分けられるのは0のフレームだけ（クランプされた`DelayTime`は0を0.1にする）。0のフレームで`rawDelay`が0を返すことを確かめる。0.02は、クランプの有無を見分けられないが、値の読み取りの確認として残す。書き込み側が0を保存しないなら、このテストは外し、実機の診断ログ（D-10）で確かめる。
- 1フレームのGIFは`frameCount == 1`。
- PNGのデータ（`CGImageDestination`で作る）は`nil`。空のData・`"GIF89a"`の6バイトだけのData・画像でないバイト列は`nil`。
- `init?`は、`frameCount == 0`のときも`nil`にする（GIFのヘッダで始まるが中身が読めないデータの扱いを決めておく）。範囲外の添字は、`rawDelay`が0、`frame(at:)`が`nil`を返す。テストで確かめる。

注: ImageIOの書き込み側が遅延をそのまま保存するかは実行して確かめる。値がずれるなら、期待値ではなくテストの作り方（プロパティの渡し方）を見直す。

### 6.3 `EmojiAnimationGateTests.swift`（新規）

4つの真偽の全16通りを表にして、真になるのは`(isForeground: true, isPiPActive: false, isScrolling: false, isCovered: false)`だけであることを確かめる。動画の再生状態が引数に無いこと（一時停止で止まらない）は、型で担保される。

### 6.4 `AnimationClockAccumulatorTests.swift`（新規）

各テストは、新しい`AnimationClockAccumulator()`から始める。

- 基準: `advance(to: 10)` → `time == 0`。
- 累積: `advance(to: 10)`、`advance(to: 10.0625)` → `time == 0.0625`。続けて`advance(to: 10.125)` → `time == 0.125`。
- 大きな差は切る: `advance(to: 10)`、`advance(to: 10.5)`（差0.5） → `time == 0.1`（`maxStep`の既定値）。
- `maxStep`を渡す: `advance(to: 10)`、`advance(to: 10.5, maxStep: 0.25)` → `time == 0.25`。
- 停止と再開: `advance(to: 10)`、`advance(to: 10.0625)`、`pause()`、`advance(to: 100)` → `time == 0.0625`のまま。続けて`advance(to: 100.0625)` → `time == 0.125`。
- 逆戻り: `advance(to: 20)`、`advance(to: 19)` → `time == 0`のまま。続けて`advance(to: 19.0625)` → `time == 0.0625`。
- 同じ時刻が2回: `advance(to: 10)`、`advance(to: 10.0625)`、`advance(to: 10.0625)` → `time == 0.0625`のまま。

### 6.5 `AnimationRunStateTests.swift`（新規）

各テストは、新しい`AnimationRunState()`から始める。

- 初期: `isRunning == false`、`gateOpen == false`、`demand == 0`。
- ゲートが閉じたまま登録: `addDemand()` → `.none`で`isRunning == false`。続けて`setGateOpen(true)` → `.start`で`isRunning == true`。
- 開けただけでは動かない: `setGateOpen(true)` → `.none`（`demand == 0`）。`addDemand()` → `.start`。もう一度`addDemand()` → `.none`で`demand == 2`。
- 最後の解除で止まる: `setGateOpen(true)`、`addDemand()`、`addDemand()`、`removeDemand()` → `.none`（`demand == 1`）。もう一度`removeDemand()` → `.stop`で`demand == 0`。
- 0での解除: `removeDemand()` → `.none`で`demand == 0`のまま（負にならない）。ゲートが開いていても同じ（`setGateOpen(true)`、`removeDemand()` → `.none`）。
- ゲートを閉じると止まる: `setGateOpen(true)`、`addDemand()` → `.start`。`setGateOpen(false)` → `.stop`。もう一度`setGateOpen(false)` → `.none`。
- 同じ値のゲート: `setGateOpen(true)`、`addDemand()` → `.start`。`setGateOpen(true)` → `.none`。
- 復帰: `setGateOpen(true)`、`addDemand()`、`setGateOpen(false)` → `.stop`。`setGateOpen(true)` → `.start`（PiPや背面からの復帰）。
- ゲートが閉じている間の増減: `addDemand()`、`addDemand()`、`removeDemand()` → すべて`.none`で`demand == 1`。`setGateOpen(true)` → `.start`。

### 6.6 テストに入れないもの

- 合成の正しさ（部分フレーム・処分方法）: ImageIOの書き込み側では部分フレームを作れないため、実機で2章の代表GIFを目視する（R-01）。
- `EmojiStore.makeEmoji`・`ChatRowView`の描画: アプリ本体はテストターゲットが無い。ロジックは`GifSource`・`AnimationTiming`・`EmojiAnimationGate`・`AnimationClockAccumulator`・`AnimationRunState`に寄せてあり、残りは薄い組み立て。

## 7. 品質管理

- CIの`swift test --package-path Packages/VLCChatCore`が成功する（既存テストを含む）。
- 0警告・0エラー。アプリ本体は`scripts/make-ipa.sh`のビルドログ（`build/xcodebuild.log`）で、`VLCChatCore`は`swift test`のジョブのログ（Swift 6言語モード）で、それぞれ`warning:`を検索して0件を確かめる。`Sendable`と`@MainActor`の隔離の警告に注意する（`GifSource`は`Sendable`にしない、`AnimationTiming`は値型で`Sendable`）。
- 追加したシンボルの参照範囲をgrepで確かめる（`makeImage`の呼び出し元が`makeEmoji`の中だけであること、`redraw`が`makeImage`と`makeEmoji`だけから呼ばれること、`EmojiAnimationClock.addDemand`・`removeDemand`を呼ぶのが`ChatRowView.syncClockDemand`だけであること）。

## 8. 動作確認（実機・人の手）

ipaはGitHub ActionsがReleasesに載せる（`m<M>-<n>`タグ）。PCのiloaderの「Import IPA」で入れる。依頼前に、ipaをダウンロードしたフォルダをExplorerで開いてから案内する（00 項目32）。

確認用データ: 2章の代表GIFを含むTwitchチャットのJSONと、PC版の`emoji_cache.sqlite`（絵文字ライブラリ）。

ログの読み方（重要）: 診断（負荷ログ）は設定シートの中にある（`SettingsView`の「診断」）。設定を開いている間は、D-05によりゲートが閉じて`GIF=停止`になる。そのため、判定は次の順で行う。
1. 手順を行ったら、設定を開かずに40秒以上（負荷ログ2回分）待つ。
2. そのあとで設定を開き、診断のログ共有で、**開く前の時刻の行だけ**を見て判定する（ログはISO8601の時刻付き）。
3. 負荷ログのCPUは直前20秒の平均なので、設定を開いた時刻を含む行は判定に使わない。

| # | 手順 | 期待（Issueの受け入れ条件） |
|---|---|---|
| 1 | 絵文字ライブラリを入れ、GIFを含むチャットを再生する | GIF絵文字が行の中で動く。止まらずに繰り返す（2）。行が出てからGIFが動き出すことで、`onScrollVisibilityChange`の通知が届くこともここで確かめる（D-06） |
| 2 | 2章の代表GIF（部分フレーム＋処分方法2・3）を目視する | 残像・欠け・黒い背景が出ず、PC版の見た目と同じ動きになる（R-01） |
| 3 | 遅延0msのGIF（2章の`4d5ecfb7…`。13フレームすべてが0ms）を見る | 診断ログの`周期=`が1.3s（13×0.1）になり、極端に速く回らない（D-04） |
| 4 | チャット欄を指で触れる／スクロールする | 触れている間と慣性スクロール中は止まり、止まったら続きから動く（3） |
| 5 | GIF絵文字が画面内に1つも無い範囲までスクロールして止め、診断の負荷ログ（20秒ごと）を見る | `GIF=停止(行=0)`になり、GIFが見えていた間の負荷ログと比べてCPUが下がる（時計自体が止まる。D-11） |
| 6 | 動画を一時停止する | GIFは動き続ける（4） |
| 7 | ホームに戻り、PiPを出す。アプリ内のPiPボタンでも試す | PiP・背面のとき、負荷ログが`場面=PiP`／`背面`・`GIF=停止`（3） |
| 8 | アプリに戻る | 前面に戻ったら再び動く（3） |
| 9 | 動いているGIFを含む行を長押ししてテキストを選択し、指を離してコピーのメニューが出ている間も見る | 長押しの間にGIFが動いていても止まっていても、選択とメニューが消えず、コピーできる（5、R-02）。止まったかどうかは記録だけにする |
| 10 | GIFを含む行で、URLをタップする。長い行の折り返しを見る | URLが開く。絵文字が行の途中でも自然に折り返す（5） |
| 11 | PNG・JPEGの絵文字と、1フレームのGIF（実データに1件）を見る | これまでと同じ見た目・同じ高さ。1フレームのGIFは静止画で、`GIF絵文字`のログが出ない（6、D-09） |
| 12 | 低電力モードをオンにして、GIFを見る | 動く（頻度が下がるのは可）（Issue） |
| 13 | 診断の負荷ログ（CPU・熱）を、GIFを画面に多数出した状態で数分見る | 大きな熱・CPUの増加が無いか確かめる。重いと感じたときは、希望30Hzのビルドと比べる（R-03）。動画がコマ落ちせず、スクロールが滑らか。あわせて診断の`phys_footprint`（メモリ）を記録する。結果をPR本文に書く（D-03の60Hzの妥当性、D-07のメモリ） |
| 14 | 混んだチャットを、最下部に追従したまま（新着が流れ続ける状態で）数十秒見る | 新着の自動スクロールのたびにGIFが止まるか、止まらないかを記録する。`.animating`にならず止まらない可能性が高い。止まって見えて気になる場合は、実装を止めてユーザーに報告する（D-05） |
| 15 | 端末の「視差効果を減らす」をオンにして、GIFを見る | 動く（設定を読まない。Issue） |
| 16 | GIF絵文字を含む行の高さと、行の幅を見る | 行がフレームごとにがたつかない（5.6の大きさの固定） |
| 17 | GIFが動いている状態で、別のチャットに切り替える（指でスクロールしている最中にも試す） | 切り替え後、触れなくてもGIFが動く（5.8の`scrollPhase`の復帰）。負荷ログの`行=`が、見えているGIF行の数と合う（見えていなければ0）。登録の解除漏れが無い（5.7） |
| 18 | GIFが動いている状態で、動画を閉じてチャット欄を消し、もう一度開く | 閉じている間は`行=0`・`GIF=停止`。開き直すと、見えている行の数に戻る |
| 19 | GIFが動いている状態で、設定から絵文字ライブラリを入れ替える | 入れ替え後、`行=`が見えているGIF行の数と合う（キャッシュの破棄で登録が漏れない） |
| 20 | 同じGIFが複数の行にあるチャットで、**一度表示してキャッシュ済みのGIF**を使い、1行を出したらスクロールを止めて数秒待ち、次の行を出す、を繰り返す | 別々の時点で見え始めた行は、それぞれ先頭フレームから動き出し、フレームが揃わない。同時に見え始めた行（チャットを開いた直後、スクロールを止めた瞬間）は、揃って動き出してよい（D-12） |
| 21 | GIFが動いている状態で、設定シートを開き、そのまま40秒以上待ってから閉じる。プレイリストシート・ファイル選択でも同じことをする | 開いていた間の負荷ログが`GIF=停止`で、閉じた後は再び動く（D-05）。ログは、閉じた後に設定を開き直して読む |

## 9. リスクと未確認事項

- **R-01 部分フレーム・処分方法の合成**: `CGImageSourceCreateImageAtIndex`が合成済みのフレームを返すかは、一次情報で確かめていない（Apple文書に明記が見つからなかった）。実データでは34件（7%）が部分フレームを持つ。確認手順の2で崩れたら、実装を止めてユーザーに報告する（自分で合成を実装して計画を変えない）。
- **R-02 毎フレームの再描画と長押し選択**: 確認手順の9で、アニメ中の行の選択が解除されるおそれ。解除される場合はユーザーに報告する（Issueの「守れる実装方式が見つからなければ再度相談」）。
- **R-03 CPU・発熱**: 最大60Hzで、時計に登録された行（見えていて、GIFを含む行）の`body`全体が評価し直される。評価のたびに、本文のリンク分割（`ChatLinks.segments`）・`AttributedString`の生成・`Text`の再レイアウトが走る。遅延の中央値は40msなので、評価の半分以上は同じ画像になる。画面内に多数のGIFがある場合の負荷は、確認手順の13で測る。重ければ、まず希望のフレームレートを30に下げる（D-03）。それでも重ければ、本文のセグメント分割を行ごとに1回だけ行う（`@State`で持つ）案と、再描画の間引き（フレームが変わったときだけ更新）を、別Issueで検討する。
- **R-04 メモリ**: Issueの「未対策のリスク」のとおり、上限を設けない。実データの見積もりはD-07。

## 10. 実装の進め方（ステップ5の順序）

0. **【省略: ユーザーが試作を省くと決めた（2026-10-17）。手順1から始め、R-01・R-02は手順4で確かめる】試作（使い捨て。マージしない）**: D-01の方式が成り立つかを、**計画の承認の前（ワークフローのステップ4の終わり〜ステップ5の着手前）に**実機で確かめる。結果（成り立つか）はこの計画に書き込んでから、ステップ5に進む（Issueの「守れる実装方式が見つからなければ、実装計画の段階で報告」に沿うため）。計画書のあるブランチ`feature/issue-26-animated-gif-emoji`から別ブランチ`feature/issue-26-prototype`を切り（計画書が同じ履歴にあるので、編集ガードが働かない。計画書は先にコミットしておく）、`ChatRowView`で1種類のGIF（2章の代表GIFの1つ）を`TimelineView(.animation)`で乱暴に差し替えるだけのipaを作る（タグ`m<M>-<n>`。Mはマイルストーン番号で、READMEの例は`m1-1`。M0〜M3が済んでいるので、試作は`m4-1`とし、本実装は`m4-2`以降を使う。番号の方針が別にあればそれに従う）。フレームは本実装と同じく`CGImageSourceCreateWithData`と`CGImageSourceCreateImageAtIndex`（`kCGImageSourceShouldCache: false`）で取り、本実装と同じ描き直しを通す（R-01の結果が本実装に当てはまるように）。確かめるのはR-02（長押しの選択・コピーのメニューが解除されないか）とR-01（部分フレームのGIFが崩れないか）の2点だけ。成り立たなければ、本実装に進まずユーザーに報告する（Issueの「守れる実装方式が見つからなければ再度相談」）。ユーザーが試作を省くと決めたら、手順1から始め、R-01・R-02は、この10章の手順4（8章の手順2・9）で確かめる。
1. `VLCChatCore`: `AnimationTiming`・`GifSource`・`EmojiAnimationGate`・`AnimationClockAccumulator`・`AnimationRunState`とそのテスト。`swift test`が通ることを確認（CIで）。
2. アプリ本体: `AnimatedEmoji`・`EmojiAnimationClock`・`EmojiStore`・`ChatRowView`・`ChatPanelView`・`AppModel`・`DiagnosticsModel`。
3. `CONTEXT.md`の用語。
4. featureブランチにpushし、CIのビルド（0警告）を確認。`m<M>-<n>`タグで確認用ipaを作り、8章を実機で確かめる。
5. PR本文に、意図・実機確認の結果・R-01〜R-04の結果を書く。この計画書はマージ前の最後のコミットで`git rm`する（`CLAUDE.md`）。計画書の判断理由のうち残すべきもの（D-01・D-04・D-06・D-11・D-12・R-01）は、コードコメントとPR本文に移す。
