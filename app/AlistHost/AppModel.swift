import Darwin
import Foundation
import Network
import SwiftUI

#if canImport(AlistCore)
import AlistCore
#endif

@MainActor
final class AppModel: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)

        var label: String {
            switch self {
            case .stopped: return "已停止"
            case .starting: return "启动中"
            case .running: return "运行中"
            case .failed(let message): return "启动失败：\(message)"
            }
        }
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var lanEnabled = false
    @Published private(set) var lanAddress: String?
    @Published private(set) var physicalMemoryBytes: UInt64?
    @Published private(set) var goAllocatedBytes: UInt64?
    @Published private(set) var goSystemBytes: UInt64?
    @Published private(set) var cpuPercent: Double?
    @Published private(set) var uptime = "00:00:00"
    @Published var errorText: String?

    let localURL = URL(string: "http://127.0.0.1:5244")!
    let keepAlive = BackgroundKeepAliveController()

#if canImport(AlistCore)
    private var runtime: IosbridgeRuntime?
#endif
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "alist.network-monitor", qos: .utility)
    private var startedAt: Date?
    private var lastCPUSample: (time: Date, seconds: Double)?
    private var lastGoMemorySample: Date?

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshLANAddress() }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    deinit {
        pathMonitor.cancel()
    }

    func start() {
        guard state != .starting, state != .running else { return }
        state = .starting
        do {
            let directories = try makeDirectories()
            let options: [String: Any] = [
                "dataDir": directories.data.path,
                "tempDir": directories.cache.path,
                "bindAddress": "127.0.0.1",
                "port": 5244,
                "webdav": true,
                "s3": false,
                "ftp": false,
                "sftp": false,
                "memoryLimitBytes": 96 * 1024 * 1024
            ]
            let data = try JSONSerialization.data(withJSONObject: options)
            let json = String(decoding: data, as: UTF8.self)
#if canImport(AlistCore)
            Task.detached(priority: .userInitiated) { [weak self] in
                var startError: NSError?
                let startedRuntime = IosbridgeStart(json, &startError)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if let startedRuntime {
                        self.runtime = startedRuntime
                        self.startedAt = Date()
                        self.state = .running
                        self.keepAlive.serviceDidChange(running: true)
                        self.refreshPerformance()
                    } else {
                        self.state = .failed(startError?.localizedDescription ?? "AList 无法启动")
                    }
                }
            }
#else
            state = .failed("AlistCore.xcframework 未生成")
#endif
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        guard state == .running else { return }
        keepAlive.serviceDidChange(running: false)
#if canImport(AlistCore)
        if let runtime { try? runtime.stop() }
        runtime = nil
#endif
        state = .stopped
        startedAt = nil
        lastCPUSample = nil
        lastGoMemorySample = nil
        lanEnabled = false
        lanAddress = nil
        physicalMemoryBytes = nil
        goAllocatedBytes = nil
        goSystemBytes = nil
        cpuPercent = nil
        uptime = "00:00:00"
    }

    func setLANEnabled(_ enabled: Bool) {
#if canImport(AlistCore)
        guard let runtime, state == .running else { return }
        do {
            try runtime.setLANEnabled(enabled)
            lanEnabled = enabled
            refreshLANAddress()
        } catch {
            errorText = error.localizedDescription
        }
#endif
    }

    func refreshPerformance() {
        guard state == .running else { return }
        let now = Date()
        if let startedAt {
            let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
            uptime = String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
        }
        if lastGoMemorySample.map({ now.timeIntervalSince($0) >= 5 }) ?? true {
            lastGoMemorySample = now
#if canImport(AlistCore)
            if let json = runtime?.memoryStats(), let data = json.data(using: .utf8),
               let values = try? JSONSerialization.jsonObject(with: data) as? [String: NSNumber] {
                goAllocatedBytes = values["alloc"]?.uint64Value
                goSystemBytes = values["sys"]?.uint64Value
            }
#endif
        }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            physicalMemoryBytes = info.phys_footprint
        }

        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            let seconds = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            let cpuSampleTime = Date()
            if let lastCPUSample {
                let elapsed = cpuSampleTime.timeIntervalSince(lastCPUSample.time)
                if elapsed > 0 { cpuPercent = max(0, (seconds - lastCPUSample.seconds) / elapsed * 100) }
            }
            lastCPUSample = (cpuSampleTime, seconds)
        }
    }

    func resumePerformanceSampling() {
        lastCPUSample = nil
        cpuPercent = nil
        refreshPerformance()
    }

    func recentLogs() throws -> String {
        let dataDir = try FileManager.default.url(for: .applicationSupportDirectory,
                                                   in: .userDomainMask, appropriateFor: nil, create: false)
        let logURL = dataDir.appendingPathComponent("Alist/log/log.log")
        let handle = try FileHandle(forReadingFrom: logURL)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        var offset = length
        var bytes = Data()
        var lineBreaks = 0
        while offset > 0 && lineBreaks <= 200 {
            let count = min(offset, 8_192)
            offset -= count
            try handle.seek(toOffset: offset)
            let chunk = try handle.read(upToCount: Int(count)) ?? Data()
            lineBreaks += chunk.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
            bytes.insert(contentsOf: chunk, at: 0)
        }
        var lines = String(decoding: bytes, as: UTF8.self).components(separatedBy: .newlines)
        if offset > 0 && !lines.isEmpty { lines.removeFirst() }
        if lines.last == "" { lines.removeLast() }
        let recent = lines.suffix(200).joined(separator: "\n")
        let pattern = "\u{001B}\\[[0-9;]*m"
        return recent.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private func makeDirectories() throws -> (data: URL, cache: URL) {
        let manager = FileManager.default
        let data = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true).appendingPathComponent("Alist", isDirectory: true)
        let cache = try manager.url(for: .cachesDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true).appendingPathComponent("Alist", isDirectory: true)
        try manager.createDirectory(at: data, withIntermediateDirectories: true)
        try manager.createDirectory(at: cache, withIntermediateDirectories: true)
        return (data, cache)
    }

    private func refreshLANAddress() {
        guard lanEnabled else { lanAddress = nil; return }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { lanAddress = nil; return }
        defer { freeifaddrs(interfaces) }
        for node in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(node.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = node.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                lanAddress = "http://\(String(cString: host)):5244"
                return
            }
        }
        lanAddress = nil
    }
}
