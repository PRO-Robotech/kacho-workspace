---
name: rule-data-integrity
description: "Целостность данных: within-service (DB-уровень) + cross-domain (peer-API)"
---

**Архив** (доводы, замеры, снятые редакции): `.claude/backup/data-integrity.md`

# Целостность данных: within-service (DB-уровень) + cross-domain (peer-API)

## Within-service инварианты — ТОЛЬКО на DB-уровне (ban #10)

arch-db-invariant-only · выражай DB-конструкцией, не software Get→check→Update · mapRepoErr + integration-тест на гонку · red: check-then-act в сервис-слое перед UPDATE
db-fk-same-db · `FK REFERENCES <t>(id) ON DELETE {RESTRICT|CASCADE|SET NULL}` · ЗАВЕСТИ db-fk-same-db · red: проверка существования кодом
db-unique · `UNIQUE` / `CREATE UNIQUE INDEX` · ЗАВЕСТИ db-unique · red: SELECT-then-INSERT
db-partial-unique · partial `UNIQUE … WHERE <cond>` · ЗАВЕСТИ db-partial-unique · red: полный UNIQUE или software-проверка
db-exclude-range · `EXCLUDE USING gist (… WITH &&)` · ЗАВЕСТИ db-exclude-range · red: сравнение диапазонов в Go
db-check · `CHECK (…)` · ЗАВЕСТИ db-check · red: валидация только в сервисе
db-cas · `UPDATE … WHERE <expected-state> RETURNING …` + проверка кардинальности · 0 rows → sentinel · red: безусловный UPDATE после Get
db-xmin-occ · `xmin::text` snapshot + `UPDATE … WHERE xmin::text=$exp` · 0 rows → конфликт · red: перезапись без сверки снимка
db-skip-locked · `FOR UPDATE SKIP LOCKED LIMIT 1` + `DELETE … RETURNING` · один writer выигрывает slot · red: SELECT свободного, затем DELETE
db-select-for-update · `SELECT … FOR UPDATE` перед merge+write · ЗАВЕСТИ db-select-for-update · red: merge без блокировки
sqlstate-to-grpc · маппь только в сервис-слое: 23503→FailedPrecondition · 23505→AlreadyExists/FailedPrecondition · 23514→InvalidArgument · 23P01→FailedPrecondition · sqlstatehome_test.go · red: решение о классе отказа вне единственного дома
no-pgx-leak · не выпускай наружу, отдавай фиксированный INTERNAL · sqlstatehome_test.go (ветка по умолчанию) · red: текст драйвера в gRPC-ответе
cas-attach-template · делай одним `UPDATE … WHERE id=$id AND (<owner>='' OR <owner>=$new) RETURNING` · 0 rows → `pgx.ErrNoRows` → FailedPrecondition · red: Get→проверка→UPDATE
no-unique-backstop · не заводи UNIQUE-индекс как backstop к CAS · ЗАВЕСТИ no-unique-backstop · red: UNIQUE, отвергающий законный multi-attach

### Чек-лист нового ссылочного поля / инварианта

concurrent-integration-test · закрой integration-тестом (testcontainers) с параллельными горутинами: ровно одна TX проходит, прочие получают ожидаемый sentinel · ЗАВЕСТИ concurrent-integration-test · red: мёрж с unit-тестом вместо него

## Cross-domain ссылки (owner-сервис / consumer-сервис)

single-owner-per-type · держи ровно одного владельца с каноническим CRUD/read-API · ЗАВЕСТИ single-owner-per-type · red: mirror-строка или cross-service FK у потребителя
consumer-validates-by-owner · храни TEXT без FK и валидируй через API владельца на Create/Update · вызов клиента в use-case · red: ссылка принята без проверки у владельца
typed-client-layering · ходи типизированным клиентом `internal/clients/<owner>_client.go`, port в use-case · usecaselayout_test.go · red: http/grpc-вызов из слоя репозитория
crossdomain-refusal-codes · не найдено → InvalidArgument · не то состояние → FailedPrecondition · владелец недоступен → Unavailable (fail-closed на мутациях) · таблица кодов use-case · red: мутация прошла при недоступном владельце
service-to-service-direct · ходи service→service напрямую · ребро в polyrepo.md · red: вызов через api-gateway
mirror-output-only · держи output-only, с пометкой source of truth, обновляй на чтении · ЗАВЕСТИ mirror-output-only · red: зеркало на входе Create/Update
delete-no-cascade · не спрашивай потребителей; потребитель переживает dangling-ref деградированным статусом · тест на dangling-ref · red: паника или cross-service cascade
owner-map · Region/Zone→geo · Account/Project/User/SA/Group/Role/AccessBinding→iam · Network/Subnet/SG/RouteTable/Address/Gateway/NIC→vpc · Instance/MachineType→compute · Volume/Snapshot/Image/DiskType→storage · LB/Listener/TargetGroup→nlb · Registry/Repository/Tag→registry · Operation — per-service · ЗАВЕСТИ owner-map · red: второй владелец типа
new-edge-in-polyrepo · фиксируй в `polyrepo.md` §runtime-edges · polyrepo.md §runtime-edges · red: цикл или ребро вне карты
warning-needs-removal-predicate · неси предикат снятия в устаревающем предупреждении · ЗАВЕСТИ warning-needs-removal-predicate · red: предупреждение без предиката снятия

