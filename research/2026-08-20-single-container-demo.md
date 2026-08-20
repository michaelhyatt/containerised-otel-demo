# Research: running the OpenTelemetry Demo in a single container

Date: 2026-08-20
Scope: how the demo is composed today, which parts are monitoring backends, how
telemetry is exported, how load generation and failure simulation are driven,
and what the current resource footprint is.

## High-level summary

The demo is already split into layered Compose files: `compose.yaml` holds the
core application plus the OTel Collector, and the monitoring backends (Jaeger,
Grafana, Prometheus, OpenSearch, OpAMP) live entirely in a separate
`compose.observability.yaml` layer. A Makefile target, `start-minimal-no-o11y`,
already runs exactly the service set the request describes. The base collector
config exports to the `debug` exporter only and provides an explicitly
documented customisation seam (`otelcol-config-extras.yml`) for adding
exporters, so pointing the demo at an external OTLP destination requires no
changes to upstream collector files. Load generation is a k6 container whose
concurrency is driven at runtime by a flagd feature flag, and all failure
simulation is likewise flagd feature flags, editable through the flagd-ui that
Envoy serves at `/feature`. There are no Kubernetes manifests in this repo (the
Helm chart lives in `opentelemetry-helm-charts`), and there is no existing
Docker-in-Docker, minikube, k3s or single-container tooling anywhere in the
tree.

## Compose layering

`compose.yaml:4-13` documents the layering, and `Makefile:19-33` wires it up:

| Layer | File | Contents |
|---|---|---|
| Core | `compose.yaml` | 20 services: the application, flagd/flagd-ui, Valkey, Postgres, telemetry-docs, otel-collector |
| Full | `compose.full.yaml` | Kafka, accounting, fraud-detection; patches `checkout` and the collector |
| Observability | `compose.observability.yaml` | Jaeger, Grafana, Prometheus, OpenSearch, OpAMP server; patches the collector and frontend-proxy |
| Profiling | `compose.profiling.yaml` | eBPF profiler, Firepit |
| Agent | `compose.agent.yaml` | agent, mcp, chatbot |
| Extras | `compose.extras.yaml` | intentionally empty fork seam, always loaded last |

Existing start targets (`Makefile:278-339`). `start-minimal-no-o11y`
(`Makefile:309-316`) runs `compose.yaml` + `compose.extras.yaml` only, i.e. core
services with no monitoring backends — the exact service set requested.

## Services and declared memory limits

Core (`compose.yaml`), all limits are `deploy.resources.limits.memory`:

| Service | Limit | Notes |
|---|---|---|
| ad | 300M | Java agent, `compose.yaml:32-76` |
| cart | 160M | .NET, `compose.yaml:79-111` |
| checkout | 20M | Go, `GOMEMLIMIT=16MiB`, `compose.yaml:114-171` |
| currency | 20M | C++, `compose.yaml:174-208` |
| email | 100M | Ruby, `compose.yaml:211-244` |
| frontend | 250M | Next.js, `compose.yaml:247-311` |
| frontend-proxy | 90M | Envoy, publishes 8080/10000, `compose.yaml:314-373` |
| image-provider | 120M | nginx, `compose.yaml:376-406` |
| load-generator | 512M | k6 + headless Chromium, `compose.yaml:409-451` |
| payment | 140M | Node, `compose.yaml:454-500` |
| product-catalog | 20M | Go, needs Postgres, `compose.yaml:503-548` |
| quote | 40M | PHP, `compose.yaml:551-584` |
| recommendation | 500M | Python, sized for the cache failure flag, `compose.yaml:587-626` |
| shipping | 20M | Rust, `compose.yaml:629-669` |
| flagd | 75M | `compose.yaml:676-700` |
| flagd-ui | 200M | Elixir/Phoenix, `compose.yaml:703-738` |
| telemetry-docs | 100M | Weaver docs site, `compose.yaml:741-767` |
| astronomy-db | 80M | Postgres 18, `compose.yaml:770-791` |
| valkey-cart | 20M | `compose.yaml:794-811` |
| otel-collector | 400M | `GOMEMLIMIT=160MiB`, `compose.yaml:820-855` |

Core total: **3167M** of declared limits.

Observability layer adds 2664M (jaeger 1200M `compose.observability.yaml:13-40`,
opensearch 1024M `:94-136`, prometheus 200M `:65-91`, grafana 175M `:43-62`,
opamp-server 65M `:141-166`). The full layer adds 1080M (kafka 620M, fraud 300M,
accounting 160M). The default `make start` therefore declares ~6.9G of limits.

## Telemetry export path

- Base collector config `src/otel-collector/otelcol-config.yml`. Receivers:
  `otlp` (gRPC + HTTP with CORS, `:11-25`), `http_check/frontend-proxy`,
  `nginx`, `docker_stats` (needs `/var/run/docker.sock`), `redis`, `postgresql`,
  `prometheus/ad`, and `host_metrics` with cpu/disk/load/filesystem/memory/
  network/paging/processes/process/system scrapers (`:75-143`, reads `/hostfs`).
