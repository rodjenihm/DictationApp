# Tabbed Settings

**Status:** Complete

## Summary

Replace the single scrolling configuration form with a sidebar-based Settings
window. Settings are organized into four top-level destinations:

1. General
2. Transcription
3. Post-processing
4. Providers

The feature must make provider configuration independent from choosing which
provider and model powers each processing stage. OpenAI is the only implemented
provider in this version, but the information architecture and provider
boundaries must support providers with different capabilities, processing
locations, authentication mechanisms, and configuration requirements.

This specification refines the Settings presentation and configuration workflow
defined by the application specification. It does not change the dictation
pipeline, retry policy, provider request behavior, or text-insertion behavior
except where Settings routing and repair behavior are stated explicitly.

## Goals

- Make Settings easier to scan and navigate.
- Give general application preferences, transcription, post-processing, and
  provider setup clear ownership.
- Establish Providers as an extensible management area without showing
  unimplemented providers.
- Keep provider credentials and connection setup separate from stage-level
  provider/model selection.
- Preserve transactional validation and saving across all Settings pages.
- Keep the existing first-run, active-session, and transcription-repair safety
  properties.
- Clearly communicate whether each configured stage processes data in the
  cloud or on-device.

## Non-goals

> Microphone input-device selection is implemented and specified separately
> by `05-microphone-selection.md`, which supersedes that non-goal.

- Implement a provider other than OpenAI.
- Show disabled providers, placeholders, roadmaps, or “Coming soon” entries.
- Add microphone input-device selection.
- Add launch-at-login, overlay customization, data-retention controls, or other
  new general preferences.
- Add multiple accounts, named profiles, or multiple credentials for one
  provider.
- Add a separate onboarding wizard.
- Add a Settings search feature.
- Change model catalogs, transcription behavior, post-processing instructions,
  recording behavior, or provider retry policies.
- Guarantee migration of development-only non-secret Settings data from the
  previous form.

## Window structure

Use a native macOS split-view Settings window:

- A fixed-width sidebar contains the four top-level destinations with an SF
  Symbol and visible text label.
- The detail area contains a page-specific title, a short description, and
  scrollable content.
- Do not retain the previous large application-wide hero header.
- A persistent footer contains save status and the context-appropriate primary
  action.
- The window remains resizable and defines sensible minimum dimensions.
- Individual pages scroll instead of requiring an excessively tall minimum
  window.
- Only one Settings window exists. Reopening Settings activates the existing
  window.

Exact dimensions, padding, typography, and animation are implementation details,
provided that the layout remains usable at its minimum size.

### Sidebar order

The order is fixed:

1. General
2. Transcription
3. Post-processing
4. Providers

### Sidebar state

Each destination may expose:

- A dot when that page contains unsaved changes.
- A warning badge when its saved configuration requires attention.
- An error badge after validation fails.

Do not show numeric counts. State must not rely on color alone; VoiceOver must
announce the equivalent status.

Providers aggregates the state of its provider entries. Transcription and
Post-processing expose their own stage health. A provider-level problem may
therefore cause both Providers and a dependent stage to show attention.

### Selection persistence and contextual routing

Persist the last ordinary top-level destination across window closes and
application launches. Do not persist nested provider-detail navigation. If the
last destination was Providers, an ordinary reopening starts at the provider
list.

Contextual entry points override the persisted destination:

| Context | Destination |
| --- | --- |
| First run | Providers → OpenAI |
| Missing or invalid provider credential | Providers → affected provider |
| No transcription provider selected | Transcription |
| Invalid or incompatible transcription model/language | Transcription |
| Post-processing configuration warning | Post-processing |
| Transcription repair | Transcription |
| Ordinary Open Settings action | Last persisted top-level destination |

Contextual routing must not discard an existing Settings draft.

## General

General contains five sections in this order. The Recording section defined by
`05-microphone-selection.md` appears directly below Permissions.

### Permissions

Show current system-derived status for:

- Microphone
- Accessibility

Retain the existing explicit Enable and Open System Settings actions. Merely
opening Settings must never trigger a macOS permission prompt.

Microphone permission remains system-derived and immediate. The transactional
input-device preference is defined by `05-microphone-selection.md`.

