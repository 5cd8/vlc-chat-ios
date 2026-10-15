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
