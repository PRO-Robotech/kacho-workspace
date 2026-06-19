# Epic «Resource-scoped AccessBinding» — Sub-phase δ (clean-form / additive non-breaking) — Acceptance

> **Статус:** ✅ APPROVED
> **Дата:** 2026-06-19
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer` — _round-1 ❌ CHANGES REQUESTED → round-2 ✅ APPROVED (2026-06-19)_. Round-1 правки внесены корректно: condition (Dδ7) выведен из δ-scope везде (карта §0.1 / Dδ1/Dδ5/Dδ7 / §2.1/§2.3 / δ-03/04/06/13 — нет живых condition-веток); §5 Open Questions → Зафиксированные решения (Q-δ-A..Q-δ-E closed); δ-02 subject-ветка убрана. Одобренное ядро scope+target не сломано, внутренних противоречий нет.
> **Эпик/тикет:** epic «Resource-scoped AccessBinding» (вариант C — selector-based grants), **финальная под-фаза δ**. KAC-номер (Subtask δ под `[EPIC]`) проставляется ДО старта `superpowers:writing-plans`. Затронутые репо: `kacho-proto` / `kacho-iam` / `kacho-api-gateway` / `kacho-ui` / `kacho-deploy` / `kacho-workspace`(docs/vault).
> **Источник требований (verbatim intent заказчика):** «α+β+γ дали полную функциональную модель resource-scoped AccessBinding (per-object + label-selector + containment + expiry). Но форма контракта осталась исторически слоёной: scope выражен ДВАЖДЫ (плоские `resource_type`/`resource_id` + дублирующий enum `scope`), target-руки названы внутренними именами (`all_in_scope`/`resources`/`selector`), а condition — это три отдельных поля с "логическим oneof" в комментарии. Целевая чистая 2026-модель — пять измерений: `AccessBinding = { subject{type,id}, roleId, scope{tier,id}, target<all|byName|bySelector>, condition<none|expiry|forward> }`. δ — аддитивная non-breaking чистка формы до этой модели: новые канонические поля ДОБАВЛЯЮТСЯ, старые помечаются `[deprecated]` и продолжают работать через двустороннюю проекцию. НИ ОДИН существующий клиент (UI до δ, API-консьюмеры, pre-δ binding'и в БД) не ломается.»
> **Ground-truth (сверено против proto/vault 2026-06-19):**
> - `kacho-proto/proto/kacho/cloud/iam/v1/access_binding.proto` — `AccessBinding{ id=1, subject_type=2, subject_id=3, role_id=4, resource_type=5, resource_id=6, created_at=7, status=8(Status PENDING/ACTIVE/REVOKED), condition_id=9, expires_at=10, granted_by_user_id=11, revoked_at=12, revoked_by_user_id=13, builtin_condition=14(BuiltinCondition), scope=15(Scope enum CLUSTER/ACCOUNT/PROJECT), target=16(AccessTarget) }`; prefix `acb-`. **Поле 17 свободно.**
> - `AccessTarget` oneof `target { AllInScope all_in_scope = 1; TargetResourceRefList resources = 2; ResourceSelector selector = 3; }` (α). γ уже сделал прецедент **deprecate+new** на `ResourceSelector`: `match_tags=2 [deprecated=true]` + новый `match_labels=3`. `ResourceSelector{ types=1, match_tags=2(deprecated), match_labels=3 }`.
> - **scope сегодня — constrained-redundant:** enum `Scope`(15) **уже** валидируется против `(resource_type, resource_id)` (proto comment §98-110 + domain `Scope.ValidateAgainst` + DB CHECK + BEFORE INSERT trigger `access_bindings_scope_default_trg`, migration 0005): CLUSTER⇒(`cluster`,`cluster_kacho_root`); ACCOUNT⇒(`account`,`acc…`); PROJECT⇒(`project`,`prj…`). Т.е. enum derived/consistent с плоскими полями — **избыточность контролируема**, не два независимых источника истины.
> - **condition сегодня — НЕ proto3 oneof, а «логический oneof» из 3 полей:** `condition_id=9` (FK→`access_binding_conditions(id)`, ABAC overlay, custom-CEL Phase 3), `expires_at=10` (TTL, рабочий через γ eager-revoke), `builtin_condition=14` (`BuiltinCondition` enum, incl `NON_EXPIRED`). Proto comment §70-72 явно фиксирует: **wire-схема НЕ может выразить это как proto3 oneof без breaking field-9 callers** — потому это «at most one of, enforced at service layer». Это исторический долг, который δ адресует.
> - **`access_bindings`-row НЕ имеет version-колонки** — γ `ReplaceTargetSelector` CAS = `xmin::text` (vault §«Selector mutable»). δ форму ресурса меняет на уровне proto/проекции — **новых таблиц не вводит** (это форма контракта над теми же данными).
> - Vault: `resources/iam-access-binding.md`, `resources/iam-access-binding-condition.md`, `rpc/iam-access-binding-service.md`.
> **Образцы формата:** `epic-resource-scoped-access-binding-gamma-acceptance.md` (родительский γ — deprecate+new прецедент D5), `epic-resource-scoped-access-binding-alpha-acceptance.md` (α — target-форма).

---

## Обзор

α+β+γ собрали **функционально полную** модель resource-scoped AccessBinding: per-object таргетинг (`resources[]`), label-selector с динамическим membership (`selector`), containment из mirror и TTL-expiry. Поведение завершено. Осталась **форма** контракта — она исторически слоёная и читается хуже, чем целевая чистая 2026-модель:

```
AccessBinding = { subject{type,id}, roleId, scope{tier,id}, target<all|byName|bySelector>, condition<none|expiry|forward> }
```

Сегодня вместо этого: scope выражен ДВАЖДЫ (плоские `resource_type`/`resource_id` + дублирующий enum `scope`), target-руки названы внутренними именами (`all_in_scope`/`resources`/`selector`), condition — три плоских поля с «логическим oneof» в комментарии (wire-схема его не выражает).

**Под-фаза δ (этот документ) — аддитивная non-breaking чистка формы ДВУХ измерений: `scope{tier,id}` + `target.all/byName/bySelector`.** condition (третье потенциальное измерение чистки) **отложено в ε** — `condition_id` field-9 уже populated, логический oneof не выразим на wire без breaking field-9 callers, `non_expired` уже работает через γ eager-revoke; в δ condition остаётся как в γ (см. §0 Dδ7, §5 Q-δ-C). Принцип единый и жёсткий: **новые канонические поля ДОБАВЛЯЮТСЯ; старые помечаются `[deprecated=true]` и НЕ удаляются** (`buf breaking` зелёный — additive + deprecate, как γ-прецедент `match_tags→match_labels`). Сервер реализует **двустороннюю проекцию**: на входе принимает старое ИЛИ новое представление (новое имеет приоритет, иначе старое), на чтении заполняет **ОБА** для back-compat. Удаление старых полей — будущий major-bump, **вне δ**.

**Forward-only / non-breaking:** старые клиенты (UI до δ, API-консьюмеры, pre-δ binding'и в БД) продолжают работать без изменений. δ — чистка читаемости/SDK-эргономики 2026 ценой временного слоя проекции; **никакой новой функциональности и никаких новых данных** δ не вводит.

Документ описывает **только внешнее наблюдаемое поведение API/UI** (формы payload, проекцию ответа, gRPC-коды, `buf breaking`-статус), не реализацию. Сценарии трассируются в имена integration-/newman-/UI-тестов через ID `δ-<NN>`. Стандартные конвенции (`api-conventions.md`, `security.md`, `data-integrity.md`) нормативны и в тело не дублируются — только ссылками (§1).

---

## 0.1 Карта эпика (контекст — детальные сценарии ТОЛЬКО для δ)

| Под-фаза | Содержание | Статус |
|---|---|---|
| **α** (прод) | `AccessBinding.target` oneof: `all_in_scope`+`resources[]` рабочие; `selector`→`UNIMPLEMENTED`; role-coverage гейт; per-object tuple; `target.id` opaque без containment | вне scope δ |
| **β** (прод) | `resource_mirror` наполняется `compute→iam RegisterResource`; `ResourceSelector{types,match_tags}`; condition-инфра | вне scope δ |
| **γ** (прод, fe3455) | Активация `selector` (label-membership через mirror) + containment (byName/byLabel из mirror.parent) + expiry (eager-revoke в reconciler). `ReplaceTargetSelector`. Прецедент **deprecate+new** `match_tags→match_labels`. Рабочий condition = `non_expired` (через expiry eager-revoke) | вне scope δ (предусловие) |
| **δ** (ЭТОТ док) | **Аддитивная non-breaking чистка формы** двух измерений: канонический `scope{tier,id}` (старые `resource_type`/`resource_id`/enum `scope` → deprecated-проекция); канонические target-имена `all/byName/bySelector` (старые arms → deprecated-aliases). Двусторонняя проекция (вход: оба представления; выход: оба заполнены). **`buf breaking` ЗЕЛЁНЫЙ** (additive+deprecate, 0 удалений). **Сценарии δ-01..δ-14 ниже** | — |
| **ε** (future) | **condition oneof-обёртка `{none\|expiry\|forward}`** (старые `condition_id`/`builtin_condition`/`expires_at` → deprecated-проекция) — **отложено из δ** (как major-bump в этой карте): `condition_id` field-9 уже populated, логический oneof не выразим на wire без breaking field-9 callers, `non_expired` уже работает через γ eager-revoke. 5-е измерение целевой модели формализуется здесь. | вне scope δ (forward-ref) |
| **major-bump v2** (future — упомянуть) | Физическое удаление deprecated-полей (`resource_type`/`resource_id`/enum `scope`/старые target arm-имена + condition-поля после ε). `buf breaking` намеренно красный, согласованный major. | вне scope δ (forward-ref) |

---

## 0. Фиксированные дизайн-решения (контракт scope+target одобрен ревьюером round-1; Q-δ-A..Q-δ-E closed — §5; НЕ переоткрывать)

| ID | Решение | Обоснование |
|---|---|---|
| **Dδ1 (additive non-breaking)** | **Новые канонические поля ДОБАВЛЯЮТСЯ** (новые field numbers, начиная с 17) для **scope + target**; старые (`resource_type=5`/`resource_id=6`/enum `scope=15`/target arm-имена `all_in_scope`/`resources`/`selector`) помечаются `[deprecated=true]`, **НЕ удаляются** (`reserved` НЕ нужен — поля остаются на проводе). condition-поля (`condition_id=9`/`builtin_condition=14`/`expires_at=10`) в δ **не трогаются** — остаются как в γ (чистка отложена в ε, Dδ7). `buf breaking` зелёный (additive + deprecate, 0 удалений). Удаление — future major (вне δ). | Прецедент γ (`match_tags→match_labels` — deprecate+new, breaking зелёный). Forward-only: ни один существующий клиент/binding не ломается. Чистая форма — польза для читаемости/SDK 2026; ценой временного слоя проекции (приемлемо, т.к. δ не вводит новых данных/функций). |
| **Dδ2 (двусторонняя проекция — приоритет НОВОГО)** | **Вход:** сервер принимает старое ИЛИ новое представление каждого измерения. При **обоих** заданных и **согласованных** — OK (новое = derived-эхо старого, см. Dδ4). При обоих заданных и **конфликтующих** — `INVALID_ARGUMENT` (Dδ5, явный reject, не silent). При **одном** заданном — оно и используется. **Выход:** на чтении (`Get`/`List*`) сервер заполняет **ОБА** представления (старые deprecated-поля + новые канонические) консистентно из одной строки данных. | «Новое имеет приоритет, иначе старое» (родитель D3). Двусторонняя проекция — единственный способ держать одновременно pre-δ-клиента (читает старые поля) и post-δ-клиента (читает новые) на одной БД-строке без миграции данных. Reject конфликта (а не silent-приоритет) — детерминированность контракта и защита от «клиент думал одно, сервер записал другое». |
| **Dδ3 (scope как вложенный `Scope scope_v2`)** | **Канонический scope — вложенный message** `Scope { Tier tier; string id }` (новое поле, напр. `scope_v2 = 17`; финальное имя — за `proto-api-reviewer`), где `Tier` — тот же closed-enum (`CLUSTER`/`ACCOUNT`/`PROJECT`), `id` — anchor-id (`cluster_kacho_root`/`acc…`/`prj…`). Старые `resource_type=5`/`resource_id=6` + enum `scope=15` → `[deprecated]`, заполняются проекцией. Проекция тривиальна и **уже существует** в виде `Scope.ValidateAgainst` (tier↔(type,id) — derived-консистентность). | Вложенный message группирует «уровень иерархии + якорь» в одно концептуальное измерение (целевая 5-мерная модель). `resource_type` фактически дублирует `tier` (enum уже derived из него — ground-truth), `resource_id` = `scope.id`. Это **самая ценная** часть чистки: устраняет тройную избыточность (`resource_type`+`resource_id`+enum) → один вложенный `{tier,id}`. _flat-vs-nested финализирует `proto-api-reviewer` на impl (Q-δ-B closed — §5)._ |
| **Dδ4 (scope derived-консистентность)** | **Старое и новое scope-представление derived-эквивалентны** через существующий предикат (`Scope.ValidateAgainst`): `tier=PROJECT ⟺ resource_type='project' ∧ resource_id starts 'prj'` (и аналогично ACCOUNT/CLUSTER). При вход-валидации: если заданы оба — обязаны быть консистентны (иначе Dδ5 reject); если задано одно — второе derive'ится сервером. На чтении оба заполнены derived-консистентно. | scope-избыточность сегодня **уже контролируема** (enum валидируется против плоских полей — не два независимых источника). δ лишь даёт чистое имя той же derived-связи. Проекция — re-use существующего `ValidateAgainst`, не новая логика. |
| **Dδ5 (конфликт старое≠новое → `INVALID_ARGUMENT`)** | **Если запрос задаёт И старое, И новое представление одного измерения, и они НЕ derived-эквивалентны → sync `INVALID_ARGUMENT`** первым стейтментом RPC, до Operation/мутации. Текст стабилен per-измерение (δ покрывает scope+target): scope — `"scope conflicts with resource_type/resource_id"`; target — `"target: new and deprecated arm disagree"`. _(condition отложен в ε — condition-конфликт-текст в δ НЕ вводится.)_ **Приоритет «новое побеждает» применяется ТОЛЬКО когда старое НЕ задано** (Dδ2); при обоих-заданных-конфликте — reject, НЕ silent-приоритет. | Зафиксированный выбор (родитель: «reject vs приоритет — зафиксируй»). Reject детерминированнее silent-приоритета: клиент, пославший оба конфликтующих, имеет баг — лучше явная ошибка, чем тихое отбрасывание одного. Derived-эквивалентные оба — OK (не конфликт). |
| **Dδ6 (target-имена via deprecate+new alias)** | **Канонические target arm-имена `all` / `byName` / `bySelector`** добавляются **аддитивно** (новые oneof-arms ИЛИ новый канонический `AccessTargetV2` message — форма за `proto-api-reviewer`), старые `all_in_scope`/`resources`/`selector` → `[deprecated]`-aliases (НЕ удаляются). Семантика 1:1: `all`≡`all_in_scope`(AllInScope), `byName`≡`resources`(TargetResourceRefList), `bySelector`≡`selector`(ResourceSelector). Проекция: вход принимает любой синоним; выход заполняет оба. **`verification_status` per-member (γ) сохраняется без изменений.** | Прецедент γ (deprecate+new). `all_in_scope`/`resources`/`selector` — внутренние имена; `all`/`byName`/`bySelector` — целевые читаемые (родитель). Семантика идентична → проекция чисто синтаксическая (rename-alias). НЕ переименование внутри одного oneof (это сломало бы wire) — additive. |
| **Dδ7 (condition oneof-обёртка — ОТЛОЖЕНО В ε, вне δ)** | **condition НЕ чистится в δ** — остаётся тремя полями `condition_id=9`/`expires_at=10`/`builtin_condition=14` + service-layer «at most one», КАК В γ. oneof-обёртка `Condition { oneof { None none; Expiry expiry; Forward builtin } }` формализуется в **будущей фазе ε** (форма-ориентир в §2.1 — forward-ref). | **Обоснование отложения (verbatim):** «`condition_id` field-9 уже populated; логический oneof не выразим на wire без breaking field-9 callers; `non_expired` уже работает через γ eager-revoke». Целевая 5-мерная модель называет `condition<none\|expiry\|forward>`, но обёртка над уже-populated field-9 сложнее scope/target и несёт риск рассинхрона проекции — потому отложена (Q-δ-C closed). δ чистит ТОЛЬКО scope+target. |
| **Dδ8 (no new data / no new tables)** | **δ — форма контракта над теми же данными.** НЕТ новых таблиц, НЕТ миграций данных, НЕТ изменения FGA-эмиссии / reconciler / containment / expiry-поведения. Проекция — чистый маппинг в handler/dto-слое (`domain↔proto`). `access_bindings`-row, `access_binding_targets`, `access_binding_target_members`, `access_binding_conditions`, `resource_mirror` — без структурных изменений. | δ — non-breaking форма-чистка, а не функциональная фича. Минимизирует риск слоя проекции: вся работа в proto + handler-маппинге + UI; backend-логика (γ reconciler/expiry/containment) не трогается. Это и держит «buf breaking зелёный» и «0 регрессий поведения». |
| **Dδ9 (pre-δ binding'и → обе формы на чтении)** | **Существующие binding'и в БД (созданные α/γ, до δ) читаются в ОБЕ формы (scope+target).** Их строки не имеют «нового» представления физически — оно derive'ится на чтении проекцией (Dδ4/Dδ6) из тех же колонок. condition читается как в γ (вне δ). Никакого backfill/миграции; `Get`/`List*` на pre-δ binding отдаёт И старые поля (как раньше), И новые канонические scope/target (derived). | Forward-only (паритет α D-8 / γ): δ не переписывает существующие данные. Проекция read-time из единственного источника (БД-строки) гарантирует, что pre-δ и post-δ binding'и читаются идентично в обеих формах. |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — flat message + oneof; форма ресурса дизайнится «в чистой форме под задачу» | Dδ3 (вложенный scope), Dδ6 (target-имена); condition (Dδ7) отложен в ε |
| `api-conventions.md` — read **sync** (`Get`/`List*`); мутации async `Operation`; Watch нет | проекция наблюдается через sync `Get`/`List*` (§A); вход — `Create`/`ReplaceTargetSelector` async (§C) |
| `api-conventions.md` — JSON camelCase | §J: новые `scope{tier,id}`, `target.all/byName/bySelector`, `matchLabels`, `verificationStatus`; deprecated-эхо scope/target `resourceType`/`resourceId`; condition вне δ — как в γ (`conditionId`/`builtinCondition`/`expiresAt`, не проецируется) |
| `api-conventions.md` — error-format; конфликт формата → sync `INVALID_ARGUMENT` первым стейтментом, стабильный текст | Dδ5, δ-04, δ-08 |
| `api-conventions.md` — `update_mask` discipline (если затрагивается Update-путь) | §C: новые scope/target поля + deprecated — единый known-set маски (δ-09); condition вне δ |
| `data-integrity.md` §within-service — δ НЕ добавляет инвариантов/таблиц; CAS `xmin` (γ replace) без изменений | Dδ8 |
| `data-integrity.md` §cross-domain — δ НЕ вводит/не меняет cross-domain рёбра (форма, не данные); `resource_id` остаётся soft-ref | Dδ8; §6 |
| `security.md` §AuthN+AuthZ ВЕЗДЕ — per-RPC Check / `requireGrantAuthority` без изменений (δ не трогает authz-путь) | §C, §6 |
| `security.md` §Internal-vs-external — все затронутые RPC **публичные** (форма tenant-API); δ не вводит Internal | §A/§C |
| `security.md` §инфра-чувствительные — проекция не добавляет полей; `verificationStatus`/labels-зеркало без изменений | Dδ8 |
| `00-kacho-core.md` ban #9 (мутации→Operation), #10 (within-DB CAS), #12 (TDD), #1 (APPROVED перед кодом), #11 (без TODO/долга — старые поля deprecated, не «на потом») | §C; Dδ8; §6 DoD (RED→GREEN) |
| `polyrepo.md` §порядок merge | §6 DoD: proto → iam → api-gateway → ui → deploy → workspace(docs) |
| `buf breaking` — **должен оставаться ЗЕЛЁНЫМ** (additive + deprecate, 0 удалений) — отличие от γ rename (там был намеренный red) | Dδ1, δ-05, §6 S1 |
| sub-phase α/γ (прод) — поведение (FGA-эмиссия, containment, expiry, selector-membership) НЕ регрессирует; δ — только форма | Dδ8, δ-07, δ-10 |

---

## 2. Форма: текущее → целевое (нормативно — Dδ3/Dδ6; condition/Dδ7 отложен в ε)

### 2.1 Два измерения чистки в δ (proto-ориентир — финал за `proto-api-reviewer`)

> **scope ⌖ для δ:** δ покрывает ТОЛЬКО **scope{tier,id} (Dδ3/Dδ4) + target.all/byName/bySelector (Dδ6)**. **condition (Dδ7) — вне δ, отложено в ε** (как major-bump в карте §0.1): остаётся тремя полями `condition_id=9`/`expires_at=10`/`builtin_condition=14` как в γ, проекция-обёртка в δ НЕ вводится. condition-блок ниже оставлен **только как forward-ref на ε** (НЕ часть δ-контракта).

```
// ── ИЗМЕРЕНИЕ scope ──────────────────────────────────────────────
// СЕЙЧАС (остаётся [deprecated], проекция):
//   string resource_type = 5;   string resource_id = 6;   Scope scope = 15;  (enum derived из (type,id))
// δ-КАНОН (additive, напр. field 17):
message Scope {                       // вложенный (Dδ3); flat-альтернатива — Q-δ-B
  enum Tier { TIER_UNSPECIFIED = 0; CLUSTER = 1; ACCOUNT = 2; PROJECT = 3; }
  Tier   tier = 1;
  string id   = 2;                    // cluster_kacho_root | acc… | prj…
}
//   Scope scope_v2 = 17;  // derived-эквивалент resource_type/resource_id/enum scope (Dδ4)

