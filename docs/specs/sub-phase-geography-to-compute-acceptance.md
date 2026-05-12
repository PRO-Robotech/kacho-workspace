# sub-phase: Region/Zone → kacho-compute + регламент кросс-доменных ссылок — acceptance (Given-When-Then)

| | |
|---|---|
| Эпик | `KAC-15` |
| Этот док | `KAC-16` (acceptance-author); APPROVE — `KAC-17` (acceptance-reviewer) |
| Дизайн | описание эпика `KAC-15` (8 пунктов) + workspace `CLAUDE.md` §«Кросс-доменные ссылки на ресурсы» |
| Scope | Перенести `Region`/`Zone` (таблицы, proto, сервисы, REST-пути) из `kacho-vpc` в `kacho-compute` **полноценно**; `kacho-vpc` (и все) ссылаются на zone через compute-API; UI → `/compute/v1/zones`; зафиксировать регламент owner/consumer-взаимодействия в CLAUDE.md по всем проектам. |
| Scope deviations | `AddressPool` остаётся в `kacho-vpc` (его `zone_id` становится `TEXT` без FK, валидируется через compute). NLB `region_id` — как было (свободная строка), отдельно не трогаем. YC-verbatim — отложено (см. workspace CLAUDE.md «Что это за проект»), поэтому уход от «verbatim YC ZoneService в compute» не нарушение. |

## Preconditions
- `kacho-proto` собран, `gen/` закоммичен, `buf lint` зелёный; ожидаемый `buf breaking` (удаление `vpc/v1` geography-сервисов) — зафиксирован в PR как намеренный.
- `kacho-compute`, `kacho-vpc`, `kacho-api-gateway`, `kacho-ui`, `kacho-deploy` обновлены и развёрнуты на dev-стенде (`155.212.210.13`).
- `make build` / `go build ./...` / `go vet ./...` зелёные во всех затронутых репо; UI-сборка зелёная.

## Scenario 1 — Geography живёт ТОЛЬКО в kacho-compute
**Given** стенд развёрнут, **When** инспектировать схемы БД и proto, **Then**:
- схема `kacho_compute` содержит таблицы `regions(id,name,created_at)` и `zones(id,region_id,name,status,created_at)`; `zones.region_id` имеет FK на `regions(id) ON DELETE RESTRICT`; seed-строки `ru-central1` и `ru-central1-{a,b,d}` присутствуют (вставлены миграцией compute, не admin-API);
- схема `kacho_vpc` **НЕ содержит** таблиц `regions`/`zones`; `subnets.zone_id` и `address_pools.zone_id` — колонки `TEXT` **без FK** (нет `subnets_zone_id_fkey`, `address_pools_zone_id_fkey`);
- в `kacho-proto` `Region`/`Zone`/`RegionService`/`ZoneService`/`InternalRegionService`/`InternalZoneService` определены в пакете `kacho.cloud.compute.v1`; `proto/kacho/cloud/vpc/v1/internal_geography_service.proto` **удалён**, в `vpc/v1` нет `Region`/`Zone`/geography-сервисов;
- `compute.v1.Zone` несёт поля `id, region_id, name, status, created_at` (объединение прежних vpc- и compute-версий).

## Scenario 2 — публичные read-only Region/Zone — на /compute/v1
**Given** Scenario 1, **When** `GET /compute/v1/regions` и `GET /compute/v1/zones[?region_id=ru-central1]` (public mux), **Then** возвращают seed-данные; `GET /compute/v1/zones/ru-central1-a` → зону со `status=UP`. `GET /vpc/v1/zones`, `GET /vpc/v1/regions` → **404** (этих путей больше нет).

## Scenario 3 — admin-CRUD Region/Zone — на /compute/v1, internal-only
**Given** Scenario 1, **When** через internal mux (`computeInternalAddr`): `POST /compute/v1/regions {id:"eu-west1",name:"EU West 1"}` → создаёт регион; `POST /compute/v1/zones {id:"eu-west1-a",region_id:"eu-west1",name:"EU West 1 A",status:"UP"}` → создаёт зону; `PATCH`/`DELETE` — работают; `DELETE /compute/v1/regions/eu-west1` пока есть `eu-west1-a` → **FailedPrecondition** (FK RESTRICT); после удаления зоны — регион удаляется. **Then** ни один из этих admin-методов не доступен на external TLS endpoint (`api.kacho.local:443`) — там 404 (ответственность api-gateway-registrar, §запрет 6).

## Scenario 4 — kacho-vpc валидирует zone через compute-API, своих таблиц не имеет
**Given** Scenario 1, **When**:
- `POST /vpc/v1/subnets {... zone_id:"ru-central1-a" ...}` → ok (vpc вызвал `compute.v1.ZoneService.Get("ru-central1-a")`, зона есть);
- `POST /vpc/v1/subnets {... zone_id:"no-such-zone" ...}` → **InvalidArgument** (vpc спросил compute → NotFound → маппинг в InvalidArgument);
- `POST /vpc/v1/addressPools {... zone_id:"ru-central1-a" ...}` → ok; с несуществующей зоной → **InvalidArgument**;
- `SubnetService.Relocate` с `destination_zone_id` существующей зоны → ok; несуществующей → **InvalidArgument**.
**Then** в коде `kacho-vpc` нет `internal/repo/geography_repo.go`, нет импл `InternalRegionService`/`InternalZoneService`; есть `internal/clients/compute_client.go`, реализующий port `GeographyRegistry` из `service/`.

