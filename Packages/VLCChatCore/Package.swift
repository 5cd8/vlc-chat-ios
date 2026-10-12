// swift-tools-version: 6.0
import PackageDescription

// SwiftVLC には依存させない。libVLC のコピーがプロセス内に2つできると未定義動作になるため、
// SwiftVLC に依存するターゲットはアプリ本体だけにする。
let package = Package(
  name: "VLCChatCore",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "VLCChatCore", targets: ["VLCChatCore"])
  ],
  targets: [
    .target(name: "VLCChatCore"),
    .testTarget(name: "VLCChatCoreTests", dependencies: ["VLCChatCore"])
  ]
)