Permission actions affect external system state immediately. They are not part
of the Settings draft, do not mark the page dirty, and are not reverted by
Discard Changes.

### Global Shortcut

Keep the existing shortcut recorder and reset-to-default action, but change the
shortcut to participate in the window-level draft:

- Recording or resetting a shortcut changes only the draft.
- Reject malformed or macOS-reserved combinations locally.
- Keep the currently registered shortcut active until Save succeeds.
- During Save, attempt registration before committing the new shortcut.
- If registration fails, keep the previous shortcut active and show an inline
  error on General.
- If a later part of the save fails, restore the previous registration on a
  best-effort basis.

### Feedback

Keep the existing sound-cues setting. It participates in the window-level draft
and takes effect only after a successful Save.

### Data & Privacy

Provide a concise, configuration-aware summary of:

- Credentials being stored in macOS Keychain.
- The current transcription provider and whether completed audio is uploaded
  or processed on-device.
- Whether post-processing is enabled and whether raw transcript text is
  uploaded or processed on-device.
- DictationApp having no user account or proprietary backend.
- Temporary recordings and in-memory transcript data not being retained after
  the session lifecycle defined by the application specification.

The summary must be generated from provider capability metadata rather than
hard-coded to OpenAI. Detailed provider/stage disclosures remain adjacent to
the controls that establish each data flow.

Do not add privacy toggles that do not change application behavior.

## Transcription

The Transcription page owns:

- Transcription provider selection.
- Transcription model selection.
- Custom transcription model input, when supported.
- The global transcription language preference.
- The selected provider’s transcription data-flow disclosure.
- Stage-specific configuration and runtime health.

### Provider selection

Always present provider selection as a first-class control, even when only one
provider is eligible.

The picker offers providers that:

- Are implemented.
- Declare transcription capability.
- Are currently usable/configured for transcription, or are provisionally
  available through the current draft.

Do not show unimplemented or incapable providers.

If the saved selection later becomes unavailable, retain and display it as
Setup required rather than silently selecting another provider. If no eligible
provider exists, show a No provider configured state and a Configure Providers
action that navigates to the provider list.

### Model selection

Models are provider- and stage-specific. A provider supplies:

- A curated transcription model catalog.
- A recommended default.
- Whether custom model identifiers are supported.

Preserve model choices per provider and per stage. When the provider changes,
restore that provider’s last valid transcription model or use its declared
default. Never reuse a model identifier across providers.

When supported, include an Advanced: Custom model option:

- Reveal a provider-specific identifier field only when selected.
- Trim surrounding whitespace.
- Preserve the identifier otherwise exactly.
- Validate a newly selected or changed custom identifier against the
  transcription stage during Save.

Known curated models do not require a network request solely because their
selection changed, unless the provider explicitly requires validation.

### Language

Language is one provider-neutral transcription preference rather than a
per-provider setting:

- Store Automatic or a canonical BCP-47 language tag.
- Preserve the selection when switching providers.
- Let the provider adapter map the preference to its own API/model identifier.
- Derive selectable explicit languages from the selected provider’s current
  capabilities.
- If a preserved language is unsupported, keep it visible with an
  incompatibility warning and require a supported language or Automatic before
  saving a newly introduced configuration.
- Never silently change the language preference when switching providers.

The language remains a recognition hint, not a translation request.

## Post-processing

Transcription and Post-processing provider selections are independent. Future
configurations may use the same provider for both stages or a different
provider for each.

Place Enable transcript cleanup at the top of the page:

- Post-processing remains disabled by default.
- When disabled, hide provider/model controls but preserve their saved and draft
  selections.
- When re-enabled, restore the last provider/model selections.
- Do not model Disabled as a provider named “None.”

When enabled, the page owns:

- Post-processing provider selection.
- Post-processing model selection.
- Custom post-processing model input, when supported.
- The selected provider’s transcript data-flow disclosure.
- Stage-specific configuration and runtime health.

Provider and model behavior follows the Transcription rules, filtered for
post-processing capability. Model selections remain provider- and
stage-specific.

If no capable configured provider exists, show Provider setup required and a
Configure Providers action. A draft that newly enables post-processing cannot
be saved until an eligible provider and valid model are selected.

Post-processing configuration failures must not change the application
specification’s raw-transcript fallback behavior or block otherwise valid
dictation.

