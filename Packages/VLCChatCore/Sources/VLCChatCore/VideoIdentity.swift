import Foundation

/// 再生位置の記憶で使う「同じ動画」の判定。名前（NFC）とサイズが同じなら同じ動画とみなす。
/// ファイルを入れ直しても続きから再生できるようにするため、内容のハッシュ（数GBを読む）は使わない。
public struct VideoIdentity: Hashable, Codable, Sendable {
  /// 拡張子込み。NFC
  public let fileName: String
  public let size: Int64

  public init(fileName: String, size: Int64) {
    self.fileName = fileName.precomposedStringWithCanonicalMapping
    self.size = size
  }

  private enum CodingKeys: String, CodingKey { case fileName, size }

  // 自動生成の init(from:) は上の init を通らないので、NFC にそろえるために手で書く。
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      fileName: try container.decode(String.self, forKey: .fileName),
      size: try container.decode(Int64.self, forKey: .size))
  }
}
