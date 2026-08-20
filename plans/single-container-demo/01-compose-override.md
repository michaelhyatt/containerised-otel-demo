# Task 01 — Compose override for the single-container service set

Affected files: `compose.single-container.yaml` (new).

## Goal

One override file, layered on `compose.yaml` only, that trims the service set,
shrinks the footprint and fixes the host ports the outer container will publish.

## Steps

1. Create the file with the Apache header required by `.licenserc.json`.
2. Drop `telemetry-docs`: it cannot be removed by an overlay, so clear the
   `frontend-proxy` dependency with `depends_on: !override` listing only
   `frontend` and `flagd-ui`, then never name `telemetry-docs` in the
   `docker compose up` service list. Verify with `docker compose config` that it
   is absent from the resolved model; if the merge tag misbehaves on the
   installed Compose version, fall back to keeping the service and note the
   100M cost.
3. Footprint overrides:
   - `load-generator`: left alone. `K6_BROWSER_ENABLED=true` and the 512M limit
     both stay as `compose.yaml:409-451` sets them, because the headless-browser
     scenario is being kept. Do not shrink this limit speculatively; Task 08
     measures it.
   - `recommendation`: 300M.
   - `otel-collector`: 300M.
   - `flagd-ui`: 150M.
4. Collector overrides:
   - `command: !override` with `--config=/etc/otelcol-config.yml`,
     `--config=${OTEL_COLLECTOR_EXPORT_CONFIG}`,
     `--config=/etc/otelcol-config-extras.yml`, and the existing
     `--feature-gates=service.profilesSupport` (the base config's `profiles`
     pipeline fails without it).
   - `volumes: !override` mounting the base config, the three export configs,
     the extras stub and the Docker socket; drop the `${HOST_FILESYSTEM}:/hostfs`
     mount since `host_metrics` is being removed.
5. Give `load-generator` a larger `/dev/shm` (`shm_size: 256m`) unless Task 08
   shows the existing `disable-dev-shm-usage` browser arg is sufficient under
   nesting. Chromium is the one component sensitive to the 64 MB default.
6. Fixed host ports (inside the outer container) via `ports: !override`:
   `frontend-proxy` 8080 and 10000, `flagd` 8013 and 8016, `otel-collector`
   4317 and 4318. Leave every other service on ephemeral ports.

## Acceptance criteria

- `docker compose --env-file .env -f compose.yaml
  -f compose.single-container.yaml config`
  resolves without error, and `frontend-proxy` no longer depends on
  `telemetry-docs`. The service definition itself still appears in the resolved
  model — an override file cannot delete one — so the running set is constrained
  by the explicit service list the entrypoint passes to `up` (Task 04).
- No file under `compose.yaml`, `compose.observability.yaml` or
  `compose.full.yaml` is modified.
- `make yamllint` and `make checklicense` pass.
