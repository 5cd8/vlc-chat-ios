import Foundation
import SQLite3

enum EmojiLibraryError: Error, CustomStringConvertible {
  case notADatabase
  case missingTable
  case missingColumns

  var description: String {
    switch self {
    case .notADatabase: "SQLiteとして開けません"
    case .missingTable: "emoji_cache テーブルがありません"
    case .missingColumns: "emoji_cache に url / data 列がありません"
    }
  }
}

/// 絵文字ライブラリ（`emoji_cache(url TEXT PRIMARY KEY, data BLOB NOT NULL)`）の取り込みと読み取り。
///
/// 取り込みは、選んだファイルをアプリの領域へコピーして検証してから、本番の場所と入れ替える。
/// 検証に失敗したら、今あるライブラリは変えない。読み取りは読み取り専用の接続で行う。
actor EmojiLibrary {
  struct ImportResult {
    let count: Int
    let sizeMB: Double
  }

  /// PC版（`EmojiCacheService.cs`）と同じ上限。これを超えるBLOBは無いものとして扱う。
  private static let maxImageBytes = 5 * 1024 * 1024
  /// C のマクロ `SQLITE_TRANSIENT` は Swift から見えないので、同じ値を作る
  /// （バインドした文字列を SQLite が自分でコピーする）。
  private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  private let libraryURL: URL
  private let temporaryURL: URL
  private var connection: OpaquePointer?

  init() {
    let directory =
      (try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
      ?? FileManager.default.temporaryDirectory
    libraryURL = directory.appendingPathComponent("emoji_cache.sqlite")
    temporaryURL = directory.appendingPathComponent("emoji_cache.import.tmp")
  }

  deinit {
    if let connection { sqlite3_close(connection) }
  }

  // MARK: - 取り込み

  /// 取り込んだ行数を返す。失敗したら投げる（今あるライブラリは変えない）。
  func importLibrary(from source: URL) throws -> ImportResult {
    let file = ScopedFile(url: source)
    let sizeMB = file.fileSizeBytes.map { Double($0) / 1_048_576 } ?? 0
    let manager = FileManager.default
    // 前回の失敗で残った一時ファイルは先に消す。
    try? manager.removeItem(at: temporaryURL)
    try manager.copyItem(at: file.url, to: temporaryURL)
    let count: Int
    do {
      count = try Self.validate(temporaryURL)
    } catch {
      try? manager.removeItem(at: temporaryURL)
      throw error
    }
    // 読み取りの接続を持ったまま入れ替えると、古いファイルを開いたまま読み続ける。
    closeConnection()
    if manager.fileExists(atPath: libraryURL.path) {
      _ = try manager.replaceItemAt(libraryURL, withItemAt: temporaryURL)
    } else {
      // 初回は置き換え先が無く、`replaceItemAt` が失敗し得る。
      try manager.moveItem(at: temporaryURL, to: libraryURL)
    }
    withExtendedLifetime(file) {}
    return ImportResult(count: count, sizeMB: sizeMB)
  }

  /// 開けて、`emoji_cache` に `url`・`data` 列があることを確かめ、行数を返す。
  private static func validate(_ url: URL) throws -> Int {
    guard let database = openReadOnly(url) else { throw EmojiLibraryError.notADatabase }
    defer { sqlite3_close(database) }
    var columns = Set<String>()
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "PRAGMA table_info(emoji_cache)", -1, &statement, nil) == SQLITE_OK else {
      throw EmojiLibraryError.notADatabase
    }
    while sqlite3_step(statement) == SQLITE_ROW {
      if let name = sqlite3_column_text(statement, 1) { columns.insert(String(cString: name)) }
    }
    sqlite3_finalize(statement)
    guard !columns.isEmpty else { throw EmojiLibraryError.missingTable }
    guard columns.contains("url"), columns.contains("data") else { throw EmojiLibraryError.missingColumns }
    guard let count = scalarInt(database, "SELECT count(*) FROM emoji_cache") else { throw EmojiLibraryError.notADatabase }
    return count
  }

  // MARK: - 読み取り

  /// ライブラリの行数。ライブラリが無い（または開けない）ときは `nil`。
  func count() -> Int? {
    guard let database = openConnection() else { return nil }
    return Self.scalarInt(database, "SELECT count(*) FROM emoji_cache")
  }

  /// `url` の画像データ。無い・大きすぎる（5MB超）・読めないときは `nil`。
  /// `url` は一字一句そのままキーに使う（`trim` や正規化をすると、取り込み時のキーと合わなくなる）。
  func imageData(for url: String) -> Data? {
    guard let database = openConnection() else { return nil }
    var length: Int?
    var statement: OpaquePointer?
    if sqlite3_prepare_v2(database, "SELECT length(data) FROM emoji_cache WHERE url = ?1", -1, &statement, nil) == SQLITE_OK {
      sqlite3_bind_text(statement, 1, url, -1, Self.sqliteTransient)
      if sqlite3_step(statement) == SQLITE_ROW { length = Int(sqlite3_column_int64(statement, 0)) }
    }
    sqlite3_finalize(statement)
    guard let length, length > 0, length <= Self.maxImageBytes else { return nil }

    var data: Data?
    statement = nil
    if sqlite3_prepare_v2(database, "SELECT data FROM emoji_cache WHERE url = ?1", -1, &statement, nil) == SQLITE_OK {
      sqlite3_bind_text(statement, 1, url, -1, Self.sqliteTransient)
      if sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) {
        data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
      }
    }
    sqlite3_finalize(statement)
    return data
  }

  private func openConnection() -> OpaquePointer? {
    if let connection { return connection }
    guard FileManager.default.fileExists(atPath: libraryURL.path) else { return nil }
    connection = Self.openReadOnly(libraryURL)
    return connection
  }

  private func closeConnection() {
    if let connection { sqlite3_close(connection) }
    connection = nil
  }

  private static func openReadOnly(_ url: URL) -> OpaquePointer? {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(database)
      return nil
    }
    return database
  }

  private static func scalarInt(_ database: OpaquePointer, _ sql: String) -> Int? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return Int(sqlite3_column_int64(statement, 0))
  }
}
