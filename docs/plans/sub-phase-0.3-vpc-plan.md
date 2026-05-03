# Sub-phase 0.3 — VPC — Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` для исполнения. Acceptance APPROVED commit `809b41b` в `kacho-workspace/docs/specs/sub-phase-0.3-vpc-acceptance.md` (82 сценария, 10 групп A–J).

**Goal:** `kacho-proto` получает домен `vpc/v1`; `kacho-vpc` — полностью реализованный синхронный сервис с пятью ресурсами (Network, Subnet, SecurityGroup+SecurityGroupRule, RouteTable+StaticRoute, Address) и кросс-сервисной валидацией `folderId` через resource-manager; e2e через port-forward; никакого async reconciler.

**Architecture:** Clean Architecture per `kacho-workspace/CLAUDE.md`: handler → service → repo с port-интерфейсами. Watch Hub — in-process (kacho-corelib/watch), outbox-запись в той же транзакции, что и мутация ресурса. Lifecycle синхронный: статус `ACTIVE` / `RESERVED` выставляется в той же транзакции, что и Upsert. Address имеет минимальный lifecycle `RESERVED → IN_USE → RELEASED` через `Internal.UpdateStatus`. Кросс-сервисный вызов vpc → resource-manager через grpc-client с timeout 5s, retry 1× on UNAVAILABLE.

**Tech stack:** Go 1.22+ (log/slog), buf, pgx/v5, sqlc, goose миграции, testcontainers-go, grpcurl для e2e. Зависимости `kacho-corelib/{watch,outbox,selector,migrations/common}` через go.mod replace/tag — без дублирования per-service.

---

## §0. Resolutions для 6 Open Questions acceptance-reviewer

Все OQ закрыты в acceptance-документе (round 2). Таблица ниже — быстрый reference для имплементации.

| # | Вопрос | Решение | Acceptance ref |
|---|--------|---------|----------------|
| Q1 | `network_id` в FieldSelector | Вариант (c): `FieldSelector.refs[{kind:"Network", uid:<net-uid>}]` — proto-изменений нет | §0 соглашения, C6 |
| Q2 | CIDR-валидация | `net.ParseCIDR` + `ip.Equal(network.IP)` check; host-bits-set → `INVALID_ARGUMENT field="spec.cidrBlock"` | §0 соглашения, I2, I19 |
| Q3 | Симулированный IP для Address | `203.0.113.0/24` (TEST-NET-3, RFC 5737); функция `assignIP(uid)`, retry on UNIQUE conflict (max 10 попыток) | §0 соглашения, F1 |
| Q4 | `SecurityGroupRule.id` семантика | Server-assigned UUID, генерируется заново при каждом Upsert (full-replace); клиент не передаёт `id` правил | §0 соглашения, D3 |
| Q5 | Concurrent create-collision | `ABORTED` с retry-семантикой; `ALREADY_EXISTS` не используется; trigger — `pgcode.UniqueViolation` при INSERT | §0 соглашения, I13, I18 |
| Q6 | `INTERNAL` Address type | Не поддерживается в 0.3; попытка создать → `INVALID_ARGUMENT`; только `EXTERNAL` | §0 «Что НЕ входит», I12 |

**Дополнительные non-blocking notes от reviewer (учтены в плане):**

- **Note 1:** `RouteTableExists` integration-тесты добавлены в G-группу (G-sub impl, §3 Phase B.5) — acceptance сценарий для метода отсутствует явно, но proto A8 требует метода `RouteTableExists`.
- **Note 2:** F5 first-call `UpdateStatus` when no-diff → no-op (`resourceVersion` не меняется) — реализуется в `AddressService.UpdateStatus` через diff-check перед записью; соответствует idempotency policy B2/F2.
- **Note 3:** E5 optional enhancement — `List RouteTable` filtered by `network_id` через `refs[kind=Network]` (аналогично C6 для Subnet). Включён как задача в B.5 в рамках `selector`-расширения; не блокирует DoD.

---

## §1. File map (cross-repo)

### `kacho-proto/` — Phase A
```
proto/kacho/cloud/vpc/v1/
  network.proto
  subnet.proto
  security_group.proto
  route_table.proto
  address.proto
  internal.proto
gen/go/kacho/cloud/vpc/v1/
  *.pb.go, *_grpc.pb.go  (committed после buf generate)
```

### `kacho-vpc/` — Phase B (новый репо-сиблинг в `cloud-demo/`)
```
cmd/vpc/main.go
internal/
  domain/
    network.go
    subnet.go
    security_group.go
    route_table.go
    address.go
  service/
    ports.go
    network_service.go
    subnet_service.go
    security_group_service.go
    route_table_service.go
    address_service.go
  repo/
    network_repo.go
    subnet_repo.go
    security_group_repo.go
    route_table_repo.go
    address_repo.go
    queries/          (sqlc-generated)
  clients/
    resource_manager_client.go
  handler/
    network_handler.go
    subnet_handler.go
    security_group_handler.go
    route_table_handler.go
    address_handler.go
    internal_handler.go
migrations/
  0001_initial.sql
  common/             (sync из kacho-corelib/migrations/common/)
Dockerfile
Makefile
deploy/
  Chart.yaml
  values.yaml
  values.dev.yaml
  templates/
    deployment.yaml
    service.yaml
    configmap.yaml
    secret.yaml
go.mod, go.sum
.golangci.yml
.github/workflows/ci.yaml
```

