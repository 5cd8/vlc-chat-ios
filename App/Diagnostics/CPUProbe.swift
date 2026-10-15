import Darwin

enum CPUProbe {
  /// このプロセスが使ったCPU時間（ユーザー＋システム、秒）。全スレッドの合計。
  static func processCPUSeconds() -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
    return seconds(usage.ru_utime) + seconds(usage.ru_stime)
  }
}