## Providers

Providers is the management area for provider-specific setup. It is not a
duplicate location for stage model or language choices.

### Provider list

Show every implemented provider, including providers that are not yet
configured. This is intentionally different from stage pickers, which filter
for capability and readiness.

Each provider row shows:

- Provider name and icon.
- Configuration status.
- Capability badges such as Transcription and Post-processing.

Supported configuration statuses are:

- Configured
- Setup required
- Attention required

Provider rows must not reorder dynamically based on status.

Selecting a provider drills into its detail page in the existing detail area.
Do not create a second permanent split view. The provider detail header exposes
a Providers back action or breadcrumb. Switching to another top-level
destination resets nested provider navigation to the list.

### Provider detail ownership

A provider detail page owns only provider-specific connection and setup
material, for example:

- API credentials.
- OAuth or other authentication.
- Local model assets.
- Provider-specific endpoints or required fields.
- Provider and capability health.

Model, language, and stage enablement choices must not be duplicated here.

Do not force all providers into a generic API-key schema. The shared provider
registry exposes common metadata and capabilities, while each provider owns its
custom configuration content, draft, validation, and commit behavior. Shared
Settings and domain-neutral presentation code must not switch on OpenAI-specific
form fields.

Support one configured account/profile per provider. Multiple keys, named
profiles, workspaces, and per-stage provider accounts are out of scope.

### OpenAI detail

OpenAI is the only provider shown in this version. Its detail page contains:

- Masked credential status without displaying the saved value.
- A blank SecureField for adding or replacing the API key.
- A Remove API Key action.
- Validation and provider-health feedback.
- Keychain and provider-specific privacy/upload disclosure.

Do not add a separate Test Connection action. Save Changes is the validation
trigger.

The saved API key is write-only from the UI:

- Never display or copy it back from Keychain.
- Keep an unsaved candidate in memory after validation failure or cancellation
  so the user can correct and retry it.
- Clear the candidate after successful Save, Discard Changes, or window close.
- Never persist, log, or include the candidate in diagnostics or error output.

Reuse the existing Keychain item:

- Service: `com.danijelmitrovic.DictationApp.openai`
- Account: `api-key`

Do not create a second OpenAI credential item as part of this feature.

## Provider capability and readiness model

Provider support must not be represented by one persisted `isConfigured`
Boolean.

Each implemented provider declares:

- Stable identity and display metadata.
- Supported capabilities independently for transcription and post-processing.
- Processing location per capability: Cloud, On-device, or an explicit
  provider-defined mixed/other description.
- Curated models and defaults per supported stage.
- Custom-model support per stage.
- Supported language behavior for transcription.
- Configuration and validation behavior.

Derive readiness per capability from applicable state, including:

- Authentication or credentials.
- Provider-specific configuration.
- OS and hardware availability.
- Installed local assets.
- Available compatible models.
- Locale/language support.
- Known runtime health.

A provider can be ready for one capability and unavailable for another. Stage
pickers filter by both declared capability and current readiness.

Configured means required provider material exists and no known provider-level
failure is active. It does not guarantee current network, account, quota, or
service availability.

Opening Settings must not make provider requests or periodically revalidate
credentials. Attention required is based on the most recent relevant validation
or runtime failure.

### Health attribution

- Credential/authentication failures belong to the provider and propagate
  Attention required to every selected stage that depends on it.
- Invalid or incompatible models/languages belong to the affected stage.
- Stage pages link to the responsible provider detail when action is required
  there.
- Successful validation clears only the matching provider/stage warning.
  Unrelated warnings remain.

Runtime health continues to be derived/in-memory as defined by the application
specification; it must not become a persisted readiness Boolean.

## Shared draft and Save behavior

All app-owned Settings pages share one in-memory draft. Navigating between
sidebar destinations or provider details must not save or discard it.

The footer action is:

- Finish Setup during first run.
- Save Changes during ordinary editing.
- Validate Repair during transcription repair.

### Dirty state

Track changes at field and destination level. A draft includes:

- General preferences such as shortcut and sound cues.
- Stage provider/model/language and enablement selections.
- Provider-specific configuration.
- Credential addition, replacement, or removal intent.

External permission state is not part of the draft.

