# RBAC rules-model 2026 — под-фаза H (`Rule.module` scalar) — Acceptance (Given-When-Then)

> **Статус:** ✅ **APPROVED** (2026-06-22, gate ban #1). Это **самостоятельная под-фаза H** эпика «RBAC rules-model 2026» (A–F уже APPROVED + LIVE на fe3455). Покрывает ТОЛЬКО переход `Rule.modules` (repeated) → `Rule.module` (scalar) — не переоткрывает A–F.
> **Дата:** 2026-06-22
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — раунд 1 ❌ (блокеры 1–5 + важное 6–10) → раунд 2 ❌ (один блокер: статистика 0031) → **раунд 3 ✅**: единственный остаток — метаданные миграции 0031 — исправлены на verified ground-truth (`grep`-подтверждено: **64 `UPDATE` / 77 rule-элементов / wildcard 5 · iam 26 · vpc 25 · compute 13 · loadbalancer 8**, токен `loadbalancer`); все содержательные пункты (B1–B5 + important 7–10) verified-correct в раунде 2. Стат-фикс детерминирован и сверен с источником — APPROVED.
> **Эпик/тикет:** KAC-`<N>` (Subtask эпика «RBAC rules-model 2026» `[EPIC]`; номер проставляется до старта `superpowers:writing-plans`). Затронутые репо: `kacho-proto` / `kacho-iam` / `kacho-api-gateway` / `kacho-ui` / `kacho-deploy` / `kacho-workspace`(docs).
> **РЕШЕНИЕ ВЛАДЕЛЬЦА (2026-06-22) — breaking refinement core Rule-модели:** `Rule.modules` (repeated string, ровно один модуль на правило в 100% live-данных) → **`Rule.module` (single string)** — **ровно ОДИН модуль на правило**. WHY: декартово `modules × resources` позволяет правилу охватывать несколько модулей и порождать невалидные `(module,resource)`-пары (компилятор fail-closed-SKIP-ит их в `validateFeedGate`/`CompileRules`) — это messy и error-prone. Один модуль на правило делает `resources` чисто отображаемыми на этот модуль. Роль, охватывающая несколько модулей, использует **несколько правил** (по одному на модуль). Это **намеренное breaking-изменение proto** — обрабатывается reserved-tombstone дисциплиной (тот же приём, что clean-cut F в **PR kacho-proto#77**), документированный major bump, НЕ добавляется в buf `except`.
> **KEY FACT (verified live, fe3455):** из 65 ролей / 64 с rules — **ноль multi-module-правил**: каждое существующее правило уже несёт single-element `modules`-массив (`modules:["iam"]`, `modules:["vpc"]`, `modules:["*"]`, `modules:["compute"]`, `modules:["loadbalancer"]` …; см. `0031_reseed_system_roles_rules.sql` — там **64 `UPDATE`** по `rules`-колонке (= 64 роли с rules), суммарно **77 rule-элементов** с `modules`-ключом, распределение по модулям: **wildcard 5 · iam 26 · vpc 25 · compute 13 · loadbalancer 8** (= 77; токен — `loadbalancer`, НЕ `nlb`); комментарий «58 system roles» в 0031 устарел — фактический migration-time count = **64 роли с rules**). Поэтому data-миграция фактически = `modules:[x]` → `module:x` (инвариант **N=1** на live). **Defensive split** для теоретического multi-module-случая всё равно специфицируется (N модулей → N правил), но на live-данных он **не срабатывает**. Low-risk.
> **Источник истины (ground-truth, читан построчно):**
> - `kacho-proto/proto/kacho/cloud/iam/v1/role.proto` — `message Rule`, `repeated string modules = 1 [(kacho.cloud.size)="1-16", (length)="1-64"]` (tags 1–5 заняты: modules/resources/verbs/resource_names/match_labels). `message Role` несёт `repeated Rule rules = 11` и **НЕ имеет `reserved`** (только `[deprecated=true]` на `permissions`=5 / `organization_id`=9 — это иной механизм, не tombstone). `role_service.proto` — `Create/Update` несут `repeated Rule rules`.
> - `kacho-proto/proto/kacho/cloud/iam/v1/access_binding.proto` — **реальный `reserved`-tombstone-прецедент** (sub-phase F / PR #77): `message AccessBinding` несёт `reserved 16, 18;` + `reserved "target", "target_ref", "selector";` (hard-removed object-selection machinery). Именно этот механизм (`reserved <tag>; reserved "<name>";`) использует H — **НЕ** `[deprecated=true]`.
> - `kacho-proto/buf.yaml` — `breaking.use: [FILE]`, `breaking.except: [ENUM_VALUE_NO_DELETE]`. Намеренный breaking F/G обрабатывается **НЕ** через расширение `except`, а через CI-step `buf breaking` `continue-on-error: true` (одноразовый major-bump; после merge baseline сдвигается → снова green) + позитивный enforcement reserved-tag/name через `scripts/tombstone_enforce.sh` (реюз reserved → `buf lint` non-zero exit). H следует тому же posture.
> - `kacho-iam/internal/domain/rule.go` — `Rule.Modules []string`; `Validate(systemCtx)` **аккумулирует** ошибки через `multierr.Append` **без early-return** (строки 84–148); `validateRuleList` грамматику токена проверяет `ruleModuleRe = ^[a-z][a-z0-9-]*$` (строка 54), wildcard system-only append на 181–184, invalid-token на 188–189 (`Illegal argument %s (invalid token %q)`); wildcard+selector на 137–140; `hasAnyWildcard`, `validateFeedGate` (цикл `for _, m := range r.Modules`), `CompileRules` декартово `modules×resources×verbs` (внешний цикл `for _, m := range r.Modules`). **В domain НЕТ closed-set-константы модулей** — только грамматика-regex.
> - `kacho-iam/internal/authzmap/fga_types.go` — `var objectTypes map[string]string` (строки 187–220): **закрытая** таблица `"<module>.<resource>" → fga_object_type`. Module-префиксы её ключей = живой closed-set модулей: **`iam` / `vpc` / `compute` / `loadbalancer`** (НЕТ `geo` — Geography вынесена в свой сервис и в objectTypes отсутствует; `nlb` как токен НЕ присутствует — модуль называется `loadbalancer`). `Catalog()` — единственный экспортируемый источник grantable-таксономии.
> - `rule_verbs.go`, `feed_registry.go` (`IsLabelSelectableType`), `rule_fingerprint.go` (`Rules.LabelSelectors`), `access_binding/scope_grant_tuples.go` (emit, `for _, m := range r.Modules`), `repo/kacho/pg/role_repo.go` (`ruleJSON{ Modules []string json:"modules" }`).
> - migration `0025_role_rules_and_cap_raise.sql` — `iam_rules_valid` это **PL/pgSQL FUNCTION** (`CREATE OR REPLACE FUNCTION kacho_iam.iam_rules_valid(rules jsonb)`, строки 30–83, обёрнут в `-- +goose StatementBegin/End`), валидирует `modules`/`resources`/`verbs` как non-empty string-массивы 1..16 (строка 49). **CHECK-constraint называется `roles_rules_valid`** (`ADD CONSTRAINT roles_rules_valid CHECK (kacho_iam.iam_rules_valid(rules))`, строка 90) — НЕ inline, НЕ названа `iam_rules_valid`.
> - `0031_reseed_system_roles_rules.sql` — system-role re-seed: **64** `UPDATE … SET rules = '[{"modules":["x"], …}]'` (array-`modules`-форма; 77 rule-элементов: wildcard 5 · iam 26 · vpc 25 · compute 13 · loadbalancer 8).
> - **Последняя применённая миграция iam = `0032`** → новая миграция этой под-фазы = **`0033`** (ban #5 — не редактировать применённую).
> **Образцы формата:** `rbac-rules-model-2026-acceptance.md` (нумерация под-фаз, §-структура, таблица стабильных текстов, DoD-чеклист, traceability); reserved-tombstone — `access_binding.proto` (sub-phase F).

---

## Обзор

Уточнение ядра модели RBAC: правило (`Rule`) перестаёт быть декартовым произведением **множества** модулей на ресурсы и становится грантом над **ровно одним модулем**. Поле `Rule.modules` (`repeated string`) заменяется на `Rule.module` (`string`). Семантика `resources × verbs` внутри правила сохраняется без изменений; меняется только то, что верхний контур правила привязан к одному модулю. Роль, покрывающая несколько модулей, выражается несколькими правилами (по одному на модуль) — что already-true для 100% live-ролей. Документ описывает **только наблюдаемое внешнее поведение API/DB-CHECK/UI** (gRPC-коды, REST-формы, форма JSONB, экраны), не реализацию. Сценарии трассируются в имена integration/newman/UI/buf-тестов через ID `H-NN`.

> **Scope-граница (явно).** Эта под-фаза НЕ трогает: FGA-эмиссию `scope_grant` (per-`(module,resource)` логика остаётся, просто `module` теперь скаляр), per-verb relations, per-object filtered List, feed-registry состав (`iam.project`/`iam.account` остаются selectable), wildcard-политику (`module:"*"` — system-only, сохраняется), cap-raise (compiled ≤1024). Это batches с in-flight `labelSelectable` labels-arm gating (под-фаза по UI labels), но **этот док ограничен только module-scalar** — зависимость отмечена в §UI, поведение labels не переопределяется.

---

## 0. Фиксированные дизайн-решения (НЕ переоткрывать; ревьюер подтверждает scope)

| ID | Решение (владелец 2026-06-22) | Сценарии |
|---|---|---|
| **H-R1** | `Rule.modules` (repeated) → **`Rule.module` (single string)**. Ровно один модуль на правило. multi-module-правило **более не представимо** (ни в proto, ни в domain, ни в JSONB). | H-01..H-05 |
| **H-R2** | **proto-breaking через reserved-tombstone** (тот же механизм, что F в **PR kacho-proto#77** на `AccessBinding`: `reserved 16, 18; reserved "target","target_ref","selector";`): в `message Rule` tag `1` + имя `modules` → `reserved 1; reserved "modules";` (НЕ переиспользуются). `module` получает **новый незанятый tag** (tags 1–5 в `Rule` заняты → **tag 6**, см. Q3). **`reserved` ≠ `[deprecated=true]`**: H использует `reserved` (hard tombstone, как F), а НЕ `[deprecated]` (мягкий маркер, как `Role.permissions`/`organization_id`). Намеренный major bump, документирован; **НЕ** добавляется в `buf.yaml` `breaking.except`. Одноразовый breaking абсорбируется CI-step `buf breaking` с `continue-on-error: true` (после merge baseline сдвигается → снова green); реюз reserved-tag/name позитивно ловится `scripts/tombstone_enforce.sh` (→ `buf lint` non-zero). `buf lint`/`buf generate` зелёные. | H-01 |
| **H-R3** | `module` **обязателен** (non-empty) + грамматика токена (`ruleModuleRe = ^[a-z][a-z0-9-]*$`) + **членство в закрытом наборе модулей** (см. §2.3). **OWNER-OF-SET (архитектурное решение, разрешает Q1 round-1):** домен становится **владельцем** module-set — новый domain-helper `domain.IsKnownModule(m) bool` (закрытый литеральный набор в `domain/`, чистый Go: stdlib+multierr, без import authzmap — clean-arch). `authzmap` **консумит** его (или удерживается lockstep через drift-test `authzmap`↔`domain`), так что `Rule.Validate` reject'ит неизвестный module на request-path (`INVALID_ARGUMENT`) **без** того чтобы domain импортировал authzmap. Источник истины набора при review/drift — module-префиксы `authzmap.objectTypes` keyset (НЕ «domain-constants» абстрактно). Пустой `module` → `INVALID_ARGUMENT`; грамматика-невалидный токен → `INVALID_ARGUMENT (invalid token)`; грамматика-валидный но вне набора → `INVALID_ARGUMENT (unknown module)`. | H-02, H-03 |
| **H-R4** | `module:"*"`-политика **сохраняется system-only** (custom-роль с `module:"*"` → `INVALID_ARGUMENT`; system seed — принимается). `resources:["*"]` тоже остаётся system-only (без изменений). **`Validate` аккумулирует ошибки** (multierr, no early-return) — `module:"*"`+selector в custom-роли возвращает ОБА текста (system-only И wildcard-cannot-combine), см. H-04b. | H-04 |
| **H-R5** | `CompileRules` + `Rules.LabelSelectors` + `scope_grant`-emission **потребляют скаляр `module`** (внешний цикл `for _, m := range r.Modules` сворачивается в один `module`) — декартова раскрутка по модулям исчезает; `resources × verbs` (и `× resourceNames`) сохраняется. Compiled-permissions форма (`m.r.rn.v`) не меняется. **Старый `Rule.Modules []string`-codepath УДАЛЯЕТСЯ** post-migration (поле `Modules` исчезает из domain), поэтому compile-parity (H-05) сверяется с **golden-fixture/snapshot** pre-migration compiled-set, а НЕ с удалённым codepath. | H-05 |
| **H-R6** | **migration 0033 (kacho-iam)** переписывает `roles.rules` JSONB для ВСЕХ ролей (system + custom): каждое правило `modules:[m1,m2,…,mN]` → **N правил** с тем же `resources`/`verbs`/`resource_names`/`match_labels` и скалярным `module:mK`, ключ `modules` дропается. На live-данных N=1 всегда (verified). Idempotent (re-run safe), reversible Down (closed-default `module:m → modules:[m]` per-rule, Q2). Применяется на fresh deploy ПОСЛЕ 0031 (трансформирует array-выход 0031) и на live fe3455 (переписывает 64 роли с rules). **Mechanics:** 0033 `CREATE OR REPLACE FUNCTION kacho_iam.iam_rules_valid` (scalar-`module`-логика, обёрнут `-- +goose StatementBegin/End`); **порядок Up: сперва row-rewrite `roles.rules`, ПОТОМ replace функции (которая дальше энфорсит через существующий CHECK-constraint `roles_rules_valid`)** — иначе CHECK заблокирует rewrite-середину. Всё в одной tx. | H-06, H-07, H-08 |
| **H-R7** | handler/DTO маппят `module` (scalar). permission-catalog + compiler-форма не затронуты `labelSelectable` (отдельный track). **System-role re-seed НЕ нужен** — 0033 переписывает rules in-place (как 0031 делал UPDATE, не INSERT). | H-05, H-08 |
| **H-R8** | **UI (kacho-ui):** RulesEditor `module` = single-select (string); `resources` scoped к выбранному модулю; role-detail рендерит `module`; «add rule» для другого модуля = отдельное правило. Зависимость на in-flight labels-arm gating отмечена, но не переопределяется здесь. | H-09 |
| **H-R9** | **gateway (kacho-api-gateway):** rebuild против нового proto (role_service-stubs маршалят `module` camelCase в REST JSON). Поведение RPC не меняется кроме формы поля. | H-01, §smoke |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — read **sync** (`Role.Get`/`List`), мутации async `Operation` (`Role.Create/Update`); Watch не существует (polling `OperationService.Get`) | H-01 (Create→Operation→Get), H-04/H-05 |
| `api-conventions.md` — malformed id → sync `INVALID_ARGUMENT` первым стейтментом; валидация формы правила — sync до Operation | H-02/H-03/H-04 (sync reject) |
| `api-conventions.md` — REST `/iam/v1/roles`; JSON camelCase — поле теперь `module` (string), не `modules` (array); `rules[]`, `resources`, `verbs`, `resourceNames`, `matchLabels` без изменений | H-01, H-09, §smoke |
| `api-conventions.md` — стабильные тексты ошибок — часть контракта; новые тексты для `module` (§2.4) согласованы по тону с существующими `Illegal argument <field> …` | §2.4 |
| `data-integrity.md` §within-service — DB CHECK-constraint **`roles_rules_valid`** (вызывает PL/pgSQL функцию **`iam_rules_valid(rules)`**) энфорсит shape-парити (ban #10): прямой INSERT мимо use-case с array-`modules` или без `module` → reject на DB-уровне. 0033 делает `CREATE OR REPLACE FUNCTION iam_rules_valid` (constraint `roles_rules_valid` остаётся, переисполняет обновлённую функцию). | H-08 |
| `00-kacho-core.md` ban #1 (APPROVED перед кодом), #5 (новая forward-миграция `0033`, не править применённую), #9 (мутации→Operation), #10 (within-DB CHECK), #12 (TDD RED→GREEN integration+newman в том же PR), #2 (без чужих облаков) | весь документ; §DoD |
| `polyrepo.md` §порядок merge | §cross-repo: proto → iam → api-gateway → ui → deploy → workspace(docs) |
| `architecture.md` — `Rule` self-validating в `domain/` (чистый Go); компилятор/эмиссия в use-case-слое; handler тонкий | H-02..H-05, §DoD |

---

## 2. Нормативные определения (источник истины для сценариев)

### 2.1. Форма правила ДО / ПОСЛЕ

| | ДО (live) | ПОСЛЕ (под-фаза H) |
|---|---|---|
| proto `message Rule` | `repeated string modules = 1 [(kacho.cloud.size)="1-16", (length)="1-64"]` | `reserved 1; reserved "modules";` + `string module = 6 [(length)="1-64"]` |
| domain `Rule` | `Modules []string` | `Module string` |
| JSONB (`roles.rules` элемент) | `{"modules":["iam"],"resources":[…],"verbs":[…],…}` | `{"module":"iam","resources":[…],"verbs":[…],…}` |
| REST JSON | `{"modules":["iam"], …}` | `{"module":"iam", …}` |
| семантика гранта | `modules × resources × verbs` (декартово; multi-module возможно) | `{module} × resources × verbs` (ровно 1 модуль; resources чисто отображаются на module) |
| multi-module роль | одно правило с `modules:[a,b]` | несколько правил, по одному на модуль |

`resources`/`verbs`/`resourceNames`/`matchLabels` — **без изменений** (cardinality, XOR-селектор, wildcard-политика resources/verbs, feed-gate). Меняется только верхний контур: модуль становится скаляром.

> **Proto-опции (для `proto-api-reviewer` — не воспринимать как регрессию):** скалярный `string module = 6` сохраняет `(kacho.cloud.length) = "1-64"` (per-string длина), но **закономерно теряет** `(kacho.cloud.size) = "1-16"` — `size` это cardinality repeated-поля, у scalar-поля её нет. Это намеренное следствие repeated→scalar, не потеря валидации.

### 2.2. Wildcard-политика для `module` (сохранена)

- `module:"*"` — **только system-роли** (seed); в custom-роли → `INVALID_ARGUMENT` (тот же системный-only-контракт, что был у `modules:["*"]`).
- `module:"*"` **+ matchLabels или + resourceNames** → `INVALID_ARGUMENT` (wildcard не комбинируется с селектором — без изменений).
- `resources:["*"]` остаётся system-only (этот док его не трогает).

### 2.3. Известный module-токен (H-R3) — закрытый набор

`module` обязан быть: (a) непустым; (b) валидным по грамматике module-токена (текущий `ruleModuleRe` = `^[a-z][a-z0-9-]*$`) **или** `"*"` (system-only); (c) **членом закрытого набора модулей платформы**.

**Закрытый набор (ровно эти четыре, ничего больше):**

```
iam   vpc   compute   loadbalancer
```

**Источник истины набора** — module-префиксы keyset `authzmap.objectTypes` (`internal/authzmap/fga_types.go`, `var objectTypes`): `iam.*`, `vpc.*`, `compute.*`, `loadbalancer.*`. Заметь: **`geo` НЕ входит** (Geography вынесена в свой сервис `kacho-geo` и в `objectTypes` отсутствует); **`nlb` как токен НЕ входит** — модуль называется `loadbalancer` (`loadbalancer.networkLoadBalancers` / `targetGroups` / `listeners`).

**OWNER-OF-SET (архитектурное решение, разрешает round-1 Q1 «defaultable-wrong»):** сегодня `domain.Rule.Validate` проверяет **только грамматику** (`ruleModuleRe`) — закрытой module-set-константы в domain **нет**. H делает **домен владельцем набора**: новый чистый-Go helper `domain.IsKnownModule(m string) bool` (литеральный закрытый набор в `domain/`, импортирует только stdlib+multierr — clean-arch, БЕЗ import authzmap). `authzmap` **консумит** `domain.IsKnownModule` (либо удерживается с ним lockstep через drift-тест `authzmap`↔`domain`, аналогично существующему `fga_model_drift_test.go`), так что единственный источник истины набора — domain, а `Rule.Validate` reject'ит неизвестный module прямо на request-path. Семантика: один модуль теперь несёт ответственность за валидность всех своих `(module,resource)`-пар, поэтому module обязан быть реальным членом набора; H-03 («banana») — request-path reject `INVALID_ARGUMENT`.

### 2.4. Стабильные тексты ошибок (часть контракта — `api-conventions.md`)

**Два РАЗДЕЛЬНЫХ module-ошибочных текста (НЕ схлопывать — для implementer):**
- **(a) грамматика-невалидный токен** (`module` не матчит `ruleModuleRe`, напр. `"VPC"`, `"a b"`): текст переименовывается из текущего per-array `Illegal argument modules (invalid token %q)` (rule.go:188) в **scalar `Illegal argument module (invalid token %q)`** (`modules`→`module`).
- **(b) грамматика-валидный, но вне закрытого набора** (`module:"banana"` — H-03): новый текст **`Illegal argument module (unknown module '<m>')`**.

| Ситуация | Код | Текст |
|---|---|---|
| `module` пустой/отсутствует | `INVALID_ARGUMENT` | `Illegal argument module (must be non-empty)` |
| `module` — грамматика-невалидный токен (a) | `INVALID_ARGUMENT` | `Illegal argument module (invalid token %q)` |
| `module` — грамматика-валидный, но не в закрытом наборе (b) | `INVALID_ARGUMENT` | `Illegal argument module (unknown module '<m>')` |
| `module:"*"` в custom-роли | `INVALID_ARGUMENT` | `Illegal argument module (wildcard '*' is system-only)` |
| `module:"*"` + selector | `INVALID_ARGUMENT` | `Illegal argument: wildcard cannot combine with resourceNames or matchLabels` |
| type не selectable (feed-gate, неизменно) | `INVALID_ARGUMENT` | `type <module>.<resource> is not selectable (no resource feed)` |

> **Накопление ошибок (ground-truth rule.go:84–148):** `Validate` аккумулирует все нарушения через `multierr.Append` **без early-return**. Одно правило, нарушающее несколько инвариантов, возвращает **все** тексты сразу (через REST/gRPC — конкатенированными в `message`/`details`). Negative-сценарии H-02/H-03/H-04b формулируют `Then` соответственно: H-02/H-03 — единичное нарушение → один текст; H-04b — два нарушения → ОБА текста. См. H-02/H-04b.

Все прочие тексты (`Illegal argument rules (must be non-empty)`, `resourceNames and matchLabels are mutually exclusive`, cap-1024 и т.д.) — **без изменений** из APPROVED A-секции (`rbac-rules-model-2026-acceptance.md` §2.5).

---

## ПОД-ФАЗА H — `Rule.modules` (repeated) → `Rule.module` (scalar)

**Deliverable:** proto-breaking (`Rule.modules`→`Rule.module = 6` через reserved-tombstone, как F #77 на AccessBinding), domain (`Rule.Module string`, новый `domain.IsKnownModule`, `Validate`/`CompileRules`/`LabelSelectors`/`scope_grant`-emit на скаляр), migration 0033 (`CREATE OR REPLACE FUNCTION iam_rules_valid` на scalar-форму через constraint `roles_rules_valid`, array→scalar rewrite + defensive split, idempotent, reversible), iam handler/DTO маппинг, gateway rebuild, UI single-select module.
**Порядок:** `kacho-proto` → `kacho-iam` → `kacho-api-gateway` → `kacho-ui` → `kacho-deploy` → `kacho-workspace`(docs).

## Сценарий H-01: Happy — Create Role со scalar `module` → Operation → Get отдаёт `module`

**ID:** H-01

**Given** аутентифицированный caller с `iam.roles.create` (editor @ account `acc-A`)
**And** proto перегенерён: `Rule` несёт `module` (string), `modules` зарезервирован

**When** клиент вызывает `RoleService.Create` (`POST /iam/v1/roles`) с payload:
  - `accountId` = `acc-A`
  - `name` = `network-ops`
  - `rules` =
    - `{module:"compute", resources:["image"], verbs:["get"]}` (ARM_ANCHOR)
    - `{module:"vpc", resources:["subnet"], verbs:["create"], matchLabels:{env:"prod"}}` (ARM_LABELS)
    - `{module:"vpc", resources:["address"], verbs:["get","update"], resourceNames:["addr5k","addr9m"]}` (ARM_NAMES)

**Then** RPC возвращает `Operation` (async, ban #9); `OperationService.Get(id)` поллится до `done=true && !error`
**And** `RoleService.Get` (`GET /iam/v1/roles/{id}`) возвращает `Role` где `rules[i].module` — скаляр (`"compute"`, `"vpc"`, `"vpc"`), поля `resources`/`verbs`/`matchLabels`/`resourceNames` сохранены
**And** в REST JSON каждое правило несёт `"module":"<x>"` (camelCase string), **нет** ключа `"modules"`
**And** `permissions` в ответе пустое (internal compiled, как в A — не затронуто)

## Сценарий H-02: `module` пустой/отсутствует → INVALID_ARGUMENT

**ID:** H-02  ·  *(H-R3)*

**Given** caller с `iam.roles.create`

**When** `RoleService.Create` с правилом (a) `{module:"", resources:["subnet"], verbs:["get"]}`; (b) правило без поля `module` вовсе

**Then** оба → sync `INVALID_ARGUMENT` (sync, до Operation), `message` содержит текст **`Illegal argument module (must be non-empty)`**
**And** в этом единичном нарушении это **единственный** module-текст: правило корректно во всём остальном (`resources`/`verbs` валидны, селектора нет), поэтому `multierr` накапливает ровно одну ошибку — assertion на единичный текст точна
**And** ни одна роль не создана

## Сценарий H-03: `module` — неизвестный токен → request-path reject

**ID:** H-03  ·  *(H-R3 closed-set / `domain.IsKnownModule`)*

**Given** caller с `iam.roles.create`

**When** `RoleService.Create` с правилом `{module:"banana", resources:["subnet"], verbs:["get"]}` (грамматика-валидна `^[a-z][a-z0-9-]*$`, но `banana` не в закрытом наборе `iam`/`vpc`/`compute`/`loadbalancer`)

**Then** sync `INVALID_ARGUMENT`, `message` содержит **`Illegal argument module (unknown module 'banana')`** (reject на request-path через `domain.IsKnownModule`, до Operation — НЕ fail-closed-SKIP в компиляторе)
**And** это единичное нарушение (resources/verbs валидны) → единственный текст; assertion точна
**And** контр-пример (positive): `{module:"vpc", resources:["subnet"], verbs:["get"]}` (член набора) → `Operation` done; `Get` отдаёт `module == "vpc"`

## Сценарий H-04: `module:"*"` — system-only (custom reject, seed принимается); accumulated errors

**ID:** H-04  ·  *(H-R4 / H-R2 wildcard parity / multierr accumulation)*

**Given** caller с `iam.roles.create` (custom-роль, `systemCtx=false`)

**When** (a) custom: `{module:"*", resources:["instance"], verbs:["get"]}`; (b) custom: `{module:"*", resources:["instance"], verbs:["get"], matchLabels:{env:"prod"}}`

**Then** (a) → sync `INVALID_ARGUMENT`, `message` содержит **`Illegal argument module (wildcard '*' is system-only)`** (одно нарушение — wildcard в custom-контексте; resources `"instance"` не wildcard, селектора нет)
**And** (b) → sync `INVALID_ARGUMENT`, `message` содержит **ОБА** текста (ground-truth: `Validate` аккумулирует через `multierr.Append` без early-return — system-only-ошибка append'ится в `validateRuleList` ПЕРВОЙ, wildcard+selector-ошибка — на rule.go:137–140):
  - **`Illegal argument module (wildcard '*' is system-only)`** (custom-роль + `module:"*"`), И
  - **`Illegal argument: wildcard cannot combine with resourceNames or matchLabels`** (`hasAnyWildcard` + matchLabels)
  Assertion проверяет наличие **обоих** подстрок в `message`/`details`, НЕ одного.
**And** (seed-path, не публичный) is_system-роль с `module:"*"` (напр. `admin` = `{module:"*",resources:["*"],verbs:["*"]}`, `systemCtx=true`) принимается при seed/0033-rewrite (детерминированный id) — wildcard БЕЗ селектора, system-context relax'ит system-only

## Сценарий H-05: компиляция/эмиссия потребляют скаляр `module`; parity против golden-fixture

**ID:** H-05  ·  *(H-R5 / H-R7)*

**Given** роль с правилом `{module:"compute", resources:["instance","disk"], verbs:["get","list"]}` (ARM_ANCHOR, один модуль, два ресурса, два verb)

**When** роль скомпилирована (`CompileRules`) и (при binding) FGA-tuples эмитированы (`scope_grant_tuples`)

**Then** compiled-permissions = `compute.instance.*.get`, `compute.instance.*.list`, `compute.disk.*.get`, `compute.disk.*.list` (форма `m.r.*.v` неизменна; `resources × verbs` раскручивается, по модулю — нет)
**And** `Rules.LabelSelectors()` для ARM_LABELS-правила с `module:"vpc"` даёт `ObjectTypes = ["vpc.<resource>", …]` (модуль один — внешний цикл по модулям свёрнут)
**And** compile-parity тест подтверждает: для каждой live-роли compiled-set из scalar-формы **идентичен** ожидаемому compiled-set. **ВАЖНО (H-R5):** старый `Rule.Modules []string`-codepath УДАЛЯЕТСЯ post-migration, поэтому parity сверяется НЕ с живым прежним codepath (его уже нет), а с **golden-fixture/snapshot** — зафиксированным до миграции compiled-set каждой live-роли (генерируется из текущего prod-кода ДО удаления `Modules`, коммитится как testdata, и scalar-вывод сверяется byte-for-byte с ним). На live N=1 это поведенческая эквивалентность

## Сценарий H-06: migration 0033 — array→scalar rewrite (live N=1)

**ID:** H-06  ·  *(H-R6, integration testcontainers)*

**Given** строка `roles.rules` в форме `[{"modules":["iam"],"resources":["account"],"verbs":["*"]}]` (типичный live-выход 0031)

**When** применяется migration `0033` (Up). **Mechanics (ground-truth 0025):** `iam_rules_valid` — PL/pgSQL FUNCTION (обёрнут `-- +goose StatementBegin/End`), CHECK-constraint называется `roles_rules_valid`. 0033 Up в одной tx: **(1)** сперва row-rewrite `roles.rules` (`modules:[m]` → `module:m`); **(2)** ПОТОМ `CREATE OR REPLACE FUNCTION kacho_iam.iam_rules_valid` на scalar-`module`-логику (constraint `roles_rules_valid` остаётся, далее переисполняет обновлённую функцию). Порядок обязателен: обновить функцию ДО rewrite значило бы, что CHECK заблокирует ещё-array-строки в середине rewrite

**Then** `roles.rules` становится `[{"module":"iam","resources":["account"],"verbs":["*"]}]` (ключ `modules` дропнут, добавлен скалярный `module`, прочие ключи без изменений)
**And** обновлённая функция `iam_rules_valid` (через constraint `roles_rules_valid`) принимает результат
**And** integration-тест (testcontainers): на дампе-аналоге fe3455 (64 роли с rules) все строки переписаны, `module` непуст у каждой, `modules`-ключ отсутствует

## Сценарий H-07: migration 0033 — defensive multi-module split + idempotent re-run

**ID:** H-07  ·  *(H-R6, defensive)*

**Given** (синтетическая, не-live) строка `[{"modules":["iam","vpc"],"resources":["account"],"verbs":["get"]}]` (теоретический multi-module)

**When** применяется migration `0033` (Up)

**Then** правило расщепляется в **два** правила с сохранением `resources`/`verbs`/`resource_names`/`match_labels`: `[{"module":"iam","resources":["account"],"verbs":["get"]},{"module":"vpc","resources":["account"],"verbs":["get"]}]`
**And** **idempotent**: повторный прогон 0033 Up на уже-переписанной строке (форма с `module`) — no-op (форма не меняется, ошибки нет)
**And** integration-тест подтверждает split + idempotent re-run

## Сценарий H-08: migration 0033 — функция принимает новую форму, отвергает старую; reversible Down

**ID:** H-08  ·  *(H-R6, within-DB ban #10)*

**Given** применённая migration `0033` (обновлённая FUNCTION `iam_rules_valid`, CHECK-constraint `roles_rules_valid` остаётся прежним по имени)

**When** (a) прямой INSERT строки rules со скалярным `{"module":"iam",…}`; (b) прямой INSERT со старой формой `{"modules":["iam"],…}`; (c) прямой INSERT правила без `module`-ключа; (d) откат `0033` (Down)

**Then** (a) → принимается constraint `roles_rules_valid` (новая `iam_rules_valid` валидирует scalar `module`); (b) → reject (старый array-`modules`-ключ более не валиден); (c) → reject (`module` обязателен)
**And** (d) Down: `CREATE OR REPLACE FUNCTION iam_rules_valid` обратно на array-`modules`-shape **и** row-rewrite `roles.rules` обратно по **closed-default** `module:m` → `modules:[m]` per-rule (Q2: Down детерминированно мапит scalar в single-element-array, **НЕ** пытается синтетически re-merge'ить разные правила в один multi-module — на live N=1 round-trip Up→Down→Up семантически тождественен); порядок Down симметричен Up (rewrite → replace function); после Down старая форма снова валидна, новая — нет
**And** integration-тест (testcontainers): прямой INSERT-парити (a/b/c) + Up→Down→Up round-trip сохраняет семантику live-ролей (round-trip формулируется на N=1-семантике — single-element-array ↔ scalar)

## Сценарий H-09: UI — RulesEditor single-select module; resources scoped; detail рендерит module

**ID:** H-09  ·  *(H-R8, kacho-ui vitest)*

**Given** UI RulesEditor против перегенерённых REST-stubs (поле `module` string)

**When** пользователь добавляет правило в RulesEditor

**Then** `module` — **single-select** (одно значение, не multi-select chips); список `resources` scoped к выбранному модулю (resources другого модуля не предлагаются)
**And** role-detail экран рендерит `module` (скаляр) для каждого правила
**And** «add rule» для другого модуля создаёт **отдельное** правило (не добавляет модуль в существующее)
**And** vitest покрывает: single-select рендер, resources-scoping по выбранному module, detail-рендер scalar module
**And** (зависимость, не переопределяется) labels-arm gating (in-flight `labelSelectable`-под-фаза) сосуществует — module-select не ломает labels-arm UI

### DoD под-фазы H

- [ ] `kacho-proto`: в `message Rule` — `reserved 1; reserved "modules";` + `string module = 6 [(kacho.cloud.length)="1-64"]` (tag 6 — первый свободный после занятых 1–5; `(size)` намеренно НЕ переносится — scalar не repeated, §2.1). Комментарий «один модуль на правило; multi-module роль = несколько правил; tombstone — как AccessBinding F #77». `Create/Update` `rules`-поле без изменений. `buf lint` зелёный (реюз reserved ловится `scripts/tombstone_enforce.sh`); `buf breaking` — **намеренный major bump через CI-step `continue-on-error: true`** (НЕ расширять `buf.yaml breaking.except`; после merge baseline сдвигается → green); `buf generate` зелёный. Gate `proto-api-reviewer`.
- [ ] `kacho-iam`: `domain.Rule.Module string` (вместо `Modules []string` — старое поле УДАЛЯЕТСЯ); новый `domain.IsKnownModule(string) bool` (закрытый набор `iam`/`vpc`/`compute`/`loadbalancer`, чистый Go, owner-of-set); `Validate` (module required + грамматика-токен + `IsKnownModule` + `module:"*"` system-only + wildcard+selector — все через `multierr.Append`, accumulate); `hasAnyWildcard`/`validateFeedGate`/`CompileRules`/`Rules.LabelSelectors`/`scope_grant_tuples` потребляют скаляр (внешний цикл по модулям свёрнут); `authzmap` консумит `domain.IsKnownModule` либо drift-тест `authzmap`↔`domain`; `repo/kacho/pg/role_repo.go` `ruleJSON{ Module string json:"module" }`; handler/DTO (`handler.go`, `toproto/role.go`) маппят `module`. permission-catalog не затронут. **System-role re-seed НЕ нужен** (0033 rewrites in place).
- [ ] `kacho-iam`: forward-миграция **`0033`** — `CREATE OR REPLACE FUNCTION kacho_iam.iam_rules_valid` (scalar-`module`-shape, обёрнут `-- +goose StatementBegin/End`; CHECK-constraint `roles_rules_valid` НЕ пересоздаётся — он переисполняет обновлённую функцию); rewrite `roles.rules` (split N-module→N-rule, scalar `module`, drop `modules`) для ВСЕХ ролей; **порядок Up: rewrite строк → ПОТОМ replace функции** (in-tx, иначе CHECK заблокирует середину rewrite); idempotent Up; reversible Down (closed-default scalar→single-element-array + restore array-функции, симметричный порядок). Применяется ПОСЛЕ 0031 на fresh deploy и на live fe3455.
- [ ] `kacho-api-gateway`: rebuild против нового proto (role_service-stubs маршалят `module` camelCase); поведение RPC не меняется. Internal* не трогаем.
- [ ] `kacho-ui`: RulesEditor `module` single-select + resources-scoping; role-detail scalar `module`; «add rule» per-module.
- [ ] **RED→GREEN** (TDD, каждый слой — ban #12, в том же PR):
  - buf: `buf breaking` ожидаемо сигналит на reserved-rename → обрабатывается `continue-on-error` major-bump (RED→GREEN артефакт в PR; tombstone_enforce зелёный);
  - domain unit (`rule_test.go`/`rule_validate_test.go`): single-module compile (H-05) + grant; `module:""` → INVALID_ARGUMENT single-text (H-02); unknown module → `IsKnownModule`-reject single-text (H-03); `module:"*"` system-only custom-reject (H-04a) + **accumulated BOTH-texts** для `module:"*"`+matchLabels (H-04b); seed-accept (H-04); compile-parity scalar↔**golden-fixture snapshot** (H-05, НЕ против удалённого `Modules`-codepath);
  - migration integration (`*_integration_test.go`, testcontainers Postgres): array→scalar rewrite (H-06), defensive multi-module split (H-07), idempotent re-run (H-07), функция/constraint accepts scalar / rejects array+missing (H-08), Up→Down→Up round-trip на N=1 (H-08);
  - newman (`tests/newman/cases/iam-*.py`): create role с scalar `module` happy (H-01) + ≥1 negative (`module:""` или unknown → 400, H-02/H-03);
  - UI vitest: single-select module, resources scoped, detail рендерит module (H-09).
- [ ] Ревью ролями: `proto-api-reviewer` (tombstone-discipline = `reserved` не `deprecated`, tag 6, `continue-on-error` major-bump, финализирует tag), `db-architect-reviewer` (0033: rewrite-в-tx, порядок rewrite-перед-replace-функции, idempotent, reversible Down closed-default, function `iam_rules_valid` vs constraint `roles_rules_valid`, ban #5/#10), `go-style-reviewer` (domain compiler/emit на скаляр, `IsKnownModule` clean-arch).
- [ ] Финальная верификация: `go test ./... -race` + `golangci-lint run` + `govulncheck` + newman зелёные.
- [ ] vault-trail: `resources/iam-role.md` (Rule-форма: `module` scalar), `rpc/iam-role-service.md` (Create/Update payload `module`), `edges/*` если затронуто (не ожидается), KAC-trail (`KAC/KAC-<N>.md`: затронутые сущности, PR-URL, status).

---

## 3. Coverage matrix

| Класс | Покрыто |
|---|---|
| **Positive (happy)** | H-01 (mixed-arm create со scalar module, Get-roundtrip), H-03 контр-пример (known module), H-05 (compile/emit на скаляр), H-06 (live array→scalar), H-09 (UI single-select) |
| **Negative** | H-02 (`module` пустой/отсутствует, single-text), H-03 (unknown module — `IsKnownModule`-reject, single-text), H-04a (`module:"*"` custom, single-text), H-04b (`module:"*"`+selector → **ОБА** текста, multierr accumulation), H-08b (reject array-`modules`), H-08c (reject missing `module`) |
| **Edge** | H-04 (system-seed `module:"*"` принимается), H-05 (resources×verbs раскрутка без module-раскрутки; LabelSelectors single-module), H-07 (defensive multi-module split — теоретический, не-live) |
| **Migration** | H-06 (array→scalar rewrite-перед-replace-функции, live N=1), H-07 (defensive split + idempotent re-run), H-08 (`iam_rules_valid`/`roles_rules_valid` new/old parity + reversible Down closed-default round-trip); live-safety §5 |

---

## 4. Traceability (H-NN ↔ имена тестов)

| Сценарий | Уровень | Имя теста (предлагаемое; integration-tester финализирует) |
|---|---|---|
| H-01 | newman + domain unit | `iam-role-create-module-scalar-happy` (newman); `TestRule_Module_HappyCompile` (unit) |
| H-02 | domain unit + newman | `TestRule_Validate_ModuleEmpty` ; `iam-role-create-module-empty-neg` |
| H-03 | domain unit + newman | `TestRule_Validate_ModuleUnknown` (IsKnownModule-reject) ; `TestIsKnownModule_ClosedSet` ; `iam-role-create-module-unknown-neg` |
| H-04 | domain unit | `TestRule_Validate_ModuleWildcardSystemOnly` (custom-reject single-text + seed-accept) ; `TestRule_Validate_WildcardPlusSelector_AccumulatesBothErrors` (H-04b multierr) |
| H-05 | domain unit + golden-fixture | `TestCompileRules_SingleModule`, `TestRules_LabelSelectors_SingleModule`, `TestCompileParity_ScalarVsGoldenSnapshot` (сверка с pre-migration testdata-snapshot, НЕ с удалённым `Modules`-codepath) |
| H-06 | integration (testcontainers) | `TestMigration0033_ArrayToScalarRewrite` |
| H-07 | integration | `TestMigration0033_DefensiveSplit`, `TestMigration0033_IdempotentRerun` |
| H-08 | integration | `TestMigration0033_CheckScalarAcceptArrayReject`, `TestMigration0033_UpDownUpRoundTrip` |
| H-09 | UI vitest | `RulesEditor.module-single-select.test.tsx`, `RoleDetail.module-render.test.tsx` |
| buf | CI | `buf breaking` (reserved-tombstone, `continue-on-error` major-bump) + `scripts/tombstone_enforce.sh` зелёный — артефакт в PR |

---

## 5. Migration-safety (live fe3455)

- **Zero multi-module правил на live (verified):** 65 ролей / 64 с rules, каждое правило уже single-element `modules`-массив (`0031_reseed_system_roles_rules.sql` пишет ровно `modules:["x"]`). Комментарий «58 system roles» в 0031 **устарел** — фактически в Up **64 `UPDATE`** по `rules` (= 64 роли с rules), суммарно **77 rule-элементов** с `modules`-ключом, распределение: **wildcard 5 · iam 26 · vpc 25 · compute 13 · loadbalancer 8** (токен `loadbalancer`, НЕ `nlb`); инвариант **N=1** на live. На live data-миграция 0033 = чистый `modules:[x]` → `module:x` rename per-rule. **Defensive N→N split** специфицирован (H-07), но на live не срабатывает.
- **Idempotent (H-07):** 0033 Up на уже-скалярной строке — no-op. Безопасно при re-run (goose-повтор, kind-bootstrap двойной apply).
- **Reversible Down (H-08, closed-default Q2):** Down `CREATE OR REPLACE FUNCTION iam_rules_valid` обратно на array-shape и переписывает `module:m` → `modules:[m]` per-rule (детерминированный single-element-array; **НЕ** пытается синтетически re-merge'ить разные scalar-правила в одно multi-module — обратное слияние неоднозначно by-design). На live (N=1) round-trip Up→Down→Up семантически тождественен. Для синтетического split-кейса Down оставляет N раздельных single-element-array-правил (канонизированная форма) — фиксируется в комментарии миграции; на live это недостижимо (N=1).
- **Порядок на fresh deploy:** 0031 (re-seed system-rules с array-`modules`) → **0033** (трансформирует array-выход 0031 в scalar). 0033 НЕ редактирует 0031 (ban #5). Migration-номер `0033` (последняя применённая = `0032`).
- **Within-DB парити (ban #10):** обновлённая FUNCTION `iam_rules_valid` (через неизменный по имени CHECK-constraint `roles_rules_valid`) — единственный источник истины формы на DB-уровне; прямой INSERT старой array-формы reject'ится (H-08b). Domain-валидация (`Rule.Validate` + `IsKnownModule`) — парная software-проверка на request-path, но DB constraint — backstop.
- **Cross-repo порядок merge:** `kacho-proto` (tombstone + `module`, buf) → `kacho-iam` (domain + 0033 + handler) → `kacho-api-gateway` (rebuild) → `kacho-ui` (single-select) → `kacho-deploy` (re-bootstrap/helm) → `kacho-workspace` (docs). Пока вышестоящее не в `main` — нижестоящий CI пиннит sibling к feature-ветке (`polyrepo.md`).

---

## 6. Открытые вопросы для ревьюера (закрыть до APPROVE)

| # | Вопрос | Резолюция (round-2) |
|---|---|---|
| Q1 | `module` closed-set membership (H-R3/§2.3) — round-1 оставил «defaultable-wrong». | **РЕШЕНО.** Closed-set = ровно `iam`/`vpc`/`compute`/`loadbalancer` (module-префиксы `authzmap.objectTypes` keyset — НЕ geo, НЕ nlb-как-токен). Архитектурно: **домен — владелец набора** (`domain.IsKnownModule`, чистый Go); `authzmap` консумит/lockstep-drift-test; `Rule.Validate` reject'ит unknown на request-path (`INVALID_ARGUMENT`) без import authzmap (clean-arch). H-03 — request-path reject. См. §2.3 / H-R3. |
| Q2 | Down для синтетического multi-module split необратим (canonical merge неоднозначен). | **РЕШЕНО (closed-default).** Down детерминированно мапит `module:m → modules:[m]` per-rule, НЕ пытается re-merge синтетический split. На live N=1 — round-trip тождественен; синтетический split — только тест. H-08 phrased на live N=1-семантике. Документировано §5 + комментарий 0033. |
| Q3 | proto: tag для `module`. | **РЕШЕНО.** `string module = 6` (tags 1–5 в `message Rule` заняты modules/resources/verbs/resource_names/match_labels; на `Role` `reserved` ещё нет — tombstone живёт в `Rule`); `reserved 1; reserved "modules";`. `proto-api-reviewer` финализирует. |
