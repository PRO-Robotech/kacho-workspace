# Sub-phase 1.x (AddressPool — split `cidr_blocks` на `v4_cidr_blocks` + `v6_cidr_blocks`) — Acceptance

**Документ:** acceptance / sub-phase 1.x AddressPool split CIDR family
**YouTrack:** [KAC-71](https://prorobotech.youtrack.cloud/issue/KAC-71)
**Дата:** 2026-05-15
**Статус:** Draft round 2 — реfлектирует блокеры и важные замечания `acceptance-reviewer` round 1; ждёт повторного review
**История:**
- round 1 (2026-05-15, утром): Draft — отправлен на review.
- round 1 review: `acceptance-reviewer` ❌ CHANGES REQUESTED — 4 блокера (semantics replace через явный bool-флаг, IPAM cascade Steps 1-2 не покрыты, D4 ExplainResolution нерешённое поведение, Bind*-family-awareness) + 4 important (defensive migration, wording, traceability Delete RPC, exact case count) + мелочи.
- round 2 (2026-05-15): применены все блокеры (B11/B12/B13/D6/D7/C6 — новые сценарии; §0 переписан; D4 переписан с явным изменением кода в handler; §10/§11/§12/§13 обновлены).
**Источник требований:** YT `KAC-71` (тело тикета); существующая структура `Subnet.{v4_cidr_blocks,v6_cidr_blocks}` (`kacho-proto/proto/kacho/cloud/vpc/v1/subnet.proto`); IPAM cascade `kacho-vpc/CLAUDE.md` §16.2 + сервис `internal/service/address_pool_service.go::doResolve` (поведение `poolHasFamily`, KAC-58 / KAC-60 / KAC-63); `02-data-model-and-conventions.md` §6 (CIDR), §14 (error codes); workspace `CLAUDE.md` запреты #5 (миграции), #10 (within-service refs — DB-уровень).
**Утверждение:** approve выставляет агент `acceptance-reviewer`. После APPROVED — стартует `superpowers:writing-plans` (план реализации) и далее `integration-tester` / `rpc-implementer`. Заказчик подключается только к финальному smoke (шаг 7 `04-roadmap-and-phasing.md` §2).

---

## 0. Цель sub-итерации (1 абзац)

Сейчас `AddressPool.cidr_blocks: repeated string` (`kacho-proto/proto/kacho/cloud/vpc/v1/internal_address_pool_service.proto`) — единый смешанный массив CIDR-блоков любого семейства. Family каждого блока вычисляется runtime через парсинг (`netip.ParsePrefix(...).Addr().Is6()` / `poolHasFamily`). Это (а) асимметрично с `Subnet`, где явно `v4_cidr_blocks` + `v6_cidr_blocks` — параллельные слоты с фиксированной семантикой; (б) делает family-фильтрацию в IPAM cascade неявной (нужно проверять каждый блок); (в) замазывает семантическое различие «v4-only / v6-only / dual-stack» пула.

В этой sub-итерации:
1. `AddressPool` рефакторится на **два явных поля**: `repeated string v4_cidr_blocks` + `repeated string v6_cidr_blocks`. Field `cidr_blocks = 7` зарезервируется (`reserved 7; reserved "cidr_blocks";`) — поле снимается из proto целиком. Это — **сознательно принятый breaking proto-change**: verbatim-YC parity отложена (workspace `CLAUDE.md` §«Что это за проект»), и расхождение с YC-shape больше не constraint. `buf breaking` против baseline `main` **ожидаемо красный** (поле удалено); красный exit-code закрывается **explicit-override на ревью PR** (commit-message `KAC-71 breaking: cidr_blocks → v4/v6_cidr_blocks split` + ссылка на этот acceptance в PR-описании). Это формализуется в A2 / REQ-IPL-PROTO-02 ниже.
2. Соответственно `CreateAddressPoolRequest.cidr_blocks` (`field=5`) и `UpdateAddressPoolRequest.cidr_blocks` (`field=6`) заменяются на `v4_cidr_blocks` + `v6_cidr_blocks` с тем же full-replace upsert-семантикой.
3. На уровне БД: новая миграция `0022_address_pool_split_cidr_family.sql` добавляет колонки `v4_cidr_blocks text[]` и `v6_cidr_blocks text[]`, backfill'ит их из существующего `cidr_blocks` по правилу «`':' ∈ block → v6`, иначе `v4`», затем `DROP COLUMN cidr_blocks`. Backfill в `DO $$ ... $$;`-блоке идемпотентен (no-op при повторном applied state). Free-list-таблица `address_pool_free_ips` и cursor-таблица `ipv6_pool_cursors` НЕ перестраиваются — они уже family-aware (freelist v4-only, cursor v6-only), pool_id-ссылка сохраняется.
4. Семантика типов пула становится явной: **v4-only pool** = `v4_cidr_blocks≠[]`, `v6_cidr_blocks=[]`; **v6-only pool** = инверсно; **dual-stack pool** = оба не пусты. Pool без обоих CIDR-списков (оба пусты) — отвергается **двумя слоями**:
   - (a) sync `InvalidArgument` на Create и на Update post-state (REQ-IPL-CR-04 / REQ-IPL-UPD-03 — service-слой);
   - (b) defensive PG `RAISE EXCEPTION` в backfill миграции `0022` (REQ-MIG-06 / C6) — fail-closed, если pre-existing row просочилась через прямой SQL.
5. IPAM cascade `address_pool_service.go::doResolve` (5 шагов из `kacho-vpc/CLAUDE.md` §16.2) становится **тривиально family-aware**: `poolHasFamily(pool, family)` заменяется на `len(pool.V4CIDRBlocks) > 0` (для `FamilyV4`) или `len(pool.V6CIDRBlocks) > 0` (для `FamilyV6`). Поведение остаётся идентичным существующему `poolHasFamily` (закрытое KAC-63 поведение family-фильтра сохраняется), но без runtime-парсинга CIDR.
6. Service-layer `address.go::doCreate` / `AllocateExternalIPv4` / `AllocateExternalIPv6` берут IP-блоки из соответствующего family-поля domain-модели (без linear-фильтра по `strings.Contains(":")`).
7. UI `address-pools` ресурс-регистрация (`kacho-ui/src/lib/resource-registry.tsx`): два отдельных array-поля `v4_cidr_blocks` / `v6_cidr_blocks` вместо одного `cidr_blocks`. Visual parity с Subnet Create/Edit: тот же `<SubnetCidrChips>` (controlled chips-list) c IPv4-tag-color=`blue` / IPv6=`geekblue`. Admin-таблица list-view — две колонки «IPv4 CIDR» / «IPv6 CIDR» вместо filter-by-`':'`-rendering.
8. Newman cases (`kacho-vpc/tests/newman/cases/internal-pool.py`): CR-CRUD кейсы обновляются под split-shape; добавляются 4 новых кейса под family-фильтр в cascade и Update full-replace по семейству.

**Что НЕ входит** (явно отложено):
- Изменение Subnet `v4_cidr_blocks`/`v6_cidr_blocks` — оно уже такое.
- Изменение Address `external_ipv4` / `external_ipv6` JSONB shape (это уже family-разделённые поля).
- `AddCidr` / `RemoveCidr` дельта-методы для AddressPool — пока остаётся full-replace через `Update`-PATCH (REQ-IPL-UPD-04 ниже). Дельта-RPC — отдельный issue.
- Migration `0022` rollback path («Down»-секция) — не входит в DoD; новый файл может содержать только `-- +goose Up` (соответственно запрету #5: применённые миграции не редактируются). Rollback `0022` не нужен — split необратим на boilerplate level.
- Обновление CLI `kacho-yc-shim` admin-tooling — этого CLI больше нет (см. `kacho-vpc/CLAUDE.md` §16.7: «`kachoctl-ipam` CLI удалён»).
- Перенос `cidr_blocks` API-shape в kacho-yc-shim compat-слой — verbatim-YC parity отложена (workspace `CLAUDE.md` §«Что это за проект»).
- Изменение AddressPool binding-таблиц (`address_pool_network_default`, `address_pool_address_override`, `network_pool_selector`, `address_pool_free_ips`, `ipv6_pool_cursors`, `ipv6_allocated_ips`, `ipv6_released_offsets`) — все они ссылаются по `pool_id`, family не хранят, эта миграция их не трогает.

**Зафиксированные соглашения:**
- **`v4_cidr_blocks` field tag = 13, `v6_cidr_blocks` = 14** в `AddressPool` (после `selector_priority=12` — следующие свободные). В `CreateAddressPoolRequest`: `v4_cidr_blocks=11`, `v6_cidr_blocks=12`. В `UpdateAddressPoolRequest`: `v4_cidr_blocks=13`, `v6_cidr_blocks=14`. Поле `cidr_blocks` (старое) — `reserved` с указанием прежнего числа и имени.
- **CIDR family detection в API-слое** — `netip.ParsePrefix` + `Addr().Is6() && !Addr().Is4In6()` (как `poolHasFamily` сейчас). Если клиент кладёт IPv6-prefix в `v4_cidr_blocks` или наоборот — sync `InvalidArgument` с verbatim текстом `"v4_cidr_blocks[N]: %q is not an IPv4 prefix"` / `"v6_cidr_blocks[N]: %q is not an IPv6 prefix"`.
- **Host-bits = 0** обязательно для обоих списков (как сейчас для `cidr_blocks`).
- **Хотя бы одно из v4/v6 непусто** — иначе `InvalidArgument "v4_cidr_blocks and v6_cidr_blocks must not be both empty"`.
- **Backfill миграции `0022`** — single-statement update: `UPDATE address_pools SET v4_cidr_blocks = ARRAY(SELECT c FROM unnest(cidr_blocks) c WHERE c !~ ':'), v6_cidr_blocks = ARRAY(SELECT c FROM unnest(cidr_blocks) c WHERE c ~ ':');` — это **идемпотентно при любом порядке применений** (одна и та же подзапросная derivation).
- **Сохранность данных при миграции** — после `0022` для каждого pre-existing pool: `v4_cidr_blocks ∪ v6_cidr_blocks` (как множество строк) == прежний `cidr_blocks` (как множество строк). Покрывается REQ-MIG-01 ниже.
- **Update full-replace — семантика через явный bool-флаг, НЕ через «непустой ИЛИ флаг»** (детерминированно, без implicit-сигналов). `UpdateAddressPoolRequest` имеет два независимых булевых флага: `replace_v4_cidr_blocks: bool` и `replace_v6_cidr_blocks: bool`. Правило:
  - **`replace_v4_cidr_blocks == true`** ⇒ выполняется replace: поле `v4_cidr_blocks` из запроса (любое — пустой массив или непустой) заменяет содержимое БД.
  - **`replace_v4_cidr_blocks == false` (или не задан)** ⇒ значение `v4_cidr_blocks` в запросе **игнорируется** (даже если оно непустое — клиент должен явно поставить флаг). v4-часть pool'а остаётся без изменений.
  - Симметрично для `replace_v6_cidr_blocks` / `v6_cidr_blocks`.
  - Это позволяет менять только один family, не трогая второй; и явно очищать family (передав `replace_v6_cidr_blocks=true, v6_cidr_blocks: []`) — что превращает dual-stack pool в v4-only, и наоборот.
  - **Invariant «хотя бы один непуст» обязан соблюдаться post-update**: попытка очистить оба family одновременно (`replace_v4=true, v4=[], replace_v6=true, v6=[]`) либо очистить единственный непустой family (на v4-only pool: `replace_v4=true, v4=[]` без `replace_v6`) → sync `InvalidArgument "v4_cidr_blocks and v6_cidr_blocks must not be both empty after update"`.
- **IPAM cascade family-filter behavior после рефактора** — идентичен текущему `poolHasFamily` (KAC-63): на каждом из 5 шагов pool без CIDR требуемой family пропускается, cascade проваливается дальше. Никаких новых cascade-веток / приоритетов не вводим. Это покрывается REQ-RESOLVE-01..04 ниже.
- **UNIQUE constraint `addresses_external_pool_ip_uniq`** (v4) и `addresses_external_v6_pool_ip_uniq` (v6) — не трогаются (они на колонках `addresses.external_ipv4`/`external_ipv6`, не на `address_pools.cidr_blocks`).
- **Free-list `address_pool_free_ips`** (миграция `0015`) и cursor `ipv6_pool_cursors` (миграция `0021`) — оба ссылаются на `address_pools(id)` по FK; их state на момент применения `0022` остаётся валидным (миграция не трогает строки этих таблиц).
- **REQ-IPL-* / REQ-MIG-* / REQ-RESOLVE-*** в этом документе — новые требования продукта, после реализации заводятся в `kacho-vpc/tests/newman/docs/PRODUCT-REQUIREMENTS.md` с теми же ID (`vpc-newman-author` отвечает за миграцию формулировок). До того — REQ-* живут только здесь.
- **Newman case-id naming** — следует `kacho-vpc/tests/newman/docs/TAXONOMY.md`: `IPL-<ACTION>-<DETAIL>` (`CR-CRUD-V4-OK`, `CR-VAL-BOTH-EMPTY`, `RESOLVE-V4-ONLY-CONST-V6-FALLTHROUGH`, …).

---

## 1. Группа A — kacho-proto / AddressPool contract

Сценарии группы A проверяют корректность proto-контракта `kacho-proto/proto/kacho/cloud/vpc/v1/internal_address_pool_service.proto` после рефактора. Тесты — `buf lint` + `buf breaking` в CI `kacho-proto`, unit-проверка сгенерированных Go-stubs в `kacho-vpc/internal/handler/internal_address_pool_handler_test.go`.

### A1. proto AddressPool.cidr_blocks → split на v4_cidr_blocks + v6_cidr_blocks

**ID:** 1.x-A1
**REQ:** REQ-IPL-PROTO-01
**Newman:** N/A (proto-shape — buf-test, не runtime)

**Given** файл `kacho-proto/proto/kacho/cloud/vpc/v1/internal_address_pool_service.proto` отрефакторен под KAC-71
**And** baseline ветка `main` имеет старое поле `repeated string cidr_blocks = 7;` в `AddressPool`

**When** разработчик собирает proto-stubs через `make proto` в `kacho-proto`

**Then** в `message AddressPool` присутствуют поля:
- `reserved 7; reserved "cidr_blocks";`
- `repeated string v4_cidr_blocks = 13;`
- `repeated string v6_cidr_blocks = 14;`
**And** старого поля `cidr_blocks` (field=7) нет — компиляция `.go`-stubs не содержит accessor `GetCidrBlocks`
**And** в `CreateAddressPoolRequest`: `reserved 5; reserved "cidr_blocks";`, `repeated string v4_cidr_blocks = 11;`, `repeated string v6_cidr_blocks = 12;`
**And** в `UpdateAddressPoolRequest`:
- `reserved 6; reserved "cidr_blocks";`
- `repeated string v4_cidr_blocks = 13;`
- `repeated string v6_cidr_blocks = 14;`
- `bool replace_v4_cidr_blocks = 15;` (новый — explicit replace trigger; см. §0)
- `bool replace_v6_cidr_blocks = 16;` (новый — explicit replace trigger; см. §0)
**And** `buf lint proto/kacho/cloud/vpc/v1/` завершается с кодом 0 (нет warning'ов)

*Трассируемость:* проверка `buf lint` — в `.github/workflows/ci.yaml` шаге `buf-lint`. Generated-stubs unit-тест — в `kacho-vpc/internal/handler/internal_address_pool_handler_test.go::TestProtoShape_V4V6CidrBlocks` (новый).

### A2. buf breaking регрессирует на baseline (явный breaking change)

**ID:** 1.x-A2
**REQ:** REQ-IPL-PROTO-02
**Newman:** N/A

**Given** ветка `main` `kacho-proto` ещё содержит старое `cidr_blocks = 7` в `AddressPool`
**And** PR `KAC-71` вносит `reserved 7; reserved "cidr_blocks";` + новые `v4_cidr_blocks`/`v6_cidr_blocks`

**When** на PR-ветке выполняется `buf breaking --against 'https://github.com/PRO-Robotech/kacho-proto.git#branch=main'`

**Then** команда завершается с **ненулевым** кодом — поле удалено = breaking change обнаружен
**And** PR-описание содержит явное обоснование breaking (тело тикета KAC-71 + ссылка на этот acceptance-документ); workspace `CLAUDE.md` §«Что это за проект» (verbatim-parity отложена) разрешает такое расхождение

*Трассируемость:* CI step `buf-breaking` — flaky-gate: PR'ит требует human-override через CI label `proto-breaking-ok` (если такого механизма нет — допускается merge при явном решении автора PR, зафиксированном в commit-message `KAC-71 breaking: cidr_blocks → v4/v6_cidr_blocks split`).

### A3. AddressPool generated Go-stubs совместимы с `kacho-vpc` repo/handler сигнатурами

**ID:** 1.x-A3
**REQ:** REQ-IPL-PROTO-03
**Newman:** N/A

**Given** proto перегенерирован (`make proto` в `kacho-proto`)
**And** `kacho-vpc` уже импортирует `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/vpc/v1` (alias `vpcv1`)

**When** в `kacho-vpc` выполняется `go build ./...`

**Then** билд завершается с кодом 0
**And** старые ссылки на `vpcv1.AddressPool{...CidrBlocks: ...}` в `kacho-vpc/internal/handler/*.go` или `internal/service/*.go` — отсутствуют (заменены на `V4CidrBlocks` / `V6CidrBlocks`)
**And** старые ссылки на `vpcv1.CreateAddressPoolRequest{...CidrBlocks: ...}` в тестах / unit-stubs — отсутствуют

*Трассируемость:* `go vet ./...` + `make build` в `kacho-vpc` CI; unit-тест handler-шейпа.

---

## 2. Группа B — kacho-vpc service layer: Create / Update / Get

Сценарии группы B покрывают `internal/service/address_pool_service.go` после рефактора. Тесты — service unit (mock port `AddressPoolRepo`) + integration через testcontainers (`internal/repo/address_pool_repo_integration_test.go::TestRepo_SplitCidrFamilies`).

### B1. Create v4-only pool — happy path

**ID:** 1.x-B1
**REQ:** REQ-IPL-CR-01
**Newman:** `IPL-CR-CRUD-V4-OK` (replaces `IPL-CR-CRUD-OK` для v4-сценария)

**Given** Postgres запущен, миграция `0022_address_pool_split_cidr_family.sql` применена
**And** Zone `ru-central1-c` существует и зарегистрирована в `kacho-compute` (gRPC `ZoneService.Get` отвечает OK)
**And** клиент аутентифицирован как admin (cluster-internal listener)

**When** клиент вызывает `POST /vpc/v1/addressPools` (api-gateway internal mux) с body:
```json
{
  "name": "pool-v4-only",
  "kind": "EXTERNAL_PUBLIC",
  "zoneId": "ru-central1-c",
  "v4CidrBlocks": ["203.0.113.0/24"],
  "v6CidrBlocks": []
}
```

**Then** ответ — HTTP 200, JSON содержит:
- `id` соответствующий regex `^apl[0-9a-z]{17}$` (Crockford-base32, 3+17)
- `name == "pool-v4-only"`
- `kind == "EXTERNAL_PUBLIC"`
- `v4CidrBlocks == ["203.0.113.0/24"]`
- `v6CidrBlocks == []` (либо отсутствует в JSON — protobuf "empty array" repr)
- `isDefault == false` (default)
- `createdAt` непустой ISO-timestamp
**And** в БД `address_pools` строка с этим `id` содержит: `v4_cidr_blocks = ARRAY['203.0.113.0/24']`, `v6_cidr_blocks = ARRAY[]::text[]`
**And** в БД `address_pool_free_ips` материализованы `2^(32-24)-2 = 254` свободных IP с `pool_id = <new-id>` (broadcast/network IP исключены, как требует миграция `0015`)
**And** в БД `ipv6_pool_cursors` строки с `pool_id = <new-id>` **нет** (v6-cursor не инициализируется для v4-only pool)

### B2. Create v6-only pool — happy path

**ID:** 1.x-B2
**REQ:** REQ-IPL-CR-02
**Newman:** `IPL-CR-CRUD-V6-OK` (replaces `IPL-CR-VAL-IPV6-CIDR` после рефактора — теперь v6 идёт в свой слот)

**Given** Postgres + zone `ru-central1-c` существуют (как в B1)

**When** клиент вызывает `POST /vpc/v1/addressPools` с body:
```json
{
  "name": "pool-v6-only",
  "kind": "EXTERNAL_PUBLIC",
  "zoneId": "ru-central1-c",
  "v4CidrBlocks": [],
  "v6CidrBlocks": ["2001:db8::/64"]
}
```

**Then** ответ — HTTP 200, JSON содержит `v4CidrBlocks == []`, `v6CidrBlocks == ["2001:db8::/64"]`, `id` с prefix `apl`
**And** в БД `address_pools` строка содержит `v4_cidr_blocks = ARRAY[]::text[]`, `v6_cidr_blocks = ARRAY['2001:db8::/64']`
**And** в БД `ipv6_pool_cursors` строка `pool_id = <new-id>` с `next_offset = 1` (инициализация через `addrRepo.InitIPv6PoolCursor`)
**And** в БД `address_pool_free_ips` строк с `pool_id = <new-id>` **нет** (freelist v4-only по миграции `0015`)

### B3. Create dual-stack pool — happy path

**ID:** 1.x-B3
**REQ:** REQ-IPL-CR-03
**Newman:** `IPL-CR-CRUD-DUAL-STACK-OK` (новый)

**Given** Postgres + zone `ru-central1-c` существуют

**When** клиент вызывает `POST /vpc/v1/addressPools` с body:
```json
{
  "name": "pool-dual-stack",
  "kind": "EXTERNAL_PUBLIC",
  "zoneId": "ru-central1-c",
  "v4CidrBlocks": ["198.51.100.0/24"],
  "v6CidrBlocks": ["2001:db8:1::/64"]
}
```

**Then** ответ — HTTP 200, JSON содержит и `v4CidrBlocks` и `v6CidrBlocks` непустые
**And** в БД `address_pool_free_ips` материализованы IP только для v4-блока (`254` строки)
**And** в БД `ipv6_pool_cursors` есть строка `pool_id = <new-id>` с `next_offset = 1`

### B4. Create — оба поля пусты → InvalidArgument

**ID:** 1.x-B4
**REQ:** REQ-IPL-CR-04
**Newman:** `IPL-CR-VAL-BOTH-EMPTY` (новый; заменяет старый `IPL-CR-VAL-MISSING-CIDR` — теперь явно про оба поля)

**Given** Postgres + zone существуют

**When** клиент вызывает `POST /vpc/v1/addressPools` с body:
```json
{
  "name": "pool-empty",
  "kind": "EXTERNAL_PUBLIC",
  "zoneId": "ru-central1-c",
  "v4CidrBlocks": [],
  "v6CidrBlocks": []
}
```

**Then** ответ — HTTP 400, gRPC code `INVALID_ARGUMENT` (3)
**And** error message содержит подстроку `"v4_cidr_blocks and v6_cidr_blocks must not be both empty"`
**And** в БД таблица `address_pools` не содержит строки с `name = 'pool-empty'`

### B5. Create — IPv6-префикс в v4_cidr_blocks → InvalidArgument

**ID:** 1.x-B5
**REQ:** REQ-IPL-CR-05
**Newman:** `IPL-CR-VAL-V6-IN-V4-SLOT` (новый)

**Given** Postgres + zone существуют

**When** клиент вызывает `POST /vpc/v1/addressPools` с body:
```json
{
  "name": "pool-cross-family",
  "kind": "EXTERNAL_PUBLIC",
  "zoneId": "ru-central1-c",
  "v4CidrBlocks": ["2001:db8::/64"],
  "v6CidrBlocks": []
}
```

**Then** ответ — HTTP 400, gRPC code `INVALID_ARGUMENT` (3)
**And** error message содержит подстроку `"v4_cidr_blocks[0]: \"2001:db8::/64\" is not an IPv4 prefix"`
**And** обратный случай (`v4CidrBlocks: []`, `v6CidrBlocks: ["10.0.0.0/24"]`) — симметрично, текст `"v6_cidr_blocks[0]: \"10.0.0.0/24\" is not an IPv6 prefix"`

### B6. Create — host-bits в v6_cidr_blocks → InvalidArgument

**ID:** 1.x-B6
**REQ:** REQ-IPL-CR-06
**Newman:** `IPL-CR-VAL-V6-HOSTBITS` (новый; параллельно к существующему `IPL-CR-VAL-BAD-CIDR-HOSTBITS` для v4)

**Given** Postgres + zone существуют

**When** клиент вызывает `POST /vpc/v1/addressPools` с body, где `v6_cidr_blocks = ["2001:db8::5/64"]` (host-bits ≠ 0)

**Then** ответ — HTTP 400, gRPC code `INVALID_ARGUMENT` (3)
**And** error message содержит `"host bits must be zero"` и упоминание canonical-form `"2001:db8::/64"`

### B7. Update — full-replace `v4_cidr_blocks` без изменения v6

**ID:** 1.x-B7
**REQ:** REQ-IPL-UPD-01
**Newman:** `IPL-UPD-V4-REPLACE-ONLY` (новый)

**Given** pool `apl-dual` создан (dual-stack — `v4=["198.51.100.0/24"]`, `v6=["2001:db8::/64"]`)
**And** Address-ов с этим pool пока нет (либо аллокации находятся вне обновляемого v4-диапазона — REQ-IPL-UPD-03)

**When** клиент вызывает `PATCH /vpc/v1/addressPools/apl-dual` с body:
```json
{
  "replaceV4CidrBlocks": true,
  "v4CidrBlocks": ["192.0.2.0/24"]
}
```

**Then** ответ — HTTP 200, JSON содержит `v4CidrBlocks == ["192.0.2.0/24"]`, `v6CidrBlocks == ["2001:db8::/64"]` (НЕ тронут — флаг `replace_v6_cidr_blocks` не выставлен)
**And** в БД `address_pool_free_ips` строки для прежнего v4-диапазона `198.51.100.0/24` удалены, для нового `192.0.2.0/24` — материализованы (254 строки)
**And** `ipv6_pool_cursors` для этого pool — без изменений (cursor не сбрасывается)

### B8. Update — full-replace `v6_cidr_blocks` без изменения v4

**ID:** 1.x-B8
**REQ:** REQ-IPL-UPD-02
**Newman:** `IPL-UPD-V6-REPLACE-ONLY` (новый)

**Given** dual-stack pool `apl-dual` (как в B7)

**When** клиент вызывает `PATCH /vpc/v1/addressPools/apl-dual` с body:
```json
{
  "replaceV6CidrBlocks": true,
  "v6CidrBlocks": ["2001:db8:2::/64"]
}
```

**Then** ответ — HTTP 200, JSON содержит `v6CidrBlocks == ["2001:db8:2::/64"]`, `v4CidrBlocks == ["198.51.100.0/24"]` (НЕ тронут — флаг `replace_v4_cidr_blocks` не выставлен)
**And** `address_pool_free_ips` для v4 — без изменений
**And** `ipv6_pool_cursors.next_offset` для этого pool **сбрасывается на 1** (новый v6-диапазон → cursor пере-инициализируется; KAC-60 invariant: освобождённые offset'ы при replace игнорируются — full clean — отдельный issue если потребуется, см. §12)

### B9. Update — попытка очистить единственный непустой family → InvalidArgument

**ID:** 1.x-B9
**REQ:** REQ-IPL-UPD-03
**Newman:** `IPL-UPD-VAL-CLEAR-BOTH` (новый)

**Given** v4-only pool `apl-v4only` (`v4=["203.0.113.0/24"]`, `v6=[]`)

**When** клиент вызывает `PATCH /vpc/v1/addressPools/apl-v4only` с body, который явно очищает `v4_cidr_blocks` через флаг (а `v6_cidr_blocks` уже пуст и не трогается):
```json
{
  "replaceV4CidrBlocks": true,
  "v4CidrBlocks": []
}
```

**Then** ответ — HTTP 400, gRPC code `INVALID_ARGUMENT` (3)
**And** error message содержит подстроку `"v4_cidr_blocks and v6_cidr_blocks must not be both empty after update"`
**And** в БД pool `apl-v4only` остался без изменений (`v4_cidr_blocks = ARRAY['203.0.113.0/24']`)

*Также проверяется симметричный случай — body `{"replaceV4CidrBlocks": true, "v4CidrBlocks": [], "replaceV6CidrBlocks": true, "v6CidrBlocks": []}` на dual-stack pool (оба флага + оба массива пустые) → тот же `INVALID_ARGUMENT` с тем же текстом, pool без изменений.*

### B10. Update — full-replace `v4_cidr_blocks` с allocated IP в старом диапазоне → FailedPrecondition

**ID:** 1.x-B10
**REQ:** REQ-IPL-UPD-04
**Newman:** `IPL-UPD-NEG-V4-ALLOCATED-CONFLICT` (новый)

**Given** v4-only pool `apl-busy` с `v4=["203.0.113.0/24"]`
**And** Address `e9b-addr1` выделен из этого pool — `external_ipv4 = {"address":"203.0.113.5", "address_pool_id":"apl-busy"}`

**When** клиент вызывает `PATCH /vpc/v1/addressPools/apl-busy` с body `{ "replaceV4CidrBlocks": true, "v4CidrBlocks": ["192.0.2.0/24"] }` (новый диапазон не пересекается с `203.0.113.5`)

**Then** ответ — HTTP 412, gRPC code `FAILED_PRECONDITION` (9)
**And** error message содержит подстроку `"cannot replace v4_cidr_blocks: pool has allocated IPs outside new range"`
**And** pool остался без изменений (`v4_cidr_blocks = ARRAY['203.0.113.0/24']`)

(Это сохраняет существующий invariant — REQ-IPL-UPD-04 наследует контракт `UpdateAddressPoolRequest.cidr_blocks` комментарий «Должно быть disjoint с уже allocated IP в этом пуле».)

### B11. Update — очистить один family на dual-stack pool (positive)

**ID:** 1.x-B11
**REQ:** REQ-IPL-UPD-05
**Newman:** `IPL-UPD-V6-CLEAR-ON-DUAL-STACK` (новый)

**Given** dual-stack pool `apl-dual-clear` создан (`v4=["198.51.100.0/24"]`, `v6=["2001:db8:ff::/64"]`)
**And** Address-ов с этим pool пока нет (либо они только в v4-диапазоне, который НЕ трогается)

**When** клиент вызывает `PATCH /vpc/v1/addressPools/apl-dual-clear` с body:
```json
{
  "replaceV6CidrBlocks": true,
  "v6CidrBlocks": []
}
```

**Then** ответ — HTTP 200, JSON содержит:
- `v4CidrBlocks == ["198.51.100.0/24"]` (НЕ тронут)
- `v6CidrBlocks == []` (явно очищен)
**And** pool теперь — **v4-only**: последующая v6-allocate cascade fall-through'ит этот pool (как в D2)
**And** в БД `v6_cidr_blocks = ARRAY[]::text[]`
**And** `ipv6_pool_cursors` для этого pool: row удаляется (либо `next_offset` обнуляется — реализационная деталь, фиксируется в плане; главное — последующая v6-allocate через этот pool возвращает `ErrPoolNotResolved`)
**And** invariant `v4 ∪ v6 ≠ ∅` соблюдён (v4 непуст)

### B12. Update — ни один replace-флаг не выставлен → no-op (200 + echo прежних значений)

**ID:** 1.x-B12
**REQ:** REQ-IPL-UPD-06
**Newman:** `IPL-UPD-NO-REPLACE-FLAGS-NOOP` (новый)

**Given** dual-stack pool `apl-dual-noop` (`v4=["198.51.100.0/24"]`, `v6=["2001:db8:ff::/64"]`)

**When** клиент вызывает `PATCH /vpc/v1/addressPools/apl-dual-noop` с body, где **ни один из `replace_v4_cidr_blocks` / `replace_v6_cidr_blocks` не выставлен**, но массивы переданы:
```json
{
  "v4CidrBlocks": ["10.99.99.0/24"],
  "v6CidrBlocks": ["2001:db8:dead::/64"],
  "description": "noop update probe"
}
```

**Then** ответ — HTTP 200, JSON содержит:
- `v4CidrBlocks == ["198.51.100.0/24"]` (прежнее, body-значение проигнорировано — флаг `replace_v4_cidr_blocks` не выставлен)
- `v6CidrBlocks == ["2001:db8:ff::/64"]` (прежнее, по той же причине)
- `description == "noop update probe"` (обновлён — это не CIDR-поле)
**And** в БД CIDR-колонки **без изменений** (`v4_cidr_blocks = ARRAY['198.51.100.0/24']`, `v6_cidr_blocks = ARRAY['2001:db8:ff::/64']`)
**And** `address_pool_free_ips` для v4 — без изменений; `ipv6_pool_cursors` — без изменений

*Семантика «оба сигнала не выставлены → CIDR-поля игнорируются»: явный bool-флаг — единственный триггер replace; пустота/непустота массива в запросе сама по себе НЕ замещает поле. (См. §0 «семантика replace через явный bool-флаг».)*

### B13. Bind* RPC — family-agnostic (валидация family только на cascade resolve)

**ID:** 1.x-B13
**REQ:** REQ-IPL-BIND-FAMILY-AGNOSTIC
**Newman:** `IPL-BIND-V6-POOL-TO-NETWORK-OK` (новый; зеркало существующего `IPL-BIND-NETWORK-DEFAULT-OK` для v6)

**Given** v6-only pool `apl-v6-bind` (`v4=[]`, `v6=["2001:db8::/64"]`, `kind=EXTERNAL_PUBLIC`, `zone=ru-central1-c`)
**And** Network `net-bind` создан в folder `f1`

**When** клиент вызывает `POST /vpc/v1/networks/net-bind/addressPoolBinding` (`InternalNetworkService.BindAsNetworkDefault`) с body `{ "poolId": "apl-v6-bind" }`

**Then** ответ — HTTP 200 (или Operation с `done=true`, в зависимости от текущей сигнатуры RPC)
**And** в `address_pool_network_default` появилась row `(network_id="net-bind", pool_id="apl-v6-bind")`
**And** Bind* **НЕ** валидирует family pool'а в момент связывания — pool без v4-блоков **разрешено** биндить к Network, даже если Network может потом использоваться для v4-allocate
**And** на последующей v4-allocate из этого Network cascade (Step 2 = `address_pool_network_default`) выбирает `apl-v6-bind`, видит `len(V4CIDRBlocks)==0`, пропускает его (family-фильтр на resolve), проваливается дальше и (если нет других pool) возвращает `FAILED_PRECONDITION "no address pool resolved ... family=v4"` (REQ-RESOLVE-02)

*Симметрично для `address_pool_address_override` (Step 1) и `cloud_pool_selector` / `network_pool_selector` (Step 3) — Bind/Set* RPC family-agnostic; family-фильтр работает **только на resolve-этапе**. См. §0 + §12 «Bind* RPC family-agnostic».*

---

## 3. Группа C — Миграция 0022 (backfill + drop)

Сценарии группы C покрывают `internal/migrations/0022_address_pool_split_cidr_family.sql`. Тесты — testcontainers Postgres + goose apply (`internal/repo/migration_0022_integration_test.go`, новый файл).

### C1. Backfill из mixed `cidr_blocks` сохраняет данные по family

**ID:** 1.x-C1
**REQ:** REQ-MIG-01
**Newman:** N/A (миграция — integration-only)

**Given** Postgres с pre-applied baseline до `0021_external_ipv6.sql` (включительно)
**And** в `address_pools` есть 3 pool-row до миграции `0022`:
- `apl-AAA1`: `cidr_blocks = ARRAY['203.0.113.0/24', '198.51.100.0/24']` (v4-only mixed)
- `apl-BBB2`: `cidr_blocks = ARRAY['2001:db8::/64']` (v6-only)
- `apl-CCC3`: `cidr_blocks = ARRAY['172.16.0.0/16', 'fd12:3456:789a::/48']` (dual-stack)

**When** применяется миграция `0022_address_pool_split_cidr_family.sql` (`goose up`)

**Then** в `address_pools` после миграции:
- `apl-AAA1`: `v4_cidr_blocks = ARRAY['203.0.113.0/24','198.51.100.0/24']`, `v6_cidr_blocks = ARRAY[]::text[]`
- `apl-BBB2`: `v4_cidr_blocks = ARRAY[]::text[]`, `v6_cidr_blocks = ARRAY['2001:db8::/64']`
- `apl-CCC3`: `v4_cidr_blocks = ARRAY['172.16.0.0/16']`, `v6_cidr_blocks = ARRAY['fd12:3456:789a::/48']`
**And** колонка `cidr_blocks` удалена (`SELECT cidr_blocks FROM address_pools` → SQLSTATE `42703` undefined column)
**And** `address_pool_free_ips` строки сохранены (FK `pool_id → address_pools(id)` остаётся валидной)
**And** `ipv6_pool_cursors` строки сохранены

### C2. Backfill идемпотентен на пустой БД

**ID:** 1.x-C2
**REQ:** REQ-MIG-02
**Newman:** N/A

**Given** Postgres с baseline до `0021` и **пустой** `address_pools` (после bootstrap, до создания pools)

**When** применяется `0022`

**Then** миграция завершается успешно (`goose_db_version` инкрементируется на `22`)
**And** в `address_pools` новые колонки `v4_cidr_blocks text[] NOT NULL DEFAULT '{}'::text[]` / `v6_cidr_blocks text[] NOT NULL DEFAULT '{}'::text[]` присутствуют
**And** колонки `cidr_blocks` нет

### C3. Backfill с pool, у которого все CIDR-блоки одной family (v4-only)

**ID:** 1.x-C3
**REQ:** REQ-MIG-03
**Newman:** N/A

**Given** до миграции существует pool `apl-only-v4` с `cidr_blocks = ARRAY['10.0.0.0/24', '10.1.0.0/24']`

**When** применяется `0022`

**Then** `apl-only-v4` имеет `v4_cidr_blocks = ARRAY['10.0.0.0/24','10.1.0.0/24']`, `v6_cidr_blocks = ARRAY[]::text[]`

### C4. Миграция не трогает binding/freelist/cursor таблицы

**ID:** 1.x-C4
**REQ:** REQ-MIG-04
**Newman:** N/A

**Given** до миграции:
- В `address_pool_network_default` — 5 строк bindings
- В `address_pool_address_override` — 3 строки overrides
- В `address_pool_free_ips` — 1000 строк (материализованных свободных IP)
- В `ipv6_pool_cursors` — 2 строки cursors

**When** применяется `0022`

**Then** все 4 таблицы (`address_pool_network_default`, `address_pool_address_override`, `address_pool_free_ips`, `ipv6_pool_cursors`) содержат **те же** строки до и после миграции (row count, content checksum совпадают)
**And** FK constraints `address_pool_free_ips.pool_id → address_pools(id)` и `ipv6_pool_cursors.pool_id → address_pools(id)` остаются валидными

### C5. Re-apply миграции (идемпотентность goose) — без дублирования backfill

**ID:** 1.x-C5
**REQ:** REQ-MIG-05
**Newman:** N/A

**Given** миграция `0022` уже применена (`goose_db_version >= 22`)
**And** созданы новые pools через split-API (`v4_cidr_blocks`, `v6_cidr_blocks` напрямую)

**When** оператор пытается повторно `goose up` (no-op для уже применённых миграций) или симулирует «re-run», заново выполняя SQL-блок миграции вручную

**Then** при повторном `goose up` — no-op (goose видит, что `0022` уже в `goose_db_version`)
**And** при ручном повторном применении SQL-блока — `ALTER TABLE address_pools ADD COLUMN v4_cidr_blocks ...` падает с SQLSTATE `42701` (duplicate_column) — это ожидаемо; миграция использует `ADD COLUMN IF NOT EXISTS` чтобы избежать ошибки в re-run-сценарии (см. DoD §11)
**And** backfill-блок `UPDATE address_pools SET v4_cidr_blocks = ...` идемпотентен: повторный UPDATE на уже разделённую таблицу выставляет те же значения (single derivation из `cidr_blocks` — но `cidr_blocks` уже DROP'нута → этот UPDATE wrapped в `IF EXISTS` check / `DO $$ ... $$` block с проверкой `information_schema.columns`)

### C6. Backfill defensive check — pool с пустым `cidr_blocks` обрывает миграцию

**ID:** 1.x-C6
**REQ:** REQ-MIG-06
**Newman:** N/A

**Given** до миграции `0022` существует pool-row, у которого `cardinality(cidr_blocks) = 0` (теоретически невозможно — service-слой это запрещает через REQ-IPL-CR-04-предшественник, но row просочилась через прямой `INSERT` / data import / pre-fix bug)

**When** применяется миграция `0022_address_pool_split_cidr_family.sql`

**Then** миграция **падает** с PostgreSQL SQLSTATE `P0001` (`raise_exception`) и сообщением вида `address_pool <id> has empty cidr_blocks; refusing to migrate (would violate post-migration invariant v4∪v6 ≠ ∅)`
**And** транзакция rollback'нута: `goose_db_version` НЕ инкрементируется (остаётся на `21`)
**And** колонки `v4_cidr_blocks` / `v6_cidr_blocks` НЕ добавлены, `cidr_blocks` НЕ удалена (БД в исходном состоянии)
**And** оператор получает явное сообщение «есть pool с empty cidr — fix data, retry»; единственный fix — вручную delete/update эту row, затем повторно `goose up`

*Reasoning: после миграции инвариант `v4 ∪ v6 ≠ ∅` обязателен (REQ-IPL-CR-04). Если backfill завершится на pool с empty cidr — он получит `v4=[]`, `v6=[]`, что нарушит invariant, и любой последующий `Update` упадёт с InvalidArgument. Defensive guard в backfill-блоке (PL/pgSQL `IF EXISTS (SELECT 1 FROM address_pools WHERE cardinality(cidr_blocks)=0) THEN RAISE EXCEPTION ...`) перехватывает это **до** структурного изменения таблицы — fail-closed, не data-loss-prone.*

---

## 4. Группа D — IPAM cascade resolve (family-aware)

Сценарии группы D покрывают `internal/service/address_pool_service.go::doResolve` (5-step cascade) после рефактора `poolHasFamily`. Тесты — integration через testcontainers (`internal/repo/ipam_cascade_integration_test.go::TestCascade_SplitFamily*`, расширение существующего).

### D1. Cascade — v4-only pool не резолвится для v6-allocate

**ID:** 1.x-D1
**REQ:** REQ-RESOLVE-01
**Newman:** `ADR-CR-EXT-V6-V4ONLY-POOL-FALLTHROUGH` (новый; параллельно к существующему `ADR-CR-EXT-V6-FAMILY-FALLTHROUGH` от KAC-63 — но с явной split-shape)

**Given** Postgres + миграция `0022` применена
**And** глобальный default v4-only pool `apl-global-v4` существует — `v4_cidr_blocks=["203.0.113.0/24"]`, `v6_cidr_blocks=[]`, `is_default=true`, `zone_id=""`, `kind=EXTERNAL_PUBLIC`
**And** другой default pool для требуемой v6-семьи в этой zone — отсутствует
**And** Network `net-1` создан в folder `f1`, без `pool_selector` / `BindAsNetworkDefault`
**And** Address `addr-1` создаётся с `external_ipv6_spec = { zone_id: "ru-central1-c" }` (запрос на v6-аллокацию)

**When** `AddressService.AllocateExternalIPv6(ctx, "addr-1")` идёт через cascade `ResolvePoolForAddressObjFamily(addr-1, FamilyV6)`

**Then** ни на одном шаге cascade pool `apl-global-v4` НЕ выбирается (он не имеет v6_cidr_blocks)
**And** cascade проваливается до Step 5 (global_default для v6 — отсутствует)
**And** allocate возвращает `FAILED_PRECONDITION` с текстом `"no address pool resolved for address addr-1 (family=v6)"` (как сейчас формируется `ErrPoolNotResolved`)

### D2. Cascade — v6-only pool не резолвится для v4-allocate

**ID:** 1.x-D2
**REQ:** REQ-RESOLVE-02
**Newman:** `ADR-CR-EXT-V4-V6ONLY-POOL-FALLTHROUGH` (новый; зеркало D1)

**Given** Postgres + миграция применена
**And** глобальный default v6-only pool `apl-global-v6` — `v4_cidr_blocks=[]`, `v6_cidr_blocks=["2001:db8::/64"]`, `is_default=true`
**And** v4-default pool в zone отсутствует
**And** Address создаётся с `external_ipv4_spec = { zone_id: "ru-central1-c" }`

**When** `AllocateExternalIPv4` идёт через cascade

**Then** pool `apl-global-v6` НЕ выбирается ни на одном шаге
**And** allocate возвращает `FAILED_PRECONDITION` `"no address pool resolved for address ... (family=v4)"`

### D3. Cascade — dual-stack pool резолвится для обоих family

**ID:** 1.x-D3
**REQ:** REQ-RESOLVE-03
**Newman:** `ADR-CR-EXT-DUAL-STACK-RESOLVE-V4-V6-OK` (новый, multi-step)

**Given** Postgres + миграция применена
**And** один dual-stack pool `apl-ds` существует — `v4_cidr_blocks=["198.51.100.0/24"]`, `v6_cidr_blocks=["2001:db8:ff::/64"]`, `is_default=true`, `zone_id="ru-central1-c"`, `kind=EXTERNAL_PUBLIC`
**And** Network `net-ds` в folder `f1`, без `pool_selector`

**When** клиент создаёт Address `addr-v4` с `external_ipv4_spec.zone_id="ru-central1-c"` (без override)
**And** клиент создаёт Address `addr-v6` с `external_ipv6_spec.zone_id="ru-central1-c"`

**Then** для `addr-v4` cascade выбирает `apl-ds` (Step 4 = zone_default) и аллоцирует IP из `198.51.100.0/24`
**And** для `addr-v6` cascade выбирает тот же `apl-ds` и аллоцирует IP из `2001:db8:ff::/64`
**And** обе аллокации успешны (HTTP 200, Operation done, `external_ipv4.address_pool_id == apl-ds`, `external_ipv6.address_pool_id == apl-ds`)
**And** `address_pool_free_ips` для `apl-ds` уменьшается на 1
**And** `ipv6_allocated_ips` для `apl-ds` увеличивается на 1
**And** `ipv6_pool_cursors.next_offset` для `apl-ds` инкрементируется

### D4. Cascade — ExplainResolution на fall-through отдаёт HTTP 200 с пустым `selected_pool` и `matched_via="none"`

**ID:** 1.x-D4
**REQ:** REQ-RESOLVE-04
**Newman:** `IPL-EXPLAIN-FAMILY-V6-FALLTHROUGH` (новый)

**Given** только один pool `apl-v4only` (`v4=[..]`, `v6=[]`, `is_default=true`, `zone=ru-central1-c`)
**And** Address `addr-v6-req` создан с `external_ipv6_spec.zone_id="ru-central1-c"` (без allocated IP — резерв-стадия)

**When** клиент вызывает `GET /vpc/v1/addressPools:explainResolution?addressId=addr-v6-req`

**Then** ответ — HTTP 200, gRPC code `OK`
**And** `selectedPool` отсутствует / null (cascade fall-through, никакого pool нет для v6 в зоне)
**And** `matchedVia == "none"` (явный sentinel, означает «ни один шаг cascade не дал pool»)
**And** `matchedSelector` — пустой объект/отсутствует
**And** `runnerUpPool` — отсутствует
**And** `runnerUpMatchedVia` — пустая строка

**Зафиксированное поведение (требует изменения кода — см. DoD §10):**
Текущая реализация `InternalAddressPoolHandler.ExplainResolution` (`internal/handler/internal_address_pool_handler.go:156`) при `ErrPoolNotResolved` из `AddressPoolService.ExplainResolution` возвращает `gRPC FailedPrecondition` (через `mapPoolErr → internalMapErr`, ветка `errors.Is(err, service.ErrPoolNotResolved)` в `internal_maperr.go:39`).

В рамках KAC-71 это поведение **меняется** для `ExplainResolution` (но НЕ для `AllocateExternalIPv4`/`AllocateExternalIPv6`): handler ловит `ErrPoolNotResolved` отдельно (до `mapPoolErr`) и возвращает `ExplainResolutionResponse{ MatchedVia: "none" }` с HTTP 200 / gRPC OK. Это позволяет admin-UI рендерить «нет подходящего pool» без обработки HTTP 412.

Семантика остальных Allocate-методов (REQ-RESOLVE-01/02 — D1/D2) — **без изменений**: при `ErrPoolNotResolved` они продолжают возвращать `FailedPrecondition`. ExplainResolution — диагностический admin-метод, для него «нет pool» — нормальный ответ, а не ошибка.

### D5. Cascade — label-selector cascade (Step 3) пропускает pool не той family

**ID:** 1.x-D5
**REQ:** REQ-RESOLVE-05
**Newman:** `IPL-RESOLVE-SELECTOR-FAMILY-SKIP` (новый)

**Given** Postgres + миграция
**And** Network `net-premium` имеет `pool_selector = {"tier":"premium"}` (через `InternalNetworkService.SetPoolSelector`)
**And** pool `apl-premium-v4`: `v4=["203.0.113.0/24"]`, `v6=[]`, `selector_labels={"tier":"premium"}`, `selector_priority=100`, `zone=ru-central1-c`
**And** pool `apl-premium-v6`: `v4=[]`, `v6=["2001:db8:ff::/64"]`, `selector_labels={"tier":"premium"}`, `selector_priority=100`, `zone=ru-central1-c`
**And** Address `addr-pre-v4` создаётся в `net-premium` с `external_ipv4_spec.zone_id="ru-central1-c"`
**And** Address `addr-pre-v6` создаётся в `net-premium` с `external_ipv6_spec.zone_id="ru-central1-c"`

**When** для каждого address вызывается `Allocate*`

**Then** `addr-pre-v4` резолвится на Step 3 в `apl-premium-v4` (v6-pool пропускается family-фильтром)
**And** `addr-pre-v6` резолвится на Step 3 в `apl-premium-v6` (v4-pool пропускается family-фильтром)
**And** оба allocate успешны
**And** `ExplainResolution` для каждого address возвращает соответствующий `matchedVia == "label_selector"` и правильный `selectedPool.id`

### D6. Cascade Step 1 — per-address override на pool не той family → family-фильтр пропускает, fall-through

**ID:** 1.x-D6
**REQ:** REQ-RESOLVE-06
**Newman:** `IPL-RESOLVE-OVERRIDE-FAMILY-SKIP` (новый; покрывает Step 1)

**Given** Postgres + миграция `0022` применена
**And** v4-only pool `apl-override-v4` (`v4=["203.0.113.0/24"]`, `v6=[]`)
**And** Address `addr-override-v6` создан с `external_ipv6_spec.zone_id="ru-central1-c"` (запрос на v6-аллокацию, ещё не allocated)
**And** через `InternalAddressPoolService.OverridePoolForAddress` (Step 1: `address_pool_address_override`) выставлен явный override: `addr-override-v6 → apl-override-v4`
**And** другого v6-pool для этой zone нет

**When** `AddressService.AllocateExternalIPv6(ctx, "addr-override-v6")` идёт через cascade `ResolvePoolForAddressObjFamily(addr, FamilyV6)`

**Then** cascade Step 1 (`address_pool_address_override`) находит pool `apl-override-v4` по address_id, но family-фильтр пропускает его (v6_cidr_blocks пуст) — НЕ выбирает на Step 1
**And** cascade продолжается на Step 2..5, нигде v6-pool не находится
**And** результат — `FAILED_PRECONDITION "no address pool resolved for address ... (family=v6)"` (ErrPoolNotResolved)
**And** Address остаётся в pre-allocate состоянии (`external_ipv6.address` пуст)

*Зафиксированный default: Step 1 family-фильтр работает по тому же правилу `poolHasFamily`, что и Step 2..5 — pool не той family пропускается, cascade fall-through до конца. (Alternative «Step 1 — abort cascade с явной ошибкой "explicit override has wrong family"» — отвергнут: симметрия с Step 2..5 проще и не вводит специальную ветку.) Этот выбор зафиксирован: явный override НЕ форсирует family-mismatch — semantic family-filter unified across all 5 steps.*

### D7. Cascade Step 2 — per-network default pool не той family → family-фильтр пропускает, fall-through

**ID:** 1.x-D7
**REQ:** REQ-RESOLVE-07
**Newman:** `IPL-RESOLVE-NETWORK-DEFAULT-FAMILY-SKIP` (новый; покрывает Step 2)

**Given** Postgres + миграция `0022` применена
**And** v6-only pool `apl-netdef-v6` (`v4=[]`, `v6=["2001:db8::/64"]`)
**And** Network `net-bind-mismatch` в folder `f1` имеет binding (Step 2: `address_pool_network_default`): `net-bind-mismatch → apl-netdef-v6`
**And** Address `addr-bind-v4` создан в `net-bind-mismatch` с `external_ipv4_spec.zone_id="ru-central1-c"` (запрос на v4-аллокацию)
**And** другого v4-pool для этой zone (через Step 3..5) нет

**When** `AllocateExternalIPv4` идёт через cascade с `family=FamilyV4`

**Then** cascade Step 2 находит binding `net-bind-mismatch → apl-netdef-v6`, но family-фильтр пропускает (v4_cidr_blocks пуст) — НЕ выбирает на Step 2
**And** cascade продолжается на Step 3..5, нигде v4-pool не находится
**And** результат — `FAILED_PRECONDITION "no address pool resolved for address ... (family=v4)"`

*Симметрично D6 — family-фильтр работает на всех 5 шагах cascade единообразно; binding/override НЕ форсирует family-mismatch.*

---

## 5. Группа E — Newman regression (api-gateway internal mux, e2e через REST)

Группа E — black-box проверка через api-gateway. Cases — `kacho-vpc/tests/newman/cases/internal-pool.py` (+ дополнения в `address.py` для Allocate-сценариев). Все case-id'ы уникальны (`validate-cases.py` hard-fail на dup); каждый — REQ-* мапится на REQ-IPL-/REQ-RESOLVE-/REQ-MIG-* из этого документа после ввода в `PRODUCT-REQUIREMENTS.md`.

### E1. IPL-CR-CRUD-V4-OK заменяет IPL-CR-CRUD-OK для v4-сценария

**ID:** 1.x-E1
**REQ:** REQ-IPL-CR-01 (REQ-newman-coverage)
**Newman case:** `IPL-CR-CRUD-V4-OK`

**Given** старый case `IPL-CR-CRUD-OK` в `internal-pool.py` использовал `"cidrBlocks": ["203.0.113.0/24"]`

**When** разработчик переименовывает / обновляет case под split-shape

**Then** новый case с id `IPL-CR-CRUD-V4-OK` шлёт `POST /vpc/v1/addressPools` с body `{"name":"ipl-crud-{{runId}}", "kind":"EXTERNAL_PUBLIC", "zoneId":"ru-central1-c", "v4CidrBlocks": ["203.0.113.0/24"], "v6CidrBlocks": []}` и ожидает 200 + `v4CidrBlocks` echo'нут в response
**And** старый case-id `IPL-CR-CRUD-OK` удалён из `cases/internal-pool.py` (или sentinel-pattern: меняется literal-id, остальное идентично)
**And** запись в `CASES-INDEX.md` обновлена; запись в `PRODUCT-REQUIREMENTS.md` (новый REQ-IPL-CR-01) — добавлена
**And** `python3 tests/newman/scripts/validate-cases.py` проходит без дублей
**And** `python3 tests/newman/scripts/gen.py` регенерит коллекции
**And** `tests/newman/scripts/run.sh --service internal-pool` показывает 0 fail

### E2. Новые negative-кейсы добавлены

**ID:** 1.x-E2
**REQ:** REQ-IPL-CR-04..06, REQ-IPL-UPD-03
**Newman:** `IPL-CR-VAL-BOTH-EMPTY`, `IPL-CR-VAL-V6-IN-V4-SLOT`, `IPL-CR-VAL-V6-HOSTBITS`, `IPL-UPD-VAL-CLEAR-BOTH`

**Given** обновлённый `internal-pool.py`

**When** newman гоняется

**Then** все 4 новых negative-case прохождят (expecting 400 + correct gRPC code 3)
**And** каждый case-id присутствует в `CASES-INDEX.md` (классы `VAL`/`NEG`, priority `P0`/`P1`)
**And** каждый ссылается на REQ-IPL-CR-04..06 / REQ-IPL-UPD-03 в `PRODUCT-REQUIREMENTS.md`

### E3. Новые family-cascade кейсы добавлены

**ID:** 1.x-E3
**REQ:** REQ-RESOLVE-01..07
**Newman:** `ADR-CR-EXT-V6-V4ONLY-POOL-FALLTHROUGH`, `ADR-CR-EXT-V4-V6ONLY-POOL-FALLTHROUGH`, `ADR-CR-EXT-DUAL-STACK-RESOLVE-V4-V6-OK`, `IPL-EXPLAIN-FAMILY-V6-FALLTHROUGH`, `IPL-RESOLVE-SELECTOR-FAMILY-SKIP`, `IPL-RESOLVE-OVERRIDE-FAMILY-SKIP`, `IPL-RESOLVE-NETWORK-DEFAULT-FAMILY-SKIP`

**Given** дополненный `address.py` (кейсы на ADR-*) и `internal-pool.py` (на IPL-*)

**When** newman гоняется

**Then** все 7 кейсов проходят (5 из round 1 + 2 новых на Step 1 / Step 2 family-фильтр)
**And** `RESULTS.md` инкрементирует общий счётчик кейсов / assertions
**And** новые case-id зафиксированы в `CASES-INDEX.md`

### E4. Новые Update/Bind positive-кейсы добавлены (round 2 delta)

**ID:** 1.x-E4
**REQ:** REQ-IPL-UPD-05, REQ-IPL-UPD-06, REQ-IPL-BIND-FAMILY-AGNOSTIC
**Newman:** `IPL-UPD-V6-CLEAR-ON-DUAL-STACK`, `IPL-UPD-NO-REPLACE-FLAGS-NOOP`, `IPL-BIND-V6-POOL-TO-NETWORK-OK`

**Given** обновлённый `internal-pool.py`

**When** newman гоняется

**Then** все 3 новых positive-case проходят (200 + verified DB state / DB unchanged для noop)
**And** каждый case-id присутствует в `CASES-INDEX.md`
**And** каждый ссылается на REQ-IPL-UPD-05 / REQ-IPL-UPD-06 / REQ-IPL-BIND-FAMILY-AGNOSTIC в `PRODUCT-REQUIREMENTS.md`

---

## 6. Группа F — UI (kacho-ui)

Сценарии группы F покрывают изменения в `kacho-ui/src/lib/resource-registry.tsx` (spec `address-pools`) и связанные inline-форм-компоненты. Тесты — manual smoke на стенде (нет автоматизированных UI-тестов в проекте сейчас).

### F1. UI Address-Pool Create form показывает два отдельных CIDR-блока

**ID:** 1.x-F1
**REQ:** REQ-UI-IPL-01

**Given** стенд развёрнут, миграция применена, kacho-vpc + kacho-ui собраны под KAC-71

**When** оператор открывает `?modal=address-pools-create` из admin-страницы AddressPool

**Then** в форме видны два независимых блока (`<SubnetCidrChips>`):
- «IPv4 CIDR blocks» — chip-list с tag-color=`blue`, ADD-input
- «IPv6 CIDR blocks» — chip-list с tag-color=`geekblue`, ADD-input
**And** старый одиночный «CIDR Blocks» array-field отсутствует
**And** label «IPv4 CIDR blocks» имеет info-tooltip с пояснением «v4-only / dual-stack pool — заполните хотя бы один из v4/v6»
**And** при отправке формы `sanitize` (resource-registry) маппит UI-shape в wire-shape `{v4CidrBlocks, v6CidrBlocks}` (snake-case `v4_cidr_blocks` после snake-mapping); body POST request содержит ровно эти два поля, не `cidrBlocks`

### F2. UI Address-Pool Edit form различает v4 / v6

**ID:** 1.x-F2
**REQ:** REQ-UI-IPL-02

**Given** существующий dual-stack pool `apl-ds` (`v4=["198.51.100.0/24"]`, `v6=["2001:db8:ff::/64"]`)

**When** оператор открывает `?modal=address-pools-edit&id=apl-ds`

**Then** в форме pre-loaded:
- IPv4 chip-list содержит `198.51.100.0/24`
- IPv6 chip-list содержит `2001:db8:ff::/64`
**And** оператор может удалить v6-chip и сохранить → отправляется PATCH `{v6CidrBlocks: []}` (с явным `replace_v6_cidr_blocks=true`)
**And** на server-side операция отрабатывает по REQ-IPL-UPD-02

### F3. UI Address-Pool list — две колонки IPv4 / IPv6

**ID:** 1.x-F3
**REQ:** REQ-UI-IPL-03

**Given** в БД 3 pool: v4-only, v6-only, dual-stack

**When** оператор открывает страницу `/system/address-pools`

**Then** в таблице видны:
- Колонка «IPv4 CIDR» — рендерит `row.v4_cidr_blocks.join(", ")` или `"—"` если пусто (без runtime-фильтра по `':'`)
- Колонка «IPv6 CIDR» — рендерит `row.v6_cidr_blocks.join(", ")` или `"—"`
**And** monospace + `text-xs`-стиль сохранён (как сейчас)
**And** `RefSelect.tsx` (`extraInfoFor.address-pools`) показывает CIDR в виде `<v4-blocks-joined>; <v6-blocks-joined>` (или `<v4>` если v6 пуст, и наоборот) — обновлён под split

### F4. UI смок: v4-only pool создать → v6-allocate в этой zone → понятная ошибка

**ID:** 1.x-F4
**REQ:** REQ-UI-IPL-04

**Given** оператор создал через UI новый v4-only pool в zone `ru-central1-d` (изолированной от seeded `default-ru-central1-a`)
**And** в этой zone нет других pool

**When** оператор переходит в `Address Create`, заполняет `external_ipv6_spec.zone_id = ru-central1-d` и отправляет

**Then** UI получает HTTP 412 / gRPC `FAILED_PRECONDITION` с текстом про `"no address pool resolved ... family=v6"` (REQ-RESOLVE-01)
**And** toast.error показывает этот текст (форма НЕ закрывается, как требует `kacho-ui/CLAUDE.md` §3.5)

---

## 7. Группа G — Smoke e2e через api-gateway (port-forward)

Финальная проверка после merge всех изменений. Скрипты — `kacho-deploy/e2e/1.x-addresspool-cidr-split/<ID>-<short-desc>.sh` (новый каталог).

### G1. Полный CR-CRUD цикл split-shape — admin smoke

**ID:** 1.x-G1
**REQ:** REQ-SMOKE-01

**Given** `make dev-up` (kind cluster, kacho-vpc/api-gateway/ui собраны на KAC-71)
**And** port-forward на `api-gateway:8080 → localhost:18080`

**When** оператор гоняет smoke:
```bash
# Create v4-only
curl -XPOST http://localhost:18080/vpc/v1/addressPools \
  -H 'content-type: application/json' \
  -d '{"name":"smoke-v4","kind":"EXTERNAL_PUBLIC","zoneId":"ru-central1-c","v4CidrBlocks":["203.0.113.0/24"],"v6CidrBlocks":[]}'

# Create v6-only
curl -XPOST http://localhost:18080/vpc/v1/addressPools \
  -H 'content-type: application/json' \
  -d '{"name":"smoke-v6","kind":"EXTERNAL_PUBLIC","zoneId":"ru-central1-c","v4CidrBlocks":[],"v6CidrBlocks":["2001:db8::/64"]}'

# Create dual-stack
curl -XPOST http://localhost:18080/vpc/v1/addressPools \
  -H 'content-type: application/json' \
  -d '{"name":"smoke-ds","kind":"EXTERNAL_PUBLIC","zoneId":"ru-central1-c","v4CidrBlocks":["198.51.100.0/24"],"v6CidrBlocks":["2001:db8:1::/64"]}'

# List — все 3 видны с split-полями
curl http://localhost:18080/vpc/v1/addressPools?zoneId=ru-central1-c

# Cleanup
for p in smoke-v4 smoke-v6 smoke-ds; do
  PID=$(curl -s "http://localhost:18080/vpc/v1/addressPools?zoneId=ru-central1-c" | jq -r ".pools[] | select(.name==\"$p\") | .id")
  curl -XDELETE "http://localhost:18080/vpc/v1/addressPools/$PID"
done
```

**Then** все 3 Create запроса — HTTP 200, JSON содержит `v4CidrBlocks`/`v6CidrBlocks` echo
**And** List показывает 3 pool с правильным split (старого `cidrBlocks` нет нигде в JSON)
**And** Delete — HTTP 200 на каждом

### G2. Newman regression полный прогон зелёный

**ID:** 1.x-G2
**REQ:** REQ-SMOKE-02

**Given** все newman-кейсы обновлены, валидированы, регенерированы (см. §5)
**And** стенд развёрнут

**When** оператор гоняет `tests/newman/scripts/run.sh` (все сервисы)

**Then** общее число pass == прежнее + **18 новых case** (net add; перечень — таблица ниже) = новый baseline
**And** failed == 0
**And** `RESULTS.md` обновляется новой версией (v19 или следующей)

**Точный учёт newman-кейсов (delta KAC-71):**

| Группа | Case-id | Тип | Net delta |
|---|---|---|---|
| B1 | `IPL-CR-CRUD-V4-OK` | rename: `IPL-CR-CRUD-OK → ...V4-OK` | 0 |
| B2 | `IPL-CR-CRUD-V6-OK` | new | +1 |
| B3 | `IPL-CR-CRUD-DUAL-STACK-OK` | new | +1 |
| B4 | `IPL-CR-VAL-BOTH-EMPTY` | rename: `IPL-CR-VAL-MISSING-CIDR → ...` | 0 |
| B5 | `IPL-CR-VAL-V6-IN-V4-SLOT` | new | +1 |
| B6 | `IPL-CR-VAL-V6-HOSTBITS` | new | +1 |
| B7 | `IPL-UPD-V4-REPLACE-ONLY` | new | +1 |
| B8 | `IPL-UPD-V6-REPLACE-ONLY` | new | +1 |
| B9 | `IPL-UPD-VAL-CLEAR-BOTH` | new | +1 |
| B10 | `IPL-UPD-NEG-V4-ALLOCATED-CONFLICT` | new | +1 |
| B11 | `IPL-UPD-V6-CLEAR-ON-DUAL-STACK` | new | +1 |
| B12 | `IPL-UPD-NO-REPLACE-FLAGS-NOOP` | new | +1 |
| B13 | `IPL-BIND-V6-POOL-TO-NETWORK-OK` | new | +1 |
| D1 | `ADR-CR-EXT-V6-V4ONLY-POOL-FALLTHROUGH` | new | +1 |
| D2 | `ADR-CR-EXT-V4-V6ONLY-POOL-FALLTHROUGH` | new | +1 |
| D3 | `ADR-CR-EXT-DUAL-STACK-RESOLVE-V4-V6-OK` | new | +1 |
| D4 | `IPL-EXPLAIN-FAMILY-V6-FALLTHROUGH` | new | +1 |
| D5 | `IPL-RESOLVE-SELECTOR-FAMILY-SKIP` | new | +1 |
| D6 | `IPL-RESOLVE-OVERRIDE-FAMILY-SKIP` | new | +1 |
| D7 | `IPL-RESOLVE-NETWORK-DEFAULT-FAMILY-SKIP` | new | +1 |
| | **Total** | | **+18** |

---

## 8. Группа H — Negative / edge sync-валидация

### H1. UNIQUE constraint `addresses_external_pool_ip_uniq` не сломан

**ID:** 1.x-H1
**REQ:** REQ-IPL-INVARIANT-01

**Given** v4-only pool `apl-busy` с `v4_cidr_blocks=["203.0.113.0/24"]`
**And** Address `e9b-a1` уже имеет `external_ipv4.address = "203.0.113.5"`, `external_ipv4.address_pool_id = "apl-busy"`

**When** другой Address `e9b-a2` пытается аллоцировать тот же IP `203.0.113.5` из того же pool (race race-of-1 / direct INSERT через testcontainers)

**Then** Postgres возвращает SQLSTATE `23505` (unique_violation) по индексу `addresses_external_pool_ip_uniq`
**And** service маппит в gRPC `ALREADY_EXISTS` / `FAILED_PRECONDITION` (согласно `mapRepoErr` / `wrapPgErr`)
**And** второй address остаётся в pre-allocate state (никакого «второго writer wins»)

(Это не breaking-change — миграция `0022` его не трогает; кейс зафиксирован как regression-check, см. workspace `CLAUDE.md` §«Within-service refs — DB-уровень обязателен».)

### H2. UNIQUE constraint `addresses_external_v6_pool_ip_uniq` не сломан

**ID:** 1.x-H2
**REQ:** REQ-IPL-INVARIANT-02

**Given** v6-only pool `apl-busy-v6` с `v6_cidr_blocks=["2001:db8::/64"]`
**And** Address `e9b-b1` уже имеет `external_ipv6.address = "2001:db8::5"`, `address_pool_id = "apl-busy-v6"`

**When** второй Address пытается выделить тот же v6 IP

**Then** Postgres возвращает SQLSTATE `23505` по `addresses_external_v6_pool_ip_uniq`
**And** service маппит в gRPC `ALREADY_EXISTS` / `FAILED_PRECONDITION`

### H3. Концурентный Create dual-stack pool с тем же `(zone_id, kind, is_default=true)` → один pool выигрывает

**ID:** 1.x-H3
**REQ:** REQ-IPL-INVARIANT-03

**Given** Postgres + миграция применена
**And** в zone `ru-central1-c` ещё нет `is_default=true` pool для `kind=EXTERNAL_PUBLIC`

**When** два concurrent клиента одновременно создают:
- Client A: `{name:"def-a", kind:"EXTERNAL_PUBLIC", zoneId:"ru-central1-c", v4CidrBlocks:["10.0.0.0/24"], isDefault:true}`
- Client B: `{name:"def-b", kind:"EXTERNAL_PUBLIC", zoneId:"ru-central1-c", v6CidrBlocks:["2001:db8::/64"], isDefault:true}`

**Then** один из запросов проходит (HTTP 200), второй получает SQLSTATE `23505` через partial UNIQUE `address_pools_zone_kind_default_uniq` → gRPC `ALREADY_EXISTS` (или `FAILED_PRECONDITION` — в зависимости от mapping; см. existing `mapRepoErr`)
**And** в БД остаётся ровно один pool с `(zone_id, kind, is_default=true)` для данной пары

(Этот invariant унаследован от `address_pools_zone_kind_default_uniq` в `0001_initial.sql:490` — миграция `0022` его не трогает; кейс — regression-check, что добавление двух CIDR-колонок не сломало partial-UNIQUE.)

---

## 9. Перекрёстная карта REQ ↔ сценарий ↔ newman-case

| REQ                            | Сценарий       | Newman case-id                                  |
|--------------------------------|----------------|--------------------------------------------------|
| REQ-IPL-PROTO-01               | 1.x-A1         | (proto-only, без newman)                        |
| REQ-IPL-PROTO-02               | 1.x-A2         | (CI-only)                                       |
| REQ-IPL-PROTO-03               | 1.x-A3         | (build-only)                                    |
| REQ-IPL-CR-01                  | 1.x-B1, 1.x-E1 | `IPL-CR-CRUD-V4-OK`                             |
| REQ-IPL-CR-02                  | 1.x-B2         | `IPL-CR-CRUD-V6-OK`                             |
| REQ-IPL-CR-03                  | 1.x-B3         | `IPL-CR-CRUD-DUAL-STACK-OK`                     |
| REQ-IPL-CR-04                  | 1.x-B4, 1.x-E2 | `IPL-CR-VAL-BOTH-EMPTY`                         |
| REQ-IPL-CR-05                  | 1.x-B5, 1.x-E2 | `IPL-CR-VAL-V6-IN-V4-SLOT`                      |
| REQ-IPL-CR-06                  | 1.x-B6, 1.x-E2 | `IPL-CR-VAL-V6-HOSTBITS`                        |
| REQ-IPL-UPD-01                 | 1.x-B7         | `IPL-UPD-V4-REPLACE-ONLY`                       |
| REQ-IPL-UPD-02                 | 1.x-B8         | `IPL-UPD-V6-REPLACE-ONLY`                       |
| REQ-IPL-UPD-03                 | 1.x-B9, 1.x-E2 | `IPL-UPD-VAL-CLEAR-BOTH`                        |
| REQ-IPL-UPD-04                 | 1.x-B10        | `IPL-UPD-NEG-V4-ALLOCATED-CONFLICT`             |
| REQ-IPL-UPD-05                 | 1.x-B11        | `IPL-UPD-V6-CLEAR-ON-DUAL-STACK`                |
| REQ-IPL-UPD-06                 | 1.x-B12        | `IPL-UPD-NO-REPLACE-FLAGS-NOOP`                 |
| REQ-IPL-BIND-FAMILY-AGNOSTIC   | 1.x-B13        | `IPL-BIND-V6-POOL-TO-NETWORK-OK`                |
| REQ-MIG-01..05                 | 1.x-C1..C5     | (integration-only, без newman)                  |
| REQ-MIG-06                     | 1.x-C6         | (integration-only, без newman)                  |
| REQ-RESOLVE-01                 | 1.x-D1, 1.x-E3 | `ADR-CR-EXT-V6-V4ONLY-POOL-FALLTHROUGH`         |
| REQ-RESOLVE-02                 | 1.x-D2, 1.x-E3 | `ADR-CR-EXT-V4-V6ONLY-POOL-FALLTHROUGH`         |
| REQ-RESOLVE-03                 | 1.x-D3, 1.x-E3 | `ADR-CR-EXT-DUAL-STACK-RESOLVE-V4-V6-OK`        |
| REQ-RESOLVE-04                 | 1.x-D4, 1.x-E3 | `IPL-EXPLAIN-FAMILY-V6-FALLTHROUGH`             |
| REQ-RESOLVE-05                 | 1.x-D5, 1.x-E3 | `IPL-RESOLVE-SELECTOR-FAMILY-SKIP`              |
| REQ-RESOLVE-06                 | 1.x-D6         | `IPL-RESOLVE-OVERRIDE-FAMILY-SKIP`              |
| REQ-RESOLVE-07                 | 1.x-D7         | `IPL-RESOLVE-NETWORK-DEFAULT-FAMILY-SKIP`       |
| REQ-UI-IPL-01..04              | 1.x-F1..F4     | (manual UI smoke)                               |
| REQ-SMOKE-01                   | 1.x-G1         | (curl smoke)                                    |
| REQ-SMOKE-02                   | 1.x-G2         | (`run.sh` aggregate)                            |
| REQ-IPL-INVARIANT-01..03       | 1.x-H1..H3     | (integration concurrent-tests)                  |

---

## 10. Definition of Done

PR-серия в репозиториях (порядок merge — топологический, см. workspace `CLAUDE.md` §«Кросс-репо зависимости»):

1. **`kacho-proto`** — proto-рефактор (KAC-71):
   - `kacho-proto/proto/kacho/cloud/vpc/v1/internal_address_pool_service.proto`:
     - `AddressPool`: `reserved 7; reserved "cidr_blocks";` + `repeated string v4_cidr_blocks = 13;` + `repeated string v6_cidr_blocks = 14;`
     - `CreateAddressPoolRequest`: `reserved 5; reserved "cidr_blocks";` + `v4_cidr_blocks=11`, `v6_cidr_blocks=12`
     - `UpdateAddressPoolRequest`: `reserved 6; reserved "cidr_blocks";` + `v4_cidr_blocks=13`, `v6_cidr_blocks=14` + флаги `replace_v4_cidr_blocks=15`, `replace_v6_cidr_blocks=16`
   - `make proto` регенерит stubs; `gen/go/kacho/cloud/vpc/v1/*.pb.go` коммитятся
   - `buf lint` зелёный (REQ-IPL-PROTO-01)
   - `buf breaking` ожидаемо красный против baseline (REQ-IPL-PROTO-02) — explicit-override в PR

2. **`kacho-vpc`** — миграция + service + handler + tests:
   - `internal/migrations/0022_address_pool_split_cidr_family.sql` — `ADD COLUMN v4_cidr_blocks/v6_cidr_blocks IF NOT EXISTS` + backfill `DO $$ ... $$;` (с **defensive `RAISE EXCEPTION` на пустой `cidr_blocks`** — REQ-MIG-06 / C6, SQLSTATE `P0001`) + `DROP COLUMN cidr_blocks IF EXISTS` (REQ-MIG-01..06)
   - `internal/domain/address_pool.go` — поля `V4CIDRBlocks []string`, `V6CIDRBlocks []string` вместо `CIDRBlocks`
   - `internal/repo/address_pool_repo.go` — обновлённый `addressPoolCols`, INSERT/UPDATE/SELECT
   - `internal/service/address_pool_service.go`:
     - `Create` validate split-shape (REQ-IPL-CR-04..06)
     - `Update` обработка `replace_v4_cidr_blocks` / `replace_v6_cidr_blocks` как **единственного триггера replace** — body-значение CIDR-полей игнорируется при отсутствии флага (REQ-IPL-UPD-01..03, REQ-IPL-UPD-05, REQ-IPL-UPD-06)
     - `Update` check `v4_cidr_blocks` replace vs allocated IP (REQ-IPL-UPD-04)
     - `doResolve` / `poolHasFamily` — заменить на `len(pool.V4CIDRBlocks)>0` / `len(pool.V6CIDRBlocks)>0` (REQ-RESOLVE-01..07) — family-фильтр применяется единообразно на **всех 5 шагах** cascade (Step 1 address_override, Step 2 network_default, Step 3 label_selector, Step 4 zone_default, Step 5 global_default)
   - `internal/service/address.go::AllocateExternalIPv4/v6` — брать family-specific блоки напрямую из domain-модели
   - `internal/handler/internal_address_pool_handler.go`:
     - обновлённый mapper proto ↔ domain
     - **`ExplainResolution` handler ловит `ErrPoolNotResolved` отдельно от `mapPoolErr` и возвращает `ExplainResolutionResponse{ MatchedVia: "none" }` с gRPC OK** (а НЕ `FailedPrecondition` через `mapPoolErr`, как сейчас). Это изменение поведения только для `ExplainResolution` — `Allocate*` методы продолжают возвращать `FailedPrecondition` при `ErrPoolNotResolved` (REQ-RESOLVE-04 / D4).
   - `internal/service/network_service.go` (Bind*-RPC) / `internal_address_pool_handler.go` (Override*-RPC) — НЕ добавлять family-validation. Family-фильтр работает только на resolve-этапе (REQ-IPL-BIND-FAMILY-AGNOSTIC / B13).
   - `internal/repo/address_pool_repo_integration_test.go` — обновлённые тесты (новый `TestRepo_SplitCidrFamilies`)
   - `internal/repo/migration_0022_integration_test.go` (новый) — REQ-MIG-01..06 (включая C6: defensive `RAISE EXCEPTION` на pool с empty `cidr_blocks`)
   - `internal/repo/ipam_cascade_integration_test.go` — расширение `TestCascade_SplitFamily*` (REQ-RESOLVE-01..07)
   - `internal/repo/concurrent_ipam_integration_test.go` (новый или расширение) — REQ-IPL-INVARIANT-01..03 (concurrent goroutines на partial UNIQUE)
   - `tests/newman/cases/internal-pool.py` + `address.py` — обновлённые/новые case'ы (см. §5; **+18 net new кейсов**, точная таблица в §7 G2)
   - `tests/newman/docs/CASES-INDEX.md` — записи новых паттернов
   - `tests/newman/docs/PRODUCT-REQUIREMENTS.md` — REQ-IPL-PROTO-01..03, REQ-IPL-CR-01..06, REQ-IPL-UPD-01..06, REQ-IPL-BIND-FAMILY-AGNOSTIC, REQ-MIG-01..06, REQ-RESOLVE-01..07, REQ-IPL-INVARIANT-01..03, REQ-UI-IPL-01..04, REQ-SMOKE-01..02
   - `tests/newman/docs/RESULTS.md` — новая версия
   - `python3 tests/newman/scripts/gen.py` и `validate-cases.py` зелёные
   - `make test` (unit + integration testcontainers) зелёный
   - `tests/newman/scripts/run.sh --service internal-pool` + `--service address` зелёные

3. **`kacho-ui`** — UI-форма + list:
   - `src/lib/resource-registry.tsx` — spec `address-pools`:
     - `columns`: две колонки IPv4/IPv6 на `v4_cidr_blocks`/`v6_cidr_blocks` (REQ-UI-IPL-03)
     - `fields`: два array-блока с `<SubnetCidrChips>`-стилем (REQ-UI-IPL-01)
     - `template`: `{ v4_cidr_blocks: [], v6_cidr_blocks: [] }`
     - `sanitize`: маппит UI-shape → wire (snake-case), фильтрует пустые
     - `hydrate`: читает `v4_cidr_blocks` / `v6_cidr_blocks` из API
   - `src/components/InlineAddressPoolCreateForm.tsx` / `InlineAddressPoolEditForm.tsx` — переиспользует `<SubnetCidrChips>` (REQ-UI-IPL-01..02)
   - `src/components/form/RefSelect.tsx` — `extraInfoFor.address-pools` (REQ-UI-IPL-03)
   - `npm run build` + `npx tsc --noEmit` зелёные
   - Manual smoke по F1-F4

4. **`kacho-workspace`** — этот acceptance-документ:
   - `docs/specs/sub-phase-1.x-addresspool-split-cidr-family-acceptance.md` (этот файл) — статус APPROVED (выставляет `acceptance-reviewer`)
   - Apдейт `docs/specs/04-roadmap-and-phasing.md` если необходимо (не обязательно, sub-phase 1.x — ad-hoc)

5. **`kacho-deploy`** — e2e smoke:
   - `e2e/1.x-addresspool-cidr-split/G1-curl-split-crud.sh` (REQ-SMOKE-01)
   - `e2e/1.x-addresspool-cidr-split/G2-newman-regression.sh` (REQ-SMOKE-02, обёртка над `run.sh`)

6. **YouTrack**:
   - `KAC-71` переведён `To do → In Progress` при старте кодинга после APPROVED acceptance-документа
   - Все PR-ссылки приклеены комментарием к `KAC-71`
   - Тикет → `Test` после CI зелёного по всем 4 репо
   - Тикет → `Done` после ручного smoke от заказчика на стенде + комментарий-артефакт со ссылками на: (a) merged PR'ы по каждому репо, (b) `RESULTS.md` newman, (c) лог `G1-curl-split-crud.sh`, (d) скриншоты UI F1-F4

7. **Git-флоу:**
   - Ветка `KAC-71` в каждом из 4 затронутых репо
   - Conventional commits (`feat(vpc):`, `feat(proto):`, `feat(ui):`, `chore(deploy):`, `docs(workspace):`)
   - Закрытие веток через `gh pr merge --delete-branch` после merge (workspace `CLAUDE.md` §«документооборот»)

---

## 11. Открытые вопросы / решения, которые принимает `acceptance-reviewer`

**Нет открытых вопросов после round 2 ревью.** Все ранее открытые пункты закрыты явными решениями:

1. **Re-apply миграции `0022`** — фиксировано: `ADD COLUMN IF NOT EXISTS` + `DROP COLUMN IF EXISTS` + backfill в `DO $$ ... $$;` с проверкой `information_schema.columns` (REQ-MIG-05 / C5). Defensive, разрешено reviewer'ом.
2. **`ExplainResolution` поведение при fall-through** — фиксировано: **HTTP 200 + `matched_via="none"` + пустой `selected_pool`**. Это требует изменения кода (`internal_address_pool_handler.go::ExplainResolution` ловит `ErrPoolNotResolved` отдельно до `mapPoolErr`). См. D4 / REQ-RESOLVE-04 / DoD §10 п.2 «handler change».
3. **`UpdateAddressPoolRequest.replace_v4_cidr_blocks` / `_v6_`** — фиксировано: **два независимых булевых флага** (field tags 15, 16), reviewer approve. Альтернатива (один enum `BOTH/V4/V6`) отвергнута.
4. **Backfill при empty `cidr_blocks`** — фиксировано как **REQ-MIG-06 + C6**: миграция падает с PG `RAISE EXCEPTION 'address_pool % has empty cidr_blocks'` (SQLSTATE `P0001`), транзакция rollback'ается, оператор fix'ит data, ретрайит. Defensive, не data-loss.
5. **`kacho-yc-shim` compat-слой** — out of scope KAC-71. Verbatim-YC parity отложена (workspace `CLAUDE.md` §«Что это за проект»). Зафиксировано в §12.

---

## 12. Что НЕ покрыто (scope-чек reviewer'ом)

- `:add-v4-cidr-blocks` / `:remove-v4-cidr-blocks` / симметрично для v6 — дельта-методы. Сейчас Update — full-replace. Если в будущем потребуется — отдельный тикет.
- IPv6 prefix > /64 (single-host /128 / fine-grained sub-allocs) — текущий sparse-counter allocator (`ipv6_pool_cursors`) ориентирован на /64 broadcast-blocks, не на под-аллокации. Этот acceptance НЕ меняет allocator-алгоритмы.
- **Cross-repo migration coordination для `kacho-yc-shim`** — **out of scope для KAC-71**. Verbatim-YC parity отложена (workspace `CLAUDE.md` §«Что это за проект»); compat-shim (если он понадобится для legacy `cidr_blocks` API-shape под yc-CLI) — отдельная поздняя фаза, не constraint на этот тикет.
- Multi-region pool (`zone_id=""` + регион-фильтр) — текущая семантика «empty zone == global default» сохраняется без изменений; family-split её не трогает.
- Перенос Geography (Region/Zone) из `kacho-vpc` в `kacho-compute` (эпик `KAC-15`) — не зависит от этого тикета и идёт параллельно.
- **Delete AddressPool RPC** (`InternalAddressPoolService.Delete`) — family-semantics для Delete не вводится: Delete просто удаляет pool по id вместе со всеми binding'ами и freelist-rows через FK CASCADE / RESTRICT (по существующим constraint'ам). Миграция `0022` его не трогает. Покрытие — существующий newman case `IPL-DEL-OK` (без изменений; работает по-прежнему, потому что Delete не читает `cidr_blocks` / `v4_cidr_blocks` / `v6_cidr_blocks`).
- **Full clean `ipv6_pool_cursors` при replace v6_cidr_blocks** (KAC-60 «освобождённые offset'ы при replace»). На текущий момент `cursor.next_offset` сбрасывается на 1, но released-offset bookkeeping (`ipv6_released_offsets`) при replace не cleanup'ится — может остаться мусор от прежнего CIDR. Это **out of scope KAC-71**: семантика unchanged от текущего поведения; отдельный issue если потребуется аудит released-offsets.
- **Family-validation на Bind\* / Override\* / SetPoolSelector RPC** — НЕ вводится. Bind/Override/SetSelector — family-agnostic; family-фильтр работает **только на resolve-этапе** (Steps 1-5 cascade). См. B13 / REQ-IPL-BIND-FAMILY-AGNOSTIC / D6 / D7. Альтернатива (validate family at bind-time) отвергнута — это противоречит идее «можно пре-бинднуть pool под будущее использование, а filter — на runtime».

---

## 13. Чеклист для acceptance-reviewer'а

- [ ] Coverage всех публичных RPC `InternalAddressPoolService` после рефактора (Create, Update, Get, List, Delete, ExplainResolution, Check) — есть либо как явный сценарий, либо как «не меняется» в §12 «НЕ покрыто» (Delete — зафиксирован)
- [ ] Coverage IPAM cascade (5 шагов из `kacho-vpc/CLAUDE.md` §16.2) для family-фильтра — D1..D7 покрывают Step 1 (address_override → D6), Step 2 (network_default → D7), Step 3 (label_selector → D5), Step 4 (zone_default → D1, D2, D3), Step 5 (global_default → D1, D2)
- [ ] Coverage Bind*/Override*/SetPoolSelector* — family-agnostic (B13 + §12 зафиксировано)
- [ ] Negative-сценарии достаточно вариативны: B4/B5/B6/B9 + H1/H2/H3 — оба-empty / cross-family / host-bits / clear-both / UNIQUE-races. + B12 (no-flags no-op) + C6 (defensive migration failure)
- [ ] Update full-replace семантика детерминирована (явный bool-флаг — единственный триггер); §0 + B7/B8/B11/B12 покрывают все 4 комбинации (replace+непустой / replace+пустой / no-replace+непустой / no-replace+пустой)
- [ ] `ExplainResolution` поведение на fall-through зафиксировано (HTTP 200 + matched_via=none); код-изменение в DoD §10 п.2
- [ ] Идемпотентность миграции — REQ-MIG-02/05 покрывают
- [ ] Backfill data-loss-prevention — REQ-MIG-01/03 + REQ-MIG-06 (defensive RAISE EXCEPTION) — C6
- [ ] Каждый сценарий имеет конкретный payload и конкретный ожидаемый код / тело ответа (verifiable)
- [ ] Каждый REQ-* линкуется на конкретный newman case-id или явно помечается «N/A» (proto / migration / UI smoke) — см. §9 таблицу
- [ ] Все запреты workspace `CLAUDE.md` соблюдены: #1 (acceptance до кода — этот документ есть), #2 (никакого «yandex» — в тексте только обоснованные «verbatim YC» как ссылки на исторический контекст; новых упоминаний нет), #3 (ORM не вводится — продолжаем sqlc + pgx), #5 (миграция — новый файл `0022`), #6 (admin-RPC на internal mux, не на external TLS), #8 (никакого cross-DB FK), #10 (within-service refs — DB-уровень — UNIQUE-индексы сохранены, partial UNIQUE на `(zone_id, kind) WHERE is_default` — сохранён), #11 (тесты в том же PR — DoD §10 явно требует integration + newman зелёными)
- [ ] Cross-repo порядок merge явно зафиксирован в §10 (kacho-proto → kacho-vpc → kacho-ui → kacho-deploy → kacho-workspace docs)
- [ ] YouTrack workflow явно описан (§10 п.6)
- [ ] §11 «Открытые вопросы» — пуст / зафиксированы решения round 2
