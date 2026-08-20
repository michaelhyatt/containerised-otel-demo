# Solution Proposals: single-container OpenTelemetry Demo

Context:

- Request: run the whole demo inside one container, evaluating Docker Compose
  in a container versus minikube in a container; strip Jaeger, Grafana and
  OpenSearch (and the rest of the monitoring stack) leaving only the collector
  and the demo services; export all signals via OTLP protobuf over both HTTP and
  gRPC to an external destination; keep the load generator and failure
  simulation reachable from outside the container; minimise memory and CPU.
- Research source: `research/2026-08-20-single-container-demo.md` — Compose
  layering, service limits, collector export seam, k6/flagd control paths.

## Proposal 1 — Docker-in-Docker running the existing Compose core layer

Overview: build one image on `docker:dind` that carries the repo's compose
files, `.env`, flagd flags and collector configs, plus every demo service image
pre-loaded into the daemon's data root. An entrypoint starts `dockerd`, waits
for readiness, and runs `docker compose -f compose.yaml -f compose.single-container.yaml up`
against the core layer only. The observability layer is simply never loaded, so
Jaeger, Grafana, Prometheus, OpenSearch and OpAMP never exist — this reuses the
seam the repo already maintains (`Makefile:309-316` already does exactly this
outside a container).

Key changes:

- New `single-container/Dockerfile`, `single-container/entrypoint.sh`,
  `compose.single-container.yaml` (footprint and port overrides),
  `src/otel-collector/otelcol-config-export-{grpc,http,both}.yml`.
- `.env` additions for the external destination and export protocol selection.
- New Makefile targets for build/run/stop.

Trade-offs:

- Requires `--privileged` (or the rootless dind variant with `/dev/fuse` and
  relaxed seccomp/apparmor), which is the single biggest downside.
- Nested overlay2 adds a small I/O overhead and `dockerd` costs roughly
  100–150 MB RSS.
- Everything else is upside: zero changes to service code, all 15 failure flags
  and the k6 flag-driven VU control keep working unmodified, the per-service
  `deploy.resources.limits` stay meaningful because real cgroups still apply,
  and the whole thing tracks upstream because the customisation lives in
  override files rather than edits to `compose.yaml`.

Validation: `docker stats` on the outer container versus a `make start`
baseline; a throwaway collector with a `debug`/`file` exporter as the external
destination, exercised once in gRPC mode and once in HTTP mode; toggling
`paymentFailure` at `/feature` and confirming error spans reach the sink;
changing `loadGeneratorVUs` and confirming k6 restarts.

Open questions: whether images should be pre-baked (larger image, offline
capable) or pulled on first boot (thin image, needs registry access).

## Proposal 2 — minikube (or k3s) in a container with the upstream Helm chart

Overview: run a single-node Kubernetes inside the container and deploy the
`opentelemetry-demo` Helm chart with the observability components disabled via
values. minikube's docker driver would itself need a Docker daemon inside the
container, so this is Kubernetes nested inside Docker-in-Docker; `k3s` in a
privileged container is the lighter variant of the same idea.

Key changes: a Kubernetes-flavoured image (kubelet/containerd or k3s plus
`kubectl` and `helm`), a values file disabling jaeger/grafana/prometheus/
opensearch and pointing the collector at the external destination, an ingress or
`hostPort` mapping for the frontend proxy, and a new dependency on
`open-telemetry/opentelemetry-helm-charts` since this repo contains no manifests.

Trade-offs:

- Directly contradicts the "minimise memory and CPU" requirement: the control
  plane (apiserver, etcd, scheduler, controller-manager, kubelet, CoreDNS,
  kube-proxy) costs roughly 1–1.5 GB RSS and a continuous CPU baseline before a
  single demo pod starts.
- Still needs `--privileged`, so it does not even buy back the security
  trade-off of Proposal 1.
- The chart version drifts independently of this repo, and none of the repo's
  `.env`, flagd bind mount or collector override plumbing applies, so the load
  generator and failure-flag wiring would have to be re-derived from chart
  values.
- The only real benefit — Kubernetes-native semantics such as probes, HPA and
  operator-based instrumentation — is not part of the request.

Validation: same telemetry checks as Proposal 1, plus chart-value regression
checks on every chart bump.

Open questions: which chart version matches this repo's service versions, and
how to expose flagd-ui and the frontend proxy without an ingress controller.

## Choice

**Proposal 1.** It is strictly cheaper on both memory and CPU, reuses the
layering and override seams the repo already maintains, keeps the load generator
and failure-flag mechanics byte-for-byte identical to the supported demo, and
adds no external chart dependency. Proposal 2's only advantage is Kubernetes
fidelity, which the request does not ask for and which costs roughly the memory
budget of the entire trimmed application.
