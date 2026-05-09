# 07 — Conventions & Constraints

Правила, которые **не выводятся** из кода — их надо знать, чтобы новый
PR не сломал контракт.

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
| Organization | `bpf` | `bpfx4ttwb2enjzgxsmjs` |
| Cloud | `b1g` | `b1g4xbdb0szxpb2yktjy` |
| Folder | `b1g` (тот же — отдельная таблица) | `b1gjy7wt1qf1nsnykwen` |
| Network | `enp` | `enp...` |
| Subnet | `e9b` | `e9bs2h48tfthkpqsjta7` |
| Address | `e9b` | `e9bv5j3ygqnc09pd7g94` |
| RouteTable | `rtb` | `rtb...` |
| SecurityGroup | `sgp` | `sgp...` |
| Gateway | `gtw` | `gtw...` |
| PrivateEndpoint | `pep` | `pep...` |
| AddressPool | `apl` | `aplv8v5a15yrns468vwn` |
| Operation | `opvpc` (vpc) / `opfo`/`oporg`/`opcl` (rm) | `opvpc...` |

ID — `TEXT` колонка с PK constraint, не UUID. Verbatim YC: garbage-id даёт
**async** NotFound, не sync InvalidArgument.

## Verbatim YC API contract

Что значит "verbatim":
- **Proto-форма** (имена полей, oneof, FieldMask, RPC сигнатуры) — точная
  копия YC.
- **Error texts** — буквально как у YC, без локализации:
  `"Folder with id {X} not found"`, `"Subnet CIDRs can not overlap"`.
- **Status codes**: `NOT_FOUND`, `ALREADY_EXISTS`, `FAILED_PRECONDITION`,
  `INVALID_ARGUMENT`, `RESOURCE_EXHAUSTED` — гpc-канон.
- **Regex'ы**: `name` для resource-manager — strict
  (`^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$`); для VPC — permissive
  (`^([a-zA-Z]([-_a-zA-Z0-9]{0,61}[a-zA-Z0-9])?)?$`, разрешает empty/uppercase/underscore).
- **Timestamp precision**: возвращается **с обрезкой до секунд**
  (`Truncate(time.Second)`), хотя в БД хранится с микросекундами.
- **Empty fields**: грpc-gateway emit'ит `EmitUnpopulated=true` →
  `"name":""` в ответе вместо отсутствия ключа.

