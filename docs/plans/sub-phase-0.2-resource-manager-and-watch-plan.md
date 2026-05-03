# Sub-phase 0.2 — Resource Manager + Watch infrastructure — Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` для исполнения. Acceptance APPROVED commit `1df396b` в `kacho-workspace/docs/specs/sub-phase-0.2-resource-manager-and-watch-acceptance.md` (71 сценарий, 9 групп A–I).

**Goal:** `kacho-corelib` получает Watch infrastructure (watch + outbox + selector + common migrations); `kacho-proto` получает домен resourcemanager; `kacho-resource-manager` — полностью реализованный сервис с default-bootstrap, идущий через kind; e2e через port-forward (api-gateway пока 0.6).

**Architecture:** Clean Architecture per `kacho-workspace/CLAUDE.md`: handler → service → repo с port-интерфейсами. Watch Hub — in-process горутина с outbox-чтением, NOTIFY wake-up, ring buffer 1024 events, fan-out на subscribers. Outbox + resource write в одной транзакции. Reconciler-нет: Org/Cloud/Folder без lifecycle.

**Tech stack:** Go 1.22+ (golang.org/x/exp/slog), buf, pgx/v5, sqlc для типизированных запросов, goose миграции, testcontainers-go, grpcurl для e2e.

---

## §0. Resolutions для 4 non-blocking note acceptance-reviewer

| # | Note | Решение |
|---|---|---|
| 1 | G1a — server игнорирует client-`uid` или INVALID_ARGUMENT? | **Server ignores** (вариант A). Безопаснее для существующих клиентов. Проверка теста: response uid !== request uid. |
| 2 | I4 имя тест-функции | Нормализуется на `TestOrganization_I4_OutboxAtomicityViaDirectSQL` |
| 3 | D5 `resourceVersion` в List response | `lastval('resource_version_seq')` (snapshot-version момента запроса) |
| 4 | Cleanup lock-ключ | Константа `kacho-corelib/watch/cleanup_lock.go: const CleanupLockName = "kacho_<svc>_cleanup"`; сервис передаёт SVC при инициализации |

---

## §1. File map (cross-repo)

### `kacho-corelib/` — Phase A
- `migrations/common/0001_resource_events.sql` — sequence + table + indexes
- `migrations/common/0002_advisory_locks.sql` — helper functions (опционально)
- `outbox/outbox.go` — `Writer` тип, `WriteEvent(tx, event)` атомарно с ресурсом
- `outbox/outbox_test.go`
- `watch/hub.go` — `Hub` структура: cursor, ring buffer 1024, subscribers map, NOTIFY listener
- `watch/hub_test.go` — testcontainers + LISTEN/NOTIFY + fan-out smoke
- `watch/event.go` — `Event{Type, Kind, UID, ResourceVersion, Data}`
- `watch/cleanup.go` — фоновая горутина, advisory lock, retention 1 час
- `selector/parser.go` — AST для FieldSelector + LabelSelector
- `selector/sql.go` — генератор `WHERE`-clause + параметризованные значения
- `selector/parser_test.go`, `selector/sql_test.go`
- Bump `go.mod` где надо; добавить depends на `kacho-proto`

### `kacho-proto/` — Phase B
- `proto/kacho/cloud/resourcemanager/v1/organization.proto`
- `proto/kacho/cloud/resourcemanager/v1/cloud.proto`
- `proto/kacho/cloud/resourcemanager/v1/folder.proto`
- `proto/kacho/cloud/resourcemanager/v1/internal.proto` — Internal-сервисы Exists
- `proto/kacho/cloud/common/v1/watch_event.proto` — общий тип WatchEvent (вынесён из 0.1)
- `gen/go/...` — committed после `make generate`

### `kacho-resource-manager/` — Phase C
- `cmd/resource-manager/main.go` — composition root, `serve` + `migrate` subcommands
- `internal/domain/{organization.go, cloud.go, folder.go}` — entities (чистый Go)
- `internal/service/{organization.go, cloud.go, folder.go, ports.go}` — use-cases + port-интерфейсы
- `internal/repo/{organization_repo.go, cloud_repo.go, folder_repo.go, queries/}` — sqlc + handwritten
- `internal/handler/{organization_handler.go, cloud_handler.go, folder_handler.go, internal_handler.go}` — gRPC + Internal
- `internal/bootstrap/default.go` — idempotent default Org/Cloud/Folder
- `migrations/0001_initial.sql` — organizations, clouds, folders таблицы
- `migrations/common/` — sync from kacho-corelib
- `Dockerfile`, `Makefile`, `deploy/Chart.yaml`, `deploy/values.yaml`, `deploy/templates/`
- `.github/workflows/ci.yaml`