### `kacho-deploy/` — Phase C
```
helm/umbrella/Chart.yaml          (добавить vpc dep)
helm/umbrella/values.dev.yaml     (добавить vpc секцию)
e2e/0.3/
  J1-network-upsert-list.sh
  J2-network-subnet-flow.sh
  J3-delete-blocked.sh
  J4-watch-subnet.sh
  J5-address-flow.sh
  J6-helm-deploy-check.sh
```

---

## §2. Phase A — kacho-proto/vpc/v1

**Acceptance scenarios:** A1–A8

### A.1 network.proto (A3)

```protobuf
syntax = "proto3";
package kacho.cloud.vpc.v1;
option go_package = "github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/vpc/v1;vpcv1";

import "kacho/cloud/common/v1/resource_meta.proto";
import "kacho/cloud/common/v1/selector.proto";
import "kacho/cloud/common/v1/watch_event.proto";

message Network {
  kacho.cloud.common.v1.ResourceMeta metadata = 1;
  NetworkSpec spec = 2;
  NetworkStatus status = 3;
}

message NetworkSpec {
  string display_name = 1;
  string description = 2;
}

message NetworkStatus {
  string state = 1;  // enum: ACTIVE, DELETING
}

message NetworkUpsertRequest  { repeated Network networks = 1; }
message NetworkUpsertResponse { repeated Network networks = 1; }

message NetworkDeleteRequest {
  message Item { string uid = 1; string name = 2; }
  repeated Item networks = 1;
}
message NetworkDeleteResponse {}

message NetworkListRequest {
  repeated kacho.cloud.common.v1.Selector selectors = 1;
  string page_token = 10;
  int32  page_size  = 11;
}
message NetworkListResponse {
  repeated Network networks = 1;
  string resource_version  = 2;
  string next_page_token   = 3;
}

message NetworkWatchRequest {
  repeated kacho.cloud.common.v1.Selector selectors = 1;
  string resource_version = 2;
}

service NetworkService {
  rpc Upsert(NetworkUpsertRequest) returns (NetworkUpsertResponse);
  rpc Delete(NetworkDeleteRequest) returns (NetworkDeleteResponse);
  rpc List(NetworkListRequest)     returns (NetworkListResponse);
  rpc Watch(NetworkWatchRequest)   returns (stream kacho.cloud.common.v1.WatchEvent);
}
```

### A.2 subnet.proto (A4)

`Subnet.Spec`: `network_id string`, `cidr_block string`, `zone_id string`, `display_name string`, `description string`.
`Subnet.Status`: `state string` (ACTIVE, DELETING).
Структура Upsert/Delete/List/Watch — аналогична Network; Delete Item по `uid` или `name+folderId`.

### A.3 security_group.proto (A5)

`SecurityGroupRule` message (вложен в файл): поля `id string`, `direction string`, `protocol string`, `port_range_min int32`, `port_range_max int32`, `cidr_blocks repeated string`, `description string`.
`SecurityGroup.Spec`: `description string`, `rules repeated SecurityGroupRule`.
`SecurityGroup.Status`: `state string` (ACTIVE, DELETING).

### A.4 route_table.proto (A6)

`StaticRoute` message: `destination_prefix string`, `next_hop_address string`, `description string`.
`RouteTable.Spec`: `network_id string`, `description string`, `static_routes repeated StaticRoute`.
`RouteTable.Status`: `state string` (ACTIVE, DELETING).

### A.5 address.proto (A7)

`Address.Spec`: `address_type string`, `zone_id string`, `description string`.
`Address.Status`: `state string` (RESERVED, IN_USE, RELEASED), `allocated_ipv4 string`.

### A.6 internal.proto (A8)

```protobuf
syntax = "proto3";
package kacho.cloud.vpc.v1;

message NetworkExistsRequest    { string uid = 1; }
message SubnetExistsRequest     { string uid = 1; }
message SecurityGroupExistsRequest { string uid = 1; }
message RouteTableExistsRequest { string uid = 1; }
message AddressExistsRequest    { string uid = 1; }
message ExistsResponse          { bool exists = 1; }

message AddressUpdateStatusRequest {
  string uid        = 1;
  string state      = 2;  // IN_USE | RELEASED | RESERVED
}
message AddressUpdateStatusResponse {
  // пустой; клиент перечитывает при необходимости
}

service VpcInternalService {
  rpc NetworkExists(NetworkExistsRequest)               returns (ExistsResponse);
  rpc SubnetExists(SubnetExistsRequest)                 returns (ExistsResponse);
  rpc SecurityGroupExists(SecurityGroupExistsRequest)   returns (ExistsResponse);
  rpc RouteTableExists(RouteTableExistsRequest)         returns (ExistsResponse);
  rpc AddressExists(AddressExistsRequest)               returns (ExistsResponse);
  rpc UpdateStatus(AddressUpdateStatusRequest)          returns (AddressUpdateStatusResponse);
}
```

*Примечание:* `UpdateStatus` покрывает F3, F4, F5; `RouteTableExists` — note 1 от reviewer (нет явного acceptance-сценария, но метод требуется proto A8 и будет использован в 0.4–0.5).

### A.7 buf generate + commit gen/

После написания proto:
1. `buf lint proto/kacho/cloud/vpc/v1/` → 0 предупреждений (A1).
2. `buf breaking --against '.git#branch=main'` → чисто (A2, только при update).
3. `buf generate` → `gen/go/kacho/cloud/vpc/v1/` обновлён.
4. Commit `gen/` в kacho-proto.

