import Foundation

/// Lightweight remote logger that mirrors local `print` output to the relay
/// server so logs from a standalone Vision Pro (where the Xcode console isn't
/// attached) can be inspected centrally.
///
/// Logs are buffered in memory and flushed in batches over HTTP POST to the
/// same host that serves the WebSocket relay (derived from `AppConfiguration.serverURL`,
/// converting `ws(s)://` to `http(s)://`). The server appends them to
/// `server/logs/visionpro.log` and prints them to its console.
///
/// Usage:
///   RemoteLog.log("APMP", "trueStereo=\(enabled) availability=\(ok)")
@MainActor
final class RemoteLogger: ObservableObject {
    static let shared = RemoteLogger()

    /// Master switch for remote logging. Turned OFF now that the stereo-depth
    /// issue is resolved, so no log traffic is generated in normal use. Flip to
    /// `true` to re-enable remote diagnostics during future investigations.
    static let isEnabled = false

    /// A single pending log entry.
    private struct Entry: Encodable {
        let ts: String
        let tag: String
        let message: String
        let device: String
        let deviceId: String
    }

    private struct Payload: Encodable {
        let logs: [Entry]
    }

    /// Pending entries waiting to be flushed to the server.
    private var buffer: [Entry] = []

    /// Hard cap so a long offline period can't grow memory without bound.
    private let maxBufferedEntries = 500

    private let deviceId: String
    private var deviceName: String { AppConfiguration.deviceName }

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var flushTask: Task<Void, Never>?
    private let session: URLSession

    private init() {
        self.deviceId = UserDefaults.standard.string(forKey: "device_id") ?? "unknown-device"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)

        // Only stream logs to the server from a REAL device, and only when the
        // master switch is on. On the simulator the external host often isn't
        // DNS-resolvable, and the constant failed POSTs add network noise.
        #if !targetEnvironment(simulator)
        if Self.isEnabled {
            startFlushLoop()
        }
        #endif
    }

    deinit {
        flushTask?.cancel()
    }

    // MARK: - Public API

    /// Logs the device/app environment once, so every server session starts with
    /// the facts needed to reason about the stereo/depth pipeline (most importantly
    /// the visionOS version, since true per-eye APMP rendering requires visionOS 26+).
    func logEnvironment() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let supportsAPMP = os.majorVersion >= 26

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        #if targetEnvironment(simulator)
        let runtime = "SIMULATOR (renders ONE eye only — depth NOT verifiable here)"
        #else
        let runtime = "DEVICE"
        #endif

        log("Env", "visionOS=\(osString) supportsAPMP(>=26)=\(supportsAPMP) runtime=\(runtime) app=\(appVersion)(\(build)) device=\(deviceName) id=\(deviceId)")
    }

    /// Records a tagged log line. Always mirrors to the local console so existing
    /// Xcode-attached workflows keep working, then queues it for the server.
    func log(_ tag: String, _ message: String) {
        print("[\(tag)] \(message)")

        // On simulator we only mirror to the console — never buffer or POST,
        // so there's zero network traffic from logging during local dev.
        #if targetEnvironment(simulator)
        return
        #else
        let entry = Entry(
            ts: isoFormatter.string(from: Date()),
            tag: tag,
            message: message,
            device: deviceName,
            deviceId: deviceId
        )
        buffer.append(entry)

        // Drop oldest entries if we exceed the cap (keep the most recent).
        if buffer.count > maxBufferedEntries {
            buffer.removeFirst(buffer.count - maxBufferedEntries)
        }
        #endif
    }

    // MARK: - Flushing

    /// Number of consecutive failed flushes, used to back off so an unreachable
    /// host (e.g. DNS not resolvable from the simulator) doesn't spam the network.
    private var consecutiveFailures = 0

    private func startFlushLoop() {
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                let delaySeconds = await self?.nextFlushDelaySeconds() ?? 1
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                await self?.flush()
            }
        }
    }

    /// 1s when healthy; exponential backoff up to 60s after repeated failures.
    private func nextFlushDelaySeconds() -> Double {
        guard consecutiveFailures > 0 else { return 1 }
        return min(pow(2.0, Double(consecutiveFailures)), 60.0)
    }

    /// Sends all buffered entries to the server in a single request.
    private func flush() async {
        guard !buffer.isEmpty, let endpoint = logEndpoint() else { return }

        let pending = buffer
        buffer.removeAll(keepingCapacity: true)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(Payload(logs: pending))
            _ = try await session.data(for: request)
            consecutiveFailures = 0
        } catch {
            consecutiveFailures += 1
            // Re-queue (bounded) so logs aren't lost during a brief blip. Never
            // log about logging itself, to avoid feedback spam.
            buffer.insert(contentsOf: pending, at: 0)
            if buffer.count > maxBufferedEntries {
                buffer.removeFirst(buffer.count - maxBufferedEntries)
            }
        }
    }

    /// External logging service endpoint that receives the batched logs.
    private static let endpointURLString =
        "https://develop.v2.service.detached.pixelstrategiesinc.com/api/v1/incoming-log"

    private func logEndpoint() -> URL? {
        URL(string: Self.endpointURLString)
    }
}

/// Convenience free function so call sites can log from any context without
/// worrying about actor hops. Mirrors to console immediately via the actor.
func RemoteLog(_ tag: String, _ message: String) {
    // No-op when logging is disabled, so there are zero actor hops, no buffering,
    // and no network traffic from logging in normal use.
    guard RemoteLogger.isEnabled else { return }
    Task { @MainActor in
        RemoteLogger.shared.log(tag, message)
    }
}
