import Combine
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: Tab = .status
    @State private var showingSettings = false
    private let performanceTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private enum Tab: Hashable { case status, web, background }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                StatusView()
                    .navigationTitle("AList")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showingSettings = true } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel("设置")
                        }
                    }
            }
            .tabItem { Label("状态", systemImage: "gauge.with.dots.needle.67percent") }
            .tag(Tab.status)

            NavigationStack {
                Group {
                    if selectedTab == .web && model.state == .running {
                        AlistWebView(url: model.localURL)
                    } else if model.state == .running {
                        Color.clear
                    } else {
                        ContentUnavailableView("AList 未运行", systemImage: "network.slash")
                    }
                }
                .navigationTitle("AList 网页")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("网页", systemImage: "globe") }
            .tag(Tab.web)

            NavigationStack {
                KeepAliveView(controller: model.keepAlive)
                    .navigationTitle("后台保活")
            }
            .tabItem { Label("后台", systemImage: "moon.stars") }
            .tag(Tab.background)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView().environmentObject(model)
        }
        .alert("AList 错误", isPresented: Binding(
            get: { model.errorText != nil },
            set: { if !$0 { model.errorText = nil } }
        )) {
            Button("确定", role: .cancel) { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
        .onAppear { model.start() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            model.keepAlive.refresh()
            model.resumePerformanceSampling()
        }
        .onReceive(performanceTicker) { _ in
            guard UIApplication.shared.applicationState == .active else { return }
            model.refreshPerformance()
        }
    }
}

private struct StatusView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingLANConfirmation = false

    var body: some View {
        List {
            Section("概览") {
                LabeledContent("运行状态", value: model.state.label)
                LabeledContent("运行时间", value: model.uptime)
                LabeledContent("CPU 占用", value: model.cpuPercent.map { String(format: "%.1f%%", $0) }
                    ?? (model.state == .running ? "采样中" : "--"))
                LabeledContent("管理员账号", value: "admin")
                LabeledContent("管理员密码", value: "admin")
            }

            Section("服务") {
                Button {
                    if model.state == .running { model.stop() } else { model.start() }
                } label: {
                    Label(model.state == .running ? "停止" : "启动",
                          systemImage: model.state == .running ? "stop.fill" : "play.fill")
                }
                .disabled(model.state == .starting)
                Toggle("局域网访问", isOn: Binding(
                    get: { model.lanEnabled },
                    set: { enabled in
                        if enabled { showingLANConfirmation = true }
                        else { model.setLANEnabled(false) }
                    }
                ))
                .disabled(model.state != .running)
            }

            Section("访问地址") {
                addressRow("本机", model.localURL.absoluteString)
                if model.lanEnabled {
                    addressRow("局域网", model.lanAddress ?? "无可用地址")
                }
            }

            Section("内存") {
                LabeledContent("物理内存", value: size(model.physicalMemoryBytes))
                LabeledContent("Go 已分配", value: size(model.goAllocatedBytes))
                LabeledContent("Go 系统内存", value: size(model.goSystemBytes))
            }
        }
        .confirmationDialog("开启局域网访问", isPresented: $showingLANConfirmation) {
            Button("开启") { model.setLANEnabled(true) }
        } message: {
            Text("同一网络中的设备将可访问 AList。管理员账号和密码固定为 admin/admin。")
        }
    }

    private func addressRow(_ title: String, _ address: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(address).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.trailing)
            Button {
                UIPasteboard.general.string = address
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("复制\(title)地址")
        }
    }

    private func size(_ bytes: UInt64?) -> String {
        guard let bytes else { return "--" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

private struct KeepAliveView: View {
    @ObservedObject var controller: BackgroundKeepAliveController

    var body: some View {
        List {
            Section("静音音频") {
                Toggle("启用", isOn: $controller.audioEnabled)
                LabeledContent("状态", value: controller.audioStatus)
            }
            Section("后台定位") {
                Toggle("启用", isOn: $controller.locationEnabled)
                LabeledContent("状态", value: controller.locationStatus)
                if controller.locationStatus == "定位权限不可用" || controller.locationStatus == "需要始终允许定位" {
                    Button("打开系统设置") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var logText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("AList 日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { loadLogs() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("刷新日志")
                }
            }
            .onAppear(perform: loadLogs)
        }
    }

    private func loadLogs() {
        logText = (try? model.recentLogs()) ?? "暂无日志"
    }
}
