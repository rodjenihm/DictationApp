# Microphone Selection

**Status:** Complete

## Summary

Let the user choose DictationApp's preferred audio input independently of the
macOS system default. New configurations prefer the Mac's built-in input when
one is available, while an explicit System Default option preserves standard
macOS routing when requested.

The selected device is resolved at the start of every recording. If a
preferred device is absent or cannot be configured before capture begins,
DictationApp temporarily uses the current system default without rewriting the
saved preference. Active recordings remain pinned to the device on which they
started.

This specification supersedes the default-input and no-picker requirements in
`docs/specifications/v1/application.md`,
`docs/specifications/v1/features/01-tabbed-settings.md`, and
`docs/specifications/v1/features/04-recording-startup-performance.md`.

## Motivation

When AirPods are the macOS default input, opening their microphone moves the
Bluetooth connection to a voice-oriented audio profile and changes playback
quality. The original recorder followed the system default through
`AVAudioEngine.inputNode` even when another device was selected for display.

DictationApp should normally record through the built-in MacBook microphone
without changing system-wide routing, while still supporting desktop Macs,
external microphones, virtual devices, and explicit user control.

## Goals

- Prefer the built-in input for a new configuration when one is available.
- Enumerate every current Core Audio device with at least one input channel.
- Provide System Default and specific-device choices in General Settings.
- Persist specific devices by stable Core Audio UID and last-known display
  name.
- Bind only DictationApp's capture unit to the resolved device.
- Keep device discovery live while Settings is open without activating audio
  capture or the microphone privacy indicator.
- Keep a disconnected saved preference visible and automatically resume it
  when the device returns.
- Fall back once to the current system default when a preferred device is
  missing or cannot be configured before capture.
- Show the actual capture device and fallback state during recording.
- Preserve cancellation, partial-capture recovery, artifact ownership, and
  immutable session behavior.

## Non-goals

- Change the macOS system-wide default input device.
- Add microphone preview, input-level metering, a test action, or monitoring
  while Settings is open.
- Switch devices during an active recording.
- Automatically choose an arbitrary non-default device when no system default
  is usable.
- Add recording-format selection.
- Add dedicated migration handling for development-only saved configuration.
- Add an automated test target.

## Preference and persistence

- Store the microphone preference with the transactional application
  configuration.
- Support System Default, built-in input, and stable-UID specific-device
  preferences.
- Store the last-known display name with a specific-device UID so a
  disconnected preference remains understandable.
- A new configuration starts with the built-in preference. During first-run
  configuration, use System Default instead when the Mac exposes no built-in
  input.
- No legacy decoding or migration path is required. An incompatible
  development-only configuration may fall back to current defaults.
- A Settings edit is provisional until Save Changes succeeds. Cancel restores
  the saved microphone preference.
- Saving an unavailable preferred device is valid because runtime fallback is
  defined.

## Device discovery

- Read the Core Audio device list, default input, device UID, localized name,
  transport type, alive state, and input stream configuration.
- Include built-in, Bluetooth, USB, display, aggregate, virtual, Continuity,
  and other devices when they expose at least one input channel.
- Exclude output-only and non-alive devices.
- Identify the built-in input from Core Audio's built-in transport type, not a
  localized display-name comparison.
- Sort System Default first, the built-in input next, and remaining connected
  inputs by localized name.
- Listen for device-list and default-input changes and publish value snapshots
  to Settings on MainActor.
- Device discovery must not start an audio unit, open a device for capture, or
  request microphone permission.
- Never log a device UID or name.

## Settings presentation

- Add a Recording section directly below Permissions on the General page.
- Present one native picker labeled Microphone.
- Include System Default followed by all connected input-capable devices.
- Preserve a saved disconnected choice as a selected
  “Device Name — Unavailable” entry.
- When the draft preference is unavailable, explain that recordings will use
  System Default until the device reconnects.
