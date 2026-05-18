---
title: vpc-apps-kacho-config
category: package
repo: kacho-vpc
layer: config
tags:
  - packages
  - kacho-vpc
  - config
---

# kacho-vpc/internal/apps/kacho/config

**Path**: `kacho-vpc/internal/apps/kacho/config/`
**Imports**: [[corelib-config]]

VPC-specific config struct + defaults + validation.

## Files

| File | Содержание |
|---|---|
| `config.go` | top-level struct `Config{ PG, GRPC, Operations, IPAM, ... }` с env-тегами |
| `defaults.go` | sensible defaults (timeouts, pool sizes) |
| `load.go` | `Load() (*Config, error)` — обёртка над [[corelib-config]] `Load` |
| `validate.go` | post-load validation (DSN reachable, port conflicts) |
| `mode.go` | runtime-mode enum (dev / prod / migrator) |
| `config_test.go` | |

## Env вars (selected)

- `KACHO_VPC_PG_DSN`
- `KACHO_VPC_GRPC_PUBLIC_ADDR` (default `:9090`)
- `KACHO_VPC_GRPC_INTERNAL_ADDR` (default `:9091`)
- `KACHO_VPC_DEFAULT_SG_INLINE` (true) — inline default-SG в Network.Create
- `KACHO_VPC_OPERATIONS_WORKER_COUNT` (default N)
- `KACHO_VPC_RM_ADDR` — peer rm endpoint
- `KACHO_VPC_COMPUTE_ADDR` — peer compute endpoint (KAC-15)

## See also

[[corelib-config]] [[vpc-cmd-vpc]]

#packages #kacho-vpc #config
