/// Twitchのチャット（`{"comments":[{...},{...}], ...}`）から、`comments` 配列の各要素のオブジェクトを
/// 1つずつ切り出す。ファイル全体を `JSONSerialization` に渡すと数倍のメモリを使うので、バイトの
/// 状態機械で要素の範囲だけを見つけ、要素ごとにパースする。
///
/// 文字列の中の `{` `}` `[` `]` `"` は数えない。配列が閉じたら、以降のバイトは読まない
/// （大きな別プロパティが後ろにあっても読まない）。
public struct JSONObjectSplitter {
  public enum Status: Equatable, Sendable {
    case needsMore
    /// 配列が閉じた、または構文が壊れて続けられない。以降のチャンクは読まなくてよい。
    case finished
  }

  public enum Outcome: Equatable, Sendable {
    /// 配列に入る前に、入力の終端か構文の破損に達した（空・BOMだけ・途中で切れた入力を含む）。
    case undetermined
    /// `comments` の配列に入った。以後は変わらない（配列の中で壊れても、そこまでの要素は有効）。
    case arrayFound
    case rootNotObject
    case commentsMissing
    case commentsNotArray
  }

  private enum Phase {
    /// 先頭の空白とBOMを読み飛ばして、ルートの `{` を待つ。
    case start
    /// ルートのオブジェクトの中（深さ1）。`comments` のキーを探す。
    case root
    /// 深さ1の文字列が終わった。続く `:` でキーかどうかが決まる。
    case afterString
    /// `comments` のキーと `:` の後。`[` を待つ。
    case expectArray
    /// 配列の要素の間（深さ2）。
    case inArray
    /// 要素のオブジェクトの中。
    case inElement
  }

  public private(set) var status: Status = .needsMore
  public private(set) var outcome: Outcome = .undetermined

  private var phase: Phase = .start
  private var depth = 0
  private var inString = false
  /// 直前のバイトが文字列の中の `\`（次の1バイトはエスケープされる）。
  private var escaped = false
  private var token: [UInt8] = []
  private var tokenActive = false
  private var tokenValid = true
  private var stringIsComments = false
  private var element: [UInt8] = []

  private static let commentsKey = Array("comments".utf8)

  public init() {}

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
  }

  /// チャンクを順に与える。要素が完成するたびに `handler` を呼ぶ（要素のバイト列は `{` から `}` まで）。
  public mutating func feed(_ chunk: [UInt8], handler: ([UInt8]) throws -> Void) rethrows -> Status {
    guard status == .needsMore else { return status }
    // 要素の途中のバイトは、チャンクの終わりか要素の完成のときにまとめて足す。
    var elementStart = 0
    var index = 0
    let count = chunk.count
    while index < count {
      let byte = chunk[index]
      if inString {
        if escaped {
          escaped = false
        } else if byte == 0x5C {
          escaped = true
          if tokenActive { tokenValid = false }
        } else if byte == 0x22 {
          inString = false
          if tokenActive {
            tokenActive = false
            stringIsComments = tokenValid && token == Self.commentsKey
            phase = .afterString
          }
        } else if tokenActive {
          if token.count < 16 { token.append(byte) } else { tokenValid = false }
        }
        index += 1
        continue
      }
      switch phase {
      case .start:
        if Self.isWhitespace(byte) || byte == 0xEF || byte == 0xBB || byte == 0xBF {
          break
        }
        if byte == 0x7B {
          depth = 1
          phase = .root
        } else {
          outcome = .rootNotObject
          status = .finished
          return status
        }
      case .root:
        rootByte(byte)
        if status == .finished { return status }
      case .afterString:
        if Self.isWhitespace(byte) { break }
        if byte == 0x3A {
          phase = stringIsComments ? .expectArray : .root
        } else {
          phase = .root
          rootByte(byte)
          if status == .finished { return status }
        }
      case .expectArray:
        if Self.isWhitespace(byte) { break }
        if byte == 0x5B {
          depth = 2
          phase = .inArray
          outcome = .arrayFound
        } else {
          outcome = .commentsNotArray
          status = .finished
          return status
        }
      case .inArray:
        switch byte {
        case 0x22:
          inString = true
        case 0x7B:
          if depth == 2 {
            phase = .inElement
            depth = 3
            element.removeAll(keepingCapacity: true)
            elementStart = index
          } else {
            depth += 1
          }
        case 0x5B:
          depth += 1
        case 0x7D:
          // 配列の要素の間に `}` は来ない。壊れているので、そこまでの要素を有効として終わる。
          if depth <= 2 {
            status = .finished
            return status
          }
          depth -= 1
        case 0x5D:
          depth -= 1
          if depth <= 1 {
            status = .finished
            return status
          }
        default:
          break
        }
      case .inElement:
        switch byte {
        case 0x22:
          inString = true
        case 0x7B, 0x5B:
          depth += 1
        case 0x7D, 0x5D:
          depth -= 1
          if depth == 2 {
            element.append(contentsOf: chunk[elementStart...index])
            phase = .inArray
            try handler(element)
            element.removeAll(keepingCapacity: true)
          }
        default:
          break
        }
      }
      index += 1
    }
    if phase == .inElement {
      // 文字列の途中でチャンクが終わった場合も含め、ここまでを持ち越す。
      element.append(contentsOf: chunk[elementStart..<count])
    }
    return status
  }

  /// ルートのオブジェクトの中のバイトを処理する（深さ1以上、文字列の外）。
  private mutating func rootByte(_ byte: UInt8) {
    switch byte {
    case 0x22:
      inString = true
      if depth == 1 {
        tokenActive = true
        tokenValid = true
        token.removeAll(keepingCapacity: true)
      }
    case 0x7B, 0x5B:
      depth += 1
    case 0x7D, 0x5D:
      depth -= 1
      if depth <= 0 {
        // ルートが閉じるまで `comments` が現れなかった。
        outcome = .commentsMissing
        status = .finished
      }
    default:
      break
    }
  }
}
