import SwiftUI

/// Settings view for configuring the Vision Pro Player app.
/// Allows users to set the WebSocket server URL and device name.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var webSocketManager: WebSocketManager

    @State private var serverURL: String = AppConfiguration.serverURL
    @State private var deviceName: String = AppConfiguration.deviceName
    @State private var autoConnect: Bool = AppConfiguration.autoConnect
    @State private var showingSaveConfirmation: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Server Configuration
                Section {
                    TextField("WebSocket Server URL", text: $serverURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Text("Example: ws://192.168.1.100:8080")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Server Connection")
                } footer: {
                    Text("Enter the WebSocket server URL running on your local network.")
                }

                // Device Settings
                Section {
                    TextField("Device Name", text: $deviceName)

                    Toggle("Auto-connect on launch", isOn: $autoConnect)
                } header: {
                    Text("Device")
                } footer: {
                    Text("This name will be displayed in the web controller.")
                }

                // Connection Status
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        ConnectionBadge(state: webSocketManager.connectionState)
                    }

                    HStack {
                        Text("Device ID")
                        Spacer()
                        Text(appState.deviceId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Connection")
                }

                // Actions
                Section {
                    Button(action: testConnection) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Test Connection")
                        }
                    }
                    .disabled(serverURL.isEmpty)

                    Button(action: reconnect) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reconnect")
                        }
                    }
                    .disabled(!webSocketManager.isConnected)
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com")!) {
                        HStack {
                            Text("Documentation")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                    }
                }
            }
            .alert("Settings Saved", isPresented: $showingSaveConfirmation) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your settings have been saved. The app will reconnect with the new settings.")
            }
        }
    }

    /// Saves the current settings
    private func saveSettings() {
        let urlChanged = serverURL != AppConfiguration.serverURL

        AppConfiguration.serverURL = serverURL
        AppConfiguration.deviceName = deviceName
        AppConfiguration.autoConnect = autoConnect

        if urlChanged && webSocketManager.isConnected {
            // Reconnect with new URL
            webSocketManager.updateServerURL(serverURL)
        }

        showingSaveConfirmation = true
    }

    /// Tests the connection with current settings
    private func testConnection() {
        // Temporarily update URL and try to connect
        let originalURL = AppConfiguration.serverURL
        AppConfiguration.serverURL = serverURL

        if webSocketManager.isConnected {
            webSocketManager.disconnect()
        }

        webSocketManager.connect()

        // Restore if it was different (the connect will use the new URL)
        if originalURL != serverURL {
            // URL has been updated, keep the new one
        }
    }

    /// Forces a reconnection
    private func reconnect() {
        webSocketManager.disconnect()
        webSocketManager.connect()
    }
}

/// A small badge showing connection state
struct ConnectionBadge: View {
    let state: WebSocketManager.ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(badgeColor)
                .frame(width: 8, height: 8)

            Text(state.rawValue.capitalized)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(badgeColor.opacity(0.2))
        )
    }

    private var badgeColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected:
            return .red
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(WebSocketManager())
}
