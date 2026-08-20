# Design Doc: single-container OpenTelemetry Demo

Parent plan. Sub-tasks live in `plans/single-container-demo/NN-*.md` and are
ordered; later tasks assume earlier ones are merged.

## Context

The demo currently runs as ~28 containers across four Compose layers and
declares roughly 6.9 GB of memory limits under `make start`. We want one
container that a person can `docker run` with an OTLP destination and get the
full application, its load generator and its failure-injection controls, with no
bundled monitoring backends and the smallest practical footprint.

## Requirements

Functional:

- One image, one `docker run`, whole demo inside it.
- No Jaeger, Grafana, Prometheus, OpenSearch, OpAMP, Firepit, Kafka group or
  agentic layer. Collector plus the application services only.
- All four signals leave the collector as OTLP protobuf to an external
  destination, selectable as gRPC, HTTP, or both simultaneously.
- k6 load generator runs both its HTTP and its headless-browser scenario, and
  its VU count stays runtime-adjustable.
- Failure simulation (the 15 flagd flags) is reachable and toggleable from
  outside the container.

Non-functional:

- Steady-state RSS of the outer container under ~2.5 GB; declared limits under
  ~2.9 GB. The k6 browser scenario stays enabled, so headless Chromium is part
  of the budget.
- No edits to service source code, and no edits to `compose.yaml`,
  `compose.observability.yaml` or `src/otel-collector/otelcol-config.yml`, so
  the fork keeps rebasing cleanly on upstream.
- New files pass `make yamllint`, `make markdownlint`, `make checklicense`.

## Research summary

See `research/2026-08-20-single-container-demo.md`. The load-bearing findings:
the monitoring backends already live in their own Compose layer and
`make start-minimal-no-o11y` already runs the target service set; the collector's
base config exports to `debug` only and ships a documented override seam;
failure simulation and load-generator concurrency are both flagd flags served
through Envoy at `/feature` and `/flagservice`; every service image is published
multi-arch on GHCR.

## Chosen approach

Proposal 1 from `research/2026-08-20-single-container-proposals.md`:
Docker-in-Docker running the existing core Compose layer, with all
customisation in override files. Rejected: minikube/k3s in a container, which
spends 1–1.5 GB on a control plane the request has no use for and adds an
external Helm chart dependency.

## Design

### Architecture

```text
docker run --privileged -p 8080:8080 otel-demo-single
└─ outer container (docker:dind, ~2.5 GB limit)
   ├─ dockerd (--data-root /demo-docker, overlay2)
   ├─ entrypoint.sh: start dockerd → wait → compose up → wait/trap
   └─ inner compose project "opentelemetry-demo" (19 services)
      ├─ frontend-proxy (Envoy) :8080  ── published to the host
      │    ├─ /            frontend
      │    ├─ /feature     flagd-ui        (failure sim + VU control)
      │    ├─ /flagservice flagd           (scripted flag changes)
      │    └─ /otlp-http/  collector HTTP  (browser telemetry)
      ├─ application services + valkey + postgres + flagd
      ├─ load-generator (k6 HTTP + headless-Chromium browser scenario)
      └─ otel-collector ──OTLP protobuf gRPC and/or HTTP──▶ external destination
```

### Key changes

| Component | Change | Notes |
|---|---|---|
| `compose.single-container.yaml` (new) | Trim service set, shrink limits, fix host ports | Uses `!reset`/`!override` merge tags; never touches `compose.yaml` |
| `src/otel-collector/otelcol-config-export-{grpc,http,both}.yml` (new) | External OTLP exporters; drop `debug`; drop `host_metrics` from the metrics pipeline | Selected by `OTEL_COLLECTOR_EXPORT_CONFIG` |
| `single-container/Dockerfile` (new) | `docker:dind` base carrying compose files, `.env`, flagd flags, collector configs | Optional prebake of service images |
| `single-container/entrypoint.sh` (new) | dockerd lifecycle, readiness wait, `compose up`, signal handling | |
| `.env` | Export destination and protocol variables | Additive only |
| `src/flagd/demo.flagd.json` | `loadGeneratorVUs` default variant `5` → `2` | Needed because the flag wins over the env default |
| `Makefile` | `build-single-container`, `start-single-container`, `stop-single-container` | |
| `single-container/README.md` (new) | Usage, endpoints, tuning, limitations | |

### Service set

Kept (19): ad, cart, checkout, currency, email, frontend, frontend-proxy,
image-provider, load-generator, payment, product-catalog, quote, recommendation,
shipping, flagd, flagd-ui, astronomy-db, valkey-cart, otel-collector.

