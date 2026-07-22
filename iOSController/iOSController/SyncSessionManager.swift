import Foundation
import Combine

/// Orchestrates synchronized playback across all connected Vision Pro devices.
///
/// Flow (see docs/adr/2026-07-22-synchronized-multi-device-playback.md):
/// 1. Measure each device's clock offset (NTP-style over the WebSocket).
/// 2. Send syncPrepare to all targets; wait at a readiness barrier.
/// 3. Broadcast syncStart with a per-device offset-adjusted wall-clock time.
/// Pause is immediate; resume re-uses the scheduled-start mechanism.
@MainActor
class SyncSessionManager: ObservableObject {
    /// Session lifecycle states
    enum SessionState: Equatable {
        case idle
        case syncingClocks
        case preparing
        case playing
        case paused
    }

    /// Per-device status within a session
    enum DeviceSyncStatus: Equatable {
        case measuringClock
        case preparing
        case ready
        case failed(String)
        case playing
        case paused
        case ended
    }

    @Published var state: SessionState = .idle
    @Published var deviceStatus: [String: DeviceSyncStatus] = [:]
    @Published var currentFilename: String?
    @Published var currentFormat: VideoFormat = .sphere360SBS

    /// Measured clock offsets: deviceClock − controllerClock, in ms
    private var clockOffsets: [String: Int64] = [:]

    /// Clock samples collected during measurement: deviceId → [(rtt, offset)]
    private var clockSamples: [String: [(rtt: Int64, offset: Int64)]] = [:]

    /// Devices that reported ready in the current prepare phase
    private var readyDevices: Set<String> = []

    /// Device IDs participating in the active session
    private(set) var sessionDevices: [String] = []

    /// Prepare + preroll of multi-GB videos can take well over 30s
    /// (asset load + readiness wait), so the barrier must be generous.
    private let readyBarrierTimeout: TimeInterval = 60.0
    private let startLeadTimeMs: Int64 = 1000

    /// Wiring provided by DeviceManager
    var sendToDevice: ((String, any Encodable) -> Void)?
    var deviceCurrentTime: ((String) -> Double?)?
    var log: ((String, LogType) -> Void)?

    private var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    // MARK: - Inbound messages (wired from WebSocketServer via DeviceManager)

    func handleClockSyncResponse(deviceId: String, response: ClockSyncResponse) {
        let t2 = nowMs
        let rtt = t2 - response.t0
        let offset = response.t1 - (response.t0 + t2) / 2
        clockSamples[deviceId, default: []].append((rtt: rtt, offset: offset))
    }

    func handleSyncReady(deviceId: String, message: SyncReadyMessage) {
        guard state == .preparing else { return }

        if message.success {
            readyDevices.insert(deviceId)
            deviceStatus[deviceId] = .ready
            log?("✅ Ready for sync: \(deviceId)", .success)
        } else {
            deviceStatus[deviceId] = .failed(message.message ?? "Prepare failed")
            log?("❌ Sync prepare failed on \(deviceId): \(message.message ?? "unknown")", .error)
        }
    }

    func handleDeviceDisconnected(deviceId: String) {
        guard state != .idle else { return }
        sessionDevices.removeAll { $0 == deviceId }
        readyDevices.remove(deviceId)
        deviceStatus[deviceId] = .failed("Disconnected")
    }

    /// Called for every status update a device sends. When every session
    /// device reports stopped (e.g. the video played to its natural end),
    /// the session is over — return the panel to idle.
    func handleDeviceStatus(deviceId: String, state deviceState: PlaybackState) {
        guard state == .playing || state == .paused else { return }
        guard sessionDevices.contains(deviceId) else { return }

        if deviceState == .stopped || deviceState == .idle {
            deviceStatus[deviceId] = .ended
            let stillActive = sessionDevices.contains { id in
                id != deviceId && deviceStatus[id] != .ended
            }
            if !stillActive {
                log?("🏁 Playback ended on all devices — sync session finished", .info)
                endSession()
            }
        }
    }

    // MARK: - Session control

    /// Runs the full sync-play sequence: clock sync → prepare barrier → scheduled start.
    func playOnAll(filename: String, format: VideoFormat, deviceIds: [String]) async {
        guard state == .idle || state == .paused else {
            log?("Sync session already active", .warning)
            return
        }
        guard !deviceIds.isEmpty else { return }

        sessionDevices = deviceIds
        currentFilename = filename
        currentFormat = format
        deviceStatus = [:]
        readyDevices = []

        // Phase 1: clock sync
        state = .syncingClocks
        log?("🕐 Measuring clock offsets for \(deviceIds.count) device(s)...", .info)
        await measureClockOffsets(deviceIds: deviceIds)

        // Phase 2: prepare barrier
        state = .preparing
        log?("🎬 Preparing '\(filename)' on all devices...", .info)
        for deviceId in deviceIds {
            deviceStatus[deviceId] = .preparing
            sendToDevice?(deviceId, SyncPrepareCommand(filename: filename, videoFormat: format))
        }

        let allReady = await waitForReadyBarrier()
        let participants = Array(readyDevices)

        guard !participants.isEmpty else {
            // Devices may be sitting in a prepared immersive space —
            // tell them to exit before giving up.
            let stopCommand = CommandMessage(action: .syncStop)
            for deviceId in sessionDevices {
                sendToDevice?(deviceId, stopCommand)
            }
            log?("❌ No devices became ready — sync session aborted", .error)
            endSession()
            return
        }

        if !allReady {
            let missing = sessionDevices.filter { !readyDevices.contains($0) }
            let stopCommand = CommandMessage(action: .syncStop)
            for deviceId in missing {
                if deviceStatus[deviceId] == .preparing {
                    deviceStatus[deviceId] = .failed("Ready timeout")
                }
                // Excluded device may still finish preparing later — make it
                // exit the immersive space instead of being stuck there.
                sendToDevice?(deviceId, stopCommand)
            }
            log?("⚠️ Starting with \(participants.count)/\(sessionDevices.count) devices (others timed out)", .warning)
        }

        // Phase 3: scheduled start
        sessionDevices = participants
        scheduleStart(mediaTime: nil)
    }

