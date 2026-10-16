import SwiftUI
import UniformTypeIdentifiers
import VLCChatCore

struct PlaylistView: View {
  let app: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  // EditButton が切り替える値は NavigationStack の内側の環境に入るので、外側のこのビューでは読めない。
  // 自前の状態を NavigationStack に渡し、行のタップでも読む。
  @State private var editMode = EditMode.inactive

  private enum ImportPurpose {
    case append
    case assignChat(UUID)
  }

  @State private var showsImporter = false
  @State private var purpose = ImportPurpose.append

  var body: some View {
    let model = app.playlist
    NavigationStack {
      Group {
        if model.playlist.entries.isEmpty {
          ContentUnavailableView("ファイルを選択して動画を追加してください", systemImage: "list.bullet")
        } else {
          List {
            ForEach(model.playlist.entries) { entry in
              row(entry, isCurrent: entry.id == model.playlist.currentID)
            }
            .onDelete { app.removeEntries(at: $0) }
            .onMove { app.moveEntries(fromOffsets: $0, toOffset: $1) }
          }
        }
      }
      .navigationTitle("プレイリスト")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { EditButton() }
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            purpose = .append
            showsImporter = true
          } label: {
            Image(systemName: "plus")
          }
          .accessibilityLabel("追加")
          Button("閉じる") { dismiss() }
        }
      }
    }
    // ツールバーの EditButton も同じ値を切り替えるよう、NavigationStack 全体に渡す。
    .environment(\.editMode, $editMode)
    .fileImporter(
      isPresented: $showsImporter, allowedContentTypes: importTypes, allowsMultipleSelection: allowsMultiple
    ) { result in
      switch result {
      case .success(let urls):
        switch purpose {
        case .append: app.appendPicked(urls: urls)
        case .assignChat(let id): app.assignChatPicked(entryID: id, urls: urls)
        }
      case .failure(let error):
        app.diagnostics.reportError("ファイル選択に失敗: \(error)")
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
    .onAppear { model.refreshValidity() }
    .onChange(of: scenePhase) { if scenePhase == .active { model.refreshValidity() } }
    .presentationDetents([.medium, .large])
  }

  private var importTypes: [UTType] {
    if case .assignChat = purpose { return [.json] }
    return [.item]
  }

  private var allowsMultiple: Bool {
    if case .assignChat = purpose { return false }
    return true
  }

  private func row(_ entry: PlaylistEntry, isCurrent: Bool) -> some View {
    // 確かめていない項目（validity に無い）は有効として表示する。
    let validity = app.playlist.validity[entry.id]
    let videoOK = validity?.video ?? true
    return HStack(spacing: 8) {
      if isCurrent && app.playback.title != nil {
        Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
      }
      if !videoOK {
        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
      }
      Text(entry.title)
        .lineLimit(2)
        .foregroundStyle(videoOK ? .primary : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        purpose = .assignChat(entry.id)
        showsImporter = true
      } label: {
        Image(systemName: "text.bubble")
          .foregroundStyle(chatColor(entry, validity))
      }
      // 行全体のタップ（再生）と競合しないよう、別のタップにする。
      .buttonStyle(.borderless)
      .accessibilityLabel("チャットを割り当て")
      .accessibilityValue(entry.chatFileName ?? "なし")
    }
    .contentShape(Rectangle())
    .onTapGesture {
      // 並べ替えの最中に行をタップしても再生を始めない。
      guard !editMode.isEditing else { return }
      guard let index = app.playlist.playlist.entries.firstIndex(where: { $0.id == entry.id }) else { return }
      app.playItem(at: index, byUser: true)
    }
    .listRowBackground(isCurrent ? Color.accentColor.opacity(0.15) : nil)
  }

  private func chatColor(_ entry: PlaylistEntry, _ validity: PlaylistModel.EntryValidity?) -> Color {
    guard entry.chatBookmark != nil else { return .secondary.opacity(0.4) }
    return validity?.chat == false ? .orange : .accentColor
  }
}