- Keep the draft selection stable when devices connect or disconnect.
- Use only preference kind or stable device UID as picker identity. Treat a
  specific device's last-known name as presentation metadata, refresh it from
  the live device snapshot when saving, and never let a rename change picker
  selection identity.
- Preserve the existing Settings read-only behavior during active sessions.
- Provide accessible labels and values through the native picker and concise
  secondary status text.

## Per-session resolution and capture

At the start of every recording:

1. Refresh the current input-device snapshot.
2. Resolve System Default directly, or resolve the saved preferred device by
   built-in transport or stable UID.
3. If the preferred device is absent, resolve System Default and mark the
   prepared recording as fallback.
4. Create a dedicated AUHAL input unit, enable input element 1, disable output
   element 0, and bind the resolved Core Audio device.
5. Read the device format, configure the unit's client format, allocate the
   maximum-slice buffer, and install the input callback before initialization.
6. Initialize and start that same unit, render input from element 1, and stream
   it to the existing asynchronous M4A writer.
7. If a present preferred device cannot be configured, clean up that attempt
   and try a different current System Default once.
8. If no candidate is usable, fail through the existing three-second capture
   failure lifecycle with actionable copy.

System Default mode does not count as fallback. A default-device change while
idle applies to the next recording. Device resolution must not mutate the
saved preference or macOS routing.

The first-buffer await has a two-second upper bound. A start call that returns
without producing a buffer, or a device/configuration failure before the first
buffer, fails as cannot-start. Successful capture still advances immediately
on its first accepted buffer.

The dedicated AUHAL and its callback state are owned by the recorder's serial
runtime queue. The real-time callback is the writer's only producer, and
teardown stops and uninitializes the AUHAL before disposing callback-owned
buffers or the writer.

## Active recording and failure behavior

- Include the resolved input name and fallback state in the immutable active
  session.
- Keep the session pinned to the starting device even if the system default
  changes.
- Show the actual input name in the menu and overlay.
- When fallback is active, append a non-blocking “preferred microphone
  unavailable” indication.
- Never switch to another device within the active recording.
- If the active device disconnects or the input unit fails after capture
  starts, stop, attempt partial finalization, and offer Transcribe Partial or
  Discard when valid.
- Evaluate partial and normal artifact success from writer finalization after
  safe AUHAL disposal. Report stop and uninitialize failures only as
  privacy-safe lifecycle diagnostics when instance disposal succeeds; a final
  instance-disposal failure remains a finalization failure because callback
  resource ownership is no longer provably safe.
- If neither preferred nor System Default can be used, show: “No microphone is
  available. Connect an input device or choose another microphone in
  Settings.”
- A rejected attempt must not leave a callback, AUHAL resource, writer, or
  temporary file.

## Privacy and diagnostics

- Device enumeration and preference storage contain hardware metadata only;
  they do not access microphone samples.
- Keep microphone capture and its privacy indicator inactive while idle.
- Never log device names, UIDs, audio, transcripts, paths, credentials,
  clipboard contents, or request bodies.
- Privacy-safe logs may report only selection mode, fallback occurrence,
  lifecycle outcome, failure classification, and timing.

## Acceptance criteria

- With AirPods as both macOS default input and output, a built-in preference
  records from the built-in microphone and does not open the AirPods input
  route.
- AirPods playback quality remains unchanged after recording completes or is
  cancelled.
- System Default mode follows a default-input change on the next session.
- A connected specific device is used without changing the system default.
- A disconnected or pre-capture-unconfigurable preference falls back once to
  System Default, remains saved, and is identified as fallback in active UI.
- Reconnecting a preferred device makes it available immediately and the next
  session uses it without another save.
- Disconnecting an active device does not switch mid-recording and retains the
  existing partial-recovery behavior.
- No-input failure cleans up and returns to idle after the existing
  three-second presentation.
- Debug and Release builds succeed with complete strict-concurrency checking,
  and repository whitespace/privacy checks pass.
