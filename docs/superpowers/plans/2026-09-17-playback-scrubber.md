# Playback Scrubber Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the operator jump to any point in the video from the controller — one headset from its card, every headset in a Play on All session from the Synchronized Playback panel, in sync.

**Architecture:** One new WebSocket command, `seek { mediaTime }`, handled by the headset without changing playback state. The controller gets a reusable `PlaybackScrubber` view driven by a pure-Swift `ScrubberModel` (drag / hold-after-release logic, testable without SwiftUI). Group seek is `syncPause` + the existing `syncResume { mediaTime, startAt }` scheduled restart — no new headset path.

**Tech Stack:** Swift 5, SwiftUI, AVFoundation; Xcode projects `iOSController/iOSController.xcodeproj` (VPC Remote, iOS 17+) and `VisionProPlayer/VisionProPlayer.xcodeproj` (VPC Player, visionOS). No XCTest targets exist; pure logic is tested with a `swiftc` harness, everything else on the simulators.

Spec: `docs/superpowers/specs/2026-09-17-playback-scrubber-design.md`.

## Global Constraints

- Seek on release only — never send a command while the finger is down.
- The scrubber is shown whenever the headset has a video loaded (`playing`, `paused`, `loading`), paired preview or not.
- Bar disabled with `--:--` while `duration` is nil.
- Hold-after-release: keep the thumb at the target until a live position is within **1.0 s** of it or **2.0 s** elapse.
- Group seek while playing: `syncPause` → `syncResume { mediaTime, startAt }` with the existing **1000 ms** lead; panel scrubber disabled for that lead time.
- Group seek while paused: individual `seek` per active device; stored `currentTime` set to the target; session stays `paused`.
- A headset in an active group session has its card scrubber disabled with hint `Use the Synchronized Playback bar`.
- Log lines: card `⏩ Seek <device> → m:ss`; group `⏩ Group seek → m:ss (N devices)`.
- Commit messages: imperative, `[app]` / `[docs]` prefix, end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Work on branch `feature/playback-scrubber` off `main`.

## Simulator setup (used by several tasks)

```bash
S=/private/tmp/claude-501/-Volumes-DEV-MAC-opt-qoo-vision-pro/35ef4e05-3abd-475b-ada2-9f879686d656/scratchpad
IPAD=4225D516-E21E-44B1-91DE-1EDB95A196C7    # iPad Air 11-inch (M3), iOS 26
AVP=258F4903-3335-4BD3-AB9A-6F0666D98E10     # Apple Vision Pro, visionOS 26.1
xcrun simctl boot $IPAD 2>/dev/null; xcrun simctl boot $AVP 2>/dev/null; open -a Simulator
```

Build + install both:

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro
xcodebuild -project iOSController/iOSController.xcodeproj -scheme iOSController -destination "id=$IPAD" -derivedDataPath $S/dd-ios build -quiet 2>&1 | grep -E "error:" ; echo "ios ${PIPESTATUS[0]}"
xcodebuild -project VisionProPlayer/VisionProPlayer.xcodeproj -scheme VisionProPlayer -destination "id=$AVP" -derivedDataPath $S/dd-avp build -quiet 2>&1 | grep -E "error:" ; echo "avp ${PIPESTATUS[0]}"
xcrun simctl terminate $IPAD com.qoostudio.vpc; xcrun simctl terminate $AVP com.qoostudio.player
xcrun simctl install $IPAD "$S/dd-ios/Build/Products/Debug-iphonesimulator/VPC Remote.app"
xcrun simctl install $AVP "$S/dd-avp/Build/Products/Debug-xrsimulator/VPC Player.app"
xcrun simctl launch $IPAD com.qoostudio.vpc
```

Then tap **Start** on the controller (top-left, ~(50,54) in the 820×1180 point space), and launch the headset with its console captured:

```bash
nohup xcrun simctl launch --console-pty $AVP com.qoostudio.player > $S/player.log 2>&1 &
sleep 8; grep -c "Registered:" $S/player.log   # expect 1
```

Test videos on the headset simulator: `Lobby_Tour.mp4` (4:12, paired with companion `Lobby_Tour.mov`), `E736F8EA-….mp4` (0:10), `SyncTest.mp4` (5:00), `1140_SCOPE….mp4` (0:02). Keep `BigBuckBunny.MP4` and the `HoW_…` master moved aside during UI tests so the card layout matches the coordinates below (`mv "$V/BigBuckBunny.MP4" "$V/HoW_IMMERSIVE_HERO_V7_VisionPro_12288x3072.mov" $S/aside/`, where `V="$(xcrun simctl get_app_container $AVP com.qoostudio.player data)/Documents/Videos"`); restore them when done.

Known tap points with 4 videos, page scrolled so the card is visible: card chevron (376,732) unscrolled; after expanding and swiping up ~550 pt: tiles at y≈820 (E736 x=196, Lobby Tour x=308), Play/Pause at (117,1080), Stop at (300,1080); sync list row "Lobby Tour" at (400,430), Play on All / Pause All / Resume All at (90,605), Stop All at (200,605). Always take a screenshot before tapping by coordinate — the layout shifts when the video list changes.

---

### Task 1: Headset — handle a `seek` command

**Files:**
- Modify: `VisionProPlayer/VisionProPlayer/Models/Models.swift:40-53` (enum) and after line 85 (new struct)
- Modify: `VisionProPlayer/VisionProPlayer/Managers/WebSocketManager.swift:30` (callback) and `:341-349` (dispatch)
- Modify: `VisionProPlayer/VisionProPlayer/Managers/NativeVideoPlayerManager.swift:411-417` (add method next to `seek(to progress:)`)
- Modify: `VisionProPlayer/VisionProPlayer/VisionProPlayerApp.swift:311` (new callback wiring) and `:413-415` (switch exhaustiveness)

**Interfaces:**
- Consumes: nothing new.
- Produces: wire message `{ "type":"command", "action":"seek", "mediaTime": Double, "timestamp": Int }` accepted by the headset; `NativeVideoPlayerManager.seek(toMediaTime: Double) async -> Bool`; a `status` message sent after every successful seek.

- [ ] **Step 1: Create the branch**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && git switch -c feature/playback-scrubber main
```

- [ ] **Step 2: Add the action and the command struct to the headset model**

In `Models.swift`, add a case to `CommandAction` (after `case syncStop`):

