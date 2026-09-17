# Stop Before Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every switch to another video — on one headset or a whole group — fully stops the previous one (immersive view closed, window back) before the next one is started, driven by a real signal from the headset instead of a fixed delay.

**Architecture:** The headset sends one extra `status` (`stopped`, `immersiveMode: false`) once its immersive view has actually closed. The controller gets `DeviceManager.stopAndWait(deviceIds:)`: send `stop` to busy headsets, wait for that status (event-driven, 6 s safety net), then continue. `playSelected` uses it instead of its 1.2 s sleep; `SyncSessionManager.playOnAll` gets a new `stopping` phase before clock sync. The two busy/done rules live in a pure `StopGate` enum tested with the existing swiftc harness.

**Tech Stack:** Swift 5, SwiftUI; `iOSController/iOSController.xcodeproj` (VPC Remote, iOS 17+) and `VisionProPlayer/VisionProPlayer.xcodeproj` (VPC Player, visionOS). Pure logic tested by `iOSController/Tests/run.sh`; everything else on the simulators.

Spec: `docs/superpowers/specs/2026-09-17-stop-before-switch-design.md`.

## Global Constraints

- **Busy** = `playbackState` is `playing`, `paused` or `loading`, **or** `immersiveMode == true`.
- **Fully stopped** = `playbackState` is `stopped` or `idle` **and** `immersiveMode == false`; a disconnect also counts as done.
- Timeout **6 s** per headset, waited in parallel; on timeout log a warning and continue.
- Idle headsets get no `stop` and no wait.
- Log lines, verbatim: `⏹ Stopping <device> before the next video` · `✅ <device> fully stopped (1.8 s)` · `⚠️ <device> did not confirm the stop within 6 s — continuing`.
- Panel label while stopping: `Stopping current videos…`; badge `STOPPING`.
- Commit messages: imperative, `[app]` / `[docs]` prefix, end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Branch `fix/stop-before-switch` off `main`.
- Task order matters: Tasks 1–3 (controller) are verified against the **current** headset build, which never sends the post-close status — that is the timeout path. Task 4 adds the headset status and verifies the fast path.

## Simulator setup (used by Tasks 2–5)

```bash
S=/private/tmp/claude-501/-Volumes-DEV-MAC-opt-qoo-vision-pro/35ef4e05-3abd-475b-ada2-9f879686d656/scratchpad
IPAD=4225D516-E21E-44B1-91DE-1EDB95A196C7    # iPad Air 11-inch (M3), iOS 26
AVP=258F4903-3335-4BD3-AB9A-6F0666D98E10     # Apple Vision Pro, visionOS 26.1
xcrun simctl boot $IPAD 2>/dev/null; xcrun simctl boot $AVP 2>/dev/null; open -a Simulator
```