### Phase A deliverables
- 6 `.proto`-файлов
- Сгенерированные `*.pb.go` + `*_grpc.pb.go` committed
- `buf lint` чисто
- CI `kacho-proto` зелёный (buf-lint + buf-breaking + gen-drift check)

---

## §3. Phase B — kacho-vpc service (Clean Architecture)

**Acceptance scenarios:** B1–B8, C1–C10, D1–D6, E1–E5, F1–F8, G1–G7, H1–H5, I1–I19

### B.1 Skeleton (Clean Architecture layout)

Инициализировать репо `kacho-vpc` в `cloud-demo/kacho-vpc/`:

```
go mod init github.com/PRO-Robotech/kacho-vpc
```

`go.mod` зависимости:
```
github.com/PRO-Robotech/kacho-proto       v0.3.0
github.com/PRO-Robotech/kacho-corelib     v0.3.0
github.com/jackc/pgx/v5
github.com/sqlc-dev/pqtype
github.com/pressly/goose/v3
google.golang.org/grpc
google.golang.org/protobuf
github.com/google/uuid
```

Создать директории согласно §1 File map. Добавить `.gitignore`, пустые `doc.go` в каждом пакете.

**Dependency rule (строго):**
- `domain/` → только stdlib + `kacho-proto` (типы proto как target для маппинга)
- `service/` → только `domain/`; определяет port-интерфейсы
- `repo/` → `domain/` + pgx + sqlc-types; реализует port-интерфейсы из service
- `clients/` → `domain/` + grpc-stubs из kacho-proto; реализует port-интерфейсы из service
- `handler/` → `service/` + grpc-stubs; тонкий transport (никакой бизнес-логики)
- `cmd/vpc/main.go` → все пакеты (единственное место wiring)

### B.2 Migrations

**`migrations/common/`** — синхронизируются из `kacho-corelib/migrations/common/` через `make sync-migrations`. Содержат: `resource_version_seq`, `resource_events`, BEFORE UPDATE trigger, cleanup function.

**`migrations/0001_initial.sql`** (goose `-- +goose Up / Down`). Создаёт 7 таблиц в БД `kacho_vpc`:

| Таблица | PK | Ключевые поля | Constraints |
|---|---|---|---|
| `networks` | `uid UUID` | `folder_id`, `name`, `labels JSONB`, `resource_version BIGINT`, `state TEXT='ACTIVE'` | UNIQUE `(folder_id,name)`; GIN on labels; BEFORE UPDATE trigger `bump_resource_version()` |
| `subnets` | `uid UUID` | `folder_id`, `network_id UUID`, `cidr_block CIDR`, `zone_id TEXT`, `state TEXT='ACTIVE'` | UNIQUE `(folder_id,name)`; FK `network_id → networks(uid) ON DELETE RESTRICT`; idx on `network_id` |
| `security_groups` | `uid UUID` | `folder_id`, `name`, `description`, `state TEXT='ACTIVE'` | UNIQUE `(folder_id,name)`; GIN on labels |
| `security_group_rules` | `id UUID` | `security_group_id UUID`, `direction`, `protocol`, `port_range_min/max INT`, `cidr_blocks TEXT[]`, `sort_order INT` | FK `security_group_id → security_groups(uid) ON DELETE CASCADE` (D4) |
| `route_tables` | `uid UUID` | `folder_id`, `network_id UUID`, `description`, `state TEXT='ACTIVE'` | UNIQUE `(folder_id,name)`; FK `network_id → networks(uid) ON DELETE RESTRICT` |
| `static_routes` | `id UUID` | `route_table_id UUID`, `destination_prefix CIDR`, `next_hop_address INET`, `sort_order INT` | FK `route_table_id → route_tables(uid) ON DELETE CASCADE` (E3) |
| `addresses` | `uid UUID` | `folder_id`, `address_type TEXT='EXTERNAL'`, `zone_id`, `state TEXT='RESERVED'`, `allocated_ipv4 INET` | UNIQUE `(folder_id,name)`; UNIQUE `allocated_ipv4` (Q3, F1) |

Все таблицы с `uid` имеют стандартные envelope-поля: `labels JSONB DEFAULT '{}'`, `annotations JSONB DEFAULT '{}'`, `creation_timestamp TIMESTAMPTZ DEFAULT NOW()`, `deletion_timestamp TIMESTAMPTZ`, `finalizers TEXT[] DEFAULT '{}'`, `generation BIGINT DEFAULT 1`.

**FK-стратегия:**
- `subnets.network_id → networks.uid ON DELETE RESTRICT` — защита B5 (`FAILED_PRECONDITION`)
- `route_tables.network_id → networks.uid ON DELETE RESTRICT` — аналогично
- `security_group_rules.security_group_id → security_groups.uid ON DELETE CASCADE` — D4
- `static_routes.route_table_id → route_tables.uid ON DELETE CASCADE` — E3
- Сервис перехватывает `pgcode.ForeignKeyViolation` и `pgcode.UniqueViolation` на уровне repo

### B.3 Domain entities

Каждый файл `internal/domain/<resource>.go` — чистый Go-тип, импортирует только `time` и `github.com/google/uuid`:

