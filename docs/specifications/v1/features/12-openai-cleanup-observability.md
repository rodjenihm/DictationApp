# OpenAI Cleanup Observability

**Status** · Implemented, Fast mode verified in the app

## Goal

Explain where runtime OpenAI cleanup spends time and compare Standard and
Fast requests using the tier OpenAI reports. Correlate cleanup attempts with
the existing session and delivery timings from the
[dictation latency specification](09-dictation-pipeline-latency.md).

## Attempt records

Write the following local records in the `cleanup` unified log category.
Use the existing in-memory session ID and number attempts from one within
each cleanup operation.

- `openai_cleanup_attempt` records the requested tier, serving tier,
  elapsed milliseconds, and an outcome classification. Request tiers are
  `fast`, `standard`, and `project_default` when the request defers to the
  project. Normalize the Responses API's `fast` and `priority` serving
  values to `fast` and `default` to `standard`. Classify missing or unusable
  tier metadata as `unreported` and unfamiliar tier strings as `unknown`.
- Classify explicit Fast rejection as `fast_tier_rejected`. Mark later
  Standard attempts in that operation as `fast_rejection_fallback`. The
  existing retry budget governs whether a Standard attempt runs. A Fast
  request that OpenAI serves as Standard remains a single attempt with two
  different tier values.
- Keep the existing cleanup-stage outcome. A usable response at the
  request boundary can still fail the transcript validation or arrive after
  the stage deadline.

## Transport records

Use a request-scoped URLSession delegate to record
`openai_cleanup_transport` entries for the transactions in each completed
metrics callback. Include the same session and attempt numbers, the
transaction number, and the connection-reuse flag for network loads.
Record the available durations in milliseconds.

| Field | Interval |
| --- | --- |
| `dns_ms` | DNS lookup start to end |
| `connect_ms` | Connection setup start to end |
| `tls_ms` | Secure handshake start to end |
| `upload_ms` | Request start to end |
| `first_response_wait_ms` | Request end to first response byte |
| `download_ms` | First response byte to response end |

Represent unavailable measurements with `-`, including unfinished phases
and connection setup phases that the task does not perform again. A task
can report multiple transactions or no transactions. The connection and
TLS timings may overlap. The first-response wait includes both network and
server time.

## Scope and privacy

Keep runtime cleanup request, retry, cancellation, and delivery behavior
independent of metrics collection. Limit records to session correlation,
attempt and transaction numbers, allowlisted tier and outcome classifications,
the connection-reuse flag, and durations. Exclude endpoint and network
identifiers, payload sizes, provider error text, credentials, dictated text,
tokens, and request and response bodies from the logs.

See [Apple's URLSession timing reference](https://developer.apple.com/documentation/foundation/urlsessiontasktransactionmetrics)
and the [OpenAI Responses API reference](https://developers.openai.com/api/reference/resources/responses/methods/create).
