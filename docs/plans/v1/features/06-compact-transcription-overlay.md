# Compact Transcription Overlay Implementation Plan

**Status:** Complete

**Specification:**
`docs/specifications/v1/features/06-compact-transcription-overlay.md`

## Baseline

- Initial branch: `main`
- Initial revision: `27d619afbf4a4f97390dd26b486e8f332bce0bf3`
- Initial worktree: clean
- Xcode uses file-system-synchronized groups, so the documentation additions do
  not require project membership changes.
- No automated test target or test changes are authorized for this feature.

## Progress

| Phase | Status | Outcome | Evidence |
| --- | --- | --- | --- |
| 1. Specification and baseline | Complete | Defined compact and attention presentation, success suppression, accessibility, and preserved behavior | Approved grilling decisions, feature specification, clean baseline |
| 2. Adaptive overlay presentation | Complete | Replaced fixed routine layout and panel minimums with bounded compact/attention presentation | Debug/Release builds, rendered fitting-size probe, and visual/source inspection |
| 3. Immediate confirmed-success completion | Complete | Removed visible success and delay while retaining a macOS accessibility announcement | Debug/Release builds and transition/source inspection |
| 4. Documentation and verification | Complete | Synchronized superseded requirements and verified both build configurations and repository hygiene | Debug/Release builds, code-signature checks, `git diff --check`, and changed-source review |

## Architecture

- `OverlayViewState` remains the presentation boundary between the session
  coordinator and SwiftUI overlay.
- `OverlayView` classifies each state as compact or attention content and owns
  state-specific copy, indicators, control style, and bounded layout.
- `OverlayWindowController` continues to own the non-activating `NSPanel`,
  session-screen selection, fitting-size measurement, and bottom-center
  positioning. It must stop imposing the independent 500-by-64-point minimum.
- `DictationCoordinator` retains the inserted state boundary but removes the
  confirmed-success sleep so normal delivery completes immediately.
- `AppModel` suppresses visible `.inserted` presentation and posts the
  nonvisual accessibility announcement before the coordinator returns to idle.
- Menu-bar status remains provider- and device-specific during active states;
  no `MenuBarContent` information architecture changes are required.

## Implementation phases

### Phase 1 — Specification and baseline

- Record the approved compact/attention state classification, sizing bounds,
  content rules, success behavior, accessibility contract, and superseded
  requirements.
- Capture the initial revision and worktree state before implementation.
- Identify the current view-level and window-level minimum dimensions so both
  are removed together.

Gate: the feature specification contains no open product decisions and the
baseline distinguishes feature edits from pre-existing work.

### Phase 2 — Adaptive overlay presentation

- Split `OverlayView` presentation into compact and attention compositions
  while preserving the existing injected actions and state ownership.
- Use single-line primary copy for routine states and concise fixed warnings
  for fallback microphone, duration limit, and raw-transcript fallback.
- Replace routine labeled Stop and Cancel buttons with compact system-symbol
  buttons that retain roles, accessibility labels, hover help, non-focusable
  behavior, and pointer operation.
- Keep labeled recovery actions and full explanatory detail in attention mode.
- Replace fixed routine and recovery widths with content-fitting layout bounded
  by the approved compact and attention ranges.
- Reduce spacing, padding, capsule-border contrast, and shadow prominence while
  retaining the material capsule.
- Remove the panel controller's 500-by-64-point minimum and size the panel from
  the hosted view's fitting size before re-centering it on the session display.
- Preserve immediate preparation presentation and avoid adding view or window
  animation.

Gate: source inspection confirms every renderable state has an intentional
presentation mode, controls retain their actions and accessibility metadata,
and neither SwiftUI nor AppKit enforces the former routine minimum.

### Phase 3 — Immediate confirmed-success completion

- Remove the 1.2-second confirmed-success sleep from the coordinator while
  preserving clipboard restoration and the inserted transition boundary.
- Dismiss or suppress the overlay when AppModel observes `.inserted`.
- Post `Transcript inserted` through the macOS accessibility announcement
  mechanism without activating DictationApp.
- Let normal pipeline completion publish idle immediately so the shortcut and
  menu return to Ready without a dead interval.
