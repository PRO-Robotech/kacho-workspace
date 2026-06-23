# IAM anchor-grant, invite-activation FGA-emission & invitee default-account — Acceptance (Given-When-Then)

> **Статус:** ✅ **APPROVED** (acceptance-reviewer, round 2, 2026-06-23). Gate ban #1 пройден — RC-1 (anchor-tier emit) + RC-2 (EmitFGARelationWrite in-tx) + RC-5 (every user → personal default account+project; gate owns-zero-accounts, no 2nd InsertActive) + RC-4 (deploy follow-up). Strict TDD.
> **Дата:** 2026-06-23
> **Автор:** `acceptance-author`
> **Ревьюер:** `acceptance-reviewer`
> **Эпик/тикет:** KAC-`<N>` (bugfix-таска под эпиком «RBAC rules-model 2026» `[EPIC]`; номер проставляется до старта `superpowers:writing-plans`). Затронутые репо: **`kacho-iam` ONLY** (нет proto / нет api-gateway / нет migration).
> **Происхождение:** live-диагностика на ревизии `fe3455` — два независимых FGA-emission бага (RC-1/RC-2), из-за которых приглашённый пользователь после активации не видит ни своего членского account-а, ни проекта, на который ему выдали грант; **плюс** owner-mandated требование RC-5 (переворачивает прежний by-design): любой пользователь, включая приглашённого, должен получать собственный дефолтный Account + Project. Корневые причины подтверждены построчным чтением источника (см. ниже).

