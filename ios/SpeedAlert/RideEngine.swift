import CoreLocation
import Combine
import UIKit

enum GpsState: Equatable {
    case off
    case acquiring
    case fix(accuracy: Double)   // 水平精度 m
    case denied
    case error

    var label: String {
        switch self {
        case .off: return "GPS 停止中"
        case .acquiring: return "GPS 取得中…"
        case .fix(let acc):
            if acc <= 10 { return "GPS 良好 ±\(Int(acc))m" }
            if acc <= 30 { return "GPS 弱い ±\(Int(acc))m" }
            return "GPS 不良 ±\(Int(acc))m"
        case .denied: return "位置情報が許可されていません"
        case .error: return "GPS エラー"
        }
    }
}

@MainActor
final class RideEngine: NSObject, ObservableObject {
    @Published var speedKmh: Double = 0
    @Published var running = false
    @Published var gps: GpsState = .off
    @Published var demoMode = false
    @Published var demoKmh: Double = 0

    @Published var targetKmh: Double {
        didSet { UserDefaults.standard.set(targetKmh, forKey: "targetKmh") }
    }
    @Published var rangeKmh: Double {
        didSet { UserDefaults.standard.set(rangeKmh, forKey: "rangeKmh") }
    }
    var alarmStartKmh: Double { max(0, targetKmh - rangeKmh) }

    private let manager = CLLocationManager()
    private let beeper = Beeper()
    private var estimator = SpeedEstimator()
    private var timer: Timer?

    override init() {
        let d = UserDefaults.standard
        targetKmh = d.object(forKey: "targetKmh") as? Double ?? 40
        rangeKmh = d.object(forKey: "rangeKmh") as? Double ?? 15
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func toggle() { running ? stop() : start() }

    func start() {
        running = true
        estimator.reset()
        try? beeper.start()

        if !demoMode {
            switch manager.authorizationStatus {
            case .notDetermined:
                gps = .acquiring
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                gps = .denied
            default:
                beginUpdates()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        running = false
        beeper.stop()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        timer?.invalidate()
        timer = nil
        gps = .off
        speedKmh = 0
    }

    private func beginUpdates() {
        gps = .acquiring
        // UIBackgroundModes に location があるので、フォアグラウンドで開始すれば
        // 画面ロック中・バックグラウンドでも更新が続く
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    private func tick() {
        let kmh = demoMode ? demoKmh : estimator.current() * 3.6
        speedKmh = kmh
        let span = max(1, targetKmh - alarmStartKmh)
        beeper.ratio = running ? (kmh - alarmStartKmh) / span : -1
    }
}

extension RideEngine: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.running, !self.demoMode else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.beginUpdates()
            case .denied, .restricted:
                self.gps = .denied
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                self.estimator.push(location)
            }
            if let last = locations.last {
                self.gps = .fix(accuracy: last.horizontalAccuracy)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if (error as? CLError)?.code == .denied { self.gps = .denied }
            else if self.gps == .acquiring { self.gps = .error }
        }
    }
}