Build + install the controller (the headset is rebuilt only in Task 4):

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro
xcodebuild -project iOSController/iOSController.xcodeproj -scheme iOSController -destination "id=$IPAD" -derivedDataPath $S/dd-ios build -quiet 2>&1 | grep -E "error:"; echo "ios build done"
pkill -f "simctl launch --console-pty $IPAD" 2>/dev/null; xcrun simctl terminate $IPAD com.qoostudio.vpc 2>/dev/null
xcrun simctl install $IPAD "$S/dd-ios/Build/Products/Debug-iphonesimulator/VPC Remote.app"
nohup xcrun simctl launch --console-pty $IPAD com.qoostudio.vpc > $S/remote.log 2>&1 &
```

Headset with console captured (once per session; it reconnects by itself when the controller restarts):

```bash
xcrun simctl install $AVP "$S/dd-avp/Build/Products/Debug-xrsimulator/VPC Player.app"
nohup xcrun simctl launch --console-pty $AVP com.qoostudio.player > $S/player.log 2>&1 &
```

Keep `BigBuckBunny.MP4` and the `HoW_…` master moved aside during UI tests so the card layout matches these coordinates (`V="$(xcrun simctl get_app_container $AVP com.qoostudio.player data)/Documents/Videos"; mv "$V/BigBuckBunny.MP4" "$V/HoW_IMMERSIVE_HERO_V7_VisionPro_12288x3072.mov" $S/aside/`); restore them at the end.

Tap points (820×1180 point space). Unscrolled page, card collapsed: **Start** (50,54), card **chevron** (376,732). Card expanded, unscrolled: tiles at y≈856 (E736 x=196, Lobby Tour x=308, SyncTest x≈420 after a leftward swipe of the tile row), **Play/Play This** (117,1056); sync list **Lobby Tour** row (400,467), **Play on All** (90,642). After a video starts the card grows; swipe up ~550 pt and screenshot before tapping again — then **Pause/Play This** (117,1080), **Stop** (300,1080). Always screenshot before tapping by coordinate.

---

### Task 1: `StopGate` — the busy / fully-stopped rules, with tests

**Files:**
- Create: `iOSController/iOSController/StopGate.swift`
- Create: `iOSController/Tests/StopGate/main.swift`
- Modify: `iOSController/Tests/run.sh`
- Modify: `iOSController/iOSController.xcodeproj/project.pbxproj` (ids `AA1000AA` / `AA0000AA`)

**Interfaces:**
- Consumes: `PlaybackState` (`iOSController/iOSController/Models.swift`: `idle, loading, playing, paused, stopped, error, unknown`).
- Produces:
  ```swift
  enum StopGate {
      static func isBusy(state: PlaybackState, immersive: Bool) -> Bool
      static func isFullyStopped(state: PlaybackState, immersive: Bool) -> Bool
  }
  ```

- [ ] **Step 1: Create the branch**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && git switch -c fix/stop-before-switch main
```

- [ ] **Step 2: Write the failing tests**

Create `iOSController/Tests/StopGate/main.swift`. `Models.swift` cannot be compiled standalone (it references the Network-backed `ClientConnection`), so the harness declares the same `PlaybackState` cases itself:

```swift
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
```

Replace `iOSController/Tests/run.sh` with:

```bash
#!/bin/bash
# Compiles the pure-logic sources with plain-Swift harnesses and runs them.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${TMPDIR:-/tmp}/vpc-remote-tests"
mkdir -p "$OUT"
swiftc -O -o "$OUT/scrubber" "$DIR/../iOSController/ScrubberModel.swift" "$DIR/ScrubberModel/main.swift"
"$OUT/scrubber"
swiftc -O -o "$OUT/stopgate" "$DIR/../iOSController/StopGate.swift" "$DIR/StopGate/main.swift"
"$OUT/stopgate"
```

- [ ] **Step 3: Run the tests to confirm they fail**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && iOSController/Tests/run.sh
```

Expected: `ScrubberModel: all tests passed`, then `error: error opening input file '.../StopGate.swift'`.

- [ ] **Step 4: Write the rules**

Create `iOSController/iOSController/StopGate.swift`:

```swift
import Foundation

/// The two rules behind "stop the previous video fully before the next one".
///
/// Pure so `Tests/run.sh` can exercise them. See
/// docs/superpowers/specs/2026-09-17-stop-before-switch-design.md.
enum StopGate {
    /// A headset that still has something loaded, or still has its immersive
    /// view open, must be stopped before it is told to play something else.
    static func isBusy(state: PlaybackState, immersive: Bool) -> Bool {
        switch state {
        case .playing, .paused, .loading: return true
        default: return immersive
        }
    }

    /// Stopped only counts once the immersive view is closed too. The headset
    /// reports `stopped` before it starts closing the view, and a `play` that
    /// lands during that teardown is exactly the race being removed.
    static func isFullyStopped(state: PlaybackState, immersive: Bool) -> Bool {
        (state == .stopped || state == .idle) && !immersive
    }
}
```

- [ ] **Step 5: Run the tests to confirm they pass**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && iOSController/Tests/run.sh
```

Expected: both `ScrubberModel: all tests passed` and `StopGate: all tests passed`.

- [ ] **Step 6: Register the file in the Xcode project**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && python3 - <<'EOF'
p='iOSController/iOSController.xcodeproj/project.pbxproj'; s=open(p).read()
def after(anchor, new):
    global s
    assert s.count(anchor)==1, anchor
    s=s.replace(anchor, anchor+new)
