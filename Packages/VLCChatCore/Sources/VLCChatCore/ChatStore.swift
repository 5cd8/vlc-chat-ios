/// 読み込んだチャット全体の不変な格納。
///
/// 約22万件でもメモリを小さく保つため、メッセージごとに `String` や配列を持たず、列ごとの配列と
/// 本文のUTF-8の領域にまとめる。メッセージの復元は、表示する範囲（最大200件）の分だけ行う。
public final class ChatStore: Sendable {
  /// 画面に出す最新のメッセージ数（PC版と同じ）。
  public static let windowSize = 200

  // メッセージ列（追加順）
  private let times: [Int32]
  private let authorIDs: [UInt32]
  private let roles: [UInt8]
  private let runStarts: [UInt32]
  private let runCounts: [UInt16]
  // run列
  private let runKinds: [UInt8]
  private let runA: [UInt32]
  private let runB: [UInt32]
  private let textArena: [UInt8]
  private let strings: [String]
  /// 時刻の昇順（同じ時刻は追加順＝安定）に並べた追加順の添字。追加順がすでに昇順なら `nil`。
  private let order: [UInt32]?

  fileprivate init(
    times: [Int32], authorIDs: [UInt32], roles: [UInt8], runStarts: [UInt32], runCounts: [UInt16],
    runKinds: [UInt8], runA: [UInt32], runB: [UInt32], textArena: [UInt8], strings: [String],
    order: [UInt32]?
  ) {
    self.times = times
    self.authorIDs = authorIDs
    self.roles = roles
    self.runStarts = runStarts
    self.runCounts = runCounts
    self.runKinds = runKinds
    self.runA = runA
    self.runB = runB
    self.textArena = textArena
    self.strings = strings
    self.order = order
  }

  public var count: Int { times.count }

  /// テスト用。文字列表（投稿者名・URL・代替テキスト）の件数。
  var stringTableCount: Int { strings.count }
  /// テスト用。並べ替えの表を持たない（追加順がすでに昇順）か。
  var usesIdentityOrder: Bool { order == nil }

  /// 時刻の昇順での位置から、追加順の添字へ。
  private func storedIndex(at position: Int) -> Int {
    if let order { return Int(order[position]) }
    return position
  }

  public func timeSeconds(at position: Int) -> Int {
    Int(times[storedIndex(at: position)])
  }

  /// `position` は時刻の昇順での位置（0 ..< count）。
  public func message(at position: Int) -> ChatMessage {
    let index = storedIndex(at: position)
    let start = Int(runStarts[index])
    let runCount = Int(runCounts[index])
    var runs: [ChatRun] = []
    runs.reserveCapacity(runCount)
    for runIndex in start..<(start + runCount) {
      if runKinds[runIndex] == 0 {
        let from = Int(runA[runIndex])
        let to = from + Int(runB[runIndex])
        runs.append(.text(String(decoding: textArena[from..<to], as: UTF8.self)))
      } else {
        runs.append(.emoji(url: strings[Int(runA[runIndex])], alt: strings[Int(runB[runIndex])]))
      }
    }
    return ChatMessage(
      timeSeconds: Int(times[index]),
      author: strings[Int(authorIDs[index])],
      role: ChatRole(rawValue: roles[index]) ?? .normal,
      runs: runs
    )
  }

  /// 「時刻 ≦ seconds」を満たすメッセージの件数（0 … count）。PC版と同じく、整数の秒どうしで比べる。
  public func endIndex(atSeconds seconds: Int) -> Int {
    var low = 0
    var high = count
    // 「時刻 ≦ seconds」が成り立つ最後の位置の次を二分探索で探す。
    while low < high {
      let middle = low + (high - low) / 2
      if timeSeconds(at: middle) <= seconds {
        low = middle + 1
      } else {
        high = middle
      }
    }
    return low
  }

  /// 画面に出す範囲。`endIndex` は先に 0 … count に丸める
  /// （別の `ChatStore` に対する古い値が来ても範囲外にならない）。
  public func window(endIndex: Int) -> Range<Int> {
    let end = min(max(endIndex, 0), count)
    return max(0, end - Self.windowSize)..<end
  }
}