// ── ИЗМЕРЕНИЕ target ─────────────────────────────────────────────
// СЕЙЧАС AccessTarget.oneof { all_in_scope=1 | resources=2 | selector=3 }  (остаётся [deprecated]-aliases)
// δ-КАНОН (additive arm-имена / AccessTargetV2 — Dδ6):
//   all         ≡ all_in_scope (AllInScope)
//   byName      ≡ resources    (TargetResourceRefList)   // + per-member verification_status (γ, без изменений)
//   bySelector  ≡ selector     (ResourceSelector{types, match_labels})

// ── ИЗМЕРЕНИЕ condition — ВНЕ δ (отложено в ε; forward-ref, НЕ часть δ-контракта) ──
// В δ condition остаётся КАК В γ: condition_id=9 + expires_at=10 + builtin_condition=14
//   («логический oneof», wire не выражает). Проекция-обёртка в δ НЕ вводится.
// ε-КАНОН (будущая фаза, НЕ δ; additive oneof-обёртка):
//   message Condition { oneof condition { None none=1; Expiry expiry=2; Forward builtin=3; } }
//   Condition condition_v2 = 18;
```

### 2.2 Матрица вход × проекция (Dδ2/Dδ5)

| Вход (одно измерение) | Поведение |
|---|---|
| только СТАРОЕ представление (pre-δ клиент) | ✅ принято; новое derive'ится сервером; на чтении заполнены оба (δ-01) |
| только НОВОЕ представление (post-δ клиент) | ✅ принято, эквивалентно; на чтении заполнены оба (δ-02) |
| ОБА, derived-эквивалентны | ✅ принято (не конфликт; новое = эхо старого, Dδ4) |
| ОБА, конфликтуют (не derived-эквивалентны) | ❌ sync `INVALID_ARGUMENT` (Dδ5; reject, не silent-приоритет) (δ-04) |
| ни одно (legacy: target вообще не задан) | ✅ back-compat α: трактуется как `all`/`all_in_scope` (без изменений α) |

### 2.3 Проекция на чтении (Dδ2 выход / Dδ9)

`Get`/`List*` любого binding'а (pre-δ или post-δ) отдаёт **оба** представления **двух** δ-измерений консистентно из одной БД-строки:
- scope: `resourceType`+`resourceId`+`scope`(enum) **И** `scope.tier`+`scope.id`;
- target: `target.allInScope/resources/selector` **И** `target.all/byName/bySelector`;
- condition: **вне δ** — отдаётся как в γ (`conditionId`/`builtinCondition`/`expiresAt`); проекция-обёртка `condition.{none|expiry|forward}` в δ НЕ вводится (отложено в ε).

---

## §A — Backend: проекция на чтении (наблюдение через read)

### Сценарий δ-03: Get binding'а отдаёт ОБА представления консистентно

**ID:** `δ-03`

**Given** существующий selector-binding `acb-X` на `project:prj_prod` (scope `PROJECT`), `target.selector{types:[compute.instance], matchLabels:{env:prod}}`, `expires_at=null`, члены `inst-1`(ACTIVE)

**When** caller вызывает sync `GET /iam/v1/accessBindings/acb-X`

**Then** `200 OK`; ответ несёт **старое** представление как раньше: `resourceType="project"`, `resourceId="prj_prod"`, `scope="PROJECT"`(enum), `target.selector{types,matchLabels}`
**And** ответ несёт **новое** каноническое представление консистентно: `scope:{tier:"PROJECT", id:"prj_prod"}`, `target.bySelector{types,matchLabels}`
**And** condition — три поля 9/10/14 как в γ (`expiresAt`/`builtinCondition`/`conditionId`), проекция в δ НЕ вводится (Dδ7 отложен в ε); здесь все пусты (нет TTL/builtin)
**And** `verificationStatus` per-member (γ) присутствует без изменений; никаких инфра-чувствительных полей (security.md)

### Сценарий δ-06: pre-δ binding (в БД до δ) читается в обе формы

**ID:** `δ-06`

**Given** binding `acb-OLD`, созданный в α/γ **до** деплоя δ (строка БД без «нового» представления физически), напр. `all_in_scope` на `account:acc-A` c `expires_at=now+30d`

**When** caller (post-δ) читает `Get(acb-OLD)` / `ListByResource`

**Then** старые поля как раньше: `resourceType="account"`, `resourceId="acc-A"`, `scope="ACCOUNT"`, `target.allInScope=true`, `expiresAt=<ts>`
**And** новые поля derive'ятся проекцией из той же строки (Dδ9): `scope:{tier:"ACCOUNT", id:"acc-A"}`, `target.all={}`
**And** condition — три поля 9/10/14 как в γ (`expiresAt=<ts>`), проекция в δ НЕ вводится (Dδ7 отложен в ε)
**And** значения старого и нового scope/target представления **derived-эквивалентны** (нет backfill/миграции — read-time проекция)

### Сценарий δ-07: Conformance — α/γ поведение НЕ регрессирует (форма, не функция)

**ID:** `δ-07`

**Given** после деплоя δ: selector-binding `acb-S` (γ-membership), byName-binding `acb-N` (α per-object), all-binding `acb-A`, TTL-binding `acb-T`

**When** проверяются FGA-эмиссия, containment, expiry, selector-membership-diff

**Then** per-object FGA-tuples, `hierarchyParentTuple`, containment-вердикты (ACTIVE/PENDING_VERIFICATION/REJECTED из mirror.parent), expiry eager-revoke, selector reconciler-diff — **идентичны pre-δ** (δ не трогает backend-логику — Dδ8)
**And** `ReplaceTargetSelector` CAS (`xmin`) работает как в γ; `Check`-результаты не меняются

---

## §C — Backend: вход (Create / ReplaceTargetSelector / Update) принимает обе формы

REST: `POST /iam/v1/accessBindings` (body несёт старую ИЛИ новую форму); `POST …/{id}:replaceTargetSelector`. gRPC async → Operation (ban #9). Проекция — чисто handler/dto-слой (Dδ8).

### Сценарий δ-01: Create со СТАРОЙ формой → работает (back-compat)

**ID:** `δ-01`

**Given** account `acc-A` + `prj_prod` (owner `usr-OWNER`), reusable роль `rol-computeeditor` (assignable на `prj_prod`), под `prj_prod` `inst-1`{env:prod} в mirror, caller — owner

**When** caller (pre-δ клиент) вызывает `POST /iam/v1/accessBindings` со **старой** формой:
  - `subjectType="user"`, `subjectId="usr-MEMBER"`, `roleId="rol-computeeditor"`
  - `resourceType="project"`, `resourceId="prj_prod"`, `scope="PROJECT"`
  - `target={"resources":{"resources":[{"type":"compute.instance","id":"inst-1"}]}}`

**Then** RPC возвращает `Operation`; poll до `done=true`; `done && !error`
**And** binding создан идентично pre-δ: per-object tuple `compute_instance:inst-1#<tier>@user:usr-MEMBER` эмитится (без изменений α)
**And** `Get` отдаёт И старую форму, И новую derived (`scope:{tier:PROJECT,id:prj_prod}`, `target.byName=[{compute.instance,inst-1}]`)

