# Task 08 — Footprint measurement and tuning pass

Affected files: `compose.single-container.yaml`, `single-container/README.md`.

Depends on: 04, 05.

## Goal

Confirm the budget in the design doc against reality, and tighten or relax the
limits based on measurement rather than guesswork.

## Steps

1. Baseline: `make start`, let it settle for 10 minutes, record total
   `docker stats` memory and CPU.
2. Single container: same procedure on the outer container, plus per-service
   figures from `docker stats` inside it.
3. Compare each service's steady RSS against its declared limit and adjust the
   overrides. Watch specifically for:
   - `load-generator` at 512M with the browser scenario on — this is the largest
     single consumer and the most likely to need *more* rather than less.
     Chromium under nesting is the main risk: watch for renderer crashes, page
     timeouts in the k6 logs, and `/dev/shm` exhaustion. If crashes appear,
     raise `shm_size` before raising the memory limit. Record the delta between
     browser-on and browser-off so the cost of keeping it is explicit and the
     README can offer disabling it as a documented escape hatch.
   - `recommendation` at 300M — exercise `recommendationCacheFailure` and check
     it degrades as intended rather than OOM-killing.
   - `ad` (JVM) — confirm `adHighCpu` and `adManualGc` still behave at the
     current limit.
   - `otel-collector` at 300M with `GOMEMLIMIT=160MiB` — verify the
     `memory_limiter` never trips under normal load, and check behaviour when
     the external destination is unreachable.
4. Consider adding `deploy.resources.limits.cpus` for the noisiest services if
   CPU rather than memory turns out to be the constraint.
5. Confirm removing `host_metrics` measurably reduced collector CPU; if not,
   reconsider keeping a reduced scraper set for demo value.
6. Write the measured numbers into the README, including a recommended
   `--memory` for the outer container.

## Acceptance criteria

- Documented steady-state RSS under 2.5 GB for the outer container.
- No service OOM-kills during a 30-minute run with load and with at least three
  failure scenarios exercised.
- The browser scenario completes iterations continuously for 30 minutes with no
  renderer crashes.
- Before/after numbers recorded in the README, including the measured cost of
  the browser scenario.
