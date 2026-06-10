# 07 — Conventions & Constraints

Правила, которые **не выводятся** из кода — их надо знать, чтобы новый
PR не сломал контракт. Это собственные конвенции продукта Kachō, зафиксированные
в `docs/` и проверяемые тестами; их менять только осознанно (через тикет).

## Naming

| Контекст | Значение |
|---|---|
| Бренд / README / UI | **Kachō** |
| ASCII / технический ID | `kacho` |
| Proto package | `kacho.cloud.<domain>.v1` |
| Имена репо | `kacho-<part>` (с дефисом) |
| Postgres database | `kacho_<domain>` (с подчёркиванием) |
| Env-переменные | `KACHO_<DOMAIN>_<NAME>` |
| Resource ID prefix | 3 символа + 17-char base32 (см. `corelib/ids`) |

## ID prefixes (по сервисам)

| Domain | Prefix | Пример |
|---|---|---|
| Account | `acc` | `acc4ttwb2enjzgxsmjs` |
| Project | `prj` | `prj4xbdb0szxpb2yktjy` |
| Network | `enp` | `enp...` |
| Subnet | `e9b` | `e9bs2h48tfthkpqsjta7` |
| Address | `e9b` | `e9bv5j3ygqnc09pd7g94` |
| RouteTable | `rtb` | `rtb...` |
| SecurityGroup | `sgp` | `sgp...` |
| Gateway | `gtw` | `gtw...` |
| NetworkInterface | `nic` | `nic...` |
| AddressPool | `apl` | `aplv8v5a15yrns468vwn` |
| Operation | `opvpc` (vpc) / `opiam` (iam) / `opcmp` (compute) | `opvpc...` |

ID — `TEXT` колонка с PK constraint, не UUID. Тип ресурса читается по prefix.
Garbage/malformed id → sync `InvalidArgument "invalid <res> id '<X>'"` первым
стейтментом RPC (`corevalidate.ResourceID`); well-formed-но-нет → `NotFound`
через `repo.Get`.

## Kachō API contract (канонические конвенции)

Форма и поведение API — собственные конвенции Kachō, зафиксированные в спеке и
тестах:

- **Proto-форма** — flat-resource message (domain-поля на верхнем уровне, без
  K8s-envelope `spec`/`status`/`metadata`/`resourceVersion`/`generation`/`finalizers`).
  `Get`/`List` синхронны; `Create`/`Update`/`Delete` и domain-действия возвращают
  `operation.Operation`. `Update` принимает `google.protobuf.FieldMask update_mask`.
- **Error texts** — единый стабильный тон, без локализации:
  `"<Resource> %s not found"`, `"<field> is immutable after <Resource>.Create"`,
  `"Illegal argument <thing>"`, `"network is not empty"`. Тексты — часть контракта.
- **Status codes**: `NOT_FOUND`, `ALREADY_EXISTS`, `FAILED_PRECONDITION`,
  `INVALID_ARGUMENT`, `UNAVAILABLE`, `INTERNAL` — gRPC-канон.
- **Regex'ы**: `name` для IAM — strict
  (`^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$`); для VPC — permissive
  (`^([a-zA-Z]([-_a-zA-Z0-9]{0,61}[a-zA-Z0-9])?)?$`, разрешает empty/uppercase/underscore).
- **Timestamp precision**: возвращается **с обрезкой до секунд**
  (`Truncate(time.Second)`), хотя в БД хранится с микросекундами.
- **Empty fields**: grpc-gateway emit'ит `EmitUnpopulated=true` →
  `"name":""` в ответе вместо отсутствия ключа.

