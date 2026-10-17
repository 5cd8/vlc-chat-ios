import Testing
@testable import VLCChatCore

struct EmojiAnimationGateTests {
  @Test("動かすのは、前面で、PiPでなく、スクロール中でなく、シートに覆われていないときだけ")
  func animatesOnlyWhenAllConditionsHold() {
    var animatingCases: [String] = []
    for isForeground in [false, true] {
      for isPiPActive in [false, true] {
        for isScrolling in [false, true] {
          for isCovered in [false, true] {
            let actual = EmojiAnimationGate.shouldAnimate(
              isForeground: isForeground, isPiPActive: isPiPActive, isScrolling: isScrolling, isCovered: isCovered)
            if actual {
              animatingCases.append("前面=\(isForeground) PiP=\(isPiPActive) スクロール=\(isScrolling) 覆い=\(isCovered)")
            }
          }
        }
      }
    }
    // 16通りのうち、真になるのは前面だけが真の1通り。
    #expect(animatingCases == ["前面=true PiP=false スクロール=false 覆い=false"])
  }
}