### Сценарий δ-02: Create с НОВОЙ формой → работает, эквивалентно

**ID:** `δ-02`

**Given** как δ-01

**When** caller (post-δ клиент) вызывает `Create` с **новой** канонической формой:
  - `subjectType="user"`, `subjectId="usr-MEMBER"` _(subject НЕ канонизируется в δ — Q-δ-D закрыт: остаются плоские `subjectType`/`subjectId`)_
  - `roleId="rol-computeeditor"`
  - `scope={"tier":"PROJECT","id":"prj_prod"}`
  - `target={"byName":{"resources":[{"type":"compute.instance","id":"inst-1"}]}}`

**Then** Operation `done && !error`; binding **эквивалентен** δ-01 (та же БД-строка, тот же per-object tuple)
**And** `Get` отдаёт обе формы консистентно; binding, созданный новой формой, и binding, созданный старой формой, **неотличимы на чтении** (одна модель данных)

### Сценарий δ-04: Конфликт старое≠новое в одном запросе → INVALID_ARGUMENT

**ID:** `δ-04`

**Given** аутентифицированный caller, grant-authority на scope

**When** `Create` задаёт И старое, И новое scope, **конфликтующие**: `resourceType="project"`,`resourceId="prj_prod"` **и** `scope={tier:"ACCOUNT", id:"acc-A"}` (не derived-эквивалентны)
**Then** sync `INVALID_ARGUMENT` `"scope conflicts with resource_type/resource_id"` (Dδ5), до Operation; binding не создан

