---
name: debugging
description: The team's disciplined approach to debugging and root-cause analysis — reproduce, form hypotheses, isolate, find the real cause (not the symptom), and verify the fix. Always use this skill whenever investigating a bug, an incident, failing tests, or unexpected behavior, instead of guessing or patching symptoms.
---

# Debugging & Root-Cause Analysis

Goal: fix the actual cause, confirmed — not the first thing that makes the symptom disappear.

## Process
1. **Reproduce first**: get a reliable, minimal reproduction. If you can't reproduce it, you can't confirm a fix. Note exact steps, inputs, environment, and frequency (always vs intermittent).
2. **Gather evidence**: read the actual error, stack trace, and logs. Establish a timeline of what happened and the system state — don't theorize before looking.
3. **Form hypotheses**: list testable hypotheses about what broke and in what order. Rank by likelihood. Avoid latching onto the first idea.
4. **Isolate**: binary-search the problem space — disable/halve code paths, bisect commits (`git bisect`), mock dependencies one at a time — until the failing component is pinned down.
5. **Find the root cause**: keep asking "why" past the symptom. The crash is often downstream of the real defect (bad input, wrong assumption, race condition, missing validation).
6. **Verify the fix**: confirm the fix actually prevents recurrence — re-run the reproduction. Add a **regression test** that fails on the old behavior (see `testing-strategy`).
7. **Check the blast radius**: did the same root cause appear elsewhere? Fix those too. Did the fix introduce risk? Review it.

## Principles
- **Symptom ≠ cause**: never ship a patch that only hides the symptom.
- **One change at a time** while diagnosing, so you know what actually mattered.
- **Reproduce → fix → verify**: a fix without a confirmed reproduction is a guess.
- **Preserve context**: record findings, the timeline, and the root cause so patterns surface over time.

## Documentation
- For non-trivial bugs/incidents, capture the root cause and resolution in the bug log (`docs/bugs/`).
- If the cause reveals a design flaw, raise it to the tech-lead and record an ADR if the fix changes architecture.

## Common root-cause categories to check
Invalid/unvalidated input · incorrect assumptions about state · race conditions/ordering ·
off-by-one/boundary · null/undefined · caching/stale data · environment/config drift ·
dependency version mismatch · time zone / encoding issues.