### `kacho-deploy/` — Phase D
- `helm/umbrella/Chart.yaml` — раскомментировать `resource-manager` dep
- `helm/umbrella/values.dev.yaml` — добавить `resource-manager:` секцию
- `e2e/0.2/*.sh` — bash-сценарии (D, E, F, H, I группы) через grpcurl + port-forward

---

## §2. Phase A — kacho-corelib (Watch + Outbox + Selector + common migrations)

**Acceptance scenarios:** A1-A8, B1-B10, C1-C6 (24 сценария)

### Phase A milestones

1. **A.1 Common migrations** (C1-C6): sequence, resource_events table, indexes, BEFORE UPDATE trigger helper, cleanup function
2. **A.2 Outbox writer** (A1, A2, A8): `outbox.WriteEvent(tx, event)` атомарно записывает в resource_events; pg_notify('kacho_<svc>') после commit
3. **A.3 Watch Hub** (A3, A4, A5, A6): in-process горутина, cursor по resource_version, ring buffer 1024, NOTIFY wake-up, polling fallback 100ms, fan-out на subscribers
4. **A.4 Watch Gone (A7)**: возврат OUT_OF_RANGE при resourceVersion < min(events)
5. **A.5 Selector parser** (B1-B10): AST + SQL generator, защита от injection через параметризацию
6. **A.6 Cleanup goroutine**: pg_advisory_xact_lock + DELETE retention 1 час

### Phase A deliverables
- 8-12 файлов в kacho-corelib
- Все unit/integration тесты green (testcontainers для outbox/watch)
- Coverage ≥ 70% per package
- go.mod bumped с depends на pgx, listen, sqlc-types

---

## §3. Phase B — kacho-proto/resourcemanager/v1

**Acceptance scenarios:** связаны с D, E, F (через proto-контракт)

### Proto-структуры

#### organization.proto
```protobuf
syntax = "proto3";
package kacho.cloud.resourcemanager.v1;
option go_package = "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/resourcemanager/v1;resourcemanagerv1";

import "kacho/cloud/common/v1/resource_meta.proto";
import "kacho/cloud/common/v1/selector.proto";
import "kacho/cloud/common/v1/watch_event.proto";

message Organization {
  kacho.cloud.common.v1.ResourceMeta metadata = 1;
  OrganizationSpec spec = 2;
}

message OrganizationSpec {
  string display_name = 1;
  string description = 2;
}

message OrganizationUpsertRequest {
  repeated Organization organizations = 1;
}
message OrganizationUpsertResponse {
  repeated Organization organizations = 1;
}

message OrganizationDeleteRequest {
  message Item {
    string uid = 1;
    string name = 2;  // alternative identification
  }
  repeated Item items = 1;
}
message OrganizationDeleteResponse {}

message OrganizationListRequest {
  repeated kacho.cloud.common.v1.Selector selectors = 1;
  string page_token = 10;
  int32 page_size = 11;
}
message OrganizationListResponse {
  repeated Organization organizations = 1;
  string resource_version = 2;
  string next_page_token = 3;
}

message OrganizationWatchRequest {
  repeated kacho.cloud.common.v1.Selector selectors = 1;
  string resource_version = 2;
}

service OrganizationService {
  rpc Upsert(OrganizationUpsertRequest) returns (OrganizationUpsertResponse);
  rpc Delete(OrganizationDeleteRequest) returns (OrganizationDeleteResponse);
  rpc List(OrganizationListRequest) returns (OrganizationListResponse);
  rpc Watch(OrganizationWatchRequest) returns (stream kacho.cloud.common.v1.WatchEvent);
}
```

Аналогично — `cloud.proto`, `folder.proto`. Cloud добавляет parent `organization_id`; Folder — `cloud_id`.

#### internal.proto
```protobuf
service OrganizationInternalService {
  rpc Exists(ExistsRequest) returns (ExistsResponse);
  rpc HasDependents(HasDependentsRequest) returns (HasDependentsResponse);
}
// Те же для CloudInternalService и FolderInternalService
```

#### watch_event.proto (вынесен в common)
```protobuf
package kacho.cloud.common.v1;
message WatchEvent {
  enum EventType { UNSPECIFIED = 0; ADDED = 1; MODIFIED = 2; DELETED = 3; }
  EventType event_type = 1;
  string resource_version = 2;
  bytes data = 3;  // marshalled <Resource>
  string kind = 4;  // "Organization" | "Cloud" | "Folder"
}
```

### Phase B deliverables
- 5 .proto файлов
- Сгенерированные `gen/go/kacho/cloud/resourcemanager/v1/*.pb.go` + `*_grpc.pb.go` committed
- buf lint clean
- В CI verify gen-drift

