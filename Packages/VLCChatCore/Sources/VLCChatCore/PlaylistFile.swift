import Foundation

public struct PlaylistSnapshot: Codable, Equatable, Sendable {
  public static let currentVersion = 1
  public var version: Int
  public var entries: [PlaylistEntry]
  public var currentID: UUID?
}

public enum PlaylistFile {
  public enum LoadError: Error, Equatable { case unreadable }

  /// ファイルが無ければ nil。読めない（壊れている・版が新しい）ときは `unreadable` を投げる。
  public static func load(from url: URL) throws -> Playlist? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let snapshot: PlaylistSnapshot
    do {
      snapshot = try JSONDecoder().decode(PlaylistSnapshot.self, from: Data(contentsOf: url))
    } catch {
      throw LoadError.unreadable
    }
    guard snapshot.version <= PlaylistSnapshot.currentVersion else { throw LoadError.unreadable }
    var playlist = Playlist(entries: snapshot.entries)
    playlist.setCurrent(id: snapshot.currentID)  // entries に無い id は無視され、nil のまま
    return playlist
  }

  public static func save(_ playlist: Playlist, to url: URL) throws {
    let snapshot = PlaylistSnapshot(
      version: PlaylistSnapshot.currentVersion, entries: playlist.entries,
      currentID: playlist.currentID)
    try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
  }
}
