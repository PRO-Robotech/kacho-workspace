---
title: proto-api
category: package
repo: kacho-proto
layer: proto
tags:
  - proto
  - api
  - legacy
---

# proto/api

**Path**: `kacho-proto/proto/kacho/cloud/api/`
**Package**: `kacho.cloud.api`
**Go import**: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/api`

Legacy / shared API-utility messages.

## Files

- `operation.proto` — старая версия `Operation` envelope **до** вынесения в отдельный domain (`kacho.cloud.operation.v1`). Сейчас — backward-compat alias / re-export для уже-сгенерированных stubs.

## Migration note

Новый код использует `kacho.cloud.operation.v1.Operation` (см. [[proto-operation]]). Этот пакет можно считать архивным / на удаление в будущем cleanup'е (KAC-94 follow-up).

#proto #api #legacy
