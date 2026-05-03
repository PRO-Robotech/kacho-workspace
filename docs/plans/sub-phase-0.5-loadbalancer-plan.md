# Sub-phase 0.5 — LoadBalancer (NLB + TargetGroup + Finalizer) — Implementation Plan

> **For agentic workers:** Acceptance APPROVED commit `5e4d5e7` в
> `kacho-workspace/docs/specs/sub-phase-0.5-loadbalancer-acceptance.md`
> (81 сценарий, 13 групп A–N).

**Goal:** `kacho-proto` получает домен loadbalancer; `kacho-loadbalancer` — полностью
реализованный сервис с reconciler-ом, симулирующим lifecycle `NetworkLoadBalancer`
(CREATING → ACTIVE, 5–15 с) и синхронным переходом `TargetGroup` (CREATING → READY);
cross-service клиенты к resource-manager, vpc, compute; finalizer
`loadbalancer.kacho.io/target-deregister` на стороне compute; сервис деплоится в
kind-кластер через Helm.

**Architecture:** Clean Architecture per `kacho-workspace/CLAUDE.md`:
`handler → service → repo` с port-интерфейсами в `service/ports.go`.
Reconciler — отдельный пакет `internal/reconciler/`, горутина-per-resource-type
с `pg_advisory_lock(uid_hash)` для координации реплик.
TargetGroup переходит в READY синхронно в handler (без reconciler-а).
Watch Hub переиспользуется из `kacho-corelib/watch`.
Cross-service клиенты реализуют port-интерфейсы из `service/` в `internal/clients/`.
Симулированные задержки параметризуются через env-переменные.

**Tech stack:** Go 1.22+ (golang.org/x/exp/slog), buf, pgx/v5, sqlc, goose-миграции,
testcontainers-go, grpcurl для e2e, `kacho-corelib` (watch, outbox, db, grpcsrv,
grpcclient, ids, errors, observability).

---

## §0. Resolutions для OQ и reviewer nits

### OQ-resolutions

| # | Вопрос | Решение |
|---|---|---|
| OQ-1 | Уникальность listener по порту/протоколу | **Вариант A:** дублирование `port + protocol` внутри одного NLB запрещено — INVALID_ARGUMENT при Upsert. Сценарий L13. |
| OQ-2 | TargetGroup с targets в разных subnet | **Разрешено:** несколько targets с разными `subnet_id` внутри одного TG допустимы. Ограничения data plane вне scope. |
| OQ-3 | NLB `status.external_ips` — симулированный IP | **Вариант B:** reconciler присваивает симулированный IP из диапазона `10.255.X.X` при переходе CREATING → ACTIVE. Хеш от UID обеспечивает детерминированность. UNIQUE-constraint в БД гарантирует локальную уникальность. Сценарии E1, K1. |
| OQ-4 | Порядок снятия finalizer-ов | **Вариант A:** оба finalizer (`compute.kacho.io/disk-detach` и `loadbalancer.kacho.io/target-deregister`) обрабатываются параллельно в двух горутинах compute-reconciler-а. Порядок снятия не гарантирован, для control plane-only системы это допустимо. Сценарий I1. |

### Reviewer nit-resolutions

| # | Nit | Решение |
|---|---|---|
| K1-nit | `status.external_ips` Then-check | Добавлена проверка в E1 и K1: `status.external_ips` содержит ≥1 IPv4-элемент при переходе в ACTIVE. Уже в acceptance, реализатор должен убедиться что reconciler явно записывает IP. |
| L9/L16 | `details[]` для ABORTED | Ответ при ABORTED включает `ErrorInfo.reason = "OCC_CONFLICT"` и `RequestInfo` с request_id. Не блокирует, но реализатор добавляет при написании service. |
| L14/L15 | Валидация имени и folder_id TG | TG-сервис применяет те же regex-проверки `^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$` для `name` и UUID-формат для `folder_id` аналогично NLB. Сценарии L14/L15 описаны для NLB — то же для TG, тесты именуются `TestTargetGroup_L14_InvalidName` и `TestTargetGroup_L15_InvalidFolderID`. |

---

## §1. File map (cross-repo)

### `kacho-proto/` — Phase A

```
proto/kacho/cloud/loadbalancer/v1/
  network_load_balancer.proto   — NetworkLoadBalancerService + все messages
  target_group.proto            — TargetGroupService + все messages
  internal.proto                — LoadBalancerInternal (NLBExists, TGExists,
                                  UpdateNLBStatus, UpdateTGStatus, RemoveTarget)
gen/go/kacho/cloud/loadbalancer/v1/
  *.pb.go                       — committed после buf generate
  *_grpc.pb.go
```

### `kacho-loadbalancer/` — Phase B (основная работа)

```
cmd/loadbalancer/main.go                        — composition root (serve/migrate subcommands)

internal/domain/
  network_load_balancer.go                      — entity NLB (stdlib + kacho-proto только)
  target_group.go                               — entity TargetGroup
  types.go                                      — shared enums, Listener, Target,
                                                   AttachedTargetGroup

internal/service/
  ports.go                                      — NLBRepo, TargetGroupRepo, FolderClient,
                                                   SubnetClient, InstanceClient port-интерфейсы
  nlb.go                                        — NLBService use-cases
  target_group.go                               — TargetGroupService use-cases
  internal.go                                   — InternalService (NLBExists, TGExists,
                                                   UpdateNLBStatus, UpdateTGStatus, RemoveTarget)
  nlb_test.go                                   — unit-тесты с mock port-интерфейсами
  target_group_test.go
  internal_test.go

internal/repo/
  nlb_repo.go                                   — реализует NLBRepo (pgx + sqlc + outbox)
  target_group_repo.go                          — реализует TargetGroupRepo
  queries/                                      — sqlc-generated (nlb.sql.go, tg.sql.go)
  sql/
    nlb.sql                                     — sqlc-аннотированные SQL-запросы для NLB
    tg.sql                                      — sqlc-аннотированные SQL-запросы для TG
  filter_builder.go                             — WHERE-clause builder для FieldSelector

internal/clients/
  folder_client.go                              — реализует FolderClient (gRPC → resource-manager)
  subnet_client.go                              — реализует SubnetClient (gRPC → vpc)
  instance_client.go                            — реализует InstanceClient (gRPC → compute)

internal/reconciler/
  dispatcher.go                                 — главный цикл: SELECT pending → dispatch
  nlb_handler.go                                — CREATING→ACTIVE, UPDATING→ACTIVE, DELETING
  advisory_lock.go                              — pg_advisory_lock helpers

internal/handler/
  nlb_handler.go                                — gRPC transport для NetworkLoadBalancerService
  target_group_handler.go                       — gRPC transport для TargetGroupService
  internal_handler.go                           — LoadBalancerInternal (не регистрируется в api-gateway)

migrations/
  common/                                       — sync из kacho-corelib (resource_events, seq)
  0001_initial.sql                              — network_load_balancers, target_groups, regions
  0002_seed_regions.sql                         — seed-данные: kacho-region-a

deploy/
  Dockerfile
  Chart.yaml
  values.yaml
  values.dev.yaml
  templates/
    deployment.yaml
    service.yaml
    configmap.yaml

Makefile
go.mod
go.sum
.github/workflows/ci.yaml
sqlc.yaml
```