**When** `Create` задаёт `target.resources=[…]` **и** `target.bySelector={…}` (разные руки/несогласованы)
**Then** sync `INVALID_ARGUMENT` `"target: new and deprecated arm disagree"` (Dδ5/oneof)

> condition (Dδ7) — **отложено в ε**: condition-конфликт-ветка из δ-04 убрана; condition остаётся тремя полями 9/10/14 как в γ, проекция в δ НЕ вводится. δ-04 покрывает только scope-конфликт + target-конфликт.

**When** `Create` задаёт `resourceType="project"`,`resourceId="prj_prod"` **и** `scope={tier:"PROJECT", id:"prj_prod"}` (derived-эквивалентны)
**Then** Operation `done && !error` — согласованные оба НЕ конфликт (Dδ4); binding создан

### Сценарий δ-08: Negative — невалидное новое scope-представление → sync INVALID_ARGUMENT

**ID:** `δ-08`

**Given** аутентифицированный caller, grant-authority

**When** `Create` c `scope={tier:"PROJECT", id:"acc-A"}` (tier↔id несогласованы внутри нового представления — PROJECT требует `prj…`)
**Then** sync `INVALID_ARGUMENT` (`Scope.ValidateAgainst` re-use, Dδ4) `"scope: tier PROJECT requires id prefix 'prj'"`, до Operation

