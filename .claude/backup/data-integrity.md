# Архив: data-integrity.md

Снято 2026-09-20. Норма живёт в `.claude/rules/data-integrity.md`.
Здесь: классы C (процесс вокруг кода) и D (замеры, доводы, отменённое, пересказы),
КРОМЕ записей, несущих названный гейт, — те остались нормами в корпусе.

## Within-service — чек-лист, слитый с уже нормированным

- `chk-fk` — чек-лист п.1 «Ссылка на ресурс в той же БД → FK… Никогда software-only» —
  дубликат нормы `db-fk-same-db`.
- `chk-partial-unique` — чек-лист п.2 «Условная уникальность → partial `UNIQUE … WHERE`» —
  дубликат `db-partial-unique`.
- `chk-cas` — чек-лист п.3 «Состояние меняется конкурирующими путями → атомарный CAS» —
  дубликат `db-cas`/`cas-attach-template`.
- `chk-sqlstate` — чек-лист п.4 «SQLSTATE→gRPC в `mapRepoErr`/serviceerr» —
  дубликат `sqlstate-to-grpc`.

## Cross-domain — довод и урок из note «Раскол compute→storage ЗАВЕРШЁН»

- `split-done-note` — весь замер по четырём измерениям (контракты/сервисы/маршруты/миграции),
  которым закрыт спор «раскол не завершён»: ноль `Disk`/`Image`/`Snapshot`/`DiskType` у compute
  в proto, маршрутах, при дропнутых миграциями таблицах. Свидетельство, что правило «один
  владелец на тип» (норма `single-owner-per-type`) уже выполняется кодом.
- `note-second-telling` — второй [!note] той же врезки: урок о том, что пересказ приёмки в двух
  местах расходится на первом уточнении числа (случай XC-9, три документа правкой одним заходом).
  Императив этого блока — «предупреждение обязано нести предикат снятия, иначе снять его
  некому» — вынесен нормой `warning-needs-removal-predicate` (осталась в корпусе).

## Cross-service saga-compensation — контекст инцидента

- `saga-context` — вводный абзац секции: почему owner не спрашивает consumer'ов на Delete и кто
  реклеймит orphan-lease/half-attached NIC при partial-fail one-shot-саги (мотивировка перед
  нормами `compensation-outbox-initiator`/`sweeper-backstop`/`compensation-reverse-order`).

## Lease-recycle — довод и обобщение

- `lease-why` — довод «без recycle orphan-lease + saga-fail исчерпывают пул под параллельным
  e2e» — обоснование уже нормированного `lease-recycle-every-path`.
- `lease-any-pool` — «тот же принцип — любой ресурс из ограниченного пула, не только IPAM»,
  слито в `lease-recycle-every-path` (общность механизма, не отдельная норма).

## Authz — приёмка XC-9 и её цена

- `grant-group-cost` — довод «цена изменения состава»: снять одного из группы — одна строка
  членства, снять одного из перечисления — снятие кортежей по всем объектам роли. Обоснование
  нормы `grant-to-group`.
- `xc9-addresses` — адреса приёмки: `docs/specs/sub-phase-XC-9-grant-to-group-discipline-acceptance.md`
  (норма §2.1, цена §3, сценарии §5); арендатору — `kaname`/`docs/content/api/access-binding.mdx`
  §«Кому выдавать».
- `authz-integration-matrix` — снята 2026-09-23 решением владельца «проверка края всегда достигается
  через newman тесты»: прежний red «40-мин e2e вместо матрицы» ставил Go-матрицу на место края; норма
  переименована в `authz-edge-matrix`, держатель `edit-comaterializes-delete` — туда же.

## Placement-coherence — разбор инцидента `regionFromZone`

- `region-derive-why` — разбор снятого 2026-07-25 дефекта `regionFromZone` (деривация региона из
  имени зоны): три признака сразу — вывод из имени, тождественно-истинный предикат на пустой
  строке, ложный комментарий про «настоящую проверку у geo». Обоснование нормы
  `no-region-from-zone-name`.

## Межсервисное намерение — инцидент

- `intent-incident` — «Реальный инцидент (2026-07-26)»: очередь регистраций одного сервиса, 198
  строк без доставки, два сцепленных дефекта (отношение вне закрытого набора + отношение чужого
  потока) и почему это не было заметно (синхронный путь выдачи маскировал мёртвый очередной).
  Обоснование норм `intent-closed-set`/`intent-verify-set`/`permission-denied-terminal`.

## Счётчик потолка — раздел СНИМАЕТСЯ (решение владельца 2026-09-16)