**`network.go`:**
```go
package domain

import "time"

type Network struct {
    UID               string
    FolderID          string
    Name              string
    Labels            map[string]string
    Annotations       map[string]string
    CreationTimestamp time.Time
    ResourceVersion   int64
    DeletionTimestamp *time.Time
    Finalizers        []string
    Generation        int64
    DisplayName       string
    Description       string
    State             NetworkState
}

type NetworkState string

const (
    NetworkStateActive   NetworkState = "ACTIVE"
    NetworkStateDeleting NetworkState = "DELETING"
)
```

Аналогично — `subnet.go` (добавляет `NetworkID string`, `CIDRBlock string`, `ZoneID string`), `security_group.go` (добавляет `Rules []SecurityGroupRule`), `route_table.go` (добавляет `NetworkID string`, `StaticRoutes []StaticRoute`), `address.go` (добавляет `AddressType string`, `ZoneID string`, `State AddressState`, `AllocatedIPv4 string`).

**Вложенные типы:**
```go
// domain/security_group.go
type SecurityGroupRule struct {
    ID           string
    Direction    string   // INGRESS | EGRESS
    Protocol     string   // TCP | UDP | ICMP | ANY
    PortRangeMin int32
    PortRangeMax int32
    CIDRBlocks   []string
    Description  string
}

// domain/route_table.go
type StaticRoute struct {
    ID                string
    DestinationPrefix string
    NextHopAddress    string
    Description       string
}

// domain/address.go
type AddressState string
const (
    AddressStateReserved AddressState = "RESERVED"
    AddressStateInUse    AddressState = "IN_USE"
    AddressStateReleased AddressState = "RELEASED"
)
```

### B.4 Service ports + use-cases

**`internal/service/ports.go`** — определяет все port-интерфейсы. `service/` не импортирует pgx, grpc-stubs, sqlc-types. Полный список портов:

| Интерфейс | Методы | Acceptance |
|---|---|---|
| `NetworkRepo` | `GetByUID`, `GetByName`, `List`, `Upsert`, `Delete`, `HasDependents` → `(bool, []string, error)` | B1–B8 |
| `SubnetRepo` | `GetByUID`, `GetByName`, `List`, `Upsert`, `Delete`, `ExistsAndNotDeleted` | C1–C10, G3, G7 |
| `SecurityGroupRepo` | `GetByUID`, `GetByName`, `List`, `Upsert`(full-replace rules в транзакции), `Delete`, `ExistsAndNotDeleted` | D1–D6, G5 |
| `RouteTableRepo` | `GetByUID`, `GetByName`, `List`, `Upsert`(full-replace routes), `Delete`, `ExistsAndNotDeleted` | E1–E5, Note 1 |
| `AddressRepo` | `GetByUID`, `GetByName`, `List`, `Upsert`, `UpdateStatus`, `Delete`, `ExistsAndNotDeleted`, `TryReserveIP` | F1–F8, G6 |
| `FolderExistsChecker` | `FolderExists(ctx, uid) (bool, error)` | H1–H5 |

`HasDependents` возвращает `(hasDeps bool, dependentKinds []string, error)` — для заполнения `PreconditionFailure.violations` (B5). `TryReserveIP` реализует atomic `INSERT ... ON CONFLICT DO NOTHING` для `allocated_ipv4`.

```go
type Pagination struct {
    PageToken string
    PageSize  int32
}
```

**`internal/service/network_service.go`** — use-case логика:

```go
type NetworkService struct { repo NetworkRepo; checker FolderExistsChecker; hub *watch.Hub }

func (s *NetworkService) Upsert(ctx context.Context, networks []*domain.Network) ([]*domain.Network, error) {
    // 1. Validate: name regex, folderId non-empty (I1, I5, H5)
    // 2. FolderExists check per item (H1) — до записи в БД
    // 3. Upsert через repo (outbox-event в той же транзакции); статус = ACTIVE
}
func (s *NetworkService) Delete(ctx context.Context, items []domain.DeleteItem) error {
    // 1. HasDependents → FAILED_PRECONDITION + PreconditionFailure.violations (B5)
    // 2. repo.Delete; NOT_FOUND если нет (I6)
}
func (s *NetworkService) List(ctx context.Context, f selector.Filter, p Pagination) ([]*domain.Network, int64, error) {
    // page_size > 1000 → INVALID_ARGUMENT (I15)
}
func (s *NetworkService) Watch(ctx context.Context, sel []selector.Selector, fromRV int64) (<-chan watch.Event, func(), error) {
    // non-decimal RV → INVALID_ARGUMENT (I16); Gone → OUT_OF_RANGE (B8, C10)
    return s.hub.Subscribe(sel, fromRV)
}
```

Аналогично — `subnet_service.go` (валидация `network_id EXISTS` через `NetworkRepo.GetByUID` → NOT_FOUND C4; CIDR-валидация I2, I3, I19), `security_group_service.go` (валидация direction/protocol/cidr_blocks: I8, I9), `route_table_service.go` (валидация network_id E4; destination_prefix I10; next_hop_address I11), `address_service.go` (валидация address_type I12; `assignIP` F1; lifecycle F3/F4/F5/F7).