**When** `Create` c `scope={tier:"TIER_UNSPECIFIED", id:"prj_prod"}`
**Then** sync `INVALID_ARGUMENT` `"scope.tier is required"` (паритет существующего `SCOPE_UNSPECIFIED`-reject)

### Сценарий δ-09: Update / ReplaceTargetSelector — новые поля в update_mask known-set

**ID:** `δ-09`

**Given** selector-binding `acb-R` (`matchLabels:{env:prod}`), caller — owner

**When** caller вызывает `:replaceTargetSelector` с новой формой `bySelector{types:[compute.instance], matchLabels:{env:prod, team:payments}}` (+ `resourceVersion` echo для CAS)
**Then** Operation `done && !error`; selector заменён (γ-семантика без изменений); `Get` отдаёт обе формы нового selector'а
**And** если RPC принимает `update_mask` — новые канонические поля И их deprecated-aliases входят в единый known-set; unknown поле → `INVALID_ARGUMENT` (api-conventions update_mask discipline); deprecated-поле в маске → принимается (не «immutable»), проецируется в новое

### Сценарий δ-10: Concurrency — δ не меняет CAS-семантику (xmin) ReplaceTargetSelector

**ID:** `δ-10`

**Given** selector-binding `acb-C`, caller — owner; две конкурентные `:replaceTargetSelector` (одна старой формой, одна новой), обе читали один `resourceVersion`

