# Issue #24 アプリアイコン 実装計画

- 対象Issue: https://github.com/5cd8/vlc-chat-ios/issues/24 （アシスタントがヒアリングで確定した要件を起票したIssue。要約・言い換えはせず、Issue本文を正とする）
- スコープ: 1PR。ブランチ `feature/issue-24-app-icon`（`origin/main` から作成済み）
- 非ゴール: ダーク／ティント用アイコン、Launch Screen画像、アプリ内の画像差し替え（Issueの非ゴール通り）
- 計画書はマージ前の最後のコミットで `git rm` する（CLAUDE.md）。判断理由のうち残すものはコードコメント／PR本文へ移す。

## 現状（確認済み）

- `App/` に `Assets.xcassets` なし。`project.yml` の target `VLCWithChat` の `sources` は `App`（`Info.plist` を除外）と `licenses`（resources）。`settings.base` に `ASSETCATALOG_COMPILER_APPICON_NAME` の指定なし（ただしXcodeGenのiOSアプリ用プリセットが既に `AppIcon` を設定している。アイコンが出ない原因はアセットが無いことだけ）。
- `scripts/make-ipa.sh` が `xcodebuild archive`（署名なし）→ ipa 化 → plist を検査（`UIBackgroundModes`、`CFBundleVersion`）。
- CI（`.github/workflows/build-ipa.yml`）は `xcodegen generate` → `make-ipa.sh`。キャッシュキーは `hashFiles('project.yml')`（project.yml を変えるとSwiftPMキャッシュが取り直しになる。初回のみ遅い。動作は壊れない）。
- PR #23（未マージ）は `project.yml` の1行（`MARKETING_VERSION` 付近）・README・workflow を触る。本計画の `project.yml` 変更は別の行なので、どちらが先でも自動マージできる見込み。後からマージされる側で `git merge origin/main` して確認する。
- この機器に Pillow は未インストール（`python`=3.14、pip 可）。

## 変更内容

### 1. 生成スクリプト `scripts/make-app-icon.py`（新規）

- Pillow で 4096x4096 に描き、`Image.Resampling.LANCZOS` で 1024x1024 に縮小（アンチエイリアス）。RGB で保存（アルファなし。App Store/iOSは透過アイコンを不可とするため）。
- 出力: `App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`。引数なしで実行、出力先はスクリプト位置からの相対（`Path(__file__).parent.parent`）。
- 座標は1024基準の定数にまとめ、描画時に係数4を掛ける。**図形の数値は下記を初期値とし、実際に描いて見た目で微調整してよい**（微調整後の値をスクリプトに反映すればよく、計画の更新は不要）。
  - 背景: 縦グラデーション（縦1×4096の画像を作って `resize` で横に伸ばす。`putpixel` の全画素ループは遅い）上 `#16346F` → 下 `#0A1A3F`（濃紺）。
  - 再生三角（白 `#FFFFFF`）: 頂点 (330,260)・(330,760)・(790,510) 付近。角は次の手順で丸める（r≈40）: 各辺を内側へ r だけ平行移動した内側の三角形を求める（頂点は角の二等分線上を r/sin(θ/2) 動く）→ その各頂点に半径 r の円を描く → 内側の頂点どうしを幅 2r の線で結ぶ → 内側の三角形を塗る。これで辺は元の三角形と一致し、角だけが丸まる（`ImageDraw.line(joint="curve")` は始点の角が丸まらず外へ広がるため使わない）。重心は (483,510) で、三角は中央よりやや左。
  - 吹き出し（アクセント `#22D3EE`）: 右下。角丸矩形 (560,640)–(920,860)、半径 ≈ 80、左下に尻尾（三角形）。初期値では三角と重ならないので縁取りは不要。重ねる調整をする場合は、一定色の縁取りでなく「吹き出しを拡大したマスクで三角を削る」（背景がグラデーションなので色の輪が出るため）。吹き出し内に濃紺の点を3つ（チャットらしさ）。
  - 主要要素はキャンバスの内側 ~90% に収める（iOSの角丸マスクで切れない。吹き出しの縁取り含め右端は ≈950 まで可）。
- 先頭コメントに「アイコンを変えるときはこのスクリプトを編集して再実行し、PNGをコミットする」と書く（How/Why not: CIでは生成せずPNGをコミットする理由＝CIにPython依存を足さないため）。

### 2. アセットカタログ（新規）

- `App/Assets.xcassets/Contents.json`: `{"info":{"author":"xcode","version":1}}`
- `App/Assets.xcassets/AppIcon.appiconset/Contents.json`:
  `{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}`
  （単一サイズ形式。Xcode 14以降で使える）
- `AppIcon.png`（スクリプトの出力）。

### 3. `project.yml`

