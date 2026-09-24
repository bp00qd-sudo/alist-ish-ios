import AVFoundation
import Combine
import CoreLocation
import Foundation

@MainActor
final class BackgroundKeepAliveController: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var audioEnabled: Bool {
        didSet {
            UserDefaults.standard.set(audioEnabled, forKey: "alist.audioKeepAlive")
            updateAudio()
        }
    }
    @Published var locationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(locationEnabled, forKey: "alist.locationKeepAlive")
            updateLocation()
        }
    }
    @Published private(set) var audioStatus = "未启用"
    @Published private(set) var locationStatus = "未启用"

    private let locationManager = CLLocationManager()
    private var player: AVAudioPlayer?
    private var serviceRunning = false
    private var requestedAlwaysAuthorization = false

    override init() {
        audioEnabled = UserDefaults.standard.bool(forKey: "alist.audioKeepAlive")
        locationEnabled = UserDefaults.standard.bool(forKey: "alist.locationKeepAlive")
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 1000
        locationManager.pausesLocationUpdatesAutomatically = false
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
    }

    func serviceDidChange(running: Bool) {
        serviceRunning = running
        updateAudio()
        updateLocation()
    }

    func refresh() {
        updateAudio()
        updateLocation()
    }

    private func updateAudio() {
        guard audioEnabled && serviceRunning else {
            player?.stop()
            player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioStatus = audioEnabled ? "等待服务启动" : "未启用"
            return
        }
        if player?.isPlaying == true {
            audioStatus = "运行中"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let activePlayer = try AVAudioPlayer(data: Self.silentWAV())
            activePlayer.numberOfLoops = -1
            activePlayer.prepareToPlay()
            guard activePlayer.play() else {
                audioStatus = "音频启动失败"
                return
            }
            player = activePlayer
            audioStatus = "运行中"
        } catch {
            audioStatus = "失败：\(error.localizedDescription)"
        }
    }

    private func updateLocation() {
        guard locationEnabled && serviceRunning else {
            locationManager.stopUpdatingLocation()
            locationManager.allowsBackgroundLocationUpdates = false
            locationStatus = locationEnabled ? "等待服务启动" : "未启用"
            return
        }
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.startUpdatingLocation()
            locationStatus = "等待定位更新"
        case .notDetermined:
            locationStatus = "等待定位授权"
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationStatus = "需要始终允许定位"
            if !requestedAlwaysAuthorization {
                requestedAlwaysAuthorization = true
                locationManager.requestAlwaysAuthorization()
            }
        case .denied, .restricted:
            locationManager.stopUpdatingLocation()
            locationStatus = "定位权限不可用"
        @unknown default:
            locationStatus = "定位状态未知"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.updateLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if self.locationEnabled && self.serviceRunning {
                self.locationStatus = "运行中"
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.locationStatus = "失败：\(error.localizedDescription)" }
    }

    @objc private func audioInterrupted(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
        if type == .began {
            audioStatus = "音频中断"
        } else {
            player?.stop()
            player = nil
            updateAudio()
        }
    }

    private static func silentWAV() -> Data {
        let sampleRate: UInt32 = 8_000
        let dataSize = UInt32(16_000)
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLE(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(1))
        data.appendLE(sampleRate)
        data.appendLE(sampleRate * 2)
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        data.appendLE(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
