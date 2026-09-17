import Foundation

// Mirror of PlaybackState in iOSController/Models.swift — Models.swift pulls in
// Network types and cannot be compiled by this harness. Keep the cases in sync.
enum PlaybackState: String { case idle, loading, playing, paused, stopped, error, unknown }

var failures = 0
func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition { failures += 1; print("FAIL (line \(line)): \(message)") }
}

// Busy: anything loaded, or the immersive view still open
for s in [PlaybackState.playing, .paused, .loading] {
    expect(StopGate.isBusy(state: s, immersive: true), "\(s) + immersive is busy")
    expect(StopGate.isBusy(state: s, immersive: false), "\(s) without immersive is still busy")
}
expect(StopGate.isBusy(state: .stopped, immersive: true), "stopped but immersive view open is busy")
expect(StopGate.isBusy(state: .idle, immersive: true), "idle but immersive view open is busy")
for s in [PlaybackState.idle, .stopped, .error, .unknown] {
    expect(!StopGate.isBusy(state: s, immersive: false), "\(s) with view closed is not busy")
}

// Fully stopped: stopped/idle AND the view closed
expect(StopGate.isFullyStopped(state: .stopped, immersive: false), "stopped + closed is fully stopped")
expect(StopGate.isFullyStopped(state: .idle, immersive: false), "idle + closed is fully stopped")
expect(!StopGate.isFullyStopped(state: .stopped, immersive: true), "stopped with view open is not fully stopped")
expect(!StopGate.isFullyStopped(state: .playing, immersive: false), "playing is not fully stopped")
expect(!StopGate.isFullyStopped(state: .loading, immersive: false), "loading is not fully stopped")
expect(!StopGate.isFullyStopped(state: .error, immersive: false), "error is not fully stopped")

if failures == 0 { print("StopGate: all tests passed") } else { print("StopGate: \(failures) failure(s)"); exit(1) }