Dropped: telemetry-docs (documentation site, 100M, and the only reason to keep
it is a `depends_on` in `frontend-proxy`), plus everything in the observability,
full, profiling and agent layers by simply not loading those files.

### Footprint budget

| Change | Saving |
|---|---|
| Observability layer never loaded | 2664M |
| Full layer (Kafka group) never loaded | 1080M |
| telemetry-docs dropped | 100M |
| recommendation 500M → 300M | 200M |
| otel-collector 400M → 300M | 100M |
| flagd-ui 200M → 150M | 50M |
| `host_metrics` receiver and `/hostfs` mount removed | CPU, mostly the `process` scraper |
| `debug` exporter removed from all pipelines | CPU and log volume |
| `loadGeneratorVUs` default 5 → 2 | CPU |
| `dockerd` added | −150M |
| load-generator kept at 512M with the browser scenario on | 0 (deliberate) |

Declared limits land near 2.7 GB; expected steady RSS 1.8–2.2 GB. Run the outer
container with `--memory=4g` and document 3.5 GB as the floor.

The k6 browser scenario is kept on purpose: it is the only source of real
browser-side telemetry in the demo, exercising the frontend's web SDK and the
`/otlp-http/` ingest path through Envoy. It is also the single largest remaining
cost — one headless Chromium session plus its renderer processes — which is why
the load generator keeps its full 512M limit while other services shrink.
Chromium in a nested container needs the existing
`K6_BROWSER_ARGS=no-sandbox,disable-dev-shm-usage` (`compose.yaml:435-436`);
without `disable-dev-shm-usage` the renderer crashes against the default 64 MB
`/dev/shm`.

### External interface

| Host port | Purpose | Required |
|---|---|---|
| 8080 | Demo UI, `/feature`, `/flagservice`, `/otlp-http` | yes |
| 8013 | flagd gRPC/HTTP flag API | optional |
| 8016 | flagd OFREP, for scripted failure injection | optional |
| 10000 | Envoy admin | optional |
| 4317/4318 | inner collector OTLP, so host apps can feed the demo collector | optional |

Optional bind mount of a host directory over `/demo/src/flagd` so flag state
survives restarts and can be edited from the host.

### Export configuration

| Variable | Meaning |
|---|---|
| `OTLP_EXPORT_PROTOCOL` | `grpc`, `http`, or `both`; interpolated straight into the collector's `--config` path, so it is the only selector |
| `OTLP_EXPORT_ENDPOINT_GRPC` | host:port for the OTLP/gRPC exporter |
| `OTLP_EXPORT_ENDPOINT_HTTP` | base URL for the OTLP/HTTP exporter |
| `OTLP_EXPORT_HEADERS` | inline map of headers, e.g. `{"authorization": "Bearer abc"}`; `{}` for none |
| `OTLP_EXPORT_INSECURE` | skip TLS verification |

Because the collector replaces rather than appends arrays, each export config
restates the full pipeline exporter list. Traces keep `span_metrics`; `debug` is
dropped everywhere.

The endpoints default to `otlp-destination-not-configured`, which fails DNS
resolution and names itself in the collector's retry logs. A localhost default
would have been worse than useless: the collector would export into its own
receivers and loop.

Each export config also has to restate `host_metrics.root_path`. The receiver is
removed from the metrics pipeline and never starts, but the collector validates
the config of unused components, so the base config's `/hostfs` path fails
startup once this layer drops that mount.

## Testing plan

- Build and boot the outer container; confirm all 19 inner services reach
  running/healthy.
- Point the demo at a throwaway collector on the host running `debug`, once per
  protocol mode, and confirm traces, metrics and logs all arrive with the
  expected `service.name` set.
- Toggle `paymentFailure` through `/feature` and confirm error spans appear at
  the sink; change `loadGeneratorVUs` and confirm k6 restarts.
- Record `docker stats` steady state and compare against `make start`.
- `make yamllint markdownlint checklicense`.

## Rollout

Additive: nothing existing changes behaviour except the `loadGeneratorVUs`
default. `make start` and friends keep working. Rollback is deleting the new
files and reverting the flag default.

## Open questions

- [ ] Prebaked images (self-contained, ~4–5 GB image) or pull-on-first-boot
      (~250 MB image, needs GHCR access and a slow first start)? Plan carries
      both, defaulting to pull-on-first-boot with prebake behind a build arg.
- [ ] Is `--privileged` acceptable in the target environment, or should the
      rootless dind variant be the default?
- [ ] Keep telemetry-docs after all? It is one line in the override file.