after('\t\tAA0000A9 /* PlaybackScrubber.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA1000A9 /* PlaybackScrubber.swift */; };\n',
      '\t\tAA0000AA /* StopGate.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA1000AA /* StopGate.swift */; };\n')
after('\t\tAA1000A9 /* PlaybackScrubber.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PlaybackScrubber.swift; sourceTree = "<group>"; };\n',
      '\t\tAA1000AA /* StopGate.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StopGate.swift; sourceTree = "<group>"; };\n')
after('\t\t\t\tAA1000A9 /* PlaybackScrubber.swift */,\n',
      '\t\t\t\tAA1000AA /* StopGate.swift */,\n')
after('\t\t\t\tAA0000A9 /* PlaybackScrubber.swift in Sources */,\n',
      '\t\t\t\tAA0000AA /* StopGate.swift in Sources */,\n')
open(p,'w').write(s)
EOF
grep -c "StopGate.swift" iOSController/iOSController.xcodeproj/project.pbxproj   # expect 4
```

- [ ] **Step 7: Build the controller**

Run the controller build line from the simulator setup. Expected: no `error:` lines.

- [ ] **Step 8: Commit**

```bash
git add iOSController/iOSController/StopGate.swift iOSController/Tests iOSController/iOSController.xcodeproj/project.pbxproj
git commit -m "[app] Add the busy / fully-stopped rules for switching videos

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Controller — `stopAndWait`, used by Play This

**Files:**
- Modify: `iOSController/iOSController/DeviceManager.swift` — new section after `func stop(deviceId:)`; `playSelected`; the `onStatusUpdate` handler; the `onDeviceDisconnected` handler

**Interfaces:**
- Consumes: `StopGate` (Task 1); existing `stop(deviceId:)`, `play(deviceId:videoUrl:format:)`, `deviceName(for:)`, `log(_:type:)`.
- Produces:
  ```swift
  @MainActor func stopAndWait(deviceIds: [String], timeout: TimeInterval = 6) async
  ```

- [ ] **Step 1: Add the wait machinery**

In `DeviceManager.swift`, directly after `func stop(deviceId: String)` (the method ending with `log("Stop command sent to ...")`), add:

```swift
    // MARK: - Stop before switch

    private enum StopOutcome { case confirmed, disconnected, timedOut }

    /// Pending "fully stopped" waits, keyed by device id. Each continuation is
    /// resumed exactly once, through `resolveStopWait`.
    private var stopWaiters: [String: CheckedContinuation<StopOutcome, Never>] = [:]

    /// Sends `stop` to every busy headset in `deviceIds` and waits until each
    /// has reported stopped with its immersive view closed, or `timeout` has
    /// passed. See docs/superpowers/specs/2026-09-17-stop-before-switch-design.md.
    ///
    /// The headset reports `stopped` before it starts closing the immersive
    /// view, so the wait is for the status it sends *after* the view is closed
    /// (`immersiveMode: false`). Older headset builds never send that one; the
    /// timeout keeps them usable.
    @MainActor
    func stopAndWait(deviceIds: [String], timeout: TimeInterval = 6) async {
        let busy = deviceIds.filter { id in
            guard let device = devices.first(where: { $0.deviceId == id }) else { return false }
            return StopGate.isBusy(state: device.state.playbackState, immersive: device.state.immersiveMode)
        }
        guard !busy.isEmpty else { return }

        for id in busy {
            log("⏹ Stopping \(deviceName(for: id)) before the next video", type: .info)
            stop(deviceId: id)
        }

        await withTaskGroup(of: Void.self) { group in
            for id in busy {
                group.addTask { @MainActor in
                    await self.waitForFullStop(deviceId: id, timeout: timeout)
                }
            }
        }
    }

    @MainActor
    private func waitForFullStop(deviceId: String, timeout: TimeInterval) async {
        let started = Date()
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<StopOutcome, Never>) in
            stopWaiters[deviceId] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.resolveStopWait(deviceId: deviceId, outcome: .timedOut)
            }
        }

        let name = deviceName(for: deviceId)
        switch outcome {
        case .confirmed:
            let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
            log("✅ \(name) fully stopped (\(seconds) s)", type: .success)
        case .disconnected:
            log("⏹ \(name) disconnected while stopping — continuing", type: .warning)
        case .timedOut:
            log("⚠️ \(name) did not confirm the stop within \(Int(timeout)) s — continuing", type: .warning)
        }
    }

    /// Resumes a pending stop wait exactly once; later calls for the same
    /// device are no-ops, which is what makes the timeout race safe.
    @MainActor
    private func resolveStopWait(deviceId: String, outcome: StopOutcome) {
        guard let continuation = stopWaiters.removeValue(forKey: deviceId) else { return }
        continuation.resume(returning: outcome)
    }
```