```swift
    case seek          // Jump to an absolute media time; playback state unchanged
```

After the `SyncResumeCommand` struct (ends line 85), add:

```swift
/// Jump to an absolute media time on the operator's behalf. Sent to one
/// headset; a group seek arrives as syncPause + syncResume instead.
struct SeekCommand: Codable {
    let type: String
    let action: String
    let mediaTime: Double
    let timestamp: Int?
}
```

- [ ] **Step 3: Dispatch it in WebSocketManager**

After line 30 (`var onSyncResumeCommand: ...`) add:

```swift
    var onSeekCommand: ((SeekCommand) -> Void)?
```

In the `case "command":` chain, insert a branch before the final `} else {` (the one that decodes `ServerCommand`):

```swift
                } else if let actionStr = json?["action"] as? String, actionStr == "seek" {
                    let seekCommand = try JSONDecoder().decode(SeekCommand.self, from: data)
                    print("[WebSocket] Seek to media time: \(seekCommand.mediaTime)")
                    onSeekCommand?(seekCommand)
```

- [ ] **Step 4: Add the player method**

In `NativeVideoPlayerManager.swift`, directly after `func seek(to progress: Double)` (ends line 417), add:

```swift
    /// Seeks to an absolute media time on the operator's behalf.
    ///
    /// Playback state is left exactly as it is: a playing video keeps playing
    /// from the new position, a paused one shows the new frame. The requested
    /// time is clamped to the asset, so a slider that disagrees with the
    /// headset by a frame cannot push past the end. Returns false when there is
    /// nothing loaded to seek.
    func seek(toMediaTime requested: Double) async -> Bool {
        guard let player = player, duration > 0 else {
            print("[NativeVideoPlayer] Cannot seek - no video loaded")
            return false
        }
        let mediaTime = min(max(requested, 0), duration)
        print("[NativeVideoPlayer] Seek to \(mediaTime)s")
        let target = CMTime(seconds: mediaTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        // The periodic observer only fires while playing; a paused seek must
        // still update the reported position.
        updateProgress(time: target)
        return true
    }
```

- [ ] **Step 5: Wire the handler in the app and keep the switch exhaustive**

In `VisionProPlayerApp.swift`, directly before the line `webSocketManager.onSyncResumeCommand = { resumeCommand in` (line 311), add:

```swift
        // Handle seek: jump and report the new position without a state change
        webSocketManager.onSeekCommand = { seekCommand in
            Task { @MainActor in
                guard await vidManager.seek(toMediaTime: seekCommand.mediaTime) else { return }
                // No state changed, so nothing else would send a status — but
                // the controller needs the new position to release its thumb.
                wsManager.sendStatus(
                    state: vidManager.playbackState.rawValue,
                    currentVideo: state.currentVideoURL,
                    immersiveMode: state.isImmersiveActive,
                    currentTime: vidManager.currentTime,
                    duration: vidManager.duration
                )
            }
        }

```

In `handleCommand`, change the line

```swift
        case .syncPrepare, .syncStart, .syncResume:
```

to

```swift
        case .syncPrepare, .syncStart, .syncResume, .seek:
```

- [ ] **Step 6: Build the headset for the simulator**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && xcodebuild -project VisionProPlayer/VisionProPlayer.xcodeproj -scheme VisionProPlayer -destination "id=258F4903-3335-4BD3-AB9A-6F0666D98E10" -derivedDataPath /private/tmp/claude-501/-Volumes-DEV-MAC-opt-qoo-vision-pro/35ef4e05-3abd-475b-ada2-9f879686d656/scratchpad/dd-avp build -quiet 2>&1 | grep -E "error:|BUILD"
```

Expected: no `error:` lines.

- [ ] **Step 7: Regression check on the headset**

Nothing can send `seek` yet (the controller only relays its own commands), so the end-to-end check of this task happens in Task 2 Step 4. Here, install and launch both apps per the simulator setup, start the controller server, expand the card and play `Lobby Tour`; tap Pause, Resume, Stop. Expected: the headset log shows `Starting playback`, `Pausing`, `Resuming`, `Stopping` as before, and `grep -c "Seek" $S/player.log` prints `0`.

- [ ] **Step 8: Commit**

```bash
git add VisionProPlayer/VisionProPlayer/Models/Models.swift VisionProPlayer/VisionProPlayer/Managers/WebSocketManager.swift VisionProPlayer/VisionProPlayer/Managers/NativeVideoPlayerManager.swift VisionProPlayer/VisionProPlayer/VisionProPlayerApp.swift
git commit -m "[app] Accept a seek command on the headset

Jumps to an absolute media time without touching playback state and
reports the new position, so the controller can drive a scrubber.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Controller — send `seek` to one headset

**Files:**
- Modify: `iOSController/iOSController/Models.swift:206-219` (enum) and after `SyncStartCommand` (~line 262)
- Modify: `iOSController/iOSController/DeviceManager.swift:167` (after `func stop(deviceId:)`)

**Interfaces:**
- Consumes: headset `seek` handling from Task 1; `webSocketServer.send(to:message:)` (exists, used for `PreviewSubscribeCommand`); `formatPosition(_:)` from `CompanionPairing.swift`.
- Produces: `SeekCommand(mediaTime:)`; `DeviceManager.seek(deviceId: String, to mediaTime: Double)`.

- [ ] **Step 1: Add the action and struct**

In `Models.swift`, add to `CommandAction` after `case syncStop`:

```swift
    case seek         // Jump one headset to an absolute media time
```

After the `SyncStartCommand` struct, add:

```swift
/// Jump one headset to an absolute media time. Playback state is unchanged on
/// the headset; a group seek never uses this while playing (see
/// SyncSessionManager.seekAll).
struct SeekCommand: Codable {
    var type: String = "command"
    var action: String = CommandAction.seek.rawValue
    let mediaTime: Double
    let timestamp: Int

    init(mediaTime: Double) {
        self.mediaTime = mediaTime
        self.timestamp = Int(Date().timeIntervalSince1970 * 1000)
    }
}
```

- [ ] **Step 2: Add the sender**

In `DeviceManager.swift`, after `func stop(deviceId: String)` (ends ~line 167), add:

```swift
    /// Jump one headset to an absolute media time. The headset keeps whatever
    /// state it is in, so this is safe while playing or paused.
    func seek(deviceId: String, to mediaTime: Double) {
        webSocketServer.send(to: deviceId, message: SeekCommand(mediaTime: mediaTime))
        log("⏩ Seek \(deviceName(for: deviceId)) → \(formatPosition(mediaTime))", type: .info)
    }
```

- [ ] **Step 3: Build the controller**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && xcodebuild -project iOSController/iOSController.xcodeproj -scheme iOSController -destination "id=4225D516-E21E-44B1-91DE-1EDB95A196C7" -derivedDataPath /private/tmp/claude-501/-Volumes-DEV-MAC-opt-qoo-vision-pro/35ef4e05-3abd-475b-ada2-9f879686d656/scratchpad/dd-ios build -quiet 2>&1 | grep -E "error:|BUILD"
```

Expected: no `error:` lines.

- [ ] **Step 4: Temporary end-to-end probe**

There is no UI yet. Add a *temporary* probe to `PlaybackControlsView` in `DeviceCardView.swift`: in the `case (.playing, true):` branch's Pause button action, before `deviceManager.pause(deviceId: device.deviceId)`, insert `deviceManager.seek(deviceId: device.deviceId, to: 120)`. Build, install both apps, play `Lobby Tour`, tap **Pause** once.

Expected in `$S/player.log`:

```
[WebSocket] Seek to media time: 120.0
[NativeVideoPlayer] Seek to 120.0s
[NativeVideoPlayer] Pausing
```

and in the controller's Activity Log: `⏩ Seek Lobby Headset → 2:00`. The preview (if the card shows it) jumps to 2:00.

- [ ] **Step 5: Remove the probe and confirm it is gone**

```bash
git diff -- iOSController/iOSController/DeviceCardView.swift   # expect empty output
```

- [ ] **Step 6: Commit**

```bash
git add iOSController/iOSController/Models.swift iOSController/iOSController/DeviceManager.swift
git commit -m "[app] Send a seek command to one headset

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Controller — `ScrubberModel`, the drag / hold logic, with tests

**Files:**
- Create: `iOSController/iOSController/ScrubberModel.swift`
- Create: `iOSController/Tests/ScrubberModel/main.swift`
- Create: `iOSController/Tests/run.sh`
- Modify: `iOSController/iOSController.xcodeproj/project.pbxproj` (register the new source)

**Interfaces:**
- Consumes: nothing.
- Produces:
  ```swift
  struct ScrubberModel {
      static let holdTolerance: Double   // 1.0
      static let holdTimeout: TimeInterval   // 2.0
      static func clamp(_ time: Double, duration: Double) -> Double
      var isDragging: Bool { get }
      mutating func beginDrag(at time: Double, duration: Double)
      mutating func drag(to time: Double, duration: Double)
      mutating func endDrag(now: Date) -> Double?      // target to send, nil if not dragging
      mutating func observe(live: Double, now: Date)    // releases an expired/confirmed hold
      func displayPosition(live: Double) -> Double
  }
  ```

- [ ] **Step 1: Write the failing tests**

Create `iOSController/Tests/ScrubberModel/main.swift`:

```swift
import Foundation

// Minimal harness: no XCTest target exists in this project, and adding one
// to the pbxproj by hand is not worth it for pure logic. Run with Tests/run.sh.
var failures = 0
func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition { failures += 1; print("FAIL (line \(line)): \(message)") }
}
func expectEqual(_ a: Double, _ b: Double, _ message: String, line: Int = #line) {
    expect(abs(a - b) < 0.0001, "\(message) — got \(a), expected \(b)", line: line)
}

let t0 = Date(timeIntervalSince1970: 1_000)

// clamp
expectEqual(ScrubberModel.clamp(-5, duration: 252), 0, "negative clamps to 0")
expectEqual(ScrubberModel.clamp(300, duration: 252), 252, "past end clamps to duration")
expectEqual(ScrubberModel.clamp(42.5, duration: 252), 42.5, "in range unchanged")
expectEqual(ScrubberModel.clamp(42.5, duration: 0), 0, "no duration → 0")

// following: display is the live position
var m = ScrubberModel()
expect(!m.isDragging, "starts not dragging")
expectEqual(m.displayPosition(live: 10), 10, "follows live")

// dragging: display is the drag target, clamped
m.beginDrag(at: 10, duration: 252)
expect(m.isDragging, "dragging after beginDrag")
m.drag(to: 120, duration: 252)
expectEqual(m.displayPosition(live: 11), 120, "shows target while dragging")
m.drag(to: 999, duration: 252)
expectEqual(m.displayPosition(live: 11), 252, "drag target clamped")

// endDrag returns the target once, then holds
m.drag(to: 120, duration: 252)
let sent = m.endDrag(now: t0)
expect(sent == 120, "endDrag returns target")
expect(!m.isDragging, "not dragging after endDrag")
expect(m.endDrag(now: t0) == nil, "second endDrag returns nil")
expectEqual(m.displayPosition(live: 11), 120, "holds at target after release")

// a stale live position within 2 s does not release the hold
m.observe(live: 11, now: t0.addingTimeInterval(0.5))
expectEqual(m.displayPosition(live: 11), 120, "still holding on stale position")

// a live position within tolerance releases the hold
m.observe(live: 120.6, now: t0.addingTimeInterval(0.8))
expectEqual(m.displayPosition(live: 120.6), 120.6, "released by confirming position")

// timeout releases the hold even with no confirming position
var m2 = ScrubberModel()
m2.beginDrag(at: 0, duration: 252)
m2.drag(to: 200, duration: 252)
_ = m2.endDrag(now: t0)
m2.observe(live: 5, now: t0.addingTimeInterval(1.9))
expectEqual(m2.displayPosition(live: 5), 200, "holding before timeout")
m2.observe(live: 5, now: t0.addingTimeInterval(2.0))
expectEqual(m2.displayPosition(live: 5), 5, "released at timeout")

// endDrag without a drag is a no-op
var m3 = ScrubberModel()
expect(m3.endDrag(now: t0) == nil, "endDrag while following returns nil")

if failures == 0 { print("ScrubberModel: all tests passed") } else { print("ScrubberModel: \(failures) failure(s)"); exit(1) }
```

Create `iOSController/Tests/run.sh`:

```bash
#!/bin/bash
# Compiles the pure-logic sources with a plain-Swift harness and runs them.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${TMPDIR:-/tmp}/vpc-remote-tests"
mkdir -p "$OUT"
swiftc -O -o "$OUT/scrubber" "$DIR/../iOSController/ScrubberModel.swift" "$DIR/ScrubberModel/main.swift"
"$OUT/scrubber"
```

```bash
chmod +x iOSController/Tests/run.sh
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && iOSController/Tests/run.sh
```

Expected: `error: no such file or directory: '.../ScrubberModel.swift'` (compilation fails because the model does not exist yet).

- [ ] **Step 3: Write the model**

Create `iOSController/iOSController/ScrubberModel.swift`:

```swift
import Foundation

/// The drag and hold-after-release logic behind `PlaybackScrubber`.
///
/// Kept free of SwiftUI so it can be exercised by `Tests/run.sh` with plain
/// swiftc. The view owns one of these and feeds it the live position; this
/// decides what the thumb should show.
///
/// Three phases:
/// - `following`: the thumb tracks the headset's live position.
/// - `dragging`: the thumb tracks the finger; nothing is sent.
/// - `holding`: the finger lifted and the seek was sent, but the headset has
///   not caught up yet. The thumb stays at the target so it does not snap
///   back to the stale position for the half-second before the seek lands.
struct ScrubberModel: Equatable {
    enum Phase: Equatable {
        case following
        case dragging(target: Double)
        case holding(target: Double, since: Date)
    }

    /// A live position this close to the target counts as "the seek landed".
    static let holdTolerance: Double = 1.0
    /// A hold never outlives this, even if no confirming position arrives.
    static let holdTimeout: TimeInterval = 2.0

    private(set) var phase: Phase = .following

    var isDragging: Bool {
        if case .dragging = phase { return true }
        return false
    }

    static func clamp(_ time: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(max(time, 0), duration)
    }

    mutating func beginDrag(at time: Double, duration: Double) {
        phase = .dragging(target: Self.clamp(time, duration: duration))
    }

    mutating func drag(to time: Double, duration: Double) {
        phase = .dragging(target: Self.clamp(time, duration: duration))
    }

    /// Ends the drag. Returns the time to send to the headset, or nil when no
    /// drag was in progress.
    mutating func endDrag(now: Date) -> Double? {
        guard case .dragging(let target) = phase else { return nil }
        phase = .holding(target: target, since: now)
        return target
    }

    /// Feed the newest live position. Releases the hold once the headset has
    /// caught up, or once the hold has outlived its timeout.
    mutating func observe(live: Double, now: Date) {
        guard case .holding(let target, let since) = phase else { return }
        if abs(live - target) <= Self.holdTolerance || now.timeIntervalSince(since) >= Self.holdTimeout {
            phase = .following
        }
    }

    /// The position the thumb should show for this live position.
    func displayPosition(live: Double) -> Double {
        switch phase {
        case .following: return live
        case .dragging(let target), .holding(let target, _): return target
        }
    }
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && iOSController/Tests/run.sh
```

Expected: `ScrubberModel: all tests passed`

- [ ] **Step 5: Register the file in the Xcode project**

The project uses explicit file references (objectVersion 56). Add the new source with ids `AA1000A8` / `AA0000A8`, next to `ViewerDirectionIndicator.swift` in all four places:

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && python3 - <<'EOF'
p='iOSController/iOSController.xcodeproj/project.pbxproj'; s=open(p).read()
def after(anchor, new):
    global s
    assert s.count(anchor)==1, anchor
    s=s.replace(anchor, anchor+new)
after('\t\tAA0000A7 /* ViewerDirectionIndicator.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA1000A7 /* ViewerDirectionIndicator.swift */; };\n',
      '\t\tAA0000A8 /* ScrubberModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA1000A8 /* ScrubberModel.swift */; };\n')
after('\t\tAA1000A7 /* ViewerDirectionIndicator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ViewerDirectionIndicator.swift; sourceTree = "<group>"; };\n',
      '\t\tAA1000A8 /* ScrubberModel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ScrubberModel.swift; sourceTree = "<group>"; };\n')
after('\t\t\t\tAA1000A7 /* ViewerDirectionIndicator.swift */,\n',
      '\t\t\t\tAA1000A8 /* ScrubberModel.swift */,\n')
after('\t\t\t\tAA0000A7 /* ViewerDirectionIndicator.swift in Sources */,\n',
      '\t\t\t\tAA0000A8 /* ScrubberModel.swift in Sources */,\n')
open(p,'w').write(s)
EOF
grep -c "ScrubberModel.swift" iOSController/iOSController.xcodeproj/project.pbxproj   # expect 4
```

- [ ] **Step 6: Build the controller**

Run the controller build command from Task 2 Step 3. Expected: no `error:` lines.

- [ ] **Step 7: Commit**

```bash
git add iOSController/iOSController/ScrubberModel.swift iOSController/Tests iOSController/iOSController.xcodeproj/project.pbxproj
git commit -m "[app] Add the scrubber drag/hold model with a swiftc test harness

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Controller — `PlaybackScrubber` view

**Files:**
- Create: `iOSController/iOSController/PlaybackScrubber.swift`
- Modify: `iOSController/iOSController.xcodeproj/project.pbxproj` (ids `AA1000A9` / `AA0000A9`)

**Interfaces:**
- Consumes: `ScrubberModel` (Task 3); `formatPosition(_:)`, `formatDuration(_:)` (globals in `CompanionPairing.swift`).
- Produces:
  ```swift
  struct PlaybackScrubber: View {
      init(position: Double, duration: Double?, isEnabled: Bool = true, hint: String? = nil, onSeek: @escaping (Double) -> Void)
  }
  ```

- [ ] **Step 1: Write the view**

Create `iOSController/iOSController/PlaybackScrubber.swift`:

