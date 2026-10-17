import SwiftUI
import VLCChatCore

/// 投稿者の種別ごとの配色（PC版のダーク配色。設定では変えない）。
enum ChatStyle {
  private static func color(_ hex: UInt32) -> Color {
    Color(
      red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }

  static func text(for role: ChatRole) -> Color {
    switch role {
    case .owner: color(0x4CD97B)
    case .moderator: color(0x4DA3FF)
    case .normal: color(0xF1F1F6)
    }
  }

  static func background(for role: ChatRole) -> Color {
    switch role {
    case .owner: color(0x16301F)
    case .moderator: color(0x16283A)
    case .normal: color(0x1C1C25)
    }
  }

  /// 左端のバー。通常の投稿は透明（PC版も透明）。
  static func accent(for role: ChatRole) -> Color {
    role == .normal ? .clear : text(for: role)
  }
}

/// 1件のチャットのカード。オーナーとモデレーターは、色・太字・左端のバーで装飾する。
struct ChatRowView: View {
  let message: ChatMessage
  let emoji: EmojiStore
  let clock: EmojiAnimationClock
  /// 行が画面内にスクロールされて見えているか（`onScrollVisibilityChange`）。
  @State private var isVisible = false
  /// 行がビューとして出ている間だけ真（`onAppear`〜`onDisappear`）。`LazyVStack` が画面外の行を保持していても、
  /// 出ていない行は時計に登録しない。
  @State private var isAppeared = false
  /// 時計に登録済みか。真の間だけ `addDemand` 済みで、解除と必ず対になる。
  @State private var isRegistered = false
  /// 登録した時点の時計の値。GIFは、ここからの経過で先頭フレームから動く（行ごとに独立して動かす）。
  @State private var startTime: TimeInterval = 0

  var body: some View {
    let role = message.role
    let weight: Font.Weight = role == .normal ? .regular : .bold
    HStack(spacing: 0) {
      Rectangle()
        .fill(ChatStyle.accent(for: role))
        .frame(width: 3)
      VStack(alignment: .leading, spacing: 2) {
        Text(message.author)
          .font(.caption)
          .fontWeight(weight)
          .opacity(0.9)
        bodyText
          .font(.callout)
          .fontWeight(weight)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .foregroundStyle(ChatStyle.text(for: role))
    .background(ChatStyle.background(for: role))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    // 長押しで選択・コピーできる。リンクのタップが効かなくなる場合は、ここを外す（リンクを優先する）。
    .textSelection(.enabled)
    .onScrollVisibilityChange(threshold: 0.1) { isVisible = $0 }
    // 登録は `onChange` の1本。`isAppeared` が変われば `needsClock` も変わるので、`onAppear` で登録を呼ばない。
    .onAppear { isAppeared = true }
    .onDisappear {
      isAppeared = false
      isVisible = false  // 古い可視の値を残さない（再表示で、画面外のまま登録されないように）
      syncClockDemand(false)  // 行が消えると `onChange` が届かないことがあるので、ここで直接解除する
    }
    .onChange(of: needsClock, initial: true) { _, needs in syncClockDemand(needs) }
  }

  /// 画面に出ていて、見えていて、アニメーション絵文字を含む行は、時計に登録する。
  /// 登録がある間だけ時計が回る（`EmojiAnimationClock`）。
  private var needsClock: Bool {
    isAppeared && isVisible
      && message.runs.contains { run in
        if case .emoji(let url, _) = run { return emoji.isAnimated(url: url) }
        return false
      }
  }

  private func syncClockDemand(_ needs: Bool) {
    guard needs != isRegistered else { return }
    isRegistered = needs
    if needs {
      startTime = clock.time
      clock.addDemand()
    } else {
      clock.removeDemand()
    }
  }

  /// 本文を、テキスト・リンク・絵文字の画像を並べた1つの `Text` にする（折り返しはテキストと一緒になる）。
  private var bodyText: Text {
    var result = Text("")
    for run in message.runs {
      switch run {
      case .text(let string):
        for segment in ChatLinks.segments(in: string) {
          switch segment {
          case .text(let plain):
            result = result + Text(plain)
          case .link(let label, let url):
            var attributed = AttributedString(label)
            attributed.link = url
            attributed.underlineStyle = .single
            result = result + Text(attributed)
          }
        }
      case .emoji(let url, let alt):
        switch emoji.lookup(url: url) {
        case .image(let image):
          result = result + Text(Image(uiImage: image))
        case .animated(let animated):
          // アニメも、静止画と同じく `Text(Image)` で本文に連結したまま、フレームだけ差し替える。絵文字を別のViewに
          // 並べると、行の途中での折り返し・長押しのコピー・URLのタップが崩れる（Issue #26）。
          // 時計を読むのは、登録済みの行だけ。それ以外の行は、時計が進んでも再描画されない。
          let image = isRegistered ? animated.frame(at: max(0, clock.time - startTime)) : animated.frames[0]
          result = result + Text(Image(uiImage: image))
        case .pending:
          // 読み込み中は幅だけを確保して、行の高さが後から変わりにくくする。
          result = result + Text("\u{3000}")
        case .missing:
          result = result + Text(alt).foregroundStyle(.secondary)
        }
      }
    }
    return result
  }
}