### `kacho-compute/` — изменения для finalizer (Phase B.9)

```
internal/clients/
  loadbalancer_client.go                        — реализует LoadBalancerClient (gRPC → loadbalancer)
internal/service/ports.go                       — добавить LoadBalancerClient port-интерфейс
internal/service/instance.go                    — добавить финалайзер в Upsert Instance
internal/reconciler/instance_handler.go         — обработать finalizer loadbalancer.kacho.io/target-deregister
```

### `kacho-deploy/` — Phase C

```
helm/loadbalancer/
  Chart.yaml
  values.yaml
  values.dev.yaml
  templates/
    deployment.yaml
    service.yaml
    configmap.yaml
helm/umbrella/Chart.yaml                        — раскомментировать loadbalancer dep
helm/umbrella/values.dev.yaml                   — добавить loadbalancer: секцию
e2e/0.5/
  M1-full-flow.sh
  M2-finalizer.sh
  M3-nlb-update.sh
  M4-full-replace-atg.sh
  M5-helm-deploy.sh
```

---

## §2. Phase A — kacho-proto/loadbalancer/v1

**Acceptance scenarios:** A1–A5

### A.1 network_load_balancer.proto

```protobuf
syntax = "proto3";
package kacho.cloud.loadbalancer.v1;
option go_package = "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/loadbalancer/v1;loadbalancerv1";

import "kacho/cloud/common/v1/resource_meta.proto";
import "kacho/cloud/common/v1/selector.proto";
import "kacho/cloud/common/v1/watch_event.proto";
import "google/protobuf/timestamp.proto";

// Listener — конфигурация порта входящего трафика NLB
message Listener {
  string name     = 1;
  int32  port     = 2;  // 1–65535
  enum Protocol {
    PROTOCOL_UNSPECIFIED = 0;
    TCP = 1;
    UDP = 2;
  }
  Protocol protocol = 3;
}

// AttachedTargetGroup — ссылка на TargetGroup, присоединённую к NLB
message AttachedTargetGroup {
  string target_group_id = 1;
}

message NetworkLoadBalancerSpec {
  string display_name  = 1;
  string description   = 2;
  string region_id     = 3;
  repeated Listener             listeners              = 4;
  repeated AttachedTargetGroup  attached_target_groups = 5;
}

message NetworkLoadBalancerStatus {
  enum State {
    STATE_UNSPECIFIED = 0;
    CREATING  = 1;
    ACTIVE    = 2;
    UPDATING  = 3;
    ERROR     = 4;
    DELETING  = 5;
  }
  State  state                   = 1;
  google.protobuf.Timestamp state_last_transition_at = 2;
  repeated string external_ips   = 3;  // симулированные IP при ACTIVE (OQ-3)
  int64  observed_generation     = 4;  // reconciler пишет = metadata.generation после перехода (J4)
  repeated StatusCondition conditions = 5;
}

message StatusCondition {
  string type    = 1;
  string status  = 2;
  string reason  = 3;
  string message = 4;
}

message NetworkLoadBalancer {
  kacho.cloud.common.v1.ResourceMeta metadata = 1;
  NetworkLoadBalancerSpec             spec     = 2;
  NetworkLoadBalancerStatus           status   = 3;
}

// Request/Response messages
message NetworkLoadBalancerUpsertRequest  { repeated NetworkLoadBalancer network_load_balancers = 1; }
message NetworkLoadBalancerUpsertResponse { repeated NetworkLoadBalancer network_load_balancers = 1; }

message NetworkLoadBalancerDeleteRequest {
  message Item { string uid = 1; string name = 2; }
  repeated Item items = 1;
}
message NetworkLoadBalancerDeleteResponse {}

message NetworkLoadBalancerListRequest {
  repeated kacho.cloud.common.v1.Selector selectors  = 1;
  string page_token = 10;
  int32  page_size  = 11;
}
message NetworkLoadBalancerListResponse {
  repeated NetworkLoadBalancer network_load_balancers = 1;
  string resource_version  = 2;
  string next_page_token   = 3;
}

message NetworkLoadBalancerWatchRequest {
  repeated kacho.cloud.common.v1.Selector selectors        = 1;
  string                                  resource_version = 2;
}

service NetworkLoadBalancerService {
  rpc Upsert(NetworkLoadBalancerUpsertRequest) returns (NetworkLoadBalancerUpsertResponse);
  rpc Delete(NetworkLoadBalancerDeleteRequest) returns (NetworkLoadBalancerDeleteResponse);
  rpc List(NetworkLoadBalancerListRequest)     returns (NetworkLoadBalancerListResponse);
  rpc Watch(NetworkLoadBalancerWatchRequest)   returns (stream kacho.cloud.common.v1.WatchEvent);
}
```

### A.2 target_group.proto

`Target` message: `subnet_id string`, `address string` (IPv4), `instance_id string` (опционально).

`TargetGroupSpec` содержит: `display_name`, `description`, `targets[]`.

`TargetGroupStatus.State` enum: `STATE_UNSPECIFIED`, `CREATING`, `READY`, `UPDATING`, `DELETING`.

`TargetGroupStatus` дополнительно содержит `state_last_transition_at` и `observed_generation int64`
(handler выставляет при синхронном переходе CREATING → READY).

`TargetGroupService`: `Upsert`, `Delete`, `List`, `Watch` (аналогично NetworkLoadBalancerService).

### A.3 internal.proto