**SubnetService.Upsert** — порядок валидации (C1, C4, H2):
1. Валидация полей: name regex (I1), cidrBlock `net.ParseCIDR` + host-bits check (I2, I3, I19), zoneId non-empty (I4) → INVALID_ARGUMENT
2. FolderID non-empty (H5) → без cross-service вызова; FolderExists (H2) → INVALID_ARGUMENT если false
3. `NetworkRepo.GetByUID(spec.network_id)` → NOT_FOUND с `ResourceInfo{resource_type="Network"}` если нет (C4)
4. `SubnetRepo.Upsert`

**`AddressService.UpdateStatus`** (F3, F4, F5, note 2): перед `repo.UpdateStatus` читается current state; если `current.State == newState` → return current без UPDATE (no-op, `resourceVersion` не меняется).

**`AddressService.Delete`** (F6, F7): если `addr.State == IN_USE` → `FAILED_PRECONDITION` с `violations[0].type="CONFLICTING_STATE"`.

**`assignIP`** (Q3, F1): цикл max 10 попыток; `offset = 1 + rand.Intn(254)` → `203.0.113.<offset>`; `TryReserveIP` использует `INSERT ... ON CONFLICT (allocated_ipv4) DO NOTHING RETURNING uid`; при exhaust → `ResourceExhausted`.

**CIDR-валидация** `validateCIDR(cidrStr, field)` (Q2, I2, I19): `ip, network, err := net.ParseCIDR(cidrStr)`; если `!ip.Equal(network.IP)` → `fieldViolation(field, "host bits set: use network address "+network.String())`.

**Name-валидация** (I1, I5): `regexp.MustCompile("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$")`.

**Cross-service client** `internal/clients/resource_manager_client.go` (H1–H5): `FolderExists` с `context.WithTimeout(5s)`; при `codes.Unavailable` — пробрасывает UNAVAILABLE (H4). Retry 1× on UNAVAILABLE через `grpc_retry.UnaryClientInterceptor` из `kacho-corelib/grpcclient`.

### B.5 Repo (sqlc + handwritten)

**sqlc.yaml** конфигурирует генерацию для `internal/repo/queries/*.sql` → `internal/repo/queries/*.go`. Handwritten-обёртки в `internal/repo/<resource>_repo.go` реализуют port-интерфейсы.

**Network HasDependents** (B5): `CountSubnetsByNetwork(uid)` + `CountRouteTablesByNetwork(uid)` в одном методе; результат — список `dependentKinds []string` (["Subnet"], ["RouteTable"] или оба). Сервис конвертирует в `FAILED_PRECONDITION` с `PreconditionFailure.violations[0].type="HAS_DEPENDENT_RESOURCES"`.

**SecurityGroupRepo.Upsert** — full-replace rules (D3, Q4): в одной транзакции: Upsert SG row → `DELETE FROM security_group_rules WHERE security_group_id=$1` → INSERT новых rules с server-assigned UUID (`uuid.New().String()`) для каждого → WriteOutboxEvent. Аналогично `RouteTableRepo.Upsert` для StaticRoute (E2).

**Idempotency (no-diff = no-op)** (B2, C2, F2): в `repo.Upsert` после `INSERT ON CONFLICT ... DO UPDATE` проверяется `xmax = 0` (PostgreSQL: если строка не обновлялась — `xmax = 0`); если не обновлялась → не пишем outbox-event, возвращаем current без изменений.

**Subnet/RouteTable List с `network_id` filter** (C6, note 3): `FieldSelector.refs[{kind:"Network", uid:<net-uid>}]` → `selector.ToSQL()` генерирует `network_id = $N`. Запрос:
```sql
SELECT * FROM subnets
WHERE (@folder_id::uuid IS NULL OR folder_id = @folder_id)
  AND (@network_id::uuid IS NULL OR network_id = @network_id)
ORDER BY creation_timestamp, uid LIMIT @page_size OFFSET @offset;
```

**`ExistsAndNotDeleted`** (G3, G7): `SELECT deletion_timestamp FROM subnets WHERE uid=$1`; `pgx.ErrNoRows` → false; `deletion_timestamp != NULL` → false (G7).

**`mapDBError`** (I13, I18): `pgerrcode.UniqueViolation` → `codes.Aborted`; `pgerrcode.ForeignKeyViolation` → `codes.NotFound` (при orphan-insert в C4, fallback если HasDependents не поймал).

### B.6 Handler (thin gRPC transport)

Каждый `internal/handler/<resource>_handler.go` — тонкий transport: `protoToDomain → service.Method → domainToProto`. Никакой бизнес-логики. Паттерн Watch:
```go
func (h *NetworkHandler) Watch(req *vpcv1.NetworkWatchRequest, stream vpcv1.NetworkService_WatchServer) error {
    fromRV, err := parseResourceVersion(req.ResourceVersion)  // I16: non-decimal → INVALID_ARGUMENT
    if err != nil { return err }
    ch, unsub, err := h.svc.Watch(stream.Context(), parseSelectors(req.Selectors), fromRV)
    if err != nil { return err }  // OUT_OF_RANGE если Gone (B8, C10)
    defer unsub()
    for evt := range ch {
        if err := stream.Send(mapWatchEvent(evt)); err != nil { return err }
    }
    return nil
}
```

**`internal/handler/internal_handler.go`** — Internal RPC (G1–G7, F3–F5): делегирует repo-методам `ExistsAndNotDeleted` и `addrService.UpdateStatus`. `InternalHandler` регистрируется на отдельном gRPC port (9091) — **не регистрируется** в api-gateway (CLAUDE.md §7).

### B.7 Cross-service client

