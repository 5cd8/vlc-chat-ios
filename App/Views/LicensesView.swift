import SwiftUI

/// SwiftVLC（MIT）と libVLC（LGPL-2.1以上）の表示。全文はアプリに同梱したテキスト。
struct LicensesView: View {
  var body: some View {
    List {
      Section("SwiftVLC") {
        Text("MIT License / Copyright (c) 2025 Omar Albeik\n使用版 \(AppModel.swiftVLCVersion)")
        Link("https://github.com/harflabs/SwiftVLC", destination: URL(string: "https://github.com/harflabs/SwiftVLC")!)
        NavigationLink("ライセンス全文") { FullTextView(title: "SwiftVLC (MIT)", resource: "SwiftVLC-MIT") }
      }
      Section("libVLC") {
        Text(
          "このアプリは libVLC（LGPL-2.1以上、VideoLAN）を静的リンクした SwiftVLC を含みます。"
            + "SwiftVLC が同梱するxcframeworkは、VideoLAN の vlc に SwiftVLC 独自のパッチを当ててビルドしたものです。"
            + "固定したコミットとパッチは、SwiftVLC の v\(AppModel.swiftVLCVersion) タグの scripts/build-libvlc.sh と scripts/patches/ にあります。")
        Link("vlc のソース", destination: URL(string: "https://code.videolan.org/videolan/vlc")!)
        Text("再ビルドの手順: このアプリのリポジトリの .github/workflows/build-ipa.yml と scripts/make-ipa.sh")
        Link("https://github.com/5cd8/vlc-chat-ios", destination: URL(string: "https://github.com/5cd8/vlc-chat-ios")!)
        NavigationLink("LGPL-2.1 全文") { FullTextView(title: "LGPL-2.1", resource: "LGPL-2.1") }
      }
    }
    .navigationTitle("ライセンス")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct FullTextView: View {
  let title: String
  let resource: String

  var body: some View {
    ScrollView {
      Text(text)
        .font(.caption.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }

  private var text: String {
    guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return "全文を読み込めませんでした" }
    return text
  }
}
