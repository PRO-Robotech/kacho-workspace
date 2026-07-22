# Целостность данных: within-service (DB-уровень) + cross-domain (peer-API)

## Within-service инварианты — ТОЛЬКО на DB-уровне (ban #10)

Внутри одной БД сервиса каждая ссылочная зависимость и инвариант **обязан** быть
выражен DB-конструкцией. Software-side `Get → check → Update` (TOCTOU) запрещён —
он race-prone (реальный инцидент: NIC-attach 2026-05-14, две Create прошли
software-guard и оба сделали безусловный UPDATE → second-writer-wins).

| Инвариант | DB-механизм |
|---|---|
| id обязан существовать в той же БД | `FK REFERENCES <t>(id) ON DELETE {RESTRICT\|CASCADE\|SET NULL}` |
| поле уникально | `UNIQUE` / `CREATE UNIQUE INDEX` |
| уникально только если поле непусто | partial `UNIQUE … WHERE <cond>` |
| range не пересекается | `EXCLUDE USING gist (… WITH &&)` |
| простой предикат | `CHECK (…)` |
| атомарный compare-and-swap | `UPDATE … WHERE <expected-state> RETURNING …` + проверка кардинальности |
| read-modify-write OCC без колонки версии | `xmin::text` snapshot + `UPDATE … WHERE xmin::text=$exp` |
| уникальная аллокация из пула под concurrency | `FOR UPDATE SKIP LOCKED LIMIT 1` + `DELETE … RETURNING` |
| сериализовать read-modify-write набора | `SELECT … FOR UPDATE` перед merge+write |

Service-слой только маппит SQLSTATE → gRPC: `23503`→FailedPrecondition,
`23505`→AlreadyExists/FailedPrecondition (по контексту), `23514`→InvalidArgument,
`23P01`→FailedPrecondition. **Никогда не leak'ай pgx-текст наружу** (→ фикс. INTERNAL).

### Шаблон attach / смена ownership — атомарный CAS (не TOCTOU)

```sql
UPDATE <table>
   SET <owner-col> = $new, <other…>
 WHERE id = $id
   AND (<owner-col> = '' OR <owner-col> = $new)   -- свободно ИЛИ уже наш (идемпотентно)
RETURNING …;
```
0 rows из RETURNING → `pgx.ErrNoRows` → `FailedPrecondition`. Single-statement UPDATE на
одной row защищён row-lock'ом: параллельный writer ждёт commit, видит обновлённый row,
CAS не matches → 0 rows. Доп. UNIQUE-индекс как «backstop» — НЕ нужен (и для
one-resource-per-owner-or-many семантики он ложно ловит нормальный multi-attach).

### Чек-лист нового ссылочного поля / инварианта

1. Ссылка на ресурс в **той же БД** → FK (+ partial UNIQUE/EXCLUDE при необходимости). Никогда software-only.
2. Условная уникальность → partial `UNIQUE … WHERE`.
3. Состояние меняется конкурирующими путями (attach/detach, allocate/free) → атомарный CAS.
4. SQLSTATE→gRPC в `mapRepoErr`/serviceerr.
5. **Integration-тест (testcontainers) с concurrent goroutines** на спорный путь — ровно одна
   транзакция проходит, остальные получают ожидаемый sentinel. Без него не мёржим (race не ловится unit-тестом).

## Cross-domain ссылки (owner-сервис / consumer-сервис)

