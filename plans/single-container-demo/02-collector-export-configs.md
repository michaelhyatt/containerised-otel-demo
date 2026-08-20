# Task 02 — Collector export configs and destination variables

Affected files: `src/otel-collector/otelcol-config-export-grpc.yml`,
`-http.yml`, `-both.yml` (new), `.env`.

Depends on: 01.

## Goal

Send every signal to an external destination as OTLP protobuf over gRPC, HTTP,
or both, without editing the base collector config.

## Steps

1. Add the destination variables to `.env` with inert defaults so the collector
   never fails to start on an unset variable: `OTLP_EXPORT_PROTOCOL=grpc`,
   `OTLP_EXPORT_ENDPOINT_GRPC`, `OTLP_EXPORT_ENDPOINT_HTTP`,
   `OTLP_EXPORT_HEADERS={}` and `OTLP_EXPORT_INSECURE=true`. No separate config-
   path variable: `OTLP_EXPORT_PROTOCOL` is interpolated directly into the
   `--config` path in Task 01's override, which keeps one source of truth.
   Endpoint defaults must not point at localhost, or the collector exports into
   its own receivers; use a name that fails DNS and explains itself in the logs.
2. Write the gRPC config: an `otlp/external` exporter reading the endpoint,
   headers and TLS setting from the environment, plus a `retry_on_failure`
   and `sending_queue` block sized conservatively so a dead destination cannot
   grow the collector past its 300M limit. Headers come from a single inline-map
   variable rather than a name/value pair, since an empty header name is not
   valid to send.
3. Restate `host_metrics.root_path` in each config. The receiver leaves the
   metrics pipeline and never starts, but the collector validates unused
   component config, so the base config's `/hostfs` path breaks startup once the
   mount is gone.
4. Write the HTTP config: the same shape with an `otlphttp/external` exporter
   and an explicit `encoding: proto`.
5. Write the `both` config: both exporters listed in every pipeline.
6. In all three, restate the pipeline lists in full, since the collector
   replaces arrays rather than merging them:
   - `traces`: exporters become the external exporter(s) plus `span_metrics`;
     `debug` is dropped.
   - `metrics`: receivers become
     `[docker_stats, http_check/frontend-proxy, nginx, otlp, redis, postgresql, prometheus/ad, span_metrics]`
     — that is the base list minus `host_metrics`; exporters become the external
     exporter(s).
   - `logs` and `profiles`: exporters become the external exporter(s).
7. Leave `src/otel-collector/otelcol-config-extras.yml` untouched so it stays
   available as the user-facing customisation seam.

## Acceptance criteria

- `otelcol validate` (or a collector start with the config) succeeds for each of
  the three files layered on the base config.
- With a local sink, all of traces, metrics and logs arrive; nothing is written
  by the `debug` exporter.
- `host_metrics` no longer appears in the resolved metrics pipeline.
- `make yamllint` and `make checklicense` pass.