**Then** ровно одна `done && !error` (CAS `xmin` прошёл); вторая `done && error.code=FAILED_PRECONDITION` `"access binding was modified concurrently, retry"` (γ-19 семантика без изменений — Dδ8)
**And** форма входа (старая/новая) НЕ влияет на CAS-исход (обе проецируются в одну мутацию); concurrent integration-тест (≥2 goroutine) обязателен (RED-first)

---

## §B — UI: миграция на канонические поля (опционально — старые ещё работают)

> δ-UI **опциональна** для работоспособности (Dδ1: старые поля живут) — но рекомендована для консистентности SDK 2026. UI мигрирует на канонические `scope{tier,id}` / `target.all/byName/bySelector` без изменения UX (condition вне δ — UI читает его как в γ).

### Сценарий δ-11: UI читает binding через новые канонические поля

**ID:** `δ-11`

**Given** оператор на `AccessBindingsPage`; binding'и созданы и pre-δ, и post-δ

**When** страница рендерит список/детали

**Then** UI читает `scope.tier`/`scope.id` (вместо `resourceType`/`resourceId`/enum `scope`), `target.all/byName/bySelector` — для **всех** binding'ов (pre-δ читаются через derived-проекцию, δ-06); condition читается как в γ (вне δ)
**And** UX неизменен: scope read-only колонка (KAC-224), grant-форма три режима (γ: весь scope / по объектам / по меткам), verification-бейджи (γ-07) — всё работает идентично pre-δ

### Сценарий δ-12: UI grant-форма отправляет новую форму, binding эквивалентен

**ID:** `δ-12`

**Given** оператор создаёт label-grant через форму (режим «По меткам»)

**When** submit

**Then** форма отправляет `Create` с новой формой (`scope{tier,id}`, `target.bySelector{types,matchLabels}`)
**And** созданный binding неотличим от созданного старой формой (δ-02); membership/verification-бейджи рендерятся как в γ-07

---

## §D — proto / buf

### Сценарий δ-05: buf breaking ЗЕЛЁНЫЙ (аддитивно + deprecate, 0 удалений)

**ID:** `δ-05`

**Given** PR с δ-proto: новые канонические поля **scope + target** добавлены новыми field-numbers (≥17); старые scope/target помечены `[deprecated=true]`; condition вне δ (не трогается); ни одно поле/arm НЕ удалено, НЕ переиспользован field-number

