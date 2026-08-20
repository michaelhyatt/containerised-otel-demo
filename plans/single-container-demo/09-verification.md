# Task 09 — End-to-end verification

Affected files: none (verification only); findings feed Tasks 02, 06, 08.

Depends on: 01–08.

## Goal

Prove all four requirements: service set, export over both protocols, load
generation, failure simulation.

## Steps

1. Stand up a throwaway sink on the host: an OTLP collector container with
   `otlp` receivers on 4317/4318 and a `debug` (or `file`) exporter.
2. Address the sink correctly. The inner containers cannot resolve
   `host.docker.internal`: `host-gateway` inside the outer container resolves to
   the inner bridge gateway, which is the outer container itself, not the host.
   Use the host's routable IP in `OTLP_EXPORT_ENDPOINT_*`, or add an
   `extra_hosts` entry on the inner collector pointing at that IP. Document
   whichever recipe is chosen.
3. Run once with `OTLP_EXPORT_PROTOCOL=grpc`, once with `http`, once with
   `both`. For each, confirm at the sink:
   - traces from frontend, checkout, cart, payment, product-catalog, and the
     `frontend-proxy` Envoy spans;
   - metrics including `span_metrics` output, `docker_stats`, the `prometheus/ad`
     scrape and k6's `k6.*` metrics, including the browser-scenario metrics;
   - logs from at least the Ruby, Go and .NET services;
   - no `host_metrics` series, and no `debug` exporter output in collector logs.
4. Confirm the browser scenario is producing telemetry, since it is the only
   path that exercises the frontend's web SDK: look for the
   `browser_add_to_cart` and `browser_change_currency` spans the scenario emits
   (`src/load-generator/script.js:312-331`) and for spans under the
   `frontend-web` service name arriving via `/otlp-http/` through Envoy. Absence
   of `frontend-web` means the browser session is failing silently, most likely
   a Chromium crash under nesting rather than an export problem — check the
   load-generator logs before touching the collector config.
5. Confirm the payload is protobuf, not JSON, on the HTTP path.
6. Confirm the demo's own list of absent components: no jaeger, grafana,
   prometheus, opensearch, opamp, kafka, accounting, fraud-detection,
   telemetry-docs, firepit, agent, mcp or chatbot container exists inside the
   outer container.
7. Exercise failure scenarios (`paymentFailure`, `cartFailure`,
   `productCatalogFailure`) and confirm the resulting errors reach the sink.
8. Kill the sink mid-run and confirm the collector's queue and retry settings
   keep it inside its memory limit, then confirm recovery when the sink returns.
9. Run `make yamllint markdownlint checklicense misspell`.

## Acceptance criteria

- All three protocol modes verified against a live sink.
- Signal coverage confirmed for traces, metrics and logs, including
  browser-scenario spans and `frontend-web` telemetry.
- Container inventory inside the outer container is exactly the 19 kept
  services.
- Repo lint and licence targets pass.
