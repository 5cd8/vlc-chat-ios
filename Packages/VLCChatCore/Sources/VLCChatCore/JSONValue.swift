import Foundation

/// `JSONSerialization` が返す値（`Any`）の型を、PC版の `JsonValueKind` と同じ基準で確かめる。
enum JSONValue {
  /// JSONの `true` / `false` か。`NSNumber` の 0・1 は `as? Bool` で真偽値になってしまうので、
  /// `CFBoolean` かどうかで区別する。
  static func isBoolean(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
  }

  static func bool(_ value: Any?) -> Bool? {
    guard let value, isBoolean(value), let number = value as? NSNumber else { return nil }
    return number.boolValue
  }

  /// JSONの数値（真偽値は除く）。
  static func number(_ value: Any?) -> Double? {
    guard let value, !isBoolean(value), let number = value as? NSNumber else { return nil }
    return number.doubleValue
  }
}
