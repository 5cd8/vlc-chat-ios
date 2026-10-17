import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import VLCChatCore

/// ImageIO の書き込み側（`CGImageDestination`）で作った 2×2px の単色GIFを読む。
/// 部分フレーム・処分方法は書き込み側では作れないので、フレームの合成は実機で確かめる（計画書 R-01）。
struct GifSourceTests {
  private static let red = (UInt8(255), UInt8(0), UInt8(0))
  private static let green = (UInt8(0), UInt8(255), UInt8(0))
  private static let blue = (UInt8(0), UInt8(0), UInt8(255))

  private func solidImage(_ color: (UInt8, UInt8, UInt8)) -> CGImage {
    let context = CGContext(
      data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(
      red: CGFloat(color.0) / 255, green: CGFloat(color.1) / 255, blue: CGFloat(color.2) / 255, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    return context.makeImage()!
  }

  /// `DelayTime` と `UnclampedDelayTime` の両方に同じ遅延（秒）を書いたGIF。
  private func makeGIF(colors: [(UInt8, UInt8, UInt8)], delays: [Double]) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, colors.count, nil)!
    let fileProperties: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
    CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
    for (index, color) in colors.enumerated() {
      let frameProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
          kCGImagePropertyGIFDelayTime: delays[index],
          kCGImagePropertyGIFUnclampedDelayTime: delays[index],
        ]
      ]
      CGImageDestinationAddImage(destination, solidImage(color), frameProperties as CFDictionary)
    }
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
  }

  /// 画像を 1×1px に縮めて描いたときの (R, G, B)。
  private func averageColor(_ image: CGImage) -> (Int, Int, Int) {
    var pixel = [UInt8](repeating: 0, count: 4)
    pixel.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
  }

  @Test("フレーム数・遅延・フレームの色を読める") func readsFramesAndDelays() throws {
    let data = makeGIF(colors: [Self.red, Self.green, Self.blue], delays: [0.25, 0.5, 0.25])
    let source = try #require(GifSource(data: data))
    #expect(source.frameCount == 3)
    #expect(abs(source.rawDelay(at: 0) - 0.25) < 0.001)
    #expect(abs(source.rawDelay(at: 1) - 0.5) < 0.001)
    #expect(abs(source.rawDelay(at: 2) - 0.25) < 0.001)
    let green = averageColor(try #require(source.frame(at: 1)))
    // パレット化と色空間の変換で多少ずれても通る許容幅。
    #expect(green.1 >= 200 && green.0 <= 55 && green.2 <= 55)
  }

  @Test("遅延0と0.02を読み分けられる") func readsShortDelays() throws {
    let data = makeGIF(colors: [Self.red, Self.green], delays: [0.0, 0.02])
    let source = try #require(GifSource(data: data))
    #expect(abs(source.rawDelay(at: 0) - 0.0) < 0.001)
    #expect(abs(source.rawDelay(at: 1) - 0.02) < 0.001)
  }

  @Test("1フレームのGIFは frameCount が1") func singleFrameGIF() throws {
    let data = makeGIF(colors: [Self.red], delays: [0.1])
    let source = try #require(GifSource(data: data))
    #expect(source.frameCount == 1)
  }

  @Test("範囲外の添字は、遅延0・フレームなし") func outOfRangeIndex() throws {
    let data = makeGIF(colors: [Self.red, Self.green], delays: [0.1, 0.1])
    let source = try #require(GifSource(data: data))
    #expect(source.rawDelay(at: -1) == 0)
    #expect(source.rawDelay(at: 2) == 0)
    #expect(source.frame(at: -1) == nil)
    #expect(source.frame(at: 2) == nil)
  }

  @Test("GIFでないデータは nil") func rejectsNonGIF() {
    let png = NSMutableData()
    let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, solidImage(Self.red), nil)
    #expect(CGImageDestinationFinalize(destination))
    #expect(GifSource(data: png as Data) == nil)
    #expect(GifSource(data: Data()) == nil)
    #expect(GifSource(data: Data("GIF89a".utf8)) == nil)  // ヘッダだけで中身が無い
    #expect(GifSource(data: Data("画像ではないバイト列".utf8)) == nil)
  }
}