    /// Pause playback on all session devices immediately.
    func pauseAll() {
        guard state == .playing else { return }
        let command = CommandMessage(action: .syncPause)
        for deviceId in sessionDevices {
            sendToDevice?(deviceId, command)
            deviceStatus[deviceId] = .paused
        }
        state = .paused
        log?("⏸️ Sync pause sent to \(sessionDevices.count) device(s)", .info)
    }

    /// Resume all session devices at the same media time and wall-clock moment.
    func resumeAll() {
        guard state == .paused else { return }

        // Use the furthest-ahead device as the common resume point; devices
        // paused within a few ms of each other so the values are near-equal.
        let mediaTime = sessionDevices
            .compactMap { deviceCurrentTime?($0) }
            .max() ?? 0

        scheduleStart(mediaTime: mediaTime)
        log?("▶️ Sync resume at \(String(format: "%.2f", mediaTime))s", .info)
    }

    /// Stop playback on all session devices and end the session.
    func stopAll() {
        guard state != .idle else { return }
        let command = CommandMessage(action: .syncStop)
        for deviceId in sessionDevices {
            sendToDevice?(deviceId, command)
        }
        log?("⏹️ Sync stop sent to \(sessionDevices.count) device(s)", .info)
        endSession()
    }

    // MARK: - Internals

    /// Sends `syncStart` (mediaTime == nil) or `syncResume` to every session
    /// device with a per-device offset-adjusted start time.
    private func scheduleStart(mediaTime: Double?) {
        let startAtController = nowMs + startLeadTimeMs

        for deviceId in sessionDevices {
            // deviceClock = controllerClock + offset
            let startAtDevice = startAtController + (clockOffsets[deviceId] ?? 0)
            if let mediaTime {
                sendToDevice?(deviceId, SyncResumeCommand(mediaTime: mediaTime, startAt: startAtDevice))
            } else {
                sendToDevice?(deviceId, SyncStartCommand(startAt: startAtDevice))
            }
            deviceStatus[deviceId] = .playing
        }

        state = .playing
        log?("🚀 Sync \(mediaTime == nil ? "start" : "resume") scheduled (+\(startLeadTimeMs)ms) for \(sessionDevices.count) device(s)", .success)
    }

    /// Measures clock offsets with several samples per device, keeping the
    /// sample with the lowest RTT (most accurate midpoint estimate).
    private func measureClockOffsets(deviceIds: [String]) async {
        clockSamples = [:]
        for deviceId in deviceIds {
            deviceStatus[deviceId] = .measuringClock
        }

        let sampleCount = 5
        for _ in 0..<sampleCount {
            let request = ClockSyncMessage(t0: nowMs)
            for deviceId in deviceIds {
                sendToDevice?(deviceId, request)
            }
            try? await Task.sleep(nanoseconds: 150_000_000) // 150 ms between samples
        }

        // Grace period for the last responses
        try? await Task.sleep(nanoseconds: 300_000_000)

        for deviceId in deviceIds {
            let samples = clockSamples[deviceId] ?? []
            if let best = samples.min(by: { $0.rtt < $1.rtt }) {
                clockOffsets[deviceId] = best.offset
                log?("🕐 \(deviceId): offset \(best.offset)ms (rtt \(best.rtt)ms, \(samples.count) samples)", .info)
            } else {
                // No response — keep any previous offset, else assume 0
                if clockOffsets[deviceId] == nil { clockOffsets[deviceId] = 0 }
                log?("⚠️ No clock sync response from \(deviceId) — using offset \(clockOffsets[deviceId] ?? 0)ms", .warning)
            }
        }
    }

    /// Waits until every session device reported ready/failed, or the barrier
    /// times out. Returns true when all devices are ready.
    private func waitForReadyBarrier() async -> Bool {
        let deadline = Date().addingTimeInterval(readyBarrierTimeout)

        while Date() < deadline {
            let pending = sessionDevices.filter { deviceStatus[$0] == .preparing }
            if pending.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return readyDevices.count == sessionDevices.count
    }

    private func endSession() {
        state = .idle
        sessionDevices = []
        readyDevices = []
        deviceStatus = [:]
        currentFilename = nil
    }
}
