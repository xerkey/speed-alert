import CoreLocation

/// GPS ドップラー速度（CLLocation.speed）を平滑化しつつ加速度を推定し、
/// 最後のフィックスから現在時刻まで外挿して GPS の約1秒の遅延を補償する。
/// キッカー進入中の加速に音を追従させるための要。
struct SpeedEstimator {
    private var v: Double = 0          // 平滑化済み速度 m/s
    private var a: Double = 0          // 平滑化済み加速度 m/s^2
    private var lastFixTime: Date?
    private var hasFix = false

    mutating func reset() { self = SpeedEstimator() }

    mutating func push(_ location: CLLocation) {
        // speed < 0 / speedAccuracy < 0 は無効値
        guard location.speed >= 0, location.speedAccuracy >= 0 else { return }
        let t = location.timestamp
        if hasFix, let last = lastFixTime {
            let dt = t.timeIntervalSince(last)
            if dt > 0, dt < 5 {
                let aRaw = (location.speed - v) / dt
                a = a * 0.5 + aRaw * 0.5
            }
        }
        v = hasFix ? v * 0.4 + location.speed * 0.6 : location.speed
        hasFix = true
        lastFixTime = t
    }

    /// 現在時刻での推定速度 m/s（外挿つき）。フィックスが3秒途絶えたら減衰させる。
    func current(at now: Date = Date()) -> Double {
        guard hasFix, let last = lastFixTime else { return 0 }
        let age = now.timeIntervalSince(last)
        if age > 3 { return max(0, v * max(0, 1 - (age - 3))) }
        return max(0, v + a * min(age, 1.5))
    }
}