**`internal/clients/resource_manager_client.go`** реализует `service.FolderExistsChecker`.

Конфигурируется через `kacho-corelib/grpcclient.Factory`:
```go
conn, err := grpcclient.NewConn(cfg.ResourceManagerAddr,
    grpcclient.WithTimeout(5*time.Second),
    grpcclient.WithRetry(1, codes.Unavailable),
)
rmClient := resourcemanagerv1.NewFolderInternalServiceClient(conn)
checker := clients.NewResourceManagerClient(rmClient)
```

Логика: если `FolderExists → {exists:false}` → service возвращает `INVALID_ARGUMENT` с `BadRequest.field_violations[0].field = "<resource>[i].metadata.folderId"` (H1–H3). Если peer недоступен → `UNAVAILABLE` с `RequestInfo` (H4). Пустой `folderId` — валидируется до вызова (H5).

### B.8 cmd/main.go (composition root)

`cmd/vpc/main.go` — единственное место wiring. Последовательность:
1. `db.NewPool` + `db.NewTransactor` + `outbox.NewWriter("kacho_vpc")`
2. `watch.NewHub(ctx, pool, HubOpts{ChannelName:"kacho_vpc", SVC:"vpc"})`
3. `grpcclient.NewConn(cfg.ResourceManagerAddr)` → `clients.NewResourceManagerClient`
4. Создание 5 Repo (net, sub, sg, rt, addr) — каждому передать pool, transactor, outbox
5. Создание 5 Service — каждому нужные Repo + `folderChecker` + hub
6. `go watch.RunCleanup(ctx, pool, "kacho_vpc")`
7. Public gRPC server (port 9090) — регистрировать все 5 ServiceServer + HealthCheck
8. Internal gRPC server (port 9091) — регистрировать `VpcInternalService`; **не маршрутизировать через api-gateway**
9. `subcommand migrate` — goose up перед serve

*Примечание:* bootstrap не нужен — нет default VPC-ресурсов. `make dev-up` поднимает resource-manager раньше vpc (зависимость в Helm umbrella).

### B.9 Helm chart + Dockerfile

**`Dockerfile`** — multi-stage, аналогично 0.2 resource-manager: `golang:1.22-alpine` builder → `distroless/static:nonroot`, бинарь `/kacho-vpc serve`.

**`deploy/Chart.yaml`:** `name: vpc`, `version: 0.3.0`, `appVersion: "0.3.0"`.

**`deploy/values.yaml`:** `image.repository: prorobotech/kacho-vpc`, ports `grpcPort: 9090` / `internalPort: 9091`, env `KACHO_VPC_DB_DSN`, `KACHO_VPC_RESOURCE_MANAGER_ADDR: resource-manager.kacho.svc.cluster.local:9091`. Requests: `cpu:100m`, `memory:128Mi`.

**`deploy/values.dev.yaml`:** `image.tag: dev`, `pullPolicy: Never`, DB DSN → `postgresql-vpc:5432/kacho_vpc`.

**`deploy/templates/deployment.yaml`** — readiness/liveness probe: `grpc_health_probe -addr :9090` (J6).

**Postgres** — отдельный StatefulSet `postgresql-vpc` в umbrella (database-per-service, аналогично `postgresql-resource-manager` из 0.2).

### B.10 Tests

**Unit-тесты** `internal/service/*_test.go` через mock port-интерфейсов (testify/mock). Именование: `Test<Resource>_<ScenarioID>_<ShortDesc>`:

- `TestNetwork_B1_CreateHappyPath`
- `TestNetwork_B2_UpsertNoDiffNoOp`
- `TestNetwork_B3_UpdateLabelsModifiedEvent`
- `TestNetwork_B4_DeleteWithoutDependents`
- `TestNetwork_B5_DeleteWithSubnetFailed`
- `TestNetwork_B6_ListByFolderID`
- `TestNetwork_B7_ListByLabel`
- `TestNetwork_B8_WatchAddedModifiedDeleted`
- `TestSubnet_C1_CreateWithNetworkId` ... `TestSubnet_C10_WatchGone`
- `TestSecurityGroup_D1_CreateNorules` ... `TestSecurityGroup_D6_WatchAdded`
- `TestRouteTable_E1_CreateWithStaticRoutes` ... `TestRouteTable_E5_ListByFolder`
- `TestAddress_F1_UpsertReservedStatus` ... `TestAddress_F8_WatchAdded`
- `TestVpcInternal_G1_NetworkExistsTrue` ... `TestVpcInternal_G7_SubnetSoftDeleted`
- `TestCrossService_H1_FolderNotFound` ... `TestCrossService_H5_EmptyFolderIdNoCall`
- `TestNegative_I1_InvalidName` ... `TestNegative_I19_HostBitsCIDR`

**Integration-тесты** `internal/service/*_acceptance_test.go` через `testcontainers-go` (Postgres + goose migrations):

```go
func TestNetwork_B1_CreateHappyPath(t *testing.T) {
    ctx := context.Background()
    pool := setupTestDB(t, ctx)  // testcontainer + migrations
    // mock FolderExistsChecker → always true
    // создать NetworkService с реальным repo
    // вызвать Upsert
    // assert UID, state=ACTIVE, outbox event
}
```

Для H-группы тесты используют mock `FolderExistsChecker` (интерфейс), а не реальный grpc — это правильно (Clean Architecture; cross-service в unit/integration через mock port).

**E2e-тесты** — bash scripts, см. §4.

