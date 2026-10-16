# Issue #24 アプリアイコン 実装計画

- 対象Issue: https://github.com/5cd8/vlc-chat-ios/issues/24 （アシスタントがヒアリングで確定した要件を起票したIssue。要約・言い換えはせず、Issue本文を正とする）
- スコープ: 1PR。ブランチ `feature/issue-24-app-icon`（`origin/main` から作成済み）
- 非ゴール: ダーク／ティント用アイコン、Launch Screen画像、アプリ内の画像差し替え（Issueの非ゴール通り）
- 計画書はマージ前の最後のコミットで `git rm` する（CLAUDE.md）。判断理由のうち残すものはコードコメント／PR本文へ移す。

## 現状（確認済み）

- `App/` に `Assets.xcassets` なし。`project.yml` の target `VLCWithChat` の `sources` は `App`（`Info.plist` を除外）と `licenses`（resources）。`settings.base` に `ASSETCATALOG_COMPILER_APPICON_NAME` なし。
- `scripts/make-ipa.sh` が `xcodebuild archive`（署名なし）→ ipa 化 → plist を検査（`UIBackgroundModes`、`CFBundleVersion`）。
- CI（`.github/workflows/build-ipa.yml`）は `xcodegen generate` → `make-ipa.sh`。キャッシュキーは `hashFiles('project.yml')`（project.yml を変えるとSwiftPMキャッシュが取り直しになる。初回のみ遅い。動作は壊れない）。
- PR #23（未マージ）は `project.yml` の1行（`MARKETING_VERSION` 付近）・README・workflow を触る。本計画の `project.yml` 変更は別の行なので、どちらが先でも自動マージできる見込み。後からマージされる側で `git merge origin/main` して確認する。
- この機器に Pillow は未インストール（`python`=3.14、pip 可）。

## 変更内容

### 1. 生成スクリプト `scripts/make-app-icon.py`（新規）

- Pillow で 4096x4096 に描き、`Image.LANCZOS` で 1024x1024 に縮小（アンチエイリアス）。RGB で保存（アルファなし。App Store/iOSは透過アイコンを不可とするため）。
- 出力: `App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`。引数なしで実行、出力先はスクリプト位置からの相対（`Path(__file__).parent.parent`）。
- 座標は1024基準の定数にまとめ、描画時に係数4を掛ける。**図形の数値は下記を初期値とし、実際に描いて見た目で微調整してよい**（微調整後の値をスクリプトに反映すればよく、計画の更新は不要）。
  - 背景: 縦グラデーション 上 `#16346F` → 下 `#0A1A3F`（濃紺）。
  - 再生三角（白 `#FFFFFF`）: 頂点 (330,260)・(330,760)・(790,510) 付近を中心に、角を丸める（塗り多角形＋同色の太線 `joint="curve"` で丸める。丸め半径 ≈ 40）。視覚的重心を考え、三角はやや左上寄り。
  - 吹き出し（アクセント `#22D3EE`）: 右下。角丸矩形 (560,640)–(920,860)、半径 ≈ 80、左下に尻尾（三角形）。三角と重なる部分は濃紺の縁取り（幅 ≈ 28）で分離する。吹き出し内に濃紺の点を3つ（チャットらしさ）。
  - 主要要素は中央 ~80%（iOSの角丸マスクで切れない）に収める。
- 先頭コメントに「アイコンを変えるときはこのスクリプトを編集して再実行し、PNGをコミットする」と書く（How/Why not: CIでは生成せずPNGをコミットする理由＝CIにPython依存を足さないため）。

### 2. アセットカタログ（新規）

- `App/Assets.xcassets/Contents.json`: `{"info":{"author":"xcode","version":1}}`
- `App/Assets.xcassets/AppIcon.appiconset/Contents.json`:
  `{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}`
  （iOS 18/Xcode 16以降の単一サイズ形式。deploymentTarget は18.0）
- `AppIcon.png`（スクリプトの出力）。

### 3. `project.yml`

- target `VLCWithChat` の `settings.base` に `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` を追加。
- `sources: - path: App` は `Assets.xcassets` を自動でリソースとして取り込む（XcodeGen の仕様）。追加の指定は不要だが、`xcodegen generate` 後の pbxproj に `Assets.xcassets` が Resources に入ることを CI の結果（下記検査）で確かめる。
- 一次情報: XcodeGen ProjectSpec（sources の自動分類）、Apple「Configuring your app icon using an asset catalog」。実装時にインストール版の挙動で確認し、取り込まれない場合は `sources` に `type: resources` 付きで明示する。

### 4. `scripts/make-ipa.sh` に検査を追加

既存の plist 検査ループ内に、ipaにアイコンが入っていることの機械的確認を足す（実機確認を待たずCIで落とすため）:

- `build/verify/Payload/$APP_NAME.app/Assets.car` が存在すること。
- `plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName raw` が `AppIcon` であること。
  （actool がアイコン登録情報をInfo.plistにマージする。キーパスが違う場合は、実際の archive のInfo.plistを `plutil -p` で確認して合わせる。まず検査を入れずに1回CIを回してplistを `build/xcodebuild.log` ではなくワークフローのログに出す手もあるが、PR作成前にローカルで確認はできない（Mac無し）ため、**キーパスが不確かならCIログで確認してから検査を確定する**）

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

- CI（`build-ipa.yml`）が警告0・既存テスト成功・ipa検査OKで通ること。`Assets.xcassets` 追加で actool の警告（例：未使用／サイズ不正）が出ないこと。
- 画像は実際に描いてから見る（`Read` で PNG を開く）。さらに、60x60 程度に縮小したプレビューも作って小さくても判別できるか確認する（00 項目23）。

## 動作確認の手順

1. 実装後、画像（1024px と縮小プレビュー）をユーザーに見せて意匠を確認してもらう（実機を待たずに調整できる）。
2. CI成功後、ipa（Actions の成果物 `ipa`、または Release）を iloader の「Import IPA」で実機に入れ、**ホーム画面にアイコンが出る**ことを確認（ユーザー）。依頼時は、成果物を置いたフォルダを `reveal_path`／`explorer.exe` で開いてから、絶対パスとファイル名（`vlc-with-chat-unsigned.ipa`）を書く（00 項目32）。
3. すでに入れてあるアプリを上書きしてもアイコンが更新されない場合は、アプリを削除して入れ直す（iOSのアイコンキャッシュ）。

## 実装順序

1. `pip install pillow`（この機器）。
2. スクリプト作成→実行→画像を見て調整→縮小プレビュー確認。
3. アセットカタログ JSON、`project.yml`。
4. `make-ipa.sh` 検査、README。
5. `feature/**` のpushでCIが走る（`build-ipa.yml` の `on.push.branches`）。pushしてCIを確認する。PR作成はユーザーの指示後。
6. セルフレビュー3回（00 項目18：追加シンボル参照のgrep、JSONの構文確認、CIの再実行で警告確認）。