Сервис `LoadBalancerInternal` с методами:
- `NetworkLoadBalancerExists(uid) → {exists}` — A5, H1–H2
- `TargetGroupExists(uid) → {exists}` — A5, H3–H4 (soft-deleted → false)
- `UpdateNetworkLoadBalancerStatus({uid, status}) → {}` — A5, H7–H8
- `UpdateTargetGroupStatus({uid, status}) → {}` — A5
- `RemoveTarget({instance_id}) → {}` — A5, H5–H6

Все request/response messages следуют именованию из acceptance A5.

### A.4 buf generate + CI

После написания proto: `buf generate` в `kacho-proto/`. Сгенерированные `gen/go/kacho/cloud/loadbalancer/v1/*.pb.go`
и `*_grpc.pb.go` коммитятся. CI-шаги: `buf lint` (A1), `buf breaking` (A2), `buf generate --error-on-new-files` (A3–A5).

### A.5 Deliverables Phase A

- 3 `.proto` файла в `kacho-proto/proto/kacho/cloud/loadbalancer/v1/`
- `gen/go/kacho/cloud/loadbalancer/v1/` — committed
- `buf lint` чистый (A1), `buf breaking` не регрессирует (A2)
- CI kacho-proto: buf-lint + buf-breaking + buf-generate зелёный

---

## §3. Phase B — kacho-loadbalancer service

**Acceptance scenarios:** B1–B7, C1–C6, D1–D6, E1–E3, F1–F4, G1–G4, H1–H8, I1–I4, J1–J6, K1–K6, L1–L16, M1–M6

### B.1 Skeleton + go.mod + sqlc setup

**go.mod** module: `github.com/PRO-Robotech/kacho-loadbalancer`

Зависимости:
- `github.com/PRO-Robotech/kacho-proto` — grpc-stubs
- `github.com/PRO-Robotech/kacho-corelib` — watch, outbox, db, grpcsrv, grpcclient, ids, errors, observability
- `github.com/jackc/pgx/v5`
- `github.com/pressly/goose/v3`
- `google.golang.org/grpc`
- `google.golang.org/protobuf`
- `github.com/testcontainers/testcontainers-go` (dev)
- `github.com/stretchr/testify` (dev)

**sqlc.yaml**: генерация в `internal/repo/queries/` из `migrations/*.sql` + `internal/repo/sql/*.sql`.
Engine: `postgresql`. Эмитирует: `sqlc.v1`.

**Makefile targets:** `generate` (buf + sqlc), `test`, `lint`, `build`, `docker-build`.

### B.2 Migrations

#### 0000_common (sync из kacho-corelib)

Содержит таблицу `resource_events` и sequence `resource_version_seq` — синхронизируется из
`kacho-corelib/migrations/common/`. Команда `make sync-migrations`.

#### 0001_initial.sql — основная схема

```sql
-- kacho_loadbalancer database schema

CREATE TABLE regions (
  id          TEXT PRIMARY KEY,
  description TEXT
);

CREATE TABLE target_groups (
  uid                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name                      TEXT        NOT NULL,
  folder_id                 UUID        NOT NULL,
  labels                    JSONB       NOT NULL DEFAULT '{}',
  annotations               JSONB       NOT NULL DEFAULT '{}',
  finalizers                TEXT[]      NOT NULL DEFAULT '{}',
  creation_timestamp        TIMESTAMPTZ NOT NULL DEFAULT now(),
  deletion_timestamp        TIMESTAMPTZ,
  resource_version          BIGINT      NOT NULL DEFAULT nextval('resource_version_seq'),
  generation                BIGINT      NOT NULL DEFAULT 1,
  -- spec (JSONB для гибкого targets[])
  display_name              TEXT,
  description               TEXT,
  targets                   JSONB       NOT NULL DEFAULT '[]',
  -- status
  state                     TEXT        NOT NULL DEFAULT 'READY',
  state_last_transition_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  observed_generation       BIGINT      NOT NULL DEFAULT 0,
  UNIQUE (folder_id, name)
);
CREATE INDEX idx_tg_folder_id ON target_groups(folder_id);
CREATE INDEX idx_tg_labels    ON target_groups USING gin(labels jsonb_path_ops);
-- Индекс для RemoveTarget: поиск TG содержащих конкретный instance_id
CREATE INDEX idx_tg_targets_instance_id ON target_groups
  USING gin(targets jsonb_path_ops);

CREATE TABLE network_load_balancers (
  uid                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name                      TEXT        NOT NULL,
  folder_id                 UUID        NOT NULL,
  labels                    JSONB       NOT NULL DEFAULT '{}',
  annotations               JSONB       NOT NULL DEFAULT '{}',
  finalizers                TEXT[]      NOT NULL DEFAULT '{}',
  creation_timestamp        TIMESTAMPTZ NOT NULL DEFAULT now(),
  deletion_timestamp        TIMESTAMPTZ,
  resource_version          BIGINT      NOT NULL DEFAULT nextval('resource_version_seq'),
  generation                BIGINT      NOT NULL DEFAULT 1,
  -- spec fields
  display_name              TEXT,
  description               TEXT,
  region_id                 TEXT        REFERENCES regions(id),
  listeners                 JSONB       NOT NULL DEFAULT '[]',   -- [{name, port, protocol}]
  attached_target_groups    JSONB       NOT NULL DEFAULT '[]',   -- [{target_group_id}]
  -- status fields
  state                     TEXT        NOT NULL DEFAULT 'CREATING',
  state_last_transition_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  external_ips              TEXT[]      NOT NULL DEFAULT '{}',
  observed_generation       BIGINT      NOT NULL DEFAULT 0,
  UNIQUE (folder_id, name)
);
CREATE INDEX idx_nlb_folder_id ON network_load_balancers(folder_id);
CREATE INDEX idx_nlb_labels    ON network_load_balancers USING gin(labels jsonb_path_ops);
CREATE INDEX idx_nlb_state     ON network_load_balancers(state)
  WHERE deletion_timestamp IS NULL;

-- BEFORE UPDATE trigger: resource_version bump
CREATE OR REPLACE FUNCTION kacho_loadbalancer_bump_rv() RETURNS trigger AS $$
BEGIN
  NEW.resource_version := nextval('resource_version_seq');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_nlb_rv BEFORE UPDATE ON network_load_balancers
  FOR EACH ROW EXECUTE FUNCTION kacho_loadbalancer_bump_rv();
CREATE TRIGGER trg_tg_rv BEFORE UPDATE ON target_groups
  FOR EACH ROW EXECUTE FUNCTION kacho_loadbalancer_bump_rv();
```

