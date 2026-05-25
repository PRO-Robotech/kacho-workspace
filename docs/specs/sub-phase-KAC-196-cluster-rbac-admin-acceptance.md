# Sub-phase KAC-196 — Cluster-RBAC Admin (control-plane RPC + UI) — Acceptance

> **Status**: DRAFT v2 — round 2 revisions applied, awaiting `acceptance-reviewer` round 2.
> **Date**: 2026-05-25.
> **YouTrack**: [KAC-196](https://prorobotech.youtrack.cloud/issue/KAC-196).
> **Parent epic**: [KAC-178](https://prorobotech.youtrack.cloud/issue/KAC-178) — stand prod-readiness (cluster admin/editor aliases уже добавлены в FGA-модели через `kacho-proto#26` + `kacho-deploy#55`; этот тикет завершает gap «как admin выдаёт admin без `kubectl exec`»).
> **Author agent**: `acceptance-author`.
> **Reviewer agent**: `acceptance-reviewer` (gate per workspace `CLAUDE.md` §«Запреты» #1).
> **Target repos**: `kacho-proto`, `kacho-iam`, `kacho-api-gateway`, `kacho-ui`.
> **Out-of-scope**: `emergency_admin` break-glass flow lifecycle (Phase 7 — [[../obsidian/kacho/resources/iam-cluster-break-glass-grant]]); subject_type `service_account` (этот тикет только `user`); `system_viewer` / `billing_admin` / `console` relations (можно расширить позже).

---

## 0. Преамбула — что эта итерация

Сейчас единственный путь выдать пользователю `system_admin` на `cluster:cluster_kacho_root` —
ручной `kubectl exec` на openfga-pod + сырой HTTP POST в `/stores/<id>/write`. Это:

1. **Не масштабируется** — каждое предоставление admin-прав требует SRE-операции с прод-доступом.
2. **Не оставляет audit-trail** — нет записи «кто кому когда выдал», только FGA tuple без атрибуции.
3. **Сценарий «отзыв admin'а»** ещё хуже — нужен ручной `tuple_keys.deletes` POST.
4. **Bootstrap уже работает** через [[../obsidian/kacho/packages/iam-seed]] `bootstrap_admin.go` (env `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL` на старте сервиса), но это **только первый admin** — дальше admins должны выдавать друг другу через **control-plane API**.

KAC-196 закрывает эту дыру: вводит 4 `Internal*` RPC на `kacho-iam` (`Get`, `GrantAdmin`,
`RevokeAdmin`, `ListAdmins`) под cluster-relation `system_admin` (см.
[[../obsidian/kacho/rpc/iam-internal-cluster-service]] §«Planned methods Phase 2»), регистрирует их
в `api-gateway` **internal mux** (workspace §«Запреты» #6 — никогда на external TLS), и добавляет
UI-страницу `/system/cluster/admins` для admin-tooling.

### 0.1 Scope (что входит)

1. **`kacho-proto`** — новый файл `proto/kacho/cloud/iam/v1/internal_cluster_service.proto` с
   4 RPC: `Get`, `GrantAdmin`, `RevokeAdmin`, `ListAdmins`. Envelope + Operation result для
   мутаций (workspace §«Запреты» #9). Один объект `cluster:cluster_kacho_root`, один relation
   `system_admin`. `admin`/`editor` aliases уже определены каскадом от `system_admin` через
   `kacho-proto#26`/`kacho-deploy#55` и **не пишутся** как явные tuples (computed).
2. **`kacho-iam`** — use-cases `grant_admin.go` / `revoke_admin.go` / `list_admins.go` /
   `get_cluster.go` под `internal/apps/kacho/api/cluster/`; handler.go + middleware-gate;
   fga_outbox enqueue в **одной TX** с insert/update (godzila §16, evgeniy §6 Reader/Writer split,
   выбранный `kacho-iam` evgeniy pattern). **Никаких новых миграций** — таблица
   `cluster_admin_grants` и её constraints уже созданы миграцией 0011.
3. **`kacho-api-gateway`** — регистрация в **internal-mux only** под `/iam/v1/internal/cluster/...`;
   permission_catalog.json entries для 4 RPC с `required_relation=admin` (computed),
   `scope_extractor={cluster, *}`.
4. **`kacho-ui`** — страница `/system/cluster/admins`: таблица текущих admin'ов (subject_id, email,
   display_name, granted_by, granted_at), кнопки `Добавить admin` (модалка с email-search →
   user_id) и `Отозвать` (per row, disabled когда self или last-admin).
5. **Тесты** в том же PR (workspace §«Запреты» #12) — integration (testcontainers, concurrent
   last-admin race, concurrent grant idempotency, concurrent grant+revoke same subject) + newman
   (12 кейсов из §5.5).

### 0.2 НЕ-scope (явно отложено)

- **`emergency_admin` break-glass lifecycle** ([[../obsidian/kacho/resources/iam-cluster-break-glass-grant]] /
  2-person approve state machine — `RequestBreakGlass` / `ApproveBreakGlass` / `RevokeBreakGlass`
  RPCs) — Phase 7 acceptance. В KAC-196 emergency_admin фигурирует **только** как computed-alias
  source (`admin = system_admin OR emergency_admin`); тест-fixture для §6.10 эмулирует уже-активный
  grant без полной импл'а Phase 7.
- **`subject_type='service_account'`** для grants — DB-схема [[../obsidian/kacho/resources/iam-cluster-admin-grant]]
  уже допускает (`CHECK IN ('user','service_account')`), но handler API в этом тикете принимает
  только `user_id` (валидация: префикс `usr_`).
- **Relations `system_viewer` / `billing_admin` / `console`** — отдельные `Grant`/`Revoke`-методы
  на другие relations (можно сделать generic `GrantClusterRole(relation, subject)` в follow-up,
  если их станет >1).
- **`granted_until` non-null grants** (TTL'd permanent admin) — namespace зарезервирован в DB
  schema (`NULL = permanent`, partial UNIQUE `WHERE granted_until IS NULL`), но handler пишет
  только `NULL`. Временные admin'ы делаются через break-glass (Phase 7), не через permanent grant.
- **Cascade revoke / mass-revoke** — этот тикет revoke'ит ровно по одному subject_id за вызов.

### 0.3 Decisions (зафиксированы до review)

| ID  | Decision | Rationale |
|-----|----------|-----------|
| **D-1** | **Один relation `system_admin`**, `admin`/`editor` — computed aliases (DSL `define admin: system_admin or emergency_admin`) и **не** материализуются как tuples. | `kacho-proto#26` уже добавил эти aliases (см. [[../obsidian/kacho/KAC/KAC-178]] DoD); запись `admin` как явный tuple ломает каскад и создаёт write-amplification. Один tuple per subject = одна row в `cluster_admin_grants` = одна fga_outbox row = одна FGA `Write`. |
| **D-2** | **Subject — только `user_id`** (без `service_account`). | Cluster-admin требует individual identity для audit ([[../obsidian/kacho/resources/iam-cluster-admin-grant]] «Gotchas»). SA-аdmins — отдельный тикет с дополнительной защитой (impersonation policy, OAuth client review). |
| **D-3** | **Gate (`who can call Grant/Revoke/List/Get`) = relation `admin`** (computed: `system_admin OR emergency_admin`) на `cluster:cluster_kacho_root`. | См. D-11 ниже — это уточнение D-3 с конкретным выбором computed-aliasа поверх raw relation. |
| **D-4** | **`GrantAdmin` идемпотентен** (повторный grant на тот же subject = no-op, 200 Operation, success result). | UI «Добавить admin» может быть retried (network blip); двойной grant не должен возвращать ошибку. На DB-уровне это обеспечивает `INSERT … ON CONFLICT (subject_type, subject_id) WHERE granted_until IS NULL DO NOTHING`; FGA `Write` идемпотентен на existing tuple by-design. |
| **D-5** | **Self-revoke запрещён** — субъект не может revoke сам себя через этот RPC. | Защита от случайного lock-out. Сценарий «admin хочет уйти» решается через «другой admin revoke'ит» (или break-glass если последний). На уровне SQL — компонент CAS-WHERE: `subject_id != $principal_id` (CHECK constraint неприменим, т.к. constraint не знает caller'а — это runtime-property, не свойство row). |
| **D-6** | **Last-admin revoke запрещён** — если в `cluster_admin_grants` ровно одна active row (`granted_until IS NULL`), её revoke возвращает `FailedPrecondition`. | Защита от полного lock-out cluster. Восстановление возможно только через DB seed (bootstrap re-apply с новым ENV) или break-glass. На DB-уровне — атомарный single-statement `UPDATE cluster_admin_grants SET granted_until = now() WHERE subject_id = $1 AND granted_until IS NULL AND (SELECT count(*) FROM cluster_admin_grants WHERE granted_until IS NULL) > 1` (CAS, workspace §«Запреты» #10). |
| **D-7** | **Audit trail = `cluster_admin_grants` table сам по себе** + audit_outbox запись. | `granted_by` фиксирует principal; `granted_at` — server-set; revoke устанавливает `granted_until = now()` без удаления row (full history). Дополнительные audit-events идут через [[../obsidian/kacho/packages/iam-jobs]] outbox в общий audit-log. |
| **D-8** | **Operation.created_by = real subject_id** (W1.4 principal propagation per KAC-178 §2). | После KAC-178#31 (compute cmd UnaryPrincipalExtract) принцип `created_by = principal_id` соблюдается всеми сервисами; этот тикет не расширяет middleware, просто опирается на готовый pipeline. |
| **D-9** | **Validation user existence — synchronous через `InternalUserService.Get` (own service)**. | `kacho-iam` сам хранит users (`kacho_iam.users`); валидация — обычный SELECT в той же TX, не cross-service RPC. Не-существующий `user_id` → `InvalidArgument "user not found"`. |
| **D-10** | **Internal only**, REST под `/iam/v1/internal/cluster/...`. | workspace §«Запреты» #6: cluster-admin enforcement — не tenant-facing. Регистрация в `api-gateway/internal/restmux/mux.go` в существующем `iamInternalAddr` блоке (mirror E0 pattern). |
| **D-11** | **Gate = `admin` (computed alias `system_admin OR emergency_admin`)**, **НЕ** raw `system_admin`. | Resolved per user clarification 2026-05-25 (open question #1). См. FGA DSL `fga_model.fga:89` — `define admin: system_admin or emergency_admin`. Rationale: emergency_admin существует именно для recovery после lock-out (все system_admin откатились или revoked друг друга) — если gate = raw `system_admin`, emergency_admin не может выдать новый system_admin → бизнес-смысл break-glass обнуляется, восстановление требует DB-seed restart. С gate = `admin` каскад работает: и system_admin, и emergency_admin проходят, recovery возможен через RPC. Применяется ко всем 4 RPC: `Get`, `GrantAdmin`, `RevokeAdmin`, `ListAdmins`. |
| **D-12** | **`RevokeAdmin` НЕ идемпотентен** — revoke non-existent admin / уже-revoked admin возвращает `NotFound`. Асимметрично с D-4 (GrantAdmin идемпотентен). | UI semantic: «Добавить admin» — операция на цели (subject) с retry-safe семантикой (двойной клик — OK); «Отозвать» — операция per specific row (visible в таблице), explicit per-row, без silent no-op. Если admin уже revoked — это либо устаревшее UI-состояние (нужен refresh), либо опечатка в curl — оба случая хотят явный 404, а не silent success. На DB-уровне реализуется через CAS-UPDATE с `granted_until IS NULL` в WHERE → 0 rows → `ErrNotFound` (если subject вообще нет — тот же 0 rows, тот же 404; SELECT-side диагностика determines подробную причину для лога/error-text). |

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace) — код только после `acceptance-reviewer` APPROVED | этот документ — gate; статус сейчас DRAFT v2 |
| **Запрет #2** — НЕ «yandex» | proto/UI/error-text — `kacho.cloud.iam.v1`, `KACHO_IAM_*` |
| **Запрет #3** — НЕ ORM | sqlc + handwritten pgx; новые методы Repo через evgeniy §6 (Reader/Writer split) — `cluster_admin_grant_reader.go` / `cluster_admin_grant_writer.go` |
| **Запрет #5** — НЕ редактировать применённую миграцию | `cluster_admin_grants` уже создана миграцией `0011` (см. [[../obsidian/kacho/resources/iam-cluster-admin-grant]]); этот тикет НЕ меняет схему таблицы и **новых миграций не вводит** (см. §5.2 и §3.2). |
| **Запрет #6** — Internal.* НЕ на external TLS endpoint | InternalClusterService.* регистрируется только в `api-gateway/internal/restmux/mux.go` (cluster-internal listener); НЕ в публичном `gw.go` |
| **Запрет #8** — DB-per-service | Все таблицы в `kacho_iam` (users, cluster_admin_grants, fga_outbox); FGA tuples в отдельном openfga-Postgres — sync через outbox-pattern (godzila §16); никаких cross-DB FK |
| **Запрет #9** — async-only мутации | `GrantAdmin` / `RevokeAdmin` возвращают `operation.Operation`; реактивность — FGA tuple visible ≤2s через outbox-drainer worker |
| **Запрет #10** — within-service refs на DB-уровне | (a) `cluster_admin_grants.cluster_id FK → clusters(id) RESTRICT` (уже в миграции 0011); (b) partial UNIQUE `(subject_type, subject_id) WHERE granted_until IS NULL` (миграция 0011) — гарантирует один permanent grant per subject; `INSERT … ON CONFLICT … DO NOTHING` для idempotent grant; partial UNIQUE одновременно служит **быстрым index-only-scan** источником для `count(*) WHERE granted_until IS NULL` в last-admin guard — никакого дополнительного индекса не нужно; (c) **last-admin guard через CAS-UPDATE с subquery `count(*) > 1`** (атомарно single-statement); (d) **self-revoke guard через CAS-UPDATE с `subject_id != $principal`** (в той же WHERE — CHECK constraint не подходит, т.к. constraint не знает caller'а — это runtime-property, см. D-5) |
| **Запрет #11** — НЕ tech-debt / TODO | Все 4 RPC реализуются полностью в одном PR на `kacho-iam` + UI; нет «follow-up `TODO(KAC-N): implement Revoke later`». Никаких новых миграций «if needed» — либо есть, либо нет; решено — нет. |
| **Запрет #12** — тесты в том же PR | Integration (testcontainers, concurrent last-admin race + concurrent grant idempotency + concurrent grant+revoke same subject + OpenFGA outage); newman (12 кейсов §5.5); UI Playwright — отдельный smaller PR в `kacho-ui` (та же ветка KAC-196) |
| **Запрет #13** — test-only PR без правок прода | НЕ применимо — это полная фича, не test-coverage спринт |
| **evgeniy §2** UseCases | `grant_admin.go`, `revoke_admin.go`, `list_admins.go`, `get_cluster.go` — каждый use-case в своём файле |
| **evgeniy §4** self-validating domain | newtype `domain.ClusterAdminGrant` с `Validate()` методом (subject_type, subject_id length, granted_by length); newtype `domain.SubjectID` (валидирует префикс `usr_`) |
| **evgeniy §5** DB-уровень валидации | uses existing миграция 0011 constraints (FK + partial UNIQUE); atomic-CAS guard для last-admin/self-revoke в SQL запросе, не в Go |
| **evgeniy §6** Reader/Writer split | `service.ClusterAdminGrantReader` + `service.ClusterAdminGrantWriter` (отдельные интерфейсы, отдельные TX); адаптеры pgx в `internal/repo/kacho/pg/` |
| **godzila §16** outbox | INSERT/UPDATE `cluster_admin_grants` + INSERT `fga_outbox` (с tuple-key) + INSERT `audit_outbox` — всё в одной DB-TX; FGAOutboxDrainer (существующий worker) подхватывает |

---

## 2. Глоссарий / доменная модель (нормативно)

### 2.1 Объекты и relations FGA

- **Объект**: `cluster:cluster_kacho_root` (singleton, hard-coded id, см. [[../obsidian/kacho/resources/iam-cluster]] «id_singleton_ck»).
- **Relations** (DSL уже задеплоено через `kacho-proto#26` + `kacho-deploy#55`, см. `fga_model.fga`):
  - `system_admin` — материализуется как tuple `cluster:cluster_kacho_root#system_admin@user:<usr_xxx>`.
  - `emergency_admin` — материализуется через break-glass flow (Phase 7), не через этот RPC.
  - `admin` — **computed** (`fga_model.fga:89`): `define admin: system_admin or emergency_admin`. Не пишется как tuple.
  - `editor` — **computed**: `define editor: admin`. Не пишется как tuple.
- **Tuple writer**: `kacho-iam` `FGAOutboxDrainer` (существующий, см. [[../obsidian/kacho/packages/iam-jobs]]).

### 2.2 Доменные newtypes (Go, `kacho-iam/internal/domain/`)

```go
type SubjectID string  // префикс usr_ + 17-char crockford; Validate(): IsValid("usr") || error

type ClusterAdminGrant struct {
    ID          string       // cag_<17>
    ClusterID   string       // = "cluster_kacho_root"
    SubjectType string       // "user" (in this ticket; CHECK на DB допускает "service_account")
    SubjectID   SubjectID
    GrantedBy   string       // principal_id (real subject_id, propagated via W1.4)
    GrantedAt   time.Time
    GrantedUntil *time.Time  // NULL = active permanent; non-NULL = revoked/expired
}

func (g *ClusterAdminGrant) Validate() error { ... }
func (g *ClusterAdminGrant) IsActive() bool  { return g.GrantedUntil == nil }
```

### 2.3 Permission catalog mapping

`kacho-api-gateway/internal/middleware/embed/permission_catalog.json` — 4 новых entry:

| RPC | required_relation | scope_extractor |
|---|---|---|
| `kacho.cloud.iam.v1.InternalClusterService.Get` | `admin` | `{type:cluster, id:cluster_kacho_root}` |
| `kacho.cloud.iam.v1.InternalClusterService.GrantAdmin` | `admin` | `{type:cluster, id:cluster_kacho_root}` |
| `kacho.cloud.iam.v1.InternalClusterService.RevokeAdmin` | `admin` | `{type:cluster, id:cluster_kacho_root}` |
| `kacho.cloud.iam.v1.InternalClusterService.ListAdmins` | `admin` | `{type:cluster, id:cluster_kacho_root}` |

`admin` — computed alias (`fga_model.fga:89`: `define admin: system_admin or emergency_admin`).
Middleware (W2 authz-gate из KAC-178/KAC-127 chain) вызывает `InternalIAMService.Check` —
OpenFGA сам разрешает каскад `system_admin → admin` и `emergency_admin → admin`. Поэтому
subject с `emergency_admin` тоже проходит gate (см. D-11 и §6.10).

---

## 3. Архитектура (компактно)

### 3.1 ASCII edges

```
        ┌─────────────────────────────────────────────────────────────┐
        │ UI /system/cluster/admins                                    │
        │  - ListAdmins (table render)                                 │
        │  - GrantAdmin (modal: email search → user_id → grant)        │
        │  - RevokeAdmin (per-row action, disabled self / last)        │
        └────────────────────┬────────────────────────────────────────┘
                             │ HTTPS REST (internal-mux, cluster-internal listener)
                             ▼
        ┌─────────────────────────────────────────────────────────────┐
        │ kacho-api-gateway                                            │
        │  - Internal restmux registration /iam/v1/internal/cluster/  │
        │  - W2 authz-gate (read permission_catalog → Check)          │
        │      Check(principal, admin, cluster:root) → allow          │
        └────────────────────┬────────────────────────────────────────┘
                             │ gRPC (principal in ctx via W1.4)
                             ▼
        ┌─────────────────────────────────────────────────────────────┐
        │ kacho-iam :9091  InternalClusterService                     │
        │   handler.go: extract principal, validate user_id (Get      │
        │               from kacho_iam.users), call use-case          │
        │                                                              │
        │   use-cases:                                                 │
        │     get_cluster.go     (Reader-TX, returns Cluster)         │
        │     grant_admin.go     (Writer-TX:                          │
        │                          INSERT cluster_admin_grants        │
        │                          ON CONFLICT (subject) WHERE active │
        │                          DO NOTHING + RETURNING id;         │
        │                          INSERT fga_outbox (Write tuple);   │
        │                          INSERT audit_outbox)               │
        │     revoke_admin.go    (Writer-TX:                          │
        │                          CAS UPDATE granted_until = now()   │
        │                          WHERE subject AND granted_until IS │
        │                          NULL AND subject_id != $principal  │
        │                          AND (SELECT count(*) FROM grants   │
        │                               WHERE active) > 1;            │
        │                          INSERT fga_outbox (Delete tuple);  │
        │                          INSERT audit_outbox)               │
        │     list_admins.go     (Reader-TX: SELECT active grants     │
        │                          JOIN users for display_name/email) │
        └────────────────────┬────────────────────────────────────────┘
                             │ async drain (FGAOutboxDrainer worker)
                             ▼
        ┌─────────────────────────────────────────────────────────────┐
        │ OpenFGA (openfga-Postgres + openfga-server)                 │
        │   tuple cluster:cluster_kacho_root#system_admin@user:<id>   │
        └─────────────────────────────────────────────────────────────┘
```

### 3.2 Файлы (целевая структура)

```
kacho-proto/proto/kacho/cloud/iam/v1/
  internal_cluster_service.proto       (NEW; 4 RPC + 8 messages: Cluster, Get/Grant/Revoke/List Req/Resp, Operation metadata)
  gen/go/...                            (regen)

kacho-iam/
  internal/domain/cluster_admin_grant.go                (NEW: newtype + Validate)
  internal/repo/kacho/pg/cluster_admin_grant_reader.go  (NEW)
  internal/repo/kacho/pg/cluster_admin_grant_writer.go  (NEW; atomic CAS UPDATE + INSERT ON CONFLICT)
  internal/repo/kacho/pg/cluster_reader.go              (NEW: singleton Get)
  internal/apps/kacho/api/cluster/get.go                (NEW use-case)
  internal/apps/kacho/api/cluster/grant_admin.go        (NEW use-case)
  internal/apps/kacho/api/cluster/revoke_admin.go       (NEW use-case)
  internal/apps/kacho/api/cluster/list_admins.go        (NEW use-case)
  internal/transport/grpc/internal_cluster_handler.go   (NEW: handler.go thin layer)
  cmd/iam/main.go                                       (REGISTER InternalClusterService на :9091)

  # МИГРАЦИЙ НЕТ.
  # Миграция 0011 уже создала: clusters, cluster_admin_grants, cluster_break_glass_grants,
  # partial UNIQUE cluster_admin_grants_subject_unique (subject_type, subject_id) WHERE granted_until IS NULL,
  # FK cluster_admin_grants.cluster_id → clusters(id) ON DELETE RESTRICT.
  # Self-revoke guard НЕ выражается как CHECK constraint (CHECK не знает caller'а — runtime-property),
  # реализуется через CAS-WHERE в Revoke SQL (D-5).
  # Last-admin guard НЕ требует дополнительного index'а — partial UNIQUE служит index-only-scan
  # источником для count(*) WHERE granted_until IS NULL (D-6).

kacho-api-gateway/
  internal/middleware/embed/permission_catalog.json     (UPDATE: +4 entries с required_relation=admin)
  internal/restmux/mux.go                               (UPDATE: register /iam/v1/internal/cluster/* в iamInternalAddr block)

kacho-ui/
  src/pages/SystemClusterAdminsPage.tsx                 (NEW: страница /system/cluster/admins)
  src/components/GrantAdminModal.tsx                    (NEW: email-search + grant)
  src/api/iam/cluster.ts                                (NEW: thin REST client)
  src/router.tsx                                        (UPDATE: route + lazy import)
```

---

## 4. Контракты (нормативно, не код)

### 4.1 RPC: `InternalClusterService.Get`

**Request** (`GetClusterRequest`): пустое сообщение (singleton).
**Response** (`Cluster`):
- `id` (= `cluster_kacho_root`)
- `name`
- `description`
- `created_at`

**Sync**, без Operation.

**REST**: `GET /iam/v1/internal/cluster`.

### 4.2 RPC: `InternalClusterService.GrantAdmin`

**Request** (`GrantClusterAdminRequest`):
- `subject_type` = `"user"` (enum SubjectType; в этом тикете только USER, валидация InvalidArgument для остальных)
- `subject_id` (string, валидируется регексом `^usr_[0-9a-hjkmnp-tv-z]{17}$`)

**Response** (`operation.Operation`):
- `metadata = Any<GrantClusterAdminMetadata>{cluster_admin_grant_id, subject_id}` (заполняется сразу при INSERT)
- `done = false` сначала; worker `OperationsWorker` (corelib) переводит в `done=true` после успешного `FGAOutboxDrainer` (≤2s)
- `response = Any<ClusterAdminGrant>` — финальная row

**REST**: `POST /iam/v1/internal/cluster/admins` body `{subject_type, subject_id}`.

### 4.3 RPC: `InternalClusterService.RevokeAdmin`

**Request** (`RevokeClusterAdminRequest`):
- `subject_type` = `"user"`
- `subject_id` (string)

**Response** (`operation.Operation`):
- `metadata = Any<RevokeClusterAdminMetadata>{cluster_admin_grant_id, subject_id}`
- `done = false` сначала; worker переводит в `done=true` после `FGAOutboxDrainer` delete-tuple успеха.
- `response = Any<ClusterAdminGrant>` — row с `granted_until` set.

**REST**: `DELETE /iam/v1/internal/cluster/admins/{subject_id}` (subject_type фиксирован `user` в этом тикете).

### 4.4 RPC: `InternalClusterService.ListAdmins`

**Request** (`ListClusterAdminsRequest`): пусто (нет pagination — admins ожидается ≤50, page_size default 1000 при необходимости).
**Response** (`ListClusterAdminsResponse`):
- `admins[]` — список `ClusterAdminEntry`:
  - `cluster_admin_grant_id` (cag_xxx)
  - `subject_type`
  - `subject_id`
  - `subject_email` (enriched from `kacho_iam.users` join)
  - `subject_display_name` (enriched)
  - `granted_by_user_id`
  - `granted_by_email` (enriched if granted_by != "bootstrap")
  - `granted_at`

Filter: `WHERE granted_until IS NULL` (только активные).

**Sync**, без Operation.

**REST**: `GET /iam/v1/internal/cluster/admins`.

### 4.5 Error mapping

| Условие | gRPC code | Message (YC-style, exact match для Newman assertions) |
|---|---|---|
| Subject_type не `user` | InvalidArgument | `"Illegal argument subject_type: only 'user' supported in this version"` |
| subject_id регекс не валидный | InvalidArgument | `"Illegal argument subject_id"` |
| User не найден в `kacho_iam.users` | InvalidArgument | `"User %s not found"` (как в YC FolderService.Get pattern; %s = subject_id) |
| Caller не имеет admin (ни system_admin, ни emergency_admin) | PermissionDenied | `"Permission denied"` (capitalized; стандартный gate-message, не leak `admin`/`system_admin`) |
| Self-revoke | FailedPrecondition | `"cannot revoke own cluster admin grant"` |
| Last-admin revoke | FailedPrecondition | `"cannot revoke last active cluster admin"` |
| Revoke non-existent / уже-revoked admin (D-12) | NotFound | `"User %s is not an active cluster admin"` (%s = subject_id) |
| FGA / OpenFGA недоступен на read path (Get / List не зовут FGA для своих данных, gate-check кэшируется ≤5s) | (не возвращаем error, gate-cache соответствует last-known state) | n/a |
| FGA / OpenFGA недоступен на write path | sync return Operation done=false (HTTP 200) | n/a — Operation позже переводится в terminal state worker'ом |
| OpenFGA постоянно недоступен (>30s retry-exhaustion в drainer) | Operation `done=true, error.code=Unavailable` (HTTP 200, Operation body содержит error) | `"OpenFGA unavailable, tuple-write retry exhausted"` |

**Newman assertion note**: все вышеуказанные message-strings проверяются `pm.expect(...).to.eql(...)`
(exact match), не `to.include(...)` (substring). Расхождение в кейсе/пунктуации ломает тест и
выявляется в RED-фазе TDD-цикла.

---

## 5. Definition of Done (нормативный чек-лист)

> [!important] Каждый пункт верифицируется конкретной командой / артефактом. `[x]` ставится по факту merge соответствующего PR.

### 5.1 Proto + регенерация (`kacho-proto`)

- [ ] `proto/kacho/cloud/iam/v1/internal_cluster_service.proto` создан с 4 RPC.
- [ ] `buf lint` зелёный.
- [ ] `buf breaking` зелёный (новый файл — non-breaking).
- [ ] `gen/go/kacho/cloud/iam/v1/internal_cluster_service.pb.go` + `_grpc.pb.go` сгенерированы и закоммичены.
- [ ] Тег `kacho-proto v?.?.?` (если используется semver) обновлён.

### 5.2 Backend (`kacho-iam`)

- [ ] **Никаких новых миграций.** Existing миграция 0011 (`cluster_admin_grants_subject_unique`
  partial UNIQUE `WHERE granted_until IS NULL`) служит и UNIQUE-инвариантом, и быстрым
  `count(*)` источником (index-only-scan) для last-admin guard. **Дополнительной миграции в
  этом тикете НЕ вводим** — это сознательное решение, не отложенный tech-debt (workspace
  §«Запреты» #11). Self-revoke guard невозможно выразить как CHECK constraint (CHECK не знает
  caller'а — это runtime-property), реализуется в CAS-WHERE handler'а.
- [ ] `internal/domain/cluster_admin_grant.go` с `Validate()`.
- [ ] `internal/repo/kacho/pg/cluster_admin_grant_writer.go`:
   - `Grant(ctx, tx, grant)` — атомарный `INSERT … ON CONFLICT (subject_type, subject_id) WHERE granted_until IS NULL DO NOTHING RETURNING id`; при 0 rows — возвращает existing id (idempotent).
   - `Revoke(ctx, tx, subject, principalID)` — атомарный `UPDATE cluster_admin_grants SET granted_until = now() WHERE subject_type=$1 AND subject_id=$2 AND granted_until IS NULL AND subject_id != $3 AND (SELECT count(*) FROM cluster_admin_grants WHERE granted_until IS NULL) > 1 RETURNING id`; при 0 rows — отдельные SELECT'ы determine reason (self / last / not-admin) → typed error sentinel (`ErrSelfRevoke` / `ErrLastAdmin` / `ErrNotFound`).
- [ ] `internal/repo/kacho/pg/cluster_admin_grant_reader.go`: `List(ctx, tx)` (active only с JOIN users); `GetBySubject(ctx, tx, subject_id)`.
- [ ] 4 use-cases в `internal/apps/kacho/api/cluster/`.
- [ ] Handler в `internal/transport/grpc/internal_cluster_handler.go` — thin layer, без бизнес-логики.
- [ ] Регистрация в `cmd/iam/main.go` на gRPC server `:9091`.
- [ ] `fga_outbox` enqueue для tuple-write/delete в **одной TX** с grant/revoke; existing `FGAOutboxDrainer` worker обрабатывает.
- [ ] `audit_outbox` enqueue (existing pattern) — payload `{event:"cluster_admin_granted"|"cluster_admin_revoked", grant_id, subject_id, principal_id, ts}`.

### 5.3 API gateway (`kacho-api-gateway`)

- [ ] `internal/middleware/embed/permission_catalog.json` — 4 entries (см. §2.3), все с `required_relation=admin`.
- [ ] `internal/restmux/mux.go` — регистрация InternalClusterService под `/iam/v1/internal/cluster/*` в `iamInternalAddr` блоке. **НЕ** в `gw.go` (public TLS endpoint) — workspace §«Запреты» #6.
- [ ] `make sync-permission-catalog` зелёный.
- [ ] Newman кейс `CLUSTER-ADMIN-INTERNAL-NOT-ON-EXTERNAL-TLS` (mirror existing `iam-internal-only-check`) — POST на `https://api.kacho.local/iam/v1/internal/cluster/admins` отвечает 404 (не registered) на public listener.

### 5.4 UI (`kacho-ui`)

- [ ] Страница `/system/cluster/admins` рендерит таблицу с колонками: Email, Display name, Granted by, Granted at, Actions.
- [ ] Кнопка `Добавить admin` открывает модалку с email autocomplete (вызов `UserService.List` filter by email) → выбор → grant.
- [ ] Кнопка `Отозвать` per row → confirm dialog → revoke. **Disabled** когда subject_id == current user id OR active admin count == 1.
- [ ] Route guard: страница доступна только subject'у с `admin` (cascade — system_admin OR emergency_admin); проверка через cached effective-permissions или 403 → redirect на dashboard.
- [ ] Playwright e2e в `kacho-ui/tests/e2e/` (или `kacho-test/`):
   - Login as system_admin → see admins page → grant new admin → list shows new admin.
   - Login as ordinary user → /system/cluster/admins → 403 page.

### 5.5 Тесты (workspace §«Запреты» #12 — в том же PR)

- [ ] **Integration tests** (`kacho-iam/internal/repo/kacho/pg/cluster_admin_grant_integration_test.go`) с testcontainers Postgres:
   - `TestGrant_Idempotent` — два последовательных Grant на тот же subject → ровно одна row, второй INSERT ON CONFLICT DO NOTHING.
   - `TestGrant_ConcurrentSameSubject` — 10 goroutines одновременно Grant того же subject → ровно одна row, остальные no-op (partial UNIQUE отрабатывает).
   - `TestRevoke_LastAdmin_Sequential` — единственный active admin пытается revoke → 0 rows updated → typed `ErrLastAdmin`.
   - `TestRevoke_ConcurrentLastAdmin` — 2 active admin'а (S1, S2), 2 goroutines одновременно вызывают revoke друг друга → **ровно одна** транзакция проходит (count downto 1), вторая получает 0 rows updated → `ErrLastAdmin`. CAS-WHERE с subquery `count(*) > 1` гарантирует атомарность.
   - `TestRevoke_Self` — admin пытается revoke self (subject_id == principal_id) → `ErrSelfRevoke`.
   - `TestRevoke_NotAdmin` — revoke non-existent admin → `ErrNotFound`.
   - `TestRevoke_AlreadyRevoked` — revoke admin, у которого row с `granted_until IS NOT NULL` (history присутствует, active row нет) → `ErrNotFound` (D-12, asymmetric с Grant idempotency).
   - `TestGrantRevoke_ConcurrentSameSubject` — 1 goroutine Grant(U2), 1 goroutine Revoke(U2) запускаются одновременно. Два acceptable исхода: (a) Grant first, then Revoke → row создаётся, затем `granted_until` set, last-admin-guard НЕ срабатывает (т.к. в setup есть baseline admin S, count>1); (b) Revoke first → `ErrNotFound` (нет active row), затем Grant создаёт row. **Invariant** (verified тестом): (i) нет финального состояния с >1 active row для subject U2; (ii) нет deadlock'а (оба goroutine завершаются за <5s); (iii) каждый goroutine возвращает либо success либо типизированный sentinel — не panic, не leak `pgx`-error. **Documentation в test header** объясняет non-determinism и invariant.
   - `TestList_JoinsUsers` — admin с populated users-row → display_name/email в результате.
   - `TestGet_Singleton` — `cluster_kacho_root` row уже есть (миграция 0011 seed); Get возвращает её.
   - `TestGrant_OpenFGAOutage` — FGAOutboxDrainer не может достучаться до OpenFGA (testcontainers тушит openfga-pod на 30+s mid-test). Setup: Grant(U2) → row в `cluster_admin_grants` ✓, row в `fga_outbox` ✓, Operation done=false. После 30s retry-exhaustion drainer переводит Operation в `done=true, error.code=Unavailable`. Verify: (i) row в `cluster_admin_grants` есть (TX committed independent от FGA); (ii) FGA tuple отсутствует (поднимаем openfga-pod после теста, Read возвращает empty — drainer уже отказался retry); (iii) **после поднятия openfga drainer переписывает tuple** (next outbox-scan tick), tuple появляется в FGA, **но** Operation остаётся в terminal `done=true, error=Unavailable` state — no resume (fail-fast acceptable per D-13). Documentation в test header объясняет async-divergence: Operation reflects time-of-execution state, не final FGA convergence; UI должна делать refresh после Operation error чтобы увидеть actual tuple state. См. D-13.

- [ ] **Newman cases** (`kacho-iam/tests/newman/cases/cluster_admin.py` → `gen.py` → `*.postman_collection.json`) — **12 кейсов**:
   - `CLUSTER-ADMIN-GET-OK` — system_admin S вызывает GET `/iam/v1/internal/cluster` → 200 с `{id: "cluster_kacho_root", name, description, created_at}` (KAC-196-00).
   - `CLUSTER-ADMIN-GET-403-ORDINARY` — ordinary user U3 → GET `/iam/v1/internal/cluster` → 403 Permission denied.
   - `CLUSTER-ADMIN-GRANT-OK` — system_admin grants new admin → 200 Operation → poll until done=true → ListAdmins shows new entry.
   - `CLUSTER-ADMIN-GRANT-403-ORDINARY` — ordinary user attempts Grant → 403 PermissionDenied.
   - `CLUSTER-ADMIN-GRANT-400-INVALID-USER` — Grant with `usr_nonexistent00000000` → 400 InvalidArgument.
   - `CLUSTER-ADMIN-GRANT-OK-IDEMPOTENT` — повторный Grant того же subject → 200 Operation (no-op, success, D-4).
   - `CLUSTER-ADMIN-REVOKE-OK` — Grant admin A, then Revoke admin A → 200 Operation → ListAdmins не показывает A.
   - `CLUSTER-ADMIN-REVOKE-403-SELF` — admin revokes self → 403 FailedPrecondition `"cannot revoke own cluster admin grant"`.
   - `CLUSTER-ADMIN-REVOKE-403-LAST` — последний admin → 403 FailedPrecondition `"cannot revoke last active cluster admin"`.
   - `CLUSTER-ADMIN-REVOKE-404-NOT-ADMIN` — revoke user, никогда не бывшего admin → 404 NotFound (D-12).
   - `CLUSTER-ADMIN-LIST-OK` — system_admin → 200 with admins[].
   - `CLUSTER-ADMIN-LIST-403-ORDINARY` — ordinary → 403.
   - `CLUSTER-ADMIN-INTERNAL-NOT-ON-EXTERNAL-TLS` — POST на public TLS endpoint → 404.

   **Note**: total = 13 newman cases (1 GET-OK + 1 GET-403 + 4 Grant + 4 Revoke + 2 List + 1 Internal-not-on-TLS). Round-2 minimum bumped to 12; actual count 13 includes one extra Revoke negative (404 NotFound) and one extra List negative (403). Если reviewer хочет ровно 12 — кейс `CLUSTER-ADMIN-REVOKE-404-NOT-ADMIN` обязателен (D-12 contract), а `CLUSTER-ADMIN-LIST-403-ORDINARY` имеет zero marginal value поверх `CLUSTER-ADMIN-GET-403-ORDINARY` и `CLUSTER-ADMIN-GRANT-403-ORDINARY` — его можно убрать. Acceptance-author оставляет все 13 как explicit-per-RPC coverage.

- [ ] **TDD-RED→GREEN evidence** (workspace §«Запреты» #12): в PR-описании kacho-iam привести лог:
   - integration tests run против main → 11 FAIL (test functions не существуют);
   - newman gen + run против main → 13 FAIL (cases не существуют либо handler возвращает Unimplemented);
   - после реализации → all GREEN.

### 5.6 Vault updates (workspace §«Obsidian vault» — обязательный trail)

- [ ] [[../obsidian/kacho/rpc/iam-internal-cluster-service]] — `status: planned → done`, `methods_count: 0 → 4`, обновить таблицу методов (Phase column → удалить, methods реализованы).
- [ ] [[../obsidian/kacho/resources/iam-cluster-admin-grant]] — `status: planned → done`; добавить раздел «RPC operations» со ссылкой на handler.
- [ ] [[../obsidian/kacho/resources/iam-cluster]] — `status: planned → done`; обновить «Lifecycle» (Get RPC доступен).
- [ ] **NEW** [[../obsidian/kacho/packages/iam-handler-internal-cluster]] — узкий файл (1-3KB) с описанием handler-пакета: exported types, imports, imported-by.
- [ ] **NEW** [[../obsidian/kacho/packages/iam-apps-cluster-usecases]] — узкий файл с 4 use-cases.
- [ ] **NEW** [[../obsidian/kacho/edges/ui-to-apigw-cluster-admins]] — описание UI→API-gateway edge (REST contract, sync vs async, error handling).
- [ ] [[../obsidian/kacho/KAC/KAC-196]] — RESOLVED 2026-05-25: KAC-196 в YouTrack — это cluster-RBAC ticket (этот acceptance-doc); vault-заметка KAC-196.md (если предзаписана под другую тему) переименовать в KAC-195.md или удалить; vault предзаписан без YT-привязки. **Действие**: создать новый `obsidian/kacho/KAC/KAC-196.md` с trail этого тикета (см. §«Obsidian vault» — KAC-тикеты обязательный trail).
- [ ] [[../obsidian/kacho/KAC/KAC-178]] — добавить ссылку на KAC-196 в «followup» / «closes followups», обновить DoD-чек-лист, если этот тикет закрывает «cluster admin tooling» gap.

---

## 6. Сценарии (Given-When-Then)

> Каждый сценарий имеет уникальный **ID** (`KAC-196-NN`) для трассировки к integration / newman / Playwright тестам.

> *Notation*: `usr_<TAG>___…___` в сценариях — placeholder для читаемости. Real id matches
> `^usr_[0-9a-hjkmnp-tv-z]{17}$` (crockford-base32, 17 chars после префикса; `_` и `o`/`i`/`l`/`u`
> не входят в crockford-alphabet). Integration tests генерят валидные ids через `ids.NewID("usr")`;
> newman cases используют hard-coded валидные ids из bootstrap-seed (`usr_s00000000000000000` для
> bootstrap admin, etc.).

---

### Сценарий 00: Get — happy path

**ID:** KAC-196-00

**Given** stand развёрнут, `kacho-iam` запущен; миграция 0011 seeded `clusters` row для
`cluster_kacho_root` (`id=cluster_kacho_root, name="Kachō Root Cluster", description="...", created_at=<seed-ts>`).
**And** admin S активен (через bootstrap).
**And** клиент аутентифицирован как S.

**When** клиент вызывает `GET /iam/v1/internal/cluster` (REST) /
`kacho.cloud.iam.v1.InternalClusterService.Get` (gRPC) с пустым body.

**Then** ответ — `200 OK` с телом `{id: "cluster_kacho_root", name: "Kachō Root Cluster", description: "...", created_at: "<seed-ts>"}`.
**And** ответ — sync (Operation envelope НЕ возвращается; D-3/D-11 gate проходит, sync read).

**Newman**: `CLUSTER-ADMIN-GET-OK`. Дополнительно ordinary user U3 → 403 (`CLUSTER-ADMIN-GET-403-ORDINARY`).

---

### Сценарий 01: GrantAdmin — happy path

**ID:** KAC-196-01

**Given** stand развёрнут, `kacho-iam` запущен с bootstrap-admin `s@prorobotech.ru` (через
`KACHO_IAM_BOOTSTRAP_ROOT_EMAIL`); этот admin получил `cluster:cluster_kacho_root#system_admin@user:usr_s00000000000000000`
через bootstrap-seed (запись в `cluster_admin_grants` + FGA tuple).
**And** в `kacho_iam.users` есть user U2 с валидным id (например `usr_u2000000000000000`) — через signup-flow.
**And** клиент аутентифицирован как S (JWT principal_id = `usr_s00000000000000000`).

**When** клиент вызывает `POST /iam/v1/internal/cluster/admins` (REST) /
`kacho.cloud.iam.v1.InternalClusterService.GrantAdmin` (gRPC) с payload:
- `subject_type = "user"`
- `subject_id = "usr_u2000000000000000"`

**Then** ответ — `200 OK` с телом `Operation { id: "op_...", done: false, metadata: {cluster_admin_grant_id: "cag_...", subject_id: "usr_u2000000000000000"} }`.
**And** в `kacho_iam.cluster_admin_grants` появилась row `{cluster_id: cluster_kacho_root, subject_type: user, subject_id: usr_u2000000000000000, granted_by: usr_s00000000000000000, granted_at: <now>, granted_until: NULL}`.
**And** в `kacho_iam.fga_outbox` появилась row `{op: write, tuple_key: {object: cluster:cluster_kacho_root, relation: system_admin, user: user:usr_u2000000000000000}}`.
**And** в `kacho_iam.audit_outbox` появилась row `{event: cluster_admin_granted, grant_id, subject_id, principal_id: usr_s00000000000000000}`.
**And** в течение **≤2s** poll `OperationService.Get(op_id)` возвращает `done=true, response=<ClusterAdminGrant>`.
**And** в течение **≤2s** OpenFGA Read возвращает tuple `cluster:cluster_kacho_root#system_admin@user:usr_u2000000000000000`.
**And** после этого U2 (после relogin / refresh JWT) может вызвать любой catalog admin RPC, требующий `cluster.admin` permission (например `InternalRegionService.Create` — KAC-178 §3 admin-only).

---

### Сценарий 02: GrantAdmin — gate enforcement

**ID:** KAC-196-02

**Given** stand готов.
**And** в кластере есть admin S (как в §01).
**And** есть ordinary user U3 (НЕ admin) — без записи в `cluster_admin_grants`.
**And** клиент аутентифицирован как U3.

**When** U3 вызывает `POST /iam/v1/internal/cluster/admins` с любым валидным payload.

**Then** ответ — `403 Forbidden` (gRPC `PermissionDenied`).
**And** error message: `"Permission denied"` (capitalized; standard gate-message, не leak `admin`/`system_admin`).
**And** в `kacho_iam.cluster_admin_grants` НЕ появилось новых rows.
**And** в `kacho_iam.fga_outbox` НЕ появилось новых rows.

---

### Сценарий 03: GrantAdmin — idempotent

**ID:** KAC-196-03

**Given** stand готов, admin S активен.
**And** U2 уже admin (`cluster_admin_grants` row с granted_until=NULL существует, FGA tuple существует).

**When** S вызывает GrantAdmin для U2 повторно.

**Then** ответ — `200 OK` с `Operation { done: false }`, metadata содержит `cluster_admin_grant_id` существующей row (НЕ новой).
**And** в `kacho_iam.cluster_admin_grants` остаётся **ровно одна** active row для U2 (никаких дубликатов).
**And** в `kacho_iam.fga_outbox` появилась row (повторный Write — FGA сама дедуплицирует на existing tuple; outbox-drainer на success помечает sent=true).
**And** Operation становится `done=true` в течение ≤2s.

---

### Сценарий 04: GrantAdmin — invalid user

**ID:** KAC-196-04

**Given** admin S активен.

**When** S вызывает GrantAdmin с `subject_id = "usr_nonexistent00000"` (валидный регекс, но user в `kacho_iam.users` не существует).

**Then** ответ — `400 Bad Request` (gRPC `InvalidArgument`).
**And** error message: `"User usr_nonexistent00000 not found"` (YC-style).
**And** в `kacho_iam.cluster_admin_grants` нет новых rows.
**And** в `kacho_iam.fga_outbox` нет новых rows.

---

### Сценарий 05: GrantAdmin — invalid subject_type

**ID:** KAC-196-05

**Given** admin S активен.

**When** S вызывает GrantAdmin с `subject_type = "service_account"`, `subject_id = "sva_..."`.

**Then** ответ — `400 Bad Request` (gRPC `InvalidArgument`).
**And** error message: `"Illegal argument subject_type: only 'user' supported in this version"`.

---

### Сценарий 06: RevokeAdmin — happy path

**ID:** KAC-196-06

**Given** admin S активен; U2 также admin (granted via §01).
**And** клиент аутентифицирован как S.

**When** S вызывает `DELETE /iam/v1/internal/cluster/admins/usr_u2000000000000000`.

**Then** ответ — `200 OK` с `Operation { id, done: false, metadata: {cluster_admin_grant_id, subject_id: usr_u2000000000000000} }`.
**And** в `kacho_iam.cluster_admin_grants` row для U2 имеет `granted_until = <now>`, row НЕ удалена (history).
**And** в `kacho_iam.fga_outbox` появилась row `{op: delete, tuple_key: {... user:usr_u2000000000000000 ...}}`.
**And** в `kacho_iam.audit_outbox` появилась row `{event: cluster_admin_revoked, ...}`.
**And** в течение ≤2s `OperationService.Get` возвращает `done=true`.
**And** в течение ≤2s OpenFGA tuple исчез (Read возвращает empty).
**And** U2 (после relogin / cache TTL ≤5s) больше НЕ может вызывать catalog admin RPCs (получает `403 PermissionDenied`, message `"Permission denied"`).

---

### Сценарий 07: RevokeAdmin — self-protection

**ID:** KAC-196-07

**Given** admins S1 и S2 активны.
**And** клиент аутентифицирован как S1.

**When** S1 вызывает RevokeAdmin для собственного `subject_id` (`usr_s1...`).

**Then** ответ — `403 Forbidden` (gRPC `FailedPrecondition`).
**And** error message: `"cannot revoke own cluster admin grant"`.
**And** row для S1 не изменилась (`granted_until` остался NULL).
**And** FGA tuple для S1 не удалён.

---

### Сценарий 08a: RevokeAdmin — last-admin protection (sequential)

**ID:** KAC-196-08a

**Given** admins S1 и S2 активны (count=2).
**And** emergency_admin EM активен через test-only fixture: insert row в `kacho_iam.cluster_break_glass_grants` (state=ACTIVE) + enqueue fga_outbox tuple `cluster:cluster_kacho_root#emergency_admin@user:usr_em...` в той же TX (миграция 0011 уже создаёт `cluster_break_glass_grants` таблицу, см. строки 127-164 migration). Это симулирует Phase 7 `RequestBreakGlass+ApproveBreakGlass` flow без полной импл'а Phase 7 — `kubectl exec` НЕ используется.
**And** клиент аутентифицирован как S1.

**When (step 1)** S1 вызывает RevokeAdmin для S2 → `200 OK Operation` (count=2→1 на момент UPDATE; UPDATE WHERE `count(*) > 1` отрабатывает: count==2, условие true, row updates).
**And** Operation становится done=true; в `cluster_admin_grants` row S2 имеет `granted_until = <now>`; count active = 1 (только S1; EM в другой таблице `cluster_break_glass_grants`, не считается last-admin guard'ом).

**When (step 2)** клиент аутентифицируется как EM (cluster_break_glass_grant — проходит D-11 gate как `emergency_admin → admin`).
**And** EM вызывает RevokeAdmin для S1.

**Then** ответ — `403 Forbidden` (gRPC `FailedPrecondition`).
**And** error message: `"cannot revoke last active cluster admin"`.
**And** row для S1 не изменилась (`granted_until` остался NULL).
**And** FGA tuple для S1 не удалён.

---

### Сценарий 08b: RevokeAdmin — last-admin protection (concurrent race, integration-only)

**ID:** KAC-196-08b (integration test only — Newman не покрывает race)

**Given** admins S1 и S2 активны (count=2). Никаких других admin-grants.

**When** 2 goroutines одновременно вызывают:
- goroutine A: Revoke(S2) от лица admin X (отдельный admin, чтобы не триггерить self-revoke; для теста — fixture-added admin X с count=3 → ровно одна revoke удалит до count=2, другая — до count=1).

Для упрощения теста используем setup count=2 (S1, S2) и 2 goroutines:
- goroutine A: Revoke(S2) от лица S1.
- goroutine B: Revoke(S1) от лица S2.

**Then** одна из двух транзакций commit'ится first (благодаря row-lock на UPDATE), её CAS-WHERE `count(*) > 1` matches (count=2 в момент start), UPDATE сработал → count=1.
**And** вторая транзакция дожидается commit'а первой, видит count=1 в её subquery, CAS-WHERE `> 1` НЕ matches → 0 rows updated → возвращает `ErrLastAdmin`.
**Invariant**: финальное состояние — ровно один из {S1, S2} active, другой revoked. Никаких deadlock'ов; обе горутины завершаются за <5s; никаких panic / leak'ов pgx-error.

**Documentation в test header**: non-determinism — какой именно admin (S1 vs S2) выживет, зависит от расписания goroutine. Тест проверяет: (i) exactly one survives; (ii) other goroutine gets `ErrLastAdmin`, не silent success; (iii) no deadlock.

---

### Сценарий 09: RevokeAdmin — non-existent admin

**ID:** KAC-196-09

**Given** admin S активен.

**When** S вызывает RevokeAdmin с `subject_id = "usr_neveradmin000000"` (валидный регекс, но user НЕ в `cluster_admin_grants` ни в одной row — ни active, ни revoked).

**Then** ответ — `404 Not Found` (gRPC `NotFound`).
**And** error message: `"User usr_neveradmin000000 is not an active cluster admin"` (YC-style; D-12).
**And** state не меняется.

---

### Сценарий 09b: RevokeAdmin — previously-revoked admin

**ID:** KAC-196-09b

**Given** admin S активен.
**And** subject U2 имеет row в `cluster_admin_grants` с `granted_until IS NOT NULL` (history present, active row absent — U2 был admin, revoked ранее).

**When** S вызывает RevokeAdmin для U2.

**Then** ответ — `404 Not Found` (gRPC `NotFound`).
**And** error message: `"User usr_u2000000000000000 is not an active cluster admin"` (D-12 — асимметрия с Grant idempotency: revoke explicit per-row, не silent no-op).
**And** state не меняется (history row остаётся как есть, новых row'ей не появляется).

---

### Сценарий 10: ListAdmins — happy path

**ID:** KAC-196-10

**Given** admins S, U2, U4 активны; U3 был admin, но revoked.
**And** клиент аутентифицирован как S.

**When** S вызывает `GET /iam/v1/internal/cluster/admins`.

**Then** ответ — `200 OK` с `{admins: [<S entry>, <U2 entry>, <U4 entry>]}` (порядок — по `granted_at ASC`).
**And** каждый entry содержит populated `subject_email`, `subject_display_name`, `granted_by_email`.
**And** U3 НЕ в списке (revoked, `granted_until IS NOT NULL`).

---

### Сценарий 11: ListAdmins — gate

**ID:** KAC-196-11

**Given** в кластере есть admins.
**And** клиент аутентифицирован как ordinary user U3.

**When** U3 вызывает `GET /iam/v1/internal/cluster/admins`.

**Then** ответ — `403 Forbidden`.
**And** error message: `"Permission denied"`.

---

### Сценарий 12: emergency_admin gate pass

**ID:** KAC-196-12

**Given** test-only fixture (Phase 7 ещё НЕ реализован, эмулируем результирующее state без RPC):
insert row в `kacho_iam.cluster_break_glass_grants` (`subject_type=user, subject_id=usr_em..., state=ACTIVE, approved_at=<now>, approved_by=<bootstrap>`) + enqueue fga_outbox tuple `cluster:cluster_kacho_root#emergency_admin@user:usr_em...` в той же TX. Миграция 0011 уже создаёт `cluster_break_glass_grants` таблицу (см. строки 127-164 migration), поэтому fixture — обычный SQL insert + outbox enqueue. **`kubectl exec` НЕ требуется** — control-plane сценарий целиком.
**And** в `kacho_iam.cluster_admin_grants` НЕТ row'и для EM (emergency_admin живёт в `cluster_break_glass_grants` — Phase 7 lifecycle отдельно).
**And** OpenFGA после outbox-drainer (≤2s) содержит tuple `cluster:cluster_kacho_root#emergency_admin@user:usr_em...`.
**And** клиент аутентифицирован как EM.

**When** EM вызывает GrantAdmin для нового user U5.

**Then** ответ — `200 OK Operation { done: false, metadata: {cluster_admin_grant_id, subject_id: usr_u5...} }`.
**And** D-11 gate (`required_relation=admin`) проходит — OpenFGA Check `(user:usr_em..., admin, cluster:cluster_kacho_root)` возвращает true благодаря cascade `emergency_admin → admin` (`fga_model.fga:89` `define admin: system_admin or emergency_admin`).
**And** row для U5 появляется в `cluster_admin_grants` с `granted_by=usr_em...` (audit trail записывает emergency_admin как actor).
**And** в течение ≤2s Operation done=true; FGA tuple `cluster:...#system_admin@user:usr_u5...` создан.

**Rationale (D-11)**: emergency_admin существует именно для recovery после lock-out (все
system_admin откатились или revoked друг друга). Если gate был бы raw `system_admin`,
emergency_admin не мог бы создать первого нового system_admin → recovery требует DB-seed
restart, что обнуляет бизнес-смысл break-glass. С gate = `admin` (computed) каскад работает.

---

### Сценарий 13: Internal-only endpoint NOT exposed on external TLS

**ID:** KAC-196-13

**Given** stand развёрнут с `api.kacho.local:443` (external TLS) и internal cluster-internal listener.

**When** анонимный клиент POST'ает на `https://api.kacho.local/iam/v1/internal/cluster/admins` body `{subject_type:"user", subject_id:"usr_..."}`.

**Then** ответ — `404 Not Found` (route не зарегистрирован в public gw).
**And** в логах api-gateway видно `route not matched` (НЕ 403 от authz — это раньше, на routing-level).

**When** клиент с валидным JWT обращается на тот же URL.
**Then** тоже `404` (тот же reason — route не существует на public mux).

---

### Сценарий 14: UI — admins page render + grant flow

**ID:** KAC-196-14 (Playwright)

**Given** UI deployed; admin S залогинен в /system.

**When** S переходит на `/system/cluster/admins`.

**Then** видна таблица с текущими admin'ами (минимум сам S).
**And** колонки: Email, Display name, Granted by, Granted at, Actions.
**And** кнопка `Добавить admin` (header).
**And** row S имеет disabled-кнопку «Отозвать» с tooltip «Cannot revoke self».
**And** если active admin count == 1, у row S дополнительно tooltip «Cannot revoke last admin».

**When** S кликает `Добавить admin` → открывается модалка с email-search input.
**And** S вводит «u2@example.com» → autocomplete показывает U2 (через `UserService.List filter email`).
**And** S выбирает U2 → нажимает `Выдать`.

**Then** модалка закрывается; toast «Admin granted to U2».
**And** в течение ≤3s таблица перерендерилась — теперь содержит row U2.

---

### Сценарий 15: UI — ordinary user → 403

**ID:** KAC-196-15 (Playwright)

**Given** ordinary user U3 залогинен.

**When** U3 переходит на `/system/cluster/admins`.

**Then** UI либо показывает 403-страницу («Недостаточно прав»), либо редиректит на `/dashboard` с toast «Forbidden».
**And** GET к `/iam/v1/internal/cluster/admins` (если UI делает оптимистический запрос) возвращает 403 — UI обрабатывает gracefully.

---

### Сценарий 16: Operation.created_by propagated correctly (W1.4)

**ID:** KAC-196-16

**Given** admin S активен; клиент аутентифицирован как S (principal_id=usr_s00000000000000000).

**When** S вызывает GrantAdmin для U2 → возвращается Operation op_X.
**And** клиент вызывает `OperationService.Get(op_X)`.

**Then** ответ содержит `created_by = "usr_s00000000000000000"` (не `"anonymous"`, не пусто).

> Этот сценарий — проверка, что W1.4 principal propagation (KAC-178 §2, kacho-compute#31 / kacho-iam main wiring `UnaryPrincipalExtract`) работает в `kacho-iam` главном процессе. Если acceptance-reviewer обнаружит, что kacho-iam ещё не mount'ит этот interceptor — это блокер.

---

### Сценарий 17: OpenFGA outage during Operation poll (resilience)

**ID:** KAC-196-17

**Given** admin S активен; openfga-pod работает нормально на начало сценария.
**And** клиент аутентифицирован как S.

**When** S вызывает GrantAdmin для U2 → ответ `200 OK Operation { done: false, metadata: {cag_id, subject_id: usr_u2...} }`.
**And** **immediately после** Grant-call testcontainers/Compose останавливает openfga-pod (`docker compose stop openfga`) — drainer теряет connectivity к OpenFGA.
**And** клиент начинает poll `OperationService.Get(op_id)` каждые 2s.

**Then** после INSERT в `cluster_admin_grants` (commit'нулся independent от FGA — DB-TX не включает FGA-RPC) row для U2 видна в `cluster_admin_grants` (`granted_until=NULL`).
**And** row в `fga_outbox` присутствует (`{op: write, tuple_key: ..., attempts: 0, last_error: NULL}` сначала; drainer инкрементит `attempts` и пишет `last_error="connection refused"` на каждом retry).
**And** в течение **30s** drainer делает retry-attempts (с exponential backoff: 1s, 2s, 4s, 8s, 15s, …) — `attempts` растёт, `last_error` накапливается.
**And** после 30s retry-exhaustion drainer marks `fga_outbox` row как `failed_terminal=true`, **OR** worker `OperationsWorker` (corelib) видит этот terminal state и переводит Operation в terminal:
- poll `OperationService.Get(op_id)` теперь возвращает `Operation { done: true, error: { code: 14 (UNAVAILABLE), message: "OpenFGA unavailable, tuple-write retry exhausted" } }`.

**And** OpenFGA tuple `cluster:cluster_kacho_root#system_admin@user:usr_u2...` **отсутствует** в FGA (Read возвращает empty), т.к. ни одна write-attempt не успешна.

**When (recovery)** openfga-pod поднимается обратно (`docker compose start openfga`).
**Then** на **next outbox-scan tick** (≤10s) drainer повторяет неуспешный `fga_outbox` row (если он остался `failed_terminal=false`, или если retry-policy включает permanent-retry); tuple **появляется** в FGA Read.
**But** Operation `op_id` остаётся в terminal `done=true, error=Unavailable` state — **no resume** (Operation status — это reflection of execution time-window, не final FGA convergence; см. D-13).

**Verification**:
- `kacho_iam.cluster_admin_grants` row для U2 — присутствует, `granted_until=NULL` (DB invariant сохранён).
- OpenFGA tuple — eventually present (после recovery).
- `OperationService.Get(op_id)` — `done=true, error=Unavailable`.
- UI semantic: пользователь видит ошибку в Operation, нажимает «Refresh» в admin-table → `ListAdmins` показывает U2 (т.к. `cluster_admin_grants` row есть). Async-divergence acceptable per D-13.

**Документация в integration-test header**: explain fail-fast Operation contract — Operation status НЕ promise about final FGA state (acceptable trade-off; alternative — bi-directional sync с rollback DB row при FGA-failure — gives stronger consistency но требует cross-system 2-phase commit, overkill для admin-tooling).

---

## 7. Риски и mitigation

| ID | Риск | Mitigation |
|---|---|---|
| R-1 | **OpenFGA model_id mismatch** — drain пишет в старый model, но handler / Check читает из нового → tuple не виден | Existing `kacho-iam-openfga-store` Secret содержит current `model_id`; drainer и Check читают из одного источника (env / config) — гарантия атомарной смены через bootstrap-job. KAC-178 уже refresh model_id; этот тикет не меняет model. |
| R-2 | **Concurrent revoke вызывает race на last-admin guard** | Mitigation в самой CAS-UPDATE `WHERE … AND (SELECT count(*) … > 1)` — single-statement subquery атомарна; integration test `TestRevoke_ConcurrentLastAdmin` (KAC-196-08b) проверяет. |
| R-3 | **Self-revoke через косвенный путь** — admin revoke'ит admin X, который через минуту revoke'ит исходного admin'а → lock-out | НЕ предотвращаем — это легитимный сценарий (admins взаимно revoke'ят); last-admin guard защищает только финальный «count→0» переход. |
| R-4 | **UI race** — admin S кликает Revoke на U2, U2 одновременно теряет права mid-session → текущие запросы U2 в полёте могут пройти gate (cache TTL=5s) | Acceptable per KAC-178 W2 design — eventually consistent ≤10s; явно описано в design-doc. |
| R-5 | **`emergency_admin` gate semantic** | **RESOLVED per D-11**: gate = `admin` (computed), каскад `system_admin OR emergency_admin` обрабатывается OpenFGA напрямую. Сценарий KAC-196-12 проверяет каскад; integration-test fixture для emergency_admin симулирует Phase 7 state без `kubectl exec`. |
| R-6 | **Bootstrap admin overlap** — если ENV `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL` сидит admin'а X, но потом X revoked через RPC; restart → seed re-creates row → conflict | Partial UNIQUE `(subject_type, subject_id) WHERE granted_until IS NULL` — INSERT ON CONFLICT DO NOTHING handle'ит грациозно (warning log); existing seed flow совместим. |
| R-7 | **KAC-196 ticket-id collision** | **RESOLVED 2026-05-25 per user clarification**: KAC-196 в YouTrack = cluster-RBAC ticket (этот acceptance-doc); vault refactor-trail для Wave A markers cleanup остался под KAC-195 (vault предзаписан без YT-привязки). Vault-заметка `obsidian/kacho/KAC/KAC-196.md` создаётся под этот тикет; если предзапись с другим content существует — переименовать в KAC-195.md или удалить. |
| R-8 | **OpenFGA outage corrupts Operation status semantic** — Operation reports error=Unavailable, но после recovery tuple появляется → user видит divergence между Operation и actual FGA state | Acceptable per D-13 — Operation reflects execution-window state; UI должна refresh ListAdmins после Operation error чтобы увидеть actual state. Документировано в §6.17 test header. Alternative (2-phase commit с rollback DB row) — overkill для admin-tooling. |

---

## 8. Открытые вопросы для `acceptance-reviewer`

1. ~~`required_relation` для gate~~ → **RESOLVED → D-11** (gate = `admin` computed alias).
2. ~~KAC-196 ticket-id collision~~ → **RESOLVED 2026-05-25** per user clarification (см. R-7).
3. ~~Revoke non-existent admin: 404 vs idempotent 200~~ → **RESOLVED → D-12** (404 NotFound, асимметрично с Grant idempotency, UI semantic per-row explicit).
4. **§5.5 last-admin guard implementation** — реализовать через CAS-UPDATE с subquery `count(*) > 1` (предложено) ИЛИ через advisory lock + SELECT-COUNT-then-UPDATE (более явный, но 2 statements)? Default — CAS с subquery (атомарно single-statement, никаких advisory locks). **Если reviewer одобряет default — close as resolved**.
5. **§4.4 ListAdmins pagination** — НЕТ pagination сейчас (admins ≤50). Reviewer подтверждает scope, либо добавить `page_token`/`page_size`?
6. **D-13 OpenFGA outage Operation semantic** — fail-fast Operation (proposed) vs Operation resume after FGA recovery (alternative)? Default — fail-fast (см. R-8 rationale). Если reviewer выберет resume-after-recovery — потребуется extra worker logic для re-poll terminal Operations + изменения в OperationsWorker contract (сейчас terminal == final).

---

## 9. Trail

- Vault: [[../obsidian/kacho/rpc/iam-internal-cluster-service]] (planned), [[../obsidian/kacho/resources/iam-cluster-admin-grant]] (planned, schema ready через миграцию 0011), [[../obsidian/kacho/resources/iam-cluster]] (planned), [[../obsidian/kacho/resources/iam-cluster-break-glass-grant]] (Phase 7 lifecycle отдельно; KAC-196 использует только existing таблицу для test-fixture), [[../obsidian/kacho/KAC/KAC-178]] (parent epic, cluster admin/editor aliases done), [[../obsidian/kacho/KAC/KAC-127]] (W1.4 propagation context).
- Specs: `docs/specs/sub-phase-2.0-iam-overview-acceptance.md`, `docs/specs/sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md` (E3 OpenFGA REBAC base), `docs/specs/2026-05-24-stand-prod-readiness-design.md` (KAC-178 design).
- Existing seed: `kacho-iam/internal/packages/iam-seed/bootstrap_admin.go` (env `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL`).
- FGA model: `kacho-deploy/openfga/fga_model.fga` (line 89: `define admin: system_admin or emergency_admin` — основание для D-11).
- Workspace `CLAUDE.md` §«Запреты» #6 (Internal not on external TLS), #10 (DB-level refs), #11 (no tech-debt), #12 (test-first).
