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
   Network/Subnet/SG/RouteTable/Address/Gateway/NetworkInterface → `kacho-vpc`; Instance/MachineType → `kacho-compute`;
   **Volume/Snapshot/Image/DiskType → `kacho-storage`** (блочное хранение; `volume_attachments` живёт у владельца-storage);
   LoadBalancer/Listener/TargetGroup → `kacho-nlb`; Registry/Repository/Tag → `kacho-registry`;
   Operation — per-service (общая `operations`-таблица из corelib).
   > [!note] Раскол compute→storage ЗАВЕРШЁН — предупреждение снято 2026-08-06
   > Здесь без малого две недели стояло предупреждение «раскол НЕ завершён», перечислявшее
   > живой дубль `Disk`/`Image`/`Snapshot`/`DiskType` у compute: свои таблицы, свои gRPC-сервисы,
   > 34 REST-маршрута, свои FGA-типы. **На дереве этого нет ни в одном из четырёх измерений**
   > (замер `ee679467`, предикат назван, чтобы его можно было повторить):
   >
   > - контрактов `Disk`/`Image`/`Snapshot`/`DiskType` в `proto/kacho/cloud/compute/v1/` — **ноль**;
   > - proto-сервисов у compute осталось **четыре**: `InstanceService`, `MachineTypeService`,
   >   `InternalMachineTypeService`, `InternalWatchService`;
   > - REST-маршрутов блочного хранения под доменом compute край не обслуживает — **ноль**
   >   (адреса здесь намеренно не воспроизводятся: цитата мёртвого маршрута читается как
   >   живое утверждение, и хук свежести справедливо считает её находкой — что он и сделал
   >   с первой редакцией этого абзаца);
   > - таблицы дропнуты миграциями `0013_drop_attached_disks`, `0021_drop_block_storage_duplicates`,
   >   `0022_drop_disk_types`.
   >
   > Правило «один владелец на тип ресурса» (п.1 выше) **выполняется**, и карта владельцев над
   > этим абзацем описывает код. Прежняя редакция требовала «не считать эту карту описанием
   > кода, пока предупреждение не снято» — снимаю его тем же порядком, каким оно ставилось:
   > замером, а не впечатлением.
   >
   > Урок, ради которого абзац остаётся вместо удаления: **предупреждение пережило свой предмет
   > и продолжало загружаться `@import`-ом в каждую сессию**. Такое утверждение опаснее обычной
   > устаревшей строки — оно читается чаще любой другой и звучит как действующее ограничение.
   > Найдено не мной: агент, писавший записку хранилища, едва не воспроизвёл «задвоенный
   > Snapshot» **по этому правилу**, перемерил и переписал. Предупреждение о незавершённой работе
   > обязано нести предикат снятия — иначе снять его некому.
   >
   > Историческая часть, которая остаётся верной: **данные переносить не требовалось** (директива
   > владельца 2026-07-27, облако не в проде). Гейт «счётчик строк на боевой базе перед удалением»
   > был снят осознанно; связующая таблица дропнута, а не перенесена (голый `DROP TABLE`, ноль
   > `INSERT`) — раскол изначально спроектирован без переноса.
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
- **Право на многих — ГРУППЕ, а не перечислением субъектов (B18).** Право, которое получает
  **больше одного** принципала **или** чей состав получателей может измениться, выдаётся
  **группе**; люди и служебные учётки добавляются в группу. Перечисление субъектов в самой
  привязке законно ровно для одного случая: получатель **один** и меняться не будет (служебная
  учётка модуля, чья личность и есть предмет выдачи). Правило связывает **наши** посевы,
  фикстуры и приёмки и действует **вперёд**; чужие привязки не переписываются. **Модели это не
  требует** — отношение членства уже принято каждым глаголом каждого типа (предикат: `awk
  '/define v_/{n++; if ($0 ~ /group#member/) g++} END{print n, g}'
  proto/kacho/cloud/iam/v1/fga_model.fga` → `99 99`; зеркало «объявления **без**
  `group#member`» → `0`). Причина — **цена изменения состава**: снять одного из группы это одна
  строка членства, снять одного из перечисления — снятие кортежей по всем объектам роли.
  Числа замера, обе стороны цены, перемещение поверхности выдачи и требование к вырожденному
  составу — **в приёмке**, `docs/specs/sub-phase-XC-9-grant-to-group-discipline-acceptance.md`
  (норма — §2.1, цена — §3, сценарии — §5); арендатору то же правило адресовано страницей
  продукта (`services/iam/docs-site/docs/api/access-binding.mdx`, §«Кому выдавать»).

  > [!note] Здесь стояло второе ИЗЛОЖЕНИЕ приёмки, а не ссылка на неё
  > Прежняя редакция воспроизводила из XC-9 шесть элементов сразу — правило, предикат с
  > зеркалом, пять чисел замера, перемещение поверхности выдачи, требование к вырожденному
  > составу и границы охвата, — и заканчивалась фразой «здесь она не пересказывается». Два
  > места об одном предмете разошлись на первом же уточнении числа: поправку пришлось вносить
  > в три документа одним заходом, и в одном из них жила ревизия замера, на которой харнесса
  > нет вовсе. Правило `@import`-ится в каждую сессию, поэтому неверная координата отсюда
  > читается чаще любой другой. Осталось то, что связывает **инженера**: сама норма, предикат
  > её применимости и адрес, по которому правят остальное.