## Scenario 5 — kacho-compute больше не proxy'ит зоны в kacho-vpc
**Given** Scenario 1, **When** инспектировать `kacho-compute`, **Then**: в `internal/clients/vpc_client.go` нет методов `GetZone`/`ListZones` и поля `internalZones`; `ZoneService` не имеет `skipPeer`-флага и `ZoneSource`-fallback'а — читает из локальной таблицы `zones`; `Disk.Create`/`Instance.Create`/`disk_types.zone_ids` валидируют `zone_id` локально (по таблице `zones`). Остановка `kacho-vpc` не ломает чтение/создание зон в compute.

## Scenario 6 — UI ходит в /compute/v1/zones
**Given** kacho-ui развёрнут, **When** открыть формы, использующие зоны (создание Subnet — `InlineSubnetCreateForm`; relocate Subnet — `SubnetRelocateDialog`; фильтр по зоне на списках — `ResourceListPage`; страница `/system/regions`), **Then** дропдауны/списки наполняются из `/compute/v1/zones` (и `/compute/v1/regions` для region-страницы); ни один UI-вызов не идёт на `/vpc/v1/zones` / `/vpc/v1/regions`. UI-сборка зелёная.

## Scenario 7 — dangling-ref переживается грациозно (NEGATIVE)
**Given** есть `kacho-vpc`-подсеть `S` в зоне `ru-central1-d` и (опц.) `AddressPool` в ней, **When** admin удаляет зону `ru-central1-d` в compute (предположим, без compute-dependents), **Then**:
- `GET /vpc/v1/subnets/{S}` — **не падает** (200), `zone_id` остаётся `"ru-central1-d"` (возможно с признаком деградации/невалидной зоны, если такой признак введён) — НЕ 500, НЕ паника сервиса;
- `POST /vpc/v1/subnets {zone_id:"ru-central1-d"}` (создание нового ресурса в удалённой зоне) → **InvalidArgument**;
- сервис `kacho-vpc` продолжает обслуживать остальные запросы.

## Scenario 8 — fail-closed при недоступности compute (NEGATIVE)
**Given** `kacho-compute` остановлен, **When** `POST /vpc/v1/subnets {zone_id:"ru-central1-a"}`, **Then** → **Unavailable** (vpc не смог провалидировать zone — fail-closed на мутации); при этом `GET /vpc/v1/subnets/{S}` существующих подсетей — **ok** (чтение уже сохранённых данных zone не перепроверяет).

## Scenario 9 — deploy/seed без vpc-geography
**Given** свежий стенд из `kacho-deploy`, **When** прогон `ci/seed.sh`, **Then**: скрипт **не** делает `POST /vpc/v1/regions` / `POST /vpc/v1/zones` (этих путей нет); зоны/регион уже есть (засеяны миграцией compute); фикстурные Network/Subnet для compute-e2e создаются с `zone_id` существующих зон и проходят; helm/compose не содержат конфига compute→vpc zone-proxy (`KACHO_COMPUTE_VPC_*`), но содержат адрес compute-сервиса для vpc→compute клиента.

## Scenario 10 — регламент кросс-доменных ссылок зафиксирован
**Given** репозитории, **When** открыть `kacho-workspace/CLAUDE.md`, `kacho-vpc/CLAUDE.md`, `kacho-compute/CLAUDE.md`, **Then**: в workspace есть секция «Кросс-доменные ссылки на ресурсы (owner-сервис / consumer-сервис) — регламент» (один owner на тип; consumer хранит чужой id `TEXT` без FK и валидирует через `Get` владельца на request-path в `internal/clients/`; denorm-зеркала read-only/помечены; владелец без cross-service cascade; dangling-ref грациозно; карта владельцев доменов; runtime-edge vs build-edge); §запрет 6 обновлён (Region/Zone admin → `/compute/v1/*`); §«Кросс-репо зависимости» содержит runtime-edge `kacho-vpc → kacho-compute` и не упоминает `kacho-compute → kacho-vpc` zone-proxy; vpc/compute CLAUDE.md согласованы с этим. `docs/specs/00/01/02` отражают: Geography — домен kacho-compute.

## Reviewer checklist (acceptance-reviewer, `KAC-17`)
- [ ] Каждый сценарий наблюдаем конкретными запросами/инспекцией кода/схемы (без «должно работать»).
- [ ] Негативные сценарии (5, 7, 8) явно проверяют отсутствие proxy / грациозность dangling-ref / fail-closed.
- [ ] Регламент owner/consumer в workspace-CLAUDE.md согласован с тем, что реально делает kacho-vpc (валидация zone через client) и kacho-compute (owner, без proxy).
- [ ] Соблюдены §запреты: нет cross-service FK (4, 8), admin-методы compute не на external TLS (6), нет ORM/новых общих БД, мутации возвращают Operation где это мутирующий публичный RPC (Region/Zone admin — internal-only, паттерн как у InternalDiskTypeService: синхронные ок).
- [ ] Кросс-репо порядок (KAC-19 proto → KAC-20 compute → KAC-21 vpc → KAC-22 api-gateway → KAC-23 ui → KAC-24 deploy → KAC-25 docs → KAC-26 test) корректен; гейт перед кодом соблюдён; CI-pinning ref'ов на feature-ветки описан.
- [ ] `buf breaking` (удаление vpc-geography) — намеренное, отмечено в плане PR; downstream-сервисы (kacho-compute) перестают импортировать `vpcv1` geography-stubs.
- → Вердикт: **APPROVED** либо список замечаний. Кодинг `KAC-19…KAC-26` — только после APPROVED.