Что **можно** менять без нарушения parity:
- Internal API (`Internal*Service`'ы) — kacho-only, свободно расширяемы.
- Admin tooling (kachoctl, kacho-tui).
- Helm/deployment.
- Backend implementation детали (как именно реализован allocator, какая
  схема таблиц) — пока observable behavior не меняется.

## Жёсткие запреты (workspace `CLAUDE.md`)

1. **НЕ начинать кодирование** до APPROVED acceptance-документа Given-When-
   Then в `docs/specs/`. Approve выставляет агент `acceptance-reviewer`.
2. **НЕ упоминать "yandex"** в handwritten коде / README / комментариях /
   env-name / именах функций.
3. **НЕ использовать ORM** (gorm, ent, bun). Только sqlc + handwritten pgx.
4. **НЕ делать каскадное удаление через границу сервиса** (только same-DB
   FK cascade).
5. **НЕ редактировать применённую миграцию.** Только новая.
6. **`Internal.*` методы НЕ публиковать на external endpoint**
   (TLS-listener `api.kacho.local:443`). Можно регистрировать через apiGW
   REST mux на cluster-internal listener (для UI/admin tooling/port-forward).
   - **Admin-UI правило**: любой новый RPC, нужный admin-UI, добавлять
     **только** в `Internal*` сервис на :9091 и регистрировать через
     `vpcInternalAddr` блок в `restmux.NewMux`. Не расширять публичные
     сервисы для admin-нужд — это сломает verbatim-parity.
7. **НЕ вводить broker** (Kafka/NATS) до тех пор, пока in-process реализация
   справляется.
8. **НЕ создавать новые единые БД** — только database-per-service.
9. **НЕ возвращать ресурс синхронно из мутирующих RPC**. Все мутации →
   `Operation`, клиент поллит до `done=true`.

## Inter-service контракты

- Только gRPC. Никакого cross-DB Postgres-доступа.
- Каждый сервис **owns** свою БД, никаких `JOIN`'ов между сервисами.
- Если нужны данные другого сервиса — RPC с retry.
- `ports.<Resource>Client` — port-интерфейс в service-слое; `clients/<svc>_client.go` — gRPC adapter.

## Operations (LRO) контракт

```protobuf
message Operation {
  string id = 1;            // opvpc... / opfo... / ...
  string description = 2;
  google.protobuf.Timestamp created_at = 3;
  bool done = 6;
  google.protobuf.Any metadata = 7;     // {networkId:"net..."} для CreateNetworkMetadata
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

**Delete RPC возвращают `Operation` с `response: google.protobuf.Empty`**
(не `DeleteXxxMetadata`!). Текущий код это **нарушает** для всех 6 Delete —
в TODO #1 у каждого сервиса.

## Hard delete

С Phase 1.0 — `DELETE FROM <table> WHERE id = $1`. Никаких
`deletion_timestamp` для tombstones. Поле в схеме могло остаться от envelope-
эпохи, но не используется.

## Flat schemas

VPC-таблицы (Network, Subnet, Address, …) — flat, без K8s envelope:
**нет** `resource_version`, `generation`, `deletion_timestamp`,
`finalizers`, `spec`, `status` (как jsonb). Только domain-specific колонки +
id/folder_id/name/description/labels/created_at.

## Optimistic concurrency

Без отдельной колонки. Используем Postgres `xmin::text` (txid версия row):
```sql
SELECT field, xmin::text FROM t WHERE id = $1;
UPDATE t SET field = $2 WHERE id = $1 AND xmin::text = $3 RETURNING ...;
```
Zero-overhead, миграция не нужна.

## Validation layering

**Sync** (до создания Operation):
- Required-поля (`folder_id`, `name`, `zone_id`, …).
- Format (`NameVPC`, `NameStrict`, `Description ≤256`, `Labels ≤64 пар`,
  `ZoneId` whitelist).
- CIDR: host-bits должны быть 0 (`netip.Prefix.Masked() == prefix`).
- DhcpOptions: `domain_name` RFC 1123, `domain_name_servers[]`/`ntp_servers[]` IP.
- UpdateMask: known-set + immutable check.
- DeletionProtection.
- Address spec: oneof external/internal — exactly one.

**Async** (внутри Operation worker):
- Folder existence через `folderClient.Exists` → `NotFound`.
- Network/Subnet existence для дочерних → `NotFound`.
- Repo Insert/Update — FK violations, EXCLUDE constraint (CIDR overlap),
  UNIQUE violation (name within folder, IP collision).
- Все маппятся через `mapRepoErr` в gRPC-status.

## Error mapping (sentinel → grpc)

`internal/service/<svc>.go::mapRepoErr` — единая точка трансляции:

| Sentinel | gRPC code | Verbatim YC text source |
|---|---|---|
| `ErrNotFound` | `NOT_FOUND` | `"<Resource> {X} not found"` |
| `ErrAlreadyExists` | `ALREADY_EXISTS` | `"<resource> with name ... exists"` |
| `ErrFailedPrecondition` | `FAILED_PRECONDITION` | varies |
| `ErrInvalidArg` | `INVALID_ARGUMENT` | varies |
| `ErrInternal` | `INTERNAL` | `"internal database error"` (no leak) |

Specific:
- CIDR overlap (PG `23P01` от EXCLUDE) → `FailedPrecondition`
  `"Subnet CIDRs can not overlap"`.
- Garbage UUID format в id → **NE** sync InvalidArgument; async через
  `repo.Get` → `NotFound`.
- Duplicate name (UNIQUE `23505`) → `ALREADY_EXISTS`.

## Что говорит "kacho-only"

**Всё внутри `Internal*Service`'ов** — это kacho-only. Не v erbatim YC.

| kacho-only resource | Внутреннее API | Внешнее (UI / admin REST) | На external TLS |
|---|---|---|---|
| Region | `InternalRegionService` | `/vpc/v1/regions*` | ❌ нет |
| Zone | `InternalZoneService` | `/vpc/v1/zones*` | ❌ нет |
| AddressPool | `InternalAddressPoolService` | `/vpc/v1/addressPools*` | ❌ нет |
| CloudPoolSelector | `InternalCloudService` | `/vpc/v1/clouds/{id}/poolSelector` | ❌ нет |
| Default-SG creation | inline в `NetworkService.doCreate` | через standard NetworkService | ✅ да (verbatim YC: создаётся) |
| IPAM allocate | inline в `AddressService.doCreate` | через standard AddressService | ✅ да (verbatim YC: external_ipv4 заполняется) |

## Top-10 gotchas (из истории фиксов)

1. **Не валидировать UUID/id sync** — garbage id даёт **async** NotFound.
2. **NameVPC permissive, не strict** — empty/uppercase/underscore разрешены.
3. **CIDR overlap** = `FailedPrecondition`, не `InvalidArgument`.
4. **CIDR host-bits = 0** обязательно, sync через `netip.Masked`.
5. **Subnet immutable**: `v4_cidr_blocks/v6_cidr_blocks/network_id/zone_id` —
   reject в mask, silent ignore в full-PATCH.
6. **Hard-delete, не soft**.
7. **Default SG создаётся inline в NetworkService.doCreate** (раньше был
   reconciler в kacho-vpc-controllers).
8. **Timestamp truncate to seconds** в proto-ответе.
9. **DeletionProtection sync-check** перед Delete — `FailedPrecondition`.
10. **page_size валидируется**, garbage page_token → `InvalidArgument`.

## Где смотреть

- Repo-уровневые details: `project/<repo>/CLAUDE.md`.
- Acceptance specs: `docs/specs/sub-phase-X.Y-<topic>-acceptance.md`.
- Workspace правила: `CLAUDE.md` в корне workspace.