- [ ] **Step 2: Resolve the wait from the status and disconnect handlers**

In the `onStatusUpdate` handler, directly after the line `self.syncManager.noteDevicePosition(deviceId, mediaTime: device.state.currentTime)` and the duration block that follows it (i.e. after the `if let reported = message.duration { ... }` block), add:

```swift
                if StopGate.isFullyStopped(state: device.state.playbackState, immersive: device.state.immersiveMode) {
                    self.resolveStopWait(deviceId: deviceId, outcome: .confirmed)
                }
```

In the `onDeviceDisconnected` handler, directly before `// Keep any active sync session consistent`, add:

```swift
                // A headset that is gone cannot confirm anything; do not hold
                // the switch for it.
                self.resolveStopWait(deviceId: deviceId, outcome: .disconnected)
```

- [ ] **Step 3: Use it in `playSelected`**

Replace the whole `playSelected` method with:

```swift
    /// Smart play that guarantees a clean start.
    ///
    /// The Vision Pro cannot reliably switch directly from one playing video to
    /// another — it must be fully stopped first, which also tears down and
    /// reopens the immersive space. This sends `stop`, waits for the headset to
    /// confirm the view is closed (`stopAndWait`), and only then sends `play`.
    /// An idle headset plays immediately.
    func playSelected(deviceId: String, videoUrl: String, format: VideoFormat) {
        guard !videoUrl.isEmpty else { return }
        guard let device = devices.first(where: { $0.deviceId == deviceId }) else { return }

        guard StopGate.isBusy(state: device.state.playbackState, immersive: device.state.immersiveMode) else {
            play(deviceId: deviceId, videoUrl: videoUrl, format: format)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.stopAndWait(deviceIds: [deviceId])
            self.play(deviceId: deviceId, videoUrl: videoUrl, format: format)
        }
    }
```

(The old optimistic `device.state.playbackState = .stopped` is gone on purpose: the real `stopped` status arrives within a frame on the LAN, and setting it early would have made `stopAndWait` see a non-busy device.)

- [ ] **Step 4: Build, install, launch (controller only)**

Run the controller build + install + launch lines from the simulator setup, then tap **Start**. The headset should still be the previous build — confirm it prints nothing after closing the view:

```bash
grep -c "immersiveMode\":false" $S/player.log   # any value; just noting the baseline
```

- [ ] **Step 5: Verify the timeout path — switch while playing**

Expand the card, select **Lobby Tour**, tap **Play**, wait 9 s. Select **E736…** (tile x=196), tap **Play This**. Wait 8 s, then:

```bash
grep -a "⏹\|✅\|⚠️\|Play command sent" $S/remote.log | tail -4
grep -n "Stopping\|Immersive space closed\|PLAY COMMAND" $S/player.log | tail -4
```

Expected controller lines, in order: `⏹ Stopping Lobby Headset before the next video` → (about 6 s later) `⚠️ Lobby Headset did not confirm the stop within 6 s — continuing` → `Play command sent to Lobby Headset`. Expected headset lines: `Stopping` → `Immersive space closed` → `PLAY COMMAND`. The E736 clip then plays (card shows Playing, then Stopped when it ends). This is the current headset build, so the timeout is the expected path here.

- [ ] **Step 6: Verify the idle path**

With the headset Stopped, select **Lobby Tour** and tap **Play**. Expected: no `⏹` line in the controller log for this play; `Play command sent` immediately; video plays. Tap **Stop**.

