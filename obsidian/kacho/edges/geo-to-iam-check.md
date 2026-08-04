---
title: "geo → iam: per-RPC OpenFGA Check (#82)"
aliases:
  - geo to iam check
  - geo authz check
category: edge
caller_repo: kacho-geo
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC/EPIC-geo-extraction]]"
tags:
  - edge
  - cross-service
  - kacho-geo
  - kacho-iam
  - authz
---

> [!note] New edge (эпик #82)
> Новый leaf-сервис `kacho-geo` обязан гейтить КАЖДЫЙ RPC обоих листенеров (public :9090 + internal :9091)
> через `InternalIAMService.Check` — internal НЕ освобождён (`security.md` authN+authZ-инвариант).

# geo → iam: per-RPC Check (#82)

**Caller**: `kacho-geo` (`internal/check/`-interceptor поверх corelib `authz`, parity с compute/vpc).
**Callee**: `kacho-iam.InternalIAMService.Check` (:9091).
**Protocol**: gRPC cluster-internal (direct dial, mTLS).
**Sync/Async**: **sync** (на каждом RPC, до handler'а).

## When invoked

- **Публичный справочник** — `RegionService.Get/List`, `ZoneService.Get/List`: per-RPC
  ReBAC-Check с них **снят** (запись помечена публичной, `internal/check/permission_map.go`),
  это задокументированное исключение — глобальный каталог оси размещения обязан читать каждый
  тенант, иначе арендатор без единой привязки не сможет назвать зону при создании ресурса.
- Admin-CRUD (`InternalRegionService` / `InternalZoneService`, :9091) → **`system_admin`**.
- Остальные RPC обоих слушателей — обычный per-RPC Check; незамапленный RPC отвечает
  fail-closed («rpc not mapped»), а не пропускается.

> [!warning] «viewer-tier (system_viewer-floor)» на публичном чтении — неверно, и ошибка опасная
> Прежняя редакция описывала эти четыре RPC как гейтованные полом чтения. В дереве на
> публичной записи интерсептор отдаёт разрешение **сразу, до извлечения субъекта**, а
> principal-цепочка geo личность только проставляет и никого не отвергает — собственного
> барьера «нет принципала → UNAUTHENTICATED» у geo на них **нет**.
>
> Почему это важно записать правильно: правка «под комментарий» здесь вернула бы дыру. Эти
> четыре RPC реально закрыты **двумя слоями вне таблицы прав** — обязательным mTLS на обоих
> слушателях (boot-guard отказывает в старте без него) и краем, который требует валидного
> принципала на своей `<exempt>`-ветке. Читать «geo сам проверяет читателя» нельзя.

## Error handling — fail-closed

| Result | gRPC code |
|---|---|
| allowed=true | (continue) |
| allowed=false | `PermissionDenied` |
| iam недоступен | `PermissionDenied "authorization service unavailable"` |
| no Principal / mTLS-провал | `PermissionDenied` / транспортный отказ |

## leaf-консумер

`kacho-geo` зовёт **только** iam (authz-Check) — больше ни от какого сервиса в runtime не зависит.
Это держит geo leaf'ом (как iam) и сохраняет ацикличность графа (`all → geo`, `geo → iam`).

## See also

[[compute-to-iam-check]] [[vpc-to-iam-check]] [[../rpc/geo-region-service]] [[../rpc/geo-zone-service]] [[../packages/corelib-authz]]

#edge #cross-service #kacho-geo #kacho-iam #authz
