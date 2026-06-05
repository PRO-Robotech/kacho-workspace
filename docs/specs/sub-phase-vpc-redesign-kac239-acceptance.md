# Acceptance (Given-When-Then) — KAC-239 VPC redesign

Гейт по workspace CLAUDE.md «Запреты» #1. Эпик [KAC-239]. Дизайн:
`docs/superpowers/specs/2026-05-30-vpc-network-sg-routetable-redesign.md`.
Решение заказчика: **Вариант 2** (гранулярные verb-RPC + own-tables, симметрично SG/RT).

Стадии (каждая — самостоятельный deliverable end-to-end, по графу proto→vpc→gw→ui, TDD):
- **S1** Network `create_default_security_group` флаг.
- **S2** SecurityGroup `used_by` («Пользователь» — к кому подключена SG) + safe-delete.
- **S3** RouteTable маршруты — own-table `route_table_routes` + verb-RPC + `StaticRoute.id`.
- **S4** SecurityGroup правила — own-table `security_group_rules` + verb-RPC `:add/:remove-rules` (UpdateRules/UpdateRule сохраняются, переписаны на own-table).

Стадии — отдельные PR. S1/S2 (additive) первыми; S3/S4 (own-table + backfill) следом.

**Точные proto-локации (по recon):**
- `create_default_security_group` → `network_service.proto` `CreateNetworkRequest`, **поле 5** (свободно), `optional bool`.
- `SecurityGroup.used_by` → `security_group.proto`, **поле 11** (после `default_for_network = 10`), `repeated kacho.cloud.reference.Reference`, output-only.
- `StaticRoute.id` → `route_table.proto`, **поле 5** (1=destination_prefix, 2=next_hop_address, 3=labels, 4=gateway_id заняты).
- verb-RPC → `route_table_service.proto` / `security_group_service.proto`, REST `:add-routes`/`:remove-routes`/`:update-route` и `:add-rules`/`:remove-rules` (эталон Subnet `:add-cidr-blocks`).

---

## S1 — Network.Create: create_default_security_group

**Контекст:** сейчас default-SG создаётся inline при `KACHO_VPC_DEFAULT_SG_INLINE=true` (env, global). Tenant не управляет per-network. Поле `optional bool` → tri-state.

### S1-1 (positive, flag=true)
- **Given** seed-проект, стенд с любым значением env
- **When** `POST /vpc/v1/networks {"projectId":"<seed>","name":"net-defsg-on","createDefaultSecurityGroup":true}` → poll Operation
- **Then** Operation `done && !error`; `Network.default_security_group_id` matches `^enp[0-9a-hj-km-np-z]{17}$`; `SecurityGroup.Get(<id>)` → `default_for_network=true`, имя `default-sg-<first8-of-net-id>`.

### S1-2 (positive, flag=false)
- **Given** seed-проект
- **When** `POST /vpc/v1/networks {"projectId":"<seed>","name":"net-defsg-off","createDefaultSecurityGroup":false}` → poll
- **Then** Operation done; `default_security_group_id == ""`; `ListNetworkSecurityGroups(<net>)` не содержит default-SG.

### S1-3 (back-compat, flag не задан)
- **Given** `KACHO_VPC_DEFAULT_SG_INLINE=true` (default)
- **When** `POST /vpc/v1/networks {"projectId":"<seed>","name":"net-defsg-nil"}` (без поля)
- **Then** поведение как раньше — `default_security_group_id` заполнен (env-fallback). (При env=false и nil → пусто; покрывается integration-тестом, не newman — стенд на env=true.)

### S1-4 (UI)
- **Given** форма создания Network
- **Then** чекбокс «Создать группу безопасности по умолчанию» (checked по умолчанию); снятие → payload `createDefaultSecurityGroup:false`; включён → `true`.

**DoD S1:** proto+regen (buf lint/breaking зелёные); vpc create.go читает `*bool` (nil→env, иначе значение); integration-тест (true→SG / false→нет / nil+env=true→SG / nil+env=false→нет); newman S1-1/S1-2 happy; UI-чекбокс; vault.

---

## S2 — SecurityGroup.used_by («Пользователь»)

