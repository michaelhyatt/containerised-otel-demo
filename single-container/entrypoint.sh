#!/bin/sh
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

set -eu

DEMO_DIR="${DEMO_DIR:-/demo}"
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/demo-docker}"
DOCKERD_LOG="${DOCKERD_LOG:-/var/log/dockerd.log}"
DOCKERD_TIMEOUT_SECONDS="${DOCKERD_TIMEOUT_SECONDS:-60}"
OTLP_EXPORT_PROTOCOL="${OTLP_EXPORT_PROTOCOL:-grpc}"
SKIP_PULL="${SKIP_PULL:-false}"
ALLOW_VFS="${ALLOW_VFS:-false}"

# The demo services started inside this container. telemetry-docs and the
# observability, Kafka, profiling and agent layers are deliberately absent, so
# the list is explicit rather than "everything in the Compose file".
SERVICES="ad astronomy-db cart checkout currency email flagd flagd-ui frontend
frontend-proxy image-provider load-generator otel-collector payment
product-catalog quote recommendation shipping valkey-cart"

DOCKERD_PID=""
LOGS_PID=""
shutting_down=false

log() {
  echo "single-container: $*"
}

fail() {
  echo "single-container: $*" >&2
  exit 1
}

compose() {
  docker compose \
    --env-file "${DEMO_DIR}/.env" \
    -f "${DEMO_DIR}/compose.yaml" \
    -f "${DEMO_DIR}/compose.single-container.yaml" \
    "$@"
}

validate_protocol() {
  case "${OTLP_EXPORT_PROTOCOL}" in
    grpc | http | both) ;;
    *)
      fail "OTLP_EXPORT_PROTOCOL must be grpc, http or both (got '${OTLP_EXPORT_PROTOCOL}')"
      ;;
  esac
  export OTLP_EXPORT_PROTOCOL
}

start_dockerd() {
  log "starting dockerd (data root ${DOCKER_DATA_ROOT}, log ${DOCKERD_LOG})"
  # Via the base image's entrypoint rather than dockerd directly: it sets up
  # cgroup v2 nesting, without which inner containers fail to start with
  # "cannot enter cgroupv2 ... with domain controllers".
  dockerd-entrypoint.sh dockerd --data-root "${DOCKER_DATA_ROOT}" \
    --storage-driver overlay2 >>"${DOCKERD_LOG}" 2>&1 &
  DOCKERD_PID=$!

  waited=0
  while ! docker info >/dev/null 2>&1; do
    if ! kill -0 "${DOCKERD_PID}" 2>/dev/null; then
      tail -n 20 "${DOCKERD_LOG}" >&2 || true
      fail "dockerd exited during startup; the container most likely needs --privileged"
    fi
    if [ "${waited}" -ge "${DOCKERD_TIMEOUT_SECONDS}" ]; then
      tail -n 20 "${DOCKERD_LOG}" >&2 || true
      fail "dockerd did not become ready within ${DOCKERD_TIMEOUT_SECONDS}s"
    fi
    sleep 1
    waited=$((waited + 1))
  done

  driver=$(docker info --format '{{.Driver}}')
  if [ "${driver}" = "vfs" ] && [ "${ALLOW_VFS}" != "true" ]; then
    fail "dockerd fell back to the vfs storage driver, which is too slow and too
large for this image. Check that the host supports nested overlay2, or set
ALLOW_VFS=true to proceed anyway."
  fi
  log "dockerd ready (storage driver ${driver})"
}

stop_dockerd() {
  [ -n "${DOCKERD_PID}" ] || return 0
  kill -TERM "${DOCKERD_PID}" 2>/dev/null || true
  waited=0
  while kill -0 "${DOCKERD_PID}" 2>/dev/null && [ "${waited}" -lt 20 ]; do
    sleep 1
    waited=$((waited + 1))
  done
}

# When the data root is a volume, so are the container definitions in it, and
# their restart policies bring the previous run back up the moment dockerd
# starts. Clear them before pulling so nothing runs with stale configuration
# during the window before compose reconciles.
cleanup_previous_run() {
  [ -n "$(docker ps --all --quiet)" ] || return 0
  log "removing containers left over from a previous run"
  compose down --remove-orphans --timeout 5 || true
}

pull_images() {
  [ "${SKIP_PULL}" = "true" ] && return 0
  log "pulling service images (first start can take several minutes)"
  # --policy missing keeps a prebaked image from re-pulling on every start.
  # shellcheck disable=SC2086
  compose pull --quiet --policy missing ${SERVICES}
}

on_term() {
  [ "${shutting_down}" = "true" ] && return 0
  shutting_down=true
  log "shutting down"
  [ -n "${LOGS_PID}" ] && kill -TERM "${LOGS_PID}" 2>/dev/null || true
  # Stopping 19 services still takes longer than Docker's default 10s grace, so
  # the container needs --stop-timeout; see single-container/README.md.
  compose down --timeout 5 --remove-orphans || true
  stop_dockerd
  exit 0
}

# Build-time mode: pull the service images into the data root so they are baked
# into an image layer, then leave the daemon stopped.
prebake() {
  validate_protocol
  start_dockerd
  cd "${DEMO_DIR}"
  SKIP_PULL=false pull_images
  stop_dockerd
  log "prebake complete"
}

run() {
  validate_protocol
  start_dockerd
  trap on_term TERM INT
  cd "${DEMO_DIR}"

  cleanup_previous_run
  pull_images

  log "starting the demo (export protocol ${OTLP_EXPORT_PROTOCOL})"
  # shellcheck disable=SC2086
  compose up --detach --no-build --remove-orphans ${SERVICES}

  compose logs --follow --tail=0 &
  LOGS_PID=$!

  log "demo is up; the UI is on port 8080"
  while kill -0 "${DOCKERD_PID}" 2>/dev/null; do
    # Sleeping in the background and waiting on it keeps signals responsive.
    sleep 5 &
    wait "$!" || true
  done
}

case "${1:-run}" in
  prebake) prebake ;;
  run) run ;;
  *) exec "$@" ;;
esac