---

## §4. Phase C — kacho-resource-manager service

**Acceptance scenarios:** D1-D14, E1-E8, F1-F5, G1a/G2-G12, H1-H4 (51 сценарий)

### Phase C milestones

#### C.1 Skeleton (Clean Architecture)

`internal/domain/organization.go`:
```go
package domain

import "time"

type Organization struct {
    UID, Name              string
    Labels, Annotations    map[string]string
    CreationTimestamp      time.Time
    ResourceVersion        int64
    DeletionTimestamp      *time.Time
    DisplayName, Description string
}
// Аналогично Cloud (с OrganizationID), Folder (с CloudID + OrganizationID)
```

`internal/service/ports.go`:
```go
package service

import (
    "context"
    "github.com/PRO-Robotech/kacho-resource-manager/internal/domain"
)

type OrganizationRepo interface {
    Get(ctx context.Context, identifier domain.OrgIdentifier) (*domain.Organization, error)
    List(ctx context.Context, filter SelectorFilter, page Pagination) ([]*domain.Organization, int64, error)
    Upsert(ctx context.Context, org *domain.Organization) (*domain.Organization, error)
    Delete(ctx context.Context, uid string) error
    HasDependents(ctx context.Context, uid string) (bool, []string, error)
    // returns (count, kinds[]) для PreconditionFailure.violations
}
// Аналогично CloudRepo, FolderRepo
```

`internal/service/organization.go`: implements use-cases via ports. NEVER imports pgx, grpc-stubs, sqlc-types.

`internal/repo/organization_repo.go`: реализует `OrganizationRepo`. Использует pgxpool + sqlc-генерированные структуры. Транзакции через `kacho-corelib/db.Transactor`. Outbox-event через `kacho-corelib/outbox.Writer`.

`internal/handler/organization_handler.go`: тонкий gRPC-handler. Парсит request, вызывает service, форматирует response. NEVER содержит бизнес-логики.

#### C.2 Migrations

`migrations/0001_initial.sql`:
- organizations (uid PK, name UNIQUE globally, labels JSONB, annotations JSONB, creation_timestamp, resource_version, deletion_timestamp NULL, finalizers TEXT[], spec JSONB)
- GIN index on labels (jsonb_path_ops)
- BEFORE UPDATE trigger sets resource_version = nextval('resource_version_seq')
- clouds (uid PK, organization_id FK→organizations DEFERRABLE INITIALLY DEFERRED, name, ..., UNIQUE (organization_id, name))
- folders (uid PK, cloud_id FK→clouds, organization_id, name, ..., UNIQUE (cloud_id, name))

FK strategy: same-DB, RESTRICT (no cascade). Сервис ловит pgcode.ForeignKeyViolation → FAILED_PRECONDITION.

#### C.3 Default bootstrap (H1-H4)

`internal/bootstrap/default.go`:
```go
func EnsureDefaults(ctx context.Context, repos *Repos) error {
    // 1. SELECT FOR UPDATE on advisory_lock(hashtext("default_bootstrap"))
    // 2. Get/create Organization "default"
    // 3. Get/create Cloud "default" в этой Org
    // 4. Get/create Folder "default" в этом Cloud
    // 5. Idempotent — повторный запуск вернёт existing UIDs
}
```
Вызывается из main.go при старте `serve`, после миграций.

#### C.4 Watch endpoint integration

Service wraps `kacho-corelib/watch.Hub`. Handler делает:
```go
func (h *Handler) Watch(req *Req, stream Stream) error {
    sub := h.hub.Subscribe(parseSelectors(req.Selectors), req.ResourceVersion)
    defer h.hub.Unsubscribe(sub)
    for evt := range sub.C {
        if err := stream.Send(evt); err != nil { return err }
    }
}
```

Hub.Subscribe возвращает Catch-up + Live channel. Handle Gone (OUT_OF_RANGE) inside Subscribe.

#### C.5 Helm chart

`deploy/Chart.yaml`, `deploy/values.yaml`, `deploy/templates/{deployment.yaml, service.yaml, configmap.yaml, secret.yaml}` per `03-deployment-and-operations.md` §6 шаблон.

#### C.6 main.go (composition root)

