---
title: rm-config
category: package
repo: kacho-resource-manager
layer: config
tags:
  - packages
  - kacho-rm
  - config
---

# kacho-resource-manager/internal/config

**Path**: `kacho-resource-manager/internal/config/`
**Imports**: [[corelib-config]]

rm config struct.

## Env vars (selected)

- `KACHO_RM_PG_DSN`
- `KACHO_RM_GRPC_ADDR` (default `:9090`)
- `KACHO_RM_BOOTSTRAP_DEFAULTS` (true) — seed на startup
- `KACHO_RM_OPERATIONS_WORKER_COUNT`

## Files

- `config.go` — единственный (~50 LOC).

## See also

[[corelib-config]] [[rm-cmd]]

#packages #kacho-rm #config
