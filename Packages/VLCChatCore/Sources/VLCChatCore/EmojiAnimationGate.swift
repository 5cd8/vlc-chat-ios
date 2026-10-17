/// GIF絵文字のアニメを動かしてよいか（Issue #26の条件を1か所にまとめたもの）。
/// `isCovered` は、シート（設定・プレイリスト・ファイル選択）がチャット欄を覆っているか。
/// 動画の再生状態は条件に含めない（一時停止中も動かし続ける）。
public enum EmojiAnimationGate {
  public static func shouldAnimate(isForeground: Bool, isPiPActive: Bool, isScrolling: Bool, isCovered: Bool) -> Bool {
    isForeground && !isPiPActive && !isScrolling && !isCovered
  }
}