- [ ] **Step 7: Commit**

```bash
git add iOSController/iOSController/DeviceManager.swift
git commit -m "[app] Wait for a headset to fully stop before playing the next video

Play This used to send stop, sleep 1.2 s and send play; the headset
reports stopped before it starts closing the immersive view, so on a
large file the play could land mid-teardown. The controller now waits
for a status with the view closed, with a 6 s safety net for headset
builds that never send one.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Controller — a `stopping` phase before Play on All

**Files:**
- Modify: `iOSController/iOSController/SyncSessionManager.swift` (`SessionState`, new hook, `playOnAll`)
- Modify: `iOSController/iOSController/DeviceManager.swift` (wiring in `setupSyncManager`)
- Modify: `iOSController/iOSController/SyncControlPanel.swift` (label, badge, Stop All visibility)

**Interfaces:**
- Consumes: `DeviceManager.stopAndWait(deviceIds:)` (Task 2).
- Produces: `SyncSessionManager.SessionState.stopping`; `var stopBusyDevices: (([String]) async -> Void)?`.

- [ ] **Step 1: Session state and hook**

In `SyncSessionManager.swift`, change the enum to:

```swift
    enum SessionState: Equatable {
        case idle
        case stopping
        case syncingClocks
        case preparing
        case playing
        case paused
    }
```

After `var setDeviceFormat: ((String, VideoFormat) -> Void)?`, add:

```swift
    /// Fully stops whatever the devices are doing before a session starts —
    /// wired by DeviceManager to `stopAndWait`. A headset that swaps files
    /// inside an open immersive view is the switch that misbehaves.
    var stopBusyDevices: (([String]) async -> Void)?
```

- [ ] **Step 2: The phase in `playOnAll`**

In `playOnAll`, directly before the line `// Phase 1: clock sync`, add:

```swift
        // Phase 0: full stop on every target. Idle devices cost nothing here.
        state = .stopping
        await stopBusyDevices?(deviceIds)
```

- [ ] **Step 3: Wire it in DeviceManager**

In `DeviceManager.swift`, after the `syncManager.setDeviceCurrentTime = { ... }` block, add:

```swift
        syncManager.stopBusyDevices = { [weak self] deviceIds in
            await self?.stopAndWait(deviceIds: deviceIds)
        }
```

- [ ] **Step 4: Show the phase in the panel**

In `SyncControlPanel.swift`, change

```swift
                    case .syncingClocks, .preparing:
                        ProgressView()
                            .controlSize(.small)
                        Text(syncManager.state == .syncingClocks ? "Syncing clocks…" : "Preparing devices…")
```

to

```swift
                    case .stopping, .syncingClocks, .preparing:
                        ProgressView()
                            .controlSize(.small)
                        Text(phaseLabel)
```

and add this computed property next to `isSessionActive`:

```swift
    private var phaseLabel: String {
        switch syncManager.state {
        case .stopping: return "Stopping current videos…"
        case .syncingClocks: return "Syncing clocks…"
        default: return "Preparing devices…"
        }
    }
```

Change the Stop All condition

```swift
                    if isSessionActive && syncManager.state != .syncingClocks {
```

to

```swift
                    if isSessionActive && syncManager.state != .syncingClocks && syncManager.state != .stopping {
```

(Stop All during the stopping phase would end the session while `playOnAll` is still about to continue into clock sync.)

In `stateBadge`, add after `case .idle: EmptyView()`:

```swift
            case .stopping:
                badge("STOPPING", color: .orange)
```

- [ ] **Step 5: Build, install, launch (controller only)**

Run the controller build + install + launch lines, tap **Start**, wait for the headset to reconnect (~9 s).

- [ ] **Step 6: Verify Play on All while a headset is playing individually (timeout path)**

Expand the card, select **Lobby Tour**, **Play**, wait 9 s. Scroll back to the top, select **Lobby Tour** in the sync list (400,467), tap **Play on All** (90,642). Screenshot within 2 s: expected badge **STOPPING** and text `Stopping current videos…`. Wait 20 s, then:

```bash
grep -a "⏹\|⚠️\|Measuring clock\|Sync start scheduled" $S/remote.log | tail -4
```

Expected, in order: `⏹ Stopping Lobby Headset before the next video` → `⚠️ … did not confirm the stop within 6 s — continuing` → `🕐 Measuring clock offsets…` → `🚀 Sync start scheduled`. Session PLAYING. Tap **Stop All**.

- [ ] **Step 7: Verify Play on All from idle**

With the headset Stopped/Idle, tap **Play on All** again. Expected: no `⏹` line; `Measuring clock offsets` at once; session PLAYING within ~3 s. Tap **Stop All**.

- [ ] **Step 8: Commit**

```bash
git add iOSController/iOSController/SyncSessionManager.swift iOSController/iOSController/DeviceManager.swift iOSController/iOSController/SyncControlPanel.swift
git commit -m "[app] Fully stop every headset before a Play on All session

syncPrepare used to be sent straight away, so a headset already playing
swapped files inside its open immersive view — the switch that
misbehaves. A stopping phase now runs stopAndWait on every target first.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Headset — report "fully stopped" after the view closes

**Files:**
- Modify: `VisionProPlayer/VisionProPlayer/VisionProPlayerApp.swift` — the `.stop, .syncStop` case in `handleCommand`; the `onPlaybackEnded` closure in `setupCommandHandling`

**Interfaces:**
- Consumes: `WebSocketManager.sendStatus(state:currentVideo:immersiveMode:currentTime:duration:)` (exists).
- Produces: one extra `status` message with `"state":"stopped","immersiveMode":false` after every immersive-space dismissal.

- [ ] **Step 1: The stop command path**

In `handleCommand`, change

```swift
        case .stop, .syncStop:
            videoManager.stop()

            // Close immersive space and restore main window
            if appState.isImmersiveActive {
                await dismissImmersiveSpace()
                appState.isImmersiveActive = false
                print("[App] Immersive space closed")

                // Reopen the main window
                openWindow(id: "main")
                print("[App] Main window reopened")
            }
        }
```

to

```swift
        case .stop, .syncStop:
            videoManager.stop()

            // Close immersive space and restore main window
            if appState.isImmersiveActive {
                await dismissImmersiveSpace()
                appState.isImmersiveActive = false
                print("[App] Immersive space closed")

                // Reopen the main window
                openWindow(id: "main")
                print("[App] Main window reopened")

                // Only now is the headset fully stopped. The status stop() sent
                // went out while the view was still open; the controller waits
                // for this one before it starts the next video.
                webSocketManager.sendStatus(
                    state: PlaybackState.stopped.rawValue,
                    currentVideo: appState.currentVideoURL,
                    immersiveMode: false,
                    currentTime: 0,
                    duration: nil
                )
            }
        }
```

- [ ] **Step 2: The playback-ended path**

In the `nativeVideoManager.onPlaybackEnded` closure, change

```swift
                if state.isImmersiveActive {
                    await self.dismissImmersiveSpace()
                    state.isImmersiveActive = false
                    print("[App] Immersive space closed after playback end")

                    self.openWindow(id: "main")
                    print("[App] Main window reopened after playback end")
                }
```

to

```swift
                if state.isImmersiveActive {
                    await self.dismissImmersiveSpace()
                    state.isImmersiveActive = false
                    print("[App] Immersive space closed after playback end")

                    self.openWindow(id: "main")
                    print("[App] Main window reopened after playback end")

                    // Same "fully stopped" report as an explicit Stop, so a
                    // switch right after a video ended does not wait in vain.
                    wsManager.sendStatus(
                        state: PlaybackState.stopped.rawValue,
                        currentVideo: state.currentVideoURL,
                        immersiveMode: false,
                        currentTime: 0,
                        duration: nil
                    )
                }
