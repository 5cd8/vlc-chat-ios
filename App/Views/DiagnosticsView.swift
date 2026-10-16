import SwiftUI

/// 画面の最下部の1行と、タップで開く詳細（メモリ・状態・エラー・間隔・ログの共有）。
struct DiagnosticsView: View {
  let app: AppModel
  @State private var showsSheet = false

  var body: some View {
    Button { showsSheet = true } label: {
      Text(summary)
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
    .accessibilityLabel("診断情報")
    .accessibilityValue(summary)
    .sheet(isPresented: $showsSheet) { detail }
  }

  private var summary: String {
    let state = app.playback.player.map { "\($0.state)" } ?? "-"
    let memory = app.diagnostics.footprintMB.map { String(format: "%.0fMB", $0) } ?? "—"
    let pip = app.diagnostics.pipActive ? " ・ PiP" : ""
    let error = app.diagnostics.lastError == nil ? "" : " ・ エラー"
    return "状態 \(state) ・ \(memory)\(pip)\(error)"
  }

  private var detail: some View {
    let diagnostics = app.diagnostics
    let model = app.playback
    return NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 6) {
          line("状態", model.player.map { "\($0.state)" } ?? "-")
          TimelineView(.periodic(from: .now, by: 1)) { _ in
            line(
              "時間",
              "\(ControlsView.format(model.displayPosition(at: ProcessInfo.processInfo.systemUptime))) / "
                + (model.duration.map(ControlsView.format) ?? "不明")
            )
          }
          line("phys_footprint", diagnostics.footprintMB.map { String(format: "%.1f MB", $0) } ?? "—")
          line("timeChanged間隔", diagnostics.timeStats?.summaryText ?? "—")
          line("PiP", diagnostics.pipActive ? "表示中" : "なし")
          line("チャット", app.chat.loadSummary ?? "なし")
          line("絵文字ライブラリ", app.emoji.hasLibrary ? "あり（\(app.emoji.libraryCount ?? 0)件）" : "なし")
          line(
            "プレイリスト",
            "\(app.playlist.playlist.entries.count)件 現在 "
              + (app.playlist.playlist.currentIndex.map { "\($0 + 1)番目" } ?? "なし"))
          line("再生位置の記憶", "\(app.resume.count)件")
          line("直近のエラー", diagnostics.lastError ?? "なし")
          line("バージョン", diagnostics.versionText)
          // 暫定の診断（Issue #12 第2段階）。原因と対策が決まったら消す。
          Text("PiP実験（暫定）").font(.headline).padding(.top, 8)
          ForEach(PiPExperiment.allCases) { experiment in
            Button(experiment.title) { app.runPiPExperiment(experiment) }
              .buttonStyle(.bordered)
              .disabled(app.isExperimentRunning || (experiment != .measure && model.title == nil))
          }
        }
        .font(.caption.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
      }
      .navigationTitle("診断")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(items: AppLog.shared.existingFileURLs) { Text("ログを共有") }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func line(_ title: String, _ value: String) -> some View {
    Text("\(title): \(value)").textSelection(.enabled)
  }
}