Save Changes is disabled only when there are no unsaved changes or validation is
running. Locally invalid drafts do not silently disable it; invoking Save runs
local validation and routes to actionable errors.

Finish Setup remains invokable whenever validation is not running so it can
route the user to missing required fields, even when defaults have produced no
dirty fields. Validate Repair remains invokable whenever repair access is
editable and validation is not running.

### Validation order and scope

Save performs:

1. Local validation for all affected pages.
2. Required provider/network validation.
3. Preparation of reversible runtime changes, including candidate shortcut
   registration.
4. Provider configuration, Keychain changes, and non-secret settings
   persistence with compensating rollback where the underlying stores cannot
   participate in one transaction.
5. Finalization of runtime changes.

The observable result must be all-or-nothing. If a step fails, retain or restore
the previously working provider configuration, Keychain contents, non-secret
settings, and active shortcut on a best-effort basis.

Only changed or newly activated configuration is validated:

- New/replaced provider authentication or provider-specific setup.
- Every changed provider, even when it is not selected by a stage, using that
  provider’s lightweight validation.
- Newly selected or changed custom models.
- Newly enabled stages.
- Stage/provider combinations whose validation-relevant inputs changed.

Do not revalidate unchanged providers or configurations gratuitously.

For OpenAI:

- Validate a new/replacement key using each active OpenAI stage whose relevant
  inputs changed.
- When OpenAI transcription is active or being configured, validation may
  upload only the bundled short silent audio fixture.
- When OpenAI is being configured but is not selected for any stage, use the
  provider’s lightweight authentication validation.
- Validation must never upload a user recording or user transcript.

### Validation progress and cancellation

While asynchronous validation is running:

- Disable editable controls.
- Replace the primary action with a visible Validating state.
- Offer Cancel.
- Keep sidebar navigation available for viewing status.

Cancellation is best-effort. It commits nothing, preserves the draft, and
returns the window to its editable state.

If the user attempts to close during validation, ask whether to cancel
validation. Confirming cancellation follows the same behavior and does not
close until cancellation handling completes.

### Validation errors

On failure:

- Mark every affected sidebar destination.
- Navigate to the first actionable error.
- Show the error inline beside the responsible field.
- Show a concise summary in the footer.
- Preserve the complete draft.
- Commit nothing.
- Clear a field’s stale error when that field is edited, then re-evaluate it on
  the next Save.

Provider-specific raw error payloads and identifiers must not leak into
provider-neutral presentation or logs.

### Draft provider readiness

A provider with newly entered but unsaved configuration becomes provisionally
available to stage pages:

- Show it in eligible provider pickers as Pending validation.
- Allow dependent model selection before Save.
- Do not label it Configured or use it for dictation until validation and commit
  succeed.

A provider staged for removal remains visible to dependent pages as Will be
disconnected.

### Removing provider authentication

Provider authentication removal participates in the draft. For OpenAI, Remove
API Key:

- Shows an impact warning before staging removal.
- Does not touch Keychain until Save succeeds.
- Can be cancelled by Discard Changes.

Allow removal even when the provider is selected or is the only usable
transcription provider. On successful removal:

- Preserve provider, model, language, and post-processing selections.
- Do not silently switch providers or disable stages.
- Mark the provider and dependent stages Setup required.
- Block new dictation and contextually route to the provider detail until a
  usable transcription provider is configured.

This intentional unavailable state is allowed after first-run setup.

### Readiness validation nuance

- Do not let a draft newly select or enable an unusable provider.
- Allow unrelated settings to save if a previously selected provider became
  unavailable externally.
- Allow an explicitly confirmed provider disconnection to save.
- Require a usable transcription configuration to complete first-run setup.
- Require a usable post-processing configuration when newly enabling
  post-processing.

### Successful save

For ordinary Save Changes:

- Keep the Settings window open.
- Clear dirty/error state for committed fields.
- Show a concise saved confirmation.
- Apply changes only to future sessions.

For Finish Setup and Validate Repair, use their flow-specific behavior below.

## Closing with unsaved changes

Closing the window with a dirty draft presents:

- Save Changes — validate and close only after a successful save.
- Discard Changes — restore persisted state, clear credential candidates, and
  close.
- Cancel — return to Settings unchanged.

Changing destinations never triggers this prompt.