```swift
import SwiftUI

/// A seek bar for a headset (or a whole group). Shows the live position while
/// idle, the finger's target while dragging, and sends exactly one seek when
/// the finger lifts. See `ScrubberModel` for the hold-after-release rule.
struct PlaybackScrubber: View {
    let position: Double
    /// Nil while the headset has not reported a running time — the bar is then
    /// disabled and shows dashes rather than guessing.
    let duration: Double?
    var isEnabled: Bool = true
    /// Shown under the bar when it is disabled, to say why.
    var hint: String? = nil
    let onSeek: (Double) -> Void

    @State private var model = ScrubberModel()
    /// The finger's position while dragging. Kept apart from `model` so the
    /// Slider binding never reads a value that is one render behind.
    @State private var dragValue: Double = 0

    private var shown: Double {
        model.isDragging ? dragValue : model.displayPosition(live: position)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let duration, duration > 0 {
                Slider(
                    value: Binding(
                        get: { shown },
                        set: { value in
                            dragValue = value
                            model.drag(to: value, duration: duration)
                        }
                    ),
                    in: 0...duration
                ) { editing in
                    if editing {
                        dragValue = shown
                        model.beginDrag(at: shown, duration: duration)
                    } else if let target = model.endDrag(now: Date()) {
                        onSeek(target)
                    }
                }
                .disabled(!isEnabled)
                .accessibilityLabel("Playback position")
                .accessibilityValue(formatPosition(shown))

                HStack {
                    Text(formatPosition(shown))
                    Spacer()
                    Text(formatDuration(duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                Slider(value: .constant(0), in: 0...1)
                    .disabled(true)
                    .accessibilityLabel("Playback position, running time not known yet")
                HStack {
                    Text("--:--")
                    Spacer()
                    Text("--:--")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if let hint, !isEnabled {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: position) { _, live in
            model.observe(live: live, now: Date())
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        PlaybackScrubber(position: 53, duration: 252) { _ in }
        PlaybackScrubber(position: 0, duration: nil) { _ in }
        PlaybackScrubber(position: 90, duration: 252, isEnabled: false, hint: "Use the Synchronized Playback bar") { _ in }
    }
    .padding()
}
```

- [ ] **Step 2: Register the file in the Xcode project**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && python3 - <<'EOF'
p='iOSController/iOSController.xcodeproj/project.pbxproj'; s=open(p).read()
def after(anchor, new):
    global s
    assert s.count(anchor)==1, anchor
    s=s.replace(anchor, anchor+new)
after('\t\tAA0000A8 /* ScrubberModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA1000A8 /* ScrubberModel.swift */; };\n',
      '\t\tAA0000A9 /* PlaybackScrubber.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA1000A9 /* PlaybackScrubber.swift */; };\n')
after('\t\tAA1000A8 /* ScrubberModel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ScrubberModel.swift; sourceTree = "<group>"; };\n',
      '\t\tAA1000A9 /* PlaybackScrubber.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PlaybackScrubber.swift; sourceTree = "<group>"; };\n')
after('\t\t\t\tAA1000A8 /* ScrubberModel.swift */,\n',
      '\t\t\t\tAA1000A9 /* PlaybackScrubber.swift */,\n')
after('\t\t\t\tAA0000A8 /* ScrubberModel.swift in Sources */,\n',
      '\t\t\t\tAA0000A9 /* PlaybackScrubber.swift in Sources */,\n')
open(p,'w').write(s)
EOF
grep -c "PlaybackScrubber.swift" iOSController/iOSController.xcodeproj/project.pbxproj   # expect 4
```

- [ ] **Step 3: Build the controller**

Run the controller build command from Task 2 Step 3. Expected: no `error:` lines.

- [ ] **Step 4: Commit**

```bash
git add iOSController/iOSController/PlaybackScrubber.swift iOSController/iOSController.xcodeproj/project.pbxproj
git commit -m "[app] Add the PlaybackScrubber view

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Controller — scrubber on the headset card

**Files:**
- Modify: `iOSController/iOSController/CompanionPreviewView.swift` (`body`, `content(for:)`, `unpairedNotice`, `start(_:)`, remove `timeBadge`)

**Interfaces:**
- Consumes: `PlaybackScrubber` (Task 4); `DeviceManager.seek(deviceId:to:)` (Task 2); `deviceManager.syncManager.state` / `.deviceStatus` (exist); `deviceManager.setPreviewSubscription(deviceId:enabled:)` (exists).
- Produces: the card behaviour described in the spec, Part 2.

- [ ] **Step 1: Add the group-session check and the scrubber piece**

In `CompanionPreviewView.swift`, after the `hasActiveVideo` computed property, add:

```swift
    /// True while this headset is an active member of a group session. Seeking
    /// one headset out of a running group would silently desync it, so the
    /// card's scrubber is read-only then and points at the group bar instead.
    private var isInActiveGroup: Bool {
        let sync = deviceManager.syncManager
        guard sync.state == .playing || sync.state == .paused else { return false }
        switch sync.deviceStatus[device.deviceId] {
        case .playing, .paused, .ready: return true
        default: return false
        }
    }

    private var scrubber: some View {
        PlaybackScrubber(
            position: position,
            duration: device.state.duration,
            isEnabled: !isInActiveGroup,
            hint: "Use the Synchronized Playback bar"
        ) { target in
            deviceManager.seek(deviceId: device.deviceId, to: target)
        }
    }
```

- [ ] **Step 2: Subscribe to the live position whenever a video is loaded**

Replace the `body`:

```swift
    var body: some View {
        Group {
            if let companion = pairedCompanion, hasActiveVideo {
                content(for: companion)
            } else if hasActiveVideo {
                unpairedNotice
            }
        }
        // The 10 Hz position feed used to be switched on only while a paired
        // preview was on screen. The scrubber needs it for every loaded video,
        // paired or not — and still nothing while the card shows no video.
        .onChange(of: hasActiveVideo, initial: true) { _, active in
            deviceManager.setPreviewSubscription(deviceId: device.deviceId, enabled: active)
        }
        .onDisappear {
            deviceManager.setPreviewSubscription(deviceId: device.deviceId, enabled: false)
            preview.teardown()
        }
    }
```

In `start(_:)`, delete the line `deviceManager.setPreviewSubscription(deviceId: device.deviceId, enabled: true)` (the subscription is now owned by `body`). The function becomes:

```swift
    private func start(_ companion: CompanionVideo) {
        verifyAndLoad(companion)
        tick()
    }
```

- [ ] **Step 3: Put the scrubber under the picture, replacing the corner badge**

In `content(for:)`, replace the block

```swift
                ZStack(alignment: .bottomLeading) {
                    PlayerLayerView(player: preview.player)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.primary.opacity(0.08))
                        }

                    timeBadge
                        .padding(8)
                }
```

with

```swift
                PlayerLayerView(player: preview.player)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.08))
                    }
```

