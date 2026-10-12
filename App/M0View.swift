import SwiftUI
import SwiftVLC
import UniformTypeIdentifiers
import VLCChatCore

/// M0の確認用の1画面。本実装では作り直す前提で、装飾は最小限にしている。
struct M0View: View {
  let model: M0Model
  @Environment(\.scenePhase) private var scenePhase
  @State private var showsFileImporter = false
  @State private var showsDocumentPicker = false
  @State private var pip: PiPController?
  @State private var isScrubbing = false
  @State private var scrubFraction = 0.0
  @State private var policySelection = AudioPolicyChoice.saved

  var body: some View {
    VStack(spacing: 0) {
      video
      controls
      Divider()
      infoPanel
    }
    .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.item]) { result in
      switch result {
      case .success(let url): model.didPick(url: url, source: "fileImporter")
      case .failure(let error): model.didFailToPick(error, source: "fileImporter")
      }
    }
    .sheet(isPresented: $showsDocumentPicker) {
      DocumentPicker { url in model.didPick(url: url, source: "UIDocumentPicker") }
    }
    .onChange(of: pip.map { ObjectIdentifier($0) }) { model.attachPiP(pip) }
    .onChange(of: policySelection) { model.setAudioPolicy(policySelection) }
    .onChange(of: scenePhase) { model.sceneDidChange(isActive: scenePhase == .active, name: "\(scenePhase)") }
  }

  @ViewBuilder private var video: some View {
    ZStack {
      Color.black
      if let player = model.player {
        PiPVideoView(player, controller: $pip, startsAutomaticallyFromInline: model.autoPiP)
          .id(model.videoViewID)
      } else {
        Text(model.setupError ?? "プレイヤーなし").foregroundStyle(.white).padding()
      }
    }
    .aspectRatio(16.0 / 9.0, contentMode: .fit)
  }

  private var controls: some View {
    VStack(spacing: 8) {
      HStack {
        Button("ファイルを選択") { showsFileImporter = true }
        Button("ピッカーで選択") { showsDocumentPicker = true }
        Button("ブックマーク(min)") { model.playBookmark(.minimal) }
        Button("ブックマーク(なし)") { model.playBookmark(.noOptions) }
      }
      .buttonStyle(.bordered)
      .font(.caption)
      .disabled(!model.isPlayerReady)

      HStack {
        Button("再生/停止") { model.togglePlayPause() }
        Button("−10秒") { model.jump(seconds: -10) }
        Button("+10秒") { model.jump(seconds: 10) }
        Button("0.5x") { model.setRate(.half) }
        Button("1x") { model.setRate(.normal) }
        Button("2x") { model.setRate(.double) }
      }
      .buttonStyle(.bordered)
      .font(.caption)

      Slider(
        value: Binding(
          get: { isScrubbing ? scrubFraction : model.fraction },
          set: { scrubFraction = $0 }
        ),
        in: 0...1
      ) { editing in
        isScrubbing = editing
        // つまみを掴んだ瞬間に、現在位置から動き出すようにする。
        if editing { scrubFraction = model.fraction }
        // 離したとき1回だけシークする。
        if !editing { model.seek(fraction: scrubFraction) }
      }

      HStack {
        Button("PiP開始") { model.startPiP() }.buttonStyle(.bordered)
        Toggle("自動PiP（次の再生から）", isOn: Bindable(model).autoPiP).font(.caption)
      }
      HStack {
        Picker("音声セッション", selection: $policySelection) {
          ForEach(AudioPolicyChoice.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        ShareLink(item: DiagnosticsLog.shared.fileURL) { Text("ログを共有").font(.caption) }
      }
      Text("音声セッション方針は次の起動から有効（今は\(model.launchPolicy.label)）").font(.caption2).foregroundStyle(.secondary)
    }
    .padding(8)
  }

  private var infoPanel: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 4) {
        if let player = model.player {
          line("状態", "\(player.state)")
          line("時間", "\(player.currentTime.formatted) / \(player.duration?.formatted ?? "不明")")
          line("rate", String(format: "%.2f", player.rate))
          line("isSeekable", "\(player.isSeekable)")
          line("activeVideoOutputs", "\(player.activeVideoOutputs)")
          line("トラック", model.trackSummary)
        }
        line("timeChanged間隔", timeStatsText)
        line("phys_footprint", model.footprintMB.map { String(format: "%.1f MB", $0) } ?? "—")
        line("PiP", "isPossible=\(model.pip?.isPossible ?? false) isActive=\(model.pip?.isActive ?? false)")
        line("PiP開始結果", model.pipStartResult)
        line("PiPイベント", model.pipSummary)
        line("選択", model.pickSummary)
        ForEach(model.bookmarkReports) { report in
          line("ブックマーク(\(report.variant.label))", report.summary)
        }
        line("エラー", model.playError ?? model.setupError ?? "なし")
        line("バージョン", model.appVersionText)
      }
      .font(.caption.monospaced())
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private var timeStatsText: String {
    guard let stats = model.timeStats else { return "—" }
    func ms(_ stat: IntervalStats.Stat) -> String {
      String(format: "%.0f/%.0f/%.0f ms", stat.min * 1000, stat.avg * 1000, stat.max * 1000)
    }
    return "受信(min/avg/max) \(ms(stats.wall)) メディア \(ms(stats.media)) n=\(stats.samples)"
  }

  private func line(_ title: String, _ value: String) -> some View {
    Text("\(title): \(value)").textSelection(.enabled)
  }
}

/// `asCopy: false` で開くピッカー。コピーされずに元の場所のURLが返るかを `fileImporter` と比べる。
private struct DocumentPicker: UIViewControllerRepresentable {
  let onPick: (URL) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void

    init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
      if let url = urls.first { onPick(url) }
    }
  }
}
