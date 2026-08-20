# Task 03 — Outer image

Affected files: `single-container/Dockerfile` (new),
`single-container/.dockerignore` or root `.dockerignore` additions.

Depends on: 01, 02.

## Goal

A `docker:dind`-based image that carries everything the inner Compose project
needs, built from the repo root as context.

## Steps

1. Base on a pinned `docker:<version>-dind` (Alpine). It already ships the
   Compose plugin at `/usr/local/libexec/docker/cli-plugins/docker-compose`;
   assert this at build time with `docker compose version` so a base-image
   change fails the build rather than the run.
2. Copy into `/demo` only what the inner project reads at runtime:
   `compose.yaml`, `compose.single-container.yaml`, `compose.extras.yaml`,
   `.env`, `src/flagd/`, `src/otel-collector/*.yml`, `src/postgresql/init.sql`,
   `otel-config.yml`. These are bind-mount sources for the inner containers and
   resolve against the outer container's filesystem, because that is where the
   inner dockerd runs.
3. Set `DOCKER_TLS_CERTDIR=""` so dind skips generating TLS material for a
   daemon only ever reached over its local socket.
4. Use a data root outside the base image's `VOLUME /var/lib/docker`, e.g.
   `/demo-docker`, so that image content baked in Task 05 survives into a layer.
5. `EXPOSE` 8080, 10000, 8013, 8016, 4317, 4318 for documentation value.
6. Add a `HEALTHCHECK` that probes `http://127.0.0.1:8080/` with busybox wget,
   with a start period long enough for the inner stack (180s or more).
7. Trim the build context: the repo root includes large service source trees.
   Extend `.dockerignore` or add a dedicated ignore file so the context stays
   small; measure the transferred context before and after.

## Acceptance criteria

- `docker build -f single-container/Dockerfile -t otel-demo-single .` succeeds
  on arm64 and amd64.
- Build context transfer is under ~50 MB.
- `make checklicense` passes (the file must be named `Dockerfile` inside
  `single-container/` for the licence glob to match).