First-run and repair modes use the context-appropriate primary-action label in
the prompt while preserving the same save/discard/cancel semantics.

## First-run behavior

Reuse the Settings window rather than creating a separate wizard:

- Open directly at Providers → OpenAI.
- Show OpenAI as Setup required until a credential is validated and saved.
- Keep all top-level destinations available.
- Do not automatically request Microphone or Accessibility permission.
- Use provider/model/language defaults from the application specification.
- Keep post-processing disabled by default.

Finish Setup requires:

- At least one usable transcription provider.
- A valid transcription model.
- A compatible explicit language or Automatic.

Microphone and Accessibility permission are not completion requirements.

After a successful Finish Setup:

- Mark first-run setup complete.
- Close Settings.
- Leave DictationApp ready in the menu bar.

## Active-session behavior

During an active recording or processing session:

- Sidebar and nested provider navigation remain usable.
- Settings fields, credential mutations, permission actions, and Save are
  read-only.
- Show a persistent explanation that the active session uses an immutable
  configuration snapshot.

If dictation begins while Settings contains an unsaved draft:

- Preserve the draft.
- Lock it for the active session.
- Make clear that the current session uses the last saved configuration.
- Re-enable the same draft when the session becomes editable.
- Refresh externally derived state such as permissions without overwriting the
  draft from persistence.

## Transcription repair

Retain the normal sidebar instead of presenting a separate repair form:

- Open on Transcription.
- Show a persistent repair explanation.
- Allow edits only to the transcription provider/model and relevant
  provider-specific authentication/configuration.
- Keep the retained session’s language fixed.
- Keep General and Post-processing visible but read-only.
- Use Validate Repair as the footer action.

If validation identifies a provider authentication problem, route to Providers
→ affected provider. Model problems remain on Transcription.

In a future multi-provider configuration, repair may switch providers only when
the candidate provider can process the retained recording’s format and fixed
language. Do not offer generally capable providers that are incompatible with
the retained artifact.

Successful repair:

- Validates and persists the repaired provider/model and any provider
  configuration for future sessions.
- Applies only the validated transcription provider/model override to the
  retained session.
- Preserves that session’s original language, recording profile, and
  post-processing snapshot.
- Closes Settings and returns to the retained-session failure UI.
- Requires a separate explicit Retry before uploading the retained recording.

Validation itself may use the provider’s safe validation fixture but must not
upload the retained recording.

## Accessibility and keyboard behavior

- All sidebar items, status indicators, provider rows, fields, disclosures, and
  actions require meaningful accessibility labels, values, and hints.
- The complete window must be navigable using standard macOS full-keyboard
  access.
- Focus must move to the first invalid actionable field after validation
  routing.
- Save/Finish/Validate Repair is the default action when enabled.
- Standard window close behavior invokes unsaved-change protection.
- Resizing and scrolling must not remove controls from the accessibility
  hierarchy.

## Acceptance criteria

- Settings opens with the four agreed sidebar destinations in the agreed order.
- Every setting from the previous single form has exactly one owning page.
- OpenAI credentials are managed only through Providers → OpenAI.
- Transcription and Post-processing independently select from capable, usable
  providers and provider-owned model catalogs.
- Only OpenAI appears; no unimplemented provider is shown anywhere.
- Provider capability/readiness and processing-location metadata are not
  OpenAI-specific.
- Language is global and provider-neutral; models are provider- and
  stage-specific.
- Navigating within Settings preserves the shared draft.
- Save validates and commits all app-owned changes transactionally.
- Shortcut changes no longer apply before Save.
- Credential replacement/removal does not alter Keychain before Save.
- The existing OpenAI Keychain item is reused and no duplicate is created.
- Validation failure routes to the responsible page and preserves the draft and
  last working saved configuration.
- Closing a dirty window offers Save, Discard, and Cancel.
- First run opens OpenAI setup and closes after successful Finish Setup.
- Ordinary Save leaves Settings open.
- Active sessions lock but do not discard an existing draft.
- Repair uses the sidebar, persists the validated repair, closes on success, and
  never retries or uploads the retained recording automatically.
- Privacy copy reflects the selected providers’ actual processing locations and
  data flows.
- Provider credentials and sensitive candidate values never appear in
  non-secure persistence, logs, diagnostics, or UI output.
