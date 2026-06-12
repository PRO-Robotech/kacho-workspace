# Sub-phase SEC-L — Operator FGA system-viewer (AccountService.List + ProjectService.List relation-driven)

**Status:** DRAFT — awaiting `acceptance-reviewer` APPROVED gate (ban #1). **Revision 2** —
addresses the blocking over-exposure defect (cascade source changed from `viewer` to the
non-wildcard `system_viewer`; fail-closed contract made binding; subject-prefix fix made an
explicit RED→GREEN line item).
**Type:** security / authz · cross-repo (kacho-proto · kacho-iam · kacho-deploy) · feature.
**Author role:** `acceptance-author`.
**Date:** 2026-06-12.
**Related:** SEC-C (migration 0009 — module-SA least-priv seed; the byte-for-byte template),
SEC-G (kacho-vpc-operator ns-syncer), RBAC-v2 / KAC-214 (already-FGA-driven `ProjectService.List`),
KAC-127 (FGA model v2).

---

## 1. Контекст и постановка задачи

### 1.1 Симптом (production-level)

`kacho-vpc-operator` (ns-syncer / project-operator) синхронизирует Kubernetes-namespace на
**каждый tenant-Project**. Чтобы материализовать ns, оператор перебирает все Account → все
Project через публичный read-API IAM (`AccountService.List` → `ProjectService.List`,
fan-out). Оператор аутентифицируется как persona-SA
`service_account:'sva'||substr(md5('kacho-vpc-operator'),1,17)` (seed migration 0009, SEC-C).

Этот SA **не владеет ни одним Account** (`accounts.owner_user_id != <operator SA>`) и **не
имеет ни одного viewer-grant** на Project. Поэтому:

- `AccountService.List` возвращает **0 accounts** (Go-фильтр по `owner_user_id == principal.ID`).
- `ProjectService.List` возвращает **0 projects** (FGA `ListObjects(viewer, project)` → пустой
  набор, fallback owner-only → тоже пусто).

Итог: оператор **никогда не материализует** namespace ни одного tenant-Project. Это
не-функционирующая фича операторского fan-out.

### 1.2 Root cause (verbatim ground-truth)

| Файл | Текущее поведение | Проблема |
|---|---|---|
| `kacho-iam/internal/apps/kacho/api/account/list.go` (`ListAccountsUseCase.Execute`, строки ~47-57) | Загружает страницу, затем Go-post-filter: `string(a.OwnerUserID) == principal.ID`. | Чисто owner-scoped. Никакого FGA. SA-оператор → 0. |
| `kacho-iam/internal/apps/kacho/api/project/list.go` (`ListProjectsUseCase.Execute`) | UNION (owner-через-Account) ∪ (FGA `ListObjects(subject,"viewer","project")`). Subject хардкожен `"user:" + principal.ID` (строка 79). FGA-outage → **silent degrade** к owner-only (строки 86-89). | (1) SA-оператор шлёт `service_account:<id>`, но запрос уходит как `user:<id>` → FGA не резолвит → 0. (2) silent degrade — НЕ контрактный fail-closed (см. INV-7 / сценарий F). |

### 1.3 Выбранное решение (user-approved): FGA system-viewer

Сделать **оба** list use-case **FGA-relation-driven**: каждый зовёт
`ListObjects(principalSubject, "viewer", "account" | "project")` и возвращает только те
object-id, на которые у principal есть relation `viewer`. Оператор-SA получает
cluster-level read-only relation так, что — и **только** он — видит **ВСЕ** Account/Project.
Обычный USER по-прежнему видит **только свои** (cascade `owner → admin → editor → viewer`,
уже в модели) — с **нулевым** over-exposure.

### 1.4 КРИТИЧЕСКАЯ security-коррекция vs наивный дизайн (фикс blocking-дефекта rev.1)

Наивная правка «`account.viewer += or viewer from cluster`» — это **массовый пробой
tenant-isolation** и здесь **отклонена**. Ground-truth `fga_model.fga` строка 80:

```
type cluster
  relations
    define viewer: [user, user:*, service_account] or system_viewer or any_admin
```

`cluster.viewer` содержит **wildcard `user:*`** (любой authenticated `user:`-principal его
удовлетворяет — by design, для tenant-facing reference-data типа Region/Zone). Если бы
`account.viewer` наследовал `or viewer from cluster`, то **каждый authenticated user**
резолвил бы `viewer@cluster:cluster_kacho_root` и получал `viewer` на **каждом** account c
ребром `account#cluster` → сценарий D (u1 НЕ должен видеть a2) падает в проде. Это и есть
нарушение INV-1 / INV-D.

**Фикс:** наследоваться через cluster-relation, которую **не удовлетворяет ни один `user:*`
userset**. Ground-truth строка 68: `cluster.system_viewer = [user, service_account]` — **без
wildcard, только direct-assignment**. Источник cascade становится **`system_viewer from
cluster`**, а оператор сидируется **`system_viewer@cluster`** (НЕ `viewer@cluster`). Output-
relation, который запрашивает `ListObjects`, остаётся `"viewer"` (чтобы `system_viewer`
оператора резолвился в `account.viewer`/`project.viewer`, а `owner` обычного юзера —
по-прежнему в `viewer` внутри account'а). Путь через `user:*` в подтипы account/project
никогда не вводится.

---

## 2. Точные изменения (нормативные требования к реализации)

> Реализация строгим TDD (ban #12): RED-тест ДО кода. Кросс-репо порядок (polyrepo.md):
> **kacho-proto → kacho-iam → kacho-deploy/docs**. api-gateway не затрагивается (контракт RPC
> не меняется).

### 2.1 FGA authorization model (kacho-proto `fga_model.fga`)

**Файл:** `kacho-proto/proto/kacho/cloud/iam/v1/fga_model.fga` (канонический источник;
Helm-configmap регенерируется `make openfga-model-json` → `gen-openfga-model-configmap.py`).

Добавить **non-wildcard** cluster→account и cluster→project read-cascade.

**`type account`** — добавить cascade к существующему `viewer` (relation `cluster` уже есть,
строка 112):

```
type account
  relations
    define cluster: [cluster]                       # уже есть
    define organization: [organization]
    define owner: [user]
    define admin: [user, service_account, group#member] or any_admin from cluster or admin from organization or owner
    define editor: [user, service_account, group#member] or admin or editor from organization
    # ИЗМЕНЕНИЕ: добавить `or system_viewer from cluster` (НЕ-wildcard источник cascade).
    # НЕ `or viewer from cluster` — иначе wildcard user:* из cluster.viewer протащит viewer
    # на КАЖДЫЙ account → массовое over-exposure (нарушение INV-1/INV-D).
    define viewer: [user, service_account, group#member] or editor or viewer from organization or system_viewer from cluster
    define billing_admin: [user, service_account] or admin or billing_admin from organization
```

**`type project`** — добавить parent-pointer relation `cluster` + тот же non-wildcard cascade
(сейчас project парентится только к account):

```
type project
  relations
    define account: [account]
    define cluster: [cluster]                        # НОВЫЙ parent-pointer
    define admin: [user, service_account, group#member] or admin from account
    define editor: [user, service_account, group#member] or admin or editor from account
    # ИЗМЕНЕНИЕ: добавить `or system_viewer from cluster` (НЕ-wildcard источник cascade).
    define viewer: [user, service_account, group#member] or editor or viewer from account or system_viewer from cluster
```

**Почему `system_viewer from cluster` безопасен (INV-6, ground-truth строка 68):**

```
type cluster
  relations
    define system_viewer: [user, service_account]    # НЕТ user:* — только direct-assignment
    ...
    define viewer: [user, user:*, service_account] or system_viewer or any_admin   # ЕСТЬ user:* — НЕ используется как источник cascade
```

Principal резолвит `viewer@account:<id>` через новое ребро **iff** он член
`system_viewer@cluster:cluster_kacho_root`. Direct-subject-набор `system_viewer` —
`[user, service_account]` **без wildcard**, поэтому произвольный `user:<rando>`, которому
`system_viewer` не выдавали, **не** матчится — ровно то, что требуют INV-1/INV-D. Оператор-SA,
сидированный `service_account:<op>#system_viewer@cluster:cluster_kacho_root` (§2.2), **матчится**
→ резолвит `viewer` на каждом account/project с ребром `#cluster` (§2.3/§2.4).

Семантика `owner`/`admin`/`editor`/`viewer` для пользователей не меняется: `owner@account`
по-прежнему cascade'ит `owner → admin → editor → viewer` внутри account'а, поэтому
`ListObjects(user:<owner>, "viewer", "account")` по-прежнему возвращает свои accounts.

**Про `system_viewer` и `user:*`:** `cluster.viewer` уже ссылается на `system_viewer`
(`... or system_viewer or any_admin`), но сам `system_viewer` не содержит `user:*`, поэтому
введение `system_viewer from cluster` на account/project **не** протаскивает транзитивно тот
`user:*`, что живёт только в собственном direct-subject-списке `cluster.viewer`. Wildcard
`user:*` заперт в `cluster.viewer` и до подтипов account/project не доходит.

**Запрещённые альтернативы:**
- НЕ `or viewer from cluster` на account/project (тянет `user:*` → massive over-exposure).
- НЕ добавлять `user:*` в `account.viewer`/`project.viewer`.
- НЕ давать оператору `editor`/`admin`-cascade (`editor from cluster`/`admin from cluster`).
- НЕ трогать `owner`/`admin`/`editor`-семантику пользователей (parity).
- НЕ расширять на per-domain ресурсы (vpc_*/compute_*) — scope только account+project.

### 2.2 Новая миграция 0010 — seed operator `system_viewer@cluster` tuple (kacho-iam)

**Файл:** `kacho-iam/internal/migrations/0010_sec_l_operator_system_viewer.sql`
(применены 0001..0009 → следующая = **0010**; ban #5: применённую 0009 не редактировать).
**Зеркалит механику 0009 §5 byte-for-byte** (FGA-tuple через `fga_outbox`, drainer применяет
идемпотентно; тот же payload-shape, тот же `ON CONFLICT DO NOTHING`):

```sql
-- +goose Up
-- +goose StatementBegin
-- SEC-L: seed operator SA `system_viewer@cluster:cluster_kacho_root` relation-tuple, чтобы
-- AccountService.List/ProjectService.List (FGA-relation-driven) вернули ВСЕ accounts/projects
-- ns-syncer'у kacho-vpc-operator (read-only catalog viewer). NON-wildcard relation
-- (system_viewer) — обычный user:* principal НИКОГДА её не удовлетворит (INV-6).
INSERT INTO kacho_iam.fga_outbox (event_type, payload, created_at) VALUES
  ('fga.tuple.write',
   jsonb_build_object(
     'user',     'service_account:' || ('sva' || substr(md5('kacho-vpc-operator'), 1, 17)),
     'relation', 'system_viewer',
     'object',   'cluster:cluster_kacho_root'),
   now())
ON CONFLICT DO NOTHING;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DELETE FROM kacho_iam.fga_outbox
 WHERE payload->>'relation' = 'system_viewer'
   AND payload->>'object'   = 'cluster:cluster_kacho_root'
   AND payload->>'user'     = 'service_account:' || ('sva' || substr(md5('kacho-vpc-operator'), 1, 17));
-- +goose StatementEnd
```

- Operator SA-id — то же детерминированное выражение, что и 0009
  (`'sva'||substr(md5('kacho-vpc-operator'),1,17)`) → гарантия совпадения subject'а.
- Сама строка operator-SA уже есть (0009 §2) — пересидировать не нужно.
- Объект — singleton `cluster:cluster_kacho_root` (тот же root, что SEC-C AccessBindings;
  write-side единственный cluster-объект, P3-D17).
- `relation = 'system_viewer'` (НЕ `'viewer'`) — это и есть фикс blocking-дефекта.

### 2.3 account.Create — write parent-tuple `account#cluster@cluster:cluster_kacho_root`

**Файл:** `kacho-iam/internal/apps/kacho/api/account/create.go` (`doCreate`, post-commit
hook рядом с существующим owner-tuple). Сейчас `doCreate` пишет только owner-tuple
(`user:<owner>#owner@account:<id>`). Добавить **второй** non-fatal post-commit write — ребро
hierarchy от cluster-root, чтобы `system_viewer from cluster` (§2.1) имел путь резолва:

```
account:<id>#cluster@cluster:cluster_kacho_root
```

Реализация — второй вызов `fgahook.WriteHierarchyTuple`, та же non-fatal / log-on-failure /
never-rollback семантика (row уже закоммичен), parity с project→account writer:

```go
// существующий owner-tuple (без изменений):
fgahook.WriteHierarchyTuple(ctx, u.fga, u.logger,
    "user", string(created.OwnerUserID), "owner", "account", string(created.ID))
// НОВОЕ ребро cluster parent-pointer:
fgahook.WriteHierarchyTuple(ctx, u.fga, u.logger,
    "cluster", "cluster_kacho_root", "cluster", "account", string(created.ID))
```

(`WriteHierarchyTuple(parentType, parentID, relation, childType, childID)` →
`childType:childID#relation@parentType:parentID` = `account:<id>#cluster@cluster:cluster_kacho_root` ✓.)

### 2.4 project.Create — write parent-tuple `project#cluster@cluster:cluster_kacho_root`

**Файл:** `kacho-iam/internal/apps/kacho/api/project/create.go` (`doCreate`). Сейчас пишет
только `project:<id>#account@account:<account_id>`. Добавить второй non-fatal write — ребро
cluster parent-pointer (нужно новому relation `cluster` у project, §2.1):

```go
// существующий project→account-tuple (без изменений):
fgahook.WriteHierarchyTuple(ctx, u.fga, u.logger,
    "account", string(created.AccountID), "account", "project", string(created.ID))
// НОВОЕ ребро cluster parent-pointer:
fgahook.WriteHierarchyTuple(ctx, u.fga, u.logger,
    "cluster", "cluster_kacho_root", "cluster", "project", string(created.ID))
```

**Замечание про существующие данные (операционное, не контрактное):** accounts/projects,
созданные **до** SEC-L, не имеют ребра `#cluster`, поэтому оператор их не увидит до back-fill.
Оператору нужно материализовать ns только для project'ов going-forward; one-shot back-fill
`#cluster`-tuples для pre-existing accounts/projects — **операционный follow-up** (вне scope
acceptance): если потребуется — отдельный admin-job, НЕ миграция, редактирующая 0009. Новые
accounts/projects (сценарий E) видны на следующем reconcile.

### 2.5 ListAccountsUseCase / ListProjectsUseCase — FGA-relation-driven (kacho-iam)

`ListAccountsUseCase` получает optional FGA-port `clients.CheckExtensions` через
`WithOpenFGA(...)` (зеркало того, как это уже сделано в `ListProjectsUseCase`).

**Subject construction (нормативно, фиксит баг §2.6):**

```
principalSubject =
    "user:"            + principal.ID   если principal.Type == "user"
    "service_account:" + principal.ID   если principal.Type == "service_account"
```

**Алгоритм фильтра:**

1. `IsAnonymous(ctx)` → empty (INV-3, существующий early-return — ДО любого FGA-вызова).
2. Загрузить страницу из repo (существующая pagination).
3. Резолвить visible-id-набор: `ids := fga.ListObjects(ctx, principalSubject, "viewer", "account", nil, 0)`.
4. Оставить только rows, чей `id ∈ ids`.
5. Вернуть отфильтрованную страницу + next-token.

**Про owner-relation (post-redesign, INV-1):** модель резолвит `owner → admin → editor →
viewer` **внутри account'а**, поэтому owned-accounts юзера входят в
`ListObjects(user:<owner>, "viewer", "account")` — существующий owner-tuple
(`user:<owner>#owner@account:<id>`, пишется `account.Create`) уже это даёт. Поэтому redesign
§2.6 **не** требует owner-specific Go-fallback; видимость юзера = ровно «owned ∪
AccessBinding-granted», вычисляется FGA. **НЕ возвращать repo-side widener
`OwnerUserID == principal.ID`** — FGA-`viewer`-набор есть единственный источник истины (это
держит INV-1 туго и не вводит wildcard-путь).

**Fail-closed контракт (INV-7, нормативно — обязателен для ОБОИХ use-case'ов): выбран F-b.**
При ошибке `ListObjects` (FGA outage / timeout / non-200) use-case возвращает `Unavailable`
(`shared`-mapped `ErrUnavailable` → gRPC `UNAVAILABLE`), **не** degraded owner-only список и
**не** full-список. Обоснование: для любого principal, чья видимость FGA-derived (здесь — все,
включая owner'ов), silent degrade — это либо leak-риск, либо under-report, который введёт
оператора в заблуждение. `UNAVAILABLE` — fail-closed-сигнал, уже принятый в проекте для
недостижимых authority-peer'ов.

- Anonymous по-прежнему short-circuit'ит в empty **до** любого FGA-вызова (INV-3 сохранён —
  FGA-outage не превращает anonymous-запрос в `UNAVAILABLE`).
- **Оператор-под-outage:** оператор-SA получает `UNAVAILABLE`, НЕ пустой список. Это
  намеренно — чтобы пустой результат **никогда** нельзя было принять за «project'ов нет» и
  запустить prune-путь ns-оператора. Задокументированное fail-closed-поведение ns-syncer'а
  (трактовать `UNAVAILABLE` как «retry, не prune») — это cross-ref-страховка; SEC-L не должен
  отдавать оператору пустой-но-OK список во время FGA-outage.

`ProjectService.List` привязан к **тому же** F-b контракту: заменить текущий non-fatal silent
degrade (строки 86-89) на возврат `Unavailable` при ошибке `ListObjects`. (Существующий
owner-account union в `project/list.go` — это intra-account ownership-резолюция и не
затрагивается, но FGA-ветка обязана fail-closed.)

### 2.6 Subject-prefix фикс (нормативно, RED→GREEN в ЭТОМ PR)

Это **прод-код-фикс** (не test-only — ban #13 НЕ применим; это feature-PR):

- `project/list.go` строка 79 хардкодит `subject := "user:" + principal.ID`. Для
  `service_account`-principal'а уходит `user:sva…`, который FGA не резолвит → оператор получает
  0 даже с tuple §2.2. **Фикс:** выводить префикс из `principal.Type` (§2.5 subject
  construction).
- `account/list.go` (новая FGA-ветка) с самого начала использует корректный префикс.

**DoD-пункт (явная RED→GREEN пара, ОБА use-case'а):** падающий unit-тест, ассертящий
**точную subject-строку**, доходящую до (mock) `ListObjects`: `service_account:<id>` для
SA-principal'а и `user:<id>` для user-principal'а — один для `account/list.go`, один для
`project/list.go`. RED до фикса, GREEN после.

### 2.7 In-memory stub — реализовать `CheckExtensions.ListObjects` (kacho-iam, test-only)

**Файл:** `kacho-iam/internal/clients/openfga_stub_test.go` (`OpenFGAStubClient`). Сейчас stub
реализует только `OpenFGAClient` (Check/Write/Delete). Добавить реализацию `ListObjects` (и
остальные методы `CheckExtensions` как минимальные no-op / empty / `ErrNotConfigured`,
достаточные для удовлетворения интерфейса) — чтобы unit-тесты use-case'ов детерминированно
драйвили FGA-фильтр. Stub должен давать тесту предзагрузить «subject X имеет viewer на
объектах {…}» и возвращать этот набор из `ListObjects(X, "viewer", "account"|"project")`. (Stub
в `_test.go` — в прод-бинарь не линкуется; прод-wiring строит `OpenFGAHTTPClient` и fail-fast'ит
без store-id.) Compile-time assertion: `var _ clients.CheckExtensions = (*OpenFGAStubClient)(nil)`.

### 2.8 Регенерация openfga-model-stub configmap (kacho-deploy)

После правки канонического `fga_model.fga` регенерировать
`kacho-deploy/helm/umbrella/templates/openfga-model-stub-configmap.yaml` через
`make openfga-model-json` (вызывает `gen-openfga-model-configmap.py`), чтобы bootstrap-job-
модель осталась byte-for-byte в синке с каноническим DSL. Configmap руками не редактировать.

---

## 3. Критические инварианты (security — нарушение = reject)

| # | Инвариант | Сценарий | Почему критичен |
|---|---|---|---|
| **INV-1** | **USER видит ТОЛЬКО свои** Account/Project (owned ∪ explicitly-granted). Никогда чужие. | A, D | Over-exposure tenant-данных = security-инцидент. |
| **INV-2** | **Operator SA** (`system_viewer@cluster:cluster_kacho_root`) видит **ВСЕ** Account/Project, read-only. | B, E | Без этого фича не работает (ns-fan-out пуст). |
| **INV-3** | **Anonymous / empty / bootstrap-fallback** видит **none** (пустой список, OK-статус). | C | default-deny, без disclosure existence. |
| **INV-4** | Operator SA — **read-only**: seed даёт только `system_viewer` (read-relation); нет editor/admin/owner, нет mutation-пути. | B, G | least-privilege; viewer ≠ writer. |
| **INV-5** | Контракт RPC `AccountService.List` / `ProjectService.List` **не меняется** (request/response/REST/pagination/filter). | H | Это не новый RPC — смена authz-источника фильтра. |
| **INV-6** | Источник нового cluster→account/project cascade — `system_viewer from cluster` — relation, которую **не удовлетворяет ни один `user:*` userset**; `user:*`-несущий `cluster.viewer` НЕ источник cascade для account/project. | D, §5.4 | Защита от массового over-exposure через wildcard. |
| **INV-7** | При недоступности FGA list-путь **fail-closed** per §2.5 (нет full-list leak; нет silent owner-fallback, который мог бы вернуть non-owned rows). | F | Read-authz fail-closed; деградация безопасна. |

---

## 4. Сценарии Given-When-Then

### Сценарий A (positive, baseline-unchanged) — USER видит только свои (INV-1)

```
Given accounts a1 (owner u1) и a2 (owner u2) существуют
  And каждый несёт account:<id>#cluster@cluster:cluster_kacho_root (записан на Create)
  And модель имеет account.viewer ... or system_viewer from cluster
 When u1 вызывает AccountService.List (principal=user:u1)
 Then ответ содержит a1
  And ответ НЕ содержит a2
  And то же для ProjectService.List: u1 видит p1, не p2
```

### Сценарий B (positive, core feature) — Operator SA видит ВСЕ (INV-2 + INV-4)

```
Given a1, a2 существуют (owners u1, u2), каждый с #cluster parent-tuple
  And opSA сидирован service_account:<op>#system_viewer@cluster:cluster_kacho_root (миграция 0010, drained)
 When opSA вызывает AccountService.List
 Then ответ содержит И a1, И a2 (все accounts)
  And когда opSA вызывает ProjectService.List — содержит И p1, И p2 (все projects)
  And subject ушёл в FGA как "service_account:<op>" (НЕ "user:<op>") — иначе 0 (§2.6)
  And opSA НЕ имеет editor/admin/owner relation (read-only; мутации остаются denied — сценарий G)
```

### Сценарий C (edge) — Anonymous → none (INV-3)

```
Given anon (authzguard.IsAnonymous(ctx) == true)
 When anon вызывает AccountService.List (resp. ProjectService.List)
 Then ответ — пустой список, статус OK
  And FGA ListObjects НЕ вызывается (short-circuit ДО FGA)
```

### Сценарий D (negative, CRITICAL over-exposure guard) — USER НЕ видит чужой (INV-1 + INV-6)

```
Given a1 (owner u1) и a2 (owner u2), каждый с #cluster parent-tuple
  And model-правка `account.viewer ... or system_viewer from cluster` развёрнута
  And u1 НЕ имеет grant на a2 и НЕ является system_viewer@cluster
 When u1 вызывает AccountService.List
 Then ответ содержит a1
  And ответ НЕ содержит a2
  And та же изоляция для ProjectService.List (u1 никогда не видит p2)
  And это держится ИМЕННО ПОТОМУ, что источник cascade — system_viewer (без user:*),
      а не user:*-несущий cluster.viewer — см. §5.4 model-conformance assertion
```

> INV-1/INV-6 регрессионный якорь: правка модели НЕ должна сделать a2 видимым для u1.
> Stub-уровень это поймать НЕ может (leak живёт в FGA-резолюции) — обязателен §5.4.

### Сценарий E (edge, propagation) — новый Account/Project виден оператору на следующем reconcile (INV-2)

```
Given opSA — system_viewer@cluster (drained)
 When u1 создаёт новый account a3 (Create → committed, account:a3#cluster@cluster:cluster_kacho_root записан non-fatally)
  And FGA-tuple спропагирован (post-commit hook применён)
 When opSA вызывает AccountService.List
 Then ответ содержит a3
  And после того как u1 создаёт project p3 в a3 (project:p3#cluster + project:p3#account записаны),
      ProjectService.List оператора содержит p3 на следующем poll
```

### Сценарий F (negative, fail-closed) — FGA недоступен → fail-closed (INV-7)

```
Given FGA ListObjects ошибается (outage / timeout / non-200)
 When authenticated principal (u1 ИЛИ opSA) вызывает AccountService.List или ProjectService.List
 Then use-case возвращает UNAVAILABLE (gRPC code 14)
  And НЕ возвращает full-список
  And НЕ degrade'ит silent'но к owner-only списку
 And когда anon вызывает во время того же outage
 Then anon по-прежнему получает empty/OK (short-circuit ДО FGA — outage не меняет anon-путь)
 And оператор трактует UNAVAILABLE как «retry, не prune» (cross-ref fail-closed prune ns-syncer'а)
```

### Сценарий G (negative, least-priv) — Operator SA не может мутировать (INV-4)

```
Given opSA — system_viewer@cluster (read-only)
 When opSA пытается AccountService.Create / Update / Delete (или Project-эквиваленты)
 Then результат ТОТ ЖЕ, что до SEC-L (никакой новой mutation-capability)
  And seed добавляет только read-relation; никакого editor/admin/owner-tuple для opSA не пишется
```

> Покрывается существующими authz-гейтами Create/Update/Delete + FGA editor/admin cascade
> (`account.editor`/`account.admin` наследуют `any_admin from cluster`, НЕ `system_viewer from
> cluster`, и НЕ `viewer from cluster`). Регрессия не ожидается; тест-якорь.

### Сценарий H (conformance) — контракт не меняется (INV-5)

```
Given изменение SEC-L развёрнуто
 When клиент вызывает AccountService.List / ProjectService.List с идентичным запросом
      (page_size, page_token, filter=name=…)
 Then shape ответа, REST-путь, pagination-токены и filter-семантика byte-for-byte
      идентичны pre-SEC-L (различается только НАБОР rows на principal)
```

---

## 5. Тесты (TDD — RED до кода, ban #12; в том же PR)

### 5.1 Unit — use-case (`kacho-iam/internal/apps/kacho/api/{account,project}/list_test.go`)

Драйв через in-memory stub (§2.7) с `ListObjects`:

- **A-unit** — u1, stub `ListObjects(user:u1,"viewer","account") = {a1}` →
  `AccountService.List` возвращает только `{a1}`. Зеркало для projects.
- **B-unit** — opSA, stub `ListObjects(service_account:op,"viewer","account") = {a1,a2}` → оба.
- **C-unit** — anon → empty, И ассерт что `ListObjects` **не вызывался**.
- **D-unit** — u1, stub возвращает `{a1}` (НЕ a2) → ответ исключает a2 (use-case-уровень;
  model-уровень leak ловит §5.4).
- **F-unit** — stub `ListObjects` → error → use-case возвращает `UNAVAILABLE` (НЕ full-список,
  НЕ owner-fallback). Отдельный кейс: anon во время outage → по-прежнему empty.
- **B (subject-prefix) RED→GREEN, ОБА use-case'а** — ассерт **точной** subject-строки в stub:
  `service_account:<id>` для SA, `user:<id>` для user. RED против текущего хардкода `"user:"`
  (project) и против отсутствующей FGA-ветки (account); GREEN после §2.6.

### 5.2 Integration — миграция (`kacho-iam/internal/repo/.../*integration_test.go`, testcontainers)

- Применить миграции до 0010; ассерт `fga_outbox`-row с `payload->>'relation' = 'system_viewer'`,
  `payload->>'object' = 'cluster:cluster_kacho_root'`,
  `payload->>'user' = 'service_account:'||('sva'||substr(md5('kacho-vpc-operator'),1,17))`.
- Re-apply (идемпотентность) → ровно одна такая outbox-row (`ON CONFLICT DO NOTHING`).
- Down-миграция её удаляет. 0009 не тронута.

### 5.3 Integration — Create пишет cluster parent-tuple

- `account.Create` happy → ассерт FGA-writer (stub/spy) получил
  `account:<id>#cluster@cluster:cluster_kacho_root` (в дополнение к owner-tuple).
- `project.Create` → ассерт `project:<id>#cluster@cluster:cluster_kacho_root` записан.
- Падение записи cluster-tuple **non-fatal** (row закоммичен, Operation успешен) — parity с
  owner-tuple writer.

### 5.4 FGA-model conformance — РЕАЛЬНЫЙ OpenFGA, доказательство отсутствия over-exposure (INV-6, BLOCKING)

`kacho-deploy` (или model-test-harness в `kacho-proto`): скомпилировать отредактированную
каноническую модель в реальный OpenFGA-store и ассертить на **уровне model-резолюции** (stub
wildcard-leak поймать не может — leak в FGA-резолюции, не в Go):

```
Seed:  account:aX#cluster@cluster:cluster_kacho_root
       service_account:<op>#system_viewer@cluster:cluster_kacho_root
       (НИКАКОГО grant для произвольного user:rando)

Assert NEGATIVE (leak-guard):
       ListObjects(user:rando, "viewer", "account") НЕ содержит aX
       Check(user:rando, "viewer", account:aX) == false

Assert POSITIVE (оператор видит):
       ListObjects(service_account:<op>, "viewer", "account") содержит aX
       Check(service_account:<op>, "viewer", account:aX) == true

Assert OWNER по-прежнему работает:
       при user:u1#owner@account:aX → Check(user:u1,"viewer",account:aX) == true

Повторить все четыре для типа "project" с project:pX#cluster + project:pX#account.
```

Это связывающее доказательство, что wildcard `user:*` в `cluster.viewer` **не** достигает
подтипов account/project (источник cascade — `system_viewer`, не `viewer`). **Без этого
model-уровневого (не stub) ассерта инвариант over-exposure не протестирован там, где он
реально ломается** — обязательный, blocking кейс.

Также: `make openfga-model-json` после правки `fga_model.fga` проходит (DSL транслируется в
JSON без ошибок); configmap-stub регенерируется (§2.8).

### 5.5 Newman — black-box через api-gateway (`kacho-iam/tests/newman/cases/iam-*.py`)

- Happy: authenticated USER листит accounts/projects → возвращены только свои.
- Negative: USER НЕ видит чужой account/project (сценарий D end-to-end).
- (Operator-SA + anon-пути покрыты на unit + model-conformance; newman гоняет user-facing
  контракт, т.к. оператор аутентифицируется service→service, не через external REST.)

---

## 6. Ручная dev-верификация (стенд kind, kacho-deploy)

```
make dev-up
make psql SVC=iam   # подтвердить outbox-intent applied / drainer прогнал system_viewer-tuple
# через port-forward api-gateway:
#   operator-persona List → видит все account/project
#   tenant-user List → видит только свои; чужой user → не видит первого
make reload-svc SVC=iam ; make logs-svc SVC=iam
```

---

## 7. Traceability — затронутые артефакты

| Требование | Изменение | Сценарий / Тест |
|---|---|---|
| Оператор видит ВСЕ accounts/projects | миграция 0010 (`system_viewer@cluster`) + модель `system_viewer from cluster` (§2.1/§2.2) | B, E / 5.2, 5.4 |
| Account.List FGA-driven | `account/list.go` + `WithOpenFGA` + `ListObjects("viewer","account")` (§2.5) | A, B / 5.1 |
| Project.List FGA-driven + subject-prefix фикс | `project/list.go` (§2.5/§2.6) | A, B, D / 5.1 |
| Над-экспозиция юзера предотвращена (нет user:* leak) | источник cascade = `system_viewer`, не `viewer` (§2.1, INV-6) | D / **5.4 (blocking)** |
| Новый account/project достижим оператору | `account.Create`/`project.Create` пишут `#cluster`-tuple (§2.3/§2.4) | E / 5.3 |
| Fail-closed при FGA-outage | возврат `Unavailable`, оба use-case'а (§2.5, F-b) | F / 5.1 |
| Read-only оператор | seed только `system_viewer` (§2.2, INV-4) | B, G / 5.2 |
| Stub поддерживает ListObjects | `openfga_stub_test.go` (§2.7) | enables 5.1 |
| Контракт не меняется | нет proto/REST/pagination-правки (Non-goals 1, INV-5) | H / 5.5 |
| Не редактировать 0009 | новая миграция 0010 (Non-goals 3) | 5.2 |
| Model-stub в синке | `make openfga-model-json` (§2.8) | 5.4 |

**Файлы:**

| Слой | Артефакт | Изменение |
|---|---|---|
| proto/model | `kacho-proto/proto/kacho/cloud/iam/v1/fga_model.fga` | `account.viewer`/`project.viewer` += `or system_viewer from cluster` (НЕ-wildcard); `project` += `cluster: [cluster]` (§2.1) |
| deploy | `kacho-deploy/helm/umbrella/templates/openfga-model-stub-configmap.yaml` | регенерируется `make openfga-model-json` (§2.8) |
| migration | `kacho-iam/internal/migrations/0010_sec_l_operator_system_viewer.sql` | seed `system_viewer@cluster-root` (§2.2) |
| use-case | `kacho-iam/internal/apps/kacho/api/account/list.go` | FGA-relation-driven + `WithOpenFGA` + subject-prefix + fail-closed (§2.5/§2.6) |
| use-case | `kacho-iam/internal/apps/kacho/api/project/list.go` | subject-prefix фикс + fail-closed (§2.5/§2.6) |
| use-case | `kacho-iam/internal/apps/kacho/api/account/create.go` | + write `account#cluster@cluster-root` (§2.3) |
| use-case | `kacho-iam/internal/apps/kacho/api/project/create.go` | + write `project#cluster@cluster-root` (§2.4) |
| clients | `kacho-iam/internal/clients/openfga_stub_test.go` | `OpenFGAStubClient` impl `CheckExtensions.ListObjects` (§2.7) |
| wiring | `kacho-iam/cmd/kacho-iam/main.go` (composition root) | `ListAccountsUseCase.WithOpenFGA(fgaClient)` |
| vault | `obsidian/kacho/edges/vpc-operator-to-iam-ns-fanout.md`, `rpc/kacho-iam-account-service.md`, `KAC/KAC-<N>.md` | trail после merge |

**Vault-сущности (wikilinks для KAC-trail):** `[[kacho-iam-AccountService]]`,
`[[kacho-iam-ProjectService]]`, `[[kacho-iam-Account]]`, `[[kacho-iam-Project]]`,
`[[vpc-operator-to-iam-ns-fanout]]`, `[[fga-authorization-model]]`.

---

## 8. Non-goals (явно ВНЕ scope под-фазы)

1. **Контракт RPC не меняется** — нет нового RPC/поля/oneof; request/response/REST/pagination/
   filter идентичны. Только смена authz-источника фильтра в существующих `List`.
2. **Мутации не меняются** — Create/Update/Delete/Move, AccessBinding, async-Operation,
   идемпотентность, authz-гейты — нетронуты. Единственное добавление на Create — один лишний
   **non-fatal** hierarchy-tuple write (§2.3/§2.4), идентичный по паттерну owner-tuple write.
   Operator остаётся read-only (INV-4).
3. **НЕ редактировать migration 0009** (ban #5) — operator-tuple идёт **новой** 0010.
4. **НЕ расширять cluster-root visibility на per-domain ресурсы** (vpc_*/compute_*/iam_*-кроме-
   account/project). Только `account` + `project`. Расширение на VPC/Compute — отдельный тикет.
5. **НЕ давать оператору editor/admin** — никакого `editor from cluster`/`admin from cluster`
   на account/project. Только read-relation `system_viewer`.
6. **НЕ менять api-gateway** (public/internal mux) — `List` уже зарегистрирован; источник
   фильтра внутренний для IAM. Нет Internal\*/external-изменений.
7. **Реальный AuthN (JWT/IAM-token)** — вне scope; principal по-прежнему из
   `operations.PrincipalFromContext` / metadata.
8. **One-shot back-fill `#cluster`-tuples для pre-existing accounts/projects** — операционный
   follow-up (§2.4 note), отдельный admin-job/тикет, НЕ часть этого acceptance.

---

## 9. Definition of Done

- [ ] APPROVED от `acceptance-reviewer` (этот док) — ДО любого кода.
- [ ] KAC-тикет заведён; ветки `KAC-<N>` в kacho-proto + kacho-iam + kacho-deploy (+docs); KAC-trail в vault.
- [ ] RED-тесты написаны и прогнаны ПЕРВЫМИ для каждого изменения (§5), показаны RED→GREEN пары.
- [ ] **Subject-prefix RED→GREEN пара для ОБОИХ `account/list.go` и `project/list.go`**
      (точная subject-строка `service_account:<id>` / `user:<id>` — §2.6) — явный line-item.
- [ ] **§5.4 model-conformance over-exposure proof (реальный OpenFGA): `user:rando` НЕ получает
      `viewer@account:aX`; оператор-SA получает** — blocking, обязан быть GREEN.
- [ ] FGA-модель: `account.viewer`/`project.viewer` += `or system_viewer from cluster`
      (НЕ-wildcard); `project` += `cluster: [cluster]`; никакая другая relation не расширена (§2.1).
- [ ] Миграция 0010 сидирует `system_viewer@cluster:cluster_kacho_root` для оператор-SA;
      идемпотентна; down ревертит; **0009 не тронута** (§2.2).
- [ ] `account.Create` + `project.Create` пишут `#cluster` parent-tuple (non-fatal) (§2.3/§2.4).
- [ ] `AccountService.List` + `ProjectService.List` FGA-`ListObjects("viewer",…)`-driven;
      нет reintroduced repo-side owner-widener; fail-closed `Unavailable` при FGA-ошибке (§2.5).
- [ ] In-memory stub реализует `CheckExtensions.ListObjects` (§2.7).
- [ ] openfga-model-stub configmap регенерирован из канонического DSL (§2.8).
- [ ] INV-1..INV-7 подтверждены тестами (особо INV-1/D над-экспозиция, INV-2/B оператор-видит-все,
      INV-6/§5.4 wildcard-leak-guard, INV-7/F fail-closed).
- [ ] Финальная верификация: `go test ./... -race` + `golangci-lint run` + `govulncheck` +
      `make audit-list-filter` + newman зелёные.
- [ ] Ревью ролями: `proto-api-reviewer` (модель), `db-architect-reviewer` (миграция/outbox),
      `system-design-reviewer` (propagation/fail-closed), `go-style-reviewer` (use-case).
- [ ] Vault-trail обновлён (edges/rpc/resources/KAC); тикет Test → Done с артефактами.

---

## 10. Открытые вопросы reviewer'у

1. **Pagination после FGA-фильтра** — оба list-пути грузят repo-страницу, затем фильтруют до
   FGA-viewer-набора, поэтому страница может вернуть меньше `page_size` rows (pre-existing
   поведение в `project/list.go`). Приемлемо для этой фазы, или нужна server-side intersection?
   (Фикс вне scope SEC-L; только флаг.)
2. **Pre-SEC-L существующие accounts/projects** не имеют `#cluster`-tuple → невидимы оператору
   до back-fill-job (§2.4 note). Подтвердить, что one-shot back-fill — операционный follow-up
   (отдельный тикет), не часть этого acceptance.