```

- [ ] **Step 3: Build and install the headset**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && S=/private/tmp/claude-501/-Volumes-DEV-MAC-opt-qoo-vision-pro/35ef4e05-3abd-475b-ada2-9f879686d656/scratchpad; AVP=258F4903-3335-4BD3-AB9A-6F0666D98E10
xcodebuild -project VisionProPlayer/VisionProPlayer.xcodeproj -scheme VisionProPlayer -destination "id=$AVP" -derivedDataPath $S/dd-avp build -quiet 2>&1 | grep -E "error:"; echo "avp build done"
pkill -f "simctl launch --console-pty $AVP" 2>/dev/null; xcrun simctl terminate $AVP com.qoostudio.player 2>/dev/null
xcrun simctl install $AVP "$S/dd-avp/Build/Products/Debug-xrsimulator/VPC Player.app"
nohup xcrun simctl launch --console-pty $AVP com.qoostudio.player > $S/player.log 2>&1 &
sleep 8; grep -c "Registered:" $S/player.log   # expect 1
```

Expected: no `error:` lines; headset registers with the running controller.

- [ ] **Step 4: Verify the fast path — single switch**

Expand the card, **Lobby Tour** → **Play**, wait 9 s. Select **E736…**, **Play This**. Wait 5 s:

```bash
grep -a "⏹\|✅\|⚠️\|Play command sent" $S/remote.log | tail -3
grep -n '"immersiveMode":false' $S/player.log | tail -1 | cut -c1-120
```

Expected: `⏹ Stopping Lobby Headset before the next video` → `✅ Lobby Headset fully stopped (x.x s)` with x well under 6 → `Play command sent`; and a headset `Sending message: {...,"state":"stopped",...,"immersiveMode":false,...}` line. The clip plays.

- [ ] **Step 5: Verify the fast path — group**

After the clip ends (card Stopped): **Lobby Tour** → **Play**, wait 9 s; then sync list **Lobby Tour** → **Play on All**. Wait 15 s:

```bash
grep -a "⏹\|✅\|Measuring clock\|Sync start scheduled" $S/remote.log | tail -4
```

Expected: `⏹ Stopping …` → `✅ … fully stopped (x.x s)` → `🕐 Measuring clock offsets…` → `🚀 Sync start scheduled`; session PLAYING. Tap **Stop All**.

- [ ] **Step 6: Verify a switch right after a video ended on its own**

Select **E736…** → **Play**; wait 13 s so it ends by itself (card Stopped). Immediately select **Lobby Tour** → **Play**. Expected: no `⏹` line (the headset reported fully stopped when the clip ended, so it is idle); plays at once.

- [ ] **Step 7: Commit**

```bash
git add VisionProPlayer/VisionProPlayer/VisionProPlayerApp.swift
git commit -m "[app] Report fully stopped once the immersive view has closed

The status sent by stop() goes out while the view is still open. The
controller now waits for this one before starting the next video.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Docs, regression, push

**Files:**
- Create: `docs/bugs/2026-09-17-switch-while-playing.md`
- Modify: `CLAUDE.md` (changelog top)
- Modify: `docs/guide/build.py` (section 10), rebuild `docs/guide/Vision-Pro-Operator-Guide.pdf` + `.html`

- [ ] **Step 1: Bug log**

Create `docs/bugs/2026-09-17-switch-while-playing.md`:

```markdown
# Switching to another video while one is playing sometimes misbehaves

- **Date**: 2026-09-17
- **Reported by**: field use
- **Severity**: High — intermittent, and Play on All had no protection at all
- **Branch**: `fix/stop-before-switch`
- **Status**: Fixed, verified on simulator

## Symptom

Selecting another video and tapping Play This while one is playing sometimes
goes wrong; stopping first and then playing the next one by hand is always
fine. Play on All while a headset is playing individually had the same
exposure.

## Root cause

- The controller's Play This did stop → sleep 1.2 s → play. The headset
  reports `stopped` *before* it begins closing the immersive view and sends
  nothing once the view is closed, so 1.2 s was a guess; a large file's
  teardown can outlast it and `play` lands mid-teardown.
- Play on All sent `syncPrepare` straight away; a busy headset swapped files
  inside its open immersive view — no stop, no teardown.

## Fix

- Headset: one extra `status` (`stopped`, `immersiveMode: false`) after the
  immersive view has closed — on a Stop command and when a video ends.
