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
