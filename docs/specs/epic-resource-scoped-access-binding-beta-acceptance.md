# Epic «Resource-scoped AccessBinding» — Sub-phase β (label+parent mirror sync `compute→iam`) — Acceptance

> **Статус:** ✅ APPROVED (`acceptance-reviewer`, 2026-06-19)
> **Дата:** 2026-06-19
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — ✅ APPROVED (round-1; ground-truth proto/edges/vault сверены; все Q-β1..6 закрыты дефолтами автора — см. вердикт-комментарий; non-blocking: уточнить, что compute label-pattern энфорсится в `kacho-corelib/validate.Labels`, а не в proto-опциях).
> **Эпик/тикет:** epic «Resource-scoped AccessBinding» (вариант C — selector-based grants), под-фаза **β**. Номер KAC проставляется ДО старта `superpowers:writing-plans` (`[EPIC]` + Subtask α/β/γ, `git-youtrack.md`). Затронутые репо под-фазы β: `kacho-proto` / `kacho-compute` / `kacho-iam` / `kacho-deploy` / `kacho-workspace`(docs/vault). vpc — **отдельная волна β2** (D-β8, обоснование ниже).
> **Источник требований (verbatim intent родителя):** «β: label+parent sync `compute→iam` — питает selector И containment. БЕЗ самого selector-движка (он γ). IAM получает и хранит labels + parent-scope каждого compute-ресурса, чтобы γ мог матчить selector и энфорсить containment SAME-DB (без запрещённого ребра iam→compute).»
> **Ground-truth (сверено против кода/proto/vault 2026-06-19):**
> - `kacho-proto/proto/kacho/cloud/iam/v1/internal_iam_service.proto:234-255` — `RegisterResourceRequest { string subject_id = 1; string relation = 2; string object = 3; string trace_id = 4; }`; `RegisterResourceResponse {}` (пустой). `UnregisterResourceRequest` (259-275) — поля идентичны. RPC `RegisterResource`/`UnregisterResource` — **Internal-only :9091, нет `google.api.http`** (ban #6), `<exempt>`-authz + ReBAC `fga_writer @ iam_fgaproxy:system` энфорс в handler. Поля 5/6/7 в `RegisterResourceRequest` **свободны**.
> - `kacho-proto/.../iam/v1/access_binding.proto:162-167` — `ResourceSelector { repeated string types = 1; map<string,string> match_tags = 2; }` — **forward-declared каркас (γ)**; используется в `AccessTarget.selector = 3` (α D-3). Здесь же — кандидат на переименование `match_tags`→`match_labels` (D-β1).
> - `kacho-proto/.../compute/v1/*.proto` — `Instance`/`Disk`/`Image`/`Snapshot` несут `string project_id` + `map<string,string> labels` (валидируемый pattern `[a-z][-_./\@0-9a-z]*` / value `[-_./\@0-9a-z]*`, size `<=64`, key `1-63`). `project_id` известен compute на `Create` ресурса.
> - vault `edges/compute-to-iam-fgaproxy.md` (status **done**, SEC-D): compute пишет owner-tuple-intent в `compute_fga_register_outbox` **в writer-tx ресурса** (`internal/repo/outbox.go::emitFGARegisterIntent`, миграция `0010`); register-drainer (`cmd/compute/main.go::startRegisterDrainer`, `internal/clients/iam_register_applier.go`) → `IAM.RegisterResource` по (opt-in) mTLS. CAS-claim/advisory-lock → exactly-once across replicas. Эмиссия **сегодня только на `Instance.Create`/Delete** (нет Update-триггера). Idempotent (write `already_exists`→OK; delete absent→OK). Error: `InvalidArgument`→poison, прочее→transient retry.
> - vault `edges/vpc-to-iam-fgaproxy.md` (status **planned**, SEC-D): идентичный контракт для vpc-ресурсов; caller-сторона vpc ещё не вызывает ребро на момент β-плана. **→ обоснование compute-first (D-β8).**
> - vault `rpc/iam-internal-iam-service.md`: `RegisterResource` handler (`internal/apps/kacho/api/internal_iam/register_resource.go`) валидирует tuple-грамматику `<type>:<id>` → эмитит в `kacho_iam.fga_outbox` в одной writer-tx → drainer (`clients/fga_applier.go`) применяет к OpenFGA. mTLS-SAN → `sva`-id → ReBAC `fga_writer @ iam_fgaproxy:system`.
> - vault `resources/iam-access-binding.md`: owner-tuple co-commit паттерн kacho-iam (`fga_outbox` + drainer) — образец для co-commit mirror-строки в той же writer-tx (D-β3).
> - **α (APPROVED 2026-06-19):** `AccessBinding.target` oneof `all_in_scope`/`resources[]` рабочие; `selector` forward-declared → `UNIMPLEMENTED`; per-object FGA tuple + tier-tuple. α D-14/D-15 зафиксировали **known-limitation**: target-containment НЕ энфорсится (peer-call `iam→compute` = цикл). **β закрывает данные под D-14** (mirror несёт parent), сам энфорс — γ.
> **Образцы формата:** `epic-resource-scoped-access-binding-alpha-acceptance.md`, `sub-phase-1.5-assignable-roles-acceptance.md`.

---

## Обзор

После α таргетинг binding'а на конкретные объекты (`target.resources[]`) принимает любой well-formed opaque `id` **без** проверки, что объект (а) существует и (б) лежит под `scope` (α-known-limitation D-14: авторитет «`inst.project_id == prj-P`» — у владельца kacho-compute, cross-DB, а peer-call `iam→compute` создал бы **цикл** в графе — `compute→iam` уже существует, `polyrepo.md` non-negotiable). Аналогично, вариант C (`selector` по меткам) нереализуем в γ, пока у IAM нет membership-данных «какие объекты несут метку `env=prod`».

Корень обеих проблем — **у IAM нет локальной (same-DB) копии labels и parent-scope чужих ресурсов**. β устраняет это, **не вводя нового runtime-ребра в запрещённом направлении**: данные приходят по **уже существующему** ребру `compute→iam` (FGA-proxy `RegisterResource`, SEC-D, status done) — то есть consumer (compute) **проталкивает** свои labels+parent в IAM, IAM их **не запрашивает**. Граф остаётся ацикличным (`iam` по-прежнему никого не зовёт).

**Под-фаза β (этот документ)** расширяет `RegisterResource`/`UnregisterResource` (Internal-only :9091) тремя аддитивными полями (`labels`, `parent_project_id`, `parent_account_id`) и заводит в kacho-iam **output-only зеркало** `kacho_iam.resource_mirror` (`object_type, object_id, parent_project_id, parent_account_id, labels jsonb`). compute эмитит расширенный payload на `Instance.Create` **И** `Instance.Update` (когда `labels` в update-mask — **новый** Update-триггер, сегодня RegisterResource только на Create), IAM UPSERT-ит mirror-строку **в той же writer-tx**, что owner-tuple emit (атомарно, ban #10). mirror — **source of truth = compute** (`data-integrity.md` §cross-domain п.3), НЕ источник истины, переживает dangling.

**β только НАПОЛНЯЕТ зеркало.** Ни selector-матчинг, ни containment-гейт в β **не читают** mirror для authz-решений — это под-фаза γ. Документ описывает только внешне наблюдаемое поведение Internal-API и состояние зеркала (через смежные Internal-read для верификации), не реализацию. Сценарии трассируются в имена integration-/newman-тестов через ID `β-<NN>`.

---

## 0.1 Карта эпика (контекст/декомпозиция — детальные сценарии ТОЛЬКО для β)

Финальная целевая модель `AccessBinding` — **5 измерений**:
`{ subject{type,id}, roleId(verb-bundle), scope{tier,id}, target<all|byName|bySelector>, condition<none|expiry|forward> }`.

| Под-фаза | Содержание | Статус в этом доке |
|---|---|---|
| **α** (DONE, в проде fe3455) | `AccessBinding.target` oneof: `all_in_scope` + `resources[]` (per-object по id) рабочие; `selector` forward-declared → `UNIMPLEMENTED`. Role-coverage гейт. Per-object FGA tuple + hierarchyParentTuple. Containment **не** энфорсится (known-limitation D-14). | **Вне scope β** (предшественник) |
| **β** (ЭТОТ док) | **label + parent sync `compute→iam`** по существующему FGA-proxy-ребру. `RegisterResource` += `labels`/`parent_project_id`/`parent_account_id`; новая таблица `kacho_iam.resource_mirror` (output-only зеркало); эмиссия на `Instance.Create` **И** `Instance.Update(labels)`; UPSERT-mirror co-commit с owner-tuple. **Питает selector И containment, но БЕЗ самого selector-движка** (он γ). compute-first; vpc — β2. | **Сценарии β-01..β-16 ниже** |
| **γ** (future — упомянуть) | reconciler: `bySelector`→tuples (снять `UNIMPLEMENTED`) **читая `resource_mirror.labels`** + containment-энфорс (`target.resources[].id` под scope — проверка `resource_mirror.parent_*`) + expiry eager-revoke. Это рабочий вариант C. | **Вне scope β** (forward-ref); β лишь наполняет mirror, γ его читает |
| **condition** (future, с γ) | 5-е измерение `condition<none|expiry|forward>`; рабочий ТОЛЬКО `non_expired` (TTL через `expires_at`→eager-revoke); прочие builtin (`mfa`/`ip`/`business`/`device`) — schema-only forward. | **Вне scope β** (forward-ref) |
| **δ** (future, отдельная волна) | Аддитивная **non-breaking** чистка формы: `scope{tier,id}` + `target.all/byName/bySelector` — канонические; старые `resourceType/resourceId/resources/all_in_scope` → deprecated через проекцию. | **Вне scope β** (forward-ref) |

> **Уточнение карты (β vs. ранний α-map):** α-acceptance в своей карте упоминал β как «governance-managed IAM Tags (новые ресурсы `Tag`/`TagBinding`)». Родитель **пересмотрел** β: источник membership меток — **labels самого владельца, зеркалируемые в IAM** (не отдельные IAM-Tag-ресурсы). Privilege-escalation-риск («tenant правит label своего ресурса → расширяет себе доступ») сохраняется как **открытый вопрос Q-β1** и адресуется в γ при энфорсе selector (mirror в β только наполняется, для authz не читается). Это намеренное решение родителя (см. требования: только прод-код / best-practice 2026 / польза продукту) — фиксируется здесь, чтобы не переоткрывать.

---

## 0. Фиксированные дизайн-решения (предлагаются автором; подлежат approve ревьюером — затем НЕ переоткрывать)

| ID | Решение | Обоснование |
|---|---|---|
| **D-β1** | **`RegisterResourceRequest` / `UnregisterResourceRequest` += аддитивные поля**: `map<string,string> labels = 5`, `string parent_project_id = 6`, `string parent_account_id = 7`. Поля **optional** (back-compat: старый compute их не шлёт → пустые). Поле-номера 5/6/7 в обоих сообщениях свободны (ground-truth proto:234-275). `Unregister` несёт те же поля для симметрии формы, но семантически Unregister использует только `object` (mirror-row удаляется по PK). **Переименование `ResourceSelector.match_tags`→`match_labels`** (access_binding.proto:167) — относится к γ (selector-движок), но как proto-правка может быть сделано в β-proto-PR (один buf-проход). | Аддитивные scalar/map-поля — `buf breaking` зелёный (back-compat). `labels` — копия владельца (для γ-selector-матчинга). `parent_project_id`/`parent_account_id` — parent-scope (для γ-containment: «объект под scope» = mirror.parent == scope-anchor, SAME-DB, без цикла — закрытие α D-14). compute знает `project_id` на Create инстанса; `account_id` — через `project→account` (compute уже резолвит для FGA hierarchy-tuple). `match_labels` точнее `match_tags` (Kachō-термин — `labels`, не `tags`); переименование сейчас — чтобы γ не делал breaking. |
| **D-β2** | **Источник истины mirror — kacho-compute (owner).** `kacho_iam.resource_mirror` — **output-only зеркало** (`data-integrity.md` §cross-domain п.3): не источник истины, не валидируется на вход публичного API, переживает dangling. β **наполняет** его на каждом `RegisterResource`-payload; **никакой публичный/Internal authz-read β не делает на основе mirror** (это γ). | Mirror — денормализованная копия чужих labels+parent для будущего SAME-DB-матчинга/containment. Делая его источником истины, IAM нарушил бы single-owner (`data-integrity.md` п.1). Не читая его для authz в β, мы держим β чисто инфраструктурным (наполнение), без изменения текущей authz-поверхности. |
| **D-β3** | **mirror-UPSERT co-commit в той же writer-tx, что owner-tuple emit (ban #10).** Handler `RegisterResource` пишет mirror-строку (UPSERT) **И** owner-tuple-intent в `kacho_iam.fga_outbox` **в одной writer-tx** — оба коммитятся атомарно или откатываются вместе. Нет «tuple есть, mirror нет» split-brain. `UnregisterResource` симметрично удаляет mirror-строку **И** эмитит tuple-revoke в той же tx. | Существующий kacho-iam-паттерн (`fga_outbox`+drainer co-commit, vault `iam-to-openfga-grant-write` / `resources/iam-access-binding`). mirror — ещё одна запись в той же tx. Within-service атомарность — DB-уровень (одна tx), не software two-phase (ban #10). |
| **D-β4** | **DB-форма (ориентир для `db-architect-reviewer`).** Таблица `kacho_iam.resource_mirror`: `object_type TEXT`, `object_id TEXT`, `parent_project_id TEXT`, `parent_account_id TEXT`, `labels JSONB NOT NULL DEFAULT '{}'`, `updated_at TIMESTAMPTZ`; **PK `(object_type, object_id)`**; **GIN-индекс на `labels`** (для γ-selector-матчинга `labels @> {...}`). UPSERT — `INSERT … ON CONFLICT (object_type,object_id) DO UPDATE SET labels=…, parent_*=…, updated_at=now()`. **БЕЗ FK** на compute-таблицы (cross-DB, ban #4/#8 — soft-ref). | PK на `(type,id)` гарантирует одну строку на объект → UPSERT-идемпотентность (at-least-once drainer retry, D-β5). GIN на JSONB — γ будет искать `labels @> {env:prod}` (read-side, не β). Within-service инвариант на DB-уровне (ban #10): UPSERT-on-PK сериализует конкурентные writes (D-β6), не software check-then-act. cross-DB → нет FK (soft-ref, dangling переживается). Точная DDL — `migration-writer`/`db-architect-reviewer`. |
| **D-β5** | **Идемпотентность сохраняется (at-least-once drainer, SEC-D).** Повтор `RegisterResource` с тем же `(object, labels, parent)` (retry дренера) → mirror-строка **не дублируется** (UPSERT на PK), owner-tuple OK (как сегодня). Повтор с **изменёнными** labels → mirror обновляется (last-payload-wins per-object). `UnregisterResource` отсутствующего объекта → OK (mirror delete absent — no-op), как сегодняшний tuple-revoke-absent. | Drainer гарантирует at-least-once, не exactly-once (vault `edges/compute-to-iam-fgaproxy`); UPSERT/DELETE-on-PK делает повтор безопасным by-construction. Контракт идемпотентности `RegisterResource` (proto:118 «повтор → OK, не AlreadyExists») расширяется на mirror без изменения семантики. |
| **D-β6** | **Update-триггер на стороне compute — НА `labels`-mask (НЕ на все поля).** Сегодня `emitFGARegisterIntent` эмитит **только** на `Instance.Create`/Delete. β добавляет эмиссию на `Instance.Update` **тогда и только тогда, когда `labels` присутствует в `update_mask`** (динамика меток для γ-selector). Прочие mutable-поля (name/description/…) **НЕ** триггерят register-intent (они не влияют ни на labels-membership, ни на parent — parent immutable у инстанса). Эмиссия — в той же writer-tx Update-ресурса (как сегодня на Create). | Эмитить на все Update — лишний трафик/intent'ы без смысла (selector матчит только labels; containment — parent, который immutable). `labels`-mask-триггер — минимальный необходимый для динамики «dev→prod». parent (`project_id`) у инстанса immutable (`api-conventions.md` update_mask discipline) → его не нужно re-эмитить. _(Открытый вопрос Q-β2: достаточно ли labels-mask или нужен и иной триггер — для ревьюера.)_ |
| **D-β7** | **mirror-row — UPSERT-обновляемая (НЕ immutable).** В отличие от `AccessBinding` (immutable по форме), mirror-строка по дизайну **изменяема** (last-write на `(labels, parent_*, updated_at)`) — она зеркалит изменяемое состояние владельца. Это согласуется с output-only-зеркалом (обновляется на каждом payload, п.3 cross-domain). concurrent-write одного объекта → детерминированный last-write через UPSERT-on-PK (row-lock), без дублей/полу-записи (D-β6, ban #10 integration-тест с goroutines). | Зеркало по определению mutable (отражает текущее состояние источника). Immutability нарушила бы «labels dev→prod» (β-04). Конкурентная консистентность — DB-уровень (UPSERT-on-PK), не software (ban #10). _(Открытый вопрос Q-β3: immutability-семантика mirror-row vs. upsert — подтвердить.)_ |
| **D-β8** | **Scope β = compute-first; vpc — отдельная волна β2.** β реализует расширение payload + mirror-наполнение **только для kacho-compute** (ребро `compute→iam` status **done**, SEC-D — caller-сторона живёт). kacho-vpc — то же ребро, но status **planned** (vpc ещё НЕ вызывает FGA-proxy на момент β; vault `edges/vpc-to-iam-fgaproxy`). proto-поля (D-β1) и mirror-таблица (D-β4) — **уже generic** (`object_type` любой), так что β2 (vpc) = только caller-сторона vpc + newman, без proto/iam-изменений. | **Обоснование compute-first:** (1) compute caller-сторона done → меньше связанного риска; (2) per-object таргетинг в α демонстрировался на `compute.instance` (α-01) → compute-mirror раньше всего нужен γ; (3) mirror generic by-design → vpc подключается без re-проектирования IAM-стороны; (4) меньший blast-radius на один deliverable (`polyrepo.md` — стадии самостоятельны). β2 — Subtask эпика, идентичный β-контракт на vpc-ресурсах. |
| **D-β9** | **β НЕ меняет authz-поверхность и НЕ читает mirror для решений.** Расширенный payload идёт по существующему Internal-only :9091-ребру (ban #6), least-priv `fga_writer @ iam_fgaproxy:system` (SEC-C) — **без изменений**. mirror **не** влияет на `Check`/`ListPermissions`/containment в β (это γ). Никакого нового публичного RPC β не вводит. | β — чисто инфраструктурное наполнение. Энфорс (чтение mirror для selector/containment) изолирован в γ → β не может регрессировать текущую authz. mTLS-SAN/ReBAC-гейт RegisterResource не зависит от добавленных полей (authz по subject-cert, не по payload-content). |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `security.md` §Internal-vs-external (ban #6) — `RegisterResource`/`UnregisterResource` Internal-only :9091, нет `google.api.http`, не на external | D-β1, D-β9, β-13 |
| `security.md` §AuthN+AuthZ ВЕЗДЕ — Internal-листенер не освобождён: mTLS + ReBAC `fga_writer @ iam_fgaproxy:system` (SEC-C) на каждом RegisterResource; расширенный payload authz не меняет | D-β9, β-11, β-12 |
| `security.md` §Инфра-чувствительные данные — mirror несёт только tenant-facing labels + parent-scope-id (не placement/underlay/wiring); β не вводит публичного read mirror | D-β2, D-β4, β-16 |
| `data-integrity.md` §within-service (ban #10) — mirror UPSERT-on-PK + co-commit owner-tuple в одной writer-tx; concurrent-write → integration-тест с goroutines | D-β3, D-β4, D-β6, D-β7, β-05 |
| `data-integrity.md` §cross-domain — mirror = output-only зеркало (source of truth = compute, п.3); `object_id` opaque soft-ref **без FK** (ban #4/#8); dangling переживается (п.4) | D-β2, D-β4, β-07, β-08 |
| `data-integrity.md` §cross-domain п.6 + `polyrepo.md` «циклы запрещены» — β НЕ вводит ребра `iam→compute/vpc`; данные текут по существующему `compute→iam` (consumer проталкивает, IAM не запрашивает) — ацикличность сохранена | Обзор, D-β2, §6 DoD (system-design-reviewer подтверждает) |
| `api-conventions.md` — `RegisterResource` остаётся **sync** Internal RPC (как сегодня, vault `rpc/iam-internal-iam-service`); НЕ async (это FGA-proxy intent, не tenant-мутация ресурса) | D-β1, β-01 |
| `api-conventions.md` update_mask discipline — Update-триггер на compute эмитит mirror-refresh при `labels` в mask; immutable `project_id` не re-эмитится | D-β6, β-04 |
| `00-kacho-core.md` ban #10 (within-DB инвариант), #4 (same-DB cascade ОК / cross-DB FK нет), #8 (нет shared БД), #12 (TDD), #1 (APPROVED перед кодом) | D-β3/D-β4 co-commit/UPSERT; cross-DB soft-ref; §6 DoD (RED→GREEN) |
| at-least-once transactional-outbox (SEC-D, vault `edges/compute-to-iam-fgaproxy`) — расширенный payload по тому же drainer; idempotent UPSERT/DELETE-on-PK | D-β5, β-06 |
| `polyrepo.md` §порядок merge | §6 DoD: proto → compute → iam → deploy → workspace(docs); vpc — β2 |
| α (APPROVED) — D-14 known-limitation (containment не энфорсится) закрывается **данными** в β; сам энфорс — γ | Обзор, D-β2, 0.1 карта |

---

## 2. Модель данных и поток (нормативно — D-β1/D-β3/D-β4)

### 2.1 Форма расширенного payload (proto-ориентир — финал за `proto-api-reviewer`)

```
// internal_iam_service.proto — RegisterResourceRequest (аддитивно к ground-truth 1-4):
message RegisterResourceRequest {
  string              subject_id        = 1;   // (существует) FGA-subject
  string              relation          = 2;   // (существует) owner-tuple relation
  string              object            = 3;   // (существует) "<type>:<id>", напр. compute_instance:inst-abc
  string              trace_id          = 4;   // (существует) optional
  map<string,string>  labels            = 5;   // NEW (β) — копия labels владельца (для γ-selector)
  string              parent_project_id = 6;   // NEW (β) — parent-scope (для γ-containment)
  string              parent_account_id = 7;   // NEW (β) — parent-scope (для γ-containment)
}
// UnregisterResourceRequest — те же поля 5/6/7 для симметрии (семантически Unregister по object)

// access_binding.proto:162 (proto-правка β, относится к γ-движку):
message ResourceSelector { repeated string types = 1; map<string,string> match_labels = 2; }  // was match_tags
```

### 2.2 Зеркало `kacho_iam.resource_mirror` (DB-ориентир — финал за `db-architect-reviewer`)

| Колонка | Тип | Назначение |
|---|---|---|
| `object_type` | TEXT (PK ч.1) | тип объекта (`compute.instance`, …; из FGA-object `<type>:<id>`) |
| `object_id` | TEXT (PK ч.2) | opaque object-id (soft-ref, без FK — cross-DB) |
| `parent_project_id` | TEXT | parent-scope для γ-containment (объект под project) |
| `parent_account_id` | TEXT | parent-scope для γ-containment (объект под account) |
| `labels` | JSONB NOT NULL DEFAULT `'{}'` | копия labels владельца (GIN-индекс — γ матчит `@>`) |
| `updated_at` | TIMESTAMPTZ | last-write маркер (UPSERT) |

> **Поток (β, ацикличность сохранена):** `Instance.Create`/`Update(labels)` в kacho-compute → `emitFGARegisterIntent` пишет расширенный intent (labels+parent) в `compute_fga_register_outbox` **в writer-tx ресурса** → register-drainer → `IAM.RegisterResource(...labels, parent_*)` по mTLS → handler UPSERT `resource_mirror` **И** owner-tuple-emit в `fga_outbox` **в одной IAM writer-tx** → fga-drainer применяет tuple к OpenFGA. `Instance.Delete` → `UnregisterResource` → mirror-delete + tuple-revoke в одной tx. **IAM никого не зовёт обратно** (mirror наполняется push-ем consumer'а, не pull-ом IAM → нет ребра `iam→compute`).

---

## 3. Глоссарий: текущее состояние (ground-truth) и дельта β

| Сущность | Текущее состояние | Дельта под-фазы β |
|---|---|---|
| `RegisterResourceRequest` (поля 1-4) | `subject_id`/`relation`/`object`/`trace_id`; sync Internal :9091 | **+= `labels=5`, `parent_project_id=6`, `parent_account_id=7`** (аддитивно, optional; D-β1) |
| `RegisterResource` handler (kacho-iam) | валидирует tuple → emit owner-tuple в `fga_outbox` (writer-tx) → drainer→OpenFGA | **+ UPSERT `resource_mirror`-строки в ТОЙ ЖЕ writer-tx** (co-commit, D-β3) |
| `UnregisterResource` handler | tuple-revoke в `fga_outbox` (writer-tx); absent→OK | **+ DELETE `resource_mirror`-строки в той же tx** (симметрия, D-β3) |
| `kacho_iam.resource_mirror` | **НЕ существует** | **НОВАЯ** output-only таблица (PK `(object_type,object_id)`, GIN на labels; D-β4) |
| `emitFGARegisterIntent` (kacho-compute) | эмитит на `Instance.Create`/Delete; payload `{subject,relation,object,trace}` | **+ labels+parent в payload**; **+ эмиссия на `Instance.Update` когда `labels` в update-mask** (D-β6) |
| register-drainer / applier (compute) | шлёт `RegisterResource` по mTLS; CAS-claim exactly-once-across-replicas; idempotent retry | шлёт **расширенный** payload (тот же drainer, +поля); idempotent (UPSERT-on-PK, D-β5) |
| `ResourceSelector` (access_binding.proto) | `{ types, match_tags }` forward-declared (γ) | `match_tags`→`match_labels` (proto-правка β, движок — γ; D-β1) |
| mirror read для authz (selector/containment) | — | **НЕ в β** (γ читает mirror; β только наполняет — D-β2/D-β9) |
| vpc-сторона (`vpc→iam` FGA-proxy) | status planned (vpc ещё не вызывает ребро) | **НЕ в β** — отдельная волна **β2** (D-β8); proto/mirror уже generic |

---

## §A — Backend: расширенный `RegisterResource` наполняет mirror (compute→iam)

gRPC: `kacho.cloud.iam.v1.InternalIAMService/RegisterResource` (**sync, Internal-only :9091**, нет REST на external — ban #6). Верификация состояния mirror в integration-тестах — прямым чтением `resource_mirror` (testcontainers) либо через смежный Internal-read (если появится в γ); в β публичного read mirror НЕТ.

### Сценарий β-01: Happy path — Create compute-instance с labels → mirror-строка появляется (eventually)

**ID:** `β-01`

**Given** kacho-compute и kacho-iam подняты; ребро `compute→iam` FGA-proxy (mTLS, SEC-D) включено
**And** проект `prj-P` под account `acc-A`
**And** caller создаёт инстанс `inst-abc` под `prj-P` с `labels = {"env":"dev","team":"core"}`

**When** `Instance.Create` коммитится (compute writer-tx: ресурс + register-intent в `compute_fga_register_outbox`); register-drainer дренит intent → `IAM.RegisterResource` по mTLS с payload:
  - `object` = `"compute_instance:inst-abc"`
  - `relation` = `"parent"` (owner-hierarchy, как сегодня)
  - `labels` = `{"env":"dev","team":"core"}`
  - `parent_project_id` = `"prj-P"`, `parent_account_id` = `"acc-A"`

**Then** RPC возвращает `RegisterResourceResponse{}` (sync `OK`)
**And** eventually (после дренажа) в `kacho_iam.resource_mirror` появляется строка `(object_type="compute.instance", object_id="inst-abc", parent_project_id="prj-P", parent_account_id="acc-A", labels={"env":"dev","team":"core"})`
**And** owner-tuple `compute_instance:inst-abc` эмитится в `fga_outbox` **в той же IAM writer-tx**, что UPSERT mirror (атомарно — D-β3; нет «tuple без mirror»)

### Сценарий β-02: Happy path — payload без labels (пустой map) → mirror-строка с пустыми labels

**ID:** `β-02`

**Given** инстанс `inst-nolabels` создаётся без labels (compute шлёт `labels={}` либо опускает поле)

**When** `IAM.RegisterResource` с `object="compute_instance:inst-nolabels"`, `labels={}` (или отсутствует), `parent_project_id="prj-P"`

**Then** sync `OK`; mirror-строка появляется с `labels={}` (JSONB DEFAULT `'{}'`, D-β4) и заполненным `parent_project_id`
**And** строка валидна для γ-containment (parent есть), но не матчит ни один label-selector (labels пусты) — graceful

### Сценарий β-03: Conformance — owner-tuple и mirror-row атомарны (co-commit в одной tx)

**ID:** `β-03`

**Given** `IAM.RegisterResource` для `compute_instance:inst-atomic` (labels+parent заполнены)

**When** handler выполняет writer-tx: UPSERT mirror-row + emit owner-tuple-intent в `fga_outbox`

**Then** оба эффекта видны **вместе** после commit (mirror-строка + outbox-строка present); промежуточного состояния «tuple-intent есть, mirror нет» (или наоборот) read'ом не наблюдается (одна tx, ban #10 — D-β3)
**And** _Обоснование для `integration-tester`/`db-architect-reviewer`:_ симуляция rollback (искусственная ошибка после mirror-UPSERT, до commit) → **ни** mirror-строки, **ни** outbox-строки (atomic abort). Тест на одной IAM-tx, не software two-phase.

### Сценарий β-04: Happy path — Update instance labels (dev→prod) → mirror обновляется (UPSERT)

**ID:** `β-04`

**Given** инстанс `inst-abc` уже зеркалирован (β-01, `labels={"env":"dev"}`)
**And** caller вызывает `Instance.Update` с `update_mask=["labels"]`, `labels={"env":"prod","team":"core"}`

**When** compute коммитит Update (writer-tx ресурса + register-intent — **новый Update-триггер** на `labels`-mask, D-β6); drainer → `IAM.RegisterResource` с обновлённым `labels`

**Then** sync `OK`; mirror-строка `(compute.instance, inst-abc)` обновляется (UPSERT-on-PK): `labels={"env":"prod","team":"core"}`, `updated_at` продвинулся
**And** строка **не** дублируется (PK `(object_type,object_id)`, D-β4); `parent_*` без изменений
**And** подтверждает динамику меток для γ-selector (объект «перешёл» из `env=dev` в `env=prod`)

### Сценарий β-04b: Conformance — Update НЕ-labels поля (name/description) → register-intent НЕ эмитится

**ID:** `β-04b`

**Given** зеркалированный `inst-abc`

**When** caller вызывает `Instance.Update` с `update_mask=["name"]` (без `labels`)

**Then** compute **НЕ** эмитит register-intent (триггер только на `labels`-mask — D-β6); mirror-строка `inst-abc` **не** меняется (`updated_at` тот же)
**And** _Обоснование:_ name/description не влияют ни на label-membership, ни на parent (immutable) → лишний intent не нужен (минимальный необходимый триггер)

### Сценарий β-05: Concurrency — параллельные Update labels одного объекта → mirror отражает last-write консистентно

**ID:** `β-05`

**Given** зеркалированный `inst-race`

**When** запускаются **две конкурентные** `IAM.RegisterResource` для `compute_instance:inst-race` с разными labels (`{"env":"dev"}` и `{"env":"prod"}`) — симуляция двух дренажей/двух близких Update

**Then** **обе** RPC `OK`; в `resource_mirror` ровно **одна** строка `(compute.instance, inst-race)` (не две — PK сериализует, D-β4)
**And** финальный `labels` — детерминированно один из двух (last-write на row-lock через UPSERT-on-PK), **не** «полу-записанный»/смешанный (ban #10 — D-β6/D-β7)
**And** _Обоснование для `integration-tester`/`db-architect-reviewer`:_ `INSERT … ON CONFLICT (object_type,object_id) DO UPDATE` на одной row — row-lock сериализует конкурентов; concurrent-non-regression тест (testcontainers, ≥2 goroutine) **ОБЯЗАТЕЛЕН** (RED-first, `data-integrity.md` §within-service п.5).

### Сценарий β-06: Idempotency — повторный RegisterResource (drainer retry) → mirror не дублируется

**ID:** `β-06`

**Given** mirror-строка `(compute.instance, inst-abc)` уже есть (β-01)

**When** register-drainer повторяет тот же `RegisterResource` (at-least-once retry, SEC-D) с идентичным payload (`object`, `labels`, `parent_*`)

**Then** sync `OK` (не `ALREADY_EXISTS` — контракт идемпотентности, proto:118)
**And** mirror-строка **не** дублируется и не меняется по содержанию (UPSERT-on-PK no-op-эквивалент; `updated_at` может продвинуться — допустимо, D-β5); owner-tuple OK
**And** FGA-tuple-set не растёт (idempotent emit, как сегодня)

### Сценарий β-07: Delete instance → Unregister → mirror-строка удалена + owner-tuple снят (симметрия)

**ID:** `β-07`

**Given** зеркалированный `inst-abc` (mirror-строка + owner-tuple present)

**When** caller вызывает `Instance.Delete`; compute эмитит `unregister`-intent в writer-tx; drainer → `IAM.UnregisterResource(object="compute_instance:inst-abc")`

**Then** sync `OK`; mirror-строка `(compute.instance, inst-abc)` **удалена** **И** owner-tuple-revoke эмитится в `fga_outbox` — **в одной IAM writer-tx** (симметрия co-commit, D-β3)
**And** последующий drainer-pass снимает tuple из OpenFGA; mirror-строки больше нет
**And** _Примечание:_ это same-DB delete внутри kacho_iam (mirror-row + outbox-row), НЕ cross-service cascade (ban #4) — compute самостоятельно инициировал Unregister, IAM не звал compute обратно

### Сценарий β-08: Cross-service — dangling: compute-объект исчез без Unregister → mirror-строка переживает graceful

**ID:** `β-08`

**Given** mirror-строка `(compute.instance, inst-orphan)` есть; затем compute-объект исчез аномально (напр. потерян unregister-intent, или объект удалён вне нормального flow) — cross-DB, без cascade в IAM (ban #4)

**When** что-либо в IAM читает `resource_mirror` (в β — только integration-верификация; в γ — selector/containment)

**Then** строка `inst-orphan` остаётся (stale), чтение **не** паникует; IAM не спрашивает compute (нет ребра `iam→compute` — `data-integrity.md` §cross-domain п.4)
**And** _Примечание (для γ):_ stale mirror-строка — допустимая деградация; reconciler γ может вычищать orphan'ы по eventual-verify, но это **вне β**. В β mirror просто переживает dangling без влияния на authz (mirror для решений не читается — D-β9)

### Сценарий β-09: Backward-compat — старый compute (payload без новых полей) → mirror-строка с пустыми labels/parent

**ID:** `β-09`

**Given** kacho-iam обновлён (поля 5/6/7 + mirror), но caller — **старый** compute (до β), шлёт `RegisterResource` только с полями 1-4

**When** `IAM.RegisterResource(object="compute_instance:inst-legacy", subject_id, relation)` без `labels`/`parent_*`

**Then** sync `OK` (back-compat — поля optional, D-β1); mirror-строка появляется с `labels={}`, `parent_project_id=""`, `parent_account_id=""` (graceful — нет данных для γ-матчинга/containment, но не ошибка)
**And** owner-tuple эмитится как раньше (proto аддитивен — `buf breaking` зелёный); старый compute продолжает работать без изменений

### Сценарий β-10: Backward-compat — proto аддитивность (новый iam ↔ старый/новый compile)

**ID:** `β-10`

**Given** proto-изменение D-β1 (поля 5/6/7 + `match_tags`→`match_labels`)

**When** прогоняется `buf lint` / `buf breaking` против baseline

**Then** `buf breaking` **зелёный**: добавление scalar/map-полей с новыми field-номерами — backward-compatible
**And** `match_tags`→`match_labels` — переименование field-**имени** при сохранении field-**номера** (`= 2`): wire-compat (по номеру), но JSON-имя меняется → отметить как осознанную правку для `proto-api-reviewer` (selector ещё `UNIMPLEMENTED` в проде, JSON-имя не имеет live-потребителей — безопасно)
**And** `gen/go/...` регенерирован и закоммичен

### Сценарий β-11: AuthZ — least-priv mTLS-SAN compute-SA не меняется расширенным payload

**ID:** `β-11`

**Given** compute-SA с mTLS client-cert SAN `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-compute` → `sva`-id → ReBAC `fga_writer @ iam_fgaproxy:system` (SEC-C)

**When** compute вызывает расширенный `RegisterResource` (с labels+parent) по mTLS

**Then** authz-гейт (`authzguard.FGAProxyGate`) проходит как раньше — решение по subject-cert, **не** по payload-content (D-β9); расширенные поля не влияют на Check
**And** payload принимается, mirror наполняется

### Сценарий β-12: Negative — caller без `fga_writer`-relation → PERMISSION_DENIED (расширенный payload не обходит гейт)

**ID:** `β-12`

**Given** сторонний SA (или модуль) **без** relation `fga_writer @ iam_fgaproxy:system`

**When** он вызывает `RegisterResource` с валидным расширенным payload (labels+parent)

**Then** gRPC `PERMISSION_DENIED` (least-priv ReBAC, SEC-C) — **до** записи mirror/tuple
**And** mirror-строка **не** появляется; добавление полей β **не** ослабило authz (D-β9)

### Сценарий β-13: Conformance — RegisterResource не публикуется на external endpoint (ban #6)

**ID:** `β-13`

**Given** kacho-iam с external TLS listener (`api.kacho.local:443`) и internal :9091

**When** клиент пытается достучаться до `RegisterResource`/`UnregisterResource` через external endpoint / api-gateway external mux

**Then** метод **недоступен** на external (нет `google.api.http`, Internal-only — ban #6; newman `iam-internal-only-check`-стиль)
**And** расширение payload (β) **не** добавляет публичной поверхности — метод остаётся :9091-only (D-β1/D-β9)

### Сценарий β-14: Negative — malformed `object` (нарушение `<type>:<id>` грамматики) → INVALID_ARGUMENT (sync)

**ID:** `β-14`

**Given** аутентифицированный compute-SA (mTLS OK)

**When** `RegisterResource` с `object="compute_instance"` (без `:<id>`) или с `#`/whitespace в object

**Then** sync `INVALID_ARGUMENT` (tuple-грамматика `<type>:<id>` нарушена — существующая валидация handler'а, vault `rpc/iam-internal-iam-service`); mirror-строка **не** появляется
**And** error-маппинг на стороне дренера: `InvalidArgument` → **poison** (no retry, SEC-D) — расширенный payload не меняет это поведение

### Сценарий β-15: Negative — невалидные labels (нарушение Kachō label-pattern) → INVALID_ARGUMENT (sync)

**ID:** `β-15`

**Given** compute-SA (mTLS OK)

**When** `RegisterResource` с `labels={"ENV":"x"}` (uppercase key — нарушает Kachō label-key pattern `[a-z][-_./\@0-9a-z]*`) или значением вне `[-_./\@0-9a-z]*` / превышением size

**Then** sync `INVALID_ARGUMENT`, message в стиле `"Illegal argument labels"` (валидация на IAM-стороне зеркалит compute label-constraints; форматный отказ первым стейтментом, `api-conventions.md`); mirror-строка **не** появляется
**And** _Примечание (Q-β4 для ревьюера):_ compute уже валидирует labels на своём Create/Update (proto-pattern) — нужно ли IAM повторно валидировать payload-labels, или довериться upstream-валидации owner'а? Предложение автора: **минимальная sanity-валидация на IAM** (defense-in-depth, не дублируя полный pattern) — payload приходит по mTLS от доверенного, но IAM не должен слепо UPSERT-ить произвольный JSONB. Финал — за ревьюером/`db-architect-reviewer`.

### Сценарий β-16: Conformance — mirror несёт только tenant-facing labels + parent-scope (без инфра-полей)

**ID:** `β-16`

**Given** зеркалированный `inst-abc`

**When** строка `resource_mirror` инспектируется (integration)

**Then** строка содержит **только** `object_type`, `object_id`, `parent_project_id`, `parent_account_id`, `labels`, `updated_at` — все tenant-facing (`security.md` §Инфра-чувствительные данные)
**And** **нет** placement/underlay/wiring/числового инфра-id (compute их и не шлёт в `RegisterResource`-payload — он не для инфры, а для owner-hierarchy + γ-матчинга)
**And** β **не** вводит публичного/Internal read mirror, отдающего эти поля наружу (наполнение only — D-β2/D-β9)

---

## 4. Открытые вопросы для `acceptance-reviewer`

> Эти вопросы автор выносит на review (в отличие от зафиксированных D-β*). После approve — закрываются и НЕ переоткрываются.

| # | Вопрос | Предложение автора |
|---|---|---|
| **Q-β1** | **Privilege-escalation: labels — источник истины владельца, а tenant может править label своего ресурса.** В γ `selector` по `match_labels` будет давать доступ; tenant, добавив `env=prod` своему инстансу, мог бы попасть под чужой prod-grant. β только наполняет mirror (не энфорсит), но решение влияет на форму данных. | β **не** энфорсит → риск **не** материализуется в β. Адресуется в **γ** при энфорсе selector (напр. selector-grant'ы — только под grant-authority того, кто владеет scope; label-membership доверяется в пределах одного scope-owner). Зафиксировать как γ-known-concern. Альтернатива (governance-managed IAM-Tags из раннего α-map) — отвергнута родителем. **Подтвердить, что β-форма (owner-labels в mirror) приемлема, риск делегирован γ.** |
| **Q-β2** | **Update-триггер: только `labels`-mask или иные поля?** (D-β6) | Только `labels`-mask (parent immutable; name/description не влияют на selector/containment). Если в будущем parent станет mutable (re-parent инстанса) — добавить триггер на `project_id`-mask. **Подтвердить «labels-only» для β.** |
| **Q-β3** | **mirror-row: immutable vs. upsert-mutable?** (D-β7) | **Upsert-mutable** (зеркало отражает изменяемое состояние владельца; immutability ломала бы dev→prod β-04). Конкурентность — DB-уровень (UPSERT-on-PK). **Подтвердить mutable-семантику.** |
| **Q-β4** | **Валидировать ли labels-payload на IAM-стороне** (дублируя compute pattern) или довериться upstream? (β-15) | Минимальная sanity-валидация на IAM (defense-in-depth: не UPSERT-ить произвольный/oversized JSONB), не полный re-парс pattern. **Подтвердить уровень валидации.** |
| **Q-β5** | **Scope β: compute-first + vpc-β2 ИЛИ compute+vpc сразу?** (D-β8) | **compute-first, vpc-follow (β2).** Обоснование: ребро `compute→iam` status **done** (caller живёт), `vpc→iam` status **planned** (vpc ещё не вызывает FGA-proxy); proto-поля и mirror-таблица — **generic by-design** (`object_type` любой), так что β2 = только caller-сторона vpc + newman, без proto/iam-изменений → минимальный blast-radius на deliverable, γ раньше получает compute-mirror (α таргетинг демонстрировался на `compute.instance`). **Подтвердить compute-first.** |
| **Q-β6** | **`Unregister` payload: нужны ли поля 5/6/7?** (D-β1) | Добавить **для симметрии формы** (одинаковый message-shape), но семантически Unregister использует только `object` (удаление по PK). Альтернатива — отдельный slim Unregister без новых полей. **Подтвердить «симметрия» vs. «slim».** |

---

## 5. Definition of Done (на каждую стадию)

Кросс-репо порядок (`polyrepo.md`): **proto → compute → iam → deploy → workspace(docs)**. vpc — отдельная волна **β2** (Subtask эпика). Стадии — самостоятельные deliverable'ы; CI нижестоящего пиннит sibling к feature-ветке до merge вышестоящего.

**S1 — proto (`kacho-proto`):**
- [ ] `RegisterResourceRequest` / `UnregisterResourceRequest` += `labels=5`, `parent_project_id=6`, `parent_account_id=7` (аддитивно, optional; D-β1, форма §2.1).
- [ ] `ResourceSelector.match_tags` → `match_labels` (access_binding.proto:167) — переименование (γ-движок, но proto-правка в β-PR; β-10).
- [ ] `buf lint` / `buf breaking` зелёные (additive поля — не breaking; rename field-имени при сохранении номера — отметить для ревью); `gen/go/...` регенерирован и закоммичен. Ревью — `proto-api-reviewer` (особ. подтвердить, что `RegisterResource` остаётся Internal-only, без `google.api.http`).

**S2 — compute (`kacho-compute`):**
- [ ] RED integration-тесты (testcontainers) по β-01/β-02/β-04/β-04b первыми (compute caller-сторона: payload-формирование + Update-триггер) → подтверждён красный → GREEN.
- [ ] `emitFGARegisterIntent` расширяется: payload += `labels` (из ресурса), `parent_project_id` (= `project_id`), `parent_account_id` (резолв `project→account`, как для hierarchy-tuple) — в writer-tx ресурса (`compute_fga_register_outbox`).
- [ ] **Новый Update-триггер**: эмиссия register-intent на `Instance.Update` **iff `labels` ∈ `update_mask`** (D-β6, β-04/β-04b). Прочие mask-поля не триггерят.
- [ ] register-drainer / `iam_register_applier.go` шлёт расширенный payload по mTLS (тот же drainer; идемпотентность сохранена — D-β5). Error-маппинг без изменений (`InvalidArgument`→poison).
- [ ] Newman happy (β-01 через стенд: Create instance → mirror eventually) + Update (β-04). _(mirror-верификация на стенде — через γ-read либо deploy-test hook; в β2/γ.)_
- [ ] by-design D-β6/D-β8 — запись в `docs/architecture/` kacho-compute (Update-on-labels register-trigger; compute-first scope).
- [ ] Ревью — `go-style-reviewer`, `system-design-reviewer` (idempotent at-least-once payload; **подтвердить, что β НЕ вводит ребра iam→compute** — данные текут compute→iam push-ем, ацикличность сохранена).

**S3 — iam (`kacho-iam`):**
- [ ] RED integration-тесты (testcontainers) по β-01/β-02/β-03/β-05/β-06/β-07/β-08/β-09/β-12/β-14/β-15/β-16 первыми, **включая β-05 (concurrent UPSERT) и β-03 (co-commit atomicity)** → подтверждён красный → GREEN.
- [ ] Миграция: `kacho_iam.resource_mirror` (PK `(object_type,object_id)`, JSONB `labels` NOT NULL DEFAULT `'{}'`, GIN на `labels`, без FK — D-β4). Ревью — `db-architect-reviewer`. **Не редактировать применённые** (новая миграция, ban #5).
- [ ] `RegisterResource` handler: парсит `object`→`(object_type,object_id)` (существующая грамматика) → **UPSERT `resource_mirror` (labels, parent_*) + emit owner-tuple-intent в `fga_outbox` в ОДНОЙ writer-tx** (co-commit, ban #10 — D-β3). `labels`-sanity-валидация (Q-β4).
- [ ] `UnregisterResource` handler: **DELETE `resource_mirror`-строки + tuple-revoke-intent в одной writer-tx** (симметрия — β-07); absent→OK (idempotent — D-β5).
- [ ] **Concurrent-non-regression тест (testcontainers, ≥2 goroutine, β-05):** конкурентные UPSERT одного объекта → одна строка, last-write детерминирован, без дублей/полу-записи (`data-integrity.md` §within-service п.5 — обязателен, RED-first).
- [ ] Back-compat: payload без новых полей → mirror с пустыми labels/parent (β-09); proto аддитивен (β-10).
- [ ] AuthZ: расширенный payload не меняет `FGAProxyGate` (β-11/β-12); метод остаётся Internal-only :9091 (β-13). Error-mapping (`INVALID_ARGUMENT` malformed object/labels; `PERMISSION_DENIED` no-relation), без leak pgx.
- [ ] by-design D-β1/D-β2/D-β3/D-β4/D-β9 — запись в `docs/architecture/` kacho-iam (resource_mirror = output-only зеркало; co-commit mirror⊕owner-tuple; mirror НЕ читается для authz в β — наполнение only; источник истины = compute).
- [ ] Ревью — `db-architect-reviewer` (`resource_mirror` PK/GIN/UPSERT-on-PK idempotency, co-commit atomicity), `go-style-reviewer`, `system-design-reviewer` (mirror⊕tuple одна tx; output-only зеркало; **ацикличность графа — β НЕ вводит iam→compute/vpc**).

**S4 — deploy (`kacho-deploy`):** helm/compose без структурных изменений (то же :9091-ребро, мигрция iam применяется существующим `cmd/migrator`); e2e-build-матрицы newman зелёные; mTLS FGA-proxy enable как сейчас.

**S5 — workspace (docs/vault):** обновить vault `rpc/iam-internal-iam-service.md` (RegisterResource/Unregister += labels/parent + mirror co-commit), `edges/compute-to-iam-fgaproxy.md` (расширенный payload + Update-триггер в History), новый `resources/iam-resource-mirror.md` (output-only зеркало: колонки, source=compute, GIN, наполняется-β/читается-γ, dangling), KAC-trail; этот acceptance-док → статус APPROVED. **НЕ заводить `edges/iam-to-compute`/`iam-to-vpc`** — β НЕ вводит cross-domain ребро (data push consumer→iam, не pull — D-β2/D-β9).

**β2 (отдельная волна — vpc, Subtask эпика):** caller-сторона kacho-vpc (`vpc→iam` FGA-proxy, status planned→done) шлёт расширенный payload для vpc-ресурсов; mirror-таблица и proto-поля уже generic (D-β8) → только vpc-caller + newman + vault `edges/vpc-to-iam-fgaproxy`. Идентичный β-контракт на `vpc.subnet`/`vpc.network`/… Без proto/iam-изменений.

**Финальная верификация (перед merge каждой Go-стадии):** `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` + newman зелёные.

---

## 6. Выход / запреты

- Единственный артефакт этого шага — настоящий markdown. **Никакого кода** (ни `.go`, ни `.sql`, ни `.proto`).
- Описано только наблюдаемое поведение Internal-API + состояние зеркала (через integration-верификацию); DB-форма (`resource_mirror`, PK/GIN, UPSERT-on-PK, co-commit) — забота `db-architect-reviewer`/`migration-writer`/`rpc-implementer`.
- **β только НАПОЛНЯЕТ mirror.** Selector-матчинг и containment-гейт (чтение mirror для authz) — **под-фаза γ**, вне scope β. β не реализует selector-движок и не снимает `UNIMPLEMENTED`.
- **β НЕ вводит cross-domain ребро `iam→compute/vpc`** — данные текут по существующему `compute→iam` (consumer push-ит свои labels+parent, IAM не запрашивает) → ацикличность графа сохранена (`polyrepo.md` non-negotiable). Это закрывает α D-14 (containment) **данными**, без цикла.
- **vpc — отдельная волна β2** (compute-first, D-β8/Q-β5).
- `RegisterResource`/`UnregisterResource` остаются **Internal-only :9091** (ban #6); расширение payload не добавляет публичной поверхности (D-β9).
- Без сравнений с чужими облаками — конвенции Kachō нормативны (`api-conventions.md`).
- Координация после APPROVED: тикет/эпик KAC + `superpowers:writing-plans` → `integration-tester` (RED по β-NN) → `rpc-implementer` → `proto-api-reviewer` (proto-поля + rename) / `db-architect-reviewer` (`resource_mirror` + co-commit) / `system-design-reviewer` (mirror⊕tuple одна tx; подтвердить отсутствие ребра iam→compute/vpc — ацикличность) → заказчик: финальный smoke (Create/Update instance → mirror eventually).
