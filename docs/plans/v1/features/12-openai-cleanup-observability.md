# OpenAI Cleanup Observability Implementation Plan

**Status** · Implemented, Fast mode verified in the app

**Specification** · [OpenAI Cleanup Observability](../../../specifications/v1/features/12-openai-cleanup-observability.md)

## Implementation

1. Add a cleanup log category and a request-scoped URLSession task delegate
   with immutable session and attempt information. Extract connection reuse
   and phase durations from the supplied transaction metrics.
2. Attach the delegate to each runtime OpenAI cleanup attempt. Record the
   requested and reported serving tiers and a classified outcome. Distinguish
   explicit Fast rejection and later Standard attempts from a server-served
   downgrade of the original request.
3. Keep timing records independent of response validity and provider
   teardown. Preserve the existing retries, cleanup deadline, and fallback.
4. Verify unsigned macOS Debug and Release builds and the working diff.
   Inspect each recorded field for sensitive data and review timing and tier
   semantics against the provider and platform API references.

## Verification evidence

- Unsigned macOS arm64 Debug and Release builds passed with Xcode 27.2 in
  both the isolated cleanup slice and the integrated tree. Swift reported
  no application diagnostics. `git diff --check` passed.
- Source inspection confirmed that the metrics delegate captures only
  immutable attempt information and reads timing fields and the reuse flag
  from the transport metrics. Response tier values pass through a fixed
  allowlist before they are logged.
- A subsequent user-run dictation reported Fast as both requested and
  served. Cleanup took 936 ms, including a first attempt lasting 928 ms.
  The fresh connection took 69 ms and the wait for the first response
  byte took 831 ms.
- A later user-run dictation also logged Fast as both requested and served
  on the first attempt. Cleanup took 729 ms, including a 716 ms request.
  The fresh connection took 78 ms, and the wait for the first response byte
  took 608 ms. The app dispatched the paste 1.204 seconds after Stop and
  confirmed delivery.
- Standard-versus-Fast latency and Fast rejection diagnostics remain
  unverified in live use.