**When** прогоняется `buf lint` + `buf breaking` против `main`

**Then** `buf lint` зелёный; **`buf breaking` ЗЕЛЁНЫЙ** (additive + deprecate — НЕ удаление/renumber; отличие от γ `match_tags→match_labels`, где red был намеренным)
**And** `gen/go/...` регенерирован; старые stubs-поля доступны (back-compat для pre-δ Go-консьюмеров)
**And** ревью — `proto-api-reviewer` (flat-form, oneof, deprecate-discipline, scope как вложенный vs flat — Q-δ-B финализируется здесь)

---

## §J — Smoke / e2e (заказчик: финальная верификация, шаг 7)

### Сценарий δ-13: e2e — старая И новая форма оба → 200, эквивалентны (REST + gRPC + UI)

**ID:** `δ-13`

**Given** развёрнутый стенд (`make dev-up`); `acc-A`+`prj_prod`+owner; reusable роль `rol-computeeditor`; `inst-1`{env:prod} в mirror

**When** owner создаёт binding **старой** формой (REST `POST accessBindings`, `resourceType/resourceId/scope`-enum + `target.resources`) → poll Operation
**Then** Operation `done`; `Get` (REST + `grpcurl`) отдаёт обе формы; per-object tuple эмитится; `Check` allowed

**When** owner создаёт второй binding **новой** формой (`scope{tier,id}` + `target.byName`) для другого subject → poll Operation
**Then** Operation `done`; второй binding эквивалентен первому на чтении (одна модель); `Check` allowed

**When** owner создаёт label-grant новой формой (`target.bySelector{types,matchLabels}`) + TTL через γ-форму (`expiresAt` — condition отложен в ε, проекция в δ НЕ вводится) → poll
**Then** γ-поведение без изменений: reconciler материализует membership; expiry eager-revoke по истечении (`status→REVOKED`); `Check` denied после revoke

**And** newman: старая форма happy + новая форма happy + конфликт-negative (δ-04) → 200/200/400; α/γ non-regression (δ-07) зелёный
**And** UI: список/форма на новых полях (δ-11/δ-12), pre-δ binding'и читаются через проекцию, UX неизменен

### Сценарий δ-14: e2e — pre-δ binding (созданный до деплоя δ) переживает upgrade

**ID:** `δ-14`

**Given** стенд с binding'ами, созданными **до** деплоя δ (α/γ-форма в БД)

**When** деплой δ; caller читает старые binding'и через REST/gRPC/UI

**Then** все pre-δ binding'и читаются в обе формы (δ-06); FGA-tuples/Check/membership/expiry без регрессии (δ-07); никакой backfill-миграции не потребовалось (Dδ9)

---

## 5. Зафиксированные решения (closed — НЕ переоткрывать; см. также §0)

> δ — единственная под-фаза эпика, где ценность vs риск была **не однозначна** (чистка формы, не функция). Вопросы Q-δ-A..Q-δ-E **закрыты** родителем/ревьюером; решения зафиксированы ниже и в §0 (Dδ*). Под-фаза сфокусирована на **scope + target**; condition отложен в ε.

| # | Вопрос | **Зафиксированное решение (ПРИНЯТО)** |
|---|---|---|
| **Q-δ-A (стоит ли δ?)** | Текущая форма функционально полна (α+β+γ в проде); δ добавляет временный слой проекции ради читаемости/SDK 2026. | **δ делается частично: scope (Dδ3/Dδ4) + target (Dδ6).** scope-чистка — высокая польза, низкий риск (избыточность уже derived-консистентна, проекция = re-use `ValidateAgainst`); target-rename — средняя польза, низкий риск (синтаксический alias, прецедент γ). condition — отложен (Q-δ-C). **Польза > риск → ПРИНЯТО.** |
| **Q-δ-B (scope: вложенный vs flat)** | `Scope{tier,id}` вложенный (Dδ3) vs плоские `scope_tier`+`scope_id`. | **scope — вложенный message `{tier, id}`** (целевая 5-мерная модель `scope{tier,id}`). flat-vs-nested финализирует `proto-api-reviewer` на impl (§D δ-05) — обе формы валидны, контракт-семантика одна. **ПРИНЯТО.** |
| **Q-δ-C (condition-oneof в δ?)** | Обёртка `Condition` oneof над уже populated `condition_id`(9)/`builtin_condition`(14)/`expires_at`(10) сложнее scope/target. | **condition отложен в ε.** В δ остаётся как в γ (3 поля 9/10/14, service-layer «at most one»); проекция-обёртка НЕ вводится. **Обоснование отложения:** «`condition_id` field-9 уже populated; логический oneof не выразим на wire без breaking field-9 callers; `non_expired` уже работает через γ eager-revoke». **ПРИНЯТО.** |
| **Q-δ-D (канонизировать subject?)** | `subject{type,id}` vs плоские `subject_type`/`subject_id`. | **subject НЕ канонизируется в δ** — остаются плоские `subjectType`/`subjectId` (читаемы и так; δ сфокусирована на scope-чистке). **ПРИНЯТО.** |
| **Q-δ-E (Dδ5: reject vs приоритет)** | Конфликт старое≠новое → reject или silent-приоритет? | **Конфликт старое≠новое → sync `INVALID_ARGUMENT` reject** (Dδ5); приоритет «новое» — только когда старое НЕ задано. Reject детерминированнее. **ПРИНЯТО (Dδ5 корректен).** |

---

## 6. Definition of Done (по стадиям)

Кросс-репо порядок (`polyrepo.md`): **proto → iam → api-gateway → ui → deploy → workspace(docs)**.

