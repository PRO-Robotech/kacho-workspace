# Sub-phase 6.0 (kacho-geo extraction) — Acceptance

> Статус: ✅ APPROVED (acceptance-reviewer, round 2 — все round-1 замечания закрыты, сверены с ground-truth)
> Дата: 2026-06-17
> Ревьюер: acceptance-reviewer
> Эпик/тикет: KAC-<N> `[EPIC]` (создать; major 6 — новый epic-anchor)

| | |
|---|---|
| Эпик | extract Geography (Region/Zone) из `kacho-compute` в новый leaf-service **`kacho-geo`** |
| Этот док | acceptance-author; APPROVE — acceptance-reviewer (gate перед любым кодом, ban #1) |
| Решение | принято владельцем: Region/Zone — это platform topology (leaf-primitive, как IAM), а не compute-абстракция |
| Граф ДО | `compute → self` (Instance.zone_id), `vpc → compute` (zone-validate), `nlb → compute` (region-validate) — три ложных ребра «ради geography» |
| Граф ПОСЛЕ | `compute → geo`, `vpc → geo`, `nlb → geo`, `api-gateway → geo`; **`geo → ничего`** (leaf, как iam). Семантически-неверные рёбра `vpc→compute` / `nlb→compute` «ради geography» удалены |

## Обзор

Region/Zone сегодня живут в `kacho-compute` (proto `kacho.cloud.compute.v1`: `Region`/`Zone` + `RegionService`/`ZoneService` public read-only + `InternalRegionService`/`InternalZoneService` admin-CRUD на :9091; схема `kacho_compute` — таблицы `regions`/`zones`, миграции `0001`/`0003`). Это сделало `kacho-compute` зависимостью трёх consumer'ов исключительно ради geography. Данный эпик выделяет Geography в новый отдельный leaf-сервис **`kacho-geo`** (домен `kacho.cloud.geo.v1`, схема `kacho_geo`, репо `github.com/PRO-Robotech/kacho-geo` — уже создан, пустой, private), переключает `compute`/`vpc`/`nlb`/`api-gateway` на него и удаляет geography из `compute.v1`. Результат — ацикличный граф `all → geo`, где `geo` ни от кого внутри проекта не зависит, а ложные рёбра «ради geography» исчезают.

Конвенции контракта нормативны и здесь не дублируются: `.claude/rules/api-conventions.md` (flat-resource + Operations, Get/List sync, REST-пути, error-format), `.claude/rules/data-integrity.md` (один владелец на тип ресурса, cross-domain ref по id+API без cross-service FK, dangling-ref грациозно, fail-closed на мутациях), `.claude/rules/security.md` (Internal* только :9091; authN+authZ на каждом RPC обоих листенеров; admin-tier = `system_admin`, read floor = `system_viewer`), `.claude/rules/polyrepo.md` (build-граф, кросс-репо порядок, CI-pinning), `.claude/rules/00-kacho-core.md` (naming, ban-list).

### Сохраняемая форма ресурсов (ground-truth — не менять)

Перенос — **lift-and-shift формы**, поля и id сохраняются один-в-один (иначе сломаются существующие `Instance.zone_id`, `Subnet.zone_id`, `address_pools.zone_id`, NLB `region_id`):

- `Region`: `id` (TEXT PK, admin-assigned, immutable, напр. `"ru-central1"`), `name`, `created_at`.
- `Zone`: `id` (TEXT PK, admin-assigned, immutable, напр. `"ru-central1-a"`), `region_id` (FK → Region.id, `ON DELETE RESTRICT`), `status` (enum `STATUS_UNSPECIFIED|UP|DOWN`), `name`, `created_at`.
- `RegionService` / `ZoneService`: `Get`/`List` — **sync** (read-only).
- `InternalRegionService` / `InternalZoneService`: `Create`/`Update`/`Delete` — admin-managed catalog, возвращают **ресурс синхронно** (НЕ `Operation`). Это установленный catalog-паттерн (`InternalDiskTypeService` — тот же стиль), сохраняется намеренно; общий принцип «мутации → Operation» к admin-only reference-каталогам Region/Zone не применяется. Реестр (id admin задаёт явно), не tenant-ресурс.
- Geography НЕ привязан к Project/Account — это глобальная platform-топология (scope `cluster`, как сейчас).

> **Scope deviation (зафиксировать в reviewer-checklist):** admin-CRUD Region/Zone остаётся синхронным (не `Operation`) — соответствует текущему compute-поведению и `InternalDiskTypeService`. Менять семантику в рамках чистого extract нельзя.

---

## Декомпозиция эпика (стадии в порядке build-графа)

Каждая стадия — самостоятельный mergeable-юнит со своим DoD. Порядок строго по `polyrepo.md`: **proto → kacho-geo (service+schema) → data-migration → consumers (compute/vpc/nlb) → api-gateway → deploy → workspace/docs**. Пока вышестоящее не в `main`, нижестоящий CI временно пиннит sibling-`ref:` на feature-ветку, после merge — `ref: main`.

| Стадия | Репо | Что | Блокирует |
|---|---|---|---|
| **S1** | `kacho-proto` | новый домен `kacho.cloud.geo.v1` (Region/Zone + 4 сервиса); план breaking-removal `compute.v1` geography | S2–S6 |
| **S2** | `kacho-geo` | clean-arch скелет (leaf) + схема `kacho_geo` + handlers + mTLS internal + per-RPC authz + audit-outbox | S3, S4 |
| **S3** | `kacho-geo` / `kacho-deploy` | data-migration: перенос строк `regions`/`zones` из `kacho_compute` → `kacho_geo` с сохранением id (dev + fe3455) | S4 |
| **S4** | `kacho-compute`, `kacho-vpc`, `kacho-nlb` | переключение consumer'ов на `geo` (typed `geo_client.go`); удаление geography из compute | S5 |
| **S5** | `kacho-api-gateway` | перерегистрация Region/Zone REST → geo backend; permission_catalog → geo FQN; Internal* на internal mux | S6 |
| **S6** | `kacho-deploy` | sub-chart `kacho-geo` + pg-geo DB + migration-job + mTLS cert (SEC-F) + values.dev/prod/fe3455 | S7 |
| **S7** | `kacho-proto` (финал) | удалить geography из `compute.v1` (`buf breaking` — намеренный, ПОСЛЕ перевода всех consumer'ов) | S8 |
| **S8** | `kacho-workspace` | docs/specs + vault (resources/rpc/packages/edges) + polyrepo build-graph + owner-map + bootstrap.sh + sync-tooling.sh | — |

> **Важно про порядок S7 (см. «Cutover/back-compat»):** удаление geography из `compute.v1` (S7) выполняется **последним**, ПОСЛЕ того как `kacho-geo` развёрнут, данные мигрированы и все consumer'ы переключены на geo. Это исключает окно недоступности Region/Zone.

---

## Cutover / back-compat strategy (как избежать окна недоступности)

Riskiest: (a) breaking-change `compute.v1` proto, (b) live data-migration на работающих стендах, (c) порядок cutover. De-risk — **expand → migrate → switch → contract** (никакого «удалили старое до появления нового»):

1. **Expand.** `kacho.cloud.geo.v1` добавляется в `kacho-proto` БЕЗ удаления `compute.v1` geography (S1). На этом шаге `buf breaking` зелёный — только additive.
2. **Stand up geo.** `kacho-geo` развёрнут на стенде (S2/S6), отвечает на Get/List/admin-CRUD, но ещё **никто его не зовёт** в продакшн-пути.
3. **Migrate data.** Строки `regions`/`zones` перенесены `kacho_compute` → `kacho_geo` с сохранением id (S3). До переключения consumer'ов оба источника содержат одинаковые данные (dual-read-safe window): и `compute.v1.ZoneService`, и `geo.v1.ZoneService` отдают совпадающие ответы.
4. **Switch consumers.** compute/vpc/nlb/api-gateway переключаются на `geo` (S4/S5). После деплоя ни один продакшн-вызов не идёт в `compute.v1` Region/Zone.
5. **Contract.** Только теперь (S7) geography удаляется из `compute.v1` (`buf breaking`, намеренный) и из схемы/кода compute. Окна недоступности нет: на каждом шаге Region/Zone доступны хотя бы из одного источника, а в момент 4→5 — уже только из geo.

**Rollback на каждом шаге:** до S7 откат тривиален (consumer-флаг/конфиг переключается обратно на `compute.v1`, данные в `kacho_compute` ещё на месте). После S7 откат = revert proto/compute PR (данные в `kacho_geo` остаются source of truth).

---

## S1 — proto-домен `kacho.cloud.geo.v1`

### Scenario 6.0-01: новый домен geo.v1 присутствует, форма сохранена
**Given** `kacho-proto` собран, `gen/` закоммичен
**When** инспектировать `proto/kacho/cloud/geo/v1/`
**Then** существуют `region.proto`, `zone.proto`, `region_service.proto`, `zone_service.proto`, `internal_catalog_service.proto` в пакете `kacho.cloud.geo.v1` с `go_package … /geo/v1;geov1`
**And** `Region` имеет поля `id, name, created_at`; `Zone` — `id, region_id, status (enum UP/DOWN/UNSPECIFIED), name, created_at` (форма идентична прежней `compute.v1`)
**And** `RegionService.Get/List` и `ZoneService.Get/List` — **sync** (возвращают ресурс / ListResponse, не `Operation`)
**And** `InternalRegionService` и `InternalZoneService` несут `Create/Update/Delete`, возвращают ресурс синхронно
**And** authz-аннотации перенесены: read-RPC `required_relation="viewer"` (system_viewer-floor), admin-RPC `required_relation="system_admin"`, `scope_extractor.object_type="cluster"`; permission-строки переименованы в `geo.*` FQN-домен (напр. `geo.regions.get`, `geo.zones.create`)
**And** **намеренно** исправлена опечатка из `compute.v1`: List-permission'ы были `compute.regionses.list` / `compute.zoneses.list` (двойное «es») — в `geo.v1` это `geo.regions.list` / `geo.zones.list` (extract — удобный момент фикса; не слепой rename). Соответствующие permission_catalog FQN в api-gateway (S5) и любые seed-tuples обновляются на исправленные строки

### Scenario 6.0-02: additive-only на этом шаге (back-compat preserved)
**Given** Scenario 6.0-01
**When** прогон `buf lint` и `buf breaking` против предыдущего commit
**Then** `buf lint` зелёный
**And** `buf breaking` зелёный — на S1 geography из `compute.v1` ещё НЕ удалена (удаление отложено в S7); добавление `geo.v1` — чисто additive
**And** REST `google.api.http`-аннотации в `geo.v1` ведут на geo-пути (см. S5 для финального решения по путям)

---

## S2 — сервис `kacho-geo` (новый leaf-репо)

### Scenario 6.0-03: clean-arch скелет, leaf-зависимости
**Given** репо `github.com/PRO-Robotech/kacho-geo` (был пустой)
**When** инспектировать структуру и `go.mod`
**Then** присутствуют `cmd/geo/main.go` (composition root), `cmd/migrator/`, `internal/{domain,service|apps,repo,clients,handler,config}`, `internal/migrations/`, `deploy/`, `Dockerfile`, `Makefile`, `.github/workflows/ci.yaml`
**And** `go.mod` содержит **только** `replace ../kacho-corelib` и `replace ../kacho-proto` (leaf: НЕ зависит от iam/vpc/compute/nlb по build — как iam)
**And** `domain/` импортирует только stdlib + `kacho-proto`; use-case не импортирует pgx/grpc-stubs (clean-arch dependency rule)

### Scenario 6.0-04: схема `kacho_geo` (regions/zones перенесены 1-в-1)
**Given** `kacho-geo` мигрирован (`cmd/migrator` против чистой БД)
**When** инспектировать схему `kacho_geo`
**Then** таблица `regions(id TEXT PK, name TEXT, created_at TIMESTAMPTZ)` и `zones(id TEXT PK, region_id TEXT NOT NULL, status TEXT, name TEXT, created_at TIMESTAMPTZ)`
**And** `zones.region_id` имеет FK на `regions(id) ON DELETE RESTRICT` (региона с зонами удалить нельзя — within-service инвариант на DB-уровне, ban #10)
**And** seed-строки `ru-central1` и `ru-central1-{a,b,d}` (status `UP`) присутствуют, вставлены миграцией geo (зеркалит compute `0001`/`0003`, идемпотентно через `ON CONFLICT DO NOTHING`/`DO UPDATE`)
**And** присутствует `geo_outbox`-таблица (audit на admin-мутациях; имя по конвенции `<domain>_outbox` — parity с `compute_outbox`/`vpc_outbox`)

### Scenario 6.0-05: public Region/Zone Get/List (happy)
**Given** `kacho-geo` развёрнут, миграция применена
**When** клиент вызывает `geo.v1.RegionService.List` (page_size=50)
**Then** возвращается `ListRegionsResponse` с регионом `ru-central1` (`name`, `createdAt` заполнены), gRPC `OK`
**And** `geo.v1.ZoneService.List` с `region_id=ru-central1` → 3 зоны `ru-central1-{a,b,d}` со `status=UP`
**And** `geo.v1.ZoneService.Get(zone_id="ru-central1-a")` → зона со `status=UP`, `regionId=ru-central1`

### Scenario 6.0-06: public Get — not found / malformed (negative)
**Given** `kacho-geo` развёрнут
**When** `geo.v1.ZoneService.Get(zone_id="no-such-zone")` (well-formed-но-нет)
**Then** gRPC `NOT_FOUND`, сообщение в стабильном тоне (`"Zone no-such-zone not found"` / эквивалент по `api-conventions.md`)
**And** `geo.v1.RegionService.Get(region_id="")` → `INVALID_ARGUMENT` (required-валидация payload первым стейтментом RPC)

### Scenario 6.0-07: admin-CRUD через Internal*, authz-gated (happy + precondition)
**Given** `kacho-geo` развёрнут; вызов идёт на cluster-internal listener (:9091) под admin-identity с `system_admin`
**When** `geo.v1.InternalRegionService.Create {id:"eu-west1", name:"EU West 1"}`
**Then** создаётся регион, ответ — `Region{id:"eu-west1", ...}` синхронно, gRPC `OK`
**And** `geo.v1.InternalZoneService.Create {id:"eu-west1-a", region_id:"eu-west1", status:UP, name:"EU West 1 A"}` → создаёт зону
**And** `geo.v1.InternalRegionService.Delete(region_id="eu-west1")` пока есть зона `eu-west1-a` → `FAILED_PRECONDITION` (FK RESTRICT, маппинг SQLSTATE 23503)
**And** после `InternalZoneService.Delete(zone_id="eu-west1-a")` — `InternalRegionService.Delete(region_id="eu-west1")` → `OK`
**And** `InternalZoneService.Create {id:"x", region_id:"no-such-region", ...}` → `FAILED_PRECONDITION` (FK violation на несуществующий регион)
**And** admin-мутация записывает строку в `geo_outbox` (в той же транзакции)

### Scenario 6.0-08: authz-инвариант на internal-листенере (security.md)
**Given** `kacho-geo` развёрнут с public (:9090) и internal (:9091) листенерами
**When** на internal-листенер приходит запрос без валидного client-cert (mTLS) ИЛИ без `system_admin`-tuple
**Then** mTLS-провал → транспортный отказ; аутентифицированный-но-без-прав → `PERMISSION_DENIED` (per-RPC `InternalIAMService.Check` энфорсится в цепочке интерсепторов обоих листенеров — internal НЕ освобождён, ban-инвариант `security.md`)
**And** read-RPC (`RegionService.Get/List`, `ZoneService.Get/List`) гейтятся viewer-tier (`system_viewer`-floor); admin-RPC — `system_admin`
**And** `Internal*Service` методы НЕ маршрутизируются на external TLS endpoint — только :9091 (ban #6)

---

## S3 — data-migration (live стенды, критично)

### Scenario 6.0-09: перенос строк с сохранением id (export/import)
**Given** работающий стенд, где `kacho_compute.regions`/`kacho_compute.zones` содержат seed-строки + (возможно) admin-добавленные через `InternalRegionService`/`InternalZoneService`
**When** выполнить data-migration job (idempotent export из `kacho_compute` → import в `kacho_geo`, либо idempotent seed + reconcile)
**Then** каждая строка `regions`/`zones` из `kacho_compute` присутствует в `kacho_geo` с **тем же `id`**, `region_id`, `status`, `name`, `created_at` (created_at сохраняется, не перезаписывается `now()`)
**And** повторный прогон job не создаёт дублей и не падает (idempotent — `ON CONFLICT`)
**And** строки, которые есть в seed обеих сторон (`ru-central1`, `ru-central1-{a,b,d}`), совпадают по содержимому (нет конфликта seed-vs-import)
**And** процедура задокументирована (export/import-скрипт ИЛИ one-time migration-job ИЛИ idempotent reconcile) с явным указанием, какой механизм выбран и почему

### Scenario 6.0-10: dual-read window — geo и compute отдают одинаковые данные (cutover-safety)
**Given** Scenario 6.0-09 выполнен, но consumer'ы ЕЩЁ не переключены (S4 не задеплоен)
**When** запросить `geo.v1.ZoneService.Get("ru-central1-a")` и (старый) `compute.v1.ZoneService.Get("ru-central1-a")`
**Then** оба возвращают зону с идентичными `id/region_id/status/name`
**And** это окно безопасно: переключение consumer'ов (S4) не приводит к расхождению zone/region-данных

### Scenario 6.0-11: существующие ссылки переживают cutover (NEGATIVE — критично)
**Given** на стенде есть `Instance` с `zone_id="ru-central1-a"`, `Subnet` с `zone_id="ru-central1-a"`, `address_pool` с `zone_id`, NLB с `region_id="ru-central1"` (созданы ДО миграции)
**When** выполнен полный cutover (S3 migrate + S4 switch + S7 contract)
**Then** `compute.v1.InstanceService.Get` существующего инстанса → `OK`, `zoneId="ru-central1-a"` (ссылка валидна — id сохранён)
**And** `vpc.v1.SubnetService.Get` существующей подсети → `OK`, `zoneId` валиден
**And** `nlb.v1.…Get` существующего LB → `OK`, `regionId` валиден
**And** ни один из этих read'ов не падает 500/паникой (dangling-ref не возникает, т.к. id перенесены 1-в-1)
**And** валидация выполнена на dev И на fe3455 стендах (см. DoD)

---

## S4 — переключение consumer'ов на geo

### Scenario 6.0-12: compute валидирует Instance.zone_id через geo (не self)
**Given** compute переключён на geo; geo развёрнут с зоной `ru-central1-a`
**When** `compute.v1.InstanceService.Create {zone_id:"ru-central1-a", ...}`
**Then** compute вызывает `geo.v1.ZoneService.Get("ru-central1-a")` (через `internal/clients/geo_client.go`), зона есть → Create возвращает `Operation`; полл `OperationService.Get(id)` до `done=true && !error`; затем `InstanceService.Get` отдаёт инстанс с `zoneId="ru-central1-a"`
**And** `compute.v1.InstanceService.Create {zone_id:"no-such-zone"}` → `INVALID_ARGUMENT` (compute спросил geo → `NOT_FOUND` → маппинг в `INVALID_ARGUMENT`, тон `"zone_id: zone no-such-zone not found"` / эквивалент)
**And** в коде `kacho-compute` НЕ осталось локальной валидации zone по собственной таблице (`ZoneRepoSource`/`ZoneRegistry` теперь бьёт в geo-client); compute больше не «владеет» зонами

### Scenario 6.0-13: vpc валидирует Subnet.zone_id через geo (ребро vpc→geo)
**Given** vpc переключён на geo
**When** `vpc.v1.SubnetService.Create {zone_id:"ru-central1-a", ...}`
**Then** vpc вызывает `geo.v1.ZoneService.Get` (через `internal/clients/geo_client.go`), зона есть → `Operation` → done → `Get` отдаёт подсеть с `zoneId`
**And** `vpc.v1.SubnetService.Create {zone_id:"no-such-zone"}` → `INVALID_ARGUMENT`
**And** `AddressPool` — zonal-ресурс (`address_pools.zone_id`, `empty = global default`; есть `address_pools_zone_idx`): `vpc.v1.AddressPoolService.Create {zone_id:"ru-central1-a"}` валидирует `zone_id` через geo → ok; несуществующая зона → `INVALID_ARGUMENT`; `zone_id=""` (global) → ok без geo-вызова
**And** существующие `address_pools` со `zone_id` переживают cutover: `vpc.v1.AddressPoolService.Get` ранее созданного zonal-пула → `OK`, `zoneId` валиден (id зоны сохранён миграцией, 6.0-09); а если зона позже удалена админом в geo — `Get` пула не падает (dangling-ref грациозно, по аналогии с 6.0-16)
**And** в `kacho-vpc` `internal/clients/compute_client.go` больше не содержит `GetZone`/`ListZones`; geo-валидация (Subnet + AddressPool) — в `geo_client.go`; ребро `vpc→compute` «ради zone» удалено

### Scenario 6.0-14: nlb валидирует region_id через geo (ребро nlb→geo)
**Given** nlb переключён на geo
**When** `nlb.v1` LoadBalancer.Create / TargetGroup.Create `{region_id:"ru-central1", ...}`
**Then** nlb вызывает `geo.v1.RegionService.Get("ru-central1")` (sync precheck на request-path, как сейчас — stateless pass-through через `retry.OnUnavailable`, **кэша нет**; вводить кэш — вне scope этого extract) → ok
**And** с `region_id="no-such-region"` → `INVALID_ARGUMENT`
**And** в `kacho-nlb` `internal/clients/compute/region_client.go` заменён на `internal/clients/geo/region_client.go` (вызывает `geo.v1.RegionService`); ребро `nlb→compute` «ради region» удалено (ребро `nlb→compute` для `InstanceService`/instance-resolve остаётся — это НЕ geography)

### Scenario 6.0-15: fail-closed при недоступности geo (NEGATIVE — мутации)
**Given** consumer'ы переключены на geo; `kacho-geo` остановлен
**When** `vpc.v1.SubnetService.Create {zone_id:"ru-central1-a"}` (мутация, требующая zone-валидации)
**Then** → `UNAVAILABLE` (consumer не смог провалидировать zone — fail-closed на мутации, `data-integrity.md` §cross-domain)
**And** `compute.v1.InstanceService.Create {zone_id:...}` при geo-down → `UNAVAILABLE`
**And** `nlb` LoadBalancer.Create при geo-down → `UNAVAILABLE`
**And** ПРИ ЭТОМ `vpc.v1.SubnetService.Get` / `compute.v1.InstanceService.Get` существующих ресурсов → `OK` (чтение уже сохранённых данных не перепроверяет zone в geo — dangling-ref переживается грациозно)

### Scenario 6.0-16: dangling-ref на чтении переживается (NEGATIVE)
**Given** есть `Subnet S` с `zone_id="ru-central1-d"`; admin удаляет зону `ru-central1-d` в geo (предположим, без geo-side dependents — geo не знает consumer'ов, нет cross-service cascade)
**When** `vpc.v1.SubnetService.Get(S)`
**Then** → `OK` (200), `zoneId` остаётся `"ru-central1-d"`; НЕ 500, НЕ паника (consumer грациозно переживает dangling cross-domain ref)
**And** `vpc.v1.SubnetService.Create {zone_id:"ru-central1-d"}` (новый ресурс в удалённой зоне) → `INVALID_ARGUMENT` (geo вернул `NOT_FOUND`)

---

## S5 — api-gateway: перерегистрация на geo backend

### Scenario 6.0-17: REST-пути Region/Zone указывают на geo backend
**Given** api-gateway пересобран
**When** инспектировать `internal/restmux/mux.go`, `internal/allowlist/list.go`, `internal/middleware/embed/permission_catalog.json`
**Then** `RegionService`/`ZoneService` (public read) и `InternalRegionService`/`InternalZoneService` (admin) зарегистрированы через **geo backend** (`geoAddr` / `geoInternalAddr`), НЕ через compute
**And** permission_catalog FQN изменены на `kacho.cloud.geo.v1.*` (напр. `kacho.cloud.geo.v1.RegionService/Get` → permission `geo.regions.get`); compute-FQN для Region/Zone удалены
**And** allowlist содержит `/kacho.cloud.geo.v1.RegionService/{Get,List}` и `/kacho.cloud.geo.v1.ZoneService/{Get,List}`; compute Region/Zone-записи удалены
**And** `Internal*` geo-сервисы зарегистрированы ТОЛЬКО на internal mux (`geoInternalAddr`), не на external (ban #6)

> **РЕШЕНИЕ по REST-пути (требует подтверждения reviewer):** новые пути — `/geo/v1/regions`, `/geo/v1/zones` (соответствует `api-conventions.md` REST-rule `/<service>/v1/<resource>`: имя сервиса = домен `geo`). Старые `/compute/v1/regions`/`/compute/v1/zones` **удаляются** (не дублируются), консистентно с тем, как предыдущий перенос Geography vpc→compute удалил `/vpc/v1/zones` без back-compat (см. `sub-phase-geography-to-compute-acceptance.md`). UI/SDK обновляются в том же эпике. Альтернатива (сохранить `/compute/v1/...` ради back-compat) **отклоняется** как нарушение REST-path convention (путь врал бы про владельца) и как тех-долг.

### Scenario 6.0-18: старые compute REST-пути geography исчезают (negative)
**Given** Scenario 6.0-17 задеплоен (после S7)
**When** `GET /compute/v1/regions` / `GET /compute/v1/zones` на external endpoint
**Then** → `404` (этих путей больше нет на compute backend)
**And** `GET /geo/v1/regions` / `GET /geo/v1/zones` → `OK` с seed-данными
**And** admin-пути `POST /geo/v1/regions` и т.п. недоступны на external TLS endpoint (`api.kacho.local:443`) → `404`; доступны только через internal mux

---

## S6 — kacho-deploy: sub-chart + pg-geo + migration-job

### Scenario 6.0-19: kacho-geo развёрнут в umbrella со своей БД
**Given** свежий стенд из `kacho-deploy` (umbrella-chart)
**When** `make dev-up` / helm-install
**Then** поднимается сервис `kacho-geo` (public :9090 + internal :9091) со своей БД `kacho_geo` (отдельный pg-инстанс/database — database-per-service, ban #8); НЕ общая с `kacho_compute`
**And** geo получает mTLS-сертификат (SEC-F cert-manager + SA) и authn-конфиг; internal-листенер требует client-cert
**And** values.dev / values.prod / values.fe3455 содержат блок `kacho-geo` (image, БД-conn, mTLS, geoAddr/geoInternalAddr для api-gateway и consumer-клиентов)
**And** добавлен и отрабатывает data-migration job (S3) как часть деплоя/upgrade на стендах с существующими данными

### Scenario 6.0-20: seed без compute-geography
**Given** свежий стенд
**When** прогон `ci/seed.sh` / e2e-фикстуры
**Then** seed НЕ делает `POST /compute/v1/regions` / `POST /compute/v1/zones` (этих путей нет); Region/Zone уже засеяны миграцией geo
**And** фикстурные `Subnet`/`Instance`/NLB создаются с `zone_id`/`region_id` существующих geo-зон/регионов и проходят
**And** helm/compose содержат `geoAddr`/`geoInternalAddr` для vpc/compute/nlb/api-gateway клиентов; конфиги compute→self-zone и vpc/nlb→compute-geography удалены

---

## S7 — contract: удаление geography из compute.v1 (breaking, последним)

### Scenario 6.0-21: geography удалена из compute.v1 (breaking — намеренный)
**Given** geo развёрнут, данные мигрированы, consumer'ы переключены (S2–S6 в `main`)
**When** прогон `buf breaking` после удаления `Region`/`Zone`/`RegionService`/`ZoneService`/`InternalRegionService`/`InternalZoneService` из `kacho.cloud.compute.v1`
**Then** `buf breaking` сигналит breaking-change — он **намеренный**, отмечен в PR как coordinated removal (выполняется ПОСЛЕ перевода всех consumer'ов, поэтому ни один live-вызов не ломается)
**And** в `compute.v1` не остаётся `region.proto`/`zone.proto`/`region_service.proto`/`zone_service.proto`; `internal_catalog_service.proto` не содержит `InternalRegionService`/`InternalZoneService` (только `InternalDiskTypeService`)
**And** `kacho-compute` `gen/`-импорты geography-stubs удалены; компиляция зелёная

### Scenario 6.0-22: в compute не осталось dead Region/Zone (no dead code)
**Given** Scenario 6.0-21
**When** инспектировать `kacho-compute`
**Then** схема `kacho_compute` НЕ содержит таблиц `regions`/`zones` (удалены новой down-safe миграцией — НЕ редактированием применённой `0001`/`0003`, ban #5; новая `00NN_drop_geography.sql`)
**And** `DiskType.zone_ids` валидируется против geo (или остаётся как есть — opaque список строк, см. reviewer-note), `Disk.zone_id`/`Instance.zone_id` валидируются через geo-client
**And** в `internal/{domain,service,repo,handler}` нет `Region`/`Zone`-impl, нет `catalog`-кода для geography (остаётся DiskType); нет `internal_catalog_handler` Region/Zone-веток
**And** `grep -rn -iE 'RegionService|ZoneService' kacho-compute/internal` не находит impl (только geo-client-вызовы, если есть)

> **Reviewer-note (требует решения):** `DiskType.zone_ids` — список зон, где предлагается тип диска. Решить: (a) `zone_ids` остаётся opaque `[]string` в compute без перекрёстной валидации против geo (минимально-инвазивно), или (b) валидируется через geo при admin-CRUD DiskType. Рекомендация: (a) на этом эпике (DiskType — admin-only, редкие записи; добавлять geo-валидацию — отдельный scope), зафиксировать как scope-deviation.

---

## S8 — workspace: docs, vault, build-graph, owner-map, bootstrap/sync

### Scenario 6.0-23: owner-map, build-graph и roadmap отражают geo как нового владельца-leaf
**Given** репозитории в `main`
**When** открыть `.claude/rules/data-integrity.md`, `.claude/rules/polyrepo.md`, `.claude/rules/00-kacho-core.md`, `docs/specs/00-overview-and-scope.md`, `docs/specs/01-architecture-and-services.md`, `docs/specs/02-data-model-and-conventions.md`, `docs/specs/04-roadmap-and-phasing.md`
**Then** owner-map (`data-integrity.md` §5): **Geography (Region/Zone) → `kacho-geo`** (не compute)
**And** `polyrepo.md` build-граф: `kacho-geo` — leaf после corelib (`replace ../kacho-corelib + ../kacho-proto`), runtime-edges `kacho-compute → kacho-geo` / `kacho-vpc → kacho-geo` / `kacho-nlb → kacho-geo` / `kacho-api-gateway → kacho-geo` зафиксированы; ребро `vpc→compute (zone)` помечено удалённым; ацикличность сохранена (geo никого не зовёт)
**And** репо-таблица `polyrepo.md` содержит строку `kacho-geo` (Geography Region/Zone, leaf)
**And** `04-roadmap-and-phasing.md` §4 обновлён: таблица сервисов содержит `kacho-geo`; runtime-рёбра `*→geo` зафиксированы; ребро `vpc→compute (zone)` удалено; ребро `nlb→compute` остаётся задокументированным **только** для Instance-таргетов (instance-resolve), НЕ для region (region-валидация теперь `nlb→geo`) — при этом `04` ранее вообще не документировал `nlb→compute (region)`, поэтому правка фиксирует корректное состояние, а не удаляет существующую запись
**And** `00-overview-and-scope.md` / `01-architecture-and-services.md` упоминают `kacho-geo` как домен Geography; в `02-data-model-and-conventions.md` Geography-таблицы под `kacho_geo`

### Scenario 6.0-24: vault-trail переписан
**Given** vault `obsidian/kacho/`
**When** инспектировать
**Then** созданы `resources/geo-region.md`, `resources/geo-zone.md`; `rpc/geo-region-service.md`, `rpc/geo-zone-service.md` (+ internal); новые `packages/`-записи geo-сервиса
**And** edges переписаны: `edges/vpc-to-geo-zone-validate.md`, `edges/nlb-to-geo-region-validation.md`, `edges/compute-to-geo-zone-validate.md` (новые); старые `vpc-to-compute-zone-validate.md` / `nlb-to-compute-region-validation.md` помечены deprecated/superseded с записью в History (KAC-номер)
**And** KAC-trail `KAC/KAC-<N>.md` для эпика создан (Status, Type, Repos, PRs, «Затронутые сущности vault», DoD-чеклист)

### Scenario 6.0-25: bootstrap + sync покрывают новый репо
**Given** workspace tooling
**When** инспектировать `bootstrap.sh`, `sync-tooling.sh`
**Then** `bootstrap.sh` repo-список содержит `kacho-geo` (клонируется в `project/`)
**And** `sync-tooling.sh` repo-список содержит `kacho-geo` (generic-оснастка `rules/agents/skills/hooks/settings.json` раскатывается в `project/kacho-geo/.claude/`)
**And** `project/kacho-geo/CLAUDE.md` `@import`-ит локальные `.claude/rules/*` (self-sufficient standalone-репо)

---

## Самые рискованные части и де-риск (явно)

| Риск | Почему опасно | Де-риск |
|---|---|---|
| **Breaking `compute.v1` proto** | удаление Region/Zone — `buf breaking`; преждевременное удаление обрушит live-consumer'ов | удаление (S7) — **последним**, ПОСЛЕ перевода всех consumer'ов на geo (expand→migrate→switch→contract); breaking помечен намеренным в PR; rollback = revert |
| **Live data-migration** | потеря/искажение строк или сброс `id`/`created_at` сломает `Instance.zone_id`/`Subnet.zone_id`/`region_id` (dangling-ref на всём стенде) | idempotent export/import с сохранением id+created_at (Scenario 6.0-09); dual-read window (6.0-10) — geo и compute совпадают до switch; валидация существующих ссылок (6.0-11) на **dev И fe3455**; job idempotent (повторный прогон безопасен) |
| **Порядок cutover** | switch до миграции данных / удаление до switch → окно недоступности Region/Zone | строгий S1→…→S7; на каждом шаге Region/Zone доступны хотя бы из одного источника; контрактное удаление только после switch |
| **authz-инвариант на geo internal** | новый сервис с internal-листенером без authz-Check = security-баг (`security.md`) | Scenario 6.0-08 явно требует per-RPC Check на обоих листенерах; mTLS на :9091; viewer-floor / system_admin |
| **api-gateway REST-путь back-compat соблазн** | оставить `/compute/v1/...` ради UI = путь врёт про владельца + тех-долг | решение зафиксировано: `/geo/v1/...`, старые пути удалены, UI/SDK обновлены в эпике (6.0-17/6.0-18) |

---

## DoD эпика (общий)

- **Acceptance-first**: этот док APPROVED (`acceptance-reviewer`) ДО любого кода (ban #1). Эпик-тикет `[EPIC]` + per-repo Subtask'и + KAC-trail в vault.
- **TDD per service** (ban #12): по каждому новому RPC/полю/клиенту — RED integration-тест (testcontainers, вкл. FK-RESTRICT и authz) + newman happy+negative в том же PR; пара RED→GREEN показана.
- **proto**: `buf lint` зелёный на всех шагах; `buf breaking` зелёный на S1 (additive), намеренно-breaking на S7 (отмечено).
- **Кросс-репо порядок** (S1→S8 по build-графу); CI sibling-`ref:`-pinning на feature-ветки пока upstream не в `main`, после merge → `ref: main`.
- **data-migration валидирована на dev + fe3455** (Scenario 6.0-09/6.0-11): id и created_at сохранены, существующие ссылки резолвятся пост-cutover.
- **security**: geo internal-листенер — mTLS + per-RPC authz-Check (6.0-08); Internal* не на external (ban #6); admin=system_admin, read=system_viewer-floor.
- **data-integrity**: один владелец (geo); consumer'ы ссылаются по id (TEXT, без cross-service FK); fail-closed на мутациях (6.0-15); dangling-ref грациозно (6.0-16); within-service FK RESTRICT zones→regions на DB-уровне.
- **No dead code**: в compute не осталось Region/Zone proto/схемы/кода (6.0-21/6.0-22); ban #5 (новая drop-миграция, не редактирование применённой); ban #11 (никакого «уберём потом»).
- **No foreign-cloud refs** (ban #2): домен/код/доки/env описаны в терминах Kachō.
- **vault + docs**: owner-map, polyrepo build-graph/edges, resources/rpc/packages/edges переписаны; bootstrap.sh + sync-tooling.sh покрывают `kacho-geo`; `docs/specs/00-overview/01-architecture/02-data-model/04-roadmap` отражают geo.
- **Финальная верификация**: `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` + newman зелёные во всех затронутых репо; e2e (`make e2e-test`) — заказчиком на шаге 7.

## Reviewer checklist (acceptance-reviewer)

- [ ] Каждый сценарий наблюдаем конкретным RPC/REST-вызовом или инспекцией кода/схемы (без «должно работать»); negative-сценарии (6.0-06, 6.0-11, 6.0-15, 6.0-16, 6.0-18) дают точный gRPC-код.
- [ ] Cutover-стратегия (expand→migrate→switch→contract) исключает окно недоступности; порядок стадий по build-графу корректен; CI-pinning описан.
- [ ] Data-migration сохраняет id+created_at; dual-read window и валидация существующих ссылок на dev+fe3455 покрыты.
- [ ] Соблюдены ban'ы: один владелец/без cross-service FK/fail-closed (6.0-13/15/16), Internal* не на external (6.0-08/17/18), database-per-service (6.0-19), новая drop-миграция не редактирует применённую (6.0-22), мутации→Operation у consumer-RPC (Instance/Subnet Create); admin Region/Zone — синхронный catalog-паттерн (зафиксированная scope-deviation).
- [ ] authz-инвариант geo internal (per-RPC Check на обоих листенерах) явно проверяется (6.0-08).
- [ ] Решение по REST-пути (`/geo/v1/...`, старые удалены) и по `DiskType.zone_ids` (scope-deviation, вариант (a) opaque) — приемлемы либо помечены к уточнению.
- [ ] `buf breaking` на S7 — намеренный, выполняется последним; на S1 — additive (зелёный).
- [ ] **Round 1 ground-truth-правки внесены:** nlb region-precheck без кэша (6.0-14); audit-таблица `geo_outbox` по конвенции `<domain>_outbox` (6.0-04/6.0-07); AddressPool — фактически zonal, валидация+dangling-ref покрыты (6.0-13); `04-roadmap-and-phasing.md` в scope S8, `nlb→compute` остаётся только для Instance-таргетов (6.0-23); опечатка `regionses`/`zoneses`→`geo.regions.list`/`geo.zones.list` исправлена намеренно (6.0-01).
- → Вердикт: **APPROVED** либо список замечаний. Кодинг S1…S8 — только после APPROVED.
