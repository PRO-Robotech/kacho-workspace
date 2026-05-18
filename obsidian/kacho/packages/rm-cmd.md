---
title: rm-cmd
category: package
repo: kacho-resource-manager
layer: cmd
tags:
  - packages
  - kacho-rm
  - cmd
  - composition-root
---

# kacho-resource-manager/cmd/resource-manager

**Path**: `kacho-resource-manager/cmd/resource-manager/main.go`

Composition root для rm-сервиса. Wiring layers (domain → service → repo → handler → gRPC server).

## Responsibilities

1. [[corelib-config]] `Load` → `rm-config`.
2. [[corelib-observability]] slogger + OTEL init.
3. [[corelib-db]] `NewPool` (schema `kacho_rm`).
4. [[rm-repo]] construction (pgx-based).
5. [[rm-service]] use-cases (depends on Repo ports).
6. [[rm-handler]] gRPC handlers (depends on services).
7. [[rm-bootstrap]] — seed defaults (default Cloud/Folder для dev).
8. [[corelib-grpcsrv]] `NewServer` → register Cloud/Folder/Organization + OperationService.
9. [[corelib-operations]] Worker.
10. [[corelib-shutdown]] Manager LIFO.

## See also

[[rm-config]] [[rm-handler]] [[rm-service]]

#packages #kacho-rm #cmd #composition-root