**Стратегия хранения:** listeners и attached_target_groups — JSONB inline в строке NLB (full-replace
семантика при каждом Upsert). targets — JSONB inline в строке TargetGroup (full-replace при Upsert,
прямое UPDATE при RemoveTarget через `jsonb_array_elements` с фильтрацией).

**Обоснование JSONB vs FK-таблицы:** listeners и attached_target_groups имеют full-replace
семантику (весь список перезаписывается при Upsert) — нет смысла в отдельных таблицах.
Проверка same-DB FK для attached_target_groups выполняется в service-слое при Upsert NLB
(`TargetGroupRepo.Exists(tgUID)`), не через DB constraint (это даёт более богатые error messages).

#### 0002_seed_regions.sql — seed-данные (сценарии M6)

```sql
INSERT INTO regions (id, description) VALUES
  ('kacho-region-a', 'Main region A')
ON CONFLICT (id) DO NOTHING;
```

`ON CONFLICT DO NOTHING` обеспечивает идемпотентность (M6).

Тест: `TestMigration_M6_SeedRegions` в пакете `migrations_test`.

### B.3 Domain entities

#### internal/domain/network_load_balancer.go

Entity `NetworkLoadBalancer` — только stdlib. Поля: все из `ResourceMeta` (UID, Name, FolderID,
Labels, Annotations, Finalizers, CreationTimestamp, DeletionTimestamp, ResourceVersion, Generation)
плюс spec-поля (DisplayName, Description, RegionID, Listeners `[]Listener`, AttachedTargetGroups
`[]AttachedTargetGroupRef`) плюс status-поля (State `NLBState`, StateLastTransitionAt,
ExternalIPs `[]string`, ObservedGeneration int64).

Вспомогательные типы: `Listener{Name, Port int32, Protocol ListenerProtocol}`,
`AttachedTargetGroupRef{TargetGroupID}`.
Enums: `NLBState` (CREATING/ACTIVE/UPDATING/ERROR/DELETING), `ListenerProtocol` (TCP/UDP).

#### internal/domain/target_group.go

Entity `TargetGroup` — только stdlib. Аналогичная структура ResourceMeta + spec (DisplayName,
Description, Targets `[]Target`) + status (State `TGState`, StateLastTransitionAt,
ObservedGeneration int64).

Вспомогательные типы: `Target{SubnetID, Address, InstanceID string}`.
Enum `TGState` (CREATING/READY/UPDATING/DELETING).

**Запрет:** `domain/` и `service/` не импортируют `pgx`, sqlc-types, grpc-stubs — правило Clean Architecture.

### B.4 Service ports + use-cases

#### internal/service/ports.go

Port-интерфейсы (все принимают `ctx context.Context`, возвращают `error`):

`NLBRepo`: `Get(uid)`, `GetByName(folderID, name)`, `List(filter, page)`,
`Upsert(nlb)`, `SoftDelete(uid)`, `Delete(uid)` (физическое), `GetPendingReconcile(limit)`,
`UpdateStatus(uid, NLBStatusPatch{State, ExternalIPs, ObservedGeneration})`.

`TargetGroupRepo`: `Get(uid)`, `GetByName(folderID, name)`, `List(filter, page)`,
`Upsert(tg)`, `SoftDelete(uid)`, `Delete(uid)`, `Exists(uid)` (для NLB FK-валидации),
`ExistsSoftDeleted(uid)`, `RemoveTargetsByInstanceID(instanceID)`.

`FolderClient`: `Exists(folderUID) (bool, error)` — cross-service к resource-manager.
`SubnetClient`: `Exists(subnetUID) (bool, error)` — cross-service к vpc.
`InstanceClient`: `Exists(instanceUID) (bool, error)` — cross-service к compute.

#### internal/service/nlb.go — ключевые use-cases

**Upsert** — проверки в порядке (все через port-интерфейсы):
1. `metadata.name` соответствует regex `^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$` — INVALID_ARGUMENT (L14)
2. `metadata.folder_id` — валидный UUID v4 — INVALID_ARGUMENT (L15)
3. `status` в запросе → INVALID_ARGUMENT (L2)
4. `spec.listeners` непустой — INVALID_ARGUMENT (L6)
5. Для каждого listener: `port` в диапазоне 1–65535 — INVALID_ARGUMENT (L5)
6. Для каждого listener: `protocol` в {TCP, UDP} — INVALID_ARGUMENT (L4)
7. Уникальность `(port, protocol)` внутри listeners — INVALID_ARGUMENT (L13, OQ-1)
8. `page_size <= 1000` при List — INVALID_ARGUMENT (L10)
9. `FolderClient.Exists(folderID)` — NOT_FOUND с ResourceInfo (G1); UNAVAILABLE при сбое (G3)
10. Для каждого `attached_target_groups[i].target_group_id`: `TargetGroupRepo.Exists(tgUID)` — INVALID_ARGUMENT с `BadRequest.field_violations` (F1)
11. Проверить `folder_id` у TG совпадает с NLB `folder_id` — INVALID_ARGUMENT (F4)
12. Idempotency check: если (folderId, name) совпадают и JSONB spec идентичен → no-op, не обновлять resource_version (D2)
13. Upsert → repo.Upsert() в транзакции с outbox event ADDED/MODIFIED
14. Если UPDATE (существующая запись): установить `state = UPDATING` (если был ACTIVE) → reconciler подхватит

**Delete**:
1. Получить NLB по uid — NOT_FOUND если нет (L7)
2. Если `deletion_timestamp != NULL` → OK идемпотентно (D6)
3. Soft-delete: выставить `deletion_timestamp`, state = DELETING, записать MODIFIED event
4. Reconciler завершает физическое удаление

**List**: применяет `FieldFilter.FolderID`, пагинация `page_size` (default 100, max 1000). Сценарий D3.

**Watch**: Subscribe через `kacho-corelib/watch.Hub`, передать filter, OUT_OF_RANGE при Gone (K6).

#### internal/service/target_group.go — ключевые use-cases