**Coverage target:** ≥ 70% per package (service/, repo/).

---

## §4. Phase C — kacho-deploy update + e2e/0.3

### C.1 Helm umbrella update

**`helm/umbrella/Chart.yaml`** — добавить:
```yaml
dependencies:
  - name: vpc
    version: "0.3.0"
    repository: "file://../../kacho-vpc/deploy"
  - name: postgresql-vpc
    version: "12.x"
    repository: "https://charts.bitnami.com/bitnami"
    alias: postgresql-vpc
```

**`helm/umbrella/values.dev.yaml`** — добавить секцию:
```yaml
vpc:
  enabled: true
  image:
    tag: "dev"
    pullPolicy: Never
  env:
    KACHO_VPC_DB_DSN: "postgres://kacho:kacho@postgresql-vpc:5432/kacho_vpc?sslmode=disable"
    KACHO_VPC_RESOURCE_MANAGER_ADDR: "resource-manager:9091"

postgresql-vpc:
  enabled: true
  auth:
    database: kacho_vpc
    username: kacho
    password: kacho
  primary:
    persistence:
      enabled: false
```

### C.2 E2e bash scripts (`kacho-deploy/e2e/0.3/`)

Каждый скрипт — `#!/usr/bin/env bash`, `set -euo pipefail`, `grpcurl -plaintext`. VPC port `localhost:9090`, Resource Manager `localhost:9091`. Структура assert через `jq` + проверка exit-кода.

| Скрипт | Scenario | Что проверяет |
|---|---|---|
| `J1-network-upsert-list.sh` | J1 | Получить FOLDER_UID → Upsert Network → List; assert uid+state=ACTIVE |
| `J2-network-subnet-flow.sh` | J2 | Create Network → Create Subnet → List; assert network_id, state=ACTIVE |
| `J3-delete-blocked.sh` | J3 | Delete Network с зависимым Subnet → assert exit!=0, FAILED_PRECONDITION, HAS_DEPENDENT_RESOURCES |
| `J4-watch-subnet.sh` | J4 | Watch в фоне → Upsert+Update+Delete → assert /tmp/watch_vpc.json: ADDED, MODIFIED, DELETED |
| `J5-address-flow.sh` | J5 | Upsert Address EXTERNAL → assert state=RESERVED, allocated_ipv4 non-empty → Delete OK |
| `J6-helm-deploy-check.sh` | J6 | kubectl get pods Running → grpc_health_probe SERVING → psql \dt содержит 8 таблиц |

### C.3 Makefile target

```makefile
e2e-test-0.3: port-forward-vpc
	for f in e2e/0.3/*.sh; do bash $$f; done

port-forward-vpc:
	kubectl port-forward svc/vpc 9090:9090 -n kacho &
	kubectl port-forward svc/resource-manager 9091:9091 -n kacho &
	sleep 2
```

---

## §5. Phase D — Smoke + Tag v0.3.0

### D.1 Smoke run

```bash
cd kacho-deploy && make dev-up
kubectl get pods -n kacho  # resource-manager + vpc Running

kubectl port-forward svc/resource-manager 9091:9091 -n kacho &
kubectl port-forward svc/vpc 9090:9090 -n kacho &

make e2e-test-0.3          # J1–J6 all green

# Финальная ручная проверка Watch:
grpcurl -plaintext -d '{"resource_version":"0"}' localhost:9090 \
  kacho.cloud.vpc.v1.SubnetService/Watch &
# … Upsert subnet → ожидаем ADDED в стриме

make dev-down
```

### D.2 CHANGELOG + Tags

Добавить запись в `kacho-workspace/docs/specs/CHANGELOG.md`:
```markdown
## [0.3.0] — 2026-05-xx
### Added
- kacho-vpc: Network, Subnet, SecurityGroup, RouteTable, Address (control plane)
- kacho-vpc: Watch Hub, outbox, cross-service Folder validation (vpc → resource-manager)
- kacho-proto: vpc/v1 domain (network, subnet, security_group, route_table, address, internal)
- kacho-deploy: vpc Helm chart + e2e/0.3 scenarios (J1–J6)
```

Поставить теги:
```bash
# в каждом затронутом репо
git tag v0.3.0 && git push origin v0.3.0
```

---

## §6. Definition of Done

Зеркалит acceptance §11. Sub-итерация 0.3 считается **завершённой**, когда **все** условия выполнены:

1. ✅ Все 82 acceptance-сценария покрыты исполняемыми тестами:
   - Integration-тесты (testcontainers-Postgres) в `kacho-vpc/internal/service/*_acceptance_test.go` — все зелёные
   - E2e bash-скрипты `kacho-deploy/e2e/0.3/*.sh` — все зелёные при `make e2e-test PHASE=0.3`
   - A1 и A2 трассируются через CI-шаги `buf-lint` / `buf-breaking` в `kacho-proto/.github/workflows/ci.yaml`

2. ✅ Proto `kacho-proto/proto/kacho/cloud/vpc/v1/` содержит: `network.proto`, `subnet.proto`, `security_group.proto`, `route_table.proto`, `address.proto`, `internal.proto` — `buf lint` и `buf breaking` зелёные; `gen/go/` committed без дрейфа

