# VPC redesign — Network defaultSG · SG used_by · отдельный метод правил/маршрутов

**Статус:** дизайн (DRAFT для acceptance). Код НЕ начат — нужен APPROVED Given-When-Then
(workspace CLAUDE.md «Запреты» #1). Фича → KAC-эпик до кода.

**Репозитории (порядок по графу):** `kacho-proto` → `kacho-vpc` → `kacho-api-gateway` → `kacho-ui` → vault/доки.

---

## 1. Network.Create — флаг «создавать default SG»

**Сейчас:** default-SG создаётся inline в `network.go::doCreate` при `KACHO_VPC_DEFAULT_SG_INLINE=true` (env, дефолт). Tenant не управляет.

**Хотим:** явный флаг в запросе.

- proto: `CreateNetworkRequest { … optional bool create_default_security_group = N; }`
  - `optional` → tri-state: задан → решает клиент; не задан → fallback на env (back-compat).
  - `true` → бэк генерит default-SG (как сейчас), `default_security_group_id` заполнен.
  - `false` → сеть без SG, `default_security_group_id` пуст.
- UI: чекбокс «Создать группу безопасности по умолчанию» (вкл по умолчанию) в форме Network.
- DoD: integration-тест (true→SG создан / false→нет); newman happy+negative; default-env поведение не сломано.

---

## 2. SecurityGroup.used_by — «Пользователь» (к кому подключена SG)

> Поправка по фидбэку: `used_by` = **потребители SG** (кто её подключил), НЕ «правило ссылается на другую SG» (это отдельная семантика, вне скоупа).

**Хотим:** на SG — поле `used_by[]` тем же контрактом, что у Address/NIC:
```json
"used_by": [
  { "referrer": { "type": "network_interface", "id": "..." }, "type": "USED_BY" },
  { "referrer": { "type": "network",           "id": "..." }, "type": "USED_BY" }  // default_security_group_id
]
```
- Референты SG: `network_interface` (NIC.security_group_ids ⊇ sg), `network` (default_security_group_id = sg).
- Output-only, считается бэком обратным обходом (как Address.used_by). На публичной поверхности (не инфра-чувствительное).
- Польза: безопасный delete (`FailedPrecondition` если used_by непуст) + «Потребители» в UI-Обзоре (тот же `ReferrerLink`).
- DoD: integration-тест (attach NIC → used_by появился; detach → исчез); newman; delete-precondition.

---

## 3. Правила SG (и маршруты RouteTable) — отдельный метод обновления

**Сейчас (по миграционной карте):** SG-rules правятся через split-endpoint `UpdateRules` (метаданные — PATCH отдельно). RouteTable.static_routes — generic array-field, правка всего ресурса. Правила/маршруты — JSONB-массивы без стабильных id.

**Боль:** обновление = замена всего набора → lost-update при конкуренции, нет адресации отдельного правила.

> **Правила SG и маршруты RT — одна и та же структура** (родитель + неупорядоченный
> набор дочерних записей: у правил порядок не важен — default-deny + любое совпавшее
> разрешает; у маршрутов — longest-prefix-match, детерминирован по длине префикса).
> Поэтому **механизм выбирается единый для обоих**; ниже оба варианта симметричны
> (rules ↔ routes). Развилка ровно одна: replace-set vs гранулярно.

### Вариант 1 — replace-set (минимум изменений), симметрично
- `UpdateSecurityGroupRules(sg_id, rules[]) → Operation` — атомарная замена набора.
- `UpdateRouteTableRoutes(route_table_id, routes[]) → Operation` — то же для маршрутов.
- Метаданные (name/labels/desc) — отдельный `Update`. Просто; но lost-update остаётся
  (клиент шлёт весь набор), нет стабильных id у записей.

### Вариант 2 — гранулярные verb-RPC + own-table (РЕКОМЕНДУЮ)
Правило/маршрут — first-class строка со стабильным `id` в своей таблице:
```
security_group_rules(id PK, sg_id FK→security_groups ON DELETE CASCADE,
                     direction, protocol, ports, target(cidr|sg_id|predefined), description)
route_table_routes(id PK, route_table_id FK→route_tables ON DELETE CASCADE,
                   destination_prefix, next_hop_address)
```
RPC (консистентно с уже существующими Subnet `:add-cidr-blocks`/`:remove-cidr-blocks`):
- `…/securityGroups/{id}:addRules(rules[]) → Operation`
- `…/securityGroups/{id}:removeRules(rule_ids[]) → Operation`
- `…/securityGroups/{id}:updateRule(rule_id, rule) → Operation`
- зеркально RouteTable: `:addRoutes` / `:removeRoutes` / `:updateRoute`

**Почему В2:**
- Стабильные `id` → адресная правка/удаление одного правила/маршрута.
- Нет lost-update всего ресурса (concurrent add/remove независимы).
- DB-инвариант на уровне БД (CLAUDE.md «within-service refs»): FK + CASCADE + при необходимости partial-UNIQUE/EXCLUDE; SQLSTATE→gRPC в maperr.
- UI уже под это готов: SG «Входящий/Исходящий» и RT «Маршруты» — собственные табы; кнопки «Добавить правило/маршрут» перевешиваются с edit-формы на verb-RPC (add/remove inline, как CIDR-чипы Subnet).
- Консистентно со стилем YC (suffix-actions `:verb`, Operation на каждой мутации).

**Миграция данных:** JSONB-массивы `rules`/`static_routes` → строки own-table (goose-миграция, backfill из существующего JSONB).

DoD В2: integration-тесты (add/remove/update по одному; concurrent add — оба прошли; remove несуществующего → NotFound); newman happy+negative; UI-табы на verb-RPC; vault (resources/vpc-securitygroup, vpc-routetable; rpc/vpc-*; edges если меняется).

---

## Решение заказчика (2026-05-30): ВАРИАНТ 2

Правила SG и маршруты RT — **гранулярные verb-RPC + own-tables**, симметрично:
- `…/securityGroups/{id}:addRules` / `:removeRules` / `:updateRule`
- `…/routeTables/{id}:addRoutes` / `:removeRoutes` / `:updateRoute`
- own-tables `security_group_rules` / `route_table_routes` (стабильный id PK, FK→родитель ON DELETE CASCADE).
- goose-миграция: backfill из существующих JSONB-массивов `rules` / `static_routes` → строки own-table.

## Декомпозиция (после выбора)
- KAC-эпик «VPC redesign: Network defaultSG + SG used_by + granular rules/routes».
- Subtasks: proto (поля+verb-RPC+own-table messages) · vpc (миграции own-tables + handlers + used_by + Network flag) · api-gateway (REST verb-routes) · ui (табы на verb-RPC + Network-чекбокс) · vault/доки.
- Acceptance GWT на каждую часть до кода; строгий TDD (RED→GREEN); тесты в том же PR.