Квоты выпиливаются полностью (`kacho#2190` закрыта этим исходом); раздел — свидетельство
принятого тогда решения, не предписание. Заводить по нему новую квоту, стадию или витрину —
нарушение. Единственное, что остаётся нормой из всего раздела, — `counter-in-insert-tx`
(осталась в корпусе); всё прочее архивируется целиком:

- `quota-retired` — сам факт снятия, предикат готовности снятия (`git grep -il quota`), порядок
  снятия по `polyrepo.md` (corelib → kaname → kacho).
- `quota-axis-table` — таблица «аналогия с кортежами прав точна для величины и ломается для
  счётчика» (форма факта, повтор записи, референт ремонта, цена опоздания, величина ошибки).
- `quota-consequences` — три следствия обособленности счётчика (реконсиляция не отменяет
  принятое решение; пересчёт внутри iam невыразим топологией; у счётчика есть конкуренция за
  единицу, у прав — нет).
- `quota-queue-noncommutative` — частный случай очереди `+1`/`−1` как некоммутативной; общее
  правило уже нормировано в `write-delete-noncommutative`/`partition-head-claim`.
- `quota-unify` — РЕШЕНИЕ 2026-08-15 и раздел «что обязано быть единым без переезда счётчика»
  (каталог видов, актуальность величины, производитель отказа, сигнатура списания, чтение,
  витрина) — форма снимаемой подсистемы.
- `quota-revisit-predicate` — предикат пересмотра решения (новый домен с ресурсом в чужой базе;
  потолок на сумму по нескольким доменам) — привязан к предмету, который снимается, действующей
  силы не имеет.
- `quota-no-mechanism-note` — находка по дороге: механизма актуальности величины не существует
  (строка учёта не обновляется никогда, `ON CONFLICT DO NOTHING`, отметка синхронизации
  неподвижна в пяти миграциях); заведено задачей уровня P0.

## Данные СТЕНДА — доводы и замеры