**Контекст:** `used_by` = к кому ПОДКЛЮЧЕНА SG (потребители), контракт `reference.Reference{referrer{type,id}, type=USED_BY}` (как Address/NIC). Референты: `network_interface` (NIC.security_group_ids ∋ sg), `network` (default_security_group_id == sg). **НЕ** про правило-ссылается-на-SG (вне скоупа).

**Механизм вычисления (derived-on-read, НЕ отдельная reference-таблица):** в `Get`/`List` SG бэк сканирует `network_interfaces` по `security_group_ids @> ['<sg>']::jsonb` + `networks WHERE default_security_group_id = '<sg>'`. Нужен GIN-индекс на `network_interfaces.security_group_ids` (иначе List N×seq-scan). Это отличается от Address (там backing `address_references` с CAS) — для SG отдельную таблицу НЕ строим.

**proto:** `SecurityGroup { … repeated kacho.cloud.reference.Reference used_by = 11; }` (output-only).

### S2-1 (пусто)
- **Given** SG без потребителей (создана отдельно, не default, не на NIC)
- **When** `GET /vpc/v1/securityGroups/<sg>`
- **Then** `used_by` отсутствует/пуст (`[]`).

### S2-2 (NIC подключил, в т.ч. multi-SG)
- **Given** NIC с `security_group_ids=[sgA, sgB]`
- **When** `Get(sgA)` и `Get(sgB)`
- **Then** у обоих `used_by` содержит `{referrer:{type:"network_interface", id:<nic>}, type:USED_BY}`.

### S2-3 (default-SG сети)
- **Given** сеть с `default_security_group_id=sg`
- **When** `Get(sg)`
- **Then** `used_by` содержит `{referrer:{type:"network", id:<net>}, type:USED_BY}`.

### S2-4 (safe-delete negative, NIC)
- **Given** не-default SG, подключённая к NIC (used_by непуст)
- **When** `DELETE /vpc/v1/securityGroups/<sg>` → poll
- **Then** Operation `done && error.code=FAILED_PRECONDITION` (текст YC-стиля, напр. `"security group is in use"`); SG остаётся (повторный Get → 200).

### S2-5 (delete после detach)
- **Given** SG, у которой убрали потребителей (NIC обновлён без неё)
- **When** `Delete`
- **Then** Operation done; SG удалена (Get → NotFound).

### S2-6 (UI)
- **Given** detail SG, Обзор
- **Then** строка «Потребители» = список `used_by` ссылками иконка+имя (ReferrerLink → RefNameLink), `network_interface`/`network` кликабельны.

