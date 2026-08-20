# Task 04 — Entrypoint and lifecycle

Affected files: `single-container/entrypoint.sh` (new).

Depends on: 03.

## Goal

Start the daemon, bring the stack up, stay in the foreground, and shut down
cleanly so `docker stop` does not leave a wedged daemon or orphaned state.

## Steps

1. Start `dockerd` in the background with `--data-root /demo-docker` and
   `--storage-driver overlay2`, logging to a file so daemon noise does not drown
   the application logs. Fail fast with a clear message if overlay2 is
   unavailable and the daemon falls back to `vfs`, which would be unusably slow
   and disk-hungry.
2. Poll `docker info` until the daemon answers, with a bounded timeout.
3. Validate `OTLP_EXPORT_PROTOCOL` against `grpc`/`http`/`both`, rejecting
   unknown values with a clear error. Compose interpolates the value into the
   collector's `--config` path, so an unchecked typo would surface as a missing
   file deep in the collector's startup instead.
4. Run `docker compose --env-file .env -f compose.yaml -f compose.single-container.yaml up -d --no-build`
   from `/demo`, naming the 19 services explicitly. `--no-build` matters: every
   service carries a `build:` section, so Compose would otherwise try to build
   from source when an image is missing.
5. Stream inner logs to stdout (`docker compose logs -f --tail=0`) so
   `docker logs` on the outer container is useful, and keep the script in the
   foreground.
6. Trap `TERM`/`INT`: `docker compose down --timeout 10 --remove-orphans`, then
   stop dockerd, then exit with the right code.
7. Keep the file `sh`-compatible (Alpine busybox) and start it with the
   `#!/bin/sh` plus licence header that `.licenserc.json` requires.

## Acceptance criteria

- `docker run --privileged -p 8080:8080 otel-demo-single` reaches a working UI
  on `http://localhost:8080` with no manual steps.
- `docker logs` shows inner service logs.
- `docker stop` returns within the timeout and leaves no `vfs` fallback warning
  in the daemon log.
- An invalid `OTLP_EXPORT_PROTOCOL` exits non-zero with a readable message.
