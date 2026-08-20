# syntax=docker/dockerfile:1-labs
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

# Bakes the demo service images into the single-container image so it starts
# without registry access, at the cost of a much larger image.
#
# RUN --security=insecure is needed to run a nested dockerd during the build, so
# this needs a builder created with the matching entitlement:
#
#   docker buildx create --name otel-demo-insecure --use \
#     --buildkitd-flags '--allow-insecure-entitlement security.insecure'
#   docker buildx build --allow security.insecure \
#     -f single-container/prebake/Dockerfile --load -t otel-demo-single:prebaked .
#
# Kept separate from the main Dockerfile so the default build needs no
# entitlement: BuildKit demands it for any insecure RUN, even one that a shell
# conditional would skip.

ARG BASE_IMAGE=otel-demo-single:latest
FROM ${BASE_IMAGE}

RUN --security=insecure /usr/local/bin/entrypoint.sh prebake

ENV SKIP_PULL="true"
