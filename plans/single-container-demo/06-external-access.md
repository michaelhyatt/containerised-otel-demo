# Task 06 — External access to load generation and failure simulation

Affected files: `compose.single-container.yaml`, `src/flagd/demo.flagd.json`,
`single-container/README.md`.

Depends on: 01, 04.

## Goal

Make every control the demo offers usable from the host, and make the load
generator's default concurrency actually low.

## Steps

1. Confirm the published surface works end to end from the host: `/` (frontend),
   `/feature` (flagd-ui, including the websocket upgrade Envoy is configured
   for, and the failure-scenario scheduler added in `52af6226`),
   `/flagservice/` (flagd's own API, for scripted toggles), and `/otlp-http/`
   (browser telemetry from the host's browser, which is why
   `PUBLIC_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` must stay `http://localhost:8080/...`).
2. Publish flagd's OFREP port (8016) so external automation can read flag state
   the same way `src/load-generator/entrypoint.sh` does.
3. Lower the load-generator default: `src/load-generator/entrypoint.sh` treats
   `LOAD_GENERATOR_VUS` only as a fallback and prefers flagd's
   `loadGeneratorVUs`, whose default variant is `5`. Change that default variant
   to `2` in `src/flagd/demo.flagd.json`; changing the env var alone has no
   effect. This flag drives only the HTTP scenario
   (`src/load-generator/script.js:20-40`); the browser scenario runs a single
   session regardless, so lowering it does not disable browser traffic.
4. Document the optional bind mount of a host directory over `/demo/src/flagd`
   so flag edits persist across container restarts, noting that flagd and
   flagd-ui share that directory.
5. Verify the `kafkaQueueProblems` flag is documented as inert in this
   configuration, since the Kafka group is not deployed.

## Acceptance criteria

- Toggling `paymentFailure` at `http://localhost:8080/feature` changes observed
  behaviour and shows up in exported telemetry.
- Setting `loadGeneratorVUs` through the UI restarts k6 within ~10s (visible in
  the load-generator logs).
- A `curl` against `http://localhost:8016/ofrep/v1/evaluate/flags/loadGeneratorVUs`
  from the host returns the current value.
- Fresh container starts with 2 HTTP VUs and a running browser scenario.