- target `VLCWithChat` の `settings.base` に `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` を、`CURRENT_PROJECT_VERSION` の後に追加（`MARKETING_VERSION` の行に接しない位置にして、PR #23 との衝突を避ける）。プリセットと重複するが、アイコン名を明示して意図を残すために書く。
- `sources: - path: App` は `Assets.xcassets` を自動でリソースとして取り込む（XcodeGen の仕様）。追加の指定は不要だが、`xcodegen generate` 後の pbxproj に `Assets.xcassets` が Resources に入ることを CI の結果（下記検査）で確かめる。
- 一次情報: XcodeGen ProjectSpec（sources の自動分類）、Apple「Configuring your app icon using an asset catalog」。実装時にインストール版の挙動で確認し、取り込まれない場合は `sources` に `type: resources` 付きで明示する。

### 4. `scripts/make-ipa.sh` に検査を追加

既存の plist 検査ループ内に、ipaにアイコンが入っていることの機械的確認を足す（実機確認を待たずCIで落とすため）:

- `build/verify/Payload/$APP_NAME.app/Assets.car` が存在すること。（`AppIcon60x60@2x.png` がバンドル直下にできるかは、Xcode 26＋単一サイズで確認できていないので必須にしない。失敗時の `ls` で見えるようにするだけ。）
- `plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName raw -o - "$plist"` が `AppIcon` であること。**`-o -` を必ず付ける**（無いとplistが抽出結果で上書きされる。既存の検査と同じ書き方）。
- 検査は `set -e` で途中終了しない形で書く: `if ! icon_name="$(plutil -extract ... raw -o - "$plist" 2>&1)" || [ "$icon_name" != AppIcon ]; then ...; exit 1; fi`。いずれかが失敗したら、`plutil -p "$plist" >&2` と `ls` でplist全体とバンドルの中身をログに出してから `exit 1` する。キーパスが違っていてもCIを1回回せば正しい値が分かる（Macが無くローカルで確かめられないため）。

### 5. README

- アイコン変更手順を1〜2行（`pip install pillow` → `python scripts/make-app-icon.py` → PNGをコミット）。既存の「ビルド」節の近くに追記。

## 設計判断

| 判断 | 採用 | 理由 | 採らなかった案 |
|---|---|---|---|
| 生成物の管理 | PNGとスクリプトをコミット | CIにPython/Pillow依存を足さず、PNGは再現可能 | CIで生成（依存増）、SVGのみ（変換ツール必要） |
| 描画ライブラリ | Pillow（4倍描画→縮小） | 純Pythonで導入が軽い | cairosvg（Windowsでcairo導入が面倒）、手書きSVG |
| 画像枚数 | 1024単一 | iOS 18以上のみ対象。濃紺背景でダークでも見える | dark/tinted の3枚（非ゴール） |
| アルファ | 無し（RGB） | 透過はアイコンで不可 | RGBA |

## テスト方針

- ビジネスロジックなし。単体テストは追加しない（ツール出力の画像）。
- 画像の自動検査: スクリプト実行後、`python -c` で `Image.open(...).size == (1024,1024)` と `mode == "RGB"` を確認（手順としてPR本文に記載）。
- 検査の本体は 4 の `make-ipa.sh` 検査（CIで機械的に）。

## 品質管理

- CI（`build-ipa.yml`）が警告0・既存テスト成功・ipa検査OKで通ること。`Assets.xcassets` 追加で actool の警告（例：未使用／サイズ不正）が出ないこと。確認は、成果物 `ipa` に含まれる `build/xcodebuild.log` を `grep -n "warning:"` し、actool／Assets.xcassets 由来の警告が無いことを見る（CI自体には警告で失敗させる仕組みは無い）。
- 画像は実際に描いてから見る（`Read` で PNG を開く）。さらに、60x60 程度に縮小したプレビューも作って小さくても判別できるか確認する（00 項目23）。

## 動作確認の手順

1. 実装後、画像（1024px と縮小プレビュー）をユーザーに見せて意匠を確認してもらう（実機を待たずに調整できる）。
2. CI成功後、ipa（featureブランチのpushではReleaseは作られず、Actionsの成果物のみ。Claudeが `gh run download <run-id> -n ipa -D <フォルダ>` で取得し、そのフォルダを開いてから依頼する）を iloader の「Import IPA」で実機に入れ、**ホーム画面にアイコンが出る**ことを確認（ユーザー）。依頼時は、成果物を置いたフォルダを `reveal_path`／`explorer.exe` で開いてから、絶対パスとファイル名（`vlc-with-chat-unsigned.ipa`）を書く（00 項目32）。
3. 上書きしてもアイコンが更新されない場合は、まず端末の再起動を試す。アプリの削除→入れ直しは、Documents（動画・チャット・設定）が消えるので、ユーザーに確認してから行う。

## 実装順序

1. `pip install pillow`（この機器）。
2. スクリプト作成→実行→画像を見て調整→縮小プレビュー確認。
3. アセットカタログ JSON、`project.yml`。
4. `make-ipa.sh` 検査、README。
5. `feature/**` のpushでCIが走る（`build-ipa.yml` の `on.push.branches`）。pushしてCIを確認する。PR作成はユーザーの指示後。
6. セルフレビュー3回（00 項目18：追加シンボル参照のgrep、JSONの構文確認（`python -m json.tool <file>`）、CIの再実行で警告確認）。
