import SwiftUI
import SwiftVLC
import UniformTypeIdentifiers

struct PlayerScreen: View {
  let app: AppModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var showsFileImporter = false
  @State private var pip: PiPController?

  var body: some View {
    let model = app.playback
    VStack(spacing: 0) {
      video(model)
      if model.title != nil {
        ControlsView(model: model) { showsFileImporter = true }
      }
      // M2でチャット欄が入る場所。
      Spacer(minLength: 0)
      DiagnosticsView(app: app)
    }
    .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.item]) { result in
      switch result {
      case .success(let url):
        model.open(url: url)
      case .failure(let error):
        app.diagnostics.reportError("ファイル選択に失敗: \(error)")
      }
    }
    .alert(
      "動画を開けませんでした",
      isPresented: Binding(
        get: { model.openError != nil },
        set: { if !$0 { model.dismissOpenError() } }
      )
    ) {
      Button("OK") { model.dismissOpenError() }
    } message: {
      Text(model.openError ?? "")
    }
    .onChange(of: pip.map { ObjectIdentifier($0) }) { model.attachPiP(pip) }
    .onChange(of: scenePhase) { model.sceneDidChange(isActive: scenePhase == .active, name: "\(scenePhase)") }
  }

  private func video(_ model: PlayerModel) -> some View {
    ZStack {
      Color.black
      // 動画を選ぶ前から常に置く。再生の後に作り直すと、SwiftVLCが既存の描画面を引き継いで
      // 自動PiPの設定が反映されない。自動PiP（startsAutomaticallyFromInline）は既定のtrueのまま。
      if let player = model.player {
        PiPVideoView(player, controller: $pip)
      }
      if let error = model.setupError {
        Text(error).foregroundStyle(.white).padding()
      } else if model.title == nil {
        Button("ファイルを選択") { showsFileImporter = true }
          .buttonStyle(.borderedProminent)
      } else {
        // .contentShape が無いと、透明な領域はタップに反応しない。
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture { model.togglePlayPause() }
      }
    }
    .aspectRatio(16.0 / 9.0, contentMode: .fit)
  }
}