- Exporters in the base config: `debug` only (`:145-146`). Pipelines for traces,
  metrics, logs and profiles all export to `debug` (`:247-264`). The `profiles`
  pipeline requires the `--feature-gates=service.profilesSupport` flag that
  `compose.yaml:831` passes.
- `src/otel-collector/otelcol-config-extras.yml` is an empty, documented fork
  seam loaded last (`compose.yaml:830`), and its header explains that the
  collector **replaces** arrays rather than appending, so pipeline exporter
  lists must be repeated in full when overriding.
- Services reach the collector through a mix of env styles: several use
  `OTEL_EXPORTER_OTLP_ENDPOINT` from `.env:39` (gRPC 4317), others hardcode
  `http://${OTEL_COLLECTOR_HOST}:${OTEL_COLLECTOR_PORT_HTTP}` with
  `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf` (checkout, shipping, email, quote,
  flagd, flagd-ui, load-generator, ad). Both OTLP protobuf transports are
  therefore already exercised on the ingest side.
- Browser telemetry goes through Envoy: `PUBLIC_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:8080/otlp-http/v1/traces`
  (`.env:40`) routed by `src/frontend-proxy/envoy.tmpl.yaml:39-40` to the
  collector's HTTP receiver.
- The collector's own self-telemetry is sent OTLP http/protobuf back into itself
  (`src/otel-collector/otelcol-config.yml:265-281`).

## Load generation

- `src/load-generator/Dockerfile` builds a custom k6 (xk6 with a local
  `xk6-otel` extension) on top of `grafana/k6:2.2.0-with-browser`.
- `compose.yaml:422-437` sets `K6_BROWSER_ENABLED=true`, which activates the
  headless-Chromium browser scenario in `src/load-generator/script.js:20-40`;
  the scenario is opt-in and keyed purely off that env var
  (`src/load-generator/script.js:17-18`).
- Concurrency is not fixed at deploy time: `src/load-generator/entrypoint.sh`
  polls flagd's OFREP endpoint every 10s for the `loadGeneratorVUs` flag and
  restarts k6 when it changes (`entrypoint.sh:31-62`).
- k6 targets `K6_TARGET_URL=http://frontend-proxy:8080` (`.env:104`) and exports
  its own metrics over OTLP http/protobuf (`compose.yaml:432-437`).

## Failure simulation

All scenarios are flagd flags in `src/flagd/demo.flagd.json`: `adFailure`,
`adHighCpu`, `adManualGc`, `cartFailure`, `emailMemoryLeak`,
`failedReadinessProbe`, `imageSlowLoad`, `intlShippingSlowdown`,
`kafkaQueueProblems` (needs the full layer), `loadGeneratorTraffic`,
`loadGeneratorVUs`, `paymentFailure`, `paymentUnreachable`,
`productCatalogFailure`, `recommendationCacheFailure`. The most recent commit
(`52af6226`) added a scheduler to flagd-ui that turns scenarios on and off
automatically.

Access paths, from `src/frontend-proxy/envoy.tmpl.yaml:59-66`:
`/flagservice/` proxies flagd itself and `/feature` proxies flagd-ui (with
websocket upgrade). flagd and flagd-ui share the `./src/flagd` bind mount
(`compose.yaml:698-699`, `:737-738`), so flag state is a file on disk.

## Frontend proxy coupling to monitoring components

`src/frontend-proxy/envoy.tmpl.yaml` defines `jaeger`, `grafana`, `opamp` and
`profiles` clusters (`:236-275`, `:302-313`) and routes for them (`:41-52`,
`:67-70`). The template is rendered with `envsubst` at container start
(`src/frontend-proxy/Dockerfile:19`), reading values that `.env:167-183`,
`.env:212-218` always define, so the clusters render even when those backends
are absent — STRICT_DNS resolution simply fails lazily and those routes return
5xx. In core-only mode `frontend-proxy` still hard-depends on `telemetry-docs`
and `flagd-ui` being healthy (`compose.yaml:366-372`).

## Build and image distribution

- All service images are published multi-arch (`linux/amd64,linux/arm64`) as
  `ghcr.io/open-telemetry/demo:<tag>-<service>` by
  `.github/workflows/component-build-images.yml:295-303`; `.env:2-4` pins
  `IMAGE_NAME=ghcr.io/open-telemetry/demo` and `DEMO_VERSION=latest`.
- Compose services all carry a `build:` section, so `docker compose up` will
  build locally when an image is missing unless `--no-build` is used.
- License headers are enforced by `make checklicense` via `.licenserc.json`,
  which covers `**/*.{yaml,yml}`, `**/*.sh` and `**/{Dockerfile,Makefile}`.
- Lint targets that gate changes: `make yamllint`, `make markdownlint`,
  `make misspell`, `make checklicense` (`Makefile:48-132`).

## Environment observed

Docker Engine 29.7.2, 12 CPUs, ~28 GiB available to the daemon, `overlayfs`
storage driver, `arm64` host.

## Absent from this repo

- No Kubernetes manifests, kustomize bases or Helm chart (upstream chart lives
  in `open-telemetry/opentelemetry-helm-charts`).
- No Docker-in-Docker, minikube, kind or k3s references anywhere in the tree.
- `README.md` states no explicit host memory/CPU requirement.