### S2-7 (default-SG delete через Network.Delete не ломается)
- **Given** сеть с default-SG (used_by ∋ {network, <net>})
- **When** `DELETE /vpc/v1/networks/<net>` → poll
- **Then** Operation done; и Network, и его default-SG удалены. (used_by-guard применяется на **публичном** `SecurityGroup.Delete`, а НЕ на cascade-пути worker'а Network.Delete — там удаление default-SG идёт до Network безусловно.)

**DoD S2:** proto+regen; GIN-индекс на `security_group_ids` (миграция); vpc computes used_by в Get+List (скан NIC @> + networks default); публичный SG.Delete → FailedPrecondition если used_by непуст (default_for_network guard сохраняется как был); cascade Network.Delete не регрессирует; integration-тест (attach→used_by/multi-SG, delete-blocked, detach→delete-ok, Network.Delete-with-default-ok); newman S2-1..S2-5; UI-строка; vault.

---

## S3 — RouteTable routes: own-table + verb-RPC

**proto:** `StaticRoute { string id = 5; … }` (oneof next_hop сохраняется: `next_hop_address=2` | `gateway_id=4`); `RouteTableService += AddRoutes/RemoveRoutes/UpdateRoute` (Operation), REST `:add-routes`/`:remove-routes`/`:update-route`.
**DB (миграция 0004):** таблица
```
route_table_routes(
  id text PK,
  route_table_id text NOT NULL REFERENCES route_tables(id) ON DELETE CASCADE,
  destination_prefix text NOT NULL,
  next_hop_address text NOT NULL DEFAULT '',
  gateway_id text NOT NULL DEFAULT '',
  labels jsonb NOT NULL DEFAULT '{}',
  CHECK ((next_hop_address <> '') <> (gateway_id <> ''))  -- ровно один next-hop (oneof)
)
```
+ **backfill из JSONB `static_routes`** (сохраняя оба next_hop-варианта: address И gateway_id); `RouteTable.static_routes` читается из own-table (ORDER BY id). DB-инвариант: FK+CASCADE+CHECK. (UNIQUE(route_table_id, destination_prefix) НЕ добавляем — YC longest-prefix допускает дубль dst с разным next-hop.)

### S3-1 add (next_hop_address)
- **Given** RT без маршрутов
- **When** `POST /vpc/v1/routeTables/<rt>:add-routes {"routes":[{"destinationPrefix":"10.0.0.0/24","nextHopAddress":"10.0.0.1"}]}` → poll
- **Then** Operation done; `RouteTable.static_routes` содержит маршрут с присвоенным непустым `id`.

### S3-2 add (gateway_id)
- **Given** RT, существующий gateway `<gw>`
- **When** `:add-routes {"routes":[{"destinationPrefix":"0.0.0.0/0","gatewayId":"<gw>"}]}` → poll
- **Then** Operation done; маршрут с `gateway_id=<gw>`, `id` присвоен. (Покрывает сохранность gateway-варианта.)

### S3-3 remove
- **Given** RT с маршрутом id=r1
- **When** `:remove-routes {"routeIds":["r1"]}` → poll
- **Then** Operation done; маршрута r1 нет.

### S3-4 update
- **Given** RT с маршрутом r1 (next_hop_address)
- **When** `:update-route {"routeId":"r1","route":{"destinationPrefix":"10.0.0.0/24","nextHopAddress":"10.0.0.2"}}` → poll
- **Then** Operation done; r1 обновлён, `id` стабилен.

### S3-5 concurrent (integration, race)
- **Given** RT
- **When** две параллельные goroutine `AddRoutes` разных маршрутов
- **Then** обе прошли (own-table INSERT, RETURNING-кардинальность=1 у каждой; нет lost-update). Проверяется на DB-уровне (testcontainers), как `address_repo_set_reference_race_integration_test.go`.

### S3-6 negative
- `:remove-routes` с route_id, которого нет в этом RT → Operation `error.code=NOT_FOUND` (`"route <id> not found"`).
- malformed route_table_id → sync `InvalidArgument "invalid route table id '<X>'"` (corevalidate.ResourceID).
- `destination_prefix` с host-bits (`10.0.0.5/24`) → sync `InvalidArgument "Illegal argument ..."` (как Subnet CIDR).
- `:add-routes` с обоими next_hop (address И gateway) или без них → `InvalidArgument` (oneof violation).

### S3-7 (UI)
- RT detail: раздел «Статические маршруты» (таблица + счётчик) с «Добавить маршрут» (форма-панель) и «⋮ → Удалить» на verb-RPC — НЕ правкой всего ресурса.

**DoD S3:** proto+regen; миграция 0004 + backfill (оба next_hop-варианта); repo own-table (Insert/Delete/Update route + чтение static_routes JOIN); 3 usecase+handler (Operation+writer-TX+outbox по эталону AddCidrBlocks); gateway REST verb-routes; integration (вкл. S3-5 concurrent) RED→GREEN; newman S3-1..S3-4 + S3-6 negative; UI; vault.

---

## S4 — SecurityGroup rules: own-table + verb-RPC

**Судьба существующих RPC (зафиксировано):** `UpdateRules` и `UpdateRule` **сохраняются** (уже реализованы, покрыты newman/integration) — переписываются поверх own-table. **Добавляются** `AddRules`/`RemoveRules` (REST `:add-rules`/`:remove-rules`) как новые additive verb-RPC, симметрично RT. Это **не breaking** в proto.

**proto:** SG rules уже имеют `id` + oneof `target {cidr_blocks=8 | security_group_id=9 | predefined_target=10}` (`exactly_one`), `direction (required)`, `ports`, `protocol_name/number`. `SecurityGroupService += AddRules(AddSecurityGroupRulesRequest)/RemoveRules(RemoveSecurityGroupRulesRequest)`.
**DB (миграция, после 0004):** таблица
```
security_group_rules(
  id text PK,
  sg_id text NOT NULL REFERENCES security_groups(id) ON DELETE CASCADE,
  direction text NOT NULL,                 -- INGRESS|EGRESS
  protocol_name text NOT NULL DEFAULT '',
  protocol_number bigint NOT NULL DEFAULT 0,
  from_port bigint NOT NULL DEFAULT 0,
  to_port bigint NOT NULL DEFAULT 0,
  v4_cidr_blocks jsonb NOT NULL DEFAULT '[]',
  v6_cidr_blocks jsonb NOT NULL DEFAULT '[]',
  target_security_group_id text NOT NULL DEFAULT '',
  predefined_target text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  labels jsonb NOT NULL DEFAULT '{}',
  CHECK (direction IN ('INGRESS','EGRESS')),
  -- target oneof: ровно один из {cidr (v4∪v6 непуст), target_security_group_id, predefined_target}
  CHECK ( ((jsonb_array_length(v4_cidr_blocks)+jsonb_array_length(v6_cidr_blocks))>0)::int
        + (target_security_group_id<>'')::int + (predefined_target<>'')::int = 1 )
)
```
+ backfill из JSONB `rules`; `SecurityGroup.rules` читается из own-table (ORDER BY id). FK+CASCADE. Дубли правил допустимы (порядок не важен → UNIQUE не нужен).

### S4-1 add (cidr target)
- **Given** SG без правил
- **When** `POST /vpc/v1/securityGroups/<sg>:add-rules {"rules":[{"direction":"INGRESS","protocolName":"tcp","ports":{"fromPort":443,"toPort":443},"cidrBlocks":{"v4CidrBlocks":["0.0.0.0/0"]}}]}` → poll
- **Then** Operation done; правило с присвоенным непустым `id`, target=cidr.

### S4-2 add (security_group_id target)
- **Given** SG `<sg>`, другая SG `<sgRef>`
- **When** `:add-rules {"rules":[{"direction":"INGRESS","securityGroupId":"<sgRef>"}]}` → poll
- **Then** Operation done; правило с target=security_group_id=<sgRef>. (Это правило-ссылается-на-SG — допустимо в правиле, отдельно от used_by.)

### S4-3 remove
- **Given** SG с правилом r1
- **When** `:remove-rules {"ruleIds":["r1"]}` → poll
- **Then** Operation done; правила r1 нет.

### S4-4 update (существующий UpdateRule сохранён)
- **Given** SG с правилом r1
- **When** `PATCH /vpc/v1/securityGroups/<sg>/rules/r1 {"rule":{...,"description":"upd"}}` → poll
- **Then** Operation done; r1 обновлён, id стабилен. (Проверяет, что UpdateRule работает поверх own-table.)

### S4-5 concurrent (integration, race)
- **Given** SG
- **When** две параллельные `AddRules` разных правил
- **Then** обе прошли (own-table INSERT; нет lost-update). DB-level testcontainers.

### S4-6 negative
- `:add-rules` с `direction=DIRECTION_UNSPECIFIED` (или без direction) → `InvalidArgument`.
- `:add-rules` без target или с >1 target → `InvalidArgument` (oneof exactly_one / CHECK).
- `:remove-rules` несуществующего rule_id → Operation `NOT_FOUND` (`"rule <id> not found"`, как сейчас UpdateRule).
- malformed sg_id → sync `InvalidArgument "invalid security group id '<X>'"`.

### S4-7 (UI)
- SG detail: табы «Входящий/Исходящий трафик» с «Добавить правило» (форма-панель) и «⋮ → Удалить» на verb-RPC.

**DoD S4:** proto+regen; миграция + backfill JSONB rules→own-table (все target-варианты + ports + protocol); repo own-table (Add/Remove/Update rule + чтение rules; UpdateRules/UpdateRule переписаны поверх own-table, OCC больше не нужен — атомарные INSERT/DELETE по id); add/remove usecase+handler; gateway REST `:add-rules`/`:remove-rules`; integration (вкл. S4-5 concurrent) RED→GREEN; newman S4-1..S4-4 + S4-6; UI; vault. Существующие newman `*-LSG-*` / UpdateRules-кейсы — зелёные (regression).

---

## Общий DoD эпика
Все стадии merged; бэкенд (proto+vpc+gateway) и UI обновлены; integration+newman зелёные (вкл. regression UpdateRules); vault (resources/vpc-securitygroup, vpc-routetable, vpc-network; rpc/*; edges) обновлён; KAC-239 → Done с артефактами (PR-ссылки, лог тестов RED→GREEN).
