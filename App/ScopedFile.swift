import Foundation

/// セキュリティスコープ付きURLの保持。`start` と `stop` を対にするため、解放時に必ず止める。
final class ScopedFile {
  let url: URL
  /// `startAccessingSecurityScopedResource()` の戻り値
  let didStartAccess: Bool

  init(url: URL) {
    self.url = url
    didStartAccess = url.startAccessingSecurityScopedResource()
  }

  deinit {
    if didStartAccess { url.stopAccessingSecurityScopedResource() }
  }

  /// ファイルがアプリのコンテナの中にあるか。ピッカーがコピーしたかの判定に使う。
  var isInsideAppContainer: Bool {
    let container = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
    return url.resolvingSymlinksInPath().path.hasPrefix(container)
  }

  var fileSizeBytes: Int? {
    try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
  }
}

/// ブックマークのオプション違い。iOSで正しい値が確定していないため、両方を別々に保存して比べる。
enum BookmarkVariant: String, CaseIterable {
  case minimal
  case noOptions

  var options: URL.BookmarkCreationOptions {
    switch self {
    case .minimal: .minimalBookmark
    case .noOptions: []
    }
  }

  var label: String {
    switch self {
    case .minimal: "minimalBookmark"
    case .noOptions: "オプションなし"
    }
  }

  var defaultsKey: String { "bookmark.\(rawValue)" }

  func save(for file: ScopedFile) throws {
    let data = try file.url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    UserDefaults.standard.set(data, forKey: defaultsKey)
  }

  var savedData: Data? { UserDefaults.standard.data(forKey: defaultsKey) }

  /// 保存したブックマークを解決する。何も保存されていなければ `nil`。
  func resolve() -> Result<(url: URL, isStale: Bool), Error>? {
    guard let data = savedData else { return nil }
    return Result {
      var isStale = false
      let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
      return (url, isStale)
    }
  }
}
