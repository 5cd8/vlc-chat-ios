import Foundation

/// ファイル名の自然順。数字を数値として、大文字小文字を区別せずに比べる（Part2 < Part10）。
public enum NaturalOrder {
  public static func areInIncreasingOrder(_ lhs: String, _ rhs: String) -> Bool {
    switch lhs.compare(rhs, options: [.numeric, .caseInsensitive]) {
    case .orderedAscending: return true
    case .orderedDescending: return false
    case .orderedSame:
      // 大文字小文字だけが違う名前も、入力の並びによらず毎回同じ順にする。
      return lhs < rhs
    }
  }

  public static func sorted(_ names: [String]) -> [String] {
    names.sorted(by: areInIncreasingOrder)
  }
}
