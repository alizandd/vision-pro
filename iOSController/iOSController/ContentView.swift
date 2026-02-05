import SwiftUI
import Network
import Darwin

struct ContentView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @State private var showingLogs = false
    @State private var showingVideoTransfer = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Server Status Bar
                ServerStatusBar()
                
                // Connection Info Card (when server is running)
                if deviceManager.isServerRunning {
                    ConnectionInfoCard()
                }
                
                // Main Content
                if deviceManager.devices.isEmpty {
                    EmptyDevicesView()
                } else {
                    DeviceListView()
                }
            }
            .navigationTitle("Vision Pro Controller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ServerToggleButton()
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // Send Videos Button
                        Button {
                            showingVideoTransfer.toggle()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(!deviceManager.isServerRunning || deviceManager.devices.isEmpty)
                        
                        // Logs Button
                        Button {
                            showingLogs.toggle()
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingLogs) {
                LogsView()
            }
            .sheet(isPresented: $showingVideoTransfer) {
                VideoTransferView(transferServer: deviceManager.fileTransferServer)
            }
        }
    }
}

// MARK: - Connection Info Card

struct ConnectionInfoCard: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @State private var localIP: String = "..."
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.blue)
                Text("Vision Pro Connection URL:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            HStack {
                Text("ws://\(localIP):\(String(format: "%d", deviceManager.serverPort))")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button {
                    UIPasteboard.general.string = "ws://\(localIP):\(String(format: "%d", deviceManager.serverPort))"
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 8)
        .onAppear {
            localIP = NetworkUtils.getLocalIPAddress() ?? "127.0.0.1"
        }
    }
}

// MARK: - Network Utils

struct NetworkUtils {
    static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            let interface = ptr?.pointee
            let addrFamily = interface?.ifa_addr.pointee.sa_family
            
            // Check for IPv4
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: (interface?.ifa_name)!)
                
                // Skip loopback
                if name == "en0" || name == "en1" || name.hasPrefix("bridge") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface?.ifa_addr,
                               socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                               &hostname,
                               socklen_t(hostname.count),
                               nil,
                               0,
                               NI_NUMERICHOST)
                    address = String(cString: hostname)
                    
                    // Prefer en0 (WiFi on iOS)
                    if name == "en0" {
                        break
                    }
                }
            }
        }
        
        return address
    }
}

// MARK: - Server Status Bar

struct ServerStatusBar: View {
    @EnvironmentObject var deviceManager: DeviceManager
    
    var body: some View {
        HStack {
            // Status Indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(deviceManager.isServerRunning ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                
                Text(deviceManager.isServerRunning ? "Server Running" : "Server Stopped")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Connection Info
            if deviceManager.isServerRunning {
                HStack(spacing: 16) {
                    Label("Port \(String(format: "%d", deviceManager.serverPort))", systemImage: "network")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("\(deviceManager.devices.count) device\(deviceManager.devices.count == 1 ? "" : "s")", systemImage: "visionpro")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }
}

// MARK: - Server Toggle Button

struct ServerToggleButton: View {
    @EnvironmentObject var deviceManager: DeviceManager
    
    var body: some View {
        Button {
            if deviceManager.isServerRunning {
                deviceManager.stopServer()
            } else {
                deviceManager.startServer()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: deviceManager.isServerRunning ? "stop.fill" : "play.fill")
                Text(deviceManager.isServerRunning ? "Stop" : "Start")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(deviceManager.isServerRunning ? .red : .green)
    }
}

// MARK: - Empty State

struct EmptyDevicesView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "visionpro")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Devices Connected")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if deviceManager.isServerRunning {
                    Text("Waiting for Vision Pro devices to connect...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Text("Use the connection URL above in Vision Pro settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Start the server to begin")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if !deviceManager.isServerRunning {
                Button {
                    deviceManager.startServer()
                } label: {
                    Label("Start Server", systemImage: "play.fill")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Device List

struct DeviceListView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(deviceManager.devices) { device in
                    DeviceCardView(device: device)
                }
            }
            .padding()
        }
    }
}

// MARK: - Logs View

struct LogsView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(deviceManager.logs.reversed()) { log in
                    HStack(alignment: .top, spacing: 12) {
                        Text(log.timeString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)
                        
                        Circle()
                            .fill(logColor(for: log.type))
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)
                        
                        Text(log.message)
                            .font(.subheadline)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Activity Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") {
                        deviceManager.clearLogs()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    func logColor(for type: LogType) -> Color {
        switch type {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DeviceManager())
}
