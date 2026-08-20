# Task 07 — Makefile targets

Affected files: `Makefile`.

Depends on: 03, 04.

## Goal

Match the existing `start-*` / `stop` ergonomics so the single-container mode is
discoverable alongside the other run modes.

## Steps

1. Add `build-single-container`, honouring a `PREBAKE_IMAGES` variable and
   defaulting to the thin build.
2. Add `start-single-container`: `docker run -d --privileged --name otel-demo-single --memory=4g`
   with the port publications from the design doc, passing the `OTLP_EXPORT_*`
   variables through from the environment, and echo the reachable URLs the way
   the existing targets do.
3. Add `stop-single-container`: stop and remove the container.
4. Keep the existing `DOCKER_COMPOSE_FILES_*` variables untouched; the new
   targets do not participate in the Compose layering used by the other modes.

## Acceptance criteria

- `make build-single-container && make start-single-container` gives a working
  demo, and `make stop-single-container` removes it.
- `make start` and the other existing targets are unchanged in behaviour.
- `make checklicense` still passes.