**Upsert** — проверки в порядке:
1. `metadata.name` regex `^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$` — INVALID_ARGUMENT (reviewer nit L14)
2. `metadata.folder_id` UUID — INVALID_ARGUMENT (reviewer nit L15)
3. `status` в запросе → INVALID_ARGUMENT (L3)
4. `FolderClient.Exists(folderID)` — NOT_FOUND (G2); UNAVAILABLE (G4)
5. Для каждого target:
   - `address` непустой ИЛИ `instance_id` непустой — INVALID_ARGUMENT (C4)
   - Если `address` указан — валидный IPv4 — INVALID_ARGUMENT (L12)
   - `SubnetClient.Exists(subnetID)` — NOT_FOUND (C1); UNAVAILABLE (C5)
   - Если `instance_id` непустой: `InstanceClient.Exists(instanceID)` — NOT_FOUND (C2); UNAVAILABLE (C6)
6. Idempotency check (B3)
7. Upsert → repo.Upsert() в транзакции. Синхронный переход CREATING → READY в той же транзакции (B2):
   - INSERT с `state='READY'`, `state_last_transition_at=now()`, `observed_generation = generation`
   - Одно событие `ADDED` в outbox (не ADDED + MODIFIED)

**Delete**:
1. Получить TG по uid — NOT_FOUND (L8)
2. Проверить, не ссылается ли ни один NLB на этот TG через `attached_target_groups` — FAILED_PRECONDITION (B7)
3. Если finalizers пусты — физическое удаление + DELETED event (B6)
4. Иначе soft-delete (нет finalizers у TG в текущей реализации, но pattern сохраняется)

#### internal/service/internal.go

**NLBExists**: возвращает `exists=false` для soft-deleted (H2, аналог H4).

**TargetGroupExists**: возвращает `exists=false` для soft-deleted (H4).

**UpdateNetworkLoadBalancerStatus**: проверяет идемпотентность — если `status.state` уже совпадает → no-op (H8, J2).

**RemoveTarget**: атомарная операция в одной транзакции (H5, H6):
1. `TargetGroupRepo.RemoveTargetsByInstanceID(instanceID)` — находит все TG с matching `instance_id` в JSONB `targets[]`
2. Для каждой TG: UPDATE targets (jsonb без matching элементов), bump resource_version через trigger
3. Записать outbox MODIFIED event для каждой изменённой TG
4. Если ни одна TG не содержала этот instance_id → OK без событий (H6)

Алгоритм `RemoveTargetsByInstanceID` в repo (raw SQL, без sqlc для сложного JSONB): UPDATE target_groups WHERE `targets @> [{instance_id: $1}]` SET targets = jsonb_agg всех elements где `instance_id != $1`, RETURNING uid и актуальный snapshot для outbox.

### B.5 Repo (sqlc + handwritten)

#### internal/repo/nlb_repo.go

Реализует `NLBRepo`. Использует `kacho-corelib/db.Transactor` + `outbox.Writer`.
Паттерн: `transactor.WithTx` → `queries.UpsertNLB` (INSERT ... ON CONFLICT DO UPDATE) →
`outboxWriter.WriteEvent(ADDED/MODIFIED)`.

`GetPendingReconcile`: NLB в состояниях CREATING/UPDATING/DELETING или `generation > observed_generation` (recovery J4).

OCC (L9): UPDATE-ветка Upsert использует `SELECT FOR UPDATE`; если 0 rows affected → ABORTED.

#### internal/repo/target_group_repo.go

Аналогично `NLBRepo`. OCC для L16.

`RemoveTargetsByInstanceID` — raw SQL (см. B.4 выше), не через sqlc (слишком специфичный JSONB).

#### internal/repo/filter_builder.go

```go
type FieldFilter struct {
    FolderID string
    Name     string
    LabelSel map[string]string
}

func BuildWhere(f FieldFilter) (string, []interface{}) {
    var clauses []string
    var args    []interface{}
    n := 1
    if f.FolderID != "" {
        clauses = append(clauses, fmt.Sprintf("folder_id = $%d", n))
        args = append(args, f.FolderID); n++
    }
    // аналогично для Name, LabelSel (jsonb @> $n)
    return strings.Join(clauses, " AND "), args
}
```

### B.6 Handler (thin gRPC transport)

#### internal/handler/nlb_handler.go

Тонкий transport-слой: parse request → service.Upsert/Delete/List → format response.
Transport-check: `req.NetworkLoadBalancers[i].Status != nil` → немедленно INVALID_ARGUMENT (L2).
`Watch`: parse resource_version (INVALID_ARGUMENT при non-numeric — L11) → `hub.Subscribe()` →
stream events; `mapWatchErr` возвращает OUT_OF_RANGE при Gone (K6).

**Запрет:** никакой бизнес-логики в handler. Вся остальная валидация — в service.

#### internal/handler/target_group_handler.go

Аналогично `NLBHandler`. Reject если `req.TargetGroups[i].Status != nil` → INVALID_ARGUMENT (L3).

#### internal/handler/internal_handler.go

Реализует `LoadBalancerInternal`: `NetworkLoadBalancerExists`, `TargetGroupExists`,
`UpdateNetworkLoadBalancerStatus`, `UpdateTargetGroupStatus`, `RemoveTarget`.

Этот handler **не регистрируется** через api-gateway наружу (constraint из CLAUDE.md §7).

### B.7 Reconciler — NLB lifecycle

**Acceptance scenarios:** E1–E3, J1–J6

TargetGroup **не обрабатывается** reconciler-ом — переход CREATING → READY синхронный в service (B2).

#### internal/reconciler/dispatcher.go

Тикер `pollInterval` (default 1 с). На каждый тик: `nlbRepo.GetPendingReconcile(ctx, 10)` (batch
LIMIT 10, J5), для каждого — `go d.handleNLB(ctx, nlb)`.

#### internal/reconciler/advisory_lock.go

`TryAcquire(ctx, pool, uid) (bool, func(), error)` — вызывает
`pg_try_advisory_lock(fnv64a(uid))`. При успехе — возвращает release-функцию
(`pg_advisory_unlock`). При занятом lock — возвращает `(false, nil, nil)`.
Тест J1 использует channel-based barrier (`ready := make(chan struct{})`) — детерминированный старт.

#### internal/reconciler/nlb_handler.go — lifecycle NLB

`handleNLB` алгоритм:
1. `TryAcquire` → если занято, return (J1)
2. Если `DeletionTimestamp != nil` → `nlbRepo.Delete(uid)` (физическое удаление, D5)
3. Если state == CREATING → `runTransition` (E1)
4. Если state == UPDATING → `runTransition` (E2)
5. Иначе → no-op (J2)