```go
func serve(ctx context.Context, cfg Config) error {
    pool, err := db.NewPool(ctx, cfg.DBDsn)
    transactor := db.NewTransactor(pool)
    outboxWriter := outbox.NewWriter("kacho_resource_manager")
    hub := watch.NewHub(ctx, pool, watch.HubOpts{
        ChannelName: "kacho_resource_manager",
        SVC:         "resource_manager",
    })
    orgRepo := repo.NewOrganizationRepo(pool, transactor, outboxWriter)
    cloudRepo := repo.NewCloudRepo(pool, transactor, outboxWriter)
    folderRepo := repo.NewFolderRepo(pool, transactor, outboxWriter)
    orgSvc := service.NewOrganizationService(orgRepo, cloudRepo, hub)
    cloudSvc := service.NewCloudService(cloudRepo, orgRepo, folderRepo, hub)
    folderSvc := service.NewFolderService(folderRepo, cloudRepo, hub)

    // Default bootstrap
    if err := bootstrap.EnsureDefaults(ctx, orgRepo, cloudRepo, folderRepo); err != nil {
        return err
    }

    // Cleanup goroutine
    go watch.RunCleanup(ctx, pool, "kacho_resource_manager")

    grpcSrv := grpcsrv.NewServer()
    resourcemanagerv1.RegisterOrganizationServiceServer(grpcSrv, handler.NewOrganizationHandler(orgSvc))
    // ...
    return grpcSrv.Serve(listener)
}
```

#### C.7 Tests
- Unit-тесты `internal/service/*_test.go` через mock-port (testify/mock)
- Integration-тесты `internal/service/*_acceptance_test.go` через testcontainers-Postgres
- Имена: `TestOrganization_<ID>_<ShortDesc>` (см. §0 acceptance)

### Phase C deliverables
- ~25 Go-файлов
- Migrations 0001
- Helm chart
- Все integration-тесты green (testcontainers)

---

## §5. Phase D — kacho-deploy + e2e + smoke

### D.1 Update helm/umbrella

Раскомментировать `resource-manager` в `Chart.yaml`. Добавить `resource-manager:` секцию в `values.dev.yaml` (image, ports 9090/8080, env KACHO_RESOURCE_MANAGER_DB_DSN, replicas: 1).

### D.2 e2e bash scripts

`kacho-deploy/e2e/0.2/`:
- D1-D14, E1-E8, F1-F5, G1-G12, H1-H4, I1-I5 → каждый сценарий → bash через grpcurl + port-forward (`kubectl port-forward svc/resource-manager 9090:9090`).
- I3 (Gone) — пометить `@manual / @slow`.

### D.3 Smoke
- `make dev-up` (с resource-manager)
- `make e2e-test` или прогон выборочных E*-сценариев
- Verify default Org/Cloud/Folder через grpcurl
- `make dev-down` clean

### D.4 CHANGELOG + tag v0.2.0

---

## §6. Definition of Done

1. ✅ Все 71 acceptance-сценарий покрыт integration-тестом ИЛИ e2e-bash (для I-группы) ИЛИ unit-тестом (для B-группы selector)
2. ✅ kacho-corelib: watch/, outbox/, selector/, migrations/common/ есть; coverage ≥ 70% per package
3. ✅ kacho-proto: resourcemanager/v1/{organization,cloud,folder,internal}.proto + watch_event.proto в common; gen/go/ committed; buf lint clean
4. ✅ kacho-resource-manager: Clean Architecture (handler→service→repo); default bootstrap idempotent; helm chart; tests green
5. ✅ kacho-deploy: helm/umbrella содержит resource-manager как dep; e2e/0.2/*.sh созданы и зелёные
6. ✅ make dev-up < 5 минут (включая resource-manager pod)
7. ✅ Smoke: grpcurl OrganizationService/List возвращает default-org; Upsert Cloud работает; Watch стрим показывает ADDED/MODIFIED/DELETED; Gone (OUT_OF_RANGE) корректен на старом resourceVersion
8. ✅ CI всех затронутых репо зелёный
9. ✅ CHANGELOG обновлён с записью «sub-phase 0.2 завершена»
10. ✅ Tag `v0.2.0` поставлен в kacho-workspace

---

## §7. Execution mode

Пользователь дал автономию до готового блока. Цепочка:

1. Этот план — голый skeleton
2. Phase A subagent (Sonnet) — kacho-corelib watch+outbox+selector+migrations
3. Phase B subagent (Sonnet) — kacho-proto resourcemanager
4. Phase C subagent (Sonnet) — kacho-resource-manager service (большой; возможно 2-3 субагента: skeleton+repo, handler+watch, bootstrap+helm)
5. Phase D myself — helm umbrella update + e2e/0.2 scripts (механика) + smoke run
6. Возврат к пользователю на финальную верификацию

Параллелизм: Phase A и Phase B независимы — могут идти параллельно если безопасно (разные репо). Phase C блокируется обоими. Phase D блокируется Phase C.

После Phase D → стоп → отчёт пользователю → пользователь делает grpcurl-проверку и approves smoke.