- Controller: `DeviceManager.stopAndWait` sends `stop` to busy headsets and
  waits for that status (6 s safety net, disconnect counts as done).
  `playSelected` uses it instead of the sleep; `playOnAll` gets a `stopping`
  phase before clock sync. Rules in `StopGate`, tested by `Tests/run.sh`.

## Verification

iOS 26 iPad + visionOS 26.1 simulators, both consoles captured.

| Case | Result |
| --- | --- |
| Play This while playing, headset without the new status | ⏹ → ⚠️ after 6 s → play; video plays |
| Play This while playing, updated headset | ⏹ → ✅ fully stopped (< 2 s) → play |
| Play on All while a headset plays individually | ⏹ → ✅ → clock sync → scheduled start |
| Play on All / Play This from idle | No stop, no delay |
| Switch right after a video ended by itself | Treated as idle; plays at once |

Not verified on hardware; the teardown timing is the thing a device pass
should watch (the ✅ line prints how long it took).

## Spec

`docs/superpowers/specs/2026-09-17-stop-before-switch-design.md`
```

- [ ] **Step 2: Changelog**

In `CLAUDE.md`, insert at the top of `## Changelog`, above `### 2026-09-17 (Update 2)`:

```markdown
### 2026-09-17 (Update 3)
- **[Fix]** Switching to another video while one is playing sometimes misbehaved; Play on All had no protection at all
  - **Bug log**: `docs/bugs/2026-09-17-switch-while-playing.md` · **Spec**: `docs/superpowers/specs/2026-09-17-stop-before-switch-design.md` · branch `fix/stop-before-switch`
  - The headset reported `stopped` *before* closing its immersive view and nothing after, so the controller's 1.2 s sleep before `play` was a guess. The headset now sends a `status` with `immersiveMode: false` once the view has closed (on Stop and when a video ends). The controller's new `DeviceManager.stopAndWait` sends `stop` to busy headsets and waits for that status (6 s safety net); `playSelected` uses it, and `playOnAll` runs it as a new `stopping` phase before clock sync. Rules in `StopGate`, tested by `iOSController/Tests/run.sh`.
  - Verified on the iOS 26 + visionOS 26.1 simulators, including the timeout path against a headset build without the new status. **Needs a device pass** — the ✅ line prints the real teardown time.
```

- [ ] **Step 3: Operator guide**

In `docs/guide/build.py`, directly before the line `{{FIG:paused}}`, add:

```html
<div class="note"><b>Switching straight to another video</b>Selecting a different video and tapping <b>Play This</b> while one is playing stops the current one <i>completely</i> first — the wearer sees the app window for a moment — and only then starts the next. <b>Play on All</b> does the same on every headset before it prepares them. This is deliberate: swapping files inside the open immersive view is what used to misbehave, so the controller now waits for each headset to confirm it has closed the view (the Activity Log shows "fully stopped" and how long it took).</div>

```

Rebuild:

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && ./docs/guide/build.sh | tail -1
```

- [ ] **Step 4: Regression**

Both apps are the final builds from Tasks 3 and 4. Run:

| Case | Expect |
| --- | --- |
| Play → Pause → Resume → Stop | unchanged |
| Card scrubber drag while playing | seek lands, thumb holds then follows |
| Preview first-play (E736 clip, then Lobby Tour) | preview shown at once, no length warning |
| Play on All → Pause All → Resume All → Stop All | unchanged |

```bash
iOSController/Tests/run.sh   # both harnesses pass
```

- [ ] **Step 5: Commit, restore the simulator, push**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro
git add docs/bugs/2026-09-17-switch-while-playing.md CLAUDE.md docs/guide/build.py docs/guide/vision-pro-operator-guide.html docs/guide/Vision-Pro-Operator-Guide.pdf
git commit -m "[docs] Record the stop-before-switch fix

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
V="$(xcrun simctl get_app_container $AVP com.qoostudio.player data)/Documents/Videos"
mv $S/aside/BigBuckBunny.MP4 $S/aside/HoW_IMMERSIVE_HERO_V7_VisionPro_12288x3072.mov "$V/" 2>/dev/null; ls "$V"
git push -u origin fix/stop-before-switch
```