- Preserve the 2.5-second raw-fallback warning and all other terminal/recovery
  durations.

Gate: a confirmed insertion restores an owned clipboard snapshot, produces no
visible success overlay, announces success accessibly, and permits a new
recording as soon as delivery completes.

### Phase 4 — Documentation and verification

- Update the base application overlay requirements to distinguish compact
  routine, attention, and invisible confirmed-success behavior.
- Update the microphone-selection presentation requirement so the menu always
  shows the actual input while the overlay shows it only for fallback.
- Record implementation and verification evidence in this plan and
  `docs/plans/v1/progress.md`.
- Build Debug and Release.
- Run `git diff --check` and privacy-sensitive source searches.
- Manually inspect routine preparation, recording, processing, no-speech, raw
  fallback, confirmed insertion, and representative attention states when
  practical.
- Confirm the panel remains bottom-centered, non-activating, focus-safe, and
  pointer-operable, and that a confirmed insertion has no visible success
  acknowledgement or shortcut delay.

Gate: both build configurations and repository checks pass; manual evidence
covers the changed presentation and success lifecycle without regressions in
focus, cancellation, recovery, or accessibility.

## Verification matrix

| Scenario | Expected result |
| --- | --- |
| Preparation | Compact `Starting…` pill appears immediately without animation |
| Ordinary recording | Single-line red indicator, elapsed time, symbol Stop, and symbol Cancel fit within the compact bound |
| Microphone fallback | Compact warning identifies the fallback device; menu retains complete detail |
| Duration warning | Compact copy identifies the approaching limit without relying on color alone |
| Transcribing, cleanup, insertion | Concise single-line status and symbol Cancel; provider detail remains in the menu |
| Confirmed insertion | Clipboard restores when owned, no visible success UI appears, accessibility announces success, and Ready is immediate |
| Raw cleanup fallback | Compact warning remains for 2.5 seconds and is visually distinct from ordinary success |
| No speech and too short | Existing duration with compact, non-actionable presentation |
| Recovery and failures | Complete message and labeled actions remain within the attention layout |
| Focus and display | Target app remains focused; overlay stays bottom-centered on the session display |

## Verification evidence

- 2026-08-23: Normally signed arm64 Debug and Release builds succeeded with the
  macOS 15.0 deployment target and strict concurrency settings.
- 2026-08-23: Both built application bundles passed strict deep code-signature
  verification.
- 2026-08-23: A temporary AppKit-hosted SwiftUI rendering probe measured
  Preparing at 120 by 31 points, ordinary Recording at 174 by 31,
  Transcribing at 146 by 31, raw fallback at 256 by 29, and the combined
  microphone-fallback/duration warning at the 360-by-31-point cap.
- 2026-08-23: The same probe measured clipboard fallback at 480 by 64 points and
  repairable transcription failure at 520 by 64. Visual inspection confirmed
  intact labels and controls in ordinary recording, combined warning, and
  repairable-failure presentations.
- 2026-08-23: Source inspection confirmed the panel now uses the hosted view's
  fitting size, confirmed insertion dismisses the overlay and refreshes Ready,
  the coordinator no longer sleeps in ordinary `.inserted`, and raw fallback
  retains its 2.5-second display.
- 2026-08-23: `git diff --check`, changed-source logging/privacy review, and
  changed-path scope review passed. The temporary sizing/rendering probe and
  its output were kept outside the repository.

## Verification limitations

- A live provider-backed confirmed insertion was not repeated. Immediate
  completion and invisible presentation were verified from the synchronous
  state transition, AppModel presentation mapping, and successful builds.
- VoiceOver was not enabled during verification. The macOS accessibility
  announcement API and required announcement/priority payload compile in both
  configurations, but spoken output was not observed live.

## Assumptions

- The approximately 360-by-44-point compact bound applies under standard macOS
  display and text settings; accessibility requirements may expand it.
- Long fallback device names may truncate visually but remain complete in
  accessibility and menu-bar presentation.
- Existing state semantics and timings remain authoritative unless this plan
  explicitly changes them.
- Build artifacts remain outside the repository.
