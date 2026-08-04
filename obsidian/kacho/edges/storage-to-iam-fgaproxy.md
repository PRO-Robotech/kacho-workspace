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
verified_against: "отметка сверки с деревом продукта стоит в тексте записки (96b2879a, 2026-08-05)"
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
fga_writer, iam_fgaproxy:system)`. Нет relation → `PermissionDenied`.

> [!warning] Классификация отказа по правам ПЕРЕВЁРНУТА — записка утверждала обратное
> Здесь было: «`PermissionDenied` → drainer трактует как **transient** (грант мог ещё не
> осесть → ретрай), НЕ poison». В дереве (`96b2879a`,
> `internal/clients/iam_register_applier.go`) — ровно наоборот: `InvalidArgument` **и**
> `PermissionDenied` → `ErrPermanent`, отравление строки. Так же у vpc, compute, nlb и
> registry — **5 из 5** (предикат: `case codes.InvalidArgument, codes.PermissionDenied:` в
> каждом `*register_applier*.go`).
>
> Перевёрнуто оно не из аккуратности: отказ по правам зависит от (вызывающий, отношение,
> объект), и повтор не меняет ни одного из трёх — то есть «временный» здесь не покупает
> будущего успеха. Хуже: дренаж держит временную строку на единицу **ниже** порога
> отравления, поэтому она никогда не покидает блокирующий набор claim-запроса, и **ни одна
> последующая строка её партиции не клеймится**. Класс наблюдался вживую: очередь, из
> которой ни одна строка никогда не была доставлена, при внешне исправном поведении
> (`data-integrity.md` §«Межсервисное намерение»). Отравление же — ограниченная пауза:
> периодический `RedrivePoisoned` (`cmd/storage/redrive_backstop.go`) переигрывает такие
> строки, и постоянная причина видна как повторяющееся отравление, а не как тишина.

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
- **Error-маппинг (сверено 2026-08-05)**: `InvalidArgument` **и** `PermissionDenied` → poison
  (см. предупреждение выше); Unavailable / дедлайн / транспорт → transient retry с backoff.
  IAM down → intent durable, Operation не падает (tuple не теряется).

## Tests (CS-1 GAP-D, TDD RED→GREEN)

- `internal/repo/pg/fga_register_outbox_integration_test.go` (testcontainers): Insert/Delete тома и
  снапшота эмитят register/unregister-строку атомарно; rollback не оставляет orphan;
  **end-to-end** — corelib drainer забирает intent и вызывает `RegisterResource` (fake IAM), строка
  помечается sent.
- `internal/clients/iam_register_applier_test.go` (fake IAM): Register/Unregister-роутинг,
  `TestClassifyRegisterErr` (InvalidArgument и PermissionDenied → permanent; Unavailable →
  transient), decode-poison.
- `internal/fgaregister/fgaregister_test.go`: tuple-форма + Payload round-trip.

## History

- **CS-1 GAP-D** (epic kacho-workspace#132, PR kacho-storage#4, branch
  `feat/CS-1-storage-network-disk`): caller-сторона реализована — outbox emit (0006) +
  register-drainer + sync-registrar + applier. Закрывает анти-BOLA owner-tuple gap (INV-10):
  без owner-tuple gateway scope_extractor не резолвил target→project.
- **#71 — callee-сторона (FGA model + iam-wiring) отсутствовала** (redesign/integration, commit
  `c01c2b9`): caller корректно эмитил `storage_<t>:<id> #project @project:<pid>`, НО
  (1) openfga-модель **не определяла типы** `storage_volume`/`storage_snapshot`/`storage_image`
  → каждый owner-tuple = poison FGA-write (`type not found` → drainer permanent-dead-letter);
  (2) даже с типом iam-реконсайлер ронял объект: `RegisterResource` мапит FGA-префикс→dotted
  mirror-ключ через `authzmap.DottedType`, без storage-записи mirror хранил `storage_volume`
  **verbatim (без точки)** → `ReconcileObjectForward`→`FGAObjectType` возвращал ok=false →
  **никакие v_\* не материализовались**. Итог (проверено live): project-scoped owner-GET = **403**
  "no authorization path", cross = 403 — **fail-CLOSED over-denial, НЕ BOLA**. Маскировалось
  false-green newman-суитой, гонявшей CRUD под `jwtBootstrap` (cluster system_admin
  short-circuit'ит per-object Check → 200). Фикс: openfga-типы (parity с nlb: `project` +
  DIRECT `v_*`, **без** `owner`-деривации — storage не эмитит owner-tuple) + `authzmap.objectTypes`
  (`storage.volumes/snapshots/images`→`storage_*`) + `verbBearingTypes` + `domain.knownModules("storage")`
  + `module_set_drift`. **Требует iam service-rebuild, не только model re-pin.** Newman
  `VOL-OBJSELF-PROJECT-SCOPED-CRUD` гоняет object-self под project-editor (unmask). TDD: model-lock
  + wiring-lock + real-OpenFGA Check.
- **#71 — ВТОРАЯ половина (materialization), commit `1a399dd` + migration `0060`**: даже с валидными
  FGA-типами + wiring project-scoped owner ВСЁ ЕЩЁ получал 403. Live-диагностика: свежий
  `storage_volume:<id>` нёс ТОЛЬКО структурный `#project`-tuple — реконсайлер материализовал **ноль**
  per-object `v_*` для creator-SA. Причина: реконсайлер материализует `v_*` только для типов из
  `domain.AllMaterializableTypes()` (`labelSelectableTypes ∪ registry.repositories`), которые
  boot-backfill `SyncAllSystemRoleSelectors` (serve.go `BackfillOwnerBindings`) проецирует в
  `role_rule_selectors` системных ролей (edit/view/admin/owner). `storage.*` там ОТСУТСТВОВАЛ →
  editor-binding невидим discovery для storage-объектов → 403 на своём ресурсе (инвариант
  data-integrity.md «role_rule_selectors для ВСЕХ materializing-ролей»). Фикс: `storage.volumes/
  snapshots/images` → `domain.labelSelectableTypes` (own-table labels, mirror-fed, парити vpc/compute)
  → `AllMaterializableTypes()` = 26; migration `0060` пере-сидит admin/edit/view/owner селекторы
  26-типным массивом (stable `rule_fp` хеширует `*.*`-rule, не object_types → idempotent UPSERT).
  Требует iam-rebuild+restart (boot-backfill подхватывает 26). **Verified live 403→200**: project-editor
  owner-GET/Update/Delete своего тома = 200, cross = 403; DB — все 4 системные роли `has_storage=t, n=26`.
  Полная цепочка #71: model-types → objectTypes/verbBearingTypes/knownModules → AllMaterializableTypes/
  role_rule_selectors → reconciler `objectType ∈ selector.types` → materialize `v_*`.

## See also

[[iam-register-resource-callee-contract]] (приёмная сторона)
[[../rpc/iam-internal-iam-service]] [[vpc-to-iam-fgaproxy]] [[compute-to-iam-fgaproxy]]
[[registry-to-iam-fga-register]] [[iam-to-openfga-grant-write]]

> [!note] Записки `storage → iam (project validate)` в vault нет
> Ссылка на неё висела здесь и не резолвилась. Само ребро существует
> (`services/storage/internal/clients/iam_client.go` — проверка проекта у владельца), но
> описано оно не было; заводить его надо отдельной запиской, а не ссылкой на пустоту.
> Соседние клиенты storage: `geo_client.go` (зона→регион, существование зоны и региона).

#edge #kacho-storage #kacho-iam #cross-service #security #internal
