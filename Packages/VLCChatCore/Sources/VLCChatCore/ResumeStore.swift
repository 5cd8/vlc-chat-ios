import Foundation

/// 再生位置の記憶。件数に上限は設けない。
public struct ResumeStore: Codable, Equatable, Sendable {
  private struct Record: Codable, Equatable, Sendable {
    var identity: VideoIdentity
    var position: TimeInterval
    var updatedAt: Date
  }

  private var records: [VideoIdentity: Record] = [:]

  public init() {}

  public var count: Int { records.count }

  /// `updatedAt` は将来の整理用に持つ（保存形式をここで確定させる）。
  public mutating func set(_ position: TimeInterval, for identity: VideoIdentity, at date: Date) {
    records[identity] = Record(identity: identity, position: position, updatedAt: date)
  }

  public func position(for identity: VideoIdentity) -> TimeInterval? {
    records[identity]?.position
  }

  public mutating func remove(_ identity: VideoIdentity) {
    records[identity] = nil
  }

  // 保存は fileName・size・position・updatedAt の配列。辞書のキーが構造体だと JSON の形が
  // 「キーと値が交互の配列」になるので、配列で持つ。
  private enum CodingKeys: String, CodingKey { case entries }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let list = try container.decode([Record].self, forKey: .entries)
    records = Dictionary(list.map { ($0.identity, $0) }, uniquingKeysWith: { _, new in new })
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    let list = records.values.sorted {
      ($0.identity.fileName, $0.identity.size) < ($1.identity.fileName, $1.identity.size)
    }
    try container.encode(list, forKey: .entries)
  }

  /// ファイルが無ければ nil。壊れていれば throws。
  public static func load(from url: URL) throws -> ResumeStore? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(ResumeStore.self, from: Data(contentsOf: url))
  }

  public func save(to url: URL) throws {
    try JSONEncoder().encode(self).write(to: url, options: .atomic)
  }
}