## Outbox-drainer concurrency — ordering только на CLAIM-уровне (выведено 2026-07-24)

Ускорять drainer конкуренцией можно **ТОЛЬКО** после ответа на вопрос: **коммутативны ли
события этого outbox?**

- **Write-only outbox** (compute `fga_register_outbox` — только регистрация owner-tuple):
  события коммутативны → `ApplyConcurrency=N` безопасен «как есть».
- **Write+delete одного ключа** (iam `fga_outbox`: grant→WRITE и revoke/delete-stale→DELETE
  одного `(user,relation,object)`) — **НЕ коммутативны**. Наивный `ApplyConcurrency>1`
  переупорядочивает → delete применяется раньше write → **tuple выживает → authz over-grant /
  cross-account leak**. Corelib-godoc это прямо оговаривает: «включать ТОЛЬКО когда финальное
  состояние target СХОДИТСЯ независимо от порядка».
- **Group-by-key НА APPLY-УРОВНЕ НЕДОСТАТОЧЕН** (ловушка — выглядит как решение, но течёт):
  claim идёт `ORDER BY (attempt_count, id)`, поэтому transient-подтянутый предшественник
  (`attempt≥1`) сортируется **позже** свежего преемника (`attempt=0`) и они попадают в **разные
  claim-батчи** — внутрибатчевая группировка/re-sort про это ничего не знает. Cross-batch
  reorder → тот же leak.
- **Правильно — partition-head-only CLAIM**: не клеймить строку, пока в её партиции есть
  **доставляемый** unsent-предшественник с меньшим id:
  `AND NOT EXISTS (SELECT 1 FROM <t> p WHERE p.sent_at IS NULL AND p.attempt_count < MaxAttempts
  AND p.id < t.id AND p.<partition_expr> = t.<partition_expr>)`. Тогда per-partition FIFO держится
  **cross-batch И cross-replica** (незакоммиченный peer-claim в чужом snapshot всё ещё
  `sent_at IS NULL`; `FOR UPDATE OF t SKIP LOCKED` лочит только кандидата, коррелированный `p` —
  чистый read). Следствие: в снапшоте claimable максимум одна строка партиции ⇒ apply-группировка
  становится не нужна (LEAN). Обязателен partial-index `((<partition_expr>), id) WHERE sent_at IS NULL`.
- **Poison исключать из блокирующего набора** (`p.attempt_count < MaxAttempts`) — отравленная
  строка никогда не применится, блокировка на ней = **вечный wedge** партиции; leak-safe (отравленный
  WRITE не создал tuple).
- **Head-of-line wedge — осознанный размен leak-safety > liveness**: persistently-transient
  предшественник блокирует СВОЮ партицию (радиус — один объект), остальные дренятся; heals на
  восстановлении peer'а. Обязателен observability-контракт (per-partition WARN + table-wide
  oldest-pending gauge), иначе застрявший revoke тихий.