Что **можно** менять, не затрагивая публичный контракт:
- Internal API (`Internal*Service`'ы) — admin-only, свободно расширяемы.
- Admin tooling / UI.
- Helm/deployment.
- Backend implementation детали (как именно реализован allocator, какая
  схема таблиц) — пока observable behavior не меняется.

## Жёсткие запреты (workspace `CLAUDE.md`)

1. **НЕ начинать кодирование** до APPROVED acceptance-документа Given-When-
   Then в `docs/specs/`. Approve выставляет агент `acceptance-reviewer`.
2. **НЕ упоминать чужие облака** (`yandex`, `aws`, …) в handwritten коде /
   README / комментариях / env-name / именах функций. CI-гейт `make verify-no-yandex`.
3. **НЕ использовать ORM** (gorm, ent, bun). Только sqlc + handwritten pgx.
4. **НЕ делать каскадное удаление через границу сервиса** (только same-DB
   FK cascade).
5. **НЕ редактировать применённую миграцию.** Только новая.
6. **`Internal.*` методы НЕ публиковать на external endpoint**
   (TLS-listener `api.kacho.local:443`). Можно регистрировать через apiGW
   REST mux на cluster-internal listener (:9091, для UI/admin tooling/port-forward).
   - **Admin-UI правило**: любой новый RPC, нужный admin-UI, добавлять
     **только** в `Internal*` сервис на :9091 и регистрировать через
     `*InternalAddr` блок в `restmux.NewMux`. Не расширять публичные
     сервисы для admin-нужд — это засветит admin-функции на external endpoint.
7. **НЕ вводить broker** (Kafka/NATS) до тех пор, пока in-process реализация
   справляется.
8. **НЕ создавать новые единые БД** — только database-per-service.
9. **НЕ возвращать ресурс синхронно из мутирующих RPC**. Все мутации →
   `Operation`, клиент поллит `OperationService.Get(id)` до `done=true`.

## Inter-service контракты

- Только gRPC. Никакого cross-DB Postgres-доступа.
- Каждый сервис **owns** свою БД, никаких `JOIN`'ов между сервисами.
- Если нужны данные другого сервиса — RPC с retry (fail-closed для мутаций →
  `Unavailable`, если peer недоступен).
- `ports.<Resource>Client` — port-интерфейс в service-слое; `clients/<svc>_client.go` — gRPC adapter.
- Карта владельцев: Geography (Region/Zone) → `kacho-compute`; IAM (Account/Project/
  User/SA/Group/Role/AccessBinding) → `kacho-iam`; Network/Subnet/SG/RouteTable/
  Address/Gateway/NetworkInterface → `kacho-vpc`; Instance/Disk/Image/Snapshot/
  DiskType → `kacho-compute`.

## Operations (LRO) контракт

```protobuf
message Operation {
  string id = 1;            // opvpc... / opiam... / opcmp...
  string description = 2;
  google.protobuf.Timestamp created_at = 3;
  bool done = 6;
  google.protobuf.Any metadata = 7;     // {networkId:"enp..."} для CreateNetworkMetadata
  oneof result {
    google.rpc.Status error = 8;        // если done && error
    google.protobuf.Any response = 9;   // Network если done && success
  }
}
```

**Шаблон в service**:
```go
op, _ := operations.New(ids.PrefixOperationVPC, "Create network "+req.Name,
    &vpcv1.CreateNetworkMetadata{NetworkId: netID})
opsRepo.Create(ctx, op)
operations.Run(ctx, opsRepo, op.ID, func(ctx context.Context) (*anypb.Any, error) {
    return s.doCreate(ctx, netID, req)
})
return &op, nil
```

`operations.Run` крутит горутину, на success → UPDATE done=true response;
на error → UPDATE done=true error.

Клиент поллит `OperationService.Get(id)` до `done=true`. **Watch RPC не существует**
(поллинг `List` 2-5с или `Operation.Get` для in-flight задач; серверного
Watch-стриминга на публичной поверхности нет).

**Delete RPC возвращают `Operation` с `response: google.protobuf.Empty`**
(не `DeleteXxxMetadata`).

## Hard delete

`DELETE FROM <table> WHERE id = $1`. Никаких `deletion_timestamp` для
tombstones — soft-delete не используется.

## Flat schemas

Таблицы (Network, Subnet, Address, …) — flat, без K8s envelope:
**нет** `resource_version`, `generation`, `deletion_timestamp`,
`finalizers`, `spec`, `status` (как jsonb). Только domain-specific колонки +
id/project_id/name/description/labels/created_at.

## Optimistic concurrency

Без отдельной колонки. Используем Postgres `xmin::text` (txid версия row):
```sql
SELECT field, xmin::text FROM t WHERE id = $1;
UPDATE t SET field = $2 WHERE id = $1 AND xmin::text = $3 RETURNING ...;
```
Zero-overhead, миграция не нужна.

## Validation layering

**Sync** (до создания Operation):
- Required-поля (`project_id`, `name`, `zone_id`, …).
- Format (`NameVPC`, `NameStrict`, `Description ≤256`, `Labels ≤64 пар`,
  `ZoneId` whitelist).
- CIDR: host-bits должны быть 0 (`netip.Prefix.Masked() == prefix`).
- DhcpOptions: `domain_name` RFC 1123, `domain_name_servers[]`/`ntp_servers[]` IP.
- UpdateMask: known-set + immutable check.
- DeletionProtection.
- Address spec: oneof external/internal — exactly one.

**Async** (внутри Operation worker):
- Project existence через `projectClient.Get` → `InvalidArgument`/`NotFound`.
- Network/Subnet existence для дочерних → `NotFound`.
- Repo Insert/Update — FK violations, EXCLUDE constraint (CIDR overlap),
  UNIQUE violation (name within project, IP collision).
- Все маппятся через `mapRepoErr` в gRPC-status.

## Error mapping (sentinel → grpc)

`internal/service/<svc>.go::mapRepoErr` — единая точка трансляции:

| Sentinel | gRPC code | Text source |
|---|---|---|
| `ErrNotFound` | `NOT_FOUND` | `"<Resource> %s not found"` |
| `ErrAlreadyExists` | `ALREADY_EXISTS` | `"<resource> with name ... exists"` |
| `ErrFailedPrecondition` | `FAILED_PRECONDITION` | varies |
| `ErrInvalidArg` | `INVALID_ARGUMENT` | varies |
| `ErrInternal` | `INTERNAL` | `"internal database error"` (no leak) |

Specific:
- CIDR overlap (PG `23P01` от EXCLUDE) → `FailedPrecondition`
  `"Subnet CIDRs can not overlap"`.
- Garbage id format → sync `InvalidArgument "invalid <res> id '<X>'"`
  (`corevalidate.ResourceID`); well-formed-но-нет → async `NotFound` через `repo.Get`.
- Duplicate name (UNIQUE `23505`) → `ALREADY_EXISTS`.

## Что значит "admin-only"

**Всё внутри `Internal*Service`'ов** — admin-only, не на external TLS-endpoint.

| admin-only resource | Внутреннее API | Внешнее (UI / admin REST) | На external TLS |
|---|---|---|---|
| Region | `InternalRegionService` | `/compute/v1/regions*` | ❌ нет |
| Zone | `InternalZoneService` | `/compute/v1/zones*` | ❌ нет |
| AddressPool | `InternalAddressPoolService` | `/vpc/v1/addressPools*` | ❌ нет |
| Default-SG creation | inline в `NetworkService.doCreate` | через standard NetworkService | ✅ да (создаётся) |
| IPAM allocate | inline в `AddressService.doCreate` | через standard AddressService | ✅ да (external_ipv4 заполняется) |

## Top-10 gotchas (из истории фиксов)

1. **Malformed id — sync InvalidArgument** первым стейтментом RPC; well-formed-но-нет → async NotFound.
2. **NameVPC permissive, не strict** — empty/uppercase/underscore разрешены.
3. **CIDR overlap** = `FailedPrecondition`, не `InvalidArgument`.
4. **CIDR host-bits = 0** обязательно, sync через `netip.Masked`.
5. **Subnet immutable**: `v4_cidr_blocks/v6_cidr_blocks/network_id/zone_id` —
   reject в mask, silent ignore в full-PATCH.
6. **Hard-delete, не soft**.
7. **Default SG создаётся inline в NetworkService.doCreate** (без отдельного reconciler).
8. **Timestamp truncate to seconds** в proto-ответе.
9. **DeletionProtection sync-check** перед Delete — `FailedPrecondition`.
10. **page_size валидируется** (`corevalidate.PageSize`), garbage page_token → `InvalidArgument`.

## Где смотреть

- Repo-уровневые details: `project/<repo>/CLAUDE.md`.
- Acceptance specs: `docs/specs/sub-phase-X.Y-<topic>-acceptance.md`.
- Workspace правила: `CLAUDE.md` в корне workspace.