## Saga-компенсация у инициатора

compensation-outbox-initiator · компенсируй у инициатора: `<svc>.compensation_outbox` в том же writer-TX ДО пометки Operation error, at-least-once drainer, идемпотентно · тест kill-worker · red: best-effort горутина после fail
sweeper-backstop · держи sweeper-backstop: освобождай lease/Volume с DETACHED/dangling Referrer дольше TTL · reconciler владельца · red: backstop как первичный путь или его отсутствие
compensation-reverse-order · обратный allocation (last-allocated → first-freed), каждый шаг идемпотентен · ЗАВЕСТИ compensation-reverse-order · red: компенсация в прямом порядке
compensation-kill-test · докажи тестом: kill worker между alloc и Volume-Create → lease реклеймится, пул не течёт · integration-тест · red: зелёный без убийства worker'а
compensation-landing-phase2 · оба пути компенсации обязаны landing до Phase-2 compute (owner GA gated) · ЗАВЕСТИ compensation-landing-phase2 · red: Phase-2 GA без обоих путей

## Lease-recycle-on-delete — IPAM/pool-ресурсы (B17, атомарно)

lease-recycle-every-path · возвращай в free-list на КАЖДОМ пути высвобождения одним оператором под row-lock, в той же TX, что ownership-CAS · `DELETE … RETURNING` / `UPDATE pool …` · red: «прочитал → вернул»
lease-test · докажи concurrent alloc/free (один writer берёт slot) + N alloc → N delete → N alloc снова проходит · integration + e2e-guard · red: тест без параллелизма

## Authz-материализация owner-доступа — flat Contract-A (eventually-consistent)

