# Task 05 — Service image provisioning

Affected files: `single-container/Dockerfile`, `single-container/entrypoint.sh`.

Depends on: 04.

## Goal

Get the 19 service images into the inner daemon, with a thin default and an
offline-capable option.

## Steps

1. Default path, pull on first boot: the entrypoint runs `docker compose pull`
   before `up`, and the README documents mounting a volume at the data root so
   the pull happens once. Expect roughly 4–5 GB of image data and several
   minutes on the first start.
2. Optional prebake in a second Dockerfile (`single-container/prebake/`) layered
   on the thin image, driven by `PREBAKE_IMAGES=true` on the Make target. It
   cannot be a build arg in the main Dockerfile: BuildKit requires the insecure
   entitlement for any `RUN --security=insecure`, including one a shell
   conditional would skip, which would burden every ordinary build.
   - Requires a buildx builder created with
     `--buildkitd-flags '--allow-insecure-entitlement security.insecure'` and a
     build invoked with `--allow security.insecure`; the repo already has a
     precedent for a custom builder in `create-multiplatform-builder`.
   - In a `RUN --security=insecure` step, start dockerd against `/demo-docker`,
     run `docker compose pull`, then stop the daemon cleanly so the layer is
     consistent.
   - The data root must not be the base image's `VOLUME /var/lib/docker`, or the
     pulled content is discarded (handled in Task 03).
3. Pin what is pulled: `.env` sets `DEMO_VERSION=latest`, which makes a prebaked
   image silently drift. Document overriding `DEMO_VERSION` to a release tag,
   and prefer that for prebaked builds.
4. Record both variants' image sizes and first-start times in the README.

## Acceptance criteria

- Default build produces an image under ~300 MB and boots successfully with
  registry access.
- Prebaked build boots with the network disabled (`--network none` on the outer
  container still brings the inner stack up; only the external OTLP export
  fails, which is expected).
- Neither variant ever falls back to building a service from source.
