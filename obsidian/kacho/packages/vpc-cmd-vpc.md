---
title: vpc-cmd-vpc
category: package
repo: kacho-vpc
layer: cmd
tags:
  - packages
  - kacho-vpc
  - cmd
  - composition-root
---

# kacho-vpc/cmd/vpc

**Path**: `kacho-vpc/cmd/vpc/main.go`

Composition root (binary entrypoint). Wiring всех слоёв: config → DB pool → repo → service → handler → gRPC server (public 9090 + internal 9091). Здесь — единственное место, где импортируются конкретные реализации port-интерфейсов.

## Responsibilities

1. `config.Load(&cfg)` — env через [[corelib-config]].
2. `observability.NewSlogger` + `InitOtel` ([[corelib-observability]]).
3. `db.NewPool(ctx, cfg.PG.DSN)` ([[corelib-db]]).
4. `db.NewTransactor(pool)`.
5. Repo construction — [[vpc-repo-kacho-pg]] (pgxpool-impl ports из [[vpc-repo-kacho]]).
6. Peer clients — [[vpc-clients]] (folder cache + compute client).
7. Service-layer — `internal/apps/kacho/api/<resource>/handler.go` + supporting services [[vpc-apps-kacho-services-addressref]] / [[vpc-apps-kacho-services-networkinternal]].
8. `grpcsrv.NewServer(...)` × 2 (public 9090, internal 9091) — [[corelib-grpcsrv]].
9. Register handlers — public service + internal admin service на separate listeners (Запреты #6).
10. [[corelib-operations]] Worker — pool горутин для async-операций.
11. [[corelib-shutdown]] Manager — LIFO graceful.

## See also

[[vpc-apps-kacho-config]] [[corelib-grpcsrv]] [[corelib-shutdown]] [[corelib-operations]]

#packages #kacho-vpc #cmd #composition-root
