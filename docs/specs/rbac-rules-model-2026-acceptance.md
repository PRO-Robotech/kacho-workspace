# RBAC rules-model 2026 — Acceptance (Given-When-Then)

> **Статус:** ✅ APPROVED (`acceptance-reviewer`, раунд 2, 2026-06-20) — можно начинать `superpowers:writing-plans` + implementation (ban #1 снят)
> **post-APPROVE consistency-правка (2026-06-20):** убраны `permissions[]`/`ruleDiagnostics` из API-поверхности Role (решение заказчика — публичный ответ Role несёт только `rules[]`; `permissions[]` — internal compiled, не заполняется; `RuleDiagnostics`/`GetRoleResponse` удалены, `Role.Get` возвращает `Role` напрямую). Требуется быстрый re-confirm `acceptance-reviewer`.
> **Дата:** 2026-06-20
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — **✅ APPROVED (раунд 2)**: round-1 CHANGES REQUESTED полностью отработаны — O-1..O-8 абсорбированы в нормативные секции (§2.2/§2.4/§2.5/§5), A-16 (O-7 Role.Delete in-use) и E-34 (O-6 dual read-projection) добавлены как полные GWT с DoD+трассировкой, fan-out limit=10000 зафиксирован консистентно (§2.5/C-21/DoD C/§0.5/§5), §5 закрыт без открытых блокеров; одобренное ядро (GWT-1..15, LST-1..6, под-фазы A–F, §11 per-object List, reuse-карта) не сломано, внутренних противоречий нет; покрытие 100% (подтверждено в раунде 1).
> **Эпик/тикет:** KAC-`<N>` `[EPIC]` «RBAC rules-model 2026» (номер проставляется до старта `superpowers:writing-plans`; фича 6 репо → эпик + Subtask per репо, `git-youtrack.md`). Затронутые репо: `kacho-proto` / `kacho-corelib`(если общее) / `kacho-iam` / `kacho-api-gateway` / `kacho-ui` / `kacho-deploy` / `kacho-workspace`(docs).
> **Источник истины (читан целиком):** `docs/specs/rbac-rules-model-2026-design.md` — финальный design (proto §2, REST §3, семантика §4, FGA-компиляция §5, инварианты §6, миграция §7, решения §8, открытые вопросы §9, GWT-1..15 §10, §11 per-object List LST-1..6). Этот acceptance покрывает дизайн полностью; **все §8-решения и §10/§11-сценарии перенесены и трассируются**.
> **Образцы формата:** `sub-phase-1.5-assignable-roles-acceptance.md`, `sub-phase-1.3-iam-subject-privileges-acceptance.md`, `epic-resource-scoped-access-binding-{alpha,gamma}-acceptance.md`, `sub-phase-vpc-redesign-kac239-acceptance.md`.

---

## Обзор

Редизайн модели авторизации Kachō в **K8s-style rules-in-role** с двумя расширениями над K8s: (1) `matchLabels{}` per-rule селекция инстансов и (2) **per-object filtered `List`** (выдача только доступных объектов, не all-or-nothing). **Role** становится переиспользуемой allow-only политикой с `rules[]` (каждое правило — `{modules[], resources[], verbs[]}` над декартовым `modules×resources`, опц. суженное `resourceNames[]` XOR `matchLabels{}`); **AccessBinding** становится тонким (`{subjects[], roleId, scopeRef{tier,id}, condition}` — без `target`/`selector`). Селекция целиком уезжает в `role.rules` (epic-100 α/γ `target`/`selector`-аппарат деприкейтится). Tier материализуется **потипно** (`scope_grant`-примитив, fix F1 — закрытие escalation #177), per-verb enforcement (delete ≠ create), `permissions[]` остаётся **INTERNAL** compiled-формой для FGA-эмиссии (anchor/names-армы; matchLabels в неё НЕ компилируется) — это **не** часть публичного API-ответа Role: `Role.Get` возвращает `Role` напрямую с `rules[]` как публичной поверхностью, `permissions[]` в ответе для rules-ролей не заполняется. Документ описывает **только наблюдаемое внешнее поведение API/FGA/UI** (gRPC-коды, REST-формы, FGA Check/ListObjects-результаты, экраны), не реализацию. Сценарии трассируются в имена integration/newman/UI-тестов через ID `<под-фаза>-<NN>`.

> **Декомпозиция (по запросу заказчика — инкрементальная реализация).** Эпик разбит на **6 под-фаз A–F**, каждая — самостоятельный end-to-end deliverable со своим DoD, в кросс-репо порядке `proto → corelib → iam → gateway → ui → deploy → docs` (`polyrepo.md`). Под-фаза «зелёная» только при RED→GREEN integration + newman в том же PR (ban #12). Маппинг §10-GWT / §11-LST дизайна на под-фазы — в §0.4.

---

## 0. Фиксированные дизайн-решения (из §8 дизайна — НЕ переоткрывать; ревьюер подтверждает scope)

> Решения **уже приняты заказчиком и зафиксированы в дизайне §8** — здесь они сведены как контрактные предпосылки сценариев. Ревьюер проверяет покрытие, не переоткрывает выбор.

### 0.1. Решения семантики/безопасности

| ID | Решение (дизайн §8) | Сценарии |
|---|---|---|
| **R-1** | **all_in_scope → type-scoped `scope_grant`-примитив** (НЕ whole-role collapse на голый anchor). all_in_scope-правило эмитит per-`(module,resource)` `scope_grant`-tuple; tier каскадит на FGA **только на свой тип**. Закрывает escalation-engine #177. **Требует изменения FGA-модели** (новый тип `scope_grant`). | A-* (compile), B-* (emit), GWT-1, GWT-2 |
| **R-2** | **per-verb enforcement** (НЕ 3-tier collapse): `delete` энфорсится **отдельно** от `create`/`update`/`get`/`list`. FGA-модель получает **per-verb relations**. (Это сознательное усиление относительно §8-строки «verb-granularity advisory» — заказчик подтвердил best-2026 per-verb, no-MVP.) | B-* (per-verb relations), GWT-2b, LST-* |
| **R-3** | **verb-`*` в custom-роли — ДОПУСТИМ** (бан снят): при per-verb модели (R-2) verb-`*` = «все verbs данного типа», bounded. **module-`*` и resource-`*` остаются system-only.** | A-04, A-05, GWT-3 |
| **R-4** | **allow-only** (нет deny, нет порядка, нет override). Эффективное множество = `∪` правил. | A-* |
| **R-5** | **`subjects[]` 1..32** — каждый субъект → независимый tuple-set / независимый revoke / независимый lineage. | E-* (subjects), GWT-15 |
| **R-6** | **`ExpandAccess` RPC** — да (audit «кто реально может X»: userset→concrete principals через FGA Expand). | E-* (ExpandAccess), GWT-15 |
| **R-7** | **`permissions[]` — INTERNAL compiled** (anchor+names армы; **matchLabels НЕ компилируется**). Live deprecated-поле (нельзя удалить, buf-breaking); используется для FGA-эмиссии/Check-reuse. **НЕ заполняется** в публичном `Get`/`List`-ответе для rules-ролей (пустое); игнорируется на входе Create/Update. Публичный API роли = `rules[]`; UI рендерит роль из `rules[]`. **`Role.Get` возвращает `Role` напрямую** (не `GetRoleResponse`-обёртку); диагностического поля (`RuleDiagnostics`) нет — `arm` выводится клиентом из формы правила, feed-проблемы — ошибка Create. | A-* (compile), GWT-6 |
| **R-8** | **condition → FGA conditional-tuple** (Condition-ref + CEL для time/IP/MFA); FGA энфорсит сам, fail-closed. matchLabels (object-state) — materialization, НЕ conditional-tuple. | C-* (condition), GWT-9 |
| **R-9** | **revoke по СОХРАНЁННОМУ tuple-set** (`access_binding_emitted_tuples`, ledger из fix #178 переиспользуется), НЕ re-derive из текущей роли. `Role.Update(rules)` → bounded фан-аут reconcile всех ACTIVE-биндингов; membership ключуется `rule_fp` (content-hash), не `rule_index`. | B-* / C-* (revoke), GWT-4, GWT-5 |
| **R-10** | **per-object filtered List (§11, КРИТИЧНО)** — `List<Resource>` отдаёт ТОЛЬКО доступные объекты (union армов), через FGA `ListObjects` поверх materialized per-object tuples + `scope_grant`. read==enforce паритет. `make audit-list-filter` расширяется до per-object. Pagination ПОСЛЕ фильтра. Применяется во **всех** доменах (iam/vpc/compute/nlb). | D-* (List-filter), LST-1..6 |

### 0.2. Решения формы / proto / миграции

| ID | Решение (дизайн §2/§6/§7/§8) | Сценарии |
|---|---|---|
| **R-11** | **proto append-only**: live-tag'и НЕ двигаются; `Role.rules=11`, `Role.resource_version=12`, `Role.created_by_user_id=13`, `Role.updated_at=14`; `AccessBinding.subjects=19`; новый `Rule`. **`RoleService.Get` остаётся `returns (Role)`** (НЕ вводим `GetRoleResponse`-обёртку); **`RuleDiagnostics` НЕ создаётся** (диагностического поля нет). `organization_id=9` — **reserved tombstone**; `Role.permissions=5` — deprecated (internal compiled). **`aggregationRule` (O-1 ПРИНЯТО): НЕ в этой фазе — упомянуть только proto-комментарием, БЕЗ резерва tag (append-only позже).** `buf breaking` зелёный. | A-01, F-09 |
| **R-12** | **cardinality**: `rules[]` 1..64; `modules`/`resources`/`verbs` 1..16 каждый; `resourceNames` ≤256/правило; `matchLabels` ≤16 ключей; **compiled `permissions[]` ≤1024** (cap-raise с live-256 lockstep-миграцией: DB CHECK + domain + proto `(size)` в одной tx); `subjects[]` 1..32. Превышение compiled-cap → `INVALID_ARGUMENT` (НЕ silent truncation, НЕ INTERNAL). | A-12, A-13, GWT-12 |
| **R-13** | **миграция live-данных**: backfill `rules` из `permissions` детерминирован **только** для anchor/names-армов (`m.r.*.v`→ARM_ANCHOR, `m.r.<id>.v`→ARM_NAMES); matchLabels из permissions НЕ recoverable. **legacy γ-биндинги (`by_name`/`by_selector` `binding.target`/`selector`) — INERT** до явного re-author (нет migration-revoke, нет double-emit, нет lazy-«когда-нибудь»). bit-identical-инвариант сужен до all_in_scope-биндингов. | F-* (migration), GWT-8 |
| **R-14** | **org-drop и grammar-flip НЕ повторяются** (сделаны `0008`/`0005`, phantom-шаги вычеркнуты). Live grammar уже 4-сегментная. `scope_ref=17`/`target_ref=18`/`match_labels` уже в live proto (epic-100) — НЕ пере-добавлять. `scope_tier/scope_id` колонки НЕ добавляются (anchor = `scope_ref`-проекция). | F-* |
| **R-15** | **breaking-cleanup только Phase 6 (F-cleanup)**: DROP legacy `access_binding_targets`/`access_binding_selector`/legacy-колонок, retire target-мутаторов (`AddTargetResources`/`RemoveTargetResources`/`ReplaceTargetSelector`/`ListGrantableResources`), rename `ListByResource→ListByScope`. До Phase 6 wire-name `ListByResource` СОХРАНЁН; target-мутаторы зарегистрированы но на write → `FAILED_PRECONDITION`. | F-cleanup-* |

### 0.3. Открытые вопросы дизайна §9 — статус для acceptance

| §9 Q | Статус в этом acceptance | Где |
|---|---|---|
| Q#1 aggregationRule | **РЕШЕНО (O-1 ПРИНЯТО):** НЕ в этой фазе; зарезервировать только **proto-комментарием** (БЕЗ резерва tag — append-only позже). Не порождает сценариев кроме «поле отсутствует/не принимается». | §0.3/R; §5 closed |
| Q#2 strict-mode double-coverage | **WARNING (не reject)** при одном tier; при разных tier'ах (anchor viewer + label admin) — оба арма, БЕЗ warning. | A-11 |
| Q#3 matchExpressions | **только AND-equality v1** (зарезервировать). matchExpressions на входе → `INVALID_ARGUMENT`. | A-09 |
| Q#4 group-amplification + ExpandAccess | admin/editor + GROUP → `requireGrantAuthority`; `ExpandAccess` реализуется (R-6). | E-*, GWT-11, GWT-15 |
| Q#5 deprecation-окно legacy target | ≥1 минорный релиз accepted-as-`FAILED_PRECONDITION`, затем Phase 6 DROP. | F-cleanup-* |
| Q#6 verb-granularity | **РЕШЕНО (O-2 ПРИНЯТО):** переопределён заказчиком на per-verb (R-2) — НЕ advisory; verb-`*` allowed (R-3). Дизайн §8 обновлён, конфликта нет. true per-verb FGA-relations входят в B. | B-*; §5 closed |

### 0.4. Маппинг §10-GWT / §11-LST дизайна → под-фазы acceptance

| Дизайн | Под-фаза | Acceptance-сценарий |
|---|---|---|
| GWT-1 (escalation type-scoped) | B | **B-10** |
| GWT-2 (mixed-tier no collapse) | B | **B-11** |
| GWT-2b (per-verb delete≠create) — *новое из R-2* | B | **B-12** |
| GWT-3 (verb-`*` ban→allow per R-3) | A | **A-04 / A-05** |
| GWT-4 (revoke after rules-edit) | C | **C-20** |
| GWT-5 (Role.Update fan-out) | C | **C-21** |
| GWT-6 (matchLabels no over-grant) | C | **C-22** |
| GWT-7 (feed-gate) | A | **A-10** |
| GWT-8 (dual-authority inert) | F | **F-20** |
| GWT-9 (condition no bypass) | C | **C-23** |
| GWT-10 (resourceNames PENDING bounded) | C | **C-24** |
| GWT-11 (label-tampering) | C | **C-25** |
| GWT-12 (cap & grammar) | A | **A-12 / A-13** |
| GWT-13 (OCC + reconcile race) | C | **C-26** |
| GWT-14 (scope/role ancestry) | A | **A-14 / A-15** |
| GWT-15 (subjects[] independence + ExpandAccess) | E | **E-30 / E-31 / E-32** |
| LST-1..6 (per-object List) §11 | D | **D-40..D-46** |
| O-7 (Role.Delete пока несёт binding-строку, FK 23503) — *резолюция заказчика* | A | **A-16** |
| O-6 (read-projection new↔legacy представления) — *резолюция заказчика* | E | **E-34** |

### 0.5. РЕЗОЛЮЦИИ ПРИНЯТЫ (заказчик) — O-1..O-8 абсорбированы в контракт

Вопросы, найденные автором acceptance (дыры/неоднозначности дизайна вне §9), **закрыты заказчиком** и перенесены в нормативные секции контракта. Это **не** открытые блокеры APPROVE — здесь только указатель «куда абсорбировано». Полные формулировки решений — §5 «Зафиксированные решения (closed)».

| O | Резолюция (ПРИНЯТО заказчиком) | Абсорбировано в |
|---|---|---|
| **O-1** aggregationRule | НЕ в фазе; только proto-комментарий, БЕЗ резерва tag | §0.3 (Q#1), R-11-комментарий |
| **O-2** per-verb vs §8 | per-verb финал (R-2) + verb-`*` allowed (R-3); дизайн §8 обновлён, конфликта нет | §0.3 (Q#6), §2.2, B-12 |
| **O-3** verb-`*` FGA-разворот | `verbs:["*"]` → полный закрытый per-verb набор типа (наследует все per-verb relations), bounded; permissions-проекция `m.r.*.*` (A-04) ок | §2.2, B-12, DoD B `fga_model.fga` |
| **O-4** iam-direct fed-типы | selectable = `iam.project`, `iam.account`; `iam.role`/`iam.serviceAccount`/`iam.group` НЕ selectable (feed-gate reject) | §2.4, A-10 |
| **O-5** ListObjects performance | load-gate (`load-testing-coach` FGA ListObjects) **обязателен** перед prod-flip под-фазы D | §0.3 (Q#5-смежн.), DoD D |
| **O-6** read-projection new↔legacy | Get/List/ListByRole заполняют ОБА представления до Phase 6; legacy-single↔subjects[] паритет | E-34, DoD E |
| **O-7** Role.Delete in-use bindings | FK 23503→FailedPrecondition `"role is in use by access bindings"` (текст без «active» — FK блокирует на любой binding-строке), без leak pgx; после **hard-purge** биндингов (`AccessBindingService.Delete` = hard delete) — Delete проходит | §2.5, A-16, DoD A |
| **O-8** fan-out limit | **limit=10000** active bindings/role; превышение → `FAILED_PRECONDITION` | §2.5, C-21, DoD C |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — read **sync** (`Get`/`List`/`ListByRole`/`ExpandAccess`/`ListObjects`-фильтр), мутации async `Operation` (`Role.Create/Update/Delete`, `AccessBinding.Create/Delete`); Watch не существует (polling) | A/D/E (sync reads), B/C/F (Operation-мутации) |
| `api-conventions.md` — `Operation`: клиент поллит `OperationService.Get(id)` до `done=true`; mis-state на async-мутации → `Operation.error.code`, НЕ второй sync-класс | B/C (Role.Update fan-out, AccessBinding.Create), C-23/C-24/C-25 (`Operation.error`) |
| `api-conventions.md` — malformed id → sync `INVALID_ARGUMENT` первым стейтментом; well-formed-но-нет → `NOT_FOUND`; mis-state → `FAILED_PRECONDITION` | A-06/A-07, B-13, E-* |
| `api-conventions.md` — cursor pagination `(created_at,id)` ASC, opaque base64 `page_token`, `page_size` 0→50/max 1000; **pagination ПОСЛЕ per-object фильтра** (§11) | D-46 (LST-6) |
| `api-conventions.md` — REST `/<service>/v1/<resource>`, suffix-action `:verb`; JSON camelCase (`rules`, `matchLabels`, `resourceNames`, `scopeRef`, `resourceVersion`, `createdByUserId`, `nextPageToken`) | A/E REST-формы, §smoke |
| `api-conventions.md` — update_mask discipline: unknown → InvalidArgument; immutable в mask → InvalidArgument; пустой → full-PATCH | A-08, C-21 |
| `data-integrity.md` §within-service — FK RESTRICT (binding→role, role→account/project), partial UNIQUE (role name per scope, strict-create binding), CAS (xmin OCC на `Role.Update`), CASCADE same-DB (`access_binding_*` child-таблицы) | A-01, C-26, R-9, R-12 |
| `data-integrity.md` §within-service п.5 — конкурентный спорный путь → integration-тест (testcontainers, ≥2 goroutine) | C-21, C-26, F-20 |
| `data-integrity.md` §cross-domain — НЕ вводит нового iam→consumer ребра (цикл): selection-id'ы — opaque soft-ref; per-object List у consumer'ов фильтруется через `InternalIAMService` (vpc/compute/nlb→iam, ребро существует), fail-closed | D-40..D-46, §6 |
| `security.md` §AuthN+AuthZ ВЕЗДЕ — каждый RPC per-RPC Check; read-RPC viewer-floor, мутации admin-tier; анонимный fail-closed; **обе проекции (public/internal)** | A-03/B/C/E (authz), D (List-filter fail-closed) |
| `security.md` §Internal-vs-external (ban #6) — Role/AccessBinding-RPC публичны (tenant-UI); `ExpandAccess`/`ListByRole` — **public** (audit для grant-authority holder, не инфра-данные). `scope_grant`-FGA-tuple — внутренняя машинерия, не на публичной поверхности | A/E (public), B (FGA internal) |
| `security.md` §Инфра-чувствительные данные — `Role`/`AccessBinding`/`AssignableRole` не светят инфра-полей; публичный ответ Role несёт только `rules[]` (`permissions[]` — internal compiled, не в API-ответе) | A-02, E-* |
| `security.md` §публичный List обязан фильтровать (listauthz CI-гейт) — **расширяется до per-object** `make audit-list-filter` | D-40..D-46 (R-10) |
| `00-kacho-core.md` ban #1 (APPROVED перед кодом), #5 (не редактировать применённую миграцию — новые forward-файлы ≥0024), #9 (мутации→Operation), #10 (within-DB инвариант — DB CHECK/FK/CAS, не TOCTOU), #12 (TDD RED→GREEN integration+newman в том же PR), #2 (без упоминания чужих облаков) | весь документ; DoD каждой под-фазы |
| `polyrepo.md` §порядок merge | DoD §A..§F: proto → corelib → iam → api-gateway → ui → deploy → workspace(docs) |
| `architecture.md` — чистый Go-компайлер `rules→permissions` в `domain/` (не PL/pgSQL, не handler); FGA-emit в service-слое | A-* (compile в domain), B-* (emit) |

---

## 2. Нормативные определения (источник истины для сценариев — из дизайна §4/§5)

> Это **нормативные** определения; сценарии ниже на них ссылаются. Изменение — только через правку дизайна, не реализации.

### 2.1. Три арма правила (дизайн §5)

| Арм | Условие | Что эмитится в FGA | type-correct |
|---|---|---|---|
| **ARM_ANCHOR** | ни `resourceNames`, ни `matchLabels` (= «все инстансы `modules×resources` под scopeRef») | per-`(module,resource)` **`scope_grant:<anchor>/<objectType>#<verb-relation>@subject`** (НЕ raw-anchor whole-role tuple) | да (per-type) |
| **ARM_NAMES** | `resourceNames` задан | per-id `fga(m,r):<id>#<verb-relation>@subject` (1 tuple/объект) | да (per-object) |
| **ARM_LABELS** | `matchLabels` задан | reconciler → per-matched-and-contained-object `fga(m,r):<obj>#<verb-relation>@subject` | да (per-object) |

`permissions[]` (**internal** compiled) содержит **только** ARM_ANCHOR (`m.r.*.v`) + ARM_NAMES (`m.r.<id>.v`). **ARM_LABELS в `permissions[]` отсутствует** (R-7/fix #8). `permissions[]` — НЕ часть API-ответа Role (не заполняется в Get/List для rules-ролей); публичная поверхность роли = `rules[]`.

### 2.2. Wildcard-политика (дизайн §4, **переопределена R-3**)

- `modules:["*"]` / `resources:["*"]` — **только system-роли** (seed); в custom → `INVALID_ARGUMENT`.
- `verbs:["*"]` — **ДОПУСТИМ в custom-роли** (R-3): при per-verb модели = «все verbs данного типа», bounded. (Это отличие от §8-строки «verb-`*` запрещён» — заказчик снял бан под per-verb R-2.)
  - **FGA-разворот (O-3 ПРИНЯТО, контрактно):** `verbs:["*"]` при эмиссии разворачивается в **полный закрытый per-verb набор данного типа** — арм наследует **все конкретные per-verb relations** этого типа из `fga_model.fga` (закрытый список verbs типа), bounded (не открытый «звёздочный» relation, не unbounded). FGA Check `S can <любой_конкретный_verb> <type>:<obj>` → allow для всех verbs типа. Это вход в `fga_model.fga` DoD под-фазы B (см. B-12-окрестность).
  - **Permissions-проекция** (compiled, output-only) `verbs:["*"]` → `m.r.*.*` (A-04) остаётся ок — projection не разворачивает per-verb набор, держит `*`-сегмент verb (R-7).
- `*` — **только как единственный элемент** своего списка (`["*"]`, не `["*","subnet"]` → `INVALID_ARGUMENT`).
- любой `*` (любая позиция) **+ matchLabels или + resourceNames** → `INVALID_ARGUMENT`.

### 2.3. Селекция / containment (дизайн §4)

- `resourceNames[]` XOR `matchLabels{}` на правило (оба → `INVALID_ARGUMENT`). Отсутствие обоих = ARM_ANCHOR.
- `matchLabels{}` непуст если задан (`{}` при наличии ключа → `INVALID_ARGUMENT`); AND-equality; **никогда не PENDING**.
- `resourceNames[]`: opaque-id 1..64, literal `*` запрещён как элемент, UNIQUE на правило.
- каждый материализованный объект обязан `IsContainedIn(scopeRef)` иначе **REJECTED** (без tuple) + audit. Лейбл **никогда** не повышает tier и **никогда** не выходит за `scopeRef`.
- `scopeRef{tier,id}`: CLUSTER⇒`cluster_kacho_root`; ACCOUNT⇒`acc…`; PROJECT⇒`prj…`. `scopeRef` обязан быть в ancestry владельца роли (`role.account_id`/`role.project_id`) иначе `FAILED_PRECONDITION`.

### 2.4. feed-availability registry (дизайн §6 fix #9)

ARM_LABELS-правило допустимо **только** на `(module,resource)` из **закрытого code-registry CONFIRMED-fed типов** = union того, что vpc/compute/nlb реально эмитят в `resource_mirror`, **плюс явный закрытый список iam-direct fed-типов** (O-4 ПРИНЯТО, epic-107 Q4):

- **iam-direct ARM_LABELS-selectable типы = ровно `iam.project`, `iam.account`** (и только они из домена iam).
- **`iam.role` / `iam.serviceAccount` / `iam.group` — НЕ selectable через `matchLabels`** (не в feed-registry) → feed-gate **reject** с `INVALID_ARGUMENT "type <m>.<r> is not selectable (no resource feed)"`.

Тип не в registry → sync `INVALID_ARGUMENT "type <m>.<r> is not selectable (no resource feed)"`. ARM_NAMES gate'у НЕ подлежит (любой тип допустим через `resourceNames`).

### 2.5. Стабильные тексты ошибок (часть контракта — `api-conventions.md`)

| Ситуация | Код | Текст |
|---|---|---|
| malformed role id | `INVALID_ARGUMENT` | `invalid role id '<X>'` |
| role well-formed, нет | `NOT_FOUND` | `Role <id> not found` |
| пустой `rules[]` | `INVALID_ARGUMENT` | `Illegal argument rules (must be non-empty)` |
| пустой `modules`/`resources`/`verbs` | `INVALID_ARGUMENT` | `Illegal argument <field> (must be non-empty)` |
| module/resource-`*` в custom | `INVALID_ARGUMENT` | `Illegal argument <field> (wildcard '*' is system-only)` |
| `*` не единственный элемент | `INVALID_ARGUMENT` | `Illegal argument <field> (wildcard '*' must be sole element)` |
| `*` + selector | `INVALID_ARGUMENT` | `Illegal argument: wildcard cannot combine with resourceNames or matchLabels` |
| resourceNames И matchLabels одновременно | `INVALID_ARGUMENT` | `Illegal argument: resourceNames and matchLabels are mutually exclusive` |
| matchLabels пуст при наличии | `INVALID_ARGUMENT` | `Illegal argument matchLabels (must be non-empty when set)` |
| matchExpressions задан (v1) | `INVALID_ARGUMENT` | `Illegal argument matchExpressions (not supported)` |
| тип не selectable (feed-gate) | `INVALID_ARGUMENT` | `type <m>.<r> is not selectable (no resource feed)` |
| compiled-cap >1024 | `INVALID_ARGUMENT` | `Illegal argument rules (compiled permissions exceed 1024)` |
| client прислал `permissions` на вход | `INVALID_ARGUMENT` | `Illegal argument permissions (compiled/output-only)` |
| immutable в update_mask | `INVALID_ARGUMENT` | `<field> is immutable after Role.Create` |
| unknown в update_mask | `INVALID_ARGUMENT` | `Illegal argument update_mask: unknown field '<f>'` |
| OCC stale на Role.Update | `FAILED_PRECONDITION` | `Role was modified concurrently, retry` |
| custom-role bind @ CLUSTER | `FAILED_PRECONDITION` | `custom role cannot be bound at CLUSTER scope` |
| scopeRef вне ancestry роли | `FAILED_PRECONDITION` | `scope <tier>:<id> is not within role ownership` |
| Role.Update fan-out > лимита (**limit=10000** active bindings/role, O-8) | `FAILED_PRECONDITION` | `role carried by too many bindings to update atomically; split role` |
| system-role Update/Delete | `FAILED_PRECONDITION` | `system role is immutable` |
| Role.Delete пока роль несёт ≥1 binding-строку | `FAILED_PRECONDITION` (через FK 23503) | `role is in use by access bindings` |
| resourceNames id out-of-scope (на материализации) | (REJECTED+audit, без tuple; сам Create — ACTIVE с partial) | n/a (материализация → REJECTED + audit-запись, без диагностического поля в API) |
| subjects[] > 32 / < 1 | `INVALID_ARGUMENT` | `Illegal argument subjects (must be 1..32)` |
| object вне всех грантов (LST-5) | `NOT_FOUND` на Get; **отсутствует** в List | `<Resource> <id> not found` |

---

## 3. Глоссарий: ground-truth (vault/код) и дельта

| Сущность | id-prefix | Ground-truth | Дельта редизайна |
|---|---|---|---|
| `Role` | `rol` | flat: id/account_id/name/description/permissions/is_system/created_at/cluster_id/(org tombstone)/project_id; scope 4-way XOR `roles_scope_xor`; `permissions` JSONB strict 4-сегмент `M.R.rn.V` cardinality 1-256; system-роли immutable seed | **+`rules[]`=11** (authority + публичный API), `resource_version`=12, `created_by_user_id`=13, `updated_at`=14; `permissions[]`→**internal compiled** (anchor/names; deprecated; **НЕ в API-ответе** для rules-ролей); cap 256→**1024**; `Role.Get` → `returns (Role)` (НЕ обёртка) |
| `Rule` | — | **НЕ существует** | **НОВЫЙ** message `{modules[], resources[], verbs[], resourceNames[] XOR matchLabels{}}` |
| `AccessBinding` | `acb` | flat: subject_type/subject_id/role_id/resource_type/resource_id/status/condition_id/scope/scope_ref(17,live)/target(16,deprec)/target_ref(18,deprec)/…; FK role RESTRICT; epic-100 α `target` + γ `selector` | **+`subjects[]`=19** (1..32); `target`/`target_ref`/`selector`-аппарат **деприкейтится** (write→FAILED_PRECONDITION в окне, DROP Phase 6); селекция уезжает в `role.rules` |
| `scope_grant` (FGA-тип) | — | **НЕ существует** | **НОВЫЙ** FGA-примитив: `viewer/editor/admin`+per-verb relations на `(anchor, objectType)`; целевые типы каскадят tier from `scope_grant:<self_type>@anchor` **только на свой тип** (fix F1) |
| `access_binding_emitted_tuples` | — | **СУЩЕСТВУЕТ** (ledger, fix #178) | **переиспользуется** для revoke по сохранённому tuple-set (R-9) |
| `access_binding_targets` / `_selector` / `_target_members` / `resource_reconcile_outbox` / `resource_mirror` | — | СУЩЕСТВУЮТ (epic-100 α/γ, mig 0018-0022) | reconciler/mirror/outbox **переиспользуются** (driven by `role.rules`, rekeyed `rule_fp`); legacy target/selector-таблицы — INERT→DROP Phase 6 |
| `RoleService.{Get,List}` | — | LIVE; List `<exempt>` tenant-wide | `Get`→`returns (Role)` (live; `rules[]` публичны, `permissions[]` пустое); `List` scope-filtered (per-object, R-10) |
| `AccessBindingService.{ExpandAccess, ListByRole}` | — | **НЕ существуют** | **НОВЫЕ** sync read-RPC (E) |
| `List<Resource>` (vpc/compute/nlb/iam) | — | type-level listauthz (all-or-nothing) | **per-object filtered** через FGA `ListObjects` (R-10/§11/D) |

---

# ПОД-ФАЗА A — proto + `Role.rules` + компиляция `rules→permissions[]`

**Deliverable:** новые proto-сообщения (`Rule`, `Role.rules`/`subjects[]`), DB `roles.rules` колонка + shape-CHECK + cap-raise, чистый Go-компайлер `rules→permissions[]` (internal compiled, anchor/names; matchLabels НЕ компилируется), `RoleService.Create/Update/Get/List` принимают/возвращают `rules` (`Get` → `returns (Role)`, `permissions[]` в ответе пустое). **БЕЗ изменения FGA-эмиссии** (это B) — A валидирует/компилирует/хранит/отдаёт.
**Порядок:** `kacho-proto` (append-only, buf clean) → `kacho-iam` (domain compiler + repo + handler) → `kacho-api-gateway` (camelCase, `Get`→`Role`) → docs.

## Сценарий A-01: Happy — Create Role с mixed-арм rules → Operation → Get отдаёт rules[] (без compiled permissions в ответе)

**ID:** A-01

**Given** аутентифицированный caller с `iam.roles.create` (editor @ account `acc-A`)
**And** типы `vpc.subnet`, `compute.instance` присутствуют в feed-registry (§2.4)

**When** клиент вызывает `RoleService.Create` (`POST /iam/v1/roles`) с payload:
  - `accountId` = `acc-A`
  - `name` = `network-ops`
  - `rules` =
    - `{modules:["compute"], resources:["image"], verbs:["get"]}` (ARM_ANCHOR)
    - `{modules:["vpc"], resources:["subnet"], verbs:["create"], matchLabels:{env:"prod"}}` (ARM_LABELS)
    - `{modules:["vpc"], resources:["address"], verbs:["get","update"], resourceNames:["addr5k","addr9m"]}` (ARM_NAMES)

**Then** RPC возвращает `Operation` (async, ban #9); `OperationService.Get(id)` поллится до `done=true && !error`
**And** `RoleService.Get` (`GET /iam/v1/roles/{id}`) возвращает `Role` напрямую (НЕ обёртку) где `id` (prefix `rol`), `createdAt` заполнены
**And** `rules` = ровно три отправленных правила (порядок/значения сохранены, authority-форма; публичный API роли)
**And** `permissions` в ответе **пустое** (internal compiled-форма для FGA-эмиссии не заполняется в публичном Get для rules-ролей — R-7)
**And** в ответе **нет** поля `ruleDiagnostics` (диагностического message нет; `arm` каждого правила выводится клиентом из формы правила: ARM_ANCHOR = нет селектора, ARM_LABELS = `matchLabels`, ARM_NAMES = `resourceNames`)

## Сценарий A-02: `permissions[]` output-only — client-sent permissions отвергается

**ID:** A-02

**Given** аутентифицированный caller с `iam.roles.create`

**When** `RoleService.Create` с непустым `permissions` в теле (вместе или вместо `rules`)

**Then** sync `INVALID_ARGUMENT` `"Illegal argument permissions (compiled/output-only)"` (permissions не принимается на вход)
**And** ни одна роль не создана

## Сценарий A-03: AuthZ — anon и non-grantor отклоняются

**ID:** A-03

**Given** (a) анонимный запрос; (b) аутентифицированный caller БЕЗ `iam.roles.create` на `acc-A`

**When** `RoleService.Create` @ `acc-A`

**Then** (a) anon → отклоняется первым (`UNAUTHENTICATED`/fail-closed, `security.md`); (b) authenticated-non-grantor → `PERMISSION_DENIED`
**And** роль не создана

## Сценарий A-04: verb-`*` в custom-роли ДОПУСТИМ (R-3 / GWT-3 переопределён)

**ID:** A-04  ·  *(GWT-3, переопределён R-3)*

**Given** caller с `iam.roles.create`

**When** `RoleService.Create` с правилом `{modules:["compute"], resources:["instance"], verbs:["*"]}` (custom)

**Then** `Operation` done без error; `Get` отдаёт `Role` где `rules[0].verbs == ["*"]` (публичный API роли = `rules[]`)
**And** `permissions` в Get-ответе **пустое** (internal compiled `compute.instance.*.*` — verb-`*` как «все verbs типа», bounded per per-verb модель — НЕ часть API-ответа; internal-форма проверяется integration-тестом compile-parity, не публичным Get)

## Сценарий A-05: module-`*` / resource-`*` в custom-роли отвергается; в system — принимается

**ID:** A-05  ·  *(GWT-3 part)*

**Given** caller с `iam.roles.create` (custom-роль)

**When** (a) `{modules:["*"], resources:["instance"], verbs:["get"]}`; (b) `{modules:["compute"], resources:["*"], verbs:["get"]}`

**Then** оба → sync `INVALID_ARGUMENT "Illegal argument <field> (wildcard '*' is system-only)"`
**And** (seed-path, не публичный) is_system-роль с `modules:["*"]`/`resources:["*"]` принимается при seed (детерминированный id)

## Сценарий A-06: malformed role id → sync INVALID_ARGUMENT первым стейтментом

**ID:** A-06

**Given** caller с правом на Get

**When** `RoleService.Get` с `id` = `"not-a-role"` (не подходит под `rol`-prefix)

**Then** sync `INVALID_ARGUMENT "invalid role id 'not-a-role'"` (первым стейтментом, до repo)

## Сценарий A-07: well-formed-но-нет role → NOT_FOUND

**ID:** A-07

**When** `RoleService.Get` с well-formed но несуществующим `rol…`

**Then** `NOT_FOUND "Role <id> not found"`

## Сценарий A-08: update_mask discipline на Role.Update

**ID:** A-08

**Given** существующая custom-роль R

**When** `RoleService.Update` с:
  - (a) `update_mask` содержит `is_system` (immutable) → `INVALID_ARGUMENT "is_system is immutable after Role.Create"`
  - (b) `update_mask` содержит `permissions` (derived) → `INVALID_ARGUMENT "permissions is immutable after Role.Create"`
  - (c) `update_mask` содержит unknown `foo` → `INVALID_ARGUMENT "Illegal argument update_mask: unknown field 'foo'"`
  - (d) `update_mask` пустой + тело с `name`,`description`,`rules` → full-PATCH применяет mutable, immutable из тела silently игнорируются → `Operation` done

**Then** соответствующие коды/тексты; (d) `Get` отражает обновлённые mutable-поля

## Сценарий A-09: matchExpressions не поддержан (Q#3 v1)

**ID:** A-09

**When** `RoleService.Create` с правилом, несущим `matchExpressions` (In/NotIn/Exists)

**Then** sync `INVALID_ARGUMENT "Illegal argument matchExpressions (not supported)"`

## Сценарий A-10: feed-availability gate — non-fed тип в matchLabels отвергается (GWT-7 / fix #9)

**ID:** A-10  ·  *(GWT-7)*

**Given** caller с `iam.roles.create`

**When** `RoleService.Create` с ARM_LABELS-правилом на (a) `vpc.addressPool` (admin-only Internal, не fed) или (b) `lb.listeners` (нет producer) или (c) `iam.role` (iam-direct, **НЕ** в selectable-списке O-4)

**Then** sync `INVALID_ARGUMENT "type vpc.addressPool is not selectable (no resource feed)"` (соотв. `lb.listeners`, `iam.role`)
**And** роль НЕ создаётся в PENDING-состоянии (это reject, не вечный PENDING)
**And** **positive iam-direct**: ARM_LABELS-правило на `iam.project` (selectable iam-direct тип, O-4) `{modules:["iam"], resources:["project"], verbs:["get"], matchLabels:{tier:"gold"}}` → **принимается** (`Operation` done; тип в feed-registry)
**And** контр-пример: ARM_NAMES-правило на тот же не-selectable тип (`iam.role` через `resourceNames`) feed-gate'у НЕ подлежит → принимается

## Сценарий A-11: anchor-vs-matchLabels double-coverage — WARNING при одном tier, без warning при разных (Q#2)

**ID:** A-11

**Given** роль с правилами на один тип `compute.instance`

**When** (a) anchor-правило `verbs:["get"]` (viewer) + matchLabels-правило `verbs:["get"]` (viewer, тот же tier) → создаётся, `Operation` done с **validation WARNING** (избыточно-но-безвредно; WARNING в `Operation.metadata`/диагностике, НЕ error)
**And** (b) anchor-правило `verbs:["get"]` (viewer) + matchLabels-правило `verbs:["create","update","delete"]` (editor/admin, иной tier) → создаётся, **БЕЗ warning** (anchor НЕ subsumes label; оба арма live)

**Then** обе роли успешно созданы; различие — наличие/отсутствие WARNING

## Сценарий A-12: cap-raise — compiled ≤1024 принимается, >1024 → INVALID_ARGUMENT (GWT-12)

**ID:** A-12  ·  *(GWT-12)*

**Given** post-migration DB (cap-raise 256→1024 применён)

**When** (a) роль, чьи rules cartesian-разворачиваются в 300 compiled permissions; (b) роль, разворачивающаяся в >1024

**Then** (a) принимается (`Operation` done; DB CHECK `iam_permissions_valid` не reject'ит)
**And** (b) sync `INVALID_ARGUMENT "Illegal argument rules (compiled permissions exceed 1024)"` (НЕ silent truncation, НЕ INTERNAL)
**And** на pre-migration DB та же роль на 300 perm была бы reject'нута — параметр трассирует cap-raise

## Сценарий A-13: cardinality-bounds правила

**ID:** A-13

**When** Create с (a) пустой `rules:[]`; (b) `rules` > 64; (c) `modules`/`resources`/`verbs` > 16; (d) `resourceNames` > 256; (e) `matchLabels` > 16 ключей; (f) пустой `modules`/`resources`/`verbs`; (g) `resourceNames` И `matchLabels` в одном правиле; (h) `matchLabels:{}` (пуст при наличии)

**Then** каждый → sync `INVALID_ARGUMENT` с соответствующим стабильным текстом (§2.5); ни одна роль не создана
**And** DB CHECK `iam_rules_valid(jsonb)` энфорсит shape parity (within-DB, ban #10) — integration-тест прямой INSERT мимо use-case тоже reject'ится

## Сценарий A-14: custom-роль bind @ CLUSTER → FAILED_PRECONDITION (GWT-14 part)

**ID:** A-14  ·  *(GWT-14)*

**Given** custom (account-owned `acc-A`) роль R

**When** `AccessBinding.Create` с `scopeRef:{tier:CLUSTER, id:cluster_kacho_root}` для роли R

**Then** `Operation.error.code = FAILED_PRECONDITION "custom role cannot be bound at CLUSTER scope"` (async-контракт, ban #9)

## Сценарий A-15: scopeRef вне ancestry роли → FAILED_PRECONDITION (GWT-14 part)

**ID:** A-15  ·  *(GWT-14)*

**Given** custom account-роль R (`role.account_id == acc-A`)

**When** `AccessBinding.Create` с `scopeRef:{tier:PROJECT, id:prj-X}` где `prj-X` НЕ принадлежит `acc-A`

**Then** `Operation.error.code = FAILED_PRECONDITION "scope <tier>:<id> is not within role ownership"`

## Сценарий A-16: Role.Delete пока роль несёт ≥1 binding → FAILED_PRECONDITION (FK 23503); после purge биндингов — проходит

**ID:** A-16  ·  *(O-7 ПРИНЯТО)*

> **Семантика удаления (зафиксировано по факту кода, ревью-round 3).** `AccessBindingService.Delete` —
> **HARD delete** (`DELETE FROM access_bindings` — строка физически удаляется, см. `abWriter.Delete`),
> НЕ soft-revoke. Soft-revoke (`status=REVOKED`, строка остаётся) — это отдельный lifecycle-путь
> `TransitionStatus` (expiry/reconcile), НЕ вызываемый из `AccessBindingService.Delete`. FK
> `access_bindings_role_fk ON DELETE RESTRICT` блокирует `Role.Delete` пока существует **любая**
> binding-строка, ссылающаяся на роль (ACTIVE **или** оставшаяся REVOKED-строка) — поэтому текст
> ошибки **не** квалифицируется словом «active»: `"role is in use by access bindings"`. Precondition
> снимается именно **purge** биндинга (hard-delete убирает FK-child).

**Given** custom-роль R несёт ≥1 access-binding-строку (`access_bindings_role_fk` RESTRICT)

**When** клиент вызывает `RoleService.Delete(R)` (`DELETE /iam/v1/roles/{id}`)

**Then** `Operation.error.code = FAILED_PRECONDITION "role is in use by access bindings"` (FK SQLSTATE `23503`→FailedPrecondition в `mapRepoErr`; **без leak pgx/SQL-текста** наружу, фикс. INTERNAL не используется)
**And** роль R НЕ удалена (остаётся в `Get`)
**And** после `AccessBinding.Delete` (hard-purge) всех биндингов, несущих R, повторный `RoleService.Delete(R)` → `Operation` done без error; затем `Get(R)` → `NOT_FOUND "Role <id> not found"`
**And** integration-тест (testcontainers): прямой DELETE при существующем FK-child reject'ится на DB-уровне (within-DB инвариант, ban #10 — RESTRICT, не software check-then-act)
**And** concurrent (data-integrity §5): `Role.Delete` ∥ `AccessBinding` grant на ту же роль → FK + row-lock сериализуют, ровно ОДИН успех; проигравший → `FAILED_PRECONDITION` (delete-loser «in use», grant-loser «role not found»), second-writer не выигрывает молча

### DoD под-фазы A
- [ ] `kacho-proto`: `Rule`/`Role.rules=11`/`resource_version=12`/`created_by_user_id=13`/`updated_at=14`/`AccessBinding.subjects=19` (append-only); **`RoleService.Get` остаётся `returns (Role)`** (НЕ `GetRoleResponse`-обёртка); **`RuleDiagnostics` НЕ создаётся**; `organization_id=9` tombstone, `Role.permissions=5` deprecated; **`aggregationRule` — только proto-комментарий «reserved, not in this phase», БЕЗ резерва tag (O-1)**; `buf lint`/`buf breaking`/`buf generate` зелёные (gate `proto-api-reviewer`).
- [ ] `kacho-iam`: forward-миграция (≥0024) `roles.rules jsonb NOT NULL DEFAULT '[]'` + `iam_rules_valid` CHECK + cap-raise lockstep (DB CHECK 256→1024 + domain + proto `(size)` в одной tx); чистый Go-компайлер `rules→permissions` (internal compiled) в `domain/` (anchor/names only, per-rule tier); `RoleService.Create/Update/Get/List` (`Get`→`Role`, `permissions[]` в ответе НЕ заполняется для rules-ролей); internal `permissions` пересчитывается в Go composition-root в одной tx с записью `rules` (НЕ в PL/pgSQL — drift-hazard); parity-fuzz `compile(rules)`↔stored permissions (integration, не публичный Get).
- [ ] `kacho-api-gateway`: `Role` camelCase (`rules`/`matchLabels`/`resourceNames`/`resourceVersion`/`createdByUserId`); `Get` отдаёт `Role` напрямую; public mux; Internal* не трогаем.
- [ ] **RED→GREEN**: integration (testcontainers — `iam_rules_valid` CHECK, cap-raise, compile parity, **label-only role (A-10) persists с пустым compiled-set**, legacy-empty-permissions всё ещё reject, **Role.Delete FK 23503→FailedPrecondition A-16** + direct-DELETE RESTRICT + **concurrent delete∥grant race**) + newman (happy A-01 + label-only A-10 positive с Get-roundtrip + negative A-02/A-04/A-05/A-09/A-10/A-12/A-13 + **A-16 delete-in-use→FAILED_PRECONDITION, затем purge→delete OK**) в том же PR.
- [ ] db-architect-reviewer (миграция), proto-api-reviewer (proto), go-style-reviewer (compiler).
- [ ] vault-trail: `resources/iam-role.md` (rules-форма, cap, `permissions[]` internal-only), `rpc/iam-role-service.md` (`Get`→`Role`), KAC-trail.

---

# ПОД-ФАЗА B — type-scoped FGA emission (`scope_grant`) + per-verb relations (fix F1 + R-2)

**Deliverable:** новый FGA-примитив `scope_grant` (type-scoped anchor, fix F1), per-verb FGA-relations (R-2), arm-tagged emit-вход (ANCHOR→`scope_grant`, NAMES→per-object, LABELS→suppress-anchor), revoke по `access_binding_emitted_tuples`. **Закрывает escalation #177.** matchLabels-материализация (reconciler) — в C; B покрывает ANCHOR+NAMES + per-verb + revoke-ledger.
**Порядок:** `kacho-proto` (`fga_model.fga` + per-verb relations) → `kacho-iam` (emit arm-tag, scope_grant, ledger-revoke) → `kacho-deploy` (FGA-модель re-bootstrap, tuple-снапшот) → docs.

## Сценарий B-10: escalation — all_in_scope даёт admin ТОЛЬКО над своим типом (GWT-1 / fix F1 / #177)

**ID:** B-10  ·  *(GWT-1, CRITICAL)*

**Given** роль с одним правилом `{modules:["compute"], resources:["instance"], verbs:["get","list","create","update","delete"]}` (ARM_ANCHOR, admin-эквивалент)
**And** binding @ `scopeRef:{tier:ACCOUNT, id:acc-A}` для subject S

**When** binding ACTIVE (Operation done), FGA-tuples материализованы

**Then** FGA Check `S can delete compute.instance:<i>` (i в scope `acc-A`) → **allow**
**And** FGA Check `S can <any> vpc.subnet:<x>` / `vpc.network:<x>` / `iam.role:<x>` → **deny** (НЕТ admin/editor/viewer над чужими типами — escalation закрыт)
**And** эмитированный tuple — `scope_grant:account:acc-A/compute_instance#admin@S` (type-scoped), НЕ whole-role tuple на голый `account:acc-A`

## Сценарий B-11: mixed-tier — anchor-tier per правило, без whole-role collapse (GWT-2)

**ID:** B-11  ·  *(GWT-2)*

**Given** роль: rule A `{compute, image, [get]}` (viewer ARM_ANCHOR) + rule B `{compute, instance, [get,list,create,update,delete]}` (editor/admin ARM_ANCHOR)
**And** binding @ ACCOUNT для S

**When** binding ACTIVE

**Then** FGA Check `S can <editor-verb> compute.image:<x>` → **deny** (image tier == viewer, НЕ поднят до editor через whole-role collapse)
**And** FGA Check `S can get compute.image:<x>` → **allow**; `S can delete compute.instance:<y>` → **allow**

## Сценарий B-12: per-verb enforcement — delete энфорсится отдельно от create (R-2 / GWT-2b)

**ID:** B-12  ·  *(R-2, новое — per-verb best-2026)*

**Given** роль с правилом `{compute, instance, ["get","create"]}` (НЕ delete, НЕ update) ARM_ANCHOR
**And** binding @ ACCOUNT для S

**When** binding ACTIVE

**Then** FGA Check `S can create compute.instance:<x>` → **allow**
**And** FGA Check `S can get compute.instance:<x>` → **allow**
**And** FGA Check `S can delete compute.instance:<x>` → **deny** (delete НЕ collapse'нут в editor вместе с create)
**And** FGA Check `S can update compute.instance:<x>` → **deny**
**And** **verb-`*` разворот (O-3):** роль с `{compute, instance, ["*"]}` ARM_ANCHOR @ ACCOUNT для S' → FGA Check `S' can <каждый_конкретный_verb из закрытого per-verb набора типа compute.instance> compute.instance:<x>` → **allow** для ВСЕХ verbs типа (арм наследует все per-verb relations типа, bounded — не открытый `*`-relation); ни один verb типа не остаётся deny

## Сценарий B-13: revoke по сохранённому tuple-set — Delete binding удаляет ровно эмитированное (GWT-4 part)

**ID:** B-13  ·  *(GWT-4 ledger, R-9)*

**Given** binding B (ARM_ANCHOR + ARM_NAMES) ACTIVE; `access_binding_emitted_tuples` несёт сохранённый при grant tuple-set

**When** `AccessBinding.Delete(B)` → `Operation` done

**Then** все эмитированные при grant tuple'ы удалены из FGA (revoke по ledger, НЕ re-derive)
**And** FGA Check для всех subjects B → **deny**; zero orphans (assert по ledger пуст для B)

## Сценарий B-14: ARM_NAMES per-object tuple + concurrent grant idempotency

**ID:** B-14

**Given** правило ARM_NAMES `{vpc, address, [get,update], resourceNames:[addr5k]}`, объект `addr5k` существует in-scope нужного типа

**When** binding ACTIVE; затем повторный идентичный `AccessBinding.Create` (same subjects/role/scope)

**Then** эмитится `fga(vpc,address):addr5k#get@S` + `…#update@S` (per-object, per-verb)
**And** повторный Create идемпотентен (strict-create UNIQUE) → не двойной tuple-set; ledger консистентен
**And** integration-тест с ≥2 concurrent goroutine на тот же binding-path: ровно один tuple-set, остальные no-op (ban #10 CAS)

### DoD под-фазы B
- [ ] `kacho-proto`: `fga_model.fga` — новый тип `scope_grant{viewer,editor,admin + per-verb relations}`; целевые типы каскадят tier from `scope_grant:<self_type>@anchor` ТОЛЬКО на свой тип; per-verb relations на всех ресурсных типах; **`verbs:["*"]`-арм разворачивается в полный закрытый per-verb набор типа — наследует ВСЕ конкретные per-verb relations типа (bounded, не открытый `*`-relation), O-3 (B-12-окрестность)**; `buf` зелёный.
- [ ] `kacho-iam`: emit с arm-tag (ANCHOR→`scope_grant`, NAMES→per-object, LABELS→suppress); per-rule tier (`verbClass` правила, НЕ whole-role); revoke по `access_binding_emitted_tuples` (ledger из #178); emit в одной writer-tx с binding INSERT + fga_outbox (ban #10).
- [ ] `kacho-deploy`: FGA-модель re-bootstrap (новый model id), pre/post tuple-снапшот; rollback-окно (старые anchor-relations параллельно).
- [ ] **RED→GREEN**: integration (escalation B-10/B-11, per-verb B-12 **+ verb-`*` разворот в полный per-verb набор типа, O-3**, revoke ledger B-13, concurrent B-14) + newman (FGA Check через api-gateway: allow/deny матрица, включая verb-`*`→все-verbs-типа) в том же PR.
- [ ] system-design-reviewer (escalation-замыкание, emit-tx-атомарность), proto-api-reviewer (`fga_model.fga`).
- [ ] vault: `edges/iam-to-openfga-check.md` (scope_grant, per-verb), `resources/iam-access-binding.md` (revoke-ledger).

---

# ПОД-ФАЗА C — per-rule reconciler + matchLabels-материализация + condition + Role.Update fan-out

**Deliverable:** ARM_LABELS reconciler (driven by `role.rules`, `rule_fp`-keyed, REUSE epic-103/γ reconciler+mirror+outbox), matchLabels per-object materialization + containment, condition→FGA conditional-tuple (R-8), resourceNames PENDING/REJECTED жизненный цикл, `Role.Update(rules)` bounded фан-аут reconcile (R-9), OCC.
**Порядок:** `kacho-iam` (reconciler rekey, matchLabels emit, condition-tuple, fan-out) → `kacho-deploy` (mirror-sync gate) → docs.

## Сценарий C-20: revoke после Role.Update(rules) — нет residual из R1∖R2 (GWT-4 full)

**ID:** C-20  ·  *(GWT-4, CRITICAL #3)*

**Given** binding B несёт роль R = rules R1 (ACTIVE, tuple-set эмитирован, ledger заполнен)

**When** `Role.Update(R, rules=R2)` где R2 ⊊ R1 (правило удалено) → затем `AccessBinding.Delete(B)`

**Then** FGA tuple-set для B **пуст**; нет residual из R1∖R2 (revoke по ledger удаляет ровно то, что было эмитировано, R-9)
**And** assert zero orphans (ledger пуст, FGA Check всех subjects → deny)

## Сценарий C-21: Role.Update fan-out — все ACTIVE-биндинги reconcile, eager-revoke по rule_fp (GWT-5)

**ID:** C-21  ·  *(GWT-5)*

**Given** роль R несёт N ACTIVE-биндингов; R содержит matchLabels-правило P

**When** `Role.Update(R)` удаляет правило P

**Then** все N биндингов reconcile (через `resource_reconcile_outbox`, async drain); per-object tuple'ы правила P eager-revoked **по `rule_fp`** (content-hash, не позиционный index)
**And** `Operation` (Role.Update) завершается когда все per-binding reconcile задренены
**And** фан-аут bounded: роль с **> 10000** ACTIVE-биндингов (фиксированный контрактный лимит, O-8) → `Operation.error FAILED_PRECONDITION "role carried by too many bindings to update atomically; split role"`
**And** integration-тест: concurrent (reorder правил в R) не десинхронит membership (rule_fp-keyed)

## Сценарий C-22: matchLabels НЕ over-grant — per-object только на совпавшие, БЕЗ anchor (GWT-6 / fix #8)

**ID:** C-22  ·  *(GWT-6, HIGH #8)*

**Given** правило `{vpc, subnet, [create], matchLabels:{env:prod}}`; в scope `acc-A` есть subnet `s1{env:prod}`, `s2{env:staging}`
**And** binding @ ACCOUNT для S

**When** binding ACTIVE, reconciler отработал

**Then** эмитится per-object tuple ТОЛЬКО на `s1` (`fga(vpc,subnet):s1#create@S`)
**And** **НЕ** эмитится anchor-tuple «все subnet в scope» (matchLabels не в `permissions[]`, fix #8)
**And** FGA Check `S can create vpc.subnet:s2` → **deny** (s2 не совпал)
**And** later `s2` получает label `env=prod` (owner-сервис обновил mirror) → reconciler домётывает tuple на `s2` → Check `s2` → allow

## Сценарий C-23: condition не bypass — expired binding → FGA Check deny на всех call-site (GWT-9)

**ID:** C-23  ·  *(GWT-9, MEDIUM #11)*

**Given** binding с `builtinCondition=NON_EXPIRED` (или time/IP/MFA condition), после момента expiry

**When** subject пытается действие на любом consumer call-site (vpc/compute/geo/nlb через `InternalIAMService.Check`)

**Then** raw FGA tuple существует, НО Check возвращает **deny** (condition энфорсится FGA conditional-tuple, R-8)
**And** fail-closed: ошибка вычисления condition → deny + audit

## Сценарий C-24: resourceNames PENDING bounded — out-of-scope/type-mismatch REJECTED, in-scope ACTIVE (GWT-10)

**ID:** C-24  ·  *(GWT-10)*

**Given** правило ARM_NAMES с id `addrZ`, которого нет в mirror на момент Create

**When** binding создан → `addrZ` материализуется `PENDING_VERIFICATION` (bounded TTL); затем три ветки:
  - (a) `addrZ` создан **вне `scopeRef`** → **REJECTED** + audit (никогда auto-ACTIVE; tuple НЕ эмитится)
  - (b) `addrZ` создан **другого типа** (mirror `object_type ≠` тип правила) → **REJECTED** (type-mismatch) + audit
  - (c) `addrZ` создан **in-scope нужного типа** → **ACTIVE** (tuple эмитится)

**Then** соответствующие переходы; binding/membership-статус (ACTIVE/PENDING_VERIFICATION/REJECTED) отражает результат материализации; bounded TTL не оставляет вечный PENDING

## Сценарий C-25: label-tampering — admin/editor matchLabels требует requireGrantAuthority (GWT-11 / sec #4)

**ID:** C-25  ·  *(GWT-11, HIGH security)*

**Given** low-priv tenant с editor на `vpc.subnet` ставит `env=prod` на свой subnet
**And** foreign admin-binding селектит `matchLabels:{env:prod}`

**When** создание admin/editor matchLabels-binding

**Then** Create требует `requireGrantAuthority` на `scopeRef` (low-priv актор НЕ может авторить self-serving admin/editor label-selector) → без права → `Operation.error PERMISSION_DENIED`
**And** на каждом reconcile — `IsContainedIn(scopeRef)` re-verify отсекает cross-scope-инъекцию через label-tampering (объект вне scope → REJECTED, не tuple)

## Сценарий C-26: OCC + reconcile race — консистентный rule-snapshot, ровно один Update (GWT-13)

**ID:** C-26  ·  *(GWT-13)*

**Given** роль R с `resource_version` (xmin-backed)

**When** concurrent: `Role.Update(R, rules)` (xmin CAS) ⟂ `AccessBinding.Create` читающий ту же R

**Then** grant использует консистентный rule-snapshot (lock binding → read role-snapshot в одной tx — нет torn read)
**And** ровно один `Role.Update` коммитит; второй с тем же `resource_version` → `FAILED_PRECONDITION "Role was modified concurrently, retry"`
**And** integration-тест ≥2 goroutine (testcontainers, ban #10/§data-integrity п.5)

### DoD под-фазы C
- [ ] `kacho-iam`: reconciler driven by `role.rules` (per-rule `rule_fp`-keyed; lock-order binding→role-snapshot); matchLabels per-object materialization + `IsContainedIn` re-verify; condition→FGA conditional-tuple (R-8); resourceNames PENDING/REJECTED lifecycle + bounded TTL; `Role.Update(rules)` bounded фан-аут reconcile (R-9) через `resource_reconcile_outbox` с **фиксированным лимитом 10000 active bindings/role (O-8) — превышение → `FAILED_PRECONDITION` (C-21)**; OCC `xmin::text` CAS; `requireGrantAuthority` на admin/editor matchLabels-binding. **REUSE** `MatchSelector`/`MatchIAMDirect`/`IsContainedIn`/`membershipTuples`/`fga_outbox`+drainer/`resource_reconcile_outbox`+sweep/`resource_mirror`.
- [ ] миграция: `role_rule_selectors(role_id, rule_fp, object_types[], match_labels jsonb) PK(role_id,rule_fp)`; ALTER `access_binding_target_members` ADD `role_id,rule_fp` + PK→`(binding_id,role_id,rule_fp,object_type,object_id)` + backfill.
- [ ] `kacho-deploy`: mirror-sync gate (vpc/compute/nlb `RegisterResource`-backfill complete перед flip).
- [ ] **RED→GREEN**: integration (revoke-after-update C-20, fan-out C-21 concurrent, matchLabels C-22, condition C-23, resourceNames C-24, label-tampering C-25, OCC race C-26) + newman в том же PR.
- [ ] system-design-reviewer (reconciler redrive, OCC, fan-out bounded), db-architect-reviewer (rekey-миграция).
- [ ] vault: `resources/iam-access-binding.md` (reconciler rekey, condition-tuple), `edges/`.

---

# ПОД-ФАЗА D — per-object filtered `List` (§11, КРИТИЧНО — требование заказчика)

**Deliverable:** `List<Resource>` во всех доменах (iam/vpc/compute/nlb) возвращает **только доступные объекты** через FGA `ListObjects` поверх materialized per-object tuples + `scope_grant`. read==enforce паритет. `make audit-list-filter` расширяется до per-object. Pagination ПОСЛЕ фильтра. **НЕ K8s all-or-nothing.**
**Порядок:** `kacho-corelib` (listauthz per-object helper, если общий) → `kacho-iam` (`InternalIAMService` ListObjects-аналог) → consumer-сервисы (vpc/compute/nlb List-filter) → `kacho-api-gateway` → `kacho-deploy` (расширить audit-гейт) → docs.

## Сценарий D-40: LST-1 labels — List отдаёт только совпавшие по меткам в scope

**ID:** D-40  ·  *(LST-1)*

**Given** subject S с matchLabels-list-грантом `{vpc, subnet, [list], matchLabels:{env:prod}}` @ ACCOUNT `acc-A`
**And** в scope: `s1{env:prod}`, `s2{env:prod}`, `s3{env:staging}`

**When** S вызывает `SubnetService.List` (`GET /vpc/v1/subnets?...`) в scope `acc-A`

**Then** ответ содержит **ровно** `{s1, s2}` (env=prod), `s3` отсутствует
**And** read==enforce: FGA Check `S can get vpc.subnet:s3` → deny (та же tuple-база)

## Сценарий D-41: LST-2 byName — List отдаёт ровно перечисленные id

**ID:** D-41  ·  *(LST-2)*

**Given** subject S с resourceNames-list-грантом на `[id1, id2]` (тип `compute.instance`) @ ACCOUNT
**And** в scope также существуют `id3, id4` (не в гранте)

**When** S вызывает `InstanceService.List`

**Then** ответ = ровно `{id1, id2}` (если существуют в scope), не больше; `id3,id4` отсутствуют

## Сценарий D-42: LST-3 global — all_in_scope list-грант → все объекты типа в scope

**ID:** D-42  ·  *(LST-3)*

**Given** subject S с ARM_ANCHOR list-грантом `{vpc, network, [list]}` @ ACCOUNT `acc-A` (`scope_grant`)

**When** S вызывает `NetworkService.List` в scope `acc-A`

**Then** ответ содержит **все** network в scope `acc-A`; network из другого account → отсутствуют (containment)

## Сценарий D-43: LST-4 union — несколько правил (labels ∪ names) → объединение видимых

**ID:** D-43  ·  *(LST-4)*

**Given** subject S с двумя list-правилами на `vpc.subnet`: matchLabels `{env:prod}` ∪ resourceNames `[sX]` (sX{env:staging})

**When** S вызывает `SubnetService.List`

**Then** ответ = `{все env=prod subnet в scope} ∪ {sX}` (union армов, дедуп)

## Сценарий D-44: LST-5 negative/no-leak — объект вне всех грантов отсутствует в List И Get→NotFound

**ID:** D-44  ·  *(LST-5)*

**Given** subject S без гранта на объект `sZ` (в том же scope)

**When** (a) S вызывает `SubnetService.List`; (b) S вызывает `SubnetService.Get(sZ)`

**Then** (a) `sZ` **отсутствует** в List (не leak'ается existence)
**And** (b) `Get(sZ)` → `NOT_FOUND "Subnet sZ not found"` (НЕ `PERMISSION_DENIED` — не подтверждаем existence)

## Сценарий D-45: read==enforce паритет — List-видимость совпадает с Check-allow

**ID:** D-45

**Given** subject S с произвольным набором rules-грантов на тип T

**When** для каждого объекта o типа T в scope сравниваются `o ∈ List(T)` и `FGA Check(S, list/get, o)`

**Then** множества **совпадают** (single source of truth — те же materialized tuples + `scope_grant`); расхождений нет
**And** `make audit-list-filter` (per-object расширение) проходит для всех публичных List всех доменов

## Сценарий D-46: LST-6 pagination — page_size/page_token корректны ПОСЛЕ фильтра

**ID:** D-46  ·  *(LST-6)*

**Given** subject S с грантом, дающим доступ к 120 объектам типа T (из 500 в scope)
**And** `page_size = 50`

**When** S листает с cursor-пагинацией (3 страницы)

**Then** страницы покрывают ровно 120 доступных объектов (50+50+20), без «дырявых» страниц (pagination применяется к **отфильтрованному** набору, не к сырому)
**And** `next_page_token` opaque base64; garbage token → `INVALID_ARGUMENT`

## Сценарий D-47: cross-domain consumer List fail-closed при недоступном IAM

**ID:** D-47

**Given** consumer (vpc/compute/nlb) фильтрует List через `InternalIAMService` (ListObjects-аналог)

**When** IAM недоступен на момент List

**Then** consumer fail-closed: `UNAVAILABLE` (НЕ возврат нефильтрованного списка — не leak; `security.md` fail-closed)

### DoD под-фазы D
- [ ] `kacho-iam`: `InternalIAMService` ListObjects-аналог (FGA `ListObjects` поверх materialized tuples + `scope_grant`); read==enforce.
- [ ] consumer-сервисы (vpc/compute/nlb + iam own List): публичный `List<Resource>` прогоняет id-set через ListObjects/batch-Check, отдаёт пересечение; pagination ПОСЛЕ фильтра; `Get` вне гранта → NOT_FOUND (no-leak).
- [ ] `kacho-corelib`: per-object listauthz helper (если ≥2 сервиса).
- [ ] `kacho-deploy`/CI: `make audit-list-filter` расширен до per-object (CI-гейт по всем публичным List всех доменов).
- [ ] **RED→GREEN**: integration + newman LST-1..6 (D-40..D-46) + D-47 fail-closed, **per арм для всех доменов** (compute/vpc/nlb/iam), в том же PR.
- [ ] system-design-reviewer (read==enforce, fail-closed, replica-isolation), security-review (no-leak).
- [ ] **load-testing-coach gate ОБЯЗАТЕЛЕН перед prod-flip (O-5 ПРИНЯТО):** нагрузочная валидация FGA `ListObjects` на крупных наборах (тысячи объектов/тип/scope) — latency/cardinality + стабильность cursor-пагинации ПОСЛЕ фильтра; prod-flip под-фазы D не разрешён без зелёного load-gate.
- [ ] vault: `edges/<consumer>-to-iam-listobjects.md`, расширить `resources/iam-access-binding.md`.

> **NB (O-5 ПРИНЯТО):** §11 требует per-object List через FGA `ListObjects`. Производительность/cardinality `ListObjects` на крупных наборах (тысячи объектов на тип в scope) — нагрузочный риск; **load-testing-coach/ghz gate обязателен перед prod-flip** (см. DoD выше). Решение зафиксировано (§5 O-5), не открытый вопрос.

---

# ПОД-ФАЗА E — `subjects[]` + `ExpandAccess` + `ListByRole`

**Deliverable:** `AccessBinding.subjects[]` (1..32, per-subject независимый tuple-set/revoke/lineage, R-5), новый sync read-RPC `ExpandAccess` (userset→concrete principals, R-6), `ListByRole` (audit «кто несёт роль R»). Group-amplification guard (Q#4).
**Порядок:** `kacho-proto` (`subjects=19`, `ExpandAccess`/`ListByRole` RPC) → `kacho-iam` → `kacho-api-gateway` (public mux) → `kacho-ui` (multi-subject grant-форма) → docs.

## Сценарий E-30: subjects[] independence — нет double-grant аномалии, per-subject revoke (GWT-15 part)

**ID:** E-30  ·  *(GWT-15)*

**Given** `AccessBinding.Create` с 32 subjects, включая `(user U, group G содержащий U)`

**When** binding ACTIVE

**Then** нет double-grant аномалии (каждый subject → независимый tuple-set; U через прямой grant И через G — корректно, не конфликт)
**And** per-subject independent revoke: удаление одного subject из набора (или per-subject path) не трогает tuple'ы других

## Сценарий E-31: ExpandAccess — userset разворачивается в concrete principals (GWT-15 part)

**ID:** E-31  ·  *(GWT-15, R-6)*

**Given** binding с group-subject G (члены: U1, U2); роль даёт `delete compute.instance`

**When** `AccessBindingService.ExpandAccess` (`POST /iam/v1/accessBindings:expandAccess`) с запросом «кто может delete compute.instance:<x>»

**Then** sync-ответ перечисляет **concrete principals** {U1, U2} (FGA Expand userset→principals), не только «group G»
**And** аудит-кейс «кто реально может X» закрыт

## Сценарий E-32: subjects[] bounds + group-amplification guard (Q#4)

**ID:** E-32

**When** (a) `Create` с `subjects:[]` (пусто) или > 32 → sync `INVALID_ARGUMENT "Illegal argument subjects (must be 1..32)"`
**And** (b) `Create` admin/editor-роли с GROUP-subject → требует `requireGrantAuthority` на `scopeRef` (иначе `Operation.error PERMISSION_DENIED`)

**Then** соответствующие коды

## Сценарий E-33: ListByRole — audit «кто несёт роль R»

**ID:** E-33

**Given** роль R несёт несколько биндингов

**When** `AccessBindingService.ListByRole(roleId=R)` (sync read, cursor-paged)

**Then** ответ перечисляет все биндинги, несущие R (с subjects/scopeRef); authz: только grant-authority holder / admin

## Сценарий E-34: read-projection — Get/List/ListByRole заполняют ОБА представления (new + legacy) в окне до Phase 6

**ID:** E-34  ·  *(O-6 ПРИНЯТО)*

**Given** binding B создан через **новое** представление: `subjects[]` (например `[{type:USER,id:U1},{type:GROUP,id:G}]`) + `scopeRef:{tier:ACCOUNT, id:acc-A}` (deprecated legacy-поля на входе НЕ задавались)

**When** клиент вызывает `AccessBindingService.Get(B)` / `List` / `ListByRole(roleId=R)` в окне до Phase 6

**Then** ответ заполняет **ОБА** представления одновременно (старые клиенты не ломаются):
  - new: `subjects[]` (полный набор), `scopeRef{tier,id}`
  - legacy: `subjectType`/`subjectId` (= **первый** subject из `subjects[]`), `resourceType`/`resourceId`/`scope` (= legacy-проекция `scopeRef`-триплета `(scope,resource_type,resource_id)`, R-14)
**And** обратная проекция: binding, авторённый через **legacy single-subject** вход (`subjectType`/`subjectId`), в ответе несёт `subjects[]` ровно из одного элемента (`[{type:subjectType,id:subjectId}]`) — паритет new←legacy
**And** проекция — output-only, не источник истины; на входе Create приоритет у `subjects[]`/`scopeRef` (legacy single-поля при наличии `subjects[]` silently игнорируются)
**And** окно действует ДО Phase 6 (F-cleanup-30 DROP'ает legacy-поля; после Phase 6 проекция снимается)

### DoD под-фазы E
- [ ] `kacho-proto`: `AccessBinding.subjects=19` (`repeated Subject`), `Subject{type,id}`; `ExpandAccess`/`ListByRole` RPC + request/response; append-only buf clean.
- [ ] `kacho-iam`: `access_binding_subjects(binding_id FK CASCADE, subject_type, subject_id) UNIQUE`; per-subject independent tuple-set/revoke/lineage; `ExpandAccess` (FGA Expand); `ListByRole`; group-amplification `requireGrantAuthority`; **dual read-projection (E-34): Get/List/ListByRole заполняют ОБА представления — new `subjects[]`/`scopeRef` + legacy `subjectType`/`subjectId`/`resourceType`/`resourceId`/`scope` (legacy = первый subject + `scopeRef`-триплет) в окне до Phase 6; legacy-single binding ⇒ `subjects[]` из одного элемента**.
- [ ] `kacho-api-gateway`: `ExpandAccess`/`ListByRole` public mux; camelCase `subjects`.
- [ ] `kacho-ui`: multi-subject grant-форма (1..32 subjects).
- [ ] **RED→GREEN**: integration (subjects independence E-30, ExpandAccess E-31, bounds/guard E-32, ListByRole E-33, **dual read-projection E-34 — Get/List/ListByRole возвращают ОБА представления + legacy-single↔subjects[] паритет**) + newman (включая E-34 new-author→legacy-fields-filled и legacy-author→subjects[]-filled) в том же PR.
- [ ] proto-api-reviewer, system-design-reviewer (group-amplification, Expand).
- [ ] vault: `rpc/iam-access-binding-service.md` (ExpandAccess/ListByRole/subjects).

---

# ПОД-ФАЗА F — миграция live-данных + UI + legacy-cleanup

**Deliverable:** backfill `rules` из `permissions` (anchor/names детерминирован; matchLabels не recoverable), legacy γ-биндинги **INERT** до re-author (R-13), UI рендер из `rules[]` (arm выводится клиентом из формы правила; verb-`*` теперь разрешён для custom — R-3), re-seed system-ролей через `rules[]`, **Phase 6 breaking-cleanup** (legacy target/selector DROP, retire target-мутаторов, rename `ListByResource→ListByScope`, R-15).
**Порядок:** `kacho-iam` (backfill-миграция, inert-guard, re-seed) → `kacho-ui` (рендер из rules) → `kacho-deploy` (flag flip после mirror-sync gate + FGA re-bootstrap) → `kacho-workspace` (docs) → **отдельный major: Phase 6 cleanup**.

## Сценарий F-01: backfill rules из permissions — детерминирован для anchor/names

**ID:** F-01

**Given** pre-redesign роль с `permissions=["compute.image.*.get", "vpc.address.addr5k.update"]` (anchor + names армы)

**When** backfill-миграция (≥0024) выполняется

**Then** `roles.rules` = `[{compute,image,[get]} (ARM_ANCHOR), {vpc,address,[update],resourceNames:[addr5k]} (ARM_NAMES)]`
**And** `compile(rules) == permissions` (round-trip parity для anchor/names)
**And** matchLabels-правил не появляется (из permissions не recoverable — их не было в плоской форме)

## Сценарий F-20: dual-authority — legacy γ-биндинг INERT, нет double-emit (GWT-8)

**ID:** F-20  ·  *(GWT-8, HIGH #10)*

**Given** legacy by_selector-биндинг (epic-100 γ `binding.selector`/`target`), существующий ДО flip-флага

**When** роль обретает matchLabels-правила (role-driven селекция включена флагом)

**Then** reconciler **НЕ** double-эмитит (legacy target tuples + role.rules tuples) для одного `(binding, object)`
**And** legacy-путь остаётся authority для pre-flag биндингов до явного re-author (role-driven селекция к ним **инертна** — explicit guard, не lazy)
**And** bit-identical-инвариант держится для all_in_scope-биндингов (compiled permissions + FGA tuple-set до/после)
**And** integration-тест: zero double-emit на legacy `(binding,object)`

## Сценарий F-21: legacy target-мутаторы в окне → FAILED_PRECONDITION (Q#5)

**ID:** F-21

**Given** окно deprecation (флаг включён, Phase 6 ещё не наступила)

**When** клиент вызывает legacy `AddTargetResources`/`RemoveTargetResources`/`ReplaceTargetSelector`

**Then** `Operation.error FAILED_PRECONDITION` (RPC зарегистрирован, но write отклоняется — селекция уехала в `role.rules`)
**And** `ListByResource` wire-name СОХРАНЁН (НЕ переименован до Phase 6)

## Сценарий F-22: UI рендер из rules[] (resource-first, arm выводится из формы правила, verb-* разрешён)

**ID:** F-22

**Given** роль с mixed-арм rules

**When** UI открывает Role-detail / grant-форму

**Then** UI рендерит роль из `role.rules[]` (НЕ из `permissions[]` — оно пустое в API-ответе); arm каждого правила (ARM_ANCHOR/ARM_LABELS/ARM_NAMES) UI выводит из формы правила (наличие `matchLabels`/`resourceNames`)
**And** автор правил per-rule; verb-`*` в UI **разрешён** для custom (R-3 — отличие от §8); module/resource-`*` disabled для custom
**And** UI прекращает отправлять `binding.target`/`selector`

## Сценарий F-09: buf-breaking чистота — append-only

**ID:** F-09

**When** CI прогоняет `buf breaking` против main на всех proto-изменениях (A+E)

**Then** **зелёный**: ZERO renumber/delete; новые `Rule`/`Role.rules=11`/`AccessBinding.subjects=19`/`ExpandAccess`/`ListByRole` — append-only; `RoleService.Get` остаётся `returns (Role)` (НЕ `GetRoleResponse`); `RuleDiagnostics` не вводится; `organization_id=9` остаётся tombstone (reserved, не удалён), `Role.permissions=5` deprecated

## Сценарий F-cleanup-30: Phase 6 — legacy DROP + rename (отдельный major, breaking)

**ID:** F-cleanup-30  ·  *(R-15, Phase 6)*

**Given** все γ-биндинги re-author'ены в `role.rules` (data-cleanup завершён); deprecation-окно (≥1 минор) прошло

**When** Phase 6 миграция/proto-major

**Then** DROP `access_binding_targets`/`access_binding_selector`/legacy-колонок (subject_type/subject_id/resource_*/scope/target/target_ref); retire target-мутатор-RPC; rename `ListByResource→ListByScope`
**And** `organization_id=9` остаётся reserved tombstone (НЕ удаляется)
**And** `buf breaking` разрешён ТОЛЬКО здесь (документированный major bump)

### DoD под-фазы F
- [ ] `kacho-iam`: backfill-миграция (≥0024) `rules` из `permissions` (anchor/names; matchLabels не recoverable); inert-guard для pre-flag γ-биндингов (no double-emit тест); re-seed system-ролей через `rules[]` (детерминированные id); `access_binding_emitted_tuples` миграция (если ledger-форма меняется — переиспользуем #178).
- [ ] `kacho-ui`: рендер из `rules[]` (arm выводится из формы правила); per-rule editor; verb-`*` allowed для custom (R-3); прекратить `binding.target`/`selector`.
- [ ] `kacho-deploy`: mirror-sync gate перед flip `KACHO_IAM_ROLE_RULES_SELECTION` (default off → flip после verify); FGA-модель re-bootstrap (`scope_grant`); tuple-снапшот pre/post; rollback-окно.
- [ ] `kacho-workspace`: docs-site Role-глава (`kacho-docs-writer`); vault-trail полный.
- [ ] **Phase 6 (отдельный major)**: legacy DROP + retire + rename; `buf breaking` разрешён только здесь.
- [ ] **RED→GREEN**: integration (backfill F-01, inert F-20, legacy-мутаторы F-21) + newman + buf-breaking CI (F-09) + UI-тесты (F-22) в соответствующих PR.
- [ ] db-architect-reviewer (backfill/inert-миграция), proto-api-reviewer (buf clean), qa-test-engineer (regression).
- [ ] заказчик — финальный smoke/e2e (`make e2e-test` / `grpcurl`): создать роль с mixed-арм rules, bind, проверить per-verb Check, per-object List, ExpandAccess.

---

## 4. Кросс-репо порядок и реюз (сводка)

| Под-фаза | proto | corelib | iam | gateway | ui | deploy | docs |
|---|---|---|---|---|---|---|---|
| A | `Rule`/`Role.rules` (`Get`→`Role`) | — | compiler+repo+handler | `Role` camelCase (`Get`→`Role`) | — | — | role-глава |
| B | `fga_model.fga` scope_grant + per-verb | — | emit arm-tag + revoke-ledger | — | — | FGA re-bootstrap | edges |
| C | — | — | reconciler rekey + matchLabels + condition + fan-out | — | — | mirror-sync gate | resources |
| D | — | listauthz per-object (если общий) | InternalIAM ListObjects | List-filter wiring | — | audit-list-filter per-object | edges |
| E | `subjects=19`/`ExpandAccess`/`ListByRole` | — | subjects+expand+listbyrole | public mux | multi-subject форма | — | rpc |
| F | (Phase 6 major) | — | backfill+inert+re-seed | (Phase 6 rename) | rules-рендер | flag-flip + FGA | docs-site |

**Реюз (НЕ переписывать):** `MatchSelector`/`MatchIAMDirect`/`IsContainedIn`/`membershipTuples`, `fga_outbox`+drainer, `resource_reconcile_outbox`+sweep, `resource_mirror`, `access_binding_emitted_tuples` (ledger #178), `requireGrantAuthority`. **Новое:** Go-компайлер `rules→permissions`, `scope_grant` FGA-примитив, per-verb FGA-relations, arm-tag emit-вход, `rule_fp`-rekey membership, `role_rule_selectors`, fan-out-reconcile, ListObjects per-object List, `ExpandAccess`/`ListByRole`.

---

## 5. Зафиксированные решения (closed) — резолюции заказчика O-1..O-8

Дизайн §9 закрыл Q#1..Q#6 (см. §0.3). Дополнительные дыры/неоднозначности, найденные автором acceptance вне §9, **закрыты заказчиком** и абсорбированы в нормативные секции контракта (§2.2/§2.4/§2.5, A-04/A-10/A-16, B-12, C-21, E-34, DoD под-фаз A/B/C/D/E). Ниже — зафиксированные решения (НЕ открытые вопросы, не блокеры APPROVE):

- **O-1 (aggregationRule, §9 Q#1) — РЕШЕНО.** Aggregation НЕ в этой фазе. Зарезервировать **только proto-комментарием** (БЕЗ резерва tag — append-only позже при необходимости). Сценариев не порождает (кроме «поле отсутствует/не принимается»). Абсорбировано: §0.3 (Q#1), R-11-комментарий.
- **O-2 (per-verb vs §8 verb-granularity) — РЕШЕНО.** Финал — **per-verb enforcement (R-2)** + **verb-`*` allowed (R-3)**; дизайн §8 обновлён под per-verb, **конфликта нет** (прежняя §8-строка «verb-granularity advisory / verb-`*` запрещён» устарела и заменена). Implementer берёт per-verb как нормативное. Абсорбировано: §0.3 (Q#6), §2.2, B-* (per-verb relations).
- **O-3 (verb-`*` FGA-разворот) — РЕШЕНО.** `verbs:["*"]` → разворачивается в **полный закрытый per-verb набор типа** (арм наследует ВСЕ конкретные per-verb relations типа из `fga_model.fga`), bounded — не открытый `*`-relation. Permissions-проекция `compute.instance.*.*` (A-04) остаётся ок (projection держит `*`-сегмент). Абсорбировано: §2.2, B-12, DoD под-фазы B (`fga_model.fga`).
- **O-4 (matchLabels feed для iam-типов) — РЕШЕНО.** ARM_LABELS-selectable iam-direct типы = **ровно `iam.project`, `iam.account`** (epic-107 Q4); **`iam.role`/`iam.serviceAccount`/`iam.group` — НЕ selectable** через `matchLabels` (feed-gate reject). Абсорбировано: §2.4, A-10 (positive `iam.project` + negative `iam.role`).
- **O-5 (ListObjects performance, §11/D) — РЕШЕНО.** Нагрузочная валидация FGA `ListObjects` (`load-testing-coach` gate) **обязательна перед prod-flip под-фазы D**. Абсорбировано: DoD под-фазы D (load-testing-coach gate перед prod-flip).
- **O-6 (read-projection new↔legacy) — РЕШЕНО.** `Get`/`List`/`ListByRole` заполняют **ОБА** представления — new (`subjects`/`scopeRef`) И legacy (`subjectType`/`subjectId`/`resourceType`/`resourceId`/`scope`) — в окне до Phase 6 (старые клиенты не ломаются); legacy-single binding ⇒ `subjects[]` из одного элемента (обратная проекция). Абсорбировано: **E-34**, DoD под-фазы E.
- **O-7 (Role.Delete пока несёт binding-строку) — РЕШЕНО + уточнено (ревью-round 3).** FK `access_bindings_role_fk` RESTRICT → SQLSTATE `23503`→`FAILED_PRECONDITION "role is in use by access bindings"` в `mapRepoErr` (без leak pgx/SQL). Текст **без «active»**: FK блокирует на любой binding-строке (ACTIVE или оставшейся REVOKED), а не только active. `AccessBindingService.Delete` — **HARD delete** (строка purge'ится, см. `abWriter.Delete`), НЕ soft-revoke (soft-revoke `TransitionStatus` — отдельный lifecycle-путь expiry/reconcile); precondition снимает именно purge биндинга. Абсорбировано: **A-16** (+ concurrent delete∥grant race, data-integrity §5), §2.5, DoD под-фазы A.
- **O-8 (fan-out limit) — РЕШЕНО.** Контрактная константа **limit=10000** active bindings/role; превышение → `FAILED_PRECONDITION` (трассируется в текст ошибки и тест). Абсорбировано: §2.5, C-21, DoD под-фазы C.

> Все O-1..O-8 закрыты заказчиком и перенесены в нормативные секции — открытых блокеров APPROVE нет. Изменение любого из этих решений — только через правку дизайна + этого acceptance, не в реализации (§coordination).

---

## 6. Соответствие cross-domain графу (`polyrepo.md` / `data-integrity.md`)

- **Нет нового iam→consumer ребра** (цикл запрещён): selection id'ы (`resourceNames`/matchLabels-объекты) — opaque soft-ref; IAM не звонит vpc/compute/nlb. Per-object List у consumer'ов фильтруется через **существующее** ребро `vpc/compute/nlb → kacho-iam` (`InternalIAMService` ListObjects-аналог), fail-closed (D-47).
- `scope_grant`/per-verb — внутри FGA-модели (`kacho-proto/fga_model.fga`), эмиссия из `kacho-iam`; не новое service→service ребро.
- within-`kacho_iam` инварианты на DB-уровне (ban #10): `roles.rules` shape CHECK, cap-raise CHECK, FK RESTRICT (binding→role, role→account/project), partial UNIQUE (role name per scope, strict-create binding), CASCADE same-DB (`access_binding_*` child), xmin OCC (Role.Update). list⇔enforce parity (D) — use-case + FGA, не DB CHECK (JOIN-предикат).
- Все мутации → `Operation` (ban #9); все read'ы sync (ban Watch-нет).
```
