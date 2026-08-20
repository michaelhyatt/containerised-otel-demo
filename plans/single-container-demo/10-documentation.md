# Task 10 — Documentation

Affected files: `single-container/README.md` (new), `README.md` (one pointer).

Depends on: 09.

## Goal

Someone who has never seen the repo can run the demo against their own backend
from the README alone.

## Steps

1. Write `single-container/README.md` covering: what the mode is and is not, the
   `docker run` invocation with required flags (`--privileged`, `--memory`, port
   publications), the `OTLP_EXPORT_*` variables with a worked example per
   protocol, the list of exposed endpoints, how to drive failure scenarios and
   load, the optional flag-persistence mount, measured footprint numbers from
   Task 08 including the cost of the browser scenario and how to disable it with
   `K6_BROWSER_ENABLED=false` for memory-constrained hosts, and the known
   limitations (privileged requirement, first-boot pull
   time, `kafkaQueueProblems` inert, no Jaeger/Grafana UIs so `/jaeger` and
   `/grafana` return 5xx by design).
2. Add a short pointer from the root `README.md` to the new mode, in the same
   style as the existing run-mode descriptions.
3. Keep it markdownlint-clean and spell-check clean.

## Acceptance criteria

- `make markdownlint`, `make misspell` and `make checklinks` pass.
- A reader following only the README reaches a working demo exporting to their
  own endpoint.
