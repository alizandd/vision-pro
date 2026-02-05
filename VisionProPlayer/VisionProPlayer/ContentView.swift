import SwiftUI

/// Main content view - minimal UI showing connection status.
/// The app is designed to be controlled remotely, so the UI is intentionally minimal.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var webSocketManager: WebSocketManager
    @EnvironmentObject var nativeVideoManager: NativeVideoPlayerManager

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Connection status
                ConnectionStatusView(state: webSocketManager.connectionState)
                
                // Server URL display (tappable to open settings)
                Button(action: { openWindow(id: "settings") }) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.secondary)
                        Text(AppConfiguration.serverURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                    )
                }
                .buttonStyle(.plain)
                
                // Connect/Disconnect button
                HStack(spacing: 12) {
                    if webSocketManager.connectionState == .connected {
                        Button(action: { webSocketManager.disconnect() }) {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else if webSocketManager.connectionState == .connecting || webSocketManager.connectionState == .reconnecting {
                        Button(action: { webSocketManager.disconnect() }) {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    } else {
                        Button(action: { webSocketManager.connect() }) {
                            Label("Connect", systemImage: "link")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                // Current state
                StatusInfoView(
                    playbackState: nativeVideoManager.playbackState,
                    currentVideo: appState.currentVideoURL,
                    isImmersive: appState.isImmersiveActive
                )

                Spacer()
            }
            .padding(32)
            .navigationTitle("Vision Pro Player")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { openWindow(id: "settings") }) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
        // Window is now completely dismissed during immersive mode (like native player)
    }
}

/// Displays the WebSocket connection status
struct ConnectionStatusView: View {
    let state: WebSocketManager.ConnectionState

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.5), lineWidth: 3)
                        .scaleEffect(state == .connecting || state == .reconnecting ? 1.5 : 1.0)
                        .opacity(state == .connecting || state == .reconnecting ? 0 : 1)
                        .animation(
                            state == .connecting || state == .reconnecting
                                ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                                : .default,
                            value: state
                        )
                )

            Text(statusText)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    private var statusColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected:
            return .red
        }
    }

    private var statusText: String {
        switch state {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .reconnecting:
            return "Reconnecting..."
        case .disconnected:
            return "Disconnected"
        }
    }
}

/// Displays current playback status information
struct StatusInfoView: View {
    let playbackState: PlaybackState
    let currentVideo: String?
    let isImmersive: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Playback state
            HStack {
                Image(systemName: stateIcon)
                    .foregroundColor(stateColor)
                Text(playbackState.rawValue.capitalized)
                    .font(.subheadline)
            }

            // Immersive mode indicator
            if isImmersive {
                HStack {
                    Image(systemName: "visionpro")
                    Text("Immersive Mode Active")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }

            // Current video (truncated)
            if let video = currentVideo {
                Text(truncatedURL(video))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }

    private var stateIcon: String {
        switch playbackState {
        case .idle:
            return "circle"
        case .loading:
            return "arrow.clockwise"
        case .playing:
            return "play.fill"
        case .paused:
            return "pause.fill"
        case .stopped:
            return "stop.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var stateColor: Color {
        switch playbackState {
        case .idle:
            return .gray
        case .loading:
            return .orange
        case .playing:
            return .green
        case .paused:
            return .yellow
        case .stopped:
            return .gray
        case .error:
            return .red
        }
    }

    private func truncatedURL(_ url: String) -> String {
        if url.count > 50 {
            let start = url.prefix(25)
            let end = url.suffix(20)
            return "\(start)...\(end)"
        }
        return url
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(WebSocketManager())
        .environmentObject(NativeVideoPlayerManager())
}
