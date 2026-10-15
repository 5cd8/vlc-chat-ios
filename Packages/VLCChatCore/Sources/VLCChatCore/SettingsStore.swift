import Foundation

/// 設定。`UserDefaults` に保存する。
public struct SettingsStore {
  private static let autoAdvanceKey = "autoAdvance"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// 既定オン。未設定と「オフにした」を区別するために `object(forKey:)` を見る。
  public var autoAdvance: Bool {
    get { defaults.object(forKey: Self.autoAdvanceKey) == nil ? true : defaults.bool(forKey: Self.autoAdvanceKey) }
    nonmutating set { defaults.set(newValue, forKey: Self.autoAdvanceKey) }
  }
}