`runTransition` алгоритм:
1. Для UPDATING: если `generation <= observedGeneration` → no-op (J2, E3)
2. `time.Sleep(simConfig.NLBDelay())` (5–15 с prod, 100–200 мс тесты)
3. Re-read из БД (read-after-sleep для E3 idempotency; проверить deletion)
4. `internalSvc.UpdateNetworkLoadBalancerStatus(uid, {State: ACTIVE, ExternalIPs: [computeExternalIP(uid)], ObservedGeneration: current.Generation})` (E1, K1, J4)

`computeExternalIP(uid)` — FNV32 хеш → `10.255.{byte2}.{byte1}` (OQ-3, вариант B, детерминированный).

**SimConfig:**
```go
type SimConfig struct{ NLBMinMs, NLBMaxMs int }
// env: KACHO_LOADBALANCER_SIM_NLB_MIN_MS=5000, _MAX_MS=15000
```

// computeExternalIP — детерминированный симулированный IP из диапазона 10.255.X.X (OQ-3, вариант B)
func computeExternalIP(uid string) string {
    h := fnv.New32a()
    h.Write([]byte(uid))
    v := h.Sum32()
    return fmt.Sprintf("10.255.%d.%d", (v>>8)%256, v%256)
}
```

**SimConfig — параметризация задержек:**

```go
type SimConfig struct {
    NLBMinMs int
    NLBMaxMs int
}

func SimConfigFromEnv() SimConfig {
    return SimConfig{
        NLBMinMs: envInt("KACHO_LOADBALANCER_SIM_NLB_MIN_MS", 5000),
        NLBMaxMs: envInt("KACHO_LOADBALANCER_SIM_NLB_MAX_MS", 15000),
    }
}

