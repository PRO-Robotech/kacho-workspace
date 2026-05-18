---
title: corelib-backoff
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
---

# corelib/backoff

**Path**: `kacho-corelib/backoff/`
**Imports**: `github.com/cenkalti/backoff/v4`, `time`
**Imported by**: `kacho-corelib/retry`

Тонкая обёртка над `cenkalti/backoff/v4` — exponential builder с дефолтами Kachō.

## Exported types

- `Backoff = backoff.BackOff` — alias.
- `BackOffContext = backoff.BackOffContext` — alias.

## Exported funcs/vars

- `var Stop = backoff.Stop` — sentinel «прекратить retry».
- `ExponentialBackoffBuilder() exponentialBackoffBuilder` — builder с `.WithMaxElapsedTime`, `.WithInitialInterval`, …; default-tuned под gRPC `Unavailable` (см. [[corelib-retry]]).
- `NewConstantBackOff(d time.Duration) Backoff` — фиксированный интервал.

## See also

[[corelib-retry]]

#packages #kacho-corelib
