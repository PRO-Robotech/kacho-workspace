---
title: "storage → iam: FGA-proxy RegisterResource/UnregisterResource (SEC-D)"
aliases:
  - storage to iam fgaproxy
  - storage register resource
  - storage owner-tuple
category: edge
caller_repo: kacho-storage
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: done
related_tickets:
  - "[[../KAC/SEC-D-services-fga-via-iam-mtls]]"
tags:
  - edge
  - kacho-storage
  - kacho-iam
  - cross-service
  - security
  - internal
---

> [!note] Реализовано в CS-1 GAP-D (caller); callee — SEC-C/SEC-D
> `kacho-iam.InternalIAMService.RegisterResource/UnregisterResource` реализован
> ([[../KAC/SEC-C-iam-fga-proxy-sa-roles]]/[[../KAC/SEC-D-services-fga-via-iam-mtls]]).
> kacho-storage подключил это ребро в CS-1 GAP-D: owner-tuple intent пишется в
> `kacho_storage.fga_register_outbox` в writer-tx ресурса, register-drainer →
> `IAM.RegisterResource` по mTLS. Storage в OpenFGA напрямую не ходит («FGA за IAM»).

# storage → iam: FGA-proxy owner-tuple write/delete

**Protocol**: gRPC cluster-internal :9091 (Internal-only, ban #6; нет на external).
**Direction**: усиление существующего `storage → iam` (ProjectService.Get + authz-Check);
ацикличность сохранена (storage не зовётся обратно).

## Зачем (анти-BOLA)

Gateway scope_extractor'ы `{storage_volume, volume_id}` / `{storage_snapshot, snapshot_id}`
(коммитнуты в iam permission-catalog) резолвят target→project ТОЛЬКО при наличии
owner-tuple `project:<projectId> #project @storage_volume:<id>` (и `@storage_snapshot:<id>`).
Без tuple owner видит DENY на свой же только что созданный ресурс. FGA object-типы
`storage_volume`/`storage_snapshot` уже есть в `fga_model.fga` — storage их НЕ переопределяет,
только эмитит tuple.

## Контракт

Идентичен [[vpc-to-iam-fgaproxy]] / [[compute-to-iam-fgaproxy]]:
`RegisterResource`/`UnregisterResource` с `{subject_id, relation, object, labels,
parent_project_id, source_version}`, идемпотентность как контракт (write existing→OK,
delete absent→OK), at-least-once через transactional-outbox (SEC-D).

## Authz (least-priv, SEC-C)

mTLS client-cert identity storage-SA → ReBAC `Check(service_account:<sva-storage>,
fga_writer, iam_fgaproxy:system)`. Нет relation → `PermissionDenied` → drainer трактует
как **transient** (grant fga_writer мог ещё не осесть → ретрай, intent durable), НЕ poison.

## Caller-side mechanics (CS-1 GAP-D, kacho-storage)

- **Домен**: `internal/fgaregister/fgaregister.go` (чистый Go) — Tuple/Payload/Encode/Decode,
  `StorageVolume(projectID, id)` / `StorageSnapshot(projectID, id)` (relation `project`),
  `EventRegister`/`EventUnregister`, port `Registrar`.
- **Intent в writer-tx**: `internal/repo/pg/fga_register.go::emitFGARegister` пишет строку в
  `kacho_storage.fga_register_outbox` (миграция `0006`) В ТОЙ ЖЕ tx, что Insert/Delete тома/снапшота
  (`volume_repo.go`/`snapshot_repo.go`; Delete делает `DELETE … RETURNING project_id` для
  unregister-subject). `event_type ∈ {fga.register, fga.unregister}` (DB CHECK); payload —
  tuple + labels + parent_project_id; `source_version` штампуется `now()` через `jsonb_set`.
  Tx abort → intent откатывается (no orphan; regression-тест `TestVolumeInsert_FailedFK_NoFGAIntent`).
- **ОТДЕЛЬНАЯ таблица** `fga_register_outbox` (drainer-схема: id IDENTITY, sent_at, attempt_count,
  last_error) — независимая от доменного `storage_outbox` (0005, sequence_no/processed_at,
  драйнеру несовместим).
- **Drainer**: corelib `outbox/drainer` (`cmd/storage/register_drainer.go::startRegisterDrainer`,
  default-on `KACHO_STORAGE_FGA_REGISTER_DRAINER_ENABLED`), table/channel
  `kacho_storage.fga_register_outbox` / `kacho_storage_fga_register_outbox`. Applier —
  `internal/clients/iam_register_applier.go`. CAS-claim `FOR UPDATE SKIP LOCKED` → exactly-once
  across replicas. Reuse authz-conn (`AuthZIAMGRPCAddr`, :9091 mTLS).
- **Sync-registrar** (immediate анти-BOLA): `internal/clients/iam_sync_registrar.go` —
  Create-flow после commit синхронно регистрирует owner-tuple (best-effort; ошибка → WARN,
  drainer подхватит at-least-once). Wired `volumeUC/snapshotUC.WithRegistrar(...)`.
- **Error-маппинг**: `InvalidArgument` → poison (no retry); PermissionDenied/Unavailable/транспорт
  → transient retry с backoff. IAM down → intent durable, Operation не падает (tuple не теряется).

## Tests (CS-1 GAP-D, TDD RED→GREEN)

- `internal/repo/pg/fga_register_outbox_integration_test.go` (testcontainers): Insert/Delete тома и
  снапшота эмитят register/unregister-строку атомарно; rollback не оставляет orphan;
  **end-to-end** — corelib drainer забирает intent и вызывает `RegisterResource` (fake IAM), строка
  помечается sent.
- `internal/clients/iam_register_applier_test.go` (fake IAM): Register/Unregister-роутинг,
  classify (InvalidArgument→permanent, Unavailable/PermissionDenied→transient), decode-poison.
- `internal/fgaregister/fgaregister_test.go`: tuple-форма + Payload round-trip.

## History

- **CS-1 GAP-D** (epic kacho-workspace#132, PR kacho-storage#4, branch
  `feat/CS-1-storage-network-disk`): caller-сторона реализована — outbox emit (0006) +
  register-drainer + sync-registrar + applier. Закрывает анти-BOLA owner-tuple gap (INV-10):
  без owner-tuple gateway scope_extractor не резолвил target→project.

## See also

[[../rpc/iam-internal-iam-service]] [[vpc-to-iam-fgaproxy]] [[compute-to-iam-fgaproxy]]
[[storage-to-iam-project-validate]] [[iam-to-openfga-grant-write]]

#edge #kacho-storage #kacho-iam #cross-service #security #internal
