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

  var fileSizeBytes: Int? {
    try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
  }
}