and, directly after the `if let reason = preview.withheldReason { ... } else { ... }` block (still inside the `VStack`, before the direction indicator), add:

```swift
            scrubber
```

Delete the whole `private var timeBadge: some View { ... }` property — nothing uses it now.

- [ ] **Step 4: Put the scrubber under the unpaired notice**

Replace `unpairedNotice` with:

```swift
    private var unpairedNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .foregroundStyle(.secondary)
                Text("No preview video — long-press the tile above to pair one.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            scrubber
        }
        .padding(.vertical, 8)
    }
```

- [ ] **Step 5: Build and install both apps, then test the card**

Run the full build + install + launch sequence from the simulator setup. Expand the card, select `Lobby Tour`, tap Play, wait ~8 s, swipe up so the card is fully visible, screenshot.

Expected: under the preview picture a slider with `0:0x` on the left and `4:12` on the right, thumb moving. No badge inside the picture.

Drag the thumb: `left_click_drag` from the thumb's current point to about 45 % of the bar's width (the bar spans roughly x=35…385 in points at the card's width; note the y from the screenshot). Then wait 3 s, screenshot, and:

```bash
grep -n "Seek to" $S/player.log | tail -2
```

Expected: headset log `Seek to 1xx.xs`; Activity Log (list icon, top right) shows `⏩ Seek Lobby Headset → 1:5x`; the preview picture jumped; the thumb stayed near the drop point (did not snap back), and the label shows the new position.

- [ ] **Step 6: Test the paused and unpaired cases**

1. Tap **Pause**, drag the thumb elsewhere, wait 2 s, screenshot. Expected: still `Paused`; position label updated to the drop point (the headset reported it via the post-seek status); tap **Resume** → playback continues from there (label keeps rising from that value).
2. Tap **Stop**. Select `E736F8EA…` (no preview paired), tap **Play**. Expected: one-line "No preview video — long-press the tile above to pair one." with a working scrubber under it, label counting up to `0:10`.

- [ ] **Step 7: Test the group-session gating**

Select `Lobby Tour` in **VIDEOS ON ALL DEVICES**, tap **Play on All**, wait ~12 s, screenshot the card. Expected: card scrubber greyed out with the hint `Use the Synchronized Playback bar`; position still ticking. Tap **Stop All**.

- [ ] **Step 8: Commit**

```bash
git add iOSController/iOSController/CompanionPreviewView.swift
git commit -m "[app] Put a seek bar on the headset card

Shown for every loaded video, paired preview or not; disabled while the
headset is in a group session so a single seek cannot desync it.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Controller — group seek in Synchronized Playback

**Files:**
- Modify: `iOSController/iOSController/SyncSessionManager.swift` (published state, wiring hooks, `seekAll`, `endSession`)
- Modify: `iOSController/iOSController/DeviceManager.swift:47-56` (wiring) and the `onStatusUpdate` / `onViewerState` handlers
- Modify: `iOSController/iOSController/SyncControlPanel.swift` (scrubber between chips and buttons)

**Interfaces:**
- Consumes: `PlaybackScrubber` (Task 4); `SeekCommand` (Task 2); existing `scheduleStart(mediaTime:)`, `activeSessionDevices`, `CommandMessage(action: .syncPause)`.
- Produces:
  ```swift
  // SyncSessionManager
  var deviceDuration: ((String) -> Double?)?
  var setDeviceCurrentTime: ((String, Double) -> Void)?
  @Published private(set) var isRestartPending: Bool
  var groupPosition: Double { get }
  var groupDuration: Double? { get }
  func noteDevicePosition(_ deviceId: String, mediaTime: Double)
  func seekAll(to mediaTime: Double)
  ```

- [ ] **Step 1: Add state, hooks and `seekAll` to the session manager**

In `SyncSessionManager.swift`, after `@Published var currentFormat: VideoFormat = .sphere360SBS`, add:

```swift
    /// Newest known media position per session device, fed by DeviceManager
    /// from both status updates and the 10 Hz viewer feed. Published so the
    /// group scrubber re-renders as positions arrive.
    @Published private(set) var livePositions: [String: Double] = [:]

    /// True for the lead time after a group seek while playing: the devices
    /// are restarting on a schedule and a second seek must not overlap it.
    @Published private(set) var isRestartPending = false
```

After `var deviceCurrentTime: ((String) -> Double?)?`, add:

```swift
    /// Running time a device reported for the loaded file, if known.
    var deviceDuration: ((String) -> Double?)?
    /// Overwrites the stored position for a device — used after a seek while
    /// paused, so the next resume starts from the seek target.
    var setDeviceCurrentTime: ((String, Double) -> Void)?
```

After the `activeSessionDevices` property, add:

```swift
    /// The group's position: the furthest-ahead active device, the same rule
    /// `resumeAll` uses to pick a common resume point.
    var groupPosition: Double {
        activeSessionDevices.compactMap { livePositions[$0] }.max() ?? 0
    }

    /// The session file's running time, from whichever active device has
    /// reported it. Nil until one does.
    var groupDuration: Double? {
        activeSessionDevices.compactMap { deviceDuration?($0) }.max()
    }

    /// Records a device's newest position while a session is running.
    func noteDevicePosition(_ deviceId: String, mediaTime: Double) {
        guard state == .playing || state == .paused, sessionDevices.contains(deviceId) else { return }
        livePositions[deviceId] = mediaTime
    }
```

After `func resumeAll()`, add:

```swift
    /// Jump every active session device to the same media time.
    ///
    /// Playing: pause the group, then restart it at the new time on a shared
    /// clock tick — exactly `resumeAll` with the operator's time instead of the
    /// measured one, so the group stays in sync. Paused: seek each device in
    /// place and remember the target, so the next `resumeAll` starts there.
    func seekAll(to mediaTime: Double) {
        let targets = activeSessionDevices
        guard !targets.isEmpty else { return }

        switch state {
        case .playing:
            guard !isRestartPending else { return }
            let pause = CommandMessage(action: .syncPause)
            for deviceId in targets {
                sendToDevice?(deviceId, pause)
                setDeviceCurrentTime?(deviceId, mediaTime)
                livePositions[deviceId] = mediaTime
            }
            log?("⏩ Group seek → \(formatPosition(mediaTime)) (\(targets.count) devices)", .info)
            scheduleStart(mediaTime: mediaTime)

            isRestartPending = true
            let lead = UInt64(startLeadTimeMs) * 1_000_000
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: lead)
                self?.isRestartPending = false
            }

        case .paused:
            for deviceId in targets {
                sendToDevice?(deviceId, SeekCommand(mediaTime: mediaTime))
                setDeviceCurrentTime?(deviceId, mediaTime)
                livePositions[deviceId] = mediaTime
            }
            log?("⏩ Group seek → \(formatPosition(mediaTime)) (\(targets.count) devices, paused)", .info)

        default:
            return
        }
    }