**S1 — proto (`kacho-proto`):**
- [ ] Канонический `scope` — вложенный message `{tier,id}` (Dδ3; flat-vs-nested финализирует `proto-api-reviewer`, Q-δ-B closed) — новый field ≥17; старые `resource_type`/`resource_id`/enum `scope` → `[deprecated=true]` (НЕ удалять).
- [ ] Канонические target arm-имена `all`/`byName`/`bySelector` (Dδ6, форма per `proto-api-reviewer`) аддитивно; старые `all_in_scope`/`resources`/`selector` → `[deprecated]`-aliases.
- [ ] **condition — ВНЕ δ (отложено в ε):** `condition_id`/`expires_at`/`builtin_condition` остаются КАК В γ; oneof-обёртка `Condition` (Dδ7) в δ НЕ добавляется (Q-δ-C closed).
- [ ] `buf lint` зелёный; **`buf breaking` ЗЕЛЁНЫЙ** (additive+deprecate, 0 удалений/renumber — δ-05). `gen/go/...` регенерирован. Ревью — `proto-api-reviewer`.

**S2 — iam (`kacho-iam`):**
- [ ] RED integration-тесты по δ-01..δ-10 первыми (вход обеих форм, проекция чтения, конфликт-reject δ-04, pre-δ-проекция δ-06, α/γ non-regression δ-07, concurrency δ-10) → красный → GREEN.
- [ ] **Двусторонняя проекция в dto/handler-слое** (Dδ2/Dδ8 — НЕ в domain, НЕ в repo; БД-строка не меняется): вход нормализует старое|новое (новое приоритет если старое пусто; derived-консистентность; конфликт → `INVALID_ARGUMENT` Dδ5); выход заполняет оба представления из одной строки.
- [ ] scope-проекция re-use `Scope.ValidateAgainst` (Dδ4) — без новой логики; **НЕТ новых таблиц/миграций** (Dδ8 — ban #11: не долг, deprecated-поля живут).
- [ ] α/γ backend-логика (FGA-эмиссия, containment из mirror.parent, expiry eager-revoke, reconciler-diff, CAS `xmin`) **НЕ трогается** (δ-07/δ-10 подтверждают non-regression).
- [ ] Error-mapping: конфликт формата → sync `INVALID_ARGUMENT` стабильный текст (δ-04/δ-08); без leak pgx.
- [ ] by-design Dδ1/Dδ2/Dδ3/Dδ6 — запись в `docs/architecture/` kacho-iam (clean-form проекция scope+target, additive non-breaking, future-major удаление deprecated; condition отложен в ε).
- [ ] Ревью — `go-style-reviewer` (thin handler-проекция), `system-design-reviewer` (подтвердить: δ не вводит новых данных/инвариантов/рёбер; чистая форма).

**S3 — api-gateway (`kacho-api-gateway`):**
- [ ] grpc-gateway аддитивно пропускает новые поля (REST mapping для вложенного `scope` и `target.all/byName/bySelector`; condition вне δ); existing RPC-регистрация без изменений (δ не вводит новых RPC). `api-gateway-registrar` подтверждает.
- [ ] newman: старая форма happy (δ-01) + новая форма happy (δ-02) + конфликт-negative (δ-04) + pre-δ-проекция (δ-06) + α/γ non-regression (δ-07), RED-first.

**S4 — ui (`kacho-ui`):**
- [ ] Миграция типов/чтения на канонические поля (`scope{tier,id}`, `target.all/byName/bySelector`; condition вне δ — читается как в γ); чтение pre-δ binding'ов через проекцию (δ-11).
- [ ] grant-форма отправляет новую форму (δ-12); UX неизменен (scope read-only колонка KAC-224, три режима target γ, verification-бейджи γ-07).
- [ ] UI-тесты (vitest/playwright) по δ-11/δ-12; back-compat: старые поля больше не нужны UI, но binding'и читаются.

**S5 — deploy (`kacho-deploy`):** изменений инфраструктуры нет (δ — форма proto/handler/ui); e2e-build-матрицы newman зелёные.

**S6 — workspace (docs/vault):** обновить `resources/iam-access-binding.md` (раздел «Clean-form (epic-100 δ)»: каноническое scope+target + deprecated-проекция + future-major; condition отложен в ε), `rpc/iam-access-binding-service.md` (двусторонняя проекция вход/выход scope+target), KAC-trail; этот acceptance-док → APPROVED. **НЕ** добавлять новых cross-domain рёбер (δ — форма, не данные).

**Финальная верификация (перед merge каждой Go-стадии):** `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` + newman зелёные + `buf breaking` ЗЕЛЁНЫЙ (δ-05).

---

## 7. Выход / запреты

- Единственный артефакт этого шага — настоящий markdown. **Никакого кода** (ни `.go`, ни `.sql`, ни `.proto`).
- Описано только наблюдаемое поведение API/UI + `buf breaking`-статус; форма proto/dto-проекции финализируется `proto-api-reviewer`/`rpc-implementer`.
- **δ — additive non-breaking форма-чистка:** старые поля `[deprecated]`, НЕ удаляются; удаление — future major (вне δ). `buf breaking` ОБЯЗАН остаться ЗЕЛЁНЫМ (отличие от γ rename).
- **δ НЕ вводит новых данных/таблиц/миграций/функциональности/рёбер** — форма контракта над теми же данными (Dδ8). α/γ backend-поведение НЕ регрессирует.
- **δ покрывает ТОЛЬКО scope + target.** condition (Dδ7) **отложено в ε** — в δ НЕ вводится condition-проекция/oneof-обёртка; condition остаётся тремя полями 9/10/14 как в γ.
- Без сравнений с чужими облаками — конвенции Kachō нормативны (`api-conventions.md`).
- **§5 решения зафиксированы (Q-δ-A..Q-δ-E closed — см. §0/§5):** δ делается частично — scope (Dδ3/Dδ4) + target (Dδ6); condition (Dδ7) отложен в ε; subject не канонизируется; конфликт старое≠новое → reject (Dδ5). «Не делать» / «делать частично» — больше не открытый вопрос.
- Координация после APPROVED: KAC Subtask δ + `superpowers:writing-plans` → `integration-tester` (RED по δ-NN) → `rpc-implementer` → `proto-api-reviewer` (proto-форма/deprecate/buf-breaking-зелёный) / `go-style-reviewer` (thin проекция) / `system-design-reviewer` (нет новых данных/рёбер) / `api-gateway-registrar` (REST mapping новых полей) → заказчик: финальный smoke (§J δ-13/δ-14).
```