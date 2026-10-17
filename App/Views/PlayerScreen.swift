import SwiftUI
import SwiftVLC
import UniformTypeIdentifiers

struct PlayerScreen: View {
  let app: AppModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var showsFileImporter = false
  @State private var pip: PiPController?
  @State private var showsPlaylist = false
  @State private var showsSettings = false

  var body: some View {
    let model = app.playback
    VStack(spacing: 0) {
      video(model)
      if model.title != nil {
        ControlsView(
          model: model, playlist: app.playlist,
          onPickFile: { showsFileImporter = true },
          onShowPlaylist: { showsPlaylist = true },
          onShowSettings: { showsSettings = true },
          onPrevious: { app.previousItem() },
          onNext: { app.nextItem() })
        ChatPanelView(app: app, isCovered: showsPlaylist || showsSettings || showsFileImporter)
      } else {
        Spacer(minLength: 0)
      }
    }
    .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
      switch result {
      case .success(let urls):
        app.handlePicked(urls: urls)
      case .failure(let error):
        app.diagnostics.reportError("ファイル選択に失敗: \(error)")
      }
    }
    .alert(
      "確認してください",
      isPresented: Binding(
        // シートの表示中は、シート側の .alert だけが出す。
        get: { app.alertMessage != nil && !showsPlaylist && !showsSettings },
        // 消す処理はここ1か所だけにする。ボタンの処理でも消すと、1回の操作で通知が2件消える。
        set: { if !$0 { app.dismissAlert() } }
      )
    ) {
      Button("OK") {}
    } message: {
      Text(app.alertMessage ?? "")
    }
    .sheet(isPresented: $showsPlaylist) { PlaylistView(app: app) }
    .sheet(isPresented: $showsSettings) { SettingsView(app: app) }
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
        HStack {
          Button("ファイルを選択") { showsFileImporter = true }
            .buttonStyle(.borderedProminent)
          if !app.playlist.playlist.entries.isEmpty {
            Button("プレイリスト") { showsPlaylist = true }
              .buttonStyle(.bordered)
          }
        }
        // 歯車は動画を開いていないときも出す（再生中は操作パネルのボタンが担う）。
        VStack {
          HStack {
            Spacer()
            Button { showsSettings = true } label: { Image(systemName: "gearshape").padding(12) }
              .accessibilityLabel("設定")
          }
          Spacer()
        }
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
