import Foundation
import Testing
@testable import VLCChatCore

struct ChatByteSourceTests {
  @Test("FileByteSourceはDataByteSourceと同じチャンク列を返す") func fileSourceMatchesDataSource() throws {
    let data = Data((0..<23).map { UInt8($0) })
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-byte-source-\(UUID().uuidString).bin")
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    var file = try FileByteSource(url: url, chunkSize: 5)
    var memory = DataByteSource(data, chunkSize: 5)
    var fileChunks: [[UInt8]] = []
    var memoryChunks: [[UInt8]] = []
    while let chunk = try file.nextChunk() { fileChunks.append(chunk) }
    while let chunk = try memory.nextChunk() { memoryChunks.append(chunk) }
    #expect(fileChunks == memoryChunks)
    #expect(fileChunks.map(\.count) == [5, 5, 5, 5, 3])
  }

  @Test("開けないファイルは投げる") func throwsForMissingFile() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
    #expect(throws: (any Error).self) { try FileByteSource(url: url) }
  }
}