```

In `endSession()`, add two lines so nothing leaks into the next session:

```swift
        livePositions = [:]
        isRestartPending = false
```

- [ ] **Step 2: Wire the hooks in DeviceManager**

In `DeviceManager.swift`, after the `syncManager.deviceCurrentTime = { ... }` block (ends line 52), add:

```swift
        syncManager.deviceDuration = { [weak self] deviceId in
            self?.devices.first(where: { $0.deviceId == deviceId })?.state.duration
        }
        syncManager.setDeviceCurrentTime = { [weak self] deviceId, mediaTime in
            self?.devices.first(where: { $0.deviceId == deviceId })?.state.currentTime = mediaTime
        }
```

In the `onStatusUpdate` handler, directly after `device.state.currentTime = message.currentTime ?? 0`, add:

```swift
                self.syncManager.noteDevicePosition(deviceId, mediaTime: device.state.currentTime)
```

In the `onViewerState` handler, directly after the `device.state.viewer = ViewerLook(...)` assignment, add:

```swift
                self.syncManager.noteDevicePosition(deviceId, mediaTime: message.mediaTime)
```

- [ ] **Step 3: Add the group scrubber to the panel**

In `SyncControlPanel.swift`, directly before the `// Group controls` comment that precedes `HStack(spacing: 10) { switch syncManager.state {`, add:

```swift
                // Group seek bar — the whole session's position, only while it runs
                if syncManager.state == .playing || syncManager.state == .paused {
                    PlaybackScrubber(
                        position: syncManager.groupPosition,
                        duration: syncManager.groupDuration,
                        isEnabled: !syncManager.isRestartPending,
                        hint: "Restarting the group…"
                    ) { target in
                        syncManager.seekAll(to: target)
                    }
                    .padding(.vertical, 4)
                }

```

- [ ] **Step 4: Build and install both apps**

Run the build + install + launch sequence from the simulator setup. Expected: no `error:` lines.

- [ ] **Step 5: Test group seek while playing**

Expand the card (so the 10 Hz feed is on), select `Lobby Tour` in **VIDEOS ON ALL DEVICES**, tap **Play on All**, wait ~12 s, screenshot. Expected: a scrubber between the `Lobby Headset` chip and the Pause All / Stop All row, thumb moving, `4:12` on the right.

Drag its thumb to about 35 % of the bar. Wait 3 s, then:

```bash
grep -n "Sync pause\|Sync resume at\|Sync start in\|Seek to" $S/player.log | tail -4
```

Expected, in this order: `[NativeVideoPlayer] Sync pause`, `[WebSocket] Sync resume at media time: 8x.x`, `[NativeVideoPlayer] Sync start in 0.99xs`. Activity Log: `⏩ Group seek → 1:2x (1 devices)` then `🚀 Sync resume scheduled (+1000ms) for 1 device(s)`. Session badge stays **PLAYING**; card preview jumped; the card's own scrubber is still disabled.

- [ ] **Step 6: Test group seek while paused, then Resume All**

Tap **Pause All**. Drag the group thumb to about 70 %. Wait 2 s:

```bash
grep -n "Seek to" $S/player.log | tail -1
```

Expected: `[NativeVideoPlayer] Seek to 17x.xs`, session still **PAUSED**, no `Sync resume` line yet. Tap **Resume All**:

```bash
grep -n "Sync resume at" $S/player.log | tail -1
```

Expected: `Sync resume at media time: 17x.x` — the seek target, not the old pause point. Tap **Stop All**.

- [ ] **Step 7: Commit**

```bash
git add iOSController/iOSController/SyncSessionManager.swift iOSController/iOSController/DeviceManager.swift iOSController/iOSController/SyncControlPanel.swift
git commit -m "[app] Seek a whole group from the Synchronized Playback panel

While playing this is a pause plus the existing scheduled resume at the
new time, so every headset restarts on the same tick. While paused each
device seeks in place and the stored position moves with it, so Resume
All starts from the seek target.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Docs — protocol, changelog, ADR, operator guide

**Files:**
- Modify: `CLAUDE.md` (Synchronized Playback Messages section; changelog top)
- Create: `docs/adr/2026-09-17-playback-scrubber.md`
- Modify: `docs/guide/build.py` (sections 10 and 11), then rebuild `docs/guide/Vision-Pro-Operator-Guide.pdf` and `docs/guide/vision-pro-operator-guide.html`

- [ ] **Step 1: Protocol line in CLAUDE.md**

In the `### Synchronized Playback Messages (2026-07-22)` JSON block, add after the `syncStop` line:

```json
{ "type": "command", "action": "seek", "mediaTime": 42.5 }
```

and after the block's closing paragraph add:

```markdown
`seek` moves one headset to an absolute media time without changing its playback state; the headset answers with a `status` carrying the new `currentTime`. A group seek is not a separate message: the controller sends `syncPause` then `syncResume` with the new `mediaTime` (playing), or a plain `seek` per device (paused).
```

- [ ] **Step 2: Changelog entry in CLAUDE.md**

Insert at the top of `## Changelog`, above `### 2026-09-17`:

```markdown
### 2026-09-17 (Update 2)
- **[Playback scrubber]** The operator can jump to any point in the video from the controller
  - **Spec**: `docs/superpowers/specs/2026-09-17-playback-scrubber-design.md` · **ADR**: `docs/adr/2026-09-17-playback-scrubber.md` · branch `feature/playback-scrubber`
  - **Protocol**: new `seek { mediaTime }` command (single headset, playback state unchanged, answered with a `status`). Group seek reuses `syncPause` + `syncResume { mediaTime, startAt }`, so the headset has no new scheduled path.
  - **iOS Controller**: `PlaybackScrubber` (seek on release; thumb holds at the target until the headset confirms or 2 s pass) driven by the pure-Swift `ScrubberModel` (`Tests/run.sh`). On every headset card with a loaded video, paired preview or not; disabled while that headset is in a group session. In `SyncControlPanel` while a session runs: `SyncSessionManager.seekAll` — pause + scheduled resume while playing, per-device seek while paused (Resume All then starts from the seek target).
  - The 10 Hz `viewerState` feed is now subscribed whenever a card shows a loaded video, not only while a preview is paired.
  - **Vision Pro**: `NativeVideoPlayerManager.seek(toMediaTime:)`, clamped to the asset; `onSeekCommand` in `WebSocketManager`.
  - Verified on the iOS 26 + visionOS 26.1 simulators. **Needs a device pass** for group seek.
```

