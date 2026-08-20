# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

FROM docker:29-dind@sha256:12e683a161823b2a839aeea999b9d960e6e1f9a97b1679ad6b441982e2d9cf07

# Fail the build rather than the run if a base image bump ever drops the plugin.
RUN docker compose version

# The daemon is only reached over its local socket, so skip TLS material.
ENV DOCKER_TLS_CERTDIR=""
# Deliberately not /var/lib/docker: the base image declares that a VOLUME, and
# anything written there during a build is discarded instead of committed.
ENV DOCKER_DATA_ROOT="/demo-docker"

WORKDIR /demo

# Only what the inner Compose project reads. Its bind mounts resolve against
# this filesystem, because the daemon serving them runs here too.
COPY compose.yaml compose.single-container.yaml compose.extras.yaml .env otel-config.yml ./
COPY src/flagd/ ./src/flagd/
COPY src/otel-collector/ ./src/otel-collector/
COPY src/postgresql/init.sql ./src/postgresql/init.sql
COPY --chmod=755 single-container/entrypoint.sh /usr/local/bin/entrypoint.sh

# frontend-proxy, Envoy admin, flagd, flagd OFREP, collector gRPC, collector HTTP
EXPOSE 8080 10000 8013 8016 4317 4318

HEALTHCHECK --interval=15s --timeout=5s --start-period=600s --retries=5 \
    CMD wget -q --spider http://127.0.0.1:8080/ || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