func (c SimConfig) NLBDelay() time.Duration {
    return randomBetween(c.NLBMinMs, c.NLBMaxMs)
}
```

Integration-тесты переопределяют через env: `KACHO_LOADBALANCER_SIM_NLB_MIN_MS=100`,
`KACHO_LOADBALANCER_SIM_NLB_MAX_MS=200`.

### B.8 Cross-service clients

Три клиента, каждый реализует соответствующий port-интерфейс из `service/ports.go`.
Все используют `kacho-corelib/grpcclient` для dial. Timeout 5 с, retry 1× на UNAVAILABLE.
При UNAVAILABLE — возвращают обёрнутую ошибку `ErrUpstream`, которую service
маппит в gRPC UNAVAILABLE (C5, C6, G3, G4).

- `folder_client.go` — `FolderClient` → `ResourceManagerInternal/FolderExists`
- `subnet_client.go` — `SubnetClient` → `VpcInternal/SubnetExists`
- `instance_client.go` — `InstanceClient` → `ComputeInternal/InstanceExists` (при указанном instanceId в Target, C2, C6)

### B.9 Internal RPC RemoveTarget + изменения в kacho-compute

**RemoveTarget** реализован в `internal/handler/internal_handler.go` loadbalancer-сервиса (см. B.4/B.6).

**Изменения в kacho-compute** для finalizer `loadbalancer.kacho.io/target-deregister`:

1. **`internal/service/ports.go`** — добавить port-интерфейс:
   ```go
   type LoadBalancerClient interface {
       RemoveTarget(ctx context.Context, instanceUID string) error
   }
   ```

2. **`internal/clients/loadbalancer_client.go`** — новый файл, реализует `LoadBalancerClient`:
   ```go
   func (c *LBGRPCClient) RemoveTarget(ctx context.Context, instanceUID string) error {
       ctxT, cancel := context.WithTimeout(ctx, 5*time.Second)
       defer cancel()
       _, err := c.client.RemoveTarget(ctxT, &lbv1.RemoveTargetRequest{InstanceId: instanceUID})
       return mapGRPCErr(err)
   }
   ```

3. **`internal/service/instance.go`** — в `Upsert` автоматически добавлять оба finalizer при
   создании Instance (I3): `"compute.kacho.io/disk-detach"` и `"loadbalancer.kacho.io/target-deregister"`.

4. **`internal/reconciler/instance_handler.go`** — в `runFinalizerDetach` два finalizer
   обрабатываются параллельно через `sync.WaitGroup` (I1, OQ-4):
   - Горутина A (`loadbalancer.kacho.io/target-deregister`): `lbClient.RemoveTarget(ctx, inst.UID)` → при успехе `instanceRepo.RemoveFinalizer(...)`; при UNAVAILABLE — логировать и **не** снимать finalizer (I4, retry на следующем poll)
   - Горутина B (`compute.kacho.io/disk-detach`): существующий disk-detach → `instanceRepo.RemoveFinalizer(...)`
   - После `wg.Wait()`: если `current.Finalizers` пуст → `instanceRepo.Delete(uid)` (физическое удаление)

### B.10 cmd/main.go — composition root

Единственное место wiring. Последовательность инициализации:

1. `db.NewPool` → pgxpool из `KACHO_LOADBALANCER_DB_DSN`
2. `db.NewTransactor`, `outbox.NewWriter("kacho_loadbalancer")`
3. `watch.NewHub(ctx, pool, {ChannelName: "kacho_loadbalancer"})`
4. Repos: `repo.NewNLBRepo(pool, transactor, outboxWriter)`, `repo.NewTargetGroupRepo(...)`
5. Clients: `grpcclient.Dial(cfg.ResourceManagerAddr/VPCAddr/ComputeAddr)` → `NewFolderGRPCClient/NewSubnetGRPCClient/NewInstanceGRPCClient`
6. Services: `service.NewInternalService(nlbRepo, tgRepo, hub)`, `service.NewNLBService(nlbRepo, tgRepo, folderClient, hub)`, `service.NewTargetGroupService(tgRepo, folderClient, subnetClient, instanceClient, hub)`
7. `go reconciler.NewDispatcher(nlbRepo, internalSvc, pool, simCfg).Run(ctx)` (только NLB; TG — синхронный)
8. `go watch.RunCleanup(ctx, pool, "kacho_loadbalancer")` (J6)
9. `grpcsrv.NewServer` → регистрировать `NLBHandler`, `TargetGroupHandler`, `InternalHandler` (LoadBalancerInternal — НЕ проксируется через api-gateway, constraint #7)

Subcommands: `serve` и `migrate` (goose up). Init-container в K8s запускает `migrate`.

### B.11 Helm chart + Dockerfile

Multi-stage Dockerfile: `golang:1.22-alpine` → `gcr.io/distroless/static-debian12`.
Бинарь: `CGO_ENABLED=0 go build -o /app/loadbalancer ./cmd/loadbalancer`.
Image: `prorobotech/kacho-loadbalancer:0.5.0`.

`deploy/Chart.yaml`: `name: loadbalancer`, `version: 0.5.0`.

`deploy/values.yaml / values.dev.yaml` — ключевые env:
`KACHO_LOADBALANCER_DB_DSN`, `KACHO_LOADBALANCER_RESOURCE_MANAGER_ADDR`,
`KACHO_LOADBALANCER_VPC_ADDR`, `KACHO_LOADBALANCER_COMPUTE_ADDR`,
`KACHO_LOADBALANCER_SIM_NLB_MIN_MS=5000`, `KACHO_LOADBALANCER_SIM_NLB_MAX_MS=15000`.
`service.port: 9090`, liveness/readiness через grpc_health_probe (M5).
Init-container запускает `/loadbalancer migrate`.

### B.12 Tests

**Unit-тесты** `internal/service/` через `testify/mock` — нет Postgres.
Именование `Test<Resource>_<ScenarioID>_<ShortDesc>`. Примеры: `TestNLB_L2_StatusInUpsert`,
`TestNLB_L13_DuplicatePortProtocol`, `TestNLB_L14_InvalidName`, `TestNLB_F1_TGNotFound`,
`TestNLB_F4_TGDifferentFolder`, `TestTargetGroup_B7_DeleteAttachedToNLB`,
`TestTargetGroup_C1_SubnetNotFound`, `TestTargetGroup_L12_InvalidIP`.

**Integration-тесты** `internal/service/*_acceptance_test.go` с testcontainers-Postgres.
Задержки 100–200 мс (env override). Timeout assertions 60 с.
Покрывают: B1–B7, C1–C6, D1–D6, E1–E3, F1–F4, G1–G4, H1–H8, J1–J6, K1–K6, L1–L16, M6.
I1–I4 (finalizer) — тесты в `kacho-compute/internal/service/instance_acceptance_test.go`.
J1 — channel-based barrier для детерминированного старта двух горутин.

---

## §4. Phase C — kacho-deploy (umbrella + e2e/0.5)

**Acceptance scenarios:** M1–M6

### C.1 Helm umbrella update

`kacho-deploy/helm/umbrella/Chart.yaml` — раскомментировать:

```yaml
dependencies:
  - name: loadbalancer
    version: "0.5.0"
    repository: "file://../loadbalancer"
```

`kacho-deploy/helm/umbrella/values.dev.yaml` — добавить:

```yaml
loadbalancer:
  image:
    repository: prorobotech/kacho-loadbalancer
    tag: "0.5.0"
  replicaCount: 1
  env:
    KACHO_LOADBALANCER_DB_DSN: "postgres://kacho:kacho@postgres-loadbalancer:5432/kacho_loadbalancer?sslmode=disable"
    KACHO_LOADBALANCER_RESOURCE_MANAGER_ADDR: "resource-manager.kacho.svc.cluster.local:9090"
    KACHO_LOADBALANCER_VPC_ADDR: "vpc.kacho.svc.cluster.local:9090"
    KACHO_LOADBALANCER_COMPUTE_ADDR: "compute.kacho.svc.cluster.local:9090"
    # Prod delays (e2e использует timeout 60 s)
    KACHO_LOADBALANCER_SIM_NLB_MIN_MS: "5000"
    KACHO_LOADBALANCER_SIM_NLB_MAX_MS: "15000"
```

Также обновить `kacho-compute` в umbrella — добавить env для loadbalancer address:

```yaml
compute:
  env:
    # ...существующие...
    KACHO_COMPUTE_LOADBALANCER_ADDR: "loadbalancer.kacho.svc.cluster.local:9090"
```

### C.2 Postgres для loadbalancer в dev-стенде

В `kacho-deploy/` добавить отдельный Postgres StatefulSet для `kacho_loadbalancer`
(database-per-service, constraint #9). В `values.dev.yaml` — секция `postgres-loadbalancer:`.

### C.3 E2e bash скрипты (port-forward)

`kacho-deploy/e2e/0.5/` — 5 скриптов:

**M1-full-flow.sh** (M1): Полный flow — Folder → Network → Subnet → Disk (wait READY) →
Instance (wait RUNNING, 60 с) → TargetGroup (ожидать `state=READY` синхронно) →
NLB (wait ACTIVE, 60 с) → List NLB. Port-forward: 9090 (resource-manager), 9091 (vpc),
9092 (compute), 9093 (loadbalancer). Проверить `external_ips` в ACTIVE-ответе, наличие
`loadbalancer.kacho.io/target-deregister` в `finalizers` Instance.

**M2-finalizer.sh** (M2): Delete Instance (из M1) → Watch на TargetGroupService получает MODIFIED
(target удалён) → Watch на InstanceService получает DELETED → проверить через List.

**M3-nlb-update.sh** (M3): Upsert NLB с дополнительным listener (port=443) → Watch получает
UPDATING → ACTIVE в течение 60 с → List проверяет два listeners.

**M4-full-replace-atg.sh** (M4): Создать два TG, привязать к NLB, затем Upsert NLB с одним TG →
проверить full-replace: в List только один ATG, второй TG не удалён.

**M5-helm-deploy.sh** (M5): `helm upgrade --install`, wait pod Ready, grpc_health_probe,
`psql -c "SELECT id FROM regions"` возвращает `kacho-region-a`.

---

## §5. Phase D — Smoke + tag v0.5.0

**Dependency:** sub-phases 0.2, 0.3, 0.4 деплоятся все вместе в kind-кластере.

### D.1 Smoke-сценарий

```bash
# 1. Поднять стенд
cd kacho-deploy && make dev-up

# 2. Проверить loadbalancer pod
kubectl wait pod -l app=loadbalancer -n kacho --for=condition=Ready --timeout=90s

# 3. Port-forward (все 4 сервиса)
kubectl port-forward svc/resource-manager 9090:9090 -n kacho &
kubectl port-forward svc/vpc              9091:9090 -n kacho &
kubectl port-forward svc/compute          9092:9090 -n kacho &
kubectl port-forward svc/loadbalancer     9093:9090 -n kacho &

# 4. Запустить e2e
make e2e-test PHASE=0.5

# 5. Проверить seed
kubectl exec -n kacho deploy/loadbalancer -- /loadbalancer migrate status

# 6. Снести стенд
make dev-down
```

### D.2 CHANGELOG

Добавить запись в `kacho-workspace/docs/specs/CHANGELOG.md`:

```
## [v0.5.0] — 2026-xx-xx

### Sub-phase 0.5 — LoadBalancer

- kacho-proto: добавлен домен loadbalancer/v1 (network_load_balancer, target_group, internal)
- kacho-loadbalancer: реализован сервис с Clean Architecture
  - NetworkLoadBalancer lifecycle: CREATING → ACTIVE / UPDATING → ACTIVE (5–15 с)
  - TargetGroup: синхронный переход CREATING → READY в handler, без reconciler-задержки
  - Reconciler с pg_advisory_lock, симулированные external_ips из 10.255.X.X
  - Internal RPC RemoveTarget: атомарное удаление targets по instanceId
  - cross-service validation: FolderExists (resource-manager), SubnetExists (vpc), InstanceExists (compute)
  - Полная валидация: regex имени, UUID folder_id, диапазон порта, дубли listener, IP format
- kacho-compute: обновлён для finalizer loadbalancer.kacho.io/target-deregister
  - Finalizer добавляется автоматически при создании Instance
  - Параллельная обработка finalizer-ов disk-detach + target-deregister
  - При UNAVAILABLE loadbalancer — retry без снятия finalizer
- kacho-deploy: loadbalancer добавлен в umbrella helm chart, e2e/0.5 сценарии
- 81 acceptance-сценарий покрыт тестами (integration + e2e)
```

### D.3 Tag

```bash
git -C kacho-loadbalancer tag -a kacho-loadbalancer:0.5.0 -m "sub-phase 0.5 complete"
```

---

## §6. Definition of Done

Полный список критериев — в acceptance §14 (N-группа). Краткая сводка для реализатора:

1. **Все 81 сценарий A1–M6 покрыты** (integration + e2e): `kacho-loadbalancer` тесты зелёные; `kacho-compute` регрессия I-группы зелёная; `make e2e-test PHASE=0.5` зелёный.

2. **Proto**: 3 файла в `kacho-proto/proto/kacho/cloud/loadbalancer/v1/`; `gen/go/` committed; `buf lint` + `buf breaking` чистые.

3. **Clean Architecture соблюдена**: `domain/`+`service/` без pgx/sqlc/grpc-stubs; бизнес-логика не в `handler/`; нет глобальных синглтонов вне `cmd/`.

4. **Reconciler (только NLB)**: `pg_advisory_lock(fnv64a(uid))` per-resource; задержки из env (5–15 с prod); `external_ips = [10.255.X.X]` и `observed_generation = metadata.generation` при ACTIVE; idempotent; recovery после краша; cleanup горутина с `pg_advisory_xact_lock`.

5. **TargetGroup**: синхронный READY в handler, reconciler не нужен.

6. **Cross-service validation**: timeout 5 с, UNAVAILABLE при сбое downstream; same-DB FK для attachedTargetGroups (INVALID_ARGUMENT, не cross-service).

7. **Finalizer** `loadbalancer.kacho.io/target-deregister`: добавляется compute при создании Instance; RemoveTarget атомарен; retry при UNAVAILABLE.

8. **Validation L1–L16**: regex имени, UUID folder_id, port 1–65535, protocol TCP/UDP, uniqueness (port+protocol), valid IPv4, address-or-instanceId, status запрет, page_size, resource_version, OCC ABORTED.

9. **Naming**: proto `kacho.cloud.loadbalancer.v1`; DB `kacho_loadbalancer`; env `KACHO_LOADBALANCER_*`; image `prorobotech/kacho-loadbalancer:0.5.0`; finalizer `loadbalancer.kacho.io/target-deregister`.

10. **CI зелёный**: kacho-proto, kacho-loadbalancer, kacho-compute, kacho-deploy.

11. **CHANGELOG.md** обновлён; тег `kacho-loadbalancer:0.5.0` поставлен.

---

## §7. Execution mode

### Параллельность и последовательность

**Phase A** (kacho-proto) — выполняется первой, блокирует Phase B (нужны Go-stubs).
Агент: `proto-sync`.

**Phase B** (kacho-loadbalancer) — выполняется после A. Внутри Phase B:
- B.1–B.3 (skeleton, migrations, domain) — параллельно, нет взаимозависимостей
- B.4–B.6 (service, repo, handler) — последовательно (repo зависит от migrations, handler — от service)
- B.7 (reconciler) — после B.4–B.6
- B.8 (clients) — параллельно с B.4
- B.9 (изменения compute) — после того как `LoadBalancerInternal` proto стаб готов (Phase A)
- B.10 (cmd/main.go) — последним, связывает всё вместе
- B.11–B.12 (helm, tests) — после B.10

**Phase B.9 (compute changes)** — выполняется параллельно с основной Phase B, зависимость только от Phase A.

**Phase C** (kacho-deploy) — после Phase B.

**Phase D** (smoke + tag) — после Phase C.

### Агенты

| Фаза | Агент |
|---|---|
| A — proto/loadbalancer/v1 | `proto-sync` |
| B.1–B.3 — skeleton + migrations + domain | `service-scaffolder` |
| B.4–B.8 — service + repo + handler + clients | `rpc-implementer` |
| B.7 — reconciler | `rpc-implementer` (тот же, reconciler — часть сервиса) |
| B.9 — compute finalizer changes | `rpc-implementer` |
| B.12 — integration tests | `integration-tester` |
| C — kacho-deploy | `api-gateway-registrar` (umbrella + e2e) |
| Review — после каждой фазы | `go-style-reviewer`, `proto-api-reviewer` |

### Ограничения реализатора

- НЕ начинать кодирование без approve данного плана
- НЕ упоминать «yandex» нигде
- НЕ использовать ORM — только sqlc + handwritten pgx
- НЕ редактировать применённую миграцию
- НЕ писать `status` через `/upsert` — только через `Internal.UpdateStatus`
- НЕ регистрировать `LoadBalancerInternal` в api-gateway
- НЕ вводить broker (Kafka/NATS)
- НЕ создавать единую БД — только `kacho_loadbalancer` отдельно
- JSONB full-replace для listeners, attached_target_groups, targets при Upsert
- TargetGroup НЕ использует reconciler — синхронный переход в handler
- OCC: `SELECT FOR UPDATE` при UPDATE-ветке Upsert (L9, L16)