- [ ] **Step 3: ADR**

Create `docs/adr/2026-09-17-playback-scrubber.md`:

```markdown
# ADR: Group seek reuses the scheduled resume rather than a scheduled seek

- **Date**: 2026-09-17
- **Status**: Accepted
- **Spec**: `docs/superpowers/specs/2026-09-17-playback-scrubber-design.md`

## Context

The controller gains a seek bar, for one headset and for a whole Play on All
session. A group seek must leave every headset at the same frame at the same
moment. The headset already supports `syncResume { mediaTime, startAt }`
(seek, preroll, start at a scheduled wall-clock tick) from the 2026-07-22
synchronised playback work.

## Options

1. **Scheduled `seek { mediaTime, startAt }`** — a new headset path that seeks
   and restarts on a tick. Clean on the wire; duplicates `scheduledResume` on
   the headset, the side that only gets verified on real devices.
2. **`syncPause` + `syncResume`** — the controller pauses the group and resumes
   it at the operator's time. No new headset code for the group case; the one
   new command (`seek`) is a plain single-headset jump.
3. **Seek only the preview** — does not control the headset. Rejected.

## Decision

Option 2. The headset gets exactly one new, unscheduled command. The group
path is a resume with a different number, already exercised by Resume All.

## Consequences

- A group seek while playing costs the same 1 s lead as a Resume All, during
  which the group bar is disabled.
- A group seek while paused is N individual `seek` commands; the controller
  updates its stored per-device position so the next Resume All uses the
  target.
- The headset's `seek` handler must not change playback state, so a paused
  headset stays paused on the new frame.
```

- [ ] **Step 4: Operator guide**

In `docs/guide/build.py`, in section 10 (`<h2>10. Playing on one headset</h2>`), directly after the `<h3>What the three buttons actually do</h3>` block's closing `</ul>` (the list of Play/Pause/Stop meanings), add:

```html
<h3>Jumping to a point in the video</h3>
<p>While a video is loaded the card shows a <b>position bar</b> under the preview (or under the "No preview video" line when none is paired), with the current position on the left and the running time on the right. <b>Drag the knob and let go</b>: the headset jumps to that point when your finger lifts, not while it moves. If the video was paused it stays paused on the new frame; if it was playing it carries on from there. The bar is greyed out while that headset is part of a <b>Play on All</b> session — use the bar in the Synchronized Playback panel instead, so the group stays together.</p>
```

In section 11 (`<h2>11. Playing on every headset at once</h2>`), directly before `<h3>Why a video is missing from the list</h3>`, add:

```html
<h3>Jumping the whole group</h3>
<p>While a group session is playing or paused, a <b>position bar</b> appears above Pause All / Stop All. Drag it and let go: every headset jumps to that point together. Playing headsets pause for about a second and restart on the same tick, exactly as Resume All does — expect that short freeze. Paused headsets move to the new frame and stay paused; the next Resume All starts from there.</p>
```

Rebuild:

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && ./docs/guide/build.sh | tail -1
```

Expected: `PDF: /Volumes/DEV-MAC/opt/qoo/vision-pro/docs/guide/Vision-Pro-Operator-Guide.pdf`.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/adr/2026-09-17-playback-scrubber.md docs/guide/build.py docs/guide/vision-pro-operator-guide.html docs/guide/Vision-Pro-Operator-Guide.pdf
git commit -m "[docs] Record the playback scrubber: protocol, ADR, operator guide

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Full regression on the simulators

**Files:** none modified.

- [ ] **Step 1: Fresh build and install of both apps** (simulator setup). Confirm binaries are newer than the last commit:

```bash
stat -f "%Sm %N" "$S/dd-avp/Build/Products/Debug-xrsimulator/VPC Player.app/VPC Player" "$S/dd-ios/Build/Products/Debug-iphonesimulator/VPC Remote.app/VPC Remote"
```

- [ ] **Step 2: Run the matrix, recording a screenshot or log line for each row**

| Case | Expect |
| --- | --- |
| Single card, playing, drag to ~2:00 | `Seek to 1xx.xs` in headset log; Activity Log `⏩ Seek …`; thumb holds then follows; preview jumps |
| Single card, paused, drag, then Resume | Still Paused after drag; Resume continues from the drop point |
| Card without preview (E736…) | Scrubber visible, label counts to 0:10 |
| Card during a group session | Scrubber disabled with hint |
| Group playing, drag to ~1:30 | `⏩ Group seek → 1:3x`; headset `Sync pause` → `Sync resume at …` → `Sync start in 0.99xs`; PLAYING |
| Group paused, drag, then Resume All | `Sync resume at` equals the seek target |
| Drag to the far right end | Clamps to 4:12; video ends normally, card shows Stopped |
| Normal Play → Pause → Resume → Stop | Unchanged |
| Play on All → Pause All → Resume All → Stop All | Unchanged |
| Preview first-play (10 s clip, then Lobby Tour) | Preview shown on first play, no length warning |

- [ ] **Step 3: Run the logic tests once more**

```bash
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && iOSController/Tests/run.sh
```

Expected: `ScrubberModel: all tests passed`.

- [ ] **Step 4: Restore the simulator data and push the branch**

```bash
V="$(xcrun simctl get_app_container $AVP com.qoostudio.player data)/Documents/Videos"
mv $S/aside/BigBuckBunny.MP4 $S/aside/HoW_IMMERSIVE_HERO_V7_VisionPro_12288x3072.mov "$V/" 2>/dev/null; ls "$V"
cd /Volumes/DEV-MAC/opt/qoo/vision-pro && git push -u origin feature/playback-scrubber
```

Any row that fails is a bug to fix on this branch before the branch is merged — do not merge with a failing row.
