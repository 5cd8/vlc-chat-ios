import SwiftUI

@main
struct VLCWithChatApp: App {
  @State private var app = AppModel()

  var body: some Scene {
    WindowGroup {
      PlayerScreen(app: app)
    }
  }
}
