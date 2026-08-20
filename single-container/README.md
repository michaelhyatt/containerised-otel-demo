# Single-container demo

Runs the whole OpenTelemetry Demo inside one container and exports every signal
to an OTLP destination you provide. There is no bundled observability stack:
Jaeger, Grafana, Prometheus, OpenSearch and the OpAMP server are not started, and
neither are the Kafka group, the profiling components or the agentic services.

Inside the container, a nested Docker daemon runs the same
[`compose.yaml`](../compose.yaml) the rest of the demo uses, layered with
[`compose.single-container.yaml`](../compose.single-container.yaml).

## How to run

You need Docker with enough room for a privileged container: 4 GB of memory and
about 4 GB of disk for the first image pull. Run the commands from the
repository root.

### 1. Build the image

```bash
make build-single-container
```

That produces `otel-demo-single:latest` (about 135 MB). It does not pull the
demo service images yet.

### 2. Point it at your OTLP destination

Export the destination in the same shell you will use to start the container.
`make start-single-container` forwards these variables into `docker run`.

OTLP/gRPC (host:port, no scheme):

```bash
export OTLP_EXPORT_PROTOCOL=grpc
export OTLP_EXPORT_ENDPOINT_GRPC=otlp.example.com:4317
export OTLP_EXPORT_HEADERS_GRPC='{"authorization": "Bearer <token>"}'
export OTLP_EXPORT_INSECURE=true
```

OTLP/HTTP (base URL, protobuf):

```bash
export OTLP_EXPORT_PROTOCOL=http
export OTLP_EXPORT_ENDPOINT_HTTP=http://otlp.example.com:4318
export OTLP_EXPORT_HEADERS_HTTP='{"authorization": "Bearer <token>"}'
export OTLP_EXPORT_INSECURE=true
```

Both at once, with a different token per endpoint:

```bash
export OTLP_EXPORT_PROTOCOL=both
export OTLP_EXPORT_ENDPOINT_GRPC=otlp.example.com:4317
export OTLP_EXPORT_ENDPOINT_HTTP=http://otlp.example.com:4318
export OTLP_EXPORT_HEADERS_GRPC='{"authorization": "Bearer <grpc-token>"}'
export OTLP_EXPORT_HEADERS_HTTP='{"authorization": "Bearer <http-token>"}'
export OTLP_EXPORT_INSECURE=true
```

