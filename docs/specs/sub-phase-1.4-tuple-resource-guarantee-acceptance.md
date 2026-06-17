# Sub-phase 1.4 (EPIC: Fleet-wide 100% resource↔IAM-owner-tuple guarantee) — Acceptance

> **Статус:** DRAFT — **ревизия 3** (gate: `acceptance-reviewer` → ✅ APPROVED; ban #1 / `.claude/rules/ai-tooling.md` §lifecycle gate 1). Перед стартом `superpowers:writing-plans` проставить KAC-номер вместо `KAC-TBD`.
> **Ревизия 3 (2026-06-18):** панель — 4/5 lens APPROVED, все 4 blocker'а ревизии 2 (B1-B4) подтверждены закрытыми; security-lens нашла ОДИН новый — **BLOCKER-1** (closed здесь): apps-SA **не имеет** SEC-C `fga_writer`-grant'а (`service_account:<sva-apps>#fga_writer@iam_fgaproxy:system`) → `RegisterResource` fail-close'ит (`InternalIAMService.RegisterResource` → `PermissionDenied`, `internal_iam/handler.go:171`, `internal_iam_service.proto:128` «Нет relation → PermissionDenied») → S1 «100% Applications получают owner-tuple» нереализуемо self-inflicted'но. Sweep non-blocker'ов N1/N3/N4/N5/N6. **Ground-truth (сверено):** SEC-C seed `kacho-iam/internal/migrations/0009_sec_c_module_sa_least_priv.sql` провиженит SA+tuple `fga_writer@iam_fgaproxy:system` ТОЛЬКО для vpc/compute/nlb (+vpc-operator/api-gateway БЕЗ fga_writer); **kacho-apps отсутствует во ВСЕХ iam-миграциях** (grep — пусто). 0009 — APPLIED (ban #5: НЕ редактировать) → нужна **НОВАЯ** sequential iam-миграция, зеркалящая форму 0009 (детерминированный `sva`-id, anchor system-user/account, `fga_outbox`-emit). Детали — в шапках затронутых разделов (S1, §3 glossary, §4).
> **Ревизия 2 (2026-06-18):** закрыты 4 blocker'а adversarial-5-lens-панели — B1 (kacho-geo никогда не категоризирован → «100% флота» был тихо неисчерпывающим; добавлен OUT-BY-DESIGN для geo + DiskType + AddressPool), B2 (AccessBinding — канонический owner-GRANT IAM — был пропущен и мискатегоризирован: он УЖЕ атомарен in-tx `access_binding/create.go:166`, выделен в отдельный backstop-only класс), B3 (live iam `fga_outbox`-drainer `serve.go:532-547` не получал S0-backstop — добавлен), B4 (inverse-orphan GC без anti-race инварианта → TOCTOU self-inflicted access-loss — добавлен анти-race + сценарий 1.4-07b с `-race`-тестом). Sweep non-blocker'ов N2-N6. Детали — в шапках затронутых разделов.
> **Дата:** 2026-06-18
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` (единственный gate APPROVED; заказчик — только финальный smoke/e2e, S4)
> **Эпик/тикет:** KAC-TBD (epic «Fleet-wide 100% resource↔IAM-owner-tuple guarantee»; per-repo subtask в **`kacho-corelib`** / **`kacho-apps`** / **`kacho-iam`** / `kacho-vpc` / `kacho-compute` / `kacho-nlb` / `kacho-api-gateway` / `kacho-deploy` / `kacho-workspace`).
> **Расширяет:** `sub-phase-W1.1-fga-outbox-drainer-acceptance.md` (corelib `outbox/drainer` — APPROVED 2026-05-23, W1.1 merged; этот эпик добавляет backstop-слой поверх него) + SEC-D/SEC-A owner-tuple-механику vpc/compute/nlb.
> **Источник требования (заказчик, дословно):** «при создании ресурса нужно создавать тапл в iam на ресурс, чтобы появился доступ; если этого не делать — доступ пропадёт. Надо 100% гарантировать что не будет кейса когда ресурс создали а тапл обвалился.»
> **Образцы формата:** `sub-phase-W1.1-fga-outbox-drainer-acceptance.md`, `sub-phase-1.2-iam-operations-acceptance.md`.
> **Ground-truth (сверено ревизией 2):** `kacho-corelib/outbox/drainer/{drainer.go:43-45,internal.go:174-249}` (claim/mark CAS keyed by **`id` bigint**, не `sequence_no`; `MaxAttempts=10`); `kacho-apps/internal/repo/kacho/pg/application.go:211(Insert),262(Delete)`; `kacho-apps/cmd/apps/main.go:90-122` (только `ProjectService.Get`+`Check`). **kacho-iam:** `access_binding/create.go:166-172` (`EmitRelationWrite` co-commit в writer-tx, **УЖЕ атомарен** — «fga_outbox INSERT commits iff the binding INSERT commits (запрет #10)»); `seed/bootstrap_admin.go:90,133,173` (cluster-admin bootstrap — **УЖЕ in-tx** `BeginTx→fga_outbox INSERT→Commit`, НЕ регрессировать); best-effort post-commit (мигрировать): `account/create.go:157-171(WriteHierarchyTuple "Non-fatal" owner + SEC-L cluster-pointer)`, `project/create.go:115-130`, `group/create.go:106-110`, `role/create.go:114-117`, `service_account/create.go:107-110`, `user/internal_upsert.go:406-476(writeBootstrapTuples best-effort post-commit — WriteTuples:446 + 5× WriteHierarchyTuple:456-475)`; `relationhook/relationhook.go:50(WriteHierarchyTuple — live iam own-resource path)`; `internal_iam/handler.go:184(WriteCreatorTuple — DEAD RPC, нет live-caller; nlb заменил его register-outbox'ом, Issue N5)`; live drainer `cmd/kacho-iam/serve.go:532-547(Table:"kacho_iam.fga_outbox", MaxAttempts:10)`; `internal/migrations/0001_initial.sql:432,440(kacho_iam.fga_outbox: id bigint PK, event_type CHECK ('fga.tuple.write','fga.tuple.delete'))`. **canonical SEC-D:** `kacho-vpc/internal/migrations/0006_fga_register_outbox.sql(id bigint PK, event_type CHECK ('fga.register','fga.unregister'), без resource_kind/jsonb-CHECK)`, `network/create.go:202,230,236`; `kacho-compute/internal/migrations/0010*(compute_fga_register_outbox: id BIGSERIAL PK + resource_kind/resource_id + event_type CHECK)`, `no_direct_fga_test.go:17(TestSEC_D_07_NoDirectFGAInClients)`; `kacho-nlb/internal/migrations/0002_fga_register_outbox.sql(id bigint PK + resource_kind/resource_id + event_type CHECK + jsonb_typeof(payload)='object' CHECK)`. **out-by-design:** `kacho-geo/internal/migrations/0001_initial.sql:35-49(geo_outbox — audit-only, sequence_no PK, event_type CREATED/UPDATED/DELETED, НЕТ project_id, НЕТ RegisterResource)`, `geo/cmd/kacho-geo/serve.go:147-149(Region/Zone admin CRUD ТОЛЬКО :9091)`. **BLOCKER-1 (apps-SA fga_writer least-priv):** `kacho-iam/internal/migrations/0009_sec_c_module_sa_least_priv.sql` сидит `service_account:<sva>#fga_writer@iam_fgaproxy:system` (через `fga_outbox`, event_type `'fga.tuple.write'`, payload `jsonb_build_object('user','relation','object')`) ТОЛЬКО для vpc/compute/nlb (vpc-operator/api-gateway — БЕЗ fga_writer); детерминированный `sva`-id = `'sva'||substr(md5('kacho-<svc>'),1,17)`, anchor system-user/account = `'usr'/'acc'||substr(md5('kacho-system'),1,17)` (`ON CONFLICT DO NOTHING`); **`kacho-apps` отсутствует во всех iam-миграциях** (0001-0015, grep — пусто). `RegisterResource`-gate: `internal_iam/handler.go:126(WithResourceRegistrar),171(нет relation → PermissionDenied)`; `internal_iam_service.proto:128`. Applier-классификация (compute/nlb-форма, образец для apps): `kacho-compute/internal/clients/iam_register_applier.go:110-111(InvalidArgument → ErrPermanent)`, `kacho-nlb/internal/clients/iam/register_applier.go:149-153,167-172(InvalidArgument → ErrPermanent; PermissionDenied/Unavailable → raw transient — retry, НЕ poison)` — без apps-grant'а доставка либо poison'ит (если IAM вернёт permanent-класс), либо **transient-retry-forever** (PermissionDenied не landing'ится никогда; `outbox_oldest_pending_age_seconds` растёт безгранично) → S1-deliverable нереализуем. **N3 stale-comment:** `serve.go:526` / `bootstrap_admin.go:122` пишут «migration 0002» про `fga_outbox`, но он в `0001_initial.sql` (док цитирует 0001 верно — repo-comment-fix запланирован в S2). **N4 apps payload-форма:** compute-shape (`kacho-compute/internal/migrations/0010_fga_register_outbox.sql`: `id BIGSERIAL PK`, `resource_kind`/`resource_id` TEXT, `payload JSONB`, event_type CHECK `'fga.register'`/`'fga.unregister'`; payload-набор `{tuples:[…]}` / `{project_id}`).

---

## Обзор

При создании любого **tenant/project-scoped** ресурса в Kachō в OpenFGA (через kacho-iam) должен появиться **owner-tuple** (project-hierarchy и/или owner self-grant) — без него ReBAC-`Check` для владельца возвращает `no path` → доступ к собственному только что созданному ресурсу пропадает (defect «403 on own freshly-created resource»). Сегодня гарантия **не сплошная**: vpc/compute/nlb атомарны (SEC-D — register-intent co-commit в той же `pgx.Tx`, что и INSERT ресурса), **kacho-apps не имеет механизма вообще** (100% Application создаются без owner-tuple), **kacho-iam пишет hierarchy/owner-tuple большинства own-resources best-effort post-commit** (теряются на любом transient-сбое) — **за двумя исключениями, которые УЖЕ атомарны**: `AccessBinding.Create` (in-tx `EmitRelationWrite` → `fga_outbox`, `access_binding/create.go:166`) и cluster-admin `bootstrap_admin.go:90` (in-tx `BeginTx→fga_outbox→Commit`). При этом **live iam `fga_outbox`-drainer** (`serve.go:532-547`, `MaxAttempts:10`) — это та же leaf-точка доставки, в которую сходятся ВСЕ hierarchy/owner/AccessBinding-tuple, и **corelib-drainer** (общий код) теряет tuple навсегда при затяжном transient-сбое IAM (`MaxAttempts=10` poison'ит даже сетевую недоступность), не имеет reconciler/метрик и тихо стартует без drainer'а.

**Перечисление флота (исчерпывающе-по-построению — аудируемо, не «100% на словах»):** мутирующих consumer-доменов ровно **6 in-scope** + **1 out-by-design**:
- **in-scope** (создают tenant/project-scoped ресурс → нужен owner-tuple): `{ kacho-corelib (foundation-drainer/reconciler), kacho-apps (greenfield), kacho-iam (own-resources), kacho-vpc, kacho-compute, kacho-nlb (backstop) }`;
- **out-by-design** (нет create-resource→owner-tuple-флоу, в scope НЕ входят, §6): **`kacho-geo`** (Region/Zone — глобальные cluster-scoped admin-only каталоги, Internal* :9091, нет `project_id` / нет tenant-владельца; authz через cluster-level `system_viewer`/`system_admin`; `geo_outbox` — **audit-only**, нет `RegisterResource`), плюс две Internal-admin-проекции внутри in-scope-сервисов: **`DiskType`** (compute Internal-каталог, нет `project_id`) и **`AddressPool`** (vpc Internal-admin, нет owner-tuple-флоу).

«100%» относится к in-scope-множеству; out-by-design-множество явно исключено с обоснованием (§3 glossary + §6) — поэтому утверждение исчерпывающе и аудируемо, а не тихо-неполно (anti-pattern «false-exhaustive», 1.2-failure-class).

Эпик доводит гарантию до **100% по in-scope-флоту** единым механизмом — **transactional-outbox-everywhere (Kachō SEC-D)**: атомарность достигается **локально** (INSERT ресурса + register-INTENT-строка co-commit в ОДНОЙ `pgx.Tx`), а доставка `RegisterResource`/`UnregisterResource` к kacho-iam :9091 (mTLS) — at-least-once, идемпотентно (FGA-409→success), с backstop'ом (reconciler + transient-no-poison + метрики + fail-closed boot-gate), причём backstop включает и **live iam `fga_outbox`-drainer** (D-5/D-6/D-7/D-8 применяются к нему наравне с register-drainer'ами vpc/compute/nlb).

**Предусловие apps→iam register-edge (BLOCKER-1, S1):** доставка `RegisterResource` к kacho-iam проходит через least-priv-gate (`fga_writer` @ `iam_fgaproxy:system`, `security.md` §least-priv, SEC-A/SEC-C). SEC-C seed (`0009`) выдаёт этот grant ТОЛЬКО vpc/compute/nlb — **kacho-apps его не имеет**, поэтому его register-intent fail-close'ится у IAM (`PermissionDenied`) и owner-tuple никогда не доходит → S1 «100% Applications получают owner-tuple» **нереализуемо** без явного провижена apps-SA-grant'а. Эпик добавляет НОВУЮ iam-миграцию (зеркало 0009, ban #5: 0009 НЕ редактируем), сидящую `service_account:<sva-apps>#fga_writer@iam_fgaproxy:system` (S1-step). Тот же `fga_writer`-провижен обязателен для **любого будущего сервиса**, добавляемого во флот SEC-D — без него register-edge мёртв на первой попытке. Документ описывает **только внешнее наблюдаемое поведение** (gRPC-коды, наблюдаемый эффект на доступ, состояние outbox-строк, метрики, boot-поведение) и НЕ реализацию (SQL/Go). Сценарии трассируются в имена integration-/newman-тестов через ID `1.4-<NN>`. Стандартные конвенции (`data-integrity.md` ban #10 outbox-in-tx; `polyrepo.md` SEC-A/SEC-D, ацикличность; `security.md` mTLS :9091 + authz; `api-conventions.md` мутации→`Operation`) — нормативны, в тело не дублируются, только ссылками (§1).

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| **ban #1** (`00-kacho-core.md`) — кодирование только после APPROVED | данный doc — gate; статус выше DRAFT |
| **ban #4 / #8** — нет cross-service cascade / database-per-service | НЕТ ACID-tx через FGA-store + service-DB; атомарность только локальная (intent-row в той же БД) — основание отказа от «tuple-first» (§Дизайн-обоснование) |
| **ban #9** — мутации возвращают `Operation` (async) | happy-path 1.4-09/1.4-30 (Create→`Operation`, polling `OperationService.Get`) |
| **ban #10** (`data-integrity.md`) — within-service инварианты на DB-уровне; outbox-emit в той же tx | intent-row co-commit в `pgx.Tx` (1.4-01); exactly-once claim — атомарный CAS `UPDATE … WHERE sent_at IS NULL AND attempt_count < $max … FOR UPDATE SKIP LOCKED RETURNING` (1.4-03, 1.4-21) |
| **ban #5** — не редактировать применённую миграцию | `kacho_iam.fga_outbox` (0001), `kacho_vpc.fga_register_outbox` (0006), `kacho_nlb.fga_register_outbox` (0002) **не трогаем**; kacho-apps — НОВАЯ миграция (greenfield); corelib reconciler/metrics — без новой common-миграции (работает с существующими per-service outbox-таблицами) |
| **ban #11** — без тех-долга/TODO «на потом» | каждый sub-phase закрывает свой кусок гарантии полностью; «follow-up» как обоснование пропуска теста запрещён |
| **ban #12 / #13** — строгий TDD, RED до кода, integration+newman в том же PR | DoD каждого sub-phase: RED→GREEN пара; concurrent race-тест для CAS обязателен (`testing.md`) |
| `data-integrity.md` §cross-domain — consumer ссылается на owner по id, валидирует через API владельца; владелец недоступен → fail-closed для мутаций (`Unavailable`); consumer грациозно переживает dangling-ref | 1.4-08 (fail-closed boot/Create при недоступном IAM), 1.4-07/07a/07b (inverse-orphan GC + anti-race); register-edge — consumer→iam, не наоборот |
| `data-integrity.md` §«CAS не TOCTOU» — состояние, меняемое конкурирующими путями (create vs GC-unregister), защищается анти-race инвариантом, не point-in-time check-then-act | inverse-orphan GC (1.4-07) Unregister'ит только при (a) нет pending/recent register-intent для id **и** (b) ресурс отсутствует через grace-window / 2 последовательных прохода; concurrent-re-create-vs-GC (1.4-07b) с обязательным `-race` integration-тестом (ban #10) |
| `polyrepo.md` §SEC-A/SEC-D + ацикличность | каждое register-ребро — **consumer→iam** (`InternalIAMService.RegisterResource`/`Unregister`, Internal-only :9091); новое ребро `apps→iam fgaproxy` фиксируется в polyrepo.md (S4); циклов нет — iam никого из consumer'ов не зовёт обратно |
| `security.md` §AuthN+AuthZ ВЕЗДЕ + §Internal-vs-external (ban #6) | `RegisterResource`/`Unregister` — Internal-only :9091, mTLS, per-RPC authz-Check (least-priv `fga_writer` @ `iam_fgaproxy:system`); drainer — внутренняя background-goroutine, не expose'ит surface |
| `architecture.md` + skill `evgeniy` — clean-arch; reconciler/drainer — горизонтальный concern в corelib | corelib `outbox/reconciler` + метрики + boot-gate (S0); per-service applier/wiring — нативно в репо |
| `vault.md` §trail | DoD S4: `packages/corelib-outbox-*`, `resources/apps-application`, `edges/apps-to-iam-fgaproxy` (новый), `edges/iam-to-openfga-*`, `KAC/KAC-<N>.md` |

---

## 2. Дизайн-обоснование (выбранный механизм + опровержение идеи заказчика — НЕ переоткрывать после APPROVED)

> Этот раздел фиксирует вердикт RLM-панели (per-service map → gap-synthesis → adversarial mechanism judge-panel). Записан для трассируемости — **не релитигировать**.

### 2.1 Выбранный механизм — transactional-outbox-everywhere (Kachō SEC-D), score 88 RECOMMENDED

Атомарность достигается **локально**: INSERT ресурса + register-INTENT-строка (`fga.register` / `fga.unregister`, payload — owner-tuple-данные incl. `project_id`) co-commit'ятся в **ОДНОЙ** `pgx.Tx`. Либо обе записи в БД, либо ни одной — нет окна «ресурс есть, intent потерян». Доставку к kacho-iam (`InternalIAMService.RegisterResource`/`UnregisterResource`, :9091, mTLS) выполняет corelib-drainer **at-least-once**, идемпотентно (FGA-409 на уже-существующий tuple → `ErrAlreadyApplied` → success). Это **уже** канонический паттерн vpc/compute/nlb (`kacho-vpc/internal/migrations/0006_fga_register_outbox.sql`, `network/create.go:202,230,236`); эпик распространяет его на kacho-apps + kacho-iam-own-resources и добавляет backstop.

### 2.2 Идея заказчика «создать tuple в IAM первым, потом ресурс, откатить tuple при ошибке» — REJECTED, score 8

Дословное предложение: «сначала write owner-tuple в IAM, затем INSERT ресурса; при сбое INSERT — compensating UnregisterResource (rollback tuple)». **Отвергнуто** по трём причинам:

1. **Нет ACID-tx, охватывающей FGA-store IAM и БД сервиса** (`ban #4/#8`: database-per-service, нет cross-service cascade/tx). «Сначала tuple, потом ресурс» — это распределённый dual-write без атомарности.
2. **Компенсирующий `UnregisterResource` сам может упасть** (тот же ненадёжный сетевой hop к IAM) → окно сбоя **перемещается** в «orphan-tuple-без-ресурса» = **access-grant leak** (выданный доступ к несуществующему/чужому id), что строго хуже, чем потерянный grant (отказ в доступе fail-closed безопаснее, чем лишний grant). Плюс добавляется второй ненадёжный hop на горячем write-path.
3. Это **регрессия** к уже убитому best-effort dual-write (GitHub Issue N5, чей фикс и есть SEC-D в vpc): «direct-FGA write после commit ресурса терял tuple навсегда на transient-сбое».

**Вывод панели:** атомарность обязана быть **локальной** (один commit одной БД), а cross-service-доставка — **асинхронной at-least-once с идемпотентностью**, не синхронным two-phase dual-write. Outbox-everywhere это и даёт.

### 2.3 Фиксированные дизайн-решения (предлагаются автором; подлежат approve ревьюером — затем НЕ переоткрывать)

| ID | Решение | Обоснование |
|---|---|---|
| D-1 | **Механизм — SEC-D outbox-everywhere** (§2.1); «tuple-first+rollback» отвергнут (§2.2). | Вердикт панели 88 vs 8. |
| D-2 | **kacho-apps — полный greenfield SEC-D**: новая таблица `kacho_apps.fga_register_outbox` (+ NOTIFY-триггер `kacho_apps_fga_register_outbox`), `Insert` переводится на реальную `pgx.Tx` (INSERT → `EmitRegister('fga.register', payload{resource_type:"apps_application", id, project_id})` → Commit), `Delete` — `EmitUnregister`, IAM `RegisterResource`-client + corelib-drainer в `cmd/apps/main.go`. | Сегодня `application.go:211` — bare `pool.QueryRow` (нет tx, нет outbox), `:262` Delete без Unregister → 100% Applications без owner-tuple. Зеркалит vpc canonical. |
| D-3 | **kacho-iam own-resources — split на 2 класса.** (a) **best-effort post-commit → мигрировать в in-tx `fga_outbox`-emit** (зеркало `EmitAuditEvent`/`EmitRelationWrite` co-commit): account/project/group/service_account/role Create (`WriteHierarchyTuple` "Non-fatal" сегодня: `account/create.go:157-171`, `project/create.go:115-130`, `group/create.go:106`, `role/create.go:114`, `service_account/create.go:107`) + user-bootstrap `internal_upsert.writeBootstrapTuples` (`:406-476` — `WriteTuples:446` + 5× `WriteHierarchyTuple`, best-effort post-commit) + соответствующие owner-self-grant tuple. (b) **УЖЕ-атомарные → НЕ трогать (backstop-only):** `AccessBinding.Create` (in-tx `EmitRelationWrite`, `access_binding/create.go:166`) и cluster-admin `seed/bootstrap_admin.go:90` (in-tx `BeginTx→fga_outbox→Commit`) — миграция S2 **НЕ должна их регрессировать**. **Новой миграции не нужно** — `fga_outbox` существует (0001), event_type-литералы `'fga.tuple.write'`/`'fga.tuple.delete'`. | Сегодня класс (a) пишет tuple после `DoWithWriteTx` («Non-fatal») → теряется на любом FGA-сбое; класс (b) уже корректен (`access_binding/create.go:166` явно «fga_outbox INSERT commits iff the binding INSERT commits (запрет #10)»). Слепой «iam own-resources = НЕТ атомарности» был ошибкой — ground-truth опровергает. |
| D-4 | **Owner-self-grant / creator-style tuple (account-owner `account/create.go:160`, bootstrap owner self-grant `internal_upsert.go:456-475`) — in-tx outbox-emit ОБЯЗАТЕЛЕН как primary; reconciler-backfill для него НЕ применим.** Subject «кто создал / кто владелец-user» не реконструируется из состояния ресурса (FGA-subject не хранится в ресурсной строке как backfillable значение). Reconciler-backfill (derive-from-state) допустим **только** для project-hierarchy-tuple (реконструируется из хранимого `project_id`), и только как safety-net для legacy never-enqueued строк. **NB:** `WriteCreatorTuple` (`internal_iam/handler.go:184`) — **dead RPC** (нет live-caller; nlb заменил его register-outbox'ом, Issue N5); инвариант D-4 формулируется на **live**-путях owner-self-grant, не на нём. | Если owner-self-grant потерян и его нет в outbox — он невосстановим; единственная гарантия — co-commit его intent в той же tx (D-3a). |
| D-5 | **corelib transient-класс «never-poison»**: ошибки `Unavailable`/timeout/conn-drop (IAM-down) НИКОГДА не poison'ят (unbounded backoff, `attempt_count`-gate их не отравляет); poison'ит **только** `ErrPermanent` (4xx-non-409, decode-fail). | Сегодня `drainer.go:43-45` `MaxAttempts=10` + transient `default`-ветка (`internal.go:464` commit `attempt_count++`) → >10 consecutive transient-сбоев делают строку **неклеймимой** (CAS `attempt_count < MaxAttempts`) = PERMANENT tuple loss из-за временной недоступности. Это прямо противоречит требованию «100% гарантия». |
| D-6 | **corelib `outbox/reconciler` sub-package** (новый): (a) re-drive poisoned (по команде/периодически сбрасывает `attempt_count`/`last_error` для повторной доставки); (b) derive-from-state backfill (enumerate ресурсные строки без applied-intent → re-emit; **только** project-hierarchy, legacy never-enqueued — D-4); (c) inverse-orphan GC (tuple, чей ресурс удалён → `Unregister`). | Сегодня reconciler-под-пакета нет (`outbox/` = `emit/event/writer` + `drainer/`). Backstop против застрявших/потерянных intent. |
| **D-6c** | **inverse-orphan GC — anti-race инвариант (НЕ TOCTOU).** GC эмитит `Unregister` для id **только** при выполнении ОБОИХ условий: **(a)** в outbox нет pending/recent `register`-intent для этого id (никакой Create «в полёте»/недавно), **И** **(b)** ресурс отсутствует устойчиво — через grace-window / два последовательных прохода (или generation/tombstone-guard), а не в одной point-in-time выборке. Конкурентный Create co-commit'ит свой register-intent → его intent ВСЕГДА «побеждает» проход GC (условие (a) ловит его). | Чисто point-in-time existence-check race-prone: GC читает «ресурс отсутствует» (stale), затем Unregister'ит tuple, который легитимный concurrent re-Create только что co-commit'нул → **self-inflicted owner access-loss** (ровно тот дефект, ради убийства которого существует эпик). Зеркалит `data-integrity.md` §«CAS не TOCTOU». Обязателен `-race` concurrent integration-тест (1.4-07b). |
| D-7 | **corelib метрики**: `outbox_backlog_depth`, `outbox_oldest_pending_age_seconds`, `outbox_poisoned_total` (per outbox-table label). | Сегодня метрик нет; poison/застой — silent (только Warn-лог). Делает «обвал tuple» наблюдаемым (алерт), а не тихим. |
| D-8 | **fail-closed boot-gate**: сервис, принимающий мутирующие Create, ОБЯЗАН иметь запущенный IAM-connected drainer. Флаг `--require-iam` (env `KACHO_<SVC>_REQUIRE_IAM=true`): нет drainer'а/peer'а → сервис **отказывает в мутирующих Create** (`Unavailable`/`FailedPrecondition`) либо отказывается от boot. | Сегодня drainer-off — silent Warn → ресурсы создаются без tuple молча. Gate превращает «тихий обвал» в явный отказ (fail-closed, безопаснее grant-leak). |
| D-9 | **Backstop для vpc/compute/nlb + live iam `fga_outbox`-drainer — БЕЗ изменения атомарности и без новой миграции**: только reconciler + fail-closed wiring + метрики. vpc/compute/nlb — S3; **iam-drainer (`serve.go:532-547`) — в S2** (тот же D-5/D-6/D-7/D-8 backstop, что и register-drainer'ы: reconciler re-drive + backlog/oldest/poisoned-метрики + `--require-iam` boot-gate). Их co-commit (vpc/compute/nlb SEC-D; iam AccessBinding/bootstrap_admin) уже корректен; structural-gate `TestSEC_D_07_NoDirectFGAInClients`-аналог сохраняется. | Не ломать рабочий канонический путь; добавить наблюдаемость и boot-gate. **iam — leaf, куда сходятся ВСЕ hierarchy/owner/AccessBinding-tuple**; его live-drainer без backstop = единая точка тихой потери для всего флота → backstop обязателен и для него. |
| D-10 | **Идемпотентность доставки** — на стороне applier: `RegisterResource` уже-существующего tuple → IAM/FGA-409 → applier возвращает `drainer.ErrAlreadyApplied` → drainer mark'ит success. At-least-once + идемпотентность = exactly-once-эффект на FGA. | Зеркалит W1.1 FGAApplier (HTTP 409→success); `RegisterResource` Internal-only идемпотентен по контракту (SEC-A). |

---

## 3. Глоссарий: текущее состояние гарантии по сервисам (ground-truth)

| Сервис | Owner-tuple механизм СЕЙЧАС | Атомарен? | Что нужно в этом эпике |
|---|---|---|---|
| **kacho-vpc** (7 tenant-ресурсов) | SEC-D: dedicated `fga_register_outbox` (0006) + register-intent co-commit в writer-tx (`network/create.go:202,230,236`) + corelib register-drainer + `InternalIAMService.RegisterResource` :9091 mTLS | **ДА** | backstop only: reconciler + fail-closed wiring + метрики (S3) — НЕ менять атомарность, НЕ новая миграция |
| **kacho-compute** | SEC-D (как vpc) + structural-gate `TestSEC_D_07_NoDirectFGAInClients` (`no_direct_fga_test.go:17`) | **ДА** | backstop only (S3) |
| **kacho-nlb** | SEC-D: `fga_register_outbox` (0002) + applier (`clients/iam/register_applier.go`) | **ДА** | backstop only (S3) |
| **kacho-apps** | **НЕТ механизма**: `Insert` = bare `pool.QueryRow` (`application.go:211`, нет tx, нет outbox); `Delete` = bare `pool.Exec` (`:262`, нет Unregister); cmd-edge только `ProjectService.Get`+`Check` (`main.go:90-122`) | **НЕТ** | **полный greenfield SEC-D** (S1, priority 1) → 100% Applications сейчас без tuple |
| **kacho-iam own-resources (best-effort)** | best-effort post-commit: `WriteHierarchyTuple` после `DoWithWriteTx` («Non-fatal»): `account/create.go:157-171` (owner + SEC-L cluster-pointer), `project/create.go:115-130`, `group/create.go:106`, `role/create.go:114`, `service_account/create.go:107`; `writeBootstrapTuples` best-effort post-commit (`internal_upsert.go:406-476`: `WriteTuples:446` + 5× `WriteHierarchyTuple:456-475`) | **НЕТ** (теряются на любом FGA-сбое) | **миграция в in-tx `fga_outbox`-emit** (S2, priority 1); `fga_outbox` уже есть (0001) — новой миграции не нужно |
| **kacho-iam AccessBinding + bootstrap_admin (УЖЕ-атомарные)** | in-tx co-commit: `AccessBinding.Create` → `EmitRelationWrite` в writer-tx (`access_binding/create.go:166-172`, «fga_outbox INSERT commits iff binding INSERT commits, запрет #10»); cluster-admin `seed/bootstrap_admin.go:90` → `BeginTx→fga_outbox INSERT→Commit` (`:133,173`) | **ДА** | **backstop-only — НЕ мигрировать/НЕ трогать emit** (S2 не должен их регрессировать); сценарии 1.4-14 (AccessBinding) + структурный гейт «bootstrap_admin emit остаётся in-tx» |
| **kacho-iam `fga_outbox` live drainer** | live drainer `serve.go:532-547` (Table `kacho_iam.fga_outbox`, `MaxAttempts:10`); общий corelib `drainer`-код → наследует transient-poison-баг D-5; нет reconciler-redrive/метрик/boot-gate | частично (та же leaf-точка для ВСЕХ hierarchy/owner/AccessBinding-tuple) | **S0-backstop в S2** (D-9, B3): reconciler re-drive + метрики (D-7) + `--require-iam` boot-gate (D-8) поверх существующего drainer'а — сценарий **1.4-15** (зеркало 1.4-04/06/23/31/32 для iam) |
| **kacho-corelib `outbox/drainer`** | W1.1 merged: LISTEN/NOTIFY + CAS-claim (по **`id`** bigint, `internal.go:174-184`) + idempotent + exp-backoff; `MaxAttempts=10` (`drainer.go:43`); transient → `attempt_count++`-commit (`internal.go`) | частично | **transient-no-poison класс (D-5) + reconciler (D-6, incl. anti-race GC D-6c) + метрики (D-7) + boot-gate (D-8)** (S0, foundation, блокирует всё) |
| **kacho-geo (Region/Zone)** — _OUT-BY-DESIGN_ | глобальные cluster-scoped admin-only каталоги, Internal* :9091 (`serve.go:147-149`); НЕТ `project_id` / нет tenant-владельца; authz cluster-level `system_viewer`/`system_admin`; `geo_outbox` — **audit-only** (sequence_no PK, CREATED/UPDATED/DELETED, `0001_initial.sql:35-49`), нет `RegisterResource`/register-флоу | n/a (нет owner-tuple-флоу) | **НИЧЕГО — вне scope (§6).** Нет create-resource→owner-tuple семантики; включён в перечисление флота как out-by-design (исчерпываемость) |
| **DiskType (kacho-compute Internal-каталог)** — _OUT-BY-DESIGN_ | Internal-admin-каталог типов дисков; нет `project_id` / нет tenant-владельца | n/a | **вне scope (§6)** — admin-каталог, не tenant-ресурс |
| **AddressPool (kacho-vpc Internal-admin)** — _OUT-BY-DESIGN_ | Internal-admin-ресурс (`/vpc/v1/addressPools`, :9091, `security.md`); нет owner-tuple-флоу | n/a | **вне scope (§6)** — admin-ресурс, не tenant-ресурс |

**Канонический образец co-commit (зеркало для S1/S2):**
- vpc: `w.Networks().Insert(...)` → `w.Outbox().Emit("Network", id, "CREATED", …)` → `w.FGARegister().EmitRegister(Intent{Tuples:[ProjectHierarchy(project_id, "vpc_network", id)]})` → `w.Commit()` — всё в одной writer-tx (`network/create.go:202-236`).
- iam (**уже-атомарный образец внутри самого kacho-iam** — точное зеркало для S2-миграции best-effort-путей): `AccessBinding.Create` — `w := repo.Writer(ctx)` → `w.AccessBindingsW().Insert(...)` → `w.AccessBindingsW().EmitRelationWrite(tuples)` (fga_outbox) → `EmitAuditEvent` → `w.Commit()` (`access_binding/create.go:140-204`). S2 переносит `WriteHierarchyTuple`-вызовы account/project/group/role/SA/bootstrap на ровно эту форму (`EmitRelationWrite`/`fga_outbox`-emit в writer-tx вместо post-commit «Non-fatal»).
- iam audit: `w.RolesW().Insert(...)` → `w.EmitAuditEvent(AuditEvent{…})` в той же `DoWithWriteTx` (`role/create.go:90-108`) — co-commit audit-строки уже корректен; S2 добавляет рядом `fga_outbox`-emit тем же co-commit.

---

## 4. Структура эпика (sub-phases) и кросс-репо порядок

| Sub-phase | Репо | Что | Приоритет |
|---|---|---|---|
| **S0** | kacho-corelib | reconciler (`outbox/reconciler`) + transient-класс no-poison (D-5) + метрики (D-7) + fail-closed boot-gate helper (D-8) | **Foundation — блокирует все** |
| **S1** | kacho-apps **+ kacho-iam (SEC-C grant)** | полный greenfield SEC-D (таблица+триггер, in-tx Insert/Delete, IAM client, drainer wiring) **+ НОВАЯ iam-миграция: apps-SA `fga_writer@iam_fgaproxy:system` (BLOCKER-1, зеркало SEC-C 0009, ban #5 не редактируем 0009)** | **1** |
| **S2** | kacho-iam | (a) best-effort own-resource + bootstrap (account/project/group/SA/role + `writeBootstrapTuples` + owner-self-grant) → in-tx `fga_outbox`-emit; (b) `AccessBinding.Create`/`bootstrap_admin.go` — **НЕ трогать** (уже in-tx, backstop-only); (c) S0-backstop поверх **live `kacho_iam.fga_outbox`-drainer** (`serve.go:532-547`): reconciler re-drive + метрики + `--require-iam` boot-gate | **1** |
| **S3** | kacho-vpc / kacho-compute / kacho-nlb | reconciler + fail-closed wiring + метрики (backstop; без изменения атомарности) | 2 (параллельно S1/S2) |
| **S4** | kacho-api-gateway / kacho-deploy / kacho-workspace | probes/env (require-iam, метрики-endpoint) + docs/vault/edges (`apps→iam fgaproxy` ребро в polyrepo.md) + **`./sync-tooling.sh` refresh** (stale synced rule-копии, N3) | 3 |

**Кросс-репо порядок (топосорт build-графа, `polyrepo.md`):** `corelib (S0)` → `apps (S1) ∥ iam (S2) ∥ (vpc/compute/nlb S3)` → `api-gateway (S4)` → `deploy (S4)` → `workspace/docs (S4)`. Пока corelib (S0) не в `main` — consumer-CI пиннит sibling к feature-ветке (`ref:` в `.github/workflows`). **BLOCKER-1 cross-repo:** apps-SA `fga_writer`-grant — это НОВАЯ **iam**-миграция, поэтому S1 затрагивает kacho-iam (а не только kacho-apps); она **должна быть применена ДО** того, как apps начнёт доставлять `RegisterResource` (иначе первая доставка `PermissionDenied`). На стенде/в e2e — миграция iam развёртывается до запуска apps-drainer'а (deploy-ordering, S4); это естественно совпадает с тем, что iam — leaf-сервис, поднимаемый раньше consumer'ов. kacho-apps edge `apps→iam RegisterResource` (fgaproxy) — новое runtime-ребро, фиксируется в `polyrepo.md` (S4). **Ground-truth (сверено):** в workspace-source `polyrepo.md` сегодня kacho-apps **вообще отсутствует** (нет repo-строки, нет узла build-графа, нет ни одного `apps→…` ребра — даже уже-существующего в коде `apps→iam ProjectService.Get`). S4 добавляет **оба** ребра (`apps→iam ProjectService.Get` + `apps→iam fgaproxy RegisterResource/UnregisterResource`) и kacho-apps в repo-таблицу/build-граф (ацикличность: consumer→iam, iam не зовёт apps обратно).

---

## §S0. corelib: reconciler + transient-no-poison + метрики + fail-closed boot-gate (foundation)

**Целевое (D-5..D-8 + D-6c):** drainer перестаёт терять intent на затяжном transient-сбое; reconciler чинит застрявшие/потерянные/orphan **с anti-race GC (D-6c — concurrent Create всегда побеждает GC-Unregister, не TOCTOU)**; метрики делают backlog/poison наблюдаемыми; boot-gate fail-close'ит сервис без IAM-drainer'а. Все изменения — в `kacho-corelib/outbox/{drainer,reconciler,metrics}`; общей миграции нет (reconciler работает с уже существующими per-service outbox-таблицами — все `fga_*`-таблицы id-keyed, claim/mark по `id` bigint, `internal.go:174-249`).

### 1.4-04 (D-5 — long-outage NO-poison: затяжной transient НЕ отравляет intent)
**Given** drainer запущен на testcontainers-Postgres + per-service outbox-таблица; fake-applier возвращает `Unavailable` (моделирует IAM-down) на первые **N > MaxAttempts** (например 15 при `MaxAttempts=10`) последовательных attempts, затем `nil`
**And** в outbox одна `fga.register`-intent-строка
**When** drainer пытается доставить её сквозь весь outage и затем IAM «возвращается»
**Then** intent-строка **НЕ** помечается poisoned (`attempt_count` НЕ замораживает её ниже клейма; transient-класс не инкрементит в poison-gate) — после восстановления IAM строка **в итоге** применяется ровно один раз (`sent_at IS NOT NULL`, `last_error IS NULL`)
**And** во время outage метрика `outbox_oldest_pending_age_seconds` растёт (intent виден как pending, не потерян)
**And** контраст-сценарий: тот же fake-applier, но ошибка `errors.Join(drainer.ErrPermanent, …)` (4xx-non-409) → строка **poisoned** (`attempt_count == MaxAttempts`, `sent_at IS NULL`, `last_error` set) — poison'ит ТОЛЬКО permanent

### 1.4-05 (D-5/D-7 — poison + alert: permanent error surfaced via метрику и reconciler)
**Given** drainer запущен; fake-applier возвращает permanent error (`ErrPermanent`, например malformed payload или FGA-4xx-non-409) на конкретную intent-строку; другие intent — `nil`
**When** drainer обрабатывает poisoned-строку и затем нормальную
**Then** poisoned-строка: `attempt_count == MaxAttempts`, `last_error` содержит причину, `sent_at IS NULL`; нормальная: `sent_at IS NOT NULL` (drainer не застрял на poisoned)
**And** метрика `outbox_poisoned_total{table=…}` инкрементнута на 1
**And** reconciler-отчёт (1.4-06) перечисляет эту строку как poisoned (id + last_error) для оператора

### 1.4-06 (D-6 — reconciler re-drive poisoned + derive-from-state backfill project-hierarchy)
**Given** (a) одна poisoned intent-строка (re-drive case); **And** (b) одна ресурсная строка с хранимым `project_id`, у которой НЕТ соответствующей applied-intent (legacy never-enqueued case — owner-tuple никогда не доходил)
**When** запускается reconciler-проход
**Then** (a) poisoned-строка пере-драйвится (re-emit / сброс в claimable) → при доступном IAM применяется → `sent_at IS NOT NULL`
**And** (b) reconciler синтезирует **только project-hierarchy**-intent для ресурса без applied-tuple (derive-from-state из `project_id`) и эмитит его → owner получает доступ к legacy-ресурсу
**And** backfill идёт **только** для legacy never-enqueued project-hierarchy-tuple (не дублирует уже-applied; не трогает строки с актуальным intent)
**And (N6 — derive-from-state пишет через ТУ ЖЕ transactional register-outbox-таблицу):** re-emit (D-6b) НЕ ходит в FGA/IAM напрямую — он **INSERT'ит новую intent-строку в ту же per-service register-outbox-таблицу** (`<svc>_fga_register_outbox` / iam `fga_outbox`), которой управляет тот же CAS-claim-путь (`sent_at IS NULL AND attempt_count < $max … FOR UPDATE SKIP LOCKED`), → доставка идёт штатным drainer'ом (at-least-once + идемпотентность D-10). **Per-service resource-enumerate** (как перечислить ресурсные строки без applied-intent) — это **per-service адаптер** (знает доменную таблицу/`project_id`-колонку), а НЕ corelib: corelib-reconciler оркеструет проход и emit, доменное перечисление инжектится сервисом

### 1.4-06a (D-4 — owner-self-grant НЕ backfillable: reconciler НЕ синтезирует его из состояния)
> Кодирует NOTE (N2-reframe): owner-self-grant subject («кто владелец-user») невосстановим из состояния ресурса → in-tx emit обязателен primary, reconciler — safety-net только для project-hierarchy. Инвариант на **live** owner-self-grant-путях (`account/create.go:160`, `internal_upsert.go:456-475`), не на dead-RPC `WriteCreatorTuple`.

**Given** ресурс, у которого был потерян owner-self-grant-tuple (live путь, напр. account-owner self-grant), и эта intent отсутствует в outbox (не была co-committed)
**When** запускается reconciler derive-from-state проход
**Then** reconciler **НЕ** создаёт owner-self-grant-tuple (нет источника истины «кто владелец-user» в ресурсной строке как backfillable subject) — он не угадывает principal
**And** reconciler синтезирует только project-hierarchy-tuple (если `project_id` хранится)
**And** это фиксирует инвариант: единственная гарантия owner-self-grant — co-commit его intent в writer-tx (D-3a/D-4); если intent не был записан — owner-self-grant невосстановим (значит S2 ОБЯЗАН эмитить его in-tx)

### 1.4-07 (D-6/D-6c — inverse-orphan GC: tuple, чей ресурс устойчиво удалён → Unregister, с anti-race инвариантом)
**Given** в FGA есть owner-tuple для ресурса, который уже удалён из БД сервиса (ресурс ушёл, но `Unregister`-intent был poisoned/потерян → orphan-grant)
**And** для этого id в outbox **нет** pending/recent `register`-intent (никакого Create «в полёте»), и ресурс отсутствует **устойчиво** — через grace-window / два последовательных прохода (D-6c)
**When** запускается reconciler inverse-orphan проход
**Then** reconciler эмитит `fga.unregister`-intent для orphan-tuple → drainer доставляет `UnregisterResource` → orphan-grant снят
**And** GC не трогает tuple ресурсов, которые ещё существуют (только tuple-без-ресурса)
**And** GC **НЕ** Unregister'ит при наличии pending/recent `register`-intent или если ресурс отсутствовал лишь в одном point-in-time снимке (анти-race инвариант D-6c: «ресурс отсутствует» проверяется устойчиво, не check-then-act)

### 1.4-07b (D-6c — concurrent re-create vs GC: intent Create всегда побеждает; НЕТ self-inflicted access-loss) — `-race`
> Кодирует анти-race инвариант D-6c. Защита от TOCTOU: GC прочитал «ресурс отсутствует» (stale), а конкурентный re-Create только что легитимно co-commit'нул register-intent — GC НЕ должен снять только что выданный owner-tuple.

**Given** corelib reconciler на testcontainers-Postgres + per-service outbox/ресурсная таблица; id `X` ранее удалён (orphan-tuple в FGA)
**And** drainer + reconciler-GC и клиентский Create работают конкурентно (goroutines, `-race`)
**When** GC-проход для `X` начинается (видит «ресурс отсутствует»), и **до** того как GC-Unregister доставлен, `Create` пере-выпускает `X` с co-committed `register`-intent в той же `pgx.Tx`
**Then** итоговое FGA-состояние содержит owner-tuple для `X` **PRESENT** (register-intent re-creator'а победил: anti-race condition (a) — pending/recent register-intent для `X` — блокирует Unregister)
**And** re-creator `Get(X)` как owner → `200`/ALLOW (доступ к своему пере-созданному ресурсу есть — дефект «self-inflicted owner access-loss» НЕ воспроизводится)
**And** GC не оставляет `X` в неконсистентном состоянии (нет «ресурс есть, tuple снят»)
**And** обязателен `-race` concurrent integration-тест (ban #10 / `testing.md`) — рядом с race-тестом CAS-claim в S0 DoD

### 1.4-08 (D-8 — fail-closed boot/Create: --require-iam без IAM-peer/drainer → отказ в мутирующих Create)
> **Канонический fail-closed режим (единый по флоту, N5):** readiness-probe → **NotReady** при незапущенном IAM-connected drainer **И** мутирующий `Create` → **отказ** (`UNAVAILABLE`/`FAILED_PRECONDITION`). НЕ either/or — оба наблюдаемых эффекта обязательны и единообразны для apps/vpc/compute/nlb/iam (никаких per-service вариаций «refuse-boot vs refuse-create»).

**Given** сервис (apps/vpc/compute/nlb/iam) сконфигурирован `--require-iam` (`KACHO_<SVC>_REQUIRE_IAM=true`), но IAM-peer недоступен / drainer не запустился
**When** клиент вызывает мутирующий `Create<Resource>`
**Then** сервис **отказывает** в мутации (наблюдаемо: `UNAVAILABLE` либо `FAILED_PRECONDITION` с фикс. текстом про недоступность IAM-register), ресурс **НЕ** создаётся (нет строки без tuple)
**And** readiness-probe сервиса при этом репортит **NotReady** (единый канонический режим — k8s не шлёт мутирующий трафик на сервис без drainer'а; оба эффекта обязательны, не альтернатива)
**And** read-RPC (`Get`/`List`) продолжают работать на уже-Ready-инстансах (fail-closed только для мутаций, `data-integrity.md` §cross-domain)
**And** контраст: при `--require-iam=false` (dev back-compat) — старый Warn-режим, Create проходит, probe Ready (только локальные фикстуры; в проде `--require-iam=true`)

### 1.4-23 (D-7 — метрики backlog/oldest/poisoned экспонируются)
**Given** drainer запущен; в outbox 3 pending intent (IAM временно down) + 1 poisoned
**When** опрашивается metrics-endpoint сервиса
**Then** `outbox_backlog_depth{table=…} == 3` (pending), `outbox_oldest_pending_age_seconds{table=…} > 0` (растёт пока IAM down), `outbox_poisoned_total{table=…} == 1`
**And** после восстановления IAM `outbox_backlog_depth` → 0 (всё доставлено), `outbox_poisoned_total` не обнуляется (исторический counter)

### 1.4-21 (ban #10 — CAS-claim exactly-once под concurrency: 2 реплики drainer'а / N goroutine'ов → каждая intent клеймится ровно один раз) — `-race`
> Кодирует exactly-once claim-инвариант, цитируемый в §1 ban #10: атомарный CAS-claim `UPDATE … WHERE sent_at IS NULL AND attempt_count < $max … FOR UPDATE SKIP LOCKED RETURNING` (corelib `drainer/internal.go:174-249`, claim по **`id` bigint**). Обязательный concurrent `-race` integration-тест foundation-слоя (S0 DoD) — рядом с anti-race GC (1.4-07b).

**Given** corelib drainer на testcontainers-Postgres; в per-service outbox **M** pending intent-строк (`sent_at IS NULL`); fake-applier считает Apply-вызовы per-intent
**And** запущены **2+ конкурентных drainer-loop'а** (моделируют 2 реплики сервиса) / N goroutine'ов поверх одной outbox-таблицы, `-race`
**When** drainer'ы конкурентно клеймят и доставляют pending-строки
**Then** каждая из M intent доставлена **ровно один раз** (fake-applier видит ровно M успешных Apply, no double-apply — CAS-claim + `FOR UPDATE SKIP LOCKED` гарантируют, что две реплики не возьмут одну строку)
**And** все M строк `sent_at IS NOT NULL`; нет строки, заклейменной двумя репликами одновременно (no lost-update на `attempt_count`)
**And** обязателен `-race` concurrent integration-тест (ban #10 / `testing.md`) — один из ДВУХ обязательных race-тестов S0 (второй — anti-race GC 1.4-07b)

---

## §S1. kacho-apps: полный greenfield SEC-D (priority 1)

**Целевое (D-2):** перевести kacho-apps на тот же SEC-D, что vpc/compute/nlb — атомарный co-commit register-intent + drainer-доставка `RegisterResource`. Закрывает «100% Applications без owner-tuple». Зеркалит canonical compute/nlb.

> **BLOCKER-1 — apps-SA `fga_writer` least-priv-grant (ОБЯЗАТЕЛЬНОЕ предусловие register-edge, S1-step + DoD).** Доставка apps→iam `RegisterResource` гейтится least-priv ReBAC-relation'ом `service_account:<sva-apps>#fga_writer@iam_fgaproxy:system` (`internal_iam/handler.go:171` нет relation → `PermissionDenied`; `internal_iam_service.proto:128`; `security.md` §AuthN+AuthZ ВЕЗДЕ). SEC-C seed (`kacho-iam/internal/migrations/0009_sec_c_module_sa_least_priv.sql`) выдаёт этот grant ТОЛЬКО vpc/compute/nlb — **kacho-apps отсутствует во всех iam-миграциях**. Без grant'а первая же apps-доставка fail-close'ится у IAM (`PermissionDenied`): по канонической applier-классификации (compute/nlb-форма — `iam_register_applier.go:110`, `register_applier.go:152`) `PermissionDenied` — **raw transient** → drainer ретраит **бесконечно**, intent НЕ landing'ится, `outbox_oldest_pending_age_seconds{table="kacho_apps.fga_register_outbox"}` растёт безгранично → S1 «100% Applications получают owner-tuple» **нереализуемо self-inflicted'но** (ровно тот failure-class «ресурс создан — tuple обвалился», который эпик существует убить). **S1 ОБЯЗАН добавить НОВУЮ sequential iam-миграцию** (0009 — APPLIED, ban #5: НЕ редактировать), зеркалящую форму 0009 / следующую паттерну seed-extend (напр. `0014_reader_sa_system_viewer.sql`): провижен `kacho-apps` system ServiceAccount + `fga_writer`-tuple через `kacho_iam.fga_outbox` (event_type `'fga.tuple.write'`, payload `jsonb_build_object('user','service_account:'||<sva-apps>, 'relation','fga_writer', 'object','iam_fgaproxy:system')`), переиспользуя детерминированные id-формы 0009 — `<sva-apps> = 'sva'||substr(md5('kacho-apps'),1,17)`, anchor system-account `'acc'||substr(md5('kacho-system'),1,17)` (anchor user/account уже сидированы 0009, `ON CONFLICT DO NOTHING`). Cross-ref SEC-C 0009 в этом разделе и в §4/§5 — implementer не должен пропустить зависимость. Тот же `fga_writer`-провижен обязателен для **ЛЮБОГО будущего сервиса**, добавляемого во флот SEC-D. Верификация — сценарий **1.4-01b**.

> **N6 (форма таблицы — db, в S1 DoD):** `kacho_apps.fga_register_outbox` ОБЯЗАНА быть **`id bigint`-keyed PK** с claim/notify по `id` (drainer claim'ит по `id`, `internal.go:174-184` — НЕ `sequence_no`; `sequence_no`-форма = `nlb_outbox`/`subject_change_outbox`, drainer-incompatible). Следовать варианту **compute** `fga_register_outbox` (`0010_fga_register_outbox.sql`): `id BIGSERIAL PK` + колонки `resource_kind`/`resource_id` TEXT + `event_type` CHECK `IN ('fga.register','fga.unregister')` + `payload JSONB NOT NULL DEFAULT '{}'::jsonb` + `sent_at`/`last_error`/`attempt_count` + pending partial-index + NOTIFY-триггер. **N4 (канонический payload-shape):** берём **compute-форму** — trace-данные в колонках `resource_kind`/`resource_id` (без отдельного jsonb-CHECK), `payload` несёт owner-tuple-данные (`{project_id}` / `{tuples:[…]}`-набор). S2-iam-intent'ы остаются существующими литералами `'fga.tuple.write'`/`'fga.tuple.delete'` (иная таблица `fga_outbox`, иной контракт — N5). (vpc-вариант (0006) — lean, без `resource_kind`; nlb-вариант (0002) добавляет `jsonb_typeof`-CHECK — берём compute-форму как канон.)

### 1.4-01 (positive — атомарный co-commit: Application INSERT + register-intent в одной committed tx)
**Given** kacho-apps на testcontainers-Postgres со схемой `kacho_apps` (вкл. новую `fga_register_outbox` таблицу + NOTIFY-триггер); project `prj-X`
**When** выполняется `ApplicationService.Create` (async→`Operation`) с payload `{projectId:"prj-X", name:"web", gitRepo:"…"}`; tx коммитится
**Then** в `kacho_apps.applications` появилась строка `app-…` (`projectId=prj-X`)
**And** в `kacho_apps.fga_register_outbox` (id-bigint-keyed, N6) появилась РОВНО одна строка с `event_type='fga.register'` (CHECK), `resource_kind='apps_application'`, `resource_id='app-…'`, `payload` (jsonb object) содержит `{project_id:"prj-X"}`, в ТОЙ ЖЕ committed tx, `sent_at IS NULL`
**And** обе записи атомарны: они либо обе присутствуют, либо обе отсутствуют

### 1.4-01a (negative — INSERT провалился → НЕТ intent-строки)
**Given** kacho-apps; `Create` с дубль-именем в проекте (нарушает partial UNIQUE `(project_id, name) WHERE name<>''`, `0002_applications.sql:131`) → INSERT ресурса падает (`ALREADY_EXISTS`)
**When** выполняется `Create` с уже занятым `{projectId:"prj-X", name:"web"}`
**Then** мутация → `ALREADY_EXISTS` (через `Operation.error`); в `kacho_apps.applications` новой строки нет
**And** в `kacho_apps.fga_register_outbox` **НЕТ** intent-строки для этой неудачной попытки (tx откатилась целиком — нет окна «intent есть, ресурса нет»)

### 1.4-01b (BLOCKER-1 — apps-SA `fga_writer` least-priv grant требуется И присутствует: без grant'а → PermissionDenied (intent не landing'ится), с seeded grant → доставлен)
> Кодирует BLOCKER-1: register-edge apps→iam гейтится ReBAC `fga_writer@iam_fgaproxy:system`. Без новой iam-миграции, провижащей `service_account:<sva-apps>#fga_writer@iam_fgaproxy:system` (зеркало SEC-C 0009), доставка fail-close'ится у IAM и owner-tuple никогда не доходит — S1-deliverable нереализуем. Сценарий доказывает grant и **необходим** (контраст), и **присутствует** (positive).

**Given** kacho-apps + kacho-iam на стенде с реальным `RegisterResource`-gate (`fga_writer@iam_fgaproxy:system`, `internal_iam/handler.go:171`); apps register-intent для `app-A` co-committed (`sent_at IS NULL`)
**When (контраст — grant ОТСУТСТВУЕТ):** apps-SA НЕ имеет `fga_writer`-tuple (новая iam-миграция не применена) → drainer доставляет `RegisterResource(app-A)`
**Then** IAM возвращает `PermissionDenied` (least-priv-gate отклоняет: «нет relation»); intent-строка `app-A` **остаётся pending** (`sent_at IS NULL`) — по канонической applier-классификации `PermissionDenied` — raw transient → drainer ретраит, intent НЕ poisoned, но и НЕ landing'ится; `outbox_oldest_pending_age_seconds{table="kacho_apps.fga_register_outbox"}` растёт (owner-tuple так и не доходит — наблюдаемый self-inflicted «обвал tuple»)
**And** per-resource `Check` для creator `app-A` → DENY (доступ к своему свежесозданному ресурсу отсутствует — воспроизводит дефект требования заказчика)
**When (positive — grant ПРИСУТСТВУЕТ):** применена новая iam-миграция, сидировавшая `service_account:<sva-apps>#fga_writer@iam_fgaproxy:system` (форма 0009: `<sva-apps>='sva'||substr(md5('kacho-apps'),1,17)`, через `fga_outbox` `'fga.tuple.write'`); drainer пере-доставляет `RegisterResource(app-A)`
**Then** IAM применяет owner-tuple (gate проходит); intent `sent_at IS NOT NULL`, `last_error IS NULL`; per-resource `Check` для creator `app-A` → ALLOW (доступ есть)
**And** инвариант: grant — **предусловие** register-edge; тот же `fga_writer`-провижен обязателен для любого нового сервиса флота SEC-D (без него register-edge мёртв)

### 1.4-02 (positive — crash-before-delivery recovery: committed Application+intent, IAM unreachable → on IAM return доставляется exactly once)
**Given** kacho-apps; Application `app-A` создан (ресурс+intent committed), но IAM :9091 был недоступен в момент создания (drainer не смог доставить) → intent `sent_at IS NULL`; сервис перезапущен (моделирует crash)
**When** drainer стартует и IAM «возвращается» (доступен)
**Then** drainer (catch-up) клеймит intent `app-A` и доставляет `InternalIAMService.RegisterResource` ровно один раз
**And** intent-строка `sent_at IS NOT NULL`, `last_error IS NULL`
**And** owner получает доступ к `app-A` (per-resource `Check` для creator → ALLOW)

### 1.4-03 (positive — idempotent double-delivery: уже-applied tuple re-delivered → FGA-409 → success)
**Given** kacho-apps; Application `app-A`, register-intent уже доставлен (tuple в FGA); строку искусственно сбросили в claimable (`sent_at=NULL`, моделирует повторную доставку после двойного NOTIFY/replica-race)
**When** drainer пере-доставляет `RegisterResource` для `app-A` (tuple уже существует в FGA)
**Then** IAM/FGA возвращает 409 (already-applied) → applier → `drainer.ErrAlreadyApplied` → drainer mark'ит `sent_at IS NOT NULL` как success
**And** в FGA по-прежнему ровно один tuple (no duplicate); итоговый эффект — exactly-once на FGA (at-least-once доставка × идемпотентность)

### 1.4-07a (positive — симметричный Unregister: Delete commits → unregister-intent co-commits → tuple снят)
**Given** kacho-apps; Application `app-A` с owner-tuple в FGA
**When** выполняется `ApplicationService.Delete(app-A)` (async→`Operation`); tx коммитится
**Then** строка `app-A` удалена из `kacho_apps.applications`; в `kacho_apps.fga_register_outbox` появилась `fga.unregister`-intent в ТОЙ ЖЕ committed tx
**And** drainer доставляет `InternalIAMService.UnregisterResource` → owner-tuple `app-A` снят из FGA (доступ к удалённому id больше не висит)
**And edge:** если unregister-intent poisoned → reconciler inverse-orphan GC (1.4-07) подчищает orphan-tuple

### 1.4-20 (concurrency — 2 параллельных Create → каждая получает свой intent, drainer доставляет ровно по одному)
**Given** kacho-apps; drainer запущен
**When** 2 goroutine'ы параллельно создают 10 Applications каждая (20 уникальных, разные имена) под нагрузкой
**Then** все 20 ресурсных строк созданы; все 20 register-intent co-committed; drainer доставляет ровно 20 `RegisterResource` (no double, no miss — атомарный CAS-claim, `data-integrity.md` ban #10)
**And** все 20 intent `sent_at IS NOT NULL`; в FGA ровно 20 owner-tuple

---

## §S2. kacho-iam: best-effort own-resource/bootstrap/owner-self-grant → in-tx fga_outbox emit + drainer-backstop (priority 1)

**Целевое (D-3/D-4/D-9):** (a) перевести **best-effort post-commit** hierarchy/owner-self-grant-tuple на in-tx `fga_outbox`-emit (зеркало уже-атомарного `AccessBinding.Create` `EmitRelationWrite`, `access_binding/create.go:166`; и `EmitAuditEvent` co-commit, `role/create.go:95`). `fga_outbox` существует (0001), event_type-литералы `'fga.tuple.write'`/`'fga.tuple.delete'` — новой миграции не нужно. Owner-self-grant — in-tx emit ОБЯЗАТЕЛЕН (D-4, невосстановим reconciler'ом). (b) **НЕ трогать** уже-атомарные `AccessBinding.Create` и `seed/bootstrap_admin.go` (backstop-only — миграция не должна их регрессировать). (c) Wire S0-backstop поверх **live `kacho_iam.fga_outbox`-drainer** (`serve.go:532-547`): reconciler re-drive + метрики + `--require-iam` boot-gate (D-9; iam — leaf, куда сходятся ВСЕ tuple).

> **Терминология:** «creator-tuple» в этом разделе означает **live owner-self-grant** (account-owner `account/create.go:160`, bootstrap owner self-grant `internal_upsert.go:456-475`). `WriteCreatorTuple` (`internal_iam/handler.go:184`) — **dead RPC** (нет live-caller, заменён register-outbox'ом в nlb, Issue N5) — он НЕ цель миграции; D-4-инвариант кодируется на live-путях.

> **N3 (repo comment-fix, в S2 DoD — НЕ acceptance-поведение):** `kacho-iam/cmd/kacho-iam/serve.go:526` и `internal/apps/kacho/seed/bootstrap_admin.go:122` называют `kacho_iam.fga_outbox` «migration 0002», но таблица создаётся в `0001_initial.sql:432,440` (док цитирует 0001 верно). S2 (который и так трогает iam-drainer/own-resource emit) попутно правит эти два stale-комментария → «migration 0001». Чисто документационный однострочник в коде, не меняет поведения.

### 1.4-10 (positive — own-resource Create: hierarchy-tuple intent co-commit в writer-tx)
> **N6 (event_type-литералы):** S2-intent'ы эмитятся ТОЛЬКО как `'fga.tuple.write'`/`'fga.tuple.delete'` — существующие литералы CHECK `kacho_iam.fga_outbox` (`0001_initial.sql:440`); таблица content-agnostic (tuple-данные в payload). НОВЫХ event_type-литералов НЕ вводить — иначе CHECK-violation `23514` → poison.

**Given** kacho-iam на testcontainers-Postgres; account `acc-X`
**When** выполняется `ProjectService.Create` (или Group/ServiceAccount/Role/Account Create) в проекте `acc-X` (async→`Operation`); writer-tx коммитится
**Then** ресурсная строка создана; в `kacho_iam.fga_outbox` появилась `'fga.tuple.write'`-intent (project→account hierarchy) в ТОЙ ЖЕ writer-tx (рядом с `EmitAuditEvent`-строкой), `sent_at IS NULL`
**And** при провале INSERT ресурса — НЕТ hierarchy-intent (tx откатилась; контраст 1.4-01a)
**And** drainer доставляет tuple → owner получает доступ к новому ресурсу (per-resource `Check` → ALLOW)

### 1.4-10a (positive — best-effort post-commit путь УСТРАНЁН: tuple переживает FGA-сбой на момент Create)
> Кодирует фикс «Non-fatal» best-effort: `account/create.go:157-171` (owner + SEC-L cluster-pointer), `project/create.go:115-130`, `group/create.go:106`, `role/create.go:114`, `service_account/create.go:107`. Уже-атомарный `AccessBinding.Create` (`access_binding/create.go:166`) — НЕ в этом сценарии (он эталон, не цель миграции; см. 1.4-14).

**Given** kacho-iam; OpenFGA недоступен в момент `Account.Create`/`Project.Create`/`Group.Create`/`Role.Create`
**When** выполняется Create при недоступном FGA
**Then** ресурс создаётся, hierarchy-tuple intent **co-committed в `fga_outbox`** (НЕ потерян — в отличие от старого best-effort `WriteHierarchyTuple` после commit)
**And** после восстановления FGA drainer доставляет tuple → доступ владельца появляется (eventual, не теряется)
**And** старый «Non-fatal» путь post-`DoWithWriteTx` для этих tuple **удалён** (структурный гейт: hierarchy-tuple-write не вызывается после возврата writer-tx)

### 1.4-10b (positive — user-bootstrap writeBootstrapTuples → in-tx fga_outbox emit)
> `internal_upsert.writeBootstrapTuples` (`:406-476`: `WriteTuples:446` + 5× `WriteHierarchyTuple:456-475`) сегодня best-effort non-fatal post-commit для всего bootstrap-графа (НЕ путать с `seed/bootstrap_admin.go:90`, который УЖЕ in-tx и не трогается).

**Given** kacho-iam; `InternalUserService.UpsertFromIdentity` создаёт bootstrap-граф (account owner / user→account hierarchy / project→account / admin self-grants)
**When** выполняется bootstrap при недоступном FGA
**Then** все bootstrap-tuples эмитятся как intent в `fga_outbox` **внутри той же bootstrap-tx**, что и INSERT'ы (не best-effort после commit)
**And** drainer доставляет их → новый User/Account/Project доступен через per-resource RPC (закрывает «no path» FGA-Check)
**And** уже-атомарный путь `seed/bootstrap_admin.go:90` (`BeginTx→fga_outbox→Commit`) **НЕ регрессирован** (структурный гейт: cluster-admin bootstrap-tuple по-прежнему co-committed in-tx)

### 1.4-11 (positive — live owner-self-grant → in-tx outbox emit ОБЯЗАТЕЛЕН; reconciler не страхует)
> D-4 (N2-reframe): инвариант на **live** owner-self-grant-путях — account-owner self-grant (`account/create.go:160`) и bootstrap owner self-grant (`internal_upsert.go:456-475`). **НЕ** на `WriteCreatorTuple` (`internal_iam/handler.go:184`) — это dead RPC без live-caller (заменён register-outbox'ом в nlb, Issue N5).

**Given** kacho-iam; Create-путь, эмитящий owner-self-grant-tuple (`account/create.go:160` user→owner→account; либо bootstrap owner self-grant `internal_upsert.go:456-475`)
**When** owner-self-grant-tuple записывается при недоступном FGA
**Then** owner-self-grant intent **co-committed в durable `fga_outbox`** в той же writer-tx (сегодня — best-effort post-commit «Non-fatal» → теряется на сбое)
**And** drainer доставляет его at-least-once → owner получает доступ к своему account/project
**And** инвариант (зеркало 1.4-06a): owner-self-grant subject («кто владелец-user») НЕ реконструируется из состояния ресурса reconciler'ом — поэтому in-tx emit здесь не optional, единственная гарантия
**And** dead-RPC `WriteCreatorTuple` НЕ требует миграции (нет live-caller; если когда-либо появится caller — он обязан следовать тому же in-tx-инварианту)

### 1.4-12 (concurrency — конкурентные own-resource Create → exactly-one intent на ресурс, drainer ровно один RegisterResource)
**Given** kacho-iam; drainer запущен
**When** 2 goroutine'ы параллельно создают по 10 Project/Group (20 уникальных) под нагрузкой
**Then** все 20 hierarchy-intent co-committed; drainer доставляет ровно 20 tuple-write (атомарный CAS-claim, no double/miss)
**And** в FGA ровно 20 hierarchy-tuple

### 1.4-13 (positive — симметричный Delete: own-resource Delete → unregister/tuple-delete intent co-commit)
**Given** kacho-iam; Project `prj-Y ∈ acc-X` с hierarchy-tuple
**When** `ProjectService.Delete(prj-Y)` (async→`Operation`); writer-tx коммитится
**Then** `fga.tuple.delete`-intent co-committed; drainer доставляет → hierarchy-tuple снят
**And** poisoned unregister → reconciler inverse-orphan GC (1.4-07/07b)

### 1.4-14 (positive — AccessBinding.Create УЖЕ-атомарен → grant-tuple доставлен → Check ALLOW; Delete → revoke; миграция S2 его НЕ трогает)
> B2: `AccessBinding` — канонический owner-GRANT IAM, УЖЕ in-tx (`access_binding/create.go:166` `EmitRelationWrite` co-commit, «fga_outbox INSERT commits iff binding INSERT commits, запрет #10»). Это backstop-only класс — миграция best-effort-путей (1.4-10/10a/10b/11) его НЕ мигрирует и НЕ регрессирует.

**Given** kacho-iam; account `acc-X`, project `prj-Y`, user-subject `usr-Z`
**When** выполняется `AccessBindingService.Create` с relation-grant (subject `usr-Z`, role/relation, resource `prj-Y`); writer-tx коммитится
**Then** binding-строка создана; `fga.tuple.write`-grant-intent co-committed в **той же** writer-tx (`EmitRelationWrite`), `sent_at IS NULL` — атомарность УЖЕ есть, эмит не меняется
**And** drainer доставляет grant-tuple → per-resource `Check(usr-Z, prj-Y)` → ALLOW (доступ выдан)
**And** симметрично: `AccessBindingService.Delete(binding)` co-commit'ит `fga.tuple.delete`-revoke-intent в writer-tx → drainer доставляет → `Check(usr-Z, prj-Y)` → DENY (доступ снят)
**And** структурный гейт: миграция S2 НЕ переносит/НЕ дублирует `AccessBinding` emit (он остаётся единственным in-tx `EmitRelationWrite`; нет регрессии в best-effort post-commit)

### 1.4-15 (positive — live iam fga_outbox drainer получает S0-backstop: long-outage no-poison + reconciler re-drive + метрики)
> B3: live drainer `serve.go:532-547` (Table `kacho_iam.fga_outbox`, `MaxAttempts:10`) — leaf-точка, куда сходятся ВСЕ hierarchy/owner/AccessBinding-tuple. D-9: тот же D-5/D-6/D-7/D-8 backstop, что и register-drainer'ы (зеркало 1.4-04/06/23/31/32 для iam).

**Given** kacho-iam с live `kacho_iam.fga_outbox`-drainer; OpenFGA недоступен > `MaxAttempts` attempts на hierarchy/owner-intent (затяжной transient)
**When** OpenFGA «возвращается», и затем запускается reconciler-проход
**Then** intent **НЕ** poisoned (transient-класс D-5 применён к iam-drainer наравне с register-drainer'ами) → в итоге доставлен ровно один раз (`sent_at IS NOT NULL`)
**And** poisoned-строка (если permanent) пере-драйвится reconciler'ом (D-6), `outbox_backlog_depth{table="kacho_iam.fga_outbox"}` / `outbox_oldest_pending_age_seconds` / `outbox_poisoned_total` наблюдаемы (D-7)
**And** при `--require-iam=true` и неподнятом iam-drainer мутирующие iam-Create отказывают + probe NotReady (D-8, зеркало 1.4-08) — leaf-сервис не принимает Create без работающей доставки собственных tuple

---

## §S3. vpc/compute/nlb: reconciler + fail-closed wiring + метрики (backstop)

**Целевое (D-9):** добавить S0-backstop в уже-атомарные сервисы — БЕЗ изменения co-commit-атомарности и БЕЗ новой миграции. Только wire reconciler + boot-gate + метрики.

### 1.4-30 (positive — e2e backstop: vpc Create → tuple доставлен; reconciler + метрики активны; атомарность не тронута)
**Given** kacho-vpc на стенде; SEC-D co-commit как раньше (`fga_register_outbox`); reconciler + метрики + `--require-iam` wired (S3)
**When** выполняется `NetworkService.Create` (async→`Operation`), polling `OperationService.Get` → `done:true`
**Then** Network создан; register-intent co-committed (как и прежде); drainer доставил `RegisterResource`; owner получает доступ
**And** `outbox_backlog_depth{table="kacho_vpc.fga_register_outbox"}` наблюдаема; reconciler-проход не находит потерянных/orphan tuple (всё consistent)
**And** атомарность co-commit НЕ изменена (структурный гейт `TestSEC_D_07_NoDirectFGAInClients`-аналог по-прежнему зелёный: applier не ходит в FGA напрямую из use-case)

### 1.4-31 (positive — vpc/compute/nlb fail-closed boot-gate активирован)
**Given** kacho-vpc/compute/nlb с `--require-iam=true`, IAM-peer недоступен
**When** клиент вызывает мутирующий `Create`
**Then** сервис отказывает (`UNAVAILABLE`/`FAILED_PRECONDITION`), ресурс не создаётся (зеркало 1.4-08 для apps/iam)
**And** read-RPC работают

### 1.4-32 (positive — vpc/compute/nlb long-outage no-poison через общий drainer D-5)
**Given** kacho-compute; IAM down > MaxAttempts attempts на register-intent
**When** IAM возвращается
**Then** register-intent НЕ poisoned (transient-класс D-5), в итоге доставлен ровно один раз (общий corelib backstop работает для всех консьюмеров)
**And** тот же общий corelib backstop (D-5) применён к **live iam `fga_outbox`-drainer** — см. 1.4-15 (iam — leaf-консьюмер собственного drainer'а, не исключён из backstop)

---

## §S4. api-gateway / deploy / docs+vault (probes, env, edges)

### 1.4-40 (deploy — единый канонический fail-closed режим (N5) для всех мутирующих сервисов)
**Given** стенд kacho-deploy
**When** деплоятся apps/vpc/compute/nlb/iam
**Then** каждый получает `KACHO_<SVC>_REQUIRE_IAM=true` (прод) + **единый канонический fail-closed режим (N5): readiness-probe → NotReady при незапущенном IAM-connected drainer И мутирующий Create → отказ** (D-8, 1.4-08) — одинаково для всех 5 сервисов (без per-service «refuse-boot vs refuse-create»-вариаций)
**And** метрики-endpoint (`outbox_backlog_depth`/`outbox_oldest_pending_age_seconds`/`outbox_poisoned_total`, для всех outbox-таблиц вкл. `kacho_iam.fga_outbox`) scraped; алерт на `outbox_poisoned_total > 0` и `outbox_oldest_pending_age_seconds > порог`

### 1.4-42 (workspace — `./sync-tooling.sh` refresh stale-копий rule-модулей, N3)
> N3: синканные `project/<repo>/.claude/rules/`-копии устарели (pre-geo-extraction snapshot): `corelib/.claude/rules/security.md` всё ещё «anonymous → full access» (back-compat без «упраздняется»); `corelib`/`geo`/`apps`/`iam` копии `polyrepo.md` всё ещё «Geography → kacho-compute» + старое ребро `vpc→compute (zone)`. S4 уже правит workspace-source `polyrepo.md` (добавление `apps→iam fgaproxy` + отсутствующего `apps→iam ProjectService.Get`) — значит обязан раскатать source-of-truth.

**Given** workspace-source `.claude/rules/{security.md,polyrepo.md}` обновлён (S4 добавил apps-рёбра в polyrepo.md; security.md и polyrepo.md в source уже актуальны: geo-extraction + «anonymous→full access упраздняется»)
**When** выполняется `./sync-tooling.sh`
**Then** все `project/<repo>/.claude/rules/`-копии перегенерированы из source (`security.md` без stale «anonymous → full access»-back-compat; `polyrepo.md` с `Geography → kacho-geo`, без `vpc→compute (zone)`-ребра, с новыми apps-рёбрами)
**And** проверка: grep `"anonymous → full access"` (как разрешённого) и `"Geography → kacho-compute"` по `project/*/.claude/rules/` — пусто (нет stale-дрейфа)

### 1.4-41 (Internal-only isolation — RegisterResource НЕ на external; mTLS :9091)
**Given** стенд
**When** `InternalIAMService.RegisterResource`/`UnregisterResource` (apps→iam, новое ребро) вызывается
**Then** доступен ТОЛЬКО на cluster-internal :9091 под mTLS + per-RPC authz-Check (least-priv `fga_writer` @ `iam_fgaproxy:system`), НЕ на external endpoint (ban #6, `security.md`)
**And** ребро `apps→iam fgaproxy (RegisterResource/UnregisterResource)` зафиксировано в `polyrepo.md` runtime-edges (вместе с уже-существующим в коде `apps→iam ProjectService.Get`, которого в polyrepo.md сегодня НЕТ) — ацикличность сохранена (consumer→iam, iam не зовёт apps обратно)
**And (BLOCKER-1):** edges-doc `apps→iam fgaproxy` фиксирует **предусловие** ребра — apps-SA несёт least-priv `fga_writer@iam_fgaproxy:system` (provisioned новой iam-миграцией, зеркало SEC-C 0009); без него ребро fail-close'ится `PermissionDenied`. Кросс-ссылка на SEC-C-инвариант: каждый новый сервис флота SEC-D обязан иметь свой `fga_writer`-grant
**And (N5 — две outbox-семьи на сервис):** edges-doc / vault фиксирует, что каждый мутирующий сервис держит **ДВЕ независимые outbox-семьи** — audit/Watch (`<svc>_outbox`, sequence_no-keyed, domain-Watch-applier) и register (`<svc>_fga_register_outbox` / iam `fga_outbox`, id-bigint-keyed, FGA-relay-applier) — у них разные appliers, разные failure-modes и **разные drainer-конфиги**; reconciler/метрики/алерты **НЕ конфлейтят** их (отдельные `table=`-лейблы, отдельный poison-учёт), иначе один poisoned FGA-intent не должен блокировать Watch-stream (и наоборот)

### 1.4-09 (BLACK-BOX e2e — newman: Create → немедленно Get/Update/Delete как creator успешно в authz-стенде; закрывает «403 on own freshly-created resource»)
> Главный end-to-end сценарий: воспроизводит и закрывает defect требования заказчика. ≥1 happy + ≥1 negative на каждый затронутый ресурс, особенно apps.

**Given** authz-enabled стенд (`production-mode`, anonymous fail-closed, drainer'ы запущены); аутентифицированный creator
**When** creator выполняет `POST /apps/v1/applications {projectId, name, gitRepo}` → `Operation`; polling `GET /operations/{id}` → `done:true`; затем **немедленно** `GET /apps/v1/applications/{id}`, `PATCH …`, `DELETE …` как тот же creator
**Then** Get/Update/Delete возвращают `200` (а НЕ `403` — owner-tuple доставлен, доступ к собственному свежесозданному ресурсу есть)
**And** то же для vpc Network / compute Instance / iam Project (per-resource happy: Create→Get как creator → `200`)
**And negative (apps):** Create с несуществующим `projectId` → `INVALID_ARGUMENT`/`FAILED_PRECONDITION` (cross-domain validate); Create при недоступном IAM (`--require-iam`) → отказ, ресурс не создан (1.4-08); чужой creator без доступа к ресурсу → `403`
**And negative (общий):** malformed id на Get → `INVALID_ARGUMENT`

---

## 5. Матрица трассируемости (сценарий → область → артефакт → репо)

| Сценарии | Область | Артефакты | Репо |
|---|---|---|---|
| 1.4-04, 04(контраст), 05, 23, **21** | transient-no-poison класс (D-5) + метрики (D-7) + **CAS-claim exactly-once `-race` (1.4-21, ban #10)** | `outbox/drainer` (transient vs ErrPermanent классификация; transient не poison'ит; CAS-claim по `id` bigint `FOR UPDATE SKIP LOCKED`), `outbox/metrics` | kacho-corelib |
| 1.4-06, 06a, 07, **07b** | reconciler (D-6): re-drive / derive-from-state backfill (только project-hierarchy, **re-emit через ту же register-outbox-таблицу N6; per-service resource-enumerate = per-service адаптер**) / inverse-orphan GC + **anti-race GC (D-6c, `-race` тест)** | новый `outbox/reconciler` sub-package + per-service enumerate-адаптер | kacho-corelib + per-service |
| 1.4-08, 31, 40 | fail-closed boot-gate (D-8) — **единый канонический режим (N5): NotReady + Create-refuse** | corelib boot-gate helper; per-service wiring; deploy env/probe | kacho-corelib, все сервисы, kacho-deploy |
| 1.4-01, **01b**, 01a, 02, 03, 07a, 09, 20 | apps greenfield SEC-D (D-2) **+ BLOCKER-1 apps-SA `fga_writer`-grant** | НОВАЯ миграция `kacho_apps.fga_register_outbox`+триггер — **N6/N4: `id BIGSERIAL` PK + `resource_kind`/`resource_id` TEXT + event_type CHECK `'fga.register'`/`'fga.unregister'` + `payload JSONB DEFAULT '{}'` (compute-вариант `0010`)** (migration-writer→db-architect-reviewer); in-tx `Insert`/`Delete` (`application.go`); `clients/iam_register_*`; drainer wiring `cmd/apps/main.go`; **+ НОВАЯ kacho-iam-миграция: apps-SA `fga_writer@iam_fgaproxy:system` (зеркало SEC-C `0009`, ban #5 — 0009 не редактируется; детерминированный `'sva'||substr(md5('kacho-apps'),1,17)`, через `fga_outbox` `'fga.tuple.write'`)** | kacho-apps **+ kacho-iam** |
| 1.4-10, 10a, 10b, 11, 12, 13 | iam **best-effort** own-resource/bootstrap/owner-self-grant → in-tx emit (D-3a/D-4) | use-cases account/project/group/service_account/role create+delete (emit в writer-tx, удалить post-commit «Non-fatal»); `internal_upsert.writeBootstrapTuples`; live owner-self-grant (`account/create.go:160`); **intent только `'fga.tuple.write'`/`'fga.tuple.delete'` (N6)**; `WriteCreatorTuple` — dead RPC, НЕ мигрируется; **БЕЗ новой миграции** (`fga_outbox` 0001) | kacho-iam |
| **1.4-14** | iam **AccessBinding УЖЕ-атомарен** (D-3b, backstop-only) | `access_binding/create.go:166` `EmitRelationWrite` — НЕ трогать; структурный гейт «не регрессировать»; symmetric Delete revoke | kacho-iam |
| **1.4-15** | iam live `fga_outbox`-drainer получает S0-backstop (D-9, B3) | reconciler re-drive + метрики + `--require-iam` boot-gate поверх `serve.go:532-547`; `bootstrap_admin.go:90` остаётся in-tx | kacho-iam, kacho-corelib |
| 1.4-30, 31, 32 | vpc/compute/nlb backstop (D-9) | reconciler+метрики+boot-gate wiring; structural-gate сохранён; БЕЗ изменения атомарности, БЕЗ миграции | kacho-vpc, kacho-compute, kacho-nlb |
| 1.4-41 | Internal-only edge + polyrepo + **N5 две outbox-семьи** | `RegisterResource`/`Unregister` :9091 mTLS; **polyrepo.md** новое ребро `apps→iam fgaproxy` (+ запись отсутствующего `apps→iam ProjectService.Get`); edges-doc фиксирует BLOCKER-1-предусловие (apps-SA `fga_writer`) + **N5: каждый сервис держит ДВЕ outbox-семьи (audit `_outbox` vs register `_fga_register_outbox`) — reconciler/метрики НЕ конфлейтят** | kacho-api-gateway, kacho-workspace |
| **1.4-42** | `./sync-tooling.sh` refresh stale rule-копий (N3) | раскат source-of-truth `.claude/rules/{security.md,polyrepo.md}` во все `project/<repo>/.claude/rules/` | kacho-workspace |
| — (out-by-design) | **kacho-geo / DiskType / AddressPool — вне scope** (§3 glossary, §6): нет create-resource→owner-tuple-флоу | НЕТ артефактов (явное исключение для исчерпываемости перечисления флота) | — |
| 1.4-09 | e2e черный ящик (newman) | newman cases happy+negative на apps/vpc/compute/iam | kacho-api-gateway / kacho-test |
| все | vault trail | `packages/corelib-outbox-reconciler` (новый), `packages/corelib-outbox-drainer` (transient-класс), `resources/apps-application` (SEC-D), `edges/apps-to-iam-fgaproxy` (новый — incl. BLOCKER-1 apps-SA `fga_writer`-предусловие), `edges/iam-to-openfga-*`, `rpc/iam-internal-iam` (apps-SA least-priv grant — новая iam-миграция), `KAC/KAC-<N>.md` | kacho-workspace |

---

## 6. Out-of-scope / Non-goals

- **kacho-geo (Region/Zone) — OUT-BY-DESIGN (B1):** глобальные cluster-scoped admin-only каталоги (Internal* :9091, нет `project_id` / нет tenant-владельца; authz через cluster-level `system_viewer`/`system_admin`). **Нет create-resource→owner-tuple-флоу** — `geo_outbox` (`0001_initial.sql:35-49`) — **audit-only** (event_type CREATED/UPDATED/DELETED, sequence_no PK), не пишет и не обязан писать `RegisterResource`. geo включён в перечисление флота явно как out-by-design (исчерпываемость «100%»: in-scope `{corelib, apps, iam, vpc, compute, nlb}` + out-by-design `{geo}` + Internal-каталоги `{DiskType, AddressPool}`).
- **DiskType (compute Internal-каталог) / AddressPool (vpc Internal-admin) — OUT-BY-DESIGN (B1):** Internal-admin-ресурсы без `project_id`/tenant-владельца → нет owner-tuple-семантики; в scope owner-tuple-гарантии НЕ входят.
- **Изменение co-commit-атомарности vpc/compute/nlb** — НЕ трогаем (D-9, уже корректна); только backstop-wiring.
- **Изменение/перенос уже-атомарного iam emit** — `AccessBinding.Create` (`access_binding/create.go:166`) и `seed/bootstrap_admin.go:90` УЖЕ in-tx (D-3b) → НЕ мигрируются, НЕ регрессируются; S2 трогает только best-effort-пути.
- **`WriteCreatorTuple` (`internal_iam/handler.go:184`)** — dead RPC без live-caller (заменён register-outbox'ом в nlb, Issue N5) → НЕ мигрируется в этом эпике; D-4-инвариант кодируется на live owner-self-grant-путях (1.4-11).
- **Новые common-миграции в corelib** для reconciler/метрик — НЕ нужны (работают с существующими per-service outbox-таблицами). Новые миграции эпика — РОВНО ДВЕ: (1) `kacho_apps.fga_register_outbox` (S1, greenfield, N6/N4-форма); (2) **новая kacho-iam-миграция apps-SA `fga_writer`-grant** (BLOCKER-1, S1, зеркало SEC-C 0009 — провижен `service_account:<sva-apps>#fga_writer@iam_fgaproxy:system`, НЕ редактирование 0009).
- **Редактирование применённых миграций** `kacho_iam.{0001 fga_outbox, 0009 sec_c}` / `kacho_vpc` (0006) / `kacho_nlb` (0002) / `kacho_compute` (0010) — запрещено (ban #5); BLOCKER-1-grant добавляется **новой sequential iam-миграцией** (не правкой 0009); iam own-resource emit использует существующую `fga_outbox` (0001) как есть (event_type `'fga.tuple.write'`/`'fga.tuple.delete'`, новых литералов не вводим — N6).
- **«tuple-first + rollback»-механизм заказчика** — осознанно отвергнут (§2.2), не реализуется.
- **Замена corelib-drainer на брокер** (Kafka/NATS) — нет (ban #7); in-process LISTEN/NOTIFY + Postgres-poll.
- **Watch/стриминг outbox-состояния** — нет (`api-conventions.md`: polling, Watch не существует); reconciler — периодический проход + on-demand.
- **Изменение FGA-модели / типов tuple** сверх существующих owner-hierarchy/owner-relation — нет; эмитим уже-определённые tuple-формы.
- **Принудительный backfill owner-self-grant из аудита/логов** — нет (D-4: subject-владелец невосстановим из состояния ресурса; reconciler синтезирует только project-hierarchy).
- **kacho-apps-operator / data-plane** — вне scope (sibling вне build-графа control-plane).

---

## 7. Definition of Done (по стадиям; порядок — build-граф `polyrepo.md`)

**Гейт:** документ получает `✅ APPROVED` от `acceptance-reviewer` до старта `superpowers:writing-plans` → `integration-tester` (RED-тесты) → `rpc-implementer`. После APPROVED статус дока → APPROVED.

**S0 — corelib (`kacho-corelib`) [foundation, блокирует все]:** transient-класс no-poison в `outbox/drainer` (D-5: `Unavailable`/timeout/conn никогда не poison'ят — unbounded backoff; poison только `ErrPermanent`); новый `outbox/reconciler` (D-6: re-drive poisoned / derive-from-state backfill project-hierarchy-only **через ту же transactional register-outbox-таблицу + per-service resource-enumerate-адаптер (N6)** / inverse-orphan GC **с anti-race инвариантом D-6c**); метрики (D-7); fail-closed boot-gate helper (D-8). **TDD RED→GREEN:** integration-тест (testcontainers) на 1.4-04/04-контраст/05/06/06a/07/**07b**/08/23/**21**, **ДВА обязательных concurrent `-race`-теста** (ban #10, `testing.md`): (1) **CAS-claim exactly-once race (1.4-21)** — 2 реплики/N goroutine'ов, каждая intent клеймится/доставляется ровно один раз, (2) **anti-race inverse-orphan GC vs concurrent re-Create (1.4-07b)** — concurrent Create-intent побеждает GC-Unregister, нет self-inflicted access-loss. `go test ./... -race`+`golangci-lint`+`govulncheck` зелёные. Merge ДО сервисов; consumer-CI пиннит corelib к feature-ветке (`polyrepo.md`).

**S1 — apps (`kacho-apps`) + kacho-iam (SEC-C grant) [priority 1]:** (a) новая миграция `kacho_apps.fga_register_outbox`+NOTIFY-триггер (`migration-writer`→`db-architect-reviewer`) — **N6/N4-форма: `id BIGSERIAL` PK (claim/mark по `id`, drainer-compatible — НЕ `sequence_no`) + `resource_kind`/`resource_id` TEXT + `event_type` CHECK `IN ('fga.register','fga.unregister')` + `payload JSONB NOT NULL DEFAULT '{}'` + pending partial-index; вариант compute `0010_fga_register_outbox`**; `Insert` → реальная `pgx.Tx` (INSERT→`EmitRegister`→Commit), `Delete` → `EmitUnregister`; `RegisterResource`-client (`internal/clients/iam_register_*`); drainer wiring `cmd/apps/main.go`; `--require-iam` boot-gate (единый режим N5). (b) **BLOCKER-1 — НОВАЯ kacho-iam-миграция (sequential, ban #5: 0009 APPLIED не редактируем)** провижащая apps-SA + tuple `service_account:<sva-apps>#fga_writer@iam_fgaproxy:system` (зеркало SEC-C `0009`-формы: детерминированный `<sva-apps>='sva'||substr(md5('kacho-apps'),1,17)`, account `'acc'||substr(md5('kacho-system'),1,17)`, через `fga_outbox` `'fga.tuple.write'` + `jsonb_build_object('user','relation','object')`; следовать seed-extend-паттерну `0014`); `db-architect-reviewer` ревьюит обе миграции. **Применяется ДО запуска apps-drainer'а** (иначе первая доставка `PermissionDenied`). **TDD RED→GREEN:** integration (1.4-01/**01b**/01a/02/03/07a/20, concurrent) + newman (1.4-09 happy+negative для apps, в т.ч. без/с grant'ом — 1.4-01b). proto-контракт apps не меняется (только internal edge) — `proto-api-reviewer` не нужен; `db-architect-reviewer` ревьюит обе новые миграции.

**S2 — iam (`kacho-iam`) [priority 1]:** (a) перевод **best-effort** post-commit hierarchy/owner-self-grant на in-tx `fga_outbox`-emit (зеркало уже-атомарного `AccessBinding` `EmitRelationWrite` / `EmitAuditEvent`) в account/project/group/service_account/role Create+Delete, `internal_upsert.writeBootstrapTuples`, live owner-self-grant (`account/create.go:160`); удалить «Non-fatal» post-`DoWithWriteTx` пути; **intent эмитятся ТОЛЬКО как `'fga.tuple.write'`/`'fga.tuple.delete'` (N6, существующие CHECK-литералы — новых не вводить)**. (b) **НЕ трогать** уже-атомарные `AccessBinding.Create` (`access_binding/create.go:166`) и `seed/bootstrap_admin.go:90` — структурный гейт «их in-tx emit не регрессирован»; `WriteCreatorTuple` (dead RPC) НЕ мигрируется. (c) S0-backstop поверх **live `kacho_iam.fga_outbox`-drainer** (`serve.go:532-547`): reconciler re-drive + метрики + `--require-iam` boot-gate (D-9). (d) **N3 repo comment-fix** (попутно): `serve.go:526` / `bootstrap_admin.go:122` «migration 0002» → «migration 0001» (таблица в `0001_initial.sql`; чисто docstring, не меняет поведения). **БЕЗ новой миграции для own-resource emit** (`fga_outbox` 0001; apps-SA-grant-миграция — в S1, не S2). **TDD RED→GREEN:** integration (1.4-10/10a/10b/11/12/13/**14**/**15**, concurrent) + newman (1.4-09 happy+negative для iam Project + AccessBinding grant/revoke). `go test ./... -race`+lint+vuln зелёные.

**S3 — vpc/compute/nlb (`kacho-vpc`/`kacho-compute`/`kacho-nlb`) [backstop]:** wire reconciler + метрики + `--require-iam` boot-gate (единый режим N5); БЕЗ изменения co-commit-атомарности, БЕЗ новой миграции; сохранить structural-gate (`TestSEC_D_07_NoDirectFGAInClients`-аналог). **TDD RED→GREEN:** integration (1.4-30/31/32) + newman (1.4-09 happy для vpc/compute). lint/vuln/race зелёные.

**S4 — api-gateway/deploy/workspace:** `RegisterResource`/`Unregister` остаются Internal-only :9091 (НЕ external, ban #6 — `api-gateway-registrar` подтверждает изоляцию); deploy env `KACHO_<SVC>_REQUIRE_IAM=true` + **единый канонический fail-closed режим (N5): readiness-probe NotReady + Create-refuse** + метрики-scrape/алерты (1.4-40); **polyrepo.md**: добавить ребро `apps→iam fgaproxy (RegisterResource/UnregisterResource)` + записать отсутствующее `apps→iam ProjectService.Get` (ацикличность); **`./sync-tooling.sh` refresh stale rule-копий (N3, 1.4-42)** — раскат обновлённого source `.claude/rules/{security.md,polyrepo.md}` во все `project/<repo>/.claude/rules/`; vault trail (`packages/corelib-outbox-reconciler` новый, `corelib-outbox-drainer` transient-класс, `resources/apps-application` SEC-D, `edges/apps-to-iam-fgaproxy` новый, `KAC/KAC-<N>.md`). Финальная верификация: все newman зелёные, `go test ./... -race`/lint/vuln зелёные во всех затронутых репо; `make audit-list-filter` (где применимо); grep stale-фраз по `project/*/.claude/rules/` пуст.

**Заказчик — финальный smoke/e2e (шаг 7):** в authz-стенде создать Application → немедленно Get/Update/Delete как creator → `200` (не `403`); `make e2e-test` / `grpcurl` на apps/vpc/compute/iam Create→Get-as-creator; убить IAM, попытаться Create при `--require-iam` → отказ, ресурс не создан; reconciler-проход на сидированной legacy-строке без tuple → доступ восстановлен. **BLOCKER-1 smoke:** подтвердить, что apps-SA несёт `fga_writer@iam_fgaproxy:system` (apps register-intent доходит — `outbox_oldest_pending_age_seconds{table="kacho_apps.fga_register_outbox"}` не растёт безгранично, creator-`Check(app)` → ALLOW); контраст — без grant'а intent застревает pending и `Check` → DENY (1.4-01b).

---

## 8. Ссылки

- Workspace правила: `../../CLAUDE.md` (ban #1/#4/#8/#10; vault; corelib reuse)
- `.claude/rules/data-integrity.md` (ban #10 outbox-in-tx, CAS, cross-domain), `.claude/rules/security.md` (mTLS :9091, authz, Internal-vs-public), `.claude/rules/polyrepo.md` (SEC-A/SEC-D, runtime-edges, ацикличность)
- Расширяемый предок: `sub-phase-W1.1-fga-outbox-drainer-acceptance.md`
- Формат-образец: `sub-phase-1.2-iam-operations-acceptance.md`
- corelib drainer (ground-truth): `project/kacho-corelib/outbox/drainer/{drainer.go,internal.go,doc.go}`
- apps gap (ground-truth): `project/kacho-apps/internal/repo/kacho/pg/application.go`, `project/kacho-apps/cmd/apps/main.go`
- iam own-resource gap (ground-truth, best-effort post-commit): `project/kacho-iam/internal/apps/kacho/api/{role,account,group,project,service_account}/create.go` («Non-fatal» `WriteHierarchyTuple`), `user/internal_upsert.go:406-476` (`writeBootstrapTuples` best-effort)
- iam УЖЕ-атомарный образец (ground-truth, НЕ трогать): `project/kacho-iam/internal/apps/kacho/api/access_binding/create.go:166-172` (`EmitRelationWrite` in-tx), `project/kacho-iam/internal/apps/kacho/seed/bootstrap_admin.go:90,133,173` (in-tx), `relationhook/relationhook.go:50` (live `WriteHierarchyTuple` path); dead RPC `internal_iam/handler.go:184` (`WriteCreatorTuple`, нет live-caller)
- iam live drainer (ground-truth, B3): `project/kacho-iam/cmd/kacho-iam/serve.go:532-547` (Table `kacho_iam.fga_outbox`, MaxAttempts:10), `internal/migrations/0001_initial.sql:432,440` (id-bigint PK, event_type CHECK `'fga.tuple.write'`/`'fga.tuple.delete'`)
- canonical SEC-D (ground-truth, N6-форма-образец): `project/kacho-compute/internal/migrations/0010*_fga_register_outbox` (id BIGSERIAL PK + resource_kind/resource_id + event_type CHECK), `project/kacho-nlb/internal/migrations/0002_fga_register_outbox.sql` (+ jsonb_typeof CHECK), `project/kacho-vpc/internal/migrations/0006_fga_register_outbox.sql` (lean-вариант), `project/kacho-vpc/internal/apps/kacho/api/network/create.go`, `project/kacho-compute/internal/clients/no_direct_fga_test.go`; corelib drainer claim-by-`id` `project/kacho-corelib/outbox/drainer/internal.go:174-249`
- out-by-design (ground-truth, B1): `project/kacho-geo/internal/migrations/0001_initial.sql:35-49` (geo_outbox audit-only, нет project_id/RegisterResource), `project/kacho-geo/cmd/kacho-geo/serve.go:147-149` (Region/Zone admin CRUD только :9091)
- **BLOCKER-1 apps-SA fga_writer (ground-truth):** SEC-C seed `project/kacho-iam/internal/migrations/0009_sec_c_module_sa_least_priv.sql` (детерминированный `'sva'||substr(md5('kacho-<svc>'),1,17)` + anchor `'usr'/'acc'||substr(md5('kacho-system'),1,17)` + `fga_writer@iam_fgaproxy:system`-tuple через `fga_outbox` ТОЛЬКО для vpc/compute/nlb; kacho-apps отсутствует во всех iam-миграциях 0001-0015); seed-extend-паттерн-образец `project/kacho-iam/internal/migrations/0014_reader_sa_system_viewer.sql`; gate `project/kacho-iam/internal/apps/kacho/api/internal_iam/handler.go:126,171` + `kacho-proto/proto/kacho/cloud/iam/v1/internal_iam_service.proto:128`; applier-классификация (compute/nlb-форма) `project/kacho-compute/internal/clients/iam_register_applier.go:110-111`, `project/kacho-nlb/internal/clients/iam/register_applier.go:149-172` (InvalidArgument→ErrPermanent; PermissionDenied/Unavailable→raw transient)
- N4 apps payload-shape (ground-truth): `project/kacho-compute/internal/migrations/0010_fga_register_outbox.sql` (id BIGSERIAL + resource_kind/resource_id + payload JSONB DEFAULT '{}'), `project/kacho-compute/internal/fgaintent/fgaintent.go` (Payload `{tuples:[…]}`-набор)
- N3 stale-comment (ground-truth, repo-fix в S2): `project/kacho-iam/cmd/kacho-iam/serve.go:526` + `project/kacho-iam/internal/apps/kacho/seed/bootstrap_admin.go:122` («migration 0002» → факт `0001_initial.sql`)
