import Foundation

/// プレイリストの状態遷移。有効かどうか（ファイルが開けるか）は Core の外が決めるので、
/// 探索は `isPlayable` を受け取る。
public struct Playlist: Equatable, Sendable {
  public private(set) var entries: [PlaylistEntry]
  /// 現在の項目は添字ではなく id で持つ。並べ替え・削除で添字がずれても同じ項目を指し続ける。
  public private(set) var currentID: UUID?

  public init(entries: [PlaylistEntry] = [], currentID: UUID? = nil) {
    self.entries = entries
    self.currentID = currentID
  }

  public var currentIndex: Int? {
    guard let currentID else { return nil }
    return entries.firstIndex { $0.id == currentID }
  }

  public var current: PlaylistEntry? { currentIndex.map { entries[$0] } }
  public var hasPrevious: Bool { (currentIndex ?? 0) > 0 }
  public var hasNext: Bool { currentIndex.map { $0 + 1 < entries.count } ?? false }

  /// 現在は先頭（空なら nil）。
  public mutating func replace(with newEntries: [PlaylistEntry]) {
    entries = newEntries
    currentID = newEntries.first?.id
  }

  /// 現在は変えない。
  public mutating func append(_ newEntries: [PlaylistEntry]) {
    entries.append(contentsOf: newEntries)
  }

  public enum Removal: Equatable, Sendable { case notCurrent, current }

  /// 現在を消したら、消した後の同じ添字の項目（元の「次」）が現在になる。末尾だったら nil。
  @discardableResult
  public mutating func remove(at index: Int) -> Removal {
    guard entries.indices.contains(index) else { return .notCurrent }
    let removedID = entries[index].id
    entries.remove(at: index)
    guard removedID == currentID else { return .notCurrent }
    currentID = entries.indices.contains(index) ? entries[index].id : nil
    return .current
  }

  /// SwiftUI の `onMove`（`Array.move(fromOffsets:toOffset:)`）と同じ意味。Core は SwiftUI に依存しないので手で書く。
  public mutating func move(fromOffsets: IndexSet, toOffset: Int) {
    let sources = fromOffsets.filter { entries.indices.contains($0) }.sorted()
    guard !sources.isEmpty else { return }
    let destination = min(max(toOffset, 0), entries.count)
    let moving = sources.map { entries[$0] }
    var rest = entries
    for index in sources.reversed() { rest.remove(at: index) }
    let insertAt = destination - sources.filter { $0 < destination }.count
    rest.insert(contentsOf: moving, at: insertAt)
    entries = rest
  }

  /// entries に無い id は無視する（現在を変えない）。nil は現在なしにする。
  public mutating func setCurrent(id: UUID?) {
    guard let id else {
      currentID = nil
      return
    }
    if entries.contains(where: { $0.id == id }) { currentID = id }
  }

  public mutating func updateEntry(id: UUID, _ change: (inout PlaylistEntry) -> Void) {
    guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
    change(&entries[index])
  }

  public struct Step: Equatable, Sendable {
    /// 次に再生する項目の添字。無ければ nil
    public let target: Int?
    /// 探索で通り過ぎた（無効だった）項目の添字
    public let skipped: [Int]
  }

  public func nextStep(isPlayable: (PlaylistEntry) -> Bool) -> Step {
    guard let index = currentIndex else { return Step(target: nil, skipped: []) }
    return scan(Array((index + 1)..<max(index + 1, entries.count)), isPlayable)
  }

  public func previousStep(isPlayable: (PlaylistEntry) -> Bool) -> Step {
    guard let index = currentIndex else { return Step(target: nil, skipped: []) }
    return scan(Array((0..<index).reversed()), isPlayable)
  }

  /// 現在の項目そのものから探し始める。現在の項目を削除した直後（元の「次」が現在になっている）に使う。
  public func stepFromCurrent(isPlayable: (PlaylistEntry) -> Bool) -> Step {
    guard let index = currentIndex else { return Step(target: nil, skipped: []) }
    return scan(Array(index..<entries.count), isPlayable)
  }

  private func scan(_ indices: [Int], _ isPlayable: (PlaylistEntry) -> Bool) -> Step {
    var skipped: [Int] = []
    for i in indices {
      if isPlayable(entries[i]) { return Step(target: i, skipped: skipped) }
      skipped.append(i)
    }
    return Step(target: nil, skipped: skipped)
  }
}
