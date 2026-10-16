import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  let app: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var showsImporter = false

  var body: some View {
    NavigationStack {
      Form {
        Section("再生") {
          Toggle(
            "自動で次の動画を再生",
            isOn: Binding(get: { app.settings.autoAdvance }, set: { app.settings.setAutoAdvance($0) }))
        }
        Section("絵文字ライブラリ") {
          LabeledContent("状態", value: app.emoji.hasLibrary ? "あり（\(app.emoji.libraryCount ?? 0)件）" : "なし")
          Button("入れ替え") { showsImporter = true }
        }
        Section("このアプリについて") {
          NavigationLink("ライセンス") { LicensesView() }
          LabeledContent("バージョン", value: app.diagnostics.versionText)
        }
      }
      .navigationTitle("設定")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } }
      }
    }
    // シートの表示中は下のビューからピッカー・アラートを出せないので、このビューにも1つずつ付ける。
    .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
      switch result {
      case .success(let urls): app.replaceEmojiPicked(urls: urls)
      case .failure(let error): app.diagnostics.reportError("ファイル選択に失敗: \(error)")
      }
    }
    .alert(
      "確認してください",
      isPresented: Binding(
        get: { app.alertMessage != nil },
        set: { if !$0 { app.dismissAlert() } }
      )
    ) {
      Button("OK") {}
    } message: {
      Text(app.alertMessage ?? "")
    }
    .presentationDetents([.medium, .large])
  }
}