fga-flat-contract-a · flat Contract-A: CRUD-глаголы — DIRECT usersets per-object `[user, service_account, group#member]`, без каскада `<rel> from project|account` · `modelcanonpin.go`, `modelrelationproducer_test.go` · red: каскадный резолв на пути запроса
materialization-async · эмить intent'ом в writer-TX → sync-registrar (best-effort) + `fga_outbox` → drainer + reconciler · outboxeventdictionary_test.go · red: синхронный dual-write в FGA на create-path
no-confirm-gate-ban9 · не гейти на видимость eventually-consistent эффекта; окно закрывает bounded client-retry · consoleconfirmprobe_test.go · red: confirm-барьер на видимость (ban #9, phantom)
fga-write-atomic-per-object · пиши весь verb-набор объекта одним Write, all-or-nothing, идемпотентно (read-delta пишет только missing) · v_update visible ⟹ набор visible · red: частично записанный набор глаголов
role-rule-selectors-all · проецируй в `role_rule_selectors` миграцией + boot-backfill `SyncAllSystemRoleSelectors` · ЗАВЕСТИ role-rule-selectors-all · red: binding невидим discovery, creator получает 403 на своём ресурсе
edit-comaterializes-delete · co-материализуй `v_delete` вместе с `v_update`, но НЕ на hierarchy-scope · ЗАВЕСТИ authz-edge-matrix · red: delete на account/project-scope
containment-transitive · считай транзитивным: account-scoped binding матчит объект в project ∈ account; mirror несёт `parent_project_id` · резолв на read-boundary · red: binding не матчит вложенный объект
authz-edge-matrix · верифицируй матрицу verb×role×scope newman через край (testing-newman.md#qa-access): edit@project full-CRUD · owner@account на project+child · cross-account DENY; запись набора глаголов в хранилище — Go integration (testing-newman.md#edge-internal-consequence) · ЗАВЕСТИ authz-edge-matrix · red: доступ края утверждён только Go-пробой
group-member-ec · эмить intent'ом в `fga_outbox` в writer-TX членства → at-least-once drainer → reconciler; слово «co-commit» запрещено · Operation.done члена не ждёт видимость · red: sync dual-write в FGA из tx группы
grant-by-email-pending · храни pending email-grant intent, ремапь в `usr-<id>` reconciler'ом на первом OIDC-login · conformance: grant→login→доступ; revoke-before-login чистит intent · red: tuple, keyed на email, либо серверный confirm-барьер
grant-to-group · выдавай ГРУППЕ, людей и SA добавляй в группу; перечисление субъектов законно только при единственном неизменном получателе · ЗАВЕСТИ grant-to-group · red: перечисление субъектов в привязке
membership-declared-everywhere · держи ноль объявлений глаголов без `group#member` · awk '/define v_/{n++; if ($0 ~ /group#member/) g++} END{print n-g}' proto/kacho/cloud/iam/v1/fga_model.fga → 0 · red: глагол без членства

## Outbox-drainer — claim по голове партиции

drainer-commutativity-question · включай только ответив «коммутативны ли события этой очереди» · internal/repohygiene/outboxorderinggate_test.go · red: `ApplyConcurrency>1` без ответа
write-only-outbox-parallel · `ApplyConcurrency=N` безопасен · outboxorderinggate_test.go · red: ApplyConcurrency сужен «на всякий случай» без замера
write-delete-noncommutative · считай НЕкоммутативной · outboxorderinggate_test.go · red: наивный `ApplyConcurrency>1` → tuple выживает → over-grant
groupbykey-insufficient · не считай решением: claim `ORDER BY (attempt_count, id)` разводит предшественника и преемника по разным батчам · outboxorderinggate_test.go · red: внутрибатчевая re-sort вместо claim-предиката
partition-head-claim · не клейми, пока в партиции есть доставляемый предшественник: `AND NOT EXISTS (SELECT 1 FROM <t> p WHERE p.sent_at IS NULL AND p.attempt_count < MaxAttempts AND p.id < t.id AND p.<part>=t.<part>)` + partial-index `((<part>), id) WHERE sent_at IS NULL` · `outboxorderinggate_test.go`, `outboxpendingindexperservice_test.go` · red: claim без предиката головы партиции
poison-not-blocking · исключай из блокирующего набора (`p.attempt_count < MaxAttempts`) · outboxorderinggate_test.go · red: вечный wedge партиции на poison
wedge-observability · обязателен per-partition WARN + table-wide oldest-pending gauge · outboxobservedgate_test.go · red: застрявший revoke без сигнала
crossbatch-ordering-test · делай CROSS-BATCH: bumped-WRITE (attempt=5) + fresh-DELETE (attempt=0) + ≥ApplyConcurrency filler'ов · RED без фикса, GREEN с фиксом · red: внутрибатчевый тест

## Placement-coherence — зона/регион

placement-coherent · делай placement-coherent · ЗАВЕСТИ placement-coherent · red: связь ресурсов из разных зоны/региона
coherence-rule · зональный↔зональный — та же `zone_id` · региональный↔региональный — тот же `region_id` · зональный↔региональный — `zone.region_id == region_id` · проверка в attach/link-CAS · red: сравнение не проведено или проведено с пустой строкой
anycast-exception · исключай из зональной проверки by construction (`zone_id=''`), оставляй региональную · ветка anycast в тесте · red: зональная проверка на anycast
placement-discriminator · несёт `placement_type ∈ {ZONAL(zone_id)|REGIONAL(region_id)}` взаимоисключающе, закреплено DB-CHECK `(placement_type='ZONAL' AND zone_id<>'' AND region_id='') OR (placement_type='REGIONAL' AND zone_id='' AND region_id<>'')` · ЗАВЕСТИ placement-discriminator · red: ad-hoc поля без дискриминатора
placement-anchor-subnet · каноничный — Subnet; NIC/Address зону не несут, наследуют через `subnet_id` · ЗАВЕСТИ placement-anchor-subnet · red: своя колонка зоны у NIC/Address
coherence-enforce-db · энфорси когерентность на DB-уровне внутри attach/link-CAS: `… AND (peer.placement_type='REGIONAL' OR peer.zone_id = $my_zone) …` · ЗАВЕСТИ coherence-enforce-db · red: software check-then-act
coherence-enforce-peer · peer-validate на пути запроса, владелец несёт placement в self-describing payload и валидирует СВОЮ строку · fail-closed Unavailable · red: владелец зовёт потребителя (цикл)
zone-existence-peer · валидируй peer-вызовом `geo.v1.ZoneService.Get` / `RegionService.Get`, fail-closed · вызов в Create/Update · red: локальная проверка или её пропуск
no-region-from-zone-name · бери ТОЛЬКО резолвом у владельца (`geo.v1.ZoneService.Get`) либо из авторитетного поля ресурса (`Subnet.RegionID`); деривация из имени запрещена (директива владельца) · вниманием (директива владельца, non-negotiable) · red: отрезание суффикса, срез по дефису, префиксное сравнение имён; предикат, тождественно истинный на пустой строке
instance-nic-same-zone · требуй ту же зону для подсети каждого интерфейса (исключение — REGIONAL-подсеть) на пути запроса Create/Update · negative-кейс · red: проверка отложена в сагу запуска
coherence-error-texts · часть контракта: зона — `"<A> is in zone %s, <B> zone is %s"` → FailedPrecondition/InvalidArgument · регион — `"... must be in the same region"` · newman-кейс на точный текст · red: свой текст отказа
coherence-instances · Instance↔Volume · Instance↔NIC(subnet) · NLB(ZONAL)↔subnet/address (включая v4/v6 dualstack в одной зоне) · NLB(REGIONAL)↔subnet/address · Address↔subnet · новый placement-scoped ресурс дописывает свою · red: инстанс без проверки
coherence-test · negative на zone/region mismatch → код + точный текст · anycast-ветка проходит · cross-family v4/v6 same-zone отдельным кейсом · ЗАВЕСТИ coherence-test · red: только положительный путь

## Межсервисное намерение — контракт приёмника

intent-closed-set · гейть закрытым набором принимаемых отношений, проверяемым ДО записи; отношение вне набора отвергай целиком; набор сверяй со списком принимающей стороны, а не с соседом · ЗАВЕСТИ intent-closed-set · red: отношение вне набора в очереди
intent-test-receiver · утверждай контракт ПРИНИМАЮЩЕЙ стороны — что эмитировано отношение, которое владелец ПРИМЕТ · ЗАВЕСТИ intent-test-receiver · red: зелёное «намерение эмитировано»
permission-denied-terminal · классифицируй терминальным, не transient · ЗАВЕСТИ permission-denied-terminal · red: повтор до MaxAttempts блокирует партицию навсегда
intent-verify-set · сверяй набор отношений нового ресурса со списком принимающей стороны, не копируй по аналогии у соседа · ЗАВЕСТИ intent-verify-set · red: набор скопирован у соседа без сверки
intent-observability · «ноль доставленных строк за всю жизнь» обязано быть заметно · outboxobservedgate_test.go · red: мёртвая очередь при исправном наблюдаемом поведении

## Счётчик потолка живёт РЯДОМ С РЕСУРСОМ, а величина — у владельца величин (решение 2026-08-15)

counter-in-insert-tx · списывай в ТОЙ ЖЕ транзакции, что вставка ресурсной строки; распределённой транзакции в стеке нет · ЗАВЕСТИ counter-in-insert-tx · red: «спросить» и «списать» разведены по сети

## Данные СТЕНДА заводятся посевом, а не миграцией (решение владельца 2026-08-17)

stand-data-by-seed · заводи посевом, вызываемым подъёмом стенда; в миграцию не кладя ни при каких условиях · git grep -ln 'INSERT INTO' -- 'services/*/internal/migrations/*.sql', каждое попадание — справочник продукта · red: данные окружения в миграции
seed-predicate · суди попадание вопросом «обязана ли строка существовать у арендатора, развернувшего продукт у себя» — нет значит посев · ЗАВЕСТИ seed-predicate · red: строка окружения принята за справочник без ответа на предикат
seed-separate-file · отдельный файл, вызываемый рецептом подъёма стенда · ЗАВЕСТИ seed-separate-file · red: вставка в миграции
seed-on-conflict-no-target · `ON CONFLICT DO NOTHING` БЕЗ указания цели · ЗАВЕСТИ seed-on-conflict-no-target · red: указанная цель пропускает частичную уникальность и EXCLUDE
seed-guard-occupancy · ограждай вставку проверкой занятости · ЗАВЕСТИ seed-guard-occupancy · red: строка появилась, а её содержимое нет
seed-verbatim-identity · бери идентичность строки дословно у соседнего посева · `standanycastpoolidentity_test.go`, `seedaddressplanparity_test.go` · red: два автора у одного слота
seed-parity-gate · держи гейтом, не комментарием · seedaddressplanparity_test.go · red: расхождение блоков, не покрывающих друг друга
seed-condition-step · отдельный шаг полосы · шаг «условие создано — полоса внешнего адреса пригодна» в console-e2e.yml · red: «стенд не готов» подано как «продукт сломан»
seed-asserts-capability · утверждай СПОСОБНОСТЬ, а не существование строки · .github/workflows/console-e2e.yml:693 · red: пул существует с пустым списком свободных адресов
