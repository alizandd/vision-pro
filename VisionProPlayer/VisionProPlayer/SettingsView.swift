import SwiftUI

/// Settings view for configuring the Vision Pro Player app.
/// Allows users to set the WebSocket server URL and device name.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var webSocketManager: WebSocketManager
    /// Shared with the app — discovery runs for the whole session, Settings is
    /// only a window onto it.
    @EnvironmentObject var bonjourDiscovery: BonjourDiscovery
    @ObservedObject private var debug = StereoDebugSettings.shared

    @State private var serverURL: String = AppConfiguration.serverURL
    @State private var deviceName: String = AppConfiguration.deviceName
    @State private var autoConnect: Bool = AppConfiguration.autoConnect
    /// Controller picked in this screen, remembered by id rather than address.
    @State private var selectedControllerId: String? = AppConfiguration.preferredControllerId
    @State private var showingSaveConfirmation: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Discover Controllers - Auto-discovery section
                Section {
                    if bonjourDiscovery.isSearching {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Searching for controllers...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if bonjourDiscovery.discoveredControllers.isEmpty && !bonjourDiscovery.isSearching {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .foregroundColor(.secondary)
                            Text("No controllers found - tap Search or enter URL below")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    ForEach(bonjourDiscovery.discoveredControllers) { controller in
                        Button {
                            serverURL = controller.webSocketURL
                            selectedControllerId = controller.controllerId
                        } label: {
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundColor(.blue)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(controller.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(controller.webSocketURL)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if serverURL == controller.webSocketURL {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.title2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Button {
                        if bonjourDiscovery.isSearching {
                            bonjourDiscovery.stopSearching()
                        } else {
                            bonjourDiscovery.startSearching()
                        }
                    } label: {
                        HStack {
                            Image(systemName: bonjourDiscovery.isSearching ? "stop.fill" : "magnifyingglass")
                            Text(bonjourDiscovery.isSearching ? "Stop Searching" : "Search for Controllers")
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("iOS Controllers (Auto-Discovery)")
                    }
                } footer: {
                    Text("Make sure iOS Controller app is running on the same WiFi network.")
                }
                .onAppear {
                    // Auto-start searching when settings opens
                    if !bonjourDiscovery.isSearching {
                        bonjourDiscovery.startSearching()
                    }
                }
                
                // Server Configuration
                Section {
                    TextField("WebSocket Server URL", text: $serverURL)
                        .onChange(of: serverURL) { _, newValue in
                            // Typing an address by hand overrides discovery.
                            if bonjourDiscovery.discoveredControllers.first(where: { $0.webSocketURL == newValue }) == nil {
                                selectedControllerId = nil
                            }
                        }
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Text("Example: ws://192.168.1.100:8080")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Manual Server Connection")
                } footer: {
                    Text("Or manually enter the WebSocket server URL.")
                }

                // Device Settings
                Section {
                    TextField("Device Name", text: $deviceName)
                        .onChange(of: deviceName) { _, newValue in
                            // Cap at the source so the operator's device card
                            // can't be broken by a very long name.
                            if newValue.count > AppConfiguration.deviceNameMaxLength {
                                deviceName = String(newValue.prefix(AppConfiguration.deviceNameMaxLength))
                            }
                        }

                    Text("Shown on the controller so you can tell this headset apart from the others. Kept until you change it or delete the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)

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

                // True per-eye stereo (the actual fix)
                Section {
                    Toggle("True 3D (per-eye stereo)", isOn: $debug.trueStereoEnabled)
                } header: {
                    HStack {
                        Image(systemName: "cube.transparent")
                        Text("Stereoscopic Depth")
                    }
                } footer: {
                    Text("Renders each eye from its own half of Side-by-Side / Over-Under video using APMP metadata (visionOS 26+). Turn OFF to use the legacy single-view rendering. Depth is only visible on a real Vision Pro.")
                }

                // Stereo / 3D Debug & Test Mode
                Section {
                    Toggle("Enable Test Mode", isOn: $debug.testModeEnabled)

                    if debug.testModeEnabled {
                        Toggle("Show diagnostics panel", isOn: $debug.showDiagnostics)

                        Toggle("Eye Compare (L|R side-by-side)", isOn: $debug.eyeCompareEnabled)

                        Picker("Eye mapping (live)", selection: $debug.uvOverride) {
                            ForEach(UVOverride.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            diagRow("Resolution",
                                    debug.diagnostics.width > 0
                                        ? "\(debug.diagnostics.width) × \(debug.diagnostics.height)"
                                        : "—")
                            diagRow("Aspect",
                                    debug.diagnostics.aspectRatio > 0
                                        ? String(format: "%.3f : 1", debug.diagnostics.aspectRatio)
                                        : "—")
                            diagRow("Codec", debug.diagnostics.codec)
                            diagRow("Native stereo", debug.diagnostics.hasNativeStereoMetadata ? "YES" : "no")
                            diagRow("Suggested", debug.diagnostics.suggestedLayout.displayName)
                        }
                        .font(.caption)
                    }
                } header: {
                    HStack {
                        Image(systemName: "view.3d")
                        Text("3D / Stereo Test Mode")
                    }
                } footer: {
                    Text("'Eye Compare' shows the Left and Right eye crops side-by-side on flat panels — this works in the SIMULATOR to verify each eye gets a different, correctly-cropped image. Final depth fusion is only visible on a real Vision Pro.")
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

    /// A compact label/value row for the inline diagnostics readout.
    private func diagRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }

    /// Saves the current settings
    private func saveSettings() {
        let urlChanged = serverURL != AppConfiguration.serverURL
        let nameChanged = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            != AppConfiguration.deviceName

        AppConfiguration.serverURL = serverURL
        AppConfiguration.deviceName = deviceName
        AppConfiguration.autoConnect = autoConnect

        // Reflect whatever was actually stored — an empty entry falls back to
        // the default, and the field should show that rather than stay blank.
        deviceName = AppConfiguration.deviceName
        // A hand-typed URL is deliberately not tied to a discovered controller,
        // so clear the preference rather than leaving a stale one behind.
        AppConfiguration.preferredControllerId = selectedControllerId

        if urlChanged && webSocketManager.isConnected {
            // Reconnect with new URL
            webSocketManager.updateServerURL(serverURL)
        } else if nameChanged {
            // Push the new name straight away, so the operator's device list
            // stops showing the old one without waiting for a reconnect.
            webSocketManager.announceIdentity()
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