- **Тест (ban #12) обязан быть CROSS-BATCH**, а не внутрибатчевым: bumped-WRITE (`attempt=5`) +
  fresh-DELETE (`attempt=0`) + ≥`ApplyConcurrency` filler'ов ⇒ без фикса delete уезжает в ранний
  батч и tuple выживает (RED), с фиксом — absent (GREEN). Внутрибатчевый тест это НЕ ловит.

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
- **Связь «зона → её регион» берётся ТОЛЬКО резолвом у владельца, НИКОГДА не выводится из имени
  (директива владельца, non-negotiable).** Имя региона и имя зоны — **произвольные строки**; между ними
  нет гарантированного отношения. Поэтому регион берётся из `geo.v1.ZoneService.Get` (поле региона в
  ответе) ЛИБО из уже полученного авторитетного поля у самого ресурса (`Subnet.RegionID` и аналоги).
  **Запрещены как приём**: отрезание суффикса зоны, срез по последнему дефису, префиксное сравнение
  имён, допущение «зона начинается с имени региона», любая иная деривация разбором строки. Причина —
  это не косметика: строковая деривация **молча возвращает пустую строку** на ресурсе без зоны
  (REGIONAL/anycast), и проверка когерентности превращается в **no-op** — сравнение с пустой строкой
  проходит всегда, поэтому защита выглядит исполненной и не отвергает ничего. Реальный дефект этого
  класса (**`regionFromZone`** — деривация, **удалённая** из дерева; имя оставлено намеренно, оно
  связывает пункт с `polyrepo.md` §runtime-edges и с приёмкой XC-1, где этот прецедент цитируется)
  найден и снят 2026-07-25; поучительно в нём то, что рядом лежало неиспользуемое авторитетное
  поле, а комментарий утверждал, что «настоящая проверка остаётся за geo», которой в потоке не было —
  то есть три признака сразу: вывод из имени, тождественно-истинный предикат и ложный комментарий.
  Новое ребро к geo ради резолва — по общим правилам межсервисных вызовов (типизированный
  клиент, per-call timeout, fail-closed `UNAVAILABLE` на мутациях) + фиксация в `polyrepo.md`.
- **Instance ↔ NIC — та же зона (директива владельца).** Машина создаётся в своей зоне, и подсеть
  **каждого** её интерфейса обязана быть в той же зоне. Исключение — **эникаст**: REGIONAL-подсеть
  зоны не несёт, из зональной проверки исключена by construction, остаётся региональная когерентность.
  Проверка — **на пути запроса** (`Create`/`Update`), не отложенная в саму сагу запуска.
- **Error-тексты** (часть контракта): mismatch зоны → `"<A> is in zone %s, <B> zone is %s"` →
  `FailedPrecondition`/`InvalidArgument`; mismatch региона → `"... must be in the same region"`.
- **Обязательные инстансы инварианта:** Instance ↔ Volume/Disk (та же зона) · Instance ↔ NIC(subnet)
  (та же зона, кроме REGIONAL/anycast subnet) · NLB(ZONAL) ↔ subnet/address (та же зона, включая
  v4/v6 dualstack в ОДНОЙ зоне) · NLB(REGIONAL) ↔ subnet/address (тот же регион + anycast) · Address ↔ subnet
  (зона наследуется). Новый placement-scoped ресурс/ссылка — добавляет свою coherence-проверку по этому правилу.
- **Тест (ban #12):** negative-кейс на zone/region mismatch → ожидаемый код + **точный текст**;
  anycast/REGIONAL-ветка → проходит (zone-check пропущен). Cross-family (v4/v6) same-zone — отдельный кейс.

## Межсервисное намерение — контракт ПРИНИМАЮЩЕЙ стороны, а не факт эмиссии (выведено 2026-07-26)

Эмитировать намерение и **иметь его применённым** — разные вещи. Регистрация ресурса у владельца
прав гейтится **закрытым набором принимаемых отношений**, проверяемым ДО записи; отношение вне
набора отвергается целиком.

**Реальный инцидент (2026-07-26):** в очереди регистраций одного сервиса **ни одна строка никогда
не была доставлена** — все 198 с отказом в правах. Два сцепленных дефекта: (а) намерение одного из
ресурсов несло отношение, которого нет в закрытом наборе принимающей стороны, при том что его
собственный комментарий заявлял паритет с соседними ресурсами — то есть был скопирован вывод, а не
проверен факт; (б) **каждое** создание несло вдобавок отношение, зарезервированное за другим потоком
и тоже отвергаемое. Дренаж классифицирует отказ в правах как **временный** ⇒ короткое замыкание ⇒
строка никогда не помечается отправленной ⇒ claim партиции по голове **блокирует последующие строки
того же ресурса** на всё окно повторов (MaxAttempts×backoff).

**Почему это не замечали:** выдача по метке работала, потому что **синхронный** регистратор
короткого замыкания не делает. То есть весь очередной путь был мёртв, а наблюдаемое поведение
выглядело исправным. И у класса есть вторая, более тихая сторона: снятие регистрации отвергается
тем же способом, что и постановка, — а значит **отзыв прав не доезжает так же, как выдача**, только
без единого видимого симптома, потому что «работает» и «не отозвано» выглядят одинаково.

**How to apply:**
- **Тест обязан утверждать контракт ПРИНИМАЮЩЕЙ стороны** — что эмитировано отношение, которое
  владелец **примет**. Слабое «намерение эмитировано» остаётся зелёным ровно на этом дефекте.
- Отказ в правах от владельца — **НЕ transient**: повтор идентичного запроса не может пройти.
  Классифицировать как терминальный, иначе строка вечно блокирует свою партицию.
- При добавлении ресурса в очередь регистраций — сверить набор отношений с закрытым списком
  принимающей стороны, а не копировать у соседа «по аналогии» (у соседа могло быть верно, а
  комментарий про паритет — ложным).
- Наблюдаемость: «ноль доставленных строк за всю жизнь очереди» обязано быть заметно. Связано:
  [[checks-with-form-but-no-substance]].
