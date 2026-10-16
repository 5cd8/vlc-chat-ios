import Observation
import VLCChatCore

@Observable
@MainActor
final class SettingsModel {
  private(set) var autoAdvance: Bool
  @ObservationIgnored private let store = SettingsStore()

  init() {
    autoAdvance = store.autoAdvance
  }

  func setAutoAdvance(_ value: Bool) {
    autoAdvance = value
    store.autoAdvance = value
  }
}