Через границу сервиса FK невозможен (DB-per-service, ban #4/#8). Регламент:

1. **Один владелец на тип ресурса** — канонический CRUD/read-API. Consumer'ы не держат mirror-строк, нет cross-service FK.
2. **Consumer ссылается по id (TEXT, без FK), валидирует через API владельца** на request-path
   (`Create`/`Update`): типизированный gRPC-клиент `internal/clients/<owner>_client.go` (port в use-case,
   impl в `clients/`). Не найдено/не то состояние → `InvalidArgument`/`FailedPrecondition`; владелец
   недоступен → `Unavailable` (fail-closed для мутаций). Вызовы — service→service напрямую (не через api-gateway).
3. **Денормализованные зеркала** (показать имя/статус чужого ресурса) — output-only, помечены
   «source of truth = `<owner>.<Resource>`», обновляются на чтении, не источник истины, не на вход Create/Update.
4. **Удаление**: владелец не спрашивает consumer'ов (нет cross-service cascade). Consumer обязан
   грациозно переживать dangling-ref (деградированный статус, не паника). Жёсткие гарантии — только same-schema FK.
5. **Карта владельцев**: Geography (Region/Zone) → `kacho-geo`; IAM (Account/Project/User/SA/Group/Role/AccessBinding) → `kacho-iam`;
   Network/Subnet/SG/RouteTable/Address/Gateway/NetworkInterface → `kacho-vpc`; Instance/Disk/Image/Snapshot/DiskType → `kacho-compute`;
   Operation — per-service (общая `operations`-таблица из corelib).
6. Новое cross-domain ребро — фиксируется в `polyrepo.md` (runtime-edge); циклы запрещены.

## Cross-service saga-compensation — one-shot launch (B12, инициатор компенсирует)

Owner никогда не спрашивает consumer'ов на Delete (нет cross-service cascade) → при partial-fail
one-shot-саги (compute `Create.launch` спанит vpc IPAM-Address-alloc + NIC-`SetReference`-CAS,
storage boot-Volume, registry pull-grant) orphan-lease / half-attached NIC **некому реклеймить**
обратным вызовом. Компенсация живёт **на инициаторе**:

- **Compensation-outbox инициатора.** worker на launch-fail **ДО** пометки `Operation` error эмитит
  компенсирующие `Free`/`ClearReference` (vpc) и `Delete` (storage) в **собственный**
  `<svc>.compensation_outbox` (тот же writer-TX, at-least-once drainer) — НЕ «best-effort в горутине»
  (процесс может умереть между fail и cleanup). Идемпотентно (повторный `Free` уже свободного — no-op).
- **Sweeper-backstop у владельца.** vpc/storage reconciler освобождает lease/Volume, чей
  `usedBy°`-`Referrer` **DETACHED/dangling** дольше TTL (двойная защита: если compensation-outbox
  инициатора не доехал — sweeper подберёт). Backstop, не первичный путь.
- **Порядок компенсации — обратный allocation** (last-allocated → first-freed); каждый шаг сам
  идемпотентен, поэтому повтор всей цепочки безопасен.
- Оба пути (outbox + sweeper) **обязаны** landing до Phase-2 compute (owner GA gated). Тест: kill
  worker между alloc и Volume-Create → lease реклеймится (compensation ИЛИ sweeper), пул не течёт.

## Lease-recycle-on-delete — IPAM/pool-ресурсы (B17, атомарно)

Ресурс из **ограниченного пула** (Address/AddressPool, внешний VIP) обязан возвращать lease в
free-list **на КАЖДОМ пути высвобождения**, атомарно:

- **Delete ресурса И teardown-владельца** (NIC-detach, VIP-teardown LB) возвращают lease в
  `AddressPool` free-list **single-statement под row-lock** (не «прочитал→вернул» — TOCTOU, ban #10):
  `DELETE … RETURNING` / `UPDATE pool … WHERE …` в той же TX, что снятие ownership-CAS.
- **Без recycle** orphan-lease + saga-fail **исчерпывают пул** под параллельным e2e (`could not
  allocate` → phantom-ресурс → каскад). Recycle — не «на потом», это часть Delete-контракта.
- Тест (ban #12): concurrent alloc/free integration (ровно один writer выигрывает slot) +
  pool-exhaustion e2e-guard (N alloc → N delete → N alloc снова проходит, пул не деградировал).
- Тот же принцип — любой ресурс из ограниченного пула, не только IPAM.

## Authz-материализация owner-доступа — flat Contract-A (eventually-consistent)

Модель OpenFGA — **flat Contract-A**: CRUD-relations (`v_get/v_list/v_create/v_update/v_delete`) —
**DIRECT usersets per-object** (`[user, service_account, group#member]`), **БЕЗ** каскада
`<rel> from project|account`. Доступ subject'а к ресурсу материализуется **per-object** iam-реконсайлером
из AccessBinding'ов (не резолвится каскадом на request-path). Инварианты (выведены из owner-tuple раундов 2026-07):

- **Материализация НЕ на синхронном create-path.** owner-tuple эмитится intent'ом в writer-TX →
  sync-registrar (best-effort post-commit, window-оптимизация) + `fga_outbox` → register-drainer
  (at-least-once) + reconciler. `Operation.done` **НЕ** ждёт видимость (см. `api-conventions.md`); owner-доступ
  в кратком окне обеспечивается bounded client-retry. Confirm-gate на видимость — запрещён (ban #9, phantom).
- **Sync-FGA-write атомарен per-object** (all-or-nothing весь verb-набор объекта одним Write; идемпотентен —
  read-delta пишет только missing, pre-existing tuple не роняет batch). `v_update`-visible ⟹ полный набор visible.
- **role_rule_selectors для ВСЕХ materializing system-ролей** (не только owner): `edit`/`view`/`admin` +
  per-domain (`vpc.network.admin`…) проецируются в `role_rule_selectors` (миграция + boot-backfill
  `SyncAllSystemRoleSelectors`) — иначе binding невидим discovery и не материализует verbs (project-scoped
  creator получал 403 на своём ресурсе). `edit`-роль co-материализует `v_delete` с `v_update` (CRUD-editor
  удаляет что редактирует), но НЕ на hierarchy-scope (account/project) — anti-over-grant.
- **Containment транзитивен**: account-scoped binding матчит объект, вложенный в project ∈ account
  (резолв project→account на read-boundary; mirror-объект несёт `parent_project_id`, account добирается JOIN'ом).
- Верификация класса — **integration-матрица** (verb×role×scope: edit@project full-CRUD; owner@account на
  project+child-ресурсах; cross-account DENY), не 40-мин e2e. Trail: `obsidian/kacho/KAC/rbac-2026-*`.
- **Group#member — outbox-emit + EC, НЕ «co-commit» (B14).** Внешний FGA НЕ может атомарно
  co-commit'иться в DB-tx группы → member-tuple эмитится **intent'ом** в `fga_outbox` (writer-TX
  добавления/удаления члена) → at-least-once drainer → reconciler покрывает `Group#member`. Формулировка
  «co-commit» запрещена (подразумевает sync dual-write с дрейфом). Group-subject в AccessBinding
  резолвится в userset — материализация членства идёт **той же** EC-дисциплиной, что owner-tuple;
  `Operation.done` члена НЕ ждёт видимость tuple.
- **grant-by-email / UserInvitation — pending-intent + reconciler-remap (B15).** Grant на subject
  `EMAIL` (до первого login): tuple keyed на email **не матчит** enforcement (резолвит `usr-`), а keyed
  на будущий `usr-` не существует pre-login. Хранить как **pending email-grant intent** → reconciler
  ремапит в `usr-<id>`-tuple на **первом OIDC-login** (invitation-accept), в ограниченном окне.
  Conformance: `grant-by-email → login → access материализуется`; `revoke-before-login → clears pending
  intent` (не залипает). Серверный confirm-барьер запрещён (ban #9) — EC-окно, bounded client-retry.

## Placement-coherence — ВСЕ ресурсы связываются зонально ИЛИ регионально (обязательно)

Любая ссылка/привязка между двумя placement-scoped ресурсами **обязана** быть
**placement-coherent**. Нельзя связать ресурсы из разной зоны/региона.

- **Правило когерентности:**
  - зональный ↔ зональный — **та же `zone_id`**;
  - региональный ↔ региональный — **тот же `region_id`**;
  - зональный ↔ региональный — зона consumer'а **∈** регион peer'а (`zone.region_id == region_id`).
- **Anycast/regional исключение:** региональный (**anycast**) ресурс зоне-независим
  (`zone_id=''`, задан `region_id`) → из **зональной** проверки исключён **by construction**
  (сравнивать не с чем); остаётся региональная. Это и есть «исключение эникаст».
- **Placement-якорь = дискриминатор, не ad-hoc поля.** placement-несущий ресурс несёт
  `placement_type ∈ {ZONAL(zone_id) | REGIONAL(region_id)}`, взаимоисключающе, закреплено
  DB-CHECK: `(placement_type='ZONAL' AND zone_id<>'' AND region_id='') OR (placement_type='REGIONAL'
  AND zone_id='' AND region_id<>'')`. Каноничный якорь — **Subnet**; NIC/Address зону НЕ несут,
  наследуют через `subnet_id` (у REGIONAL-subnet зоны нет → адреса region-scoped, anycast).
- **Где энфорсить:**
  - within-service (обе строки в одной БД) — **на DB-уровне** внутри attach/link-CAS:
    `… AND (peer.placement_type='REGIONAL' OR peer.zone_id = $my_zone) …` (не software check-then-act, ban #10);
  - cross-service — **peer-validate на request-path**: owner несёт placement в **self-describing**
    payload и валидирует **свою** строку (fail-closed `Unavailable`; owner НЕ зовёт consumer — ацикличность).
- **Существование `zone_id`/`region_id`** — валидировать peer-вызовом `geo.v1.ZoneService.Get` /
  `RegionService.Get` (не локально), fail-closed. Пропуск (напр. непроверенная зона внешнего адреса) — баг.
- **Error-тексты** (часть контракта): mismatch зоны → `"<A> is in zone %s, <B> zone is %s"` →
  `FailedPrecondition`/`InvalidArgument`; mismatch региона → `"... must be in the same region"`.
- **Обязательные инстансы инварианта:** Instance ↔ Volume/Disk (та же зона) · Instance ↔ NIC(subnet)
  (та же зона, кроме REGIONAL/anycast subnet) · NLB(ZONAL) ↔ subnet/address (та же зона, включая
  v4/v6 dualstack в ОДНОЙ зоне) · NLB(REGIONAL) ↔ subnet/address (тот же регион + anycast) · Address ↔ subnet
  (зона наследуется). Новый placement-scoped ресурс/ссылка — добавляет свою coherence-проверку по этому правилу.
- **Тест (ban #12):** negative-кейс на zone/region mismatch → ожидаемый код + **точный текст**;
  anycast/REGIONAL-ветка → проходит (zone-check пропущен). Cross-family (v4/v6) same-zone — отдельный кейс.