Use `OTLP_EXPORT_INSECURE=false` when the destination presents a certificate
you expect to verify. See [Choosing a destination](#choosing-a-destination)
for the full variable list.

### 3. Start the container

```bash
make start-single-container
```

`--privileged` is required: the nested daemon cannot start without it.
`--stop-timeout 60` matters too, because stopping 19 services takes around 30
seconds and Docker's default 10 second grace period kills the container
mid-shutdown.

The first start pulls about 4 GB of service images inside the container and
takes several minutes. Follow it with:

```bash
docker logs -f otel-demo-single
```

You are waiting for `single-container: demo is up; the UI is on port 8080`.
The images are cached in the `otel-demo-single-data` volume, so later starts
take about a minute.

If a previous `otel-demo-single` container is still around, stop it first:

```bash
make stop-single-container
```

### 4. Open the demo

| URL | What you get |
|---|---|
| <http://localhost:8080> | shop UI |
| <http://localhost:8080/feature> | feature flags and failure scenarios |
| <http://localhost:8016> | flagd OFREP, for scripting flags |
| <http://localhost:10000> | Envoy admin |

The load generator starts on its own. After a minute you should see traces,
metrics and logs at your destination, including `frontend-web` spans from the
browser scenario.

### 5. Stop

```bash
make stop-single-container
```

That stops and removes the container. The `otel-demo-single-data` volume is
left in place so the next start does not re-pull the service images.

### Without Make

```bash
docker build -f single-container/Dockerfile -t otel-demo-single:latest .
docker volume create otel-demo-single-data
docker run --detach --privileged --name otel-demo-single \
  --memory=4g --stop-timeout 60 \
  --publish 8080:8080 --publish 10000:10000 \
  --publish 8013:8013 --publish 8016:8016 \
  --publish 4317:4317 --publish 4318:4318 \
  --env OTLP_EXPORT_PROTOCOL \
  --env OTLP_EXPORT_ENDPOINT_GRPC \
  --env OTLP_EXPORT_ENDPOINT_HTTP \
  --env OTLP_EXPORT_HEADERS \
  --env OTLP_EXPORT_HEADERS_GRPC \
  --env OTLP_EXPORT_HEADERS_HTTP \
  --env OTLP_EXPORT_INSECURE \
  --volume otel-demo-single-data:/demo-docker \
  otel-demo-single:latest
```

`make start-single-container` publishes 4317 and 4318, which collides with a
collector already listening on those ports on the host. Drop those two
`--publish` flags if you are running your OTLP destination locally.

## Choosing a destination

| Variable | Default | Meaning |
|---|---|---|
| `OTLP_EXPORT_PROTOCOL` | `grpc` | `grpc`, `http` or `both` |
| `OTLP_EXPORT_ENDPOINT_GRPC` | `otlp-destination-not-configured:4317` | host:port for OTLP/gRPC |
| `OTLP_EXPORT_ENDPOINT_HTTP` | `http://otlp-destination-not-configured:4318` | base URL for OTLP/HTTP |
| `OTLP_EXPORT_HEADERS` | `{}` | inline map of headers sent with every request |
| `OTLP_EXPORT_HEADERS_GRPC` | `${OTLP_EXPORT_HEADERS}` | headers for the gRPC exporter only |
| `OTLP_EXPORT_HEADERS_HTTP` | `${OTLP_EXPORT_HEADERS}` | headers for the HTTP exporter only |
| `OTLP_EXPORT_INSECURE` | `true` | skip TLS verification |

Both transports send OTLP protobuf; the HTTP one sends
`content-type: application/x-protobuf`.

`OTLP_EXPORT_INSECURE` defaults to `true`, which suits the plaintext collector
most people point this at first. Set it to `false` for any destination that is
not on your own machine, or the exporter will not verify its certificate. Note
also that whatever you put in `OTLP_EXPORT_HEADERS` is visible in
`docker inspect`, so treat a token there the way you would any other environment
variable secret.

With a token and TLS:

```bash
docker run ... \
  --env OTLP_EXPORT_PROTOCOL=http \
  --env OTLP_EXPORT_ENDPOINT_HTTP=https://otlp.example.com \
  --env 'OTLP_EXPORT_HEADERS={"authorization": "Bearer <token>"}' \
  --env OTLP_EXPORT_INSECURE=false \
  otel-demo-single:latest
```

`both` sends every signal twice, once per transport, so point the two endpoints
at different destinations unless you want duplicates. Destinations that issue a
separate token per endpoint need `OTLP_EXPORT_HEADERS_GRPC` and
`OTLP_EXPORT_HEADERS_HTTP` rather than the shared `OTLP_EXPORT_HEADERS`.

If the destination is unreachable the demo still runs. The collector queues,
retries and logs the endpoint it cannot reach, which is why the defaults are a
name that fails DNS rather than a localhost address that would make the
collector export into its own receivers.

Anything the variables do not cover goes in
[`otelcol-config-extras.yml`](../src/otel-collector/otelcol-config-extras.yml),
which is loaded last and merges into the exporter definitions.

## What is exposed

| Port | Purpose |
|---|---|
| 8080 | demo UI, `/feature`, `/flagservice/`, `/otlp-http/` |
| 8013 | flagd flag API |
| 8016 | flagd OFREP endpoint |
| 10000 | Envoy admin |
| 4317 / 4318 | the demo's own collector, if you want to feed telemetry into it |

`/jaeger`, `/grafana` and `/telemetry` return 503: those services are
deliberately absent.

## Load generation and failure simulation

The k6 load generator runs both its HTTP scenario and its headless-Chromium
browser scenario. The browser scenario is what produces the `frontend-web`
telemetry and the `browser_add_to_cart` and `browser_change_currency` spans, and
it is also the single most expensive component in the container. To trade it
away on a constrained host, set `K6_BROWSER_ENABLED=false` on the
`load-generator` service.

Failure scenarios are the usual flagd flags, reachable in three ways:

- the UI at `http://localhost:8080/feature`, including the scheduler that turns
  scenarios on and off automatically;
- flagd's API on port 8013 or its OFREP endpoint on 8016, for scripting:

  ```bash
  curl -s -XPOST -H 'Content-Type: application/json' -d '{}' \
    http://localhost:8016/ofrep/v1/evaluate/flags/loadGeneratorVUs
  ```

- a bind mount over the flag file, if you want edits to survive restarts:
  `--volume "$PWD/src/flagd:/demo/src/flagd"`. flagd and flagd-ui share that
  directory and flagd reloads the file when it changes.

`loadGeneratorVUs` defaults to 2 in this repo and only affects the HTTP
scenario. `kafkaQueueProblems` does nothing here, since the Kafka group is not
deployed.

## Footprint

Measured on a 12-core arm64 host, both transports enabled, load generator
running with the browser scenario, after the stack settled:

| | Value |
|---|---|
| Outer container memory | 1.7–2.1 GiB of a 4 GiB limit |
| Outer container CPU | roughly 0.7 cores idle-ish, peaking above 3 cores while the browser scenario works |
| Largest services | ad 220 MiB, load-generator 190 MiB, otel-collector 170 MiB, flagd-ui 150 MiB, frontend 100 MiB |

For comparison, the default `make start` declares 6.75 GiB of memory limits
across 28 services; this mode declares 2.68 GiB across 19.

Where the savings come from: the observability layer (2664M of declared limits)
and the Kafka group (1080M) are never started, telemetry-docs is dropped (100M),
recommendation goes from 500M to 300M, the collector from 400M to 300M and
flagd-ui from 200M to 175M. On the CPU side the collector loses the
`host_metrics` receiver, whose scrapers describe the container rather than the
host, and the `debug` exporter.

The collector sits near 170 MiB with a healthy destination and climbs to around
280 MiB when the destination is down and its queue fills, which is what the
300M limit and the bounded sending queue are sized for.

## Offline images

The default image is about 135 MB and pulls the service images on first start.
To bake them in instead, so the container starts with no registry access:

```bash
docker buildx create --name otel-demo-insecure --use \
  --buildkitd-flags '--allow-insecure-entitlement security.insecure'
make build-single-container PREBAKE_IMAGES=true
```

This needs the insecure entitlement because the build runs a nested daemon to
pull the images. Pin `DEMO_VERSION` in [`.env`](../.env) to a release tag first,
or the baked images silently drift from `latest`.

## Limitations

- Requires `--privileged`.
- The first start needs access to `ghcr.io` unless the images are prebaked.
- Nested overlay2 is required; the entrypoint refuses to run on the `vfs`
  fallback unless `ALLOW_VFS=true`.
- One container means one failure domain: the demo's per-service memory limits
  still apply inside, but the whole demo restarts together.