3. ✅ kacho-vpc реализован по Clean Architecture:
   - `domain/` не импортирует pgx, grpc-stubs, sqlc-типы
   - `service/` определяет port-интерфейсы, импортирует только `domain/`
   - `handler/` — тонкий transport-слой, никакой бизнес-логики
   - Единственное место wiring — `cmd/vpc/main.go`
   - `internal/handler/internal_handler.go` — **не регистрируется** в api-gateway

4. ✅ Cross-service validation работает (H1–H5):
   - При Upsert любого VPC-ресурса вызывается FolderExists через resource-manager gRPC-client
   - `exists=false` → `INVALID_ARGUMENT` с полем `metadata.folderId`
   - UNAVAILABLE → пробрасывается как `UNAVAILABLE` с RequestInfo

5. ✅ Address lifecycle синхронный (F1–F8):
   - Upsert → `RESERVED` в той же транзакции; `allocated_ipv4` назначен из `203.0.113.0/24`
   - `UpdateStatus` → `IN_USE` / `RELEASED`; no-diff → no-op (note 2)
   - Delete в состоянии `IN_USE` → `FAILED_PRECONDITION` с `CONFLICTING_STATE`

6. ✅ Intra-domain cascade работает:
   - Delete SecurityGroup → SecurityGroupRules удалены (CASCADE, D4)
   - Delete RouteTable → StaticRoutes удалены (CASCADE, E3)
   - Upsert SecurityGroup/RouteTable — правила/маршруты атомарно заменяются (D3, E2)

7. ✅ Network/Subnet dependency protection:
   - Delete Network с зависимым Subnet → `FAILED_PRECONDITION` + `HAS_DEPENDENT_RESOURCES` (B5)
   - Delete Network с зависимым RouteTable — аналогично

8. ✅ kacho-corelib reuse (нет дублирования):
   - `kacho-vpc` импортирует `kacho-corelib/{watch,outbox,selector,migrations/common}`
   - Проверяется через `go mod graph`

9. ✅ Helm chart для vpc в `kacho-deploy/helm/` и в `helm/umbrella/Chart.yaml`; `make dev-up` < 5 минут (с vpc pod)

10. ✅ Naming conventions (acceptance §10):
    - Proto package: `kacho.cloud.vpc.v1`
    - DB: `kacho_vpc`; таблицы: `networks`, `subnets`, `security_groups`, `security_group_rules`, `route_tables`, `static_routes`, `addresses`, `resource_events`
    - Env: `KACHO_VPC_*`
    - k8s service: `vpc.kacho.svc.cluster.local`; Docker image: `prorobotech/kacho-vpc:0.3.0`
    - Нет упоминаний «yandex» в коде, README, комментариях

11. ✅ CI всех затронутых репо зелёный:
    - `kacho-proto`: buf-lint, buf-breaking, gen-drift check
    - `kacho-vpc`: golangci-lint, `go test ./...` (включая integration с testcontainers)
    - `kacho-deploy`: helm lint

12. ✅ `kacho-workspace/docs/specs/CHANGELOG.md` содержит запись о завершении sub-phase 0.3

13. ✅ Тег `v0.3.0` поставлен в каждом затронутом репо

---

## §7. Execution mode

Пользователь дал автономию до готового блока. Цепочка:

1. Этот план — единственный артефакт этого шага.
2. **Phase A subagent (Sonnet)** — kacho-proto/vpc/v1: 6 proto-файлов + buf generate + gen/ commit. Параллельно с Phase B.1 (нет зависимостей, разные репо).
3. **Phase B subagent (Sonnet) — skeleton** (B.1): go.mod, директории, `.gitignore`, doc.go, Makefile-skeleton. Параллельно с Phase A.
4. **Phase B subagent (Sonnet) — migrations** (B.2): 0001_initial.sql + sync common. Блокируется B.1.
5. **Phase B subagent (Sonnet) — domain + service** (B.3–B.4): domain entities, service ports + use-cases, validation helpers, assignIP. Блокируется B.2 (нужен schema).
6. **Phase B subagent (Sonnet) — repo** (B.5): sqlc config + queries + handwritten repos. Параллельно с B.3–B.4 по skeleton; финальный wiring после обоих.
7. **Phase B subagent (Sonnet) — handler + clients + cmd** (B.6–B.8): thin handlers, ResourceManagerClient, composition root. Блокируется B.4+B.5.
8. **Phase B subagent (Sonnet) — tests** (B.10): unit + integration. Параллельно с B.9 (Helm/Dockerfile).
9. **Phase B subagent (Sonnet) — helm + dockerfile** (B.9): Dockerfile, Chart.yaml, values.*. Параллельно с B.10.
10. **Phase C subagent (Sonnet)** — kacho-deploy: umbrella update + e2e/0.3/*.sh. Блокируется Phase B (финальный интерфейс).
11. **Phase D — smoke + CHANGELOG + tags**. Блокируется Phase C.
12. Возврат к пользователю на финальную верификацию (grpcurl smoke + `make e2e-test PHASE=0.3`).

**Параллелизм:**
- Phase A ‖ Phase B.1 (разные репо, нет зависимостей)
- Phase B.3–B.4 ‖ Phase B.5 (разные пакеты; B.5 использует domain-типы, но skeleton уже есть из B.1)
- Phase B.9 ‖ Phase B.10 (независимы)
- Phase C блокируется завершением всех Phase B
- Phase D блокируется Phase C

После Phase D → стоп → отчёт пользователю → пользователь делает grpcurl-проверку и approves smoke → тег v0.3.0.