- `seed-why` — довод «почему не вкусовщина»: миграция применяется везде включая боевую поставку,
  применённую миграцию не правят (ban #5). Обоснование `stand-data-by-seed`.
- `seed-measure-note` — замер 2026-08-17: предикат `git grep -ln 'INSERT INTO'` даёт 45
  попаданий на `origin/main` (iam 27 · vpc 7 · nlb 4 · compute 4 · storage 2 · registry 1); это
  список кандидатов, а не 45 нарушений — сплошная адъюдикация не проводилась.
- `seed-table-header` — вводная фраза перед таблицей «как выглядит правильный посев» (эталоны:
  каталог geo, каталог хранения, полоса внешних адресов) — сама таблица разошлась по нормам
  `seed-separate-file`…`seed-condition-step`.
- `seed-607` — инцидент #607: проба консоли была красна с первого прогона и блокировала два MR,
  потому что полосу внешних адресов заводил посев одного набора проб, а другая полоса его не
  звала; починка — посевом, не миграцией.

## Снято 2026-09-26 (ws#780): сжатие корпуса под потолок check-06 на сведении волны 0 с 771

Сведённое дерево `778` × `771` дало 221 997 знаков при потолке 200 000 (решение владельца
2026-09-19); потолок не поднимался. Ниже — ПРЕЖНИЕ редакции строк, сжатых этим изменением,
дословно: доводы, замеры и пересказы канона уходят сюда, норма (id · императив · держатель ·
red) осталась в корпусе под тем же id.

**no-region-from-zone-name** — прежняя редакция:

no-region-from-zone-name · бери ТОЛЬКО резолвом у владельца (`geo.v1.ZoneService.Get`) либо из авторитетного поля ресурса (`Subnet.RegionID`); деривация из имени запрещена (директива владельца) · вниманием (директива владельца, non-negotiable) · red: отрезание суффикса, срез по дефису, префиксное сравнение имён; предикат, тождественно истинный на пустой строке

**concurrent-integration-test** — прежняя редакция:

concurrent-integration-test · закрой integration-тестом (testcontainers) с параллельными горутинами: ровно одна TX проходит, прочие получают ожидаемый sentinel · ЗАВЕСТИ concurrent-integration-test · red: мёрж с unit-тестом вместо него

**grant-by-email-pending** — прежняя редакция:

grant-by-email-pending · храни pending email-grant intent, ремапь в `usr-<id>` reconciler'ом на первом OIDC-login · conformance: grant→login→доступ; revoke-before-login чистит intent · red: tuple, keyed на email, либо серверный confirm-барьер

**stand-data-by-seed** — прежняя редакция:

stand-data-by-seed · заводи посевом, вызываемым подъёмом стенда; в миграцию не кладя ни при каких условиях · git grep -ln 'INSERT INTO' -- 'services/*/internal/migrations/*.sql', каждое попадание — справочник продукта · red: данные окружения в миграции

**intent-closed-set** — прежняя редакция:

intent-closed-set · гейть закрытым набором принимаемых отношений, проверяемым ДО записи; отношение вне набора отвергай целиком; набор сверяй со списком принимающей стороны, а не с соседом · ЗАВЕСТИ intent-closed-set · red: отношение вне набора в очереди

**intent-verify-set** — прежняя редакция:

intent-verify-set · сверяй набор отношений нового ресурса со списком принимающей стороны, не копируй по аналогии у соседа · ЗАВЕСТИ intent-verify-set · red: набор скопирован у соседа без сверки

(второй проход того же сжатия)

**partition-head-claim** — прежняя редакция:

partition-head-claim · не клейми, пока в партиции есть доставляемый предшественник: `AND NOT EXISTS (SELECT 1 FROM <t> p WHERE p.sent_at IS NULL AND p.attempt_count < MaxAttempts AND p.id < t.id AND p.<part>=t.<part>)` + partial-index `((<part>), id) WHERE sent_at IS NULL` · `outboxorderinggate_test.go`, `outboxpendingindexperservice_test.go` · red: claim без предиката головы партиции

**placement-discriminator** — прежняя редакция:

placement-discriminator · несёт `placement_type ∈ {ZONAL(zone_id)|REGIONAL(region_id)}` взаимоисключающе, закреплено DB-CHECK `(placement_type='ZONAL' AND zone_id<>'' AND region_id='') OR (placement_type='REGIONAL' AND zone_id='' AND region_id<>'')` · ЗАВЕСТИ · red: ad-hoc поля без дискриминатора

(второй проход того же сжатия)

**authz-edge-matrix** — прежняя редакция:

authz-edge-matrix · верифицируй матрицу verb×role×scope newman через край (testing-newman.md#qa-access): edit@project full-CRUD, owner@account на project+child, cross-account DENY; запись набора глаголов в хранилище — Go integration (testing-newman.md#edge-internal-consequence) · ЗАВЕСТИ · red: доступ края утверждён только Go-пробой

**no-region-from-zone-name** — прежняя редакция:

no-region-from-zone-name · бери ТОЛЬКО резолвом у владельца (`geo.v1.ZoneService.Get`) либо из авторитетного поля (`Subnet.RegionID`); деривация из имени запрещена (директива владельца) · вниманием · red: отрезание суффикса, срез по дефису, префиксное сравнение имён; предикат, истинный на пустой строке

## Снято 2026-09-26 (ws#786): сжатие корпуса под потолок check-06 на сведении 786 с 771

Сведённое дерево `786` × `771` (волна-0 в волну-3) дало 208 847 знаков при потолке 200 000
(решение владельца 2026-09-19); потолок не поднимался. Нормы каскада закрытия и снятия влитых
веток (786) и требования волны-0 (771) сохранены под теми же id; ниже — ПРЕЖНИЕ редакции строк,
сжатых этим изменением, дословно (редакция сведения до сжатия).

arch-db-invariant-only · выражай DB-конструкцией, не software Get→check→Update · mapRepoErr + integration-тест на гонку · red: check-then-act в сервис-слое перед UPDATE
sqlstate-to-grpc · маппь только в сервис-слое: 23503→FailedPrecondition · 23505→AlreadyExists/FailedPrecondition · 23514→InvalidArgument · 23P01→FailedPrecondition · sqlstatehome_test.go · red: решение о классе отказа вне единственного дома
concurrent-integration-test · закрой integration-тестом (testcontainers) с параллельными горутинами: проходит ровно одна TX, прочие получают ожидаемый sentinel · ЗАВЕСТИ · red: мёрж с unit-тестом вместо него
single-owner-per-type · держи ровно одного владельца с каноническим CRUD/read-API · ЗАВЕСТИ · red: mirror-строка или cross-service FK у потребителя
consumer-validates-by-owner · храни TEXT без FK и валидируй через API владельца на Create/Update · вызов клиента в use-case · red: ссылка принята без проверки у владельца
typed-client-layering · ходи типизированным клиентом `internal/clients/<owner>_client.go`, port в use-case · usecaselayout_test.go · red: http/grpc-вызов из слоя репозитория
mirror-output-only · держи output-only, с пометкой source of truth, обновляй на чтении · ЗАВЕСТИ · red: зеркало на входе Create/Update
delete-no-cascade · не спрашивай потребителей; потребитель переживает dangling-ref деградированным статусом · тест на dangling-ref · red: паника или cross-service cascade
owner-map · Region/Zone→geo · Account/Project/User/SA/Group/Role/AccessBinding→iam · Network/Subnet/SG/RouteTable/Address/Gateway/NIC→vpc · Instance/MachineType→compute · Volume/Snapshot/Image/DiskType→storage · LB/Listener/TargetGroup→nlb · Registry/Repository/Tag→registry · Operation — per-service · ЗАВЕСТИ · red: второй владелец типа
compensation-outbox-initiator · компенсируй у инициатора: `<svc>.compensation_outbox` в том же writer-TX ДО пометки Operation error, at-least-once drainer, идемпотентно · тест kill-worker · red: best-effort горутина после fail
sweeper-backstop · держи sweeper-backstop: освобождай lease/Volume с DETACHED/dangling Referrer дольше TTL · reconciler владельца · red: backstop как первичный путь или его отсутствие
compensation-kill-test · докажи тестом: kill worker между alloc и Volume-Create → lease реклеймится, пул не течёт · integration-тест · red: зелёный без убийства worker'а
lease-recycle-every-path · возвращай в free-list на КАЖДОМ пути высвобождения одним оператором под row-lock, в той же TX, что ownership-CAS · `DELETE … RETURNING` / `UPDATE pool …` · red: «прочитал → вернул»
lease-test · докажи concurrent alloc/free (один writer берёт slot) + N alloc → N delete → N alloc снова проходит · integration + e2e-guard · red: тест без параллелизма
materialization-async · эмить intent'ом в writer-TX → sync-registrar (best-effort) + `fga_outbox` → drainer + reconciler · outboxeventdictionary_test.go · red: синхронный dual-write в FGA на create-path
fga-write-atomic-per-object · пиши весь verb-набор объекта одним Write, all-or-nothing, идемпотентно (read-delta пишет только missing) · v_update visible ⟹ набор visible · red: частично записанный набор глаголов
role-rule-selectors-all · проецируй в `role_rule_selectors` миграцией + boot-backfill `SyncAllSystemRoleSelectors` · ЗАВЕСТИ · red: binding невидим discovery, creator получает 403 на своём ресурсе
edit-comaterializes-delete · co-материализуй `v_delete` вместе с `v_update`, но НЕ на hierarchy-scope · ЗАВЕСТИ authz-edge-matrix · red: delete на account/project-scope
containment-transitive · считай транзитивным: account-scoped binding матчит объект в project ∈ account; mirror несёт `parent_project_id` · резолв на read-boundary · red: binding не матчит вложенный объект
group-member-ec · эмить intent'ом в `fga_outbox` в writer-TX членства → at-least-once drainer → reconciler; слово «co-commit» запрещено · Operation.done члена не ждёт видимость · red: sync dual-write в FGA из tx группы
grant-by-email-pending · храни pending email-grant intent, ремапь в `usr-<id>` reconciler-ом на первом OIDC-login · conformance: grant→login→доступ, revoke-before-login чистит intent · red: tuple на email либо серверный confirm-барьер
grant-to-group · выдавай ГРУППЕ, людей и SA добавляй в группу; перечисление субъектов законно только при единственном неизменном получателе · ЗАВЕСТИ · red: перечисление субъектов в привязке
partition-head-claim · не клейми, пока в партиции есть доставляемый предшественник: `NOT EXISTS` неотправленной строки той же `<part>` с меньшим id и `attempt_count < MaxAttempts`, плюс partial-index `((<part>), id) WHERE sent_at IS NULL` · `outboxorderinggate_test.go`, `outboxpendingindexperservice_test.go` · red: claim без предиката головы партиции
wedge-observability · обязателен per-partition WARN + table-wide oldest-pending gauge · outboxobservedgate_test.go · red: застрявший revoke без сигнала
crossbatch-ordering-test · делай CROSS-BATCH: bumped-WRITE (attempt=5) + fresh-DELETE (attempt=0) + ≥ApplyConcurrency filler'ов · RED без фикса, GREEN с фиксом · red: внутрибатчевый тест
placement-coherent · делай placement-coherent · ЗАВЕСТИ · red: связь ресурсов из разных зоны/региона
anycast-exception · исключай из зональной проверки by construction (`zone_id=''`), оставляй региональную · ветка anycast в тесте · red: зональная проверка на anycast
coherence-enforce-db · энфорси когерентность на DB-уровне внутри attach/link-CAS: `… AND (peer.placement_type='REGIONAL' OR peer.zone_id = $my_zone) …` · ЗАВЕСТИ · red: software check-then-act
zone-existence-peer · валидируй peer-вызовом `geo.v1.ZoneService.Get` / `RegionService.Get`, fail-closed · вызов в Create/Update · red: локальная проверка или её пропуск
no-region-from-zone-name · регион бери ТОЛЬКО резолвом у владельца (`geo.v1.ZoneService.Get`) либо из авторитетного поля (`Subnet.RegionID`); деривация из имени запрещена (директива владельца) · вниманием · red: срез суффикса или по дефису, префиксное сравнение имён; предикат, истинный на пустой строке
instance-nic-same-zone · требуй ту же зону для подсети каждого интерфейса (исключение — REGIONAL-подсеть) на пути запроса Create/Update · negative-кейс · red: проверка отложена в сагу запуска
intent-closed-set · гейть закрытым набором принимаемых отношений ДО записи; отношение вне набора отвергай целиком; набор сверяй со списком принимающей стороны, а не с соседом · ЗАВЕСТИ · red: отношение вне набора в очереди
intent-test-receiver · утверждай контракт ПРИНИМАЮЩЕЙ стороны — что эмитировано отношение, которое владелец ПРИМЕТ · ЗАВЕСТИ · red: зелёное «намерение эмитировано»
permission-denied-terminal · классифицируй терминальным, не transient · ЗАВЕСТИ · red: повтор до MaxAttempts блокирует партицию навсегда
intent-verify-set · набор отношений нового ресурса сверяй со списком принимающей стороны (`intent-closed-set`) · ЗАВЕСТИ · red: набор скопирован у соседа без сверки
counter-in-insert-tx · списывай в ТОЙ ЖЕ транзакции, что вставка ресурсной строки; распределённой транзакции в стеке нет · ЗАВЕСТИ · red: «спросить» и «списать» разведены по сети
stand-data-by-seed · заводи посевом при подъёме стенда, в миграцию — никогда · git grep -ln 'INSERT INTO' -- 'services/*/internal/migrations/*.sql': каждое попадание — справочник продукта · red: данные окружения в миграции
seed-predicate · суди попадание вопросом «обязана ли строка существовать у арендатора, развернувшего продукт у себя» — нет значит посев · ЗАВЕСТИ · red: строка окружения принята за справочник без ответа на предикат
seed-guard-occupancy · ограждай вставку проверкой занятости · ЗАВЕСТИ · red: строка появилась, а её содержимое нет
seed-verbatim-identity · бери идентичность строки дословно у соседнего посева · `standanycastpoolidentity_test.go`, `seedaddressplanparity_test.go` · red: два автора у одного слота
seed-parity-gate · держи гейтом, не комментарием · seedaddressplanparity_test.go · red: расхождение блоков, не покрывающих друг друга
seed-asserts-capability · утверждай СПОСОБНОСТЬ, а не существование строки · .github/workflows/console-e2e.yml:693 · red: пул существует с пустым списком свободных адресов

## Снято 2026-10-01 (ws-sync-main): сжатие корпуса под потолок check-06 на сведении `main` с `771`

Сведённое дерево `main` × `771` дало 215 385 знаков при потолке 200 000 (решение владельца
2026-09-19); потолок не поднимался. Норма (id · императив · держатель · red) осталась в корпусе
под тем же id; ниже — ПРЕЖНИЕ редакции сжатых строк, дословно.

partition-head-claim · не клейми при доставляемом предшественнике в партиции: `NOT EXISTS` неотправленной строки той же `<part>` с меньшим id и `attempt_count < MaxAttempts`, плюс partial-index `((<part>), id) WHERE sent_at IS NULL` · `outboxorderinggate_test.go`, `outboxpendingindexperservice_test.go` · red: claim без предиката головы партиции

authz-edge-matrix · матрицу verb×role×scope верифицируй newman через край (testing-newman.md#qa-access): edit@project full-CRUD, owner@account на project+child, cross-account DENY; запись набора глаголов в хранилище — Go integration · ЗАВЕСТИ · red: доступ края утверждён только Go-пробой

no-region-from-zone-name · регион — ТОЛЬКО резолвом у владельца (`geo.v1.ZoneService.Get`) либо из авторитетного поля (`Subnet.RegionID`); деривация из имени запрещена (директива владельца) · вниманием · red: срез суффикса, префиксное сравнение имён; предикат, истинный на пустой строке
