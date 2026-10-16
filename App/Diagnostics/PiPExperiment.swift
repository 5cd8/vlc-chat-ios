import Foundation

/// 切り替えの後に `PiPController.isPossible` が偽のとき、何で真に戻るかを実機で試すための暫定の実験
/// （Issue #12 第2段階）。診断シートのボタンから `AppModel.runPiPExperiment` を呼ぶ。
/// 原因と対策が決まったら、ボタンごと消す。
enum PiPExperiment: CaseIterable, Identifiable {
  case pauseResume
  case reopenCurrent
  case recreateController
  case measure

  var id: Self { self }

  var title: String {
    switch self {
    case .pauseResume: "一時停止→再開"
    case .reopenCurrent: "同じ動画を開き直す"
    case .recreateController: "PiPControllerを作り直す（描画面は引き継ぐ）"
    case .measure: "今の可否を測る"
    }
  }
}