/// `ChatStore` を作る。追加順のまま積み、`finish()` で並べ替えと容量の詰め直しを行う。
public struct ChatStoreBuilder {
  private var times: [Int32] = []
  private var authorIDs: [UInt32] = []
  private var roles: [UInt8] = []
  private var runStarts: [UInt32] = []
  private var runCounts: [UInt16] = []
  private var runKinds: [UInt8] = []
  private var runA: [UInt32] = []
  private var runB: [UInt32] = []
  private var textArena: [UInt8] = []
  private var strings: [String] = []
  /// 同じ文字列を1つにまとめる（読み込み中だけ使う）。
  private var stringIDs: [String: UInt32] = [:]
  /// 本文の領域やrun列が32bitの添字に収まらなくなったら、以降の追加を止める。
  private var isFull = false

  public init() {}

  public var count: Int { times.count }

  private mutating func intern(_ string: String) -> UInt32 {
    if let id = stringIDs[string] { return id }
    let id = UInt32(strings.count)
    strings.append(string)
    stringIDs[string] = id
    return id
  }

  public mutating func append(timeSeconds: Int, author: String, role: ChatRole, runs: [ChatRun]) {
    // 範囲外の時刻は、壊れた入力として捨てる（クラッシュさせない）。
    guard !isFull, let time = Int32(exactly: timeSeconds) else { return }
    // 4GBを超える入力は想定していない。超えたら、ここまでに積んだ分で完了させる。
    if textArena.count > Int(UInt32.max) - (1 << 20) || runKinds.count > Int(UInt32.max) - (1 << 20) {
      isFull = true
      return
    }
    times.append(time)
    authorIDs.append(intern(author))
    roles.append(role.rawValue)
    runStarts.append(UInt32(runKinds.count))
    // 1メッセージのrunが65535を超えたら、超えた分は捨てる（実データでは起こらない）。
    let kept = runs.prefix(Int(UInt16.max))
    runCounts.append(UInt16(kept.count))
    for run in kept {
      switch run {
      case .text(let text):
        let bytes = Array(text.utf8)
        runKinds.append(0)
        runA.append(UInt32(textArena.count))
        runB.append(UInt32(bytes.count))
        textArena.append(contentsOf: bytes)
      case .emoji(let url, let alt):
        runKinds.append(1)
        runA.append(intern(url))
        runB.append(intern(alt))
      }
    }
  }

  /// 並べ替え（時刻の昇順、同じ時刻は追加順＝安定）と、各配列の容量の詰め直しを行う。
  public func finish() -> ChatStore {
    var isAscending = true
    var previous = Int32.min
    for time in times {
      if time < previous {
        isAscending = false
        break
      }
      previous = time
    }
    var order: [UInt32]?
    if !isAscending {
      // `sort` は安定とは限らないので、比較に追加順を含める。
      var indices = [UInt32](0..<UInt32(times.count))
      let snapshot = times
      indices.sort { left, right in
        let leftTime = snapshot[Int(left)]
        let rightTime = snapshot[Int(right)]
        return leftTime != rightTime ? leftTime < rightTime : left < right
      }
      order = Self.compact(indices)
    }
    return ChatStore(
      times: Self.compact(times), authorIDs: Self.compact(authorIDs), roles: Self.compact(roles),
      runStarts: Self.compact(runStarts), runCounts: Self.compact(runCounts),
      runKinds: Self.compact(runKinds), runA: Self.compact(runA), runB: Self.compact(runB),
      textArena: Self.compact(textArena), strings: Self.compact(strings), order: order
    )
  }

  /// `Array(x)` はバッファを共有して容量が残るので、必要な大きさの新しい領域に写す。
  private static func compact<T>(_ array: [T]) -> [T] {
    var copy: [T] = []
    copy.reserveCapacity(array.count)
    copy.append(contentsOf: array)
    return copy
  }
}
