import SwiftUI
import VLCChatCore

/// 動画の下のチャット欄。読み込みの状態に応じて表示を切り替え、読み込めたら再生位置までの最新200件を出す。
struct ChatPanelView: View {
  let app: AppModel
  /// 設定・プレイリスト・ファイル選択のシートが、チャット欄を覆っているか（`PlayerScreen` が渡す）。
  let isCovered: Bool
  @Environment(\.scenePhase) private var scenePhase
  /// 一覧の最下部が見えているか。利用者が上へ遡ったときだけ偽になる。
  @State private var isAtBottom = true
  /// 画面に出している末尾。最下部が見えている間は `chat.endIndex` に追従し、遡っている間は止める
  /// （新着を足さず先頭の行も消さないので、見ている行がずれない）。
  @State private var shownEnd = 0
  @State private var scrollPhase: ScrollPhase = .idle
  /// 長押しの後、次に触れるまでGIFのアニメを止めておく判定。`textSelection` のメニューは、指を離した後に出る。
  /// その間にアニメの更新が再開すると閉じてしまうので、長押しが認識されたら、次に触れるまで動かさない。
  @State private var longPressHold = LongPressHold()
  /// 指が触れている間だけ真。ジェスチャが終わる・取り消されると自動で偽に戻る。
  /// `ScrollPhase` は、動かさずに触れ続けても `tracking` にならないので、触れているかの判定には使えない。
  @GestureState private var isTouching = false
  /// 長押しとみなす秒数。システムの長押し認識（約0.5秒）より少し短くして、メニューが出る前に止める。
  private static let longPressSeconds = 0.45

  var body: some View {
    let chat = app.chat
    ZStack {
      // 下のセーフエリアにも黒を敷く（一覧はセーフエリアの内側に置く）。
      Color.black.ignoresSafeArea(.container, edges: .bottom)
      content(chat)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // 配色はPC版のダーク配色で固定。端末のライトモードでも読めるように、この領域だけダークにする。
    .environment(\.colorScheme, .dark)
    .onChange(of: chat.endIndex) { old, new in
      if new < shownEnd || new - old >= Self.jumpThreshold {
        // 後ろへのシーク、または前へ大きくシークした。古い履歴を残さず最下部へ戻す。
        // 制限：混んだチャットを高倍速で見ていると、0.25秒の1回の更新でも200件以上進むことがあり、
        // その場合は遡り中でも最下部へ戻る（シークと区別できないため。許容した）。
        isAtBottom = true
        shownEnd = new
      } else if isAtBottom {
        shownEnd = new
      }
    }
    .onChange(of: isAtBottom) { _, atBottom in
      if atBottom { shownEnd = chat.endIndex }
    }
    // 別のチャットに替わったら、古い末尾を引き継がない。
    .onChange(of: chat.store.map { ObjectIdentifier($0) }) {
      isAtBottom = true
      shownEnd = chat.endIndex
      // 一覧のScrollViewは作り直されるので、操作中のまま残った値でGIFが止まり続けないようにする
      // （`onScrollPhaseChange` は変化があったときしか呼ばれない）。
      scrollPhase = .idle
      longPressHold = LongPressHold()
    }
    // GIF絵文字のアニメは、前面で、PiPでなく、スクロール中でなく、シートに覆われていないときだけ動かす。
    // 動画の一時停止では止めない。実際に回すかは、時計に登録された行があるかとも合わせて時計が決める。
    .onChange(of: shouldAnimate, initial: true) { app.emojiClock.setGateOpen(shouldAnimate) }
    .onDisappear { app.emojiClock.setGateOpen(false) }
    .onChange(of: isTouching) { _, touching in
      if touching { longPressHold.touchBegan() }
    }
    // 背面では画面が見えないので回さない。停止中（再生が終わった後など）は位置が0に戻るので更新を飛ばし、
    // 最後の表示を残す。ループ自体は止めない（`id` は scenePhase だけなので、止めると再開しない）。
    .task(id: scenePhase) {
      guard scenePhase != .background else { return }
      while !Task.isCancelled {
        if !app.playback.isClockStopped {
          let position = app.playback.displayPosition(at: ProcessInfo.processInfo.systemUptime)
          if position.isFinite {
            chat.updatePosition(seconds: Int(max(0, position).rounded(.down)))
          }
        }
        try? await Task.sleep(for: .milliseconds(250))
      }
    }
  }

  private var shouldAnimate: Bool {
    EmojiAnimationGate.shouldAnimate(
      isForeground: scenePhase == .active, isPiPActive: app.diagnostics.pipActive,
      isScrolling: scrollPhase != .idle || isTouching || longPressHold.isHolding, isCovered: isCovered)
  }

  /// 1回の更新でこれ以上進んだら、前への大きなシークとみなす（凍結中の自然な新着の蓄積では解かない）。
  private static let jumpThreshold = ChatStore.windowSize

  @ViewBuilder
  private func content(_ chat: ChatModel) -> some View {
    switch chat.state {
    case .none:
      notice("チャットを読み込むには、「ファイルを選択」で .json を選んでください")
    case .loading:
      VStack(spacing: 8) {
        ProgressView()
        Text("読み込み中").font(.callout).foregroundStyle(.secondary)
      }
    case .failed:
      notice("チャットを読み込めませんでした")
    case .loaded:
      if let store = chat.store {
        if store.count == 0 {
          notice("メッセージがありません")
        } else {
          list(store: store)
        }
      }
    }
  }

  private func notice(_ text: String) -> some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .padding()
  }

  private func list(store: ChatStore) -> some View {
    let range = store.window(endIndex: shownEnd)
    return ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 6) {
          ForEach(range, id: \.self) { position in
            ChatRowView(message: store.message(at: position), emoji: app.emoji, clock: app.emojiClock)
              .id(position)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
      }
      // 初回の表示位置を最下部にする。内容の大きさが変わるとき（絵文字の画像の読み込みなど）も最下部寄りに
      // 保たれるが、遡って読んでいる間は `shownEnd` を止めているので、この指定で動くのは行の高さが変わった分だけ。
      .defaultScrollAnchor(.bottom)
      .onScrollGeometryChange(for: Bool.self) { geometry in
        // 内容が表示領域より短いときも真になる（差の絶対値にすると、短い内容で偽になって止まる）。
        geometry.visibleRect.maxY >= geometry.contentSize.height - 2
      } action: { _, atBottom in
        if atBottom {
          isAtBottom = true
        } else if scrollPhase == .interacting || scrollPhase == .decelerating {
          // 偽にするのは利用者の操作中だけ。自動のスクロールや新着で内容が伸びたときは偽にしない。
          isAtBottom = false
        }
      }
      .onScrollPhaseChange { _, newPhase in scrollPhase = newPhase }
      // 触れている間と、長押しの認識を、スクロール状態とは別に取る（どちらもスクロールを邪魔しない同時認識）。
      .simultaneousGesture(DragGesture(minimumDistance: 0).updating($isTouching) { _, state, _ in state = true })
      .simultaneousGesture(
        LongPressGesture(minimumDuration: Self.longPressSeconds).onEnded { _ in longPressHold.longPressRecognized() })
      .onChange(of: shownEnd) {
        if isAtBottom, shownEnd > 0 {
          // 切り替えにアニメーションは付けない。
          var transaction = Transaction()
          transaction.disablesAnimations = true
          withTransaction(transaction) { proxy.scrollTo(shownEnd - 1, anchor: .bottom) }
        }
      }
      .transaction { $0.animation = nil }
    }
  }
}
