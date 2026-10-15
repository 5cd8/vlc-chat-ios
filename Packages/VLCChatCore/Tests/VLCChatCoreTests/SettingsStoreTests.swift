import Foundation
import Testing
@testable import VLCChatCore

struct SettingsStoreTests {
  private func withDefaults(_ body: (UserDefaults, String) -> Void) {
    let suite = "SettingsStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    body(defaults, suite)
  }

  @Test("自動進行は既定でオン") func autoAdvanceDefaultsToOn() {
    withDefaults { defaults, _ in
      #expect(SettingsStore(defaults: defaults).autoAdvance)
    }
  }

  @Test("オフにすると新しい SettingsStore で読んでもオフ、戻せる") func autoAdvancePersists() {
    withDefaults { defaults, _ in
      SettingsStore(defaults: defaults).autoAdvance = false
      #expect(!SettingsStore(defaults: defaults).autoAdvance)
      SettingsStore(defaults: defaults).autoAdvance = true
      #expect(SettingsStore(defaults: defaults).autoAdvance)
    }
  }
}