> **Источник истины (ground-truth, читан построчно):**
> - `kacho-iam/internal/apps/kacho/api/access_binding/scope_grant_tuples.go` — `emitAnchorRule` (строки 113–188). Строки **159–161**: `if !authzmap.TypeHasVerbRelations(objType) { continue }` — ARM_ANCHOR-правило на **tier-only** типе (`account`/`project`) эмитит **ноль** subject-tuples. Корректная concrete-object-форма tier-tuple уже существует в `emitNamesRule` (строки **200–217**): `add(abrepo.RelationTuple{User: subject, Relation: tier, Object: <objType>:<id>})`, и в комментарии 200–205 явно задокументировано «безопасно для ВСЕХ типов, включая tier-only account/project». WILDCARD `*.*`-ветка (строки 131–142) уже эмитит tier-tuple на bare anchor через `anchorTierRelation` (строки 240–250).
> - `kacho-iam/internal/authzmap/fga_types.go` — `TypeHasVerbRelations` (строки 110–112) + `verbBearingTypes` (строки 120–143): `account` и `project` **намеренно ОТСУТСТВУЮТ** (tier-only ancestors, комментарий 142). `ObjectType("iam","account")="account"`, `ObjectType("iam","project")="project"` (`objectTypes` строки 212–213). Drift-gate `authzmap/fga_model_drift_test.go` держит набор в lockstep с `fga_model.fga`.
> - `kacho-iam/internal/apps/kacho/api/user/internal_upsert.go` — `doUpsert` Step 1 (строки **204–242**): активация PENDING-invite (`ActivateInvite`) коммитит ТОЛЬКО `ActivateInvite`-UPDATE + `iam.user.updated` audit-event в writer-tx (`w.UsersW().ActivateInvite` → `w.EmitAuditEvent` → `w.Commit`, строки 209/218/232); **НЕ** эмитит member-hierarchy-tuple `account:<activated.AccountID>#account@iam_user:<activated.ID>`. Bootstrap-путь эмитит forms через `bootstrapTuples` (чистый builder, строки 445–463) и доставляет их через `w.EmitFGARelationWrite` в bootstrap-tx (строки 408–411). Bootstrap-gate (строка **257**): `if !activatedAny && len(existing) == 0` — активированный invitee при `activatedAny=true` **НЕ** проходит gate → bootstrap SKIPPED → у invitee **нет** собственного base Account/Project (этот SKIP — корень RC-5).
> - `kacho-iam/internal/repo/kacho/pg/tx.go` — `(*writeTx).EmitFGARelationWrite(ctx, []service.RelationTuple)` (строки **95–104**): in-tx emit интента `fga.tuple.write` в `kacho_iam.fga_outbox` на ТОЙ ЖЕ `pgx.Tx` writer-tx'а (atomic с окружающей мутацией, ban #10 / SEC-D). Делегирует `fga_outbox.EmitWriteTx`. **Это** корректный in-tx co-commit-механизм — тот же, что использует bootstrap-путь (internal_upsert.go:408–411). `service.RelationTuple{User, Relation, Object}` (governance_ports.go:32–36).
> - `kacho-iam/internal/apps/kacho/api/relationhook/relationhook.go` — `WriteHierarchyTuple(...)` (строки 21–23, 50–85): **POST-COMMIT best-effort прямой `relations.WriteTuples()` в OpenFGA** («The write is best-effort and non-fatal: the resource row is already committed when this runs», строки 20–23). Это **НЕ** writer-tx и **НЕ** `fga_outbox` — его НЕЛЬЗЯ co-commit'ить, он нарушает ban #10. RC-2 **НЕ** использует этот helper (ранняя ревизия дока ошибочно ссылалась на него). Из него заимствуется ТОЛЬКО tuple-**форма** (`<parentType>:<parentID>#<relation>@<childType>:<childID>` объектно-инвертирована: FGA-форма `<childType>:<childID>#<relation>@<parentType>:<parentID>`), byte-идентичная `bootstrapTuples` hierarchy-блоку (internal_upsert.go:455).
> - **Последняя применённая миграция iam = `0032`** (CLAUDE.md §6 + MEMORY). Эта таска **миграцию НЕ добавляет** (ban #5 — n/a; чистый use-case/emit fix). RC-5 не вводит новую таблицу/колонку — только новый read-метод над существующей колонкой `accounts.owner_user_id` (account_repo.go:36) для gate-предиката «owns-zero-accounts».
> **Образцы формата:** `rbac-rules-model-2026-H-rule-module-scalar-acceptance.md`, `rbac-rules-model-2026-acceptance.md` (нумерация, §-структура, таблица стабильных текстов, DoD-чеклист, traceability).

---

## Обзор

Три связанных бага в `kacho-iam` ломают первый сквозной сценарий «пригласить → активировать → выдать грант на проект» так, что приглашённый пользователь после логина не видит ни членского account-а инвайтера, ни проекта, на который ему выдан anchor-role-грант, **и** не получает собственного дефолтного Account/Project (требование владельца: у любого пользователя должен быть дефолтный проект и аккаунт).

- **RC-1 (PRIMARY):** ARM_ANCHOR-правило (`all_in_scope`: без `resourceNames`, без `matchLabels`) на **tier-only** типе (`iam.account` / `iam.project`), привязанное к account/project-scoped binding, попадает в `continue` (scope_grant_tuples.go:159–161) и эмитит **ноль** subject-tuples → грант молча нефункционален. Фикс: в `emitAnchorRule`, когда `objType` — tier-only И тип ресурса правила совпадает с типом anchor-scope binding-а (`objType == anchorType`), эмитить **concrete tier-tuple на anchor-объекте** (`<anchorType>:<anchorID>#<tier>@<subject>`) вместо `continue`. Это та же безопасная форма, что уже эмитит `emitNamesRule`; именно её читают `ProjectService.List` / `AccountService.List` через `ListObjects(subject,"viewer",type)`.
- **RC-2:** активация invite (PENDING→ACTIVE на Kratos-регистрации, internal_upsert.go:204–242) коммитит только `ActivateInvite`-UPDATE + audit-event, но **не** эмитит member-hierarchy-tuple `account:<A>#account@iam_user:<activatedID>` — активированный member не имеет FGA-ребра в account инвайтера. Фикс: внутри **той же** Step-1 writer-tx (ban #10, co-commit рядом с `w.UsersW().ActivateInvite` + `w.EmitAuditEvent`, до `w.Commit`) вызвать `w.EmitFGARelationWrite(ctx, []service.RelationTuple{{User:"account:<A>", Relation:"account", Object:"iam_user:<activatedID>"}})` — тот же in-tx outbox-механизм, что использует bootstrap-путь (internal_upsert.go:408–411). **НЕ** `relationhook.WriteHierarchyTuple` (он post-commit best-effort, не co-commit-able, нарушает ban #10). Форма tuple — та же, что у `bootstrapTuples` hierarchy-блока (internal_upsert.go:455), но это про **форму**, а не про **механизм эмиссии**. Идемпотентно (re-activate → тот же intent → ровно одно ребро при at-least-once drain).
- **RC-5 (NEW — owner-mandated, переворачивает прежний by-design):** требование владельца — «у любого пользователя должен быть дефолтный проект и аккаунт», **включая** приглашённого+активированного. Сейчас bootstrap (personal Account + "default" Project + 2 self-admin AB + `bootstrapTuples`, internal_upsert.go:~290–420) gated `if !activatedAny && len(existing)==0` (строка 257): invitee активируется → `activatedAny=true` → bootstrap SKIPPED → у invitee НЕТ собственного аккаунта. Фикс: bootstrap должен сработать ТАКЖЕ для invited+activated пользователя, который **не владеет ни одним account-ом** — gate меняется так, чтобы personal-bootstrap срабатывал всегда, когда у разрешённого/активированного user-row число owned-account-ов (`accounts.owner_user_id == userID`) == 0, независимо от `activatedAny`. End-state invitee: **И** (a) собственный дефолтный Account + "default" Project (bootstrap, self-admin), **И** (b) членство в account инвайтера (invite AccessBinding + RC-2 hierarchy-tuple). Идемпотентно: повторная активация НЕ создаёт второй personal account.

Документ описывает **только наблюдаемое внешнее поведение** (эмитированный FGA-tuple-set, `fga_outbox`-строки, результат `Check` / `ListObjects`, REST-ответы `ProjectService.List` / `AccountService.List` / `Get` через api-gateway, gRPC/HTTP-коды), не реализацию. RC-5 наблюдаем как «invitee видит собственный personal Account + "default" Project» (его `AccountService.List` / `ProjectService.List`). Сценарии трассируются в имена integration/newman-тестов через ID `T-Ix` / `T-Ex`.

---

## 0. Фиксированные дизайн-решения (НЕ переоткрывать; ревьюер подтверждает scope)

| ID | Решение | Сценарии |
|---|---|---|
| **D-R1** | **RC-1 фикс — направленный, минимальный.** В `emitAnchorRule`: tier-only `objType` (`account`/`project`) эмитит concrete tier-tuple `{User:subject, Relation:tier, Object:anchorType+":"+anchorID}` **ТОЛЬКО** при `objType == anchorType` (правило на тип того же scope, что и binding). `tier` берётся из `domain.ResolveVerbsAndTier(r.Verbs)` (тот же источник, что используется уже). | T-I1, T-I2 |
| **D-R2** | **Mismatched tier-тип сохраняет SKIP.** ARM_ANCHOR-правило на `iam.account` при **project-scoped** binding (или наоборот) НЕ эмитит ничего (`objType != anchorType`) — account никогда не cascade-ит вверх со своего child-проекта; в FGA-модели нет `from project` на account. Это сохранение fail-closed-SKIP (wrong-direction), не регрессия. | T-I1 |
| **D-R3** (исправлено по system-design-review) | **#177 guard сохраняется — но это про `scope_grant`-carrier, НЕ про cascade на child.** Настоящий #177-источник — `sg_<objType>` carrier-tuple, который RC-1 на tier-only НЕ эмитит (G1), и `v_*` per-verb тоже не эмитит (G2). Concrete tier-tuple `project:P#viewer@user` **ПО МОДЕЛИ каскадит `viewer` на child-ресурсы внутри scope** (`vpc_network.viewer = … or viewer from project`) — это НАМЕРЕННАЯ project-viewer-семантика, идентичная ARM_NAMES и legacy-permissions (G3, by-design `Check=True`). Граница, которую RC-1 сохраняет — **scope containment**: grant НЕ протекает на **sibling** project/account вне якоря (G4). Прежняя формулировка «не cascade-ит на child» была фактически неверна (смешивала carrier-over-cascade с интринсик `viewer from project`); подтверждено `system-design-reviewer`, тест T-I4 переформулирован на G1–G4. | T-I1, T-I4 |
| **D-R4** | **RC-1 — НЕТ migration / НЕТ proto / НЕТ FGA-model change.** `viewer`/`editor`/`admin` — уже direct relations на `account`/`project` (`anchorTierRelation` пишет tier verbatim для account/project; cluster-mapping не задействован, т.к. фикс ограничен `account`/`project`). | весь документ |
| **D-R5** | **RC-2 фикс — co-commit в writer-tx через `EmitFGARelationWrite`.** Member-hierarchy-tuple (форма `{User:"account:<A>", Relation:"account", Object:"iam_user:<activatedID>"}`) эмитится интентом `fga.tuple.write` в `kacho_iam.fga_outbox` через `w.EmitFGARelationWrite(ctx, []service.RelationTuple{…})` (tx.go:95–104) — на **той же** Step-1 writer-tx, что `w.UsersW().ActivateInvite` + `w.EmitAuditEvent`, **до** `w.Commit` (ban #10 — никакого best-effort post-commit). **НЕ** `relationhook.WriteHierarchyTuple` — он post-commit best-effort direct-write в OpenFGA, не co-commit-able. Tuple-**форма** byte-идентична `bootstrapTuples` hierarchy-блоку (internal_upsert.go:455) — но это про форму, не про механизм эмиссии. | T-I3 |
| **D-R6** | **RC-2 + RC-5 идемпотентны.** Повторная активация того же invite (re-login) эмитит тот же RC-2 tuple-intent → at-least-once + идемпотентный drain → ровно одно FGA-ребро (дублей нет). RC-5 bootstrap при re-activate **НЕ** создаёт второй personal account: после первого прогона у invitee owned-account-count == 1, поэтому новый gate-предикат (owns-zero-accounts, см. D-R7) уже false. | T-I3, T-I5, T-E4 |
| **D-R7 (FIX — owner-mandated, переворачивает прежний by-design)** | **КАЖДЫЙ пользователь (включая invited+activated) получает собственный дефолтный Account + "default" Project.** Прежнее «invitee НЕ имеет personal base account» (by-design) **отменено** решением владельца «у любого пользователя должен быть дефолтный проект и аккаунт». Фикс: bootstrap (personal Account + "default" Project + 2 self-admin AB + `bootstrapTuples`) срабатывает не только для genuinely-new identity, а **всегда, когда у разрешённого/активированного user-row число owned-account-ов (`accounts.owner_user_id == userID`) == 0**. Gate-предикат `!activatedAny && len(existing)==0` (internal_upsert.go:257) меняется на «owns-zero-accounts» (новый read-метод над `accounts.owner_user_id`; не новая таблица/колонка). Ordering: activate-then-bootstrap (bootstrap идёт в Step-2 после Step-1-активации); bootstrap сохраняет свою отдельную tx-структуру (`shared.DoWithWriteTx`, internal_upsert.go:322) — RC-2 emit остаётся в Step-1 writer-tx, bootstrap-emit — в bootstrap-tx. **Тонкость invited-vs-new-identity:** у invited+activated user user-row **уже существует** (создан `InsertPending` под account инвайтера, `ActivateInvite` сохраняет его id) — поэтому для invitee bootstrap создаёт только personal Account + "default" Project + 2 self-admin AB + `bootstrapTuples` для **существующего** user-id; он **НЕ** делает повторный `InsertActive` (это вызвало бы 23505 на UNIQUE(external_id)). Для genuinely-new identity (нет PENDING, нет ACTIVE) путь остаётся прежним (`InsertActive` нового user-row + bootstrap). End-state invitee: **И** собственный personal Account + "default" Project (self-admin), **И** членство в account инвайтера (invite AB + RC-2 tuple + RC-1 grant). `Operation.metadata.created` для invitee остаётся `false` (user-row не новый — переиспользуется activated id, resolveUserID:178–180); «created» отражает создание user-identity, не personal-account-bootstrap. | T-E1, T-I5, T-E4 |
| **D-R8 (НЕ в scope кода — deploy/CI follow-up)** | **RC-4:** fe3455 крутит **stale FGA-model revision** (account/project cascade `viewer from cluster` → `user:*` wildcard → false-positive `Check(viewer)=True` при 0 tuples). **Текущая каноническая `fga_model.fga` (kacho-proto) уже использует `system_viewer from cluster`** — non-wildcard `[user, service_account]` (`account.viewer` строки 332–341, `project.viewer` строки 537–544; `cluster.system_viewer` строка 93). То есть RC-4 — про **задеплоенную stale-ревизию на fe3455**, а НЕ про правку proto/.fga (D-R4 «no proto/model change» остаётся true). Лечится операционным **re-bootstrap** FGA-store на current-model + assertion на model-revision drift. Это **операционный/CI follow-up** (re-bootstrap + drift-gate), НЕ часть code-acceptance этой таски. | §RC-4 follow-up |

---

## 1. Связь с регламентом (нормативно; в тело не дублируется)

| Регламент | Где соблюдается |
|---|---|
| `api-conventions.md` — read **sync** (`ProjectService.Get`/`List`, `AccountService.List`), мутации async `Operation` (`AccessBinding.Create`, `InternalUserService.UpsertFromIdentity`); Watch не существует (polling `OperationService.Get`) | T-I2, T-I3, T-E1 (Create→Operation→done→Get) |
| `data-integrity.md` §within-service (ban #10) — FGA-tuple-intent (`fga_outbox`-строка) co-committed **в той же writer-tx**, что доменная мутация: RC-2 — в Step-1 writer-tx (activate-invite UPDATE + audit-event) через `w.EmitFGARelationWrite`; RC-5 bootstrap-tuples — в bootstrap-tx (`shared.DoWithWriteTx`). НЕ best-effort post-commit (`relationhook.WriteHierarchyTuple` исключён). Drain — at-least-once + идемпотентно (transactional-outbox). | T-I3 (RC-2 co-commit), T-I5 (RC-5 bootstrap-tx) |
| `data-integrity.md` §CAS — concurrent `AccessBinding.Create` остаётся strict-create (partial UNIQUE `access_bindings_active_grant_uniq`, §4.5 CLAUDE.md): ровно один грант проходит, дубль → `ALREADY_EXISTS`. | T-I4 |
| `security.md` — `InternalUserService.UpsertFromIdentity` — Internal-only (:9091, Kratos provision-hook / admin-tooling), **НЕ** на external TLS endpoint (ban #6). Newman invite-activate проходит через internal-mux / hook-путь, не через external public RPC. | T-E1, T-E4 |
| `00-kacho-core.md` ban #1 (APPROVED перед кодом), #9 (мутации→Operation), #10 (within-tx outbox-intent), #11 (никакого тех-долга — все три RC чинятся в этом же PR), #12 (TDD RED→GREEN: integration **И** newman в том же PR), #13 (known-failing RED-декларация для product-bug), #2 (без чужих облаков) | весь документ; §DoD |
| `architecture.md` — `emitAnchorRule` — чистая детерминированная per-rule projection (pure builder); RC-2 emit — в use-case-слое (`doUpsert` Step-1) через repo-port `w.EmitFGARelationWrite` (in-tx outbox); RC-5 переиспользует `bootstrapTuples`-builder (не дублирует tuple-форму). | T-I1, T-I3, T-I5 |
| `polyrepo.md` §порядок merge | single-repo: `kacho-iam` (нет вышестоящих proto/corelib/gateway-изменений). |
| `testing.md` — integration (testcontainers Postgres **+ OpenFGA**) + newman в том же PR; concurrent-race для CAS. | весь §3 / §4 |

---

## 2. Нормативные определения (источник истины для сценариев)

### 2.1. Tuple-формы (точные строки, часть контракта)

| Имя | Форма (`User # Relation @ Object`, в FGA — `Object#Relation@User`) | Эмитируется когда |
|---|---|---|
| **anchor tier-tuple (RC-1 fix)** | `<anchorType>:<anchorID>` # `<tier>` @ `<subject>` (напр. `project:prj_P#viewer@user:usr_U`) | ARM_ANCHOR-правило, `objType` ∈ {`account`,`project`}, `objType == anchorType` |
| **member hierarchy-tuple (RC-2 fix)** | `iam_user:<activatedID>` # `account` @ `account:<A>` (FGA-форма: `account:<A>#account@iam_user:<activatedID>`; `service.RelationTuple{User:"account:<A>", Relation:"account", Object:"iam_user:<activatedID>"}`) | активация PENDING-invite — эмитится через `w.EmitFGARelationWrite` в Step-1 writer-tx |
| **personal bootstrap-tuples (RC-5 fix)** | full `bootstrapTuples`-набор (owner/admin grants + `iam_user`/`project`→account hierarchy + cluster-pointers + AB-hierarchy; internal_upsert.go:449–462) на собственных personal `account:<acc>` / `project:<prj>` invitee | bootstrap для invited+activated user, owns-zero-accounts (RC-5 gate) — эмитится через `w.EmitFGARelationWrite` в bootstrap-tx |
| concrete tier-tuple (ARM_NAMES, существует) | `<objType>:<id>` # `<tier>` @ `<subject>` | ARM_NAMES (`resourceNames`) — без изменений, паритет с RC-1 |
| scope_grant carrier (verb-bearing, существует) | `<anchorType>:<anchorID>` # `sg_<objType>` @ `scope_grant:<key>` | ARM_ANCHOR на verb-bearing типе — **НЕ** эмитится для tier-only (RC-1 фикс этого НЕ меняет) |

`<subject>` = `domain.FGASubjectRef(subjectType, subjectID)` (напр. `user:usr_U`). `<tier>` ∈ {`viewer`,`editor`,`admin`} = `domain.ResolveVerbsAndTier(r.Verbs)`.

### 2.2. RC-1 решающая таблица эмиссии (decision table)

| Тип ресурса правила (`objType`) | verb-bearing? | binding scope (`anchorType`) | `objType==anchorType`? | Результат (ДО фикса) | Результат (ПОСЛЕ фикса) |
|---|---|---|---|---|---|
| `project` | нет (tier-only) | `project` | да | **0 tuples** (BUG) | `project:<id>#viewer@subj` |
| `account` | нет (tier-only) | `account` | да | **0 tuples** (BUG) | `account:<id>#viewer@subj` |
| `account` | нет (tier-only) | `project` | нет | 0 tuples | 0 tuples (SKIP сохранён — wrong-direction) |
| `project` | нет (tier-only) | `account` | нет | 0 tuples | 0 tuples (SKIP сохранён) |
| `vpc_network` | да | `project` | n/a | scope_grant + v_* + tier | scope_grant + v_* + tier (**без изменений**) |
| `*` / `*` (wildcard) | n/a | tier-scope | n/a | bare-anchor tier (`anchorTierRelation`) | bare-anchor tier (**без изменений**) |

### 2.3. Стабильные тексты ошибок / коды (часть контракта; не меняются этой таской)

| Поведение | gRPC / HTTP |
|---|---|
| `AccessBinding.Create` happy | `Operation` (async) → `done=true, no error` |
| дубль активной 5-tuple grant | `ALREADY_EXISTS` (409) — strict-create, без изменений |
| `ProjectService.Get(P)` для авторизованного субъекта | `Project` (200) |
| `ProjectService.Get(P)` / `List` без видимости | пусто / `NOT_FOUND`/`PERMISSION_DENIED` per текущая list-фильтрация — **не меняется** этой таской |
| `UpsertFromIdentity` happy (активация) | `Operation` → `done=true`, `metadata.user_id = <existing activated id>`, `created=false` (`created` = создан ли user-identity; personal-account-bootstrap НЕ меняет этот флаг) |
| `UpsertFromIdentity` invitee owns-zero-accounts (RC-5) | то же `Operation` → `done=true`; side-effect — invitee получает собственный personal Account + "default" Project (наблюдаемо через его `AccountService.List` / `ProjectService.List`) |

---

## 3. Integration-сценарии (testcontainers Postgres 16 **+ OpenFGA**)

> Файлы: `internal/apps/kacho/api/access_binding/*_test.go` (emitter-unit на реальной форме tuple-set) и `internal/repo/kacho/pg/*_integration_test.go` (`fga_outbox` co-commit, drain, `Check`/`ListObjects` против реального OpenFGA). RED пишется и прогоняется ДО фикса (ban #12).

### Сценарий T-I1 — emitAnchorRule на tier-only anchor (PRIMARY RC-1) — `positive` + `edge`

**ID:** `T-I1`

**Given** роль `R` с одним ARM_ANCHOR-правилом `{module:"iam", resources:["project"], verbs:["get","list"]}` (нет `resourceNames`, нет `matchLabels`)
**And** binding `B` субъекта `user:usr_U` на роль `R`, scope = **project** (`resourceType="project"`, `resourceID="prj_P"`)

**When** вычисляется emitted-tuple-set этого binding-а (`rulesBindingTuples(B, R)`)

**Then** набор содержит ровно один subject-tuple `project:prj_P # viewer @ user:usr_U` (tier `viewer` из verbs `get/list`)
**And** набор **НЕ** содержит `scope_grant:*` linking-tuple (`sg_project@…`) — tier-only тип не получает scope_grant carrier (#177 guard)
**And** набор **НЕ** содержит `account:*`-tuple и НЕ содержит dangling `sg_*` / `v_*`-write
**And** симметричный кейс: правило `resources:["account"]` на **account**-scoped binding → ровно `account:<accID> # viewer @ user:usr_U`

**And (edge — D-R2 wrong-direction SKIP):** правило `{module:"iam", resources:["account"]}` на **project**-scoped binding → emitted-set по этому правилу **пуст** (0 tuples; `objType="account" != anchorType="project"`), без паники, без dangling-write

### Сценарий T-I2 — AccessBinding.Create end-to-end → outbox → Check/ListObjects (RC-1) — `positive`

**ID:** `T-I2`

**Given** существует project `prj_P` и роль `R` с ARM_ANCHOR-правилом `{module:"iam", resources:["project"], verbs:["get","list"]}`

**When** клиент вызывает `AccessBinding.Create` с payload:
  - `subjectType` = `user`, `subjectId` = `usr_U`
  - `roleId` = `<R.id>`
  - `resourceType` = `project`, `resourceId` = `prj_P`
**And** клиент поллит `OperationService.Get(operationId)` до `done=true`

**Then** `Operation.done=true` без `error`
**And** в `kacho_iam.fga_outbox` (в той же writer-tx, что INSERT binding-а) есть intent-строка с tuple `project:prj_P # viewer @ user:usr_U`
**And** после drain'а: `Check(user:usr_U, viewer, project:prj_P) = True`
**And** `ListObjects(user:usr_U, "viewer", "project")` включает `prj_P`

### Сценарий T-I3 — invite-активация эмитит member hierarchy-tuple co-committed с audit (RC-2) — `positive`

**ID:** `T-I3`

**Given** существует ACTIVE user-инвайтер с account `acc_A`
**And** есть PENDING-invite-row для email `invitee@x` в account `acc_A` (`invite_status='PENDING'`, `account_id='acc_A'`)
**And** новый Kratos identity (`external_id='ext_INV'`) регистрируется этим email-ом (нет ACTIVE-row по `ext_INV`, нет другого PENDING)

**When** вызывается `InternalUserService.UpsertFromIdentity` с `externalId='ext_INV'`, `email='invitee@x'`
**And** клиент поллит `OperationService.Get(operationId)` до `done=true`

**Then** PENDING-row становится ACTIVE (`invite_status='ACTIVE'`, `external_id='ext_INV'`), id сохраняется
**And** в `kacho_iam.audit_outbox` есть `iam.user.updated`-event (changed_fields включает `invite_status`)
**And** в `kacho_iam.fga_outbox` есть intent-строка (`event_type='fga.tuple.write'`) с tuple `account:acc_A # account @ iam_user:<activatedID>`, **закоммиченная в ТОЙ ЖЕ tx, что и `iam.user.updated` audit-event и `ActivateInvite`-UPDATE** — проверяется тем, что обе outbox-строки (`audit_outbox` + `fga_outbox`) появляются атомарно (либо обе, либо ни одной при rollback). Это достижимо ТОЛЬКО через `w.EmitFGARelationWrite` на writer-tx (НЕ через post-commit `relationhook.WriteHierarchyTuple`, который пишет напрямую в OpenFGA после commit и не оставляет `fga_outbox`-строки). Инвариант ban #10: rolled-back Step-1 tx не оставляет ни audit-, ни fga-intent-строки
**And** после drain'а: `Check(iam_user:<activatedID>, account, account:acc_A) = True` (member-ребро существует)
**And (RC-5):** bootstrap **срабатывает** для этого invitee, т.к. он owns-zero-accounts — детально покрыт в T-I5 (этот сценарий фокусируется на RC-2 co-commit; здесь достаточно зафиксировать, что RC-2-эмиссия происходит независимо от bootstrap, в Step-1 writer-tx)

### Сценарий T-I4 — #177 guard + concurrent grant-create CAS (RC-1 safety) — `negative`/`edge`/`concurrency`

**ID:** `T-I4`

**Given** под project `prj_P` есть child-ресурс `vpc_network:net_N` (`vpc_network:net_N#project@project:prj_P`-hierarchy уже существует) + есть **sibling** `project:prj_P2` и `account:acc_A2`, на которые grant НЕ выдавался
**And** субъекту `user:usr_U` выдан anchor-grant `viewer` на `project:prj_P` (через T-I2-путь)

**When** проверяется форма эмиссии и границы grant'а

**Then** (G1) набор эмитнутых tuple **НЕ содержит** `sg_*` (scope_grant carrier) — tier-only тип НЕ получает scope_grant-carrier (это и был источник #177 over-cascade)
**And** (G2) набор **НЕ содержит** `v_*` (per-verb) tuple — emitAnchorRule на tier-only эмитит ТОЛЬКО concrete tier-tuple `project:prj_P#viewer@user:usr_U`
**And** (G3, by-design) `Check(user:usr_U, viewer, vpc_network:net_N)` **= True** — `vpc_network.viewer = … or viewer from project` в канонической FGA-модели, поэтому concrete `project:prj_P#viewer` каскадит `viewer` на child-ресурсы **внутри scope** (НАМЕРЕННАЯ project-viewer-семантика, идентичная ARM_NAMES и legacy-permissions; это НЕ #177 over-cascade — тот был про `scope_grant`-carrier, см. G1)
**And** (G4, scope containment) `Check(user:usr_U, viewer, project:prj_P2)` **= False** И `Check(user:usr_U, viewer, account:acc_A2)` **= False** И `ListObjects(user:usr_U, "viewer", "project")` **НЕ содержит** `prj_P2` — grant НЕ протекает за пределы заякоренного scope на sibling project/account (read==enforce: consumer-`ListObjects` подтверждает границу)

**And (concurrency):** при 8 параллельных goroutine'ах `AccessBinding.Create` с идентичной 5-tuple (`user/usr_U/R/project/prj_P`) ровно **одна** транзакция проходит (`Operation.done`, грант создан), остальные получают `ALREADY_EXISTS` (strict-create partial UNIQUE `access_bindings_active_grant_uniq`); ни в одном исходе нет dangling-tuple / poisoned `fga_outbox`-строки

### Сценарий T-I5 — invite-активация user'а без account → bootstrap fires + RC-2 tuple + ActivateInvite consistent (RC-5) — `positive`/`edge`

**ID:** `T-I5`

**Given** ACTIVE user-инвайтер с account `acc_A`
**And** PENDING-invite-row для email `invitee@x` в account `acc_A` (`invite_status='PENDING'`, `account_id='acc_A'`) — user-row уже существует, но invitee **не владеет** ни одним account-ом (`accounts.owner_user_id == <invitee.id>` count == 0)
**And** новый Kratos identity (`external_id='ext_INV'`) регистрируется этим email-ом

**When** вызывается `InternalUserService.UpsertFromIdentity` с `externalId='ext_INV'`, `email='invitee@x'`
**And** клиент поллит `OperationService.Get(operationId)` до `done=true`

**Then** PENDING-row становится ACTIVE (`ActivateInvite` отработал, id сохранён) — Step-1
**And** RC-5 bootstrap **срабатывает** (новый gate-предикат owns-zero-accounts == true): создан **новый personal Account** (`accounts.owner_user_id = <invitee.id>`, name `personal-cloud-<tail>`) + **"default" Project** под ним + 2 self-admin AccessBinding (account-admin + project-admin на personal-scope) — Step-2
**And** bootstrap **НЕ** делает повторный `InsertActive` (user-row переиспользуется; нет 23505 на UNIQUE(external_id))
**And** в `kacho_iam.fga_outbox` есть intent'ы `bootstrapTuples` для personal-графа (`user:<invitee>#owner@account:<personal>`, `user:<invitee>#admin@account:<personal>`, `user:<invitee>#admin@project:<default>`, `account:<personal>#account@iam_user:<invitee>`, `account:<personal>#account@project:<default>`, cluster-pointers, AB-hierarchy), закоммиченные в bootstrap-tx
**And** RC-2 member-hierarchy-tuple `account:acc_A # account @ iam_user:<invitee>` (членство в account инвайтера) **тоже** эмитирован — в Step-1 writer-tx (см. T-I3); не теряется при срабатывании bootstrap
**And** после drain'а: `Check(user:<invitee>, owner, account:<personal>) = True` (владеет своим account-ом) **И** `Check(iam_user:<invitee>, account, account:acc_A) = True` (member account-а инвайтера) — оба ребра сосуществуют
**And** ровно **один** owned account у invitee (`accounts.owner_user_id == <invitee.id>` count == 1)

---

## 4. Newman e2e-сценарии (black-box через api-gateway)

> Файлы: `tests/newman/cases/iam-*.py` → `validate-cases.py` → `gen.py`. Минимум **1 happy + 1 negative** (ban #12). RED против реального бага fe3455 → known-failing-декларация в `RESULTS.md` «Known failing — product bugs» + GitHub Issue `bug`+`verified-by:test` (ban #13), кейс остаётся красным до фикса прода, затем GREEN.

### Сценарий T-E1 — invite → activate → grant anchor-role on project → invitee видит P и A (RC-1+RC-2) — `positive`

**ID:** `T-E1`

**Given** инвайтер-принципал владеет account `A` (project `P` под `A`)
**And** инвайтер создаёт PENDING-invite на email `invitee@x` (в account `A`)
**And** identity `invitee@x` активируется (registration/login → Kratos provision-hook → `UpsertFromIdentity`); поллинг `OperationService.Get` до `done=true`
**And** инвайтеру/админу выдан anchor-role-грант на invitee: `AccessBinding.Create` `{subjectType:user, subjectId:<invitee>, roleId:<R: ARM_ANCHOR iam.project get,list>, resourceType:project, resourceId:P}` → `Operation` `done=true`

**When** invitee-принципал вызывает `GET /iam/v1/projects` (`ProjectService.List`)
**And** invitee вызывает `GET /iam/v1/projects/P` (`ProjectService.Get`)
**And** invitee вызывает `GET /iam/v1/accounts` (`AccountService.List`)

**Then** `ProjectService.List` содержит `P` (RED pre-fix: список пуст — RC-1)
**And** `ProjectService.Get(P)` = **200** с `id=P`, `accountId=A` (RED pre-fix: not visible)
**And** `AccountService.List` содержит `A` инвайтера (RED pre-fix: пусто — member-ребро RC-2 отсутствовало + grant RC-1)
**And (RC-5):** `AccountService.List` invitee **дополнительно** содержит его **собственный** personal Account (`accounts.owner_user_id = <invitee>`, name `personal-cloud-…`) — RED pre-fix: отсутствует (bootstrap был SKIPPED для invitee)
**And (RC-5):** `ProjectService.List` invitee **дополнительно** содержит собственный "default" Project под personal Account — RED pre-fix: отсутствует
**And (RC-5):** invitee имеет полные права на собственный personal scope: `ProjectService.Get(<personal default project>)` = **200**, `AccountService.Get(<personal account>)` = **200** (self-admin)

### Сценарий T-E2 — scope containment: invitee НЕ видит не-выданный sibling (RC-1 границы) — `negative`

**ID:** `T-E2`

**Given** end-state из T-E1 (invitee имеет grant `viewer` на `project:P` под account `A`)
**And** существует **другой** project `P2` под `A` (без отдельного grant invitee) и **другой** account `A2` (invitee не member)

**When** invitee-принципал вызывает `GET /iam/v1/projects/P2` и `GET /iam/v1/accounts/A2`

**Then** `ProjectService.Get(P2)` НЕ возвращает `P2` invitee (нет grant — `NOT_FOUND`/`PERMISSION_DENIED` per текущая list-фильтрация), `ProjectService.List` invitee НЕ содержит `P2`
**And** `AccountService.Get(A2)` НЕ виден invitee; `AccountService.List` НЕ содержит `A2`
**And** грант на `project:P` НЕ протёк на sibling-ресурсы (vpc/compute) под `P` (наблюдаемо: их List через соответствующий сервис не показывает их invitee)

### Сценарий T-E3 — ARM_NAMES parity с зафиксированным anchor (RC-1 эквивалентность) — `positive`/`edge`

**ID:** `T-E3`

**Given** роль `R_names` с правилом `{module:"iam", resources:["project"], verbs:["get","list"], resourceNames:["P"]}` (ARM_NAMES, без anchor)

**When** invitee получает grant с `R_names` (scope project P) вместо ARM_ANCHOR-роли из T-E1; поллинг до `done`

**Then** `ProjectService.List` invitee содержит `P` и `ProjectService.Get(P)=200` — **тот же** наблюдаемый результат, что у фиксированного ARM_ANCHOR (T-E1): подтверждает, что RC-1 фикс приводит anchor-форму к уже-работающей names-форме (паритет concrete tier-tuple)

### Сценарий T-E4 — идемпотентная re-активация (RC-2 идемпотентность) — `idempotency`/`edge`

**ID:** `T-E4`

**Given** invitee уже активирован один раз (end-state T-E1: один member hierarchy-tuple в account `A`, один ACTIVE-row, **один собственный personal Account + "default" Project** — RC-5)

**When** тот же identity логинится повторно → `UpsertFromIdentity` `{externalId:ext_INV, email:invitee@x}` ещё раз; поллинг до `done`

**Then** `Operation.done=true`, `metadata.created=false`, `metadata.user_id` = тот же activated id
**And (RC-5 идемпотентность):** **НЕ** создан второй personal Account — у invitee остаётся **ровно один** owned account (`accounts.owner_user_id == <invitee>` count == 1): на повторном проходе owns-zero-accounts == false → bootstrap НЕ срабатывает второй раз
**And** НЕ создан второй "default" Project, НЕ задублированы self-admin AccessBinding
**And** invitee по-прежнему остаётся member account-а инвайтера `A` (членство не потеряно)
**And** НЕ появилось дублирующее member hierarchy-ребро (`Check(iam_user:<id>, account, account:A)=True`, ровно одно ребро; повторный intent идемпотентен при drain'е)
**And** наблюдаемая видимость invitee (List проектов/account-ов: personal + inviter's granted) идентична состоянию до повторной активации

---

## 5. Coverage / traceability matrix

| ID | Уровень | RC | Тип | Что проверяет | Файл-таргет (имя теста трассируется по ID) |
|---|---|---|---|---|---|
| **T-I1** | integration (emitter+FGA) | RC-1 | positive + edge | `emitAnchorRule` tier-only → concrete tier-tuple на anchor; symmetric account; wrong-direction SKIP; нет `sg_*`/`account:*`/dangling | `internal/apps/kacho/api/access_binding/*_test.go` |
| **T-I2** | integration (Postgres+OpenFGA) | RC-1 | positive | `AccessBinding.Create`→`fga_outbox`→drain→`Check`+`ListObjects(viewer,project)` | `internal/repo/kacho/pg/*_integration_test.go` |
| **T-I3** | integration (Postgres+OpenFGA) | RC-2 | positive | activate-invite co-commit member-tuple + audit в ОДНОЙ tx через `EmitFGARelationWrite` (`fga_outbox`+`audit_outbox` атомарны); `Check(account)` | `internal/repo/kacho/pg/*_integration_test.go` |
| **T-I4** | integration (OpenFGA + Postgres CAS) | RC-1 | negative + concurrency | #177 guard (нет cascade на sibling verb-bearing) — `Check` И `ListObjects(viewer,vpc_network)`; concurrent grant-create CAS зелёный | `internal/apps/kacho/api/access_binding/*_test.go` + `*_integration_test.go` |
| **T-I5** | integration (Postgres+OpenFGA) | RC-5 | positive + edge | invite-activate user owns-zero-accounts → bootstrap fires (personal Account + "default" Project + self-admin + `bootstrapTuples`) + ActivateInvite + RC-2 inviter-tuple — все consistent; no 2nd `InsertActive` | `internal/repo/kacho/pg/*_integration_test.go` |
| **T-E1** | newman e2e | RC-1+RC-2+RC-5 | positive | invite→activate→grant→invitee видит P + A инвайтера **И** собственный personal Account + "default" Project | `tests/newman/cases/iam-*.py` |
| **T-E2** | newman e2e | RC-1 | negative | scope containment — не-выданный sibling project/account невидим | `tests/newman/cases/iam-*.py` |
| **T-E3** | newman e2e | RC-1 | positive + edge | ARM_NAMES ≡ fixed ARM_ANCHOR (паритет) | `tests/newman/cases/iam-*.py` |
| **T-E4** | newman e2e | RC-2+RC-5 | idempotency + edge | re-активация: нет дубль member-tuple, **ровно один** owned personal account (нет второго bootstrap) | `tests/newman/cases/iam-*.py` |

**Покрытие 7 обязательных классов:** happy (T-I2/T-I3/T-I5/T-E1/T-E3) · invalid-input n/a (фикс — emit-логика + gate-предикат, не новый input-валидатор; existing reject-пути не меняются) · not-found (T-E2) · precondition (n/a — grant strict-create уже покрыт) · idempotency (T-E4 + T-I3 re-activate + T-I5/T-E4 single personal account) · concurrency (T-I4 CAS) · cross-service ref (n/a — FGA emit внутри iam; consumer `ListObjects` — T-I2/T-I4/T-E1). RC-1 + RC-2 + RC-5 (fixed-was-D-R7) покрыты явно.

---

## RC-4 — deploy/CI follow-up (НЕ часть code-acceptance)

> Утверждается явно, чтобы RC-1/RC-2 верифицировались против **корректной** FGA-модели и not-false-positive.

fe3455 крутит **stale FGA-model revision**, в которой account/project имеют cascade `viewer from cluster`, а cluster-ребро резолвится через `user:*` wildcard → `Check(viewer)=True` даже при **нуле** subject-tuples (false-positive, маскирует RC-1). Лечится **операционно**, НЕ кодом этой таски:
1. **Re-bootstrap** OpenFGA-store на корректную (current) model-revision (deploy-шаг при выкатке фикса).
2. **Model-revision drift-assertion** (CI/deploy-гейт): задеплоенная FGA-model-revision == ожидаемой из `fga_model.fga` (kacho-proto) — чтобы stale-model не маскировал authz-баги впредь. Заводится отдельным GitHub Issue (`tech-debt`/`enhancement`) в `kacho-deploy`/`kacho-workspace` + строкой в KAC-trail.

Integration-сценарии T-I1..T-I4 гоняются на **свежем** OpenFGA-контейнере с current-model (testcontainers), поэтому RC-4 их не затрагивает; newman T-E1 на стенде требует выполненного шага 1 (re-bootstrap), иначе RED-причина смешается с RC-4 — отмечается в `RESULTS.md`.

---

## 6. Definition of Done (DoD)

- [ ] **Acceptance APPROVED** — `acceptance-reviewer` ✅ (этот документ; ban #1).
- [ ] **RED first (ban #12):** T-I1..T-I5 + T-E1..T-E4 написаны и прогнаны КРАСНЫМИ ДО фикса; RED-причина зафиксирована (RC-1: 0 tuples / список пуст; RC-2: member-tuple отсутствует / нет `fga_outbox`-строки в Step-1 tx; RC-5: invitee owns-zero-accounts, bootstrap SKIPPED → нет personal account). Пара RED→GREEN в PR/отчёте.
- [ ] **RC-1 фикс:** `emitAnchorRule` (scope_grant_tuples.go) — tier-only `objType==anchorType` эмитит concrete tier-tuple на anchor (D-R1); mismatched сохраняет SKIP (D-R2); нет `sg_*`/dangling (D-R3).
- [ ] **RC-2 фикс:** activate-invite (internal_upsert.go doUpsert Step 1) — `w.EmitFGARelationWrite(ctx, []service.RelationTuple{{User:"account:<A>", Relation:"account", Object:"iam_user:<activatedID>"}})` co-committed в Step-1 writer-tx рядом с `ActivateInvite` + `EmitAuditEvent`, до `Commit` (D-R5; **НЕ** `relationhook.WriteHierarchyTuple`); идемпотентно (D-R6).
- [ ] **RC-5 фикс (переворачивает прежний by-design D-R7):** gate в `doUpsert` (internal_upsert.go:257) меняется на «owns-zero-accounts» (новый read-метод над `accounts.owner_user_id`); bootstrap personal Account + "default" Project + self-admin AB + `bootstrapTuples` срабатывает для invited+activated user без owned-account, переиспользуя существующий user-row (без повторного `InsertActive`); идемпотентно — ровно один personal account (D-R7).
- [ ] **НЕТ migration / НЕТ proto / НЕТ FGA-model change / НЕТ api-gateway change** (D-R4) — single-repo `kacho-iam`. RC-5 добавляет только новый read-метод над существующей колонкой `accounts.owner_user_id` (не новая таблица/колонка → миграции нет).
- [ ] **GREEN:** T-I1..T-I5 + T-E1..T-E4 зелёные; `go test ./... -race`, `golangci-lint run`, `govulncheck`, `make audit-list-filter` зелёные; newman зелёные (после RC-4 re-bootstrap на стенде).
- [ ] **Ревью ролями:** `system-design-reviewer` (FGA cascade / #177 safety / outbox at-least-once-идемпотентность / RC-5 gate-предикат + activate-then-bootstrap ordering), `db-architect-reviewer` (Step-1 writer-tx co-commit `fga_outbox`+`audit_outbox` через `EmitFGARelationWrite`; owns-zero-accounts read-метод; RC-5 re-activate не создаёт 2-й account), `go-style-reviewer` (thin emit, переиспользование `bootstrapTuples`-builder).
- [ ] **RC-4 follow-up Issue** заведён (re-bootstrap + model-drift-gate) и привязан; НЕ блокирует merge code-фикса, но требуется до live-верификации newman.
- [ ] **Trail:** vault обновлён (`edges/`-запись про grant-emission / member-tuple, `rpc/iam-*` если затронут контракт-комментарий, `KAC/KAC-<N>.md`) + тикет Test→Done с артефактами (PR-URL, RED→GREEN-лог).
