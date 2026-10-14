import SwiftUI

@main
struct VLCWithChatApp: App {
  @State private var model = M0Model()

  var body: some Scene {
    WindowGroup {
      M0View(model: model)
    }
  }
}
