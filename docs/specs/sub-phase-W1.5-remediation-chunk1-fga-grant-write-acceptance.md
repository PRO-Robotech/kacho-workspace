# Sub-phase W1.5 — Remediation Chunk 1: DB/FGA grant-write desync — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` per workspace `CLAUDE.md` §Запреты #1).
> **Date**: 2026-05-24
> **YouTrack**: KAC-141 W1.5 (subtask of [KAC-136](https://prorobotech.youtrack.cloud/issue/KAC-136), child of epic [KAC-134](https://prorobotech.youtrack.cloud/issue/KAC-134) "kacho-iam → production-ready"). KAC-141 issue created post-APPROVED.
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-iam` — `internal/authzmap/`, `internal/apps/kacho/api/access_binding/{create,delete,tuples,helpers}.go`, `internal/service/{phase7_jit_service,jit_pending_service,phase7_break_glass_service,phase7b_workers,phase7_workers}.go`, optional new helper for `fga_outbox` INSERT.
>   - **NOT touched (verified)**: `kacho-corelib` (generic `Drainer[T]` from W1.1 unchanged); `kacho-proto` (no new RPC / field — payload schema for `fga_outbox` is the existing `{"user","relation","object"}` 3-tuple — see §3.1); `kacho-api-gateway` (drainer already applies to OpenFGA; ditto for subject-change cache).
> **Branch (all repos)**: `KAC-141` (off `main`).
> **Parent epic plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 1.
> **Wave plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-wave1.md` §W1.5.
> **Source of finding-level requirements**: `docs/superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` §1.3 Chunk 1 (findings #8, #16, #47, #48, #50, #51, #52).
> **Predecessors (must be `main`-merged before impl starts)**:
> - W1.1 — `fga_outbox` drainer ([[KAC-137]]) — **MERGED** 2026-05-23. Drainer reads `kacho_iam.fga_outbox`, calls `OpenFGAClient.WriteTuples`/`DeleteTuples`, marks `sent_at`.
> - W1.2 — `subject_change_outbox` push-drain + per-subject cache invalidation ([[KAC-138]]) — **MERGED**. Provides the atomic emit-in-tx pattern (`SubjectChangeEmitter.EmitTx`) which W1.5 mirrors for `fga_outbox` writes in JIT/BG paths.
> - W1.3 — gateway authz fail-closed — MERGED.
> - W1.4 — principal propagation cross-service — IN PROGRESS at draft time; W1.5 impl may proceed in parallel (no file overlap), but W1.5 newman cases that rely on cross-service authority (vpc.networks.get propagation) need W1.4 GREEN to fully verify.

---

## 0. Преамбула — что эта sub-итерация (précis)

W1.5 закрывает **корневую патологию** authz-стека kacho-iam: «OpenFGA не является надёжным
источником истины — три grant-пути из четырёх не пишут tuple, единственный пишущий маппит по
имени роли». После W1.1 (drainer работает) и W1.2 (atomic emit-in-tx pattern доступен через
`SubjectChangeEmitter`) появляется техническая возможность **унифицировать ВСЕ FGA-мутации**
(grant/revoke) через `fga_outbox`: emit в той же DB-tx, что и domain-row (binding /
jit-binding / break-glass-grant); drainer асинхронно применяет к OpenFGA с retry и
идемпотентностью.

W1.5 поставляет шесть конкретных изменений (по findings из remediation plan §1.3):

| # | Sev | File:line (verified 2026-05-24) | Симптом | Fix |
|---|---|---|---|---|
| **#47** | P0 | `internal/apps/kacho/api/access_binding/create.go:158-225` (`resolveBindingRelation`+`roleNameToRelation`) | `Create` строит FGA-relation **из ИМЕНИ роли** (`.admin`/`.editor`/`.viewer` → admin/editor/viewer); `role.permissions[]` **не читается** → custom-role с гранулярными permissions схлопывается в viewer / admin / editor (по имени), теряя permission-granularity. | Заменить `roleNameToRelation(role.Name)` на `authzmap.PermissionsToRelations(role.Permissions)` — derive набор FGA-relations из конкретных permission-строк (`vpc.networks.get` → relation `vpc_network_get` ИЛИ standard role `viewer` если все permissions укладываются в seeded preset; точная декомпозиция — см. §3.2 mapping table). Эмит — **N tuples** в `fga_outbox` (по одной row на relation), в той же tx что и binding-row. |
| **#48** | P2 | `internal/apps/kacho/api/access_binding/create.go:224` (`return roleNameToRelation(...)`) + `internal/apps/kacho/api/access_binding/tuples.go:24-115` (`roleNameToRelation` duplicate); `internal/authzmap/role_expand.go:73-84` (`authzmap.RoleNameToRelation` parallel mapper) | Two parallel name-mappers (`tuples.go::roleNameToRelation`, `authzmap.RoleNameToRelation`); `create.go` импортирует первый, второй — мёртвый код. Drift-prone. | Удалить `roleNameToRelation` из `tuples.go` + `resolveBindingRelation` из `create.go`; единственный mapper — `authzmap.PermissionsToRelations` (new). Все callsites переключить на него. |
| **#16** | P2 | `internal/apps/kacho/api/access_binding/create.go:146-172` (`w.Commit(ctx)` на стр. 146, затем `u.fga.WriteTuples` на стр. 161 — non-fatal `logger.Warn` на err) | После commit'а binding-row sync вызывается `OpenFGAClient.WriteTuples`. FGA-ошибка — **non-fatal Warn**. Split-brain: binding в БД, FGA-tuple отсутствует → authz `no path`. | Удалить post-commit sync `WriteTuples` + `Warn`. Вместо этого: **в той же writer-tx, что и binding-Insert + subject_change_outbox emit**, добавить N×INSERT в `fga_outbox (event_type='fga.tuple.write', payload=<tuple-json>)` через новый helper `fgaoutbox.EmitWrite(ctx, tx, []FGATuple)`. На commit fail tx rollback ⇒ ни binding-row, ни outbox rows; drainer не «увидит» orphan'ов. Drainer (W1.1) асинхронно применит. |
| **#8** | P0 | `internal/apps/kacho/api/access_binding/delete.go:116-130` (post-commit sync `u.fga.DeleteTuples`, non-fatal Warn) | Симметричная #16 проблема на revoke-path: `DeleteTuples` после commit'а, non-fatal на err. Если FGA-write fails — binding row удалён, FGA tuple остался → отозванный grant **продолжает grant'ить**. | Удалить post-commit `DeleteTuples` + Warn. **В той же writer-tx, что и binding-Delete + subject_change_outbox emit**, добавить N×INSERT в `fga_outbox (event_type='fga.tuple.delete', payload=<tuple-json>)` через `fgaoutbox.EmitDelete(ctx, tx, []FGATuple)`. Tuples — инверсия того, что писал Create (relation + project-hierarchy если scope=project). |
| **#50** | P0 | `internal/service/phase7_jit_service.go:333-360` (auto-grant path `tx := s.tx.Begin → s.bindings.InsertTx → tx.Commit`; **no FGA emit**) | JIT auto-approve путь INSERT'ит `AccessBinding{Status:ACTIVE}` через `bindings.InsertTx` — **bypass'ит** FGA entirely. Пользователь получает «grant в БД», но authz Check возвращает DENY (no FGA tuple). | После `InsertTx` (до `tx.Commit`) — call `fgaEmitter.EmitWriteTx(ctx, tx, tuplesForBinding(inserted))`. Same tx → atomic. Drainer применит. Помимо этого — emit `subject_change_outbox` event_type=`binding_grant` (parity с AccessBinding.Create, для cache-invalidate чтобы prior negative cache entries пропадали — see open question OQ-W1.5-2). |
| **#51** | P0 | `internal/service/jit_pending_service.go:285-287` (`s.fga.EmitSubjectErasure(ctx, ..., payload)` в Approve path); ditto `jit_pending_service.go:412` для expiry through `ExpirePending`; `internal/service/phase7b_workers.go::JitPendingExpirerWorker.Tick` calls ExpirePending → same emit. | Approve и Expiry вызывают `s.fga.EmitSubjectErasure` — это CAEP **deletion** event (`iam.subject.erased`, GDPR-уровня), **не** grant/revoke FGA mutation. Реального FGA write/delete нет. Approve приводит к ACTIVE binding без FGA tuple; Expiry — к REVOKED binding без FGA-tuple removal. | Approve: заменить `s.fga.EmitSubjectErasure(...)` на `fgaEmitter.EmitWriteTx(ctx, tx, tuplesForBinding(minted))`. Expiry: emit `EmitDeleteTx(ctx, tx, tuplesForBinding(expired))`. `EmitSubjectErasure` оставить **ТОЛЬКО** для GDPR `phase7_gdpr_service.go::EraseSubject` (отдельный путь — subject_erased CAEP push). |
| **#52** | P0 | `internal/service/phase7_break_glass_service.go:248-296` (`ApproveB`: `s.grants.ApproveB` flips state→ACTIVE, audit/CAEP emit, **no `cluster_admin_grants` INSERT, no `fga_outbox` INSERT**) | `ApproveB` flips `cluster_break_glass_grants.state = ACTIVE` + audit/CAEP, но не пишет parity-row в `cluster_admin_grants` и не emit'ит `fga_outbox` write. Subject не получает FGA `cluster:system_admin` tuple → ничего не открывается. Существующий путь parity — `bootstrap_admin.go::Run` (verified строки 90-176) — пишет cluster_admin_grants + fga_outbox + audit_outbox в одной tx. | В ApproveB (после успеха `s.grants.ApproveB`, до `tx.Commit`): (a) INSERT в `cluster_admin_grants(id, cluster_id, subject_type='user', subject_id=<grant.subject_id>, granted_by=<approver_b>, granted_at=now)` — mirror bootstrap_admin §90-120; (b) `fgaEmitter.EmitWriteTx(ctx, tx, []FGATuple{{User:"user:"+subject_id, Relation:"system_admin", Object:"cluster:"+cluster_id}})` — mirror bootstrap_admin §122-151. Atomic с state-flip → tx fail ⇒ ничего из этого не committed. |

### 0.1 W1.5 НЕ включает

- **No new proto / no new RPC** — W1.5 fix internal. `kacho-proto` не трогаем.
- **Не трогает `internal/authzmap/SubjectFGA` / `ObjectFGA`** — они корректны (KAC-WS23 / E3). Меняем только role-mapping (name→permissions).
- **Не добавляет permission-conditions** (FGA conditions, MFA-fresh, source_ip) — это #23 в remediation plan, попадёт в Chunk 5 (W2/W3).
- **Не реализует FGA model v3** с granular permission-relations (вид `vpc_network_get`, `compute_instance_delete`) — W1.5 использует **уже-задеклараренный** FGA model v2 set of relations (`admin`/`editor`/`viewer`/`use`/`member`/`system_admin`/`vpc_network_get` etc если уже seeded). Если задекларированных granular relations не хватает для конкретной permission — **fallback на ближайший standard tier** (`viewer` для read-only permissions, `editor` для write, `admin` для admin) — см. §3.2 mapping table + open question OQ-W1.5-1.
- **Не меняет drainer механику** (W1.1) и не меняет cache-invalidate (W1.2) — переиспользуем as-is.
- **Не трогает other findings из Chunk 2** (#9/#11/#12/#13/#35/#36/#37/#39/#43/#53) — это W1.6.
- **Не меняет `JIT.DenyJITActivation`** / `BreakGlass.Deny` — they уже emit subject_change_outbox через W1.2; не emit'ят fga_outbox **потому что binding never existed** (deny ⇒ pending row never minted to AccessBinding) → no FGA tuple to remove. Verified `phase7_break_glass_service.go:311-345` + `jit_pending_service.go:315-...`.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** | gate данного doc; impl стартует только после APPROVED. |
| **Запрет #2** | в коде/комментариях/тестах не упоминается. |
| **Запрет #3** | handwritten pgx + sqlc; новый helper `fgaoutbox.EmitWriteTx` / `EmitDeleteTx` — handwritten `tx.Exec` (parity с bootstrap_admin.go). Никакого ORM. |
| **Запрет #4** | within-iam-DB только (cluster_admin_grants + fga_outbox + subject_change_outbox + access_bindings — все в `kacho_iam`). Cross-DB cascade отсутствует. |
| **Запрет #5** | `fga_outbox` (мигр. 0002) **не редактируем**; `cluster_admin_grants` (мигр. 0011) **не редактируем**. Опциональная новая миграция `0024_*` (если потребуется доп-индекс или ALTER) — отдельный файл; **default — без новой миграции** (см. §3). |
| **Запрет #6** | `Internal.*` обычная гигиена. Изменения W1.5 не expose'ят новых публичных RPC. |
| **Запрет #7** | broker отсутствует — drainer in-process. |
| **Запрет #8** | DB-per-service — все INSERT'ы в `kacho_iam`-DB. Cross-service FGA write идёт через drainer (in-process HTTP к OpenFGA), не cross-DB. |
| **Запрет #9** | мутации остаются async через Operation envelope. `Create`/`Delete`/JIT/BG возвращают `*operation.Operation` — без изменения. |
| **Запрет #10** (within-service refs DB-level) | **ключевой для W1.5**: каждая binding-mutation + fga_outbox INSERT в **одной** `pgx.Tx` через writer-pattern (mirror W1.2 `SubjectChangeEmitter.EmitTx` + bootstrap_admin §90-176). Rollback tx ⇒ atomic: ни binding-row, ни outbox-row. Integration-тесты с force-Rollback — обязательны (§6.4 W1.5-ROLLBACK-*). |
| **Запрет #11** (test-first + tests-in-PR + RED→GREEN) | каждый из 7 findings закрывается одной парой `RED (failing integration / newman) → GREEN (impl)`. Newman кейсы: `AUTHZ-CUSTOM-ROLE-GRANULAR-PERMISSIONS` (NEW), `AUTHZ-BINDING-CREATE-THEN-CHECK-ALLOW` (NEW), reuses `AUTHZ-REVOKE-ENFORCED-A-INV` (existed since W1.2; will FLIP from current behaviour to verify W1.5-8 атомарного delete-emit), `JIT-AUTO-ACTIVATE-ENFORCED` (NEW), `JIT-PENDING-APPROVE-ENFORCED` (NEW), `JIT-EXPIRY-REVOKES` (NEW), `BREAKGLASS-2APPROVE-ENFORCED` (NEW). Verification per finding в DoD §7. |
| **CLAUDE.md §«Принцип переиспользования через kacho-corelib»** | `fgaoutbox.EmitWriteTx` / `EmitDeleteTx` — если используется в **двух** места внутри kacho-iam (AccessBinding + JIT + BG = три consumer'а) — оставляем в kacho-iam internal helper (`internal/repo/kacho/pg/fga_outbox_emitter.go` parity с `subject_change_emitter.go`). Перенос в corelib — backlog (нужно ещё одному сервису). |
| **CLAUDE.md §«Within-service refs DB-уровень обязателен»** | atomic emit ровно в той же tx, что и domain row + subject_change_outbox; rollback inject test (§6.4). |
| **Vault discipline** | KAC-141.md заметка; обновление `edges/iam-to-openfga-grant-write.md` (sync→async для AB/JIT/BG); `resources/iam-access-binding.md` (update Gotchas — sync FGA write больше не существует); `resources/iam-jit-eligibility.md` (lifecycle — FGA emit-in-tx); `resources/iam-cluster-break-glass-grant.md` (ApproveB: пишет cluster_admin_grants + fga_outbox). |

---

## 2. Глоссарий

- **fga_outbox** — таблица `kacho_iam.fga_outbox` (мигр. 0002), schema `(id bigserial, event_type IN ('fga.tuple.write','fga.tuple.delete'), payload jsonb, created_at, sent_at, last_error, attempt_count)`. W1.5 не меняет схему.
- **FGA tuple** — `{User: "user:<id>" | "service_account:<id>" | "group:<id>#member", Relation: "<rel>", Object: "<type>:<id>"}` (см. `clients.FGATuple`).
- **Atomic emit-in-tx** — INSERT в `fga_outbox` через `tx.Exec(...)` той же `pgx.Tx`, что domain row insert/update/delete. Tx-rollback ⇒ outbox row не visible drainer'у.
- **fgaoutbox.EmitWriteTx** (NEW helper, §4.1) — `func EmitWriteTx(ctx, pgx.Tx, []FGATuple) error` — batch INSERT'ит N rows event_type=`fga.tuple.write`, payload=JSON({user,relation,object}).
- **fgaoutbox.EmitDeleteTx** (NEW helper) — то же но event_type=`fga.tuple.delete`.
- **tuplesForBinding(b)** (renamed `accessBindingTuples` from `tuples.go`) — превращает `domain.AccessBinding` + `relation` в N tuples (1 relation + 1 hierarchy-tuple если scope=project, как сейчас в `create.go:179-183`). После W1.5 — принимает `[]Relation` (slice, не одиночный) → N×M tuples (один per (relation, hierarchy)).
- **PermissionsToRelations** (NEW в `authzmap`, §3.2) — `func PermissionsToRelations(permissions []string) []Relation` — derive FGA-relations из permission-strings; primary entry-point. Replaces `roleNameToRelation`.
- **Standard tier mapping** — fallback: permissions фильтруются по prefix → relation: `*.get|*.list|*.view → viewer`, `*.create|*.update|*.delete|*.*` → admin/editor (см. §3.2 table). Granular permission-relations (`vpc_network_get`) используются если они уже задекларированы в FGA model — иначе fallback.

---

## 3. Data model + mapping

### 3.1 `fga_outbox` payload format (NO change)

Используется existing schema (bootstrap_admin.go:124-138):

```json
{
  "user":     "user:usr_abc123",
  "relation": "system_admin",
  "object":   "cluster:default"
}
```

Один `fga.tuple.write` или `fga.tuple.delete` event = **один** tuple. Если binding порождает N tuples (relation-tuple + project-hierarchy tuple), пишем **N rows** в outbox (parity с `bindings → 2 tuples` логикой в `create.go:179-183`).

### 3.2 PermissionsToRelations mapping (`authzmap`, NEW)

```go
// Relation — typed string for FGA relation names.
type Relation string

// PermissionsToRelations derives FGA relations from a role's permission list.
//
// Strategy (W1.5 conservative — see OQ-W1.5-1 for granular-relations path):
//   1. If permissions == nil OR len == 0 → return []Relation{"viewer"} (least privilege fallback).
//   2. Group permissions by verb-class (read-only, write, admin):
//        verb ∈ {get, list, view, watch}        → read-only
//        verb ∈ {create, update, delete, write} → write
//        verb ∈ {admin, *}                      → admin
//   3. Map to FGA relation tier:
//        any admin            → "admin"
//        else any write       → "editor"
//        else read-only-only  → "viewer"
//   4. If FGA model has granular per-permission relations (e.g. `vpc_network_get`)
//      AND every permission maps to one → return granular set (instead of tier).
//      Detection: lookup in seeded `authzmap.GranularRelations` set (W1.5 ships
//      this as an explicit list of known granular relations; new ones added in
//      W2/W3 by extending the set).
//
// Returned list is deduplicated and stable-ordered (for test stability and
// idempotent fga_outbox writes — same role → same N tuples → same drainer
// outcome).
func PermissionsToRelations(permissions []string) []Relation
```

**Mapping examples (verified by integration tests §6.2):**

| Role permissions | Returned relations |
|---|---|
| `[]` (empty / nil) | `["viewer"]` |
| `["vpc.networks.get"]` | `["viewer"]` (verb=get → read-only tier; no granular `vpc_network_get` relation seeded yet) |
| `["vpc.networks.get", "vpc.networks.create"]` | `["editor"]` (any write → editor tier) |
| `["vpc.*.*"]` | `["admin"]` (wildcard → admin tier) |
| `["iam.accessBindings.create"]` | `["editor"]` |
| (custom, post-W2 with granular relations) `["vpc.networks.get"]` if `vpc_network_get` ∈ GranularRelations | `["vpc_network_get"]` |

### 3.3 `cluster_admin_grants` INSERT in BG.ApproveB (mirror bootstrap_admin)

Verified table schema (мигр. 0011) — мы не редактируем; пишем `INSERT INTO cluster_admin_grants (id, cluster_id, subject_type, subject_id, granted_by, granted_at) VALUES ($1, $2, 'user', $3, $4, $5)` — где `granted_by = string(req.Approver)` (B-approver), `granted_at = now`.

> Bootstrap-admin использует `'bootstrap'` как `granted_by` — Approve path использует **реального** user-id. Это намеренно: в audit-trail видно «cluster-admin выдан break-glass, approver B = userX» vs «bootstrap process».

### 3.4 No new migration (default decision)

Default решение — **новой миграции нет**. Все три таблицы уже existуют (мигр. 0002 `fga_outbox`, 0011 `cluster_admin_grants`, мигр. 0023 W1.2 `subject_change_outbox` v2). Если acceptance-reviewer попросит дополнительный индекс (например `cluster_admin_grants_subject_unique` для idempotency BG.ApproveB) — отдельный файл `0024_cluster_admin_grants_idempotency.sql`. См. **OQ-W1.5-5**.

---

## 4. API / interface contract

### 4.1 `fgaoutbox` helper (kacho-iam, NEW package `internal/repo/kacho/pg/fga_outbox/`)

Parity с `subject_change_emitter.go` (W1.2) — stateless adapter, операция выполняется на caller-supplied tx, никогда не на pool-managed connection (запрет #10 — нужна та же tx что state-flip).

```go
// Package fga_outbox — atomic emit-in-tx helper for kacho_iam.fga_outbox.
// Mirrors the pattern established by W1.2 SubjectChangeEmitter.
package fga_outbox

import (
    "context"
    "encoding/json"
    "fmt"

    "github.com/jackc/pgx/v5"
    "github.com/PRO-Robotech/kacho-iam/internal/clients"
)

// EmitWriteTx — N×INSERT INTO kacho_iam.fga_outbox (event_type='fga.tuple.write', payload=$1).
// MUST be called inside the same pgx.Tx as the domain state-change (AccessBinding insert /
// jit binding mint / cluster_admin_grants insert). Tx rollback ⇒ no orphan outbox rows.
func EmitWriteTx(ctx context.Context, tx pgx.Tx, tuples []clients.FGATuple) error {
    return emitTx(ctx, tx, "fga.tuple.write", tuples)
}

// EmitDeleteTx — N×INSERT event_type='fga.tuple.delete'.
// Caller supplies the EXACT tuples that were originally written by EmitWriteTx
// (symmetric revoke — relation + project-hierarchy).
func EmitDeleteTx(ctx context.Context, tx pgx.Tx, tuples []clients.FGATuple) error {
    return emitTx(ctx, tx, "fga.tuple.delete", tuples)
}

func emitTx(ctx context.Context, tx pgx.Tx, eventType string, tuples []clients.FGATuple) error {
    if len(tuples) == 0 {
        return nil // no-op; caller decides whether 0 tuples is an error
    }
    for _, t := range tuples {
        payload, err := json.Marshal(map[string]string{
            "user": t.User, "relation": t.Relation, "object": t.Object,
        })
        if err != nil {
            return fmt.Errorf("fga_outbox: marshal payload: %w", err)
        }
        if _, err := tx.Exec(ctx,
            `INSERT INTO fga_outbox (event_type, payload, created_at)
             VALUES ($1, $2::jsonb, now())`,
            eventType, payload,
        ); err != nil {
            return fmt.Errorf("fga_outbox: insert: %w", err)
        }
    }
    return nil
}
```

> Could be extracted to `kacho-corelib/outbox/fga/` later if another service writes FGA tuples — backlog'ed (one consumer = kacho-iam now).

### 4.2 AccessBinding.Create changes (`create.go`)

```go
// BEFORE (current, finding #16 + #47):
if err := w.Commit(ctx); err != nil { return nil, mapRepoErr(err) }
committed = true
if u.fga != nil {
    relation := u.resolveBindingRelation(ctx, string(b.RoleID))    // #47 — name-based
    tup, ok := bindingToTupleWithRelation(b, relation)
    if ok {
        if err := u.fga.WriteTuples(ctx, []clients.FGATuple{tup}); err != nil {
            u.logger.Warn(...)                                       // #16 — non-fatal
        }
    }
}
if strings.EqualFold(string(created.ResourceType), "project") {
    fgahook.WriteHierarchyTuple(ctx, u.fga, u.logger, ...)
}

// AFTER (W1.5 fix #16 + #47 + #48):
role, err := w.RolesW().Get(ctx, b.RoleID)         // inside tx; read-only — ok
if err != nil { return nil, mapRepoErr(err) }
relations := authzmap.PermissionsToRelations(role.Permissions)        // #47/#48: permission-based
tuples := tuplesForBinding(created, relations)                        // N relations → N+hierarchy tuples
if err := fga_outbox.EmitWriteTx(ctx, w.Tx(), tuples); err != nil {   // #16: atomic emit-in-tx
    return nil, mapRepoErr(err)
}
if err := w.Commit(ctx); err != nil { return nil, mapRepoErr(err) }   // commit AB + subject_change + fga_outbox atomically
committed = true
// No post-commit sync FGA write. Drainer (W1.1) applies asynchronously.
```

### 4.3 AccessBinding.Delete changes (`delete.go`)

```go
// BEFORE (current, finding #8):
if err := w.Commit(ctx); err != nil { return nil, mapRepoErr(err) }
committed = true
if u.fga != nil {
    relation := resolveRelationFromRepo(ctx, u.repo, string(deletedBinding.RoleID))   // name-based; carries #47
    tuples := accessBindingTuples(deletedBinding, relation)
    if err := u.fga.DeleteTuples(ctx, tuples); err != nil {
        u.logger.Warn(...)                                                              // non-fatal — #8 root
    }
}

// AFTER (W1.5 fix #8):
role, err := w.RolesW().Get(ctx, deletedBinding.RoleID)
if err != nil { return nil, mapRepoErr(err) }
relations := authzmap.PermissionsToRelations(role.Permissions)
tuples := tuplesForBinding(deletedBinding, relations)
if err := fga_outbox.EmitDeleteTx(ctx, w.Tx(), tuples); err != nil {
    return nil, mapRepoErr(err)
}
if err := w.Commit(ctx); err != nil { return nil, mapRepoErr(err) }
committed = true
// Drainer asynchronously DELETEs tuples from OpenFGA.
```

### 4.4 JIT auto-grant (`phase7_jit_service.go::ActivateJIT`)

After `s.bindings.InsertTx(ctx, tx, binding)` (line 353), BEFORE `tx.Commit(ctx)` (line 357):

```go
role, err := s.roles.GetTx(ctx, tx, e.RoleID)                     // new dependency: JITService.roles port
if err != nil { return ActivateJITResult{}, err }
relations := authzmap.PermissionsToRelations(role.Permissions)
tuples := tuplesForBinding(inserted, relations)
if err := s.fgaEmitter.EmitWriteTx(ctx, tx, tuples); err != nil { // new port on JITService
    return ActivateJITResult{}, err
}
// Optional (OQ-W1.5-2): emit subject_change_outbox binding_grant for cache invalidation of negative cache.
if s.subjectChange != nil { _ = s.subjectChange.EmitTx(ctx, tx, SubjectChangeEvent{...}) }
if err := tx.Commit(ctx); err != nil { return ActivateJITResult{}, err }
```

### 4.5 JIT pending Approve (`jit_pending_service.go::ApproveJITActivation`)

Replace line 286-287:
```go
// BEFORE:
logEmitFailure(s.logger, true, "fga", "iam.jit.activation_approved",
    s.fga.EmitSubjectErasure(ctx, domain.UserID(p.RequestedBy), payload))
```
with:
```go
// AFTER (W1.5 fix #51 approve-path):
role, err := s.roles.GetTx(ctx, tx, e.RoleID)
if err != nil { return ..., err }
relations := authzmap.PermissionsToRelations(role.Permissions)
tuples := tuplesForBinding(minted, relations)
if err := s.fgaEmitter.EmitWriteTx(ctx, tx, tuples); err != nil {
    return ..., err
}
```

### 4.6 JIT pending expiry (`jit_pending_service.go::ExpirePending` / `phase7b_workers.go::JitPendingExpirerWorker.Tick`)

Replace `EmitSubjectErasure` (line ~412 ExpirePending). Use `EmitDeleteTx` for the binding's tuples — the worker must look up the expired binding (it has `binding_id` from the pending row) and compute `tuplesForBinding`. If binding row already gone (concurrent revoke) — skip emit (idempotent, drainer also accepts 404 as `ErrAlreadyApplied`).

### 4.7 BreakGlass.ApproveB (`phase7_break_glass_service.go::ApproveB`)

After `s.grants.ApproveB(ctx, tx, ...)` (line 276), BEFORE `tx.Commit(ctx)` (line 280):

```go
// (a) cluster_admin_grants INSERT — mirror bootstrap_admin §90-120
adminGrantID := domain.NewKac127ID(domain.PrefixClusterAdminGrant)
_, err = tx.Exec(ctx,
    `INSERT INTO cluster_admin_grants (id, cluster_id, subject_type, subject_id, granted_by, granted_at)
     VALUES ($1, $2, 'user', $3, $4, $5)`,
    adminGrantID, string(out.ClusterID), string(out.SubjectID), string(req.Approver), now)
if err != nil {
    // 23505 (concurrent ApproveB winner already INSERT'ed) → idempotent, swallow
    if pgErr := /* extract */; pgErr != nil && pgErr.Code == "23505" {
        // graceful; out remains the canonical row
    } else {
        return domain.ClusterBreakGlassGrant{}, fmt.Errorf("bg approve_b: insert cluster_admin_grants: %w", err)
    }
}

// (b) fga_outbox emit — mirror bootstrap_admin §122-151
tuple := clients.FGATuple{
    User: "user:" + string(out.SubjectID),
    Relation: "system_admin",
    Object: "cluster:" + string(out.ClusterID),
}
if err := s.fgaEmitter.EmitWriteTx(ctx, tx, []clients.FGATuple{tuple}); err != nil {
    return domain.ClusterBreakGlassGrant{}, fmt.Errorf("bg approve_b: fga emit: %w", err)
}
```

### 4.8 Removal: `accessBindingTuples` / `roleNameToRelation` / `resolveRelationFromRepo` / `resolveBindingRelation` in `access_binding/`

- `tuples.go::roleNameToRelation` — **delete**.
- `tuples.go::bindingToTupleWithRelation` — replaced by new `tuplesForBinding(binding, []Relation)` (multi-relation aware).
- `tuples.go::accessBindingTuples(b, relation string)` — replaced by `tuplesForBinding(b, []Relation)`.
- `create.go::resolveBindingRelation` — **delete**.
- `delete.go::resolveRelationFromRepo` — **delete**.
- `authzmap.RoleNameToRelation` — keep deprecated for one release cycle (tests still reference it); annotate `// Deprecated: use PermissionsToRelations`; remove in W3 cleanup.

### 4.9 Drainer / OpenFGA client / cache invalidation — UNCHANGED

W1.1 drainer + W1.2 SubjectChangeEmitter + W1.2 InternalAuthzCacheService are all reused as-is. W1.5 only changes the *write-side* (emit-in-tx instead of post-commit sync). No drainer changes; no proto changes.

---

## 5. Test discipline (запрет #11) — RED first

PR обязан содержать **в указанном порядке**:

1. **RED phase commit** (testing-only): all integration tests from §6 + newman cases from §6.5 written and committed BEFORE any impl. CI red on this commit (compile-fail OR test-fail).
2. **GREEN phase commits**: per-finding impl driving each RED test → GREEN. PR description shows per-finding RED→GREEN evidence (test name, before-output, after-output).
3. **Newman cases** added to `project/kacho-iam/tests/newman/cases/authz-deny.py` (new cases) and `tests/newman/cases/iam-*.py` if needed; regenerate via `gen.py`; verify `run.sh` picks up; verify CI matrix gate (W0.3) still green.
4. **Atomicity tests obligatory** (§6.4 ROLLBACK-*): force tx rollback after fga_outbox emit but before commit; assert: zero binding rows, zero fga_outbox rows, zero subject_change_outbox rows. Per CLAUDE.md §запрет #10.

---

## 6. Сценарии (Given-When-Then) — основа интеграционных тестов

> All scenarios use Postgres testcontainer (kacho-iam migrations 0001-0023 applied) + fake `OpenFGAClient` recorder (already in repo, `clients/openfga_stub_client.go`) + drainer running in-test for end-to-end verification where relevant.

### 6.1 Per-finding happy-paths

#### Сценарий W1.5-08 — AccessBinding.Delete writes fga_outbox revoke in same tx; drainer applies; Check DENIES

**ID**: W1.5-08 (closes finding #8)

**Given** drainer + fake OpenFGAClient running (recorder mode)
**And** AccessBinding `acb_t08` exists for subject `usr_alice`, role with permissions `["vpc.networks.get"]` (→ relation `viewer` per §3.2)
**And** post-Create, `fga_outbox` has 1 write-row (already applied by drainer; recorder shows 1 `WriteTuples` call with `{user:"user:usr_alice", relation:"viewer", object:"project:prj_x"}`)
**And** OpenFGAClient.Check(`user:usr_alice`, `viewer`, `project:prj_x`) → **ALLOW**

**When** `AccessBindingService.Delete(id="acb_t08")` Operation completes (worker → doDelete → tx Begin → Get binding + role → Delete row + EmitSubjectChange + EmitDeleteTx → Commit)

**Then** в `kacho_iam.fga_outbox` появилась row `event_type='fga.tuple.delete', payload={user:..., relation:"viewer", object:"project:prj_x"}, sent_at IS NULL`
**And** в `kacho_iam.subject_change_outbox` row `event_type='binding_revoke', subject_id='usr_alice'` (W1.2 path, unchanged)
**And** в `kacho_iam.access_bindings` row для `acb_t08` отсутствует
**And** в течение **2 секунд** drainer применяет → recorder shows `DeleteTuples` call → `fga_outbox.sent_at IS NOT NULL`
**And** OpenFGAClient.Check(...) теперь → **DENY** (`{allowed:false}`)

---

#### Сценарий W1.5-16 — AccessBinding.Create writes fga_outbox in same tx; drainer applies; Check ALLOWS

**ID**: W1.5-16 (closes finding #16)

**Given** Role `rol_t16` with permissions `["vpc.networks.get"]` (→ relation `viewer`)
**And** drainer + fake OpenFGAClient running

**When** `AccessBindingService.Create(subject=usr_bob, role=rol_t16, resource_type=project, resource_id=prj_y)` Operation completes

**Then** `kacho_iam.fga_outbox` имеет row `event_type='fga.tuple.write', payload={user:"user:usr_bob", relation:"viewer", object:"project:prj_y"}`
**And** в той же tx (verified via tx-introspection in test) — `access_bindings` row + `subject_change_outbox` row + N `fga_outbox` rows
**And** post-commit, fake OpenFGAClient.WriteTuples **NOT** called inline (sync write removed)
**And** drainer применяет в течение **2 секунд** → recorder shows 1 WriteTuples call → Check ALLOW

---

#### Сценарий W1.5-47 — Custom role with permissions=[vpc.networks.get,vpc.networks.create] → relation `editor`, granular Check matrix

**ID**: W1.5-47 (closes finding #47)

**Given** Custom role `rol_custom_t47` with permissions `["vpc.networks.get", "vpc.networks.create"]`
**And** drainer + fake OpenFGAClient (with seeded FGA model)

**When** binding granted: subject=`usr_carol`, role=`rol_custom_t47`, resource=`project:prj_z`

**Then** `fga_outbox.payload` содержит **relation:"editor"** (per §3.2 mapping: any write verb → editor tier)
**And** OpenFGAClient.Check(`user:usr_carol`, `editor`, `project:prj_z`) → ALLOW after drainer applies
**And** Check(`user:usr_carol`, `admin`, `project:prj_z`) → DENY (no admin grant)
**And** Check(`user:usr_carol`, `viewer`, `project:prj_z`) → ALLOW (editor implies viewer via FGA model)

> **Cross-reference** for granular relations (post-W2/W3): when `vpc_network_get` is added to `GranularRelations`, replay this scenario with permissions=[`vpc.networks.get`] only — expect 2 fga_outbox rows (`vpc_network_get` granular + `viewer` standard fallback) per OQ-W1.5-1 final answer.

---

#### Сценарий W1.5-48 — Single mapper: `roleNameToRelation` and `resolveBindingRelation` removed

**ID**: W1.5-48 (closes finding #48)

**Given** kacho-iam codebase at HEAD post-W1.5

**When** `grep -rn "roleNameToRelation\|resolveBindingRelation\|resolveRelationFromRepo" internal/`

**Then** zero matches in `internal/apps/kacho/api/access_binding/` (deleted)
**And** zero matches in `internal/service/`
**And** `internal/authzmap/role_expand.go::RoleNameToRelation` — annotated `// Deprecated` but kept (tests still use)
**And** `internal/authzmap/role_expand.go::PermissionsToRelations` exists with documented mapping table from §3.2

> Static linting-style test (codified in `go test ./internal/...` via `analysis/lint` or simple `grep` fixture-test) — fails RED if old names still referenced.

---

#### Сценарий W1.5-50 — JIT auto-activate (approval_required=false) writes fga_outbox in same tx; Check ALLOWS post-drainer

**ID**: W1.5-50 (closes finding #50)

**Given** `jit_eligibility` row `jite_t50` (user=`usr_dave`, role=`rol_viewer`, resource=`project:prj_w`, approval_required=false, max_duration=1h)
**And** drainer + fake OpenFGAClient running

**When** `JITService.ActivateJIT(eligibility=jite_t50, requested_duration=15min, requested_by=usr_dave)`

**Then** `kacho_iam.access_bindings` row `acb_...` inserted (status=ACTIVE, expires_at=now+15min)
**And** `kacho_iam.fga_outbox` row event_type=`fga.tuple.write`, payload={user:"user:usr_dave", relation:"viewer", object:"project:prj_w"}, in **same tx** as the binding insert
**And** drainer applies within **2s**; fake FGA Check(`user:usr_dave`, `viewer`, `project:prj_w`) → ALLOW

---

#### Сценарий W1.5-51-APPROVE — JIT pending Approve writes fga_outbox grant; Check ALLOWS

**ID**: W1.5-51-APPROVE (closes finding #51 approve-path)

**Given** `jit_pending` row `jp_t51` (requester=`usr_eve`, role with permissions=[`compute.instances.list`], resource=`project:prj_v`, status=PENDING)
**And** `JitPendingService.ApproveJITActivation(jp_t51, approver=usr_admin)` invoked

**When** ApproveJIT completes (tx: Get pending → Decide → InsertTx binding → EmitWriteTx → Commit)

**Then** `fga_outbox` row event_type=`fga.tuple.write`, payload={user:"user:usr_eve", relation:"viewer" (read verb → viewer per §3.2), object:"project:prj_v"}
**And** NO `EmitSubjectErasure` call (verified by fake `s.fga` recorder count == 0)
**And** Check(`user:usr_eve`, `viewer`, `project:prj_v`) → ALLOW after drainer

---

#### Сценарий W1.5-51-EXPIRY — JIT auto-expiry writes fga_outbox revoke; Check DENIES

**ID**: W1.5-51-EXPIRY (closes finding #51 expiry-path)

**Given** ACTIVE binding `acb_t51e` (from previous Approve), `expires_at = now - 1s`
**And** `JitPendingExpirerWorker.Tick()` runs

**When** worker calls `ExpirePending`

**Then** `fga_outbox` row event_type=`fga.tuple.delete`, payload={user:"user:usr_eve", relation:"viewer", object:"project:prj_v"}
**And** `access_bindings` row для `acb_t51e` status=REVOKED (atomic с emit)
**And** Check(...) → DENY after drainer

---

#### Сценарий W1.5-52 — BreakGlass.ApproveB writes cluster_admin_grants + fga_outbox in same tx; Check cluster-admin ALLOWS

**ID**: W1.5-52 (closes finding #52)

**Given** `cluster_break_glass_grants` row `bgg_t52` in state=AWAITING_APPROVAL_B, subject=`usr_frank`, cluster=`default`, expires_at=now+2h
**And** `BreakGlassService.ApproveB(grant=bgg_t52, approver=usr_admin2)` invoked

**When** ApproveB completes

**Then** `cluster_break_glass_grants.state` = ACTIVE
**And** `cluster_admin_grants` имеет row `(cluster_id=default, subject_type=user, subject_id=usr_frank, granted_by=usr_admin2, granted_at≈now)`
**And** `fga_outbox` row event_type=`fga.tuple.write`, payload={user:"user:usr_frank", relation:"system_admin", object:"cluster:default"}
**And** ВСЕ три INSERT'а в одной tx (verified via tx-introspection)
**And** Check(`user:usr_frank`, `system_admin`, `cluster:default`) → ALLOW after drainer

---

### 6.2 PermissionsToRelations mapping unit tests

#### Сценарий W1.5-MAP-EMPTY — empty permissions → `["viewer"]`

**ID**: W1.5-MAP-01

**Given** `PermissionsToRelations(nil)` and `PermissionsToRelations([]string{})`

**Then** both return `[]Relation{"viewer"}`

---

#### Сценарий W1.5-MAP-READ — read-only permissions → `["viewer"]`

**ID**: W1.5-MAP-02

**Given** `PermissionsToRelations([]string{"vpc.networks.get", "compute.instances.list", "iam.roles.view"})`

**Then** returns `[]Relation{"viewer"}` (verb-class: get/list/view → read-only → viewer tier)

---

#### Сценарий W1.5-MAP-WRITE — mixed read+write → `["editor"]`

**ID**: W1.5-MAP-03

**Given** `PermissionsToRelations([]string{"vpc.networks.get", "vpc.networks.create"})`

**Then** returns `[]Relation{"editor"}` (any write verb → editor tier)

---

#### Сценарий W1.5-MAP-ADMIN — wildcard or admin verb → `["admin"]`

**ID**: W1.5-MAP-04

**Given** `PermissionsToRelations([]string{"vpc.*.*"})` and `PermissionsToRelations([]string{"iam.accessBindings.admin"})`

**Then** both return `[]Relation{"admin"}`

---

#### Сценарий W1.5-MAP-GRANULAR (post-W2 opt-in) — granular relation seeded → uses it

**ID**: W1.5-MAP-05

**Given** `authzmap.GranularRelations["vpc_network_get"] = struct{}{}`
**And** `PermissionsToRelations([]string{"vpc.networks.get"})`

**Then** returns `[]Relation{"vpc_network_get"}` (single granular relation; no fallback tier)

> Test guarded by feature-flag; default W1.5 deployment has empty `GranularRelations` → fallback to tier — keeps integration tests deterministic.

---

### 6.3 Concurrency

#### Сценарий W1.5-CONCURRENT-CREATE — concurrent AccessBinding.Create for same 5-tuple → exactly 1 fga_outbox row

**ID**: W1.5-CONCURRENT-01

**Given** 5 goroutines parallel call `AccessBindingService.Create(subject=usr_g, role=rol_g, resource=project:prj_g)` (identical 5-tuple → ON CONFLICT idempotent)

**Then** ровно **одна** row in `access_bindings` (ON CONFLICT DO UPDATE SET id = id)
**And** ровно **одна** group of `fga_outbox` write rows (one per relation tuple; not 5×N — the loser tx-paths rollback their own outbox INSERT)
**And** ровно **одна** `subject_change_outbox` binding_grant row

> Verifies atomicity: only the winning tx commits fga_outbox INSERTs.

---

#### Сценарий W1.5-CONCURRENT-DELETE — concurrent Delete + Create on same binding-id → drainer sees ordered outbox stream

**ID**: W1.5-CONCURRENT-02

**Given** binding `acb_cc` exists with viewer-relation tuple already applied

**When** goroutine-A calls Delete(acb_cc), goroutine-B calls Create(same 5-tuple) concurrently; both Operations complete

**Then** `fga_outbox` has 2 rows ordered by `created_at` — first `fga.tuple.delete`, then `fga.tuple.write` (OR vice versa — depends on which tx commits first); drainer applies in `created_at ASC` order
**And** final OpenFGA state = single tuple (either alive if Create won last, or absent if Delete won last) — no leaked tuples

---

### 6.4 Atomicity (rollback-no-leak — per запрет #10)

#### Сценарий W1.5-ROLLBACK-AB-CREATE — tx rollback after fga_outbox emit → zero rows visible

**ID**: W1.5-ROLLBACK-01

**Given** real Postgres testcontainer (not mock); kacho-iam writer-tx instrumented to inject error AFTER `EmitWriteTx` succeeds, BEFORE `Commit`

**When** AccessBinding.Create.doCreate runs through the instrumented path

**Then** `tx.Rollback()` invoked
**And** `kacho_iam.access_bindings` имеет 0 rows for the candidate id
**And** `kacho_iam.fga_outbox` имеет 0 rows for the candidate payload
**And** `kacho_iam.subject_change_outbox` имеет 0 rows
**And** Operation.error reflects the injected failure

---

#### Сценарий W1.5-ROLLBACK-AB-DELETE — same for Delete path

**ID**: W1.5-ROLLBACK-02

Same shape as ROLLBACK-01 but Delete-path; assert binding row **still exists** (not deleted), fga_outbox no delete-row.

---

#### Сценарий W1.5-ROLLBACK-JIT — JIT auto-activate rollback

**ID**: W1.5-ROLLBACK-03

Inject error in `ActivateJIT` after EmitWriteTx, before Commit. Assert no binding row, no fga_outbox row.

---

#### Сценарий W1.5-ROLLBACK-BG — BG ApproveB rollback

**ID**: W1.5-ROLLBACK-04

Inject error in ApproveB after cluster_admin_grants INSERT, after fga_outbox EmitWriteTx, before Commit. Assert: no cluster_admin_grants row, no fga_outbox row, break-glass state **unchanged** (still AWAITING_APPROVAL_B).

---

### 6.5 Newman E2E

#### Newman W1.5-NM-01 — `AUTHZ-REVOKE-ENFORCED-A-INV` (existing W1.2 case; verify W1.5 makes Check return DENY because tuple actually deleted)

**ID**: W1.5-NM-01

**Existing case** (added in W1.2 — `tests/newman/cases/authz-deny.py::AUTHZ-REVOKE-ENFORCED-A-INV`). Pre-W1.5: passes because subject_change cache invalidate ensures next Check on **same gateway replica** misses cache → goes to OpenFGA → OpenFGA STILL has the tuple (W1.2 only invalidated cache, didn't delete tuple) → ALLOW… **wait**: this case actually currently passes because OpenFGA does respond DENY post-W1.2 cache invalidate because the sync `DeleteTuples` call in `delete.go:121` happens (existing pre-W1.5 code; finding #8 is about that being non-fatal). After W1.5 removes the sync call and replaces with outbox emit, the test must STILL pass because drainer applies the delete within 2s. **GWT**: AAA grants admin → INV (binding+outbox-write); drainer applies; INV's first GET account-A returns 200; AAA revokes; subject_change_outbox emit + fga_outbox delete-emit; drainer applies delete; cache invalidated → next GET account-A returns 403 within ≤ 2s.

#### Newman W1.5-NM-02 — `AUTHZ-CUSTOM-ROLE-GRANULAR-PERMISSIONS` (NEW)

**ID**: W1.5-NM-02

**Given** AAA (account admin) creates **custom role** `customRoleReader` with permissions=[`compute.instances.list`]
**And** AAA grants binding(`customRoleReader`, INV, `project:prj_A`)

**When** INV calls `GET /compute/v1/instances?projectId=prj_A`

**Then** 200 OK (FGA ALLOW — permissions-mapping correctly yielded `viewer` relation)

**And** INV calls `DELETE /compute/v1/instances/<some_id>?projectId=prj_A`

**Then** 403 PERMISSION_DENIED (only viewer, no delete permission)

> Requires W1.4 principal propagation merged for the cross-service Check (api-gateway → kacho-compute → kacho-iam InternalIAMService.Check) to see correct principal. If W1.4 still in-flight at impl time, case marked `skip-until-w14-green` with explicit comment.

#### Newman W1.5-NM-03 — `JIT-AUTO-ACTIVATE-ENFORCED` (NEW)

**ID**: W1.5-NM-03

**Given** AAA creates `jit_eligibility` for INV (role=`viewer`, project=`prj_A`, approval_required=false, max_duration=1h)

**When** INV calls `ActivateJIT(jite_id, requested_duration=15min)` → 200 (Operation returns)

**Then** within ≤ 2s, INV `GET /iam/v1/projects/prj_A` returns 200 (FGA Check ALLOW because viewer-tuple now applied)

#### Newman W1.5-NM-04 — `JIT-PENDING-APPROVE-ENFORCED` (NEW)

**ID**: W1.5-NM-04

Similar to NM-03 but with `approval_required=true`; ApproveB triggers FGA write; Check ALLOW post-drainer.

#### Newman W1.5-NM-05 — `JIT-EXPIRY-REVOKES` (NEW)

**ID**: W1.5-NM-05

After NM-03 / NM-04, wait until `expires_at` passes + worker tick (≤ 1 min in test config); then INV `GET /iam/v1/projects/prj_A` → 403.

#### Newman W1.5-NM-06 — `BREAKGLASS-2APPROVE-ENFORCED` (NEW)

**ID**: W1.5-NM-06

**Given** REQUESTER user_id=`usr_R`; ApproverA=`usr_A`; ApproverB=`usr_B`; cluster=`default`

**When** `Request → ApproveA → ApproveB` flow completes

**Then** `cluster_admin_grants` row inserted (visible via `InternalClusterService.ListClusterAdminGrants`)
**And** REQUESTER calls some cluster-admin-gated RPC (e.g. `InternalClusterService.UpdateClusterConfig` if any; else direct OpenFGA Check via internal `InternalAuthorize.Check(user:usr_R, system_admin, cluster:default)`) → ALLOW

---

## 7. Definition of Done

- [ ] `acceptance-reviewer` ✅ APPROVED данного doc; all OQs resolved
- [ ] Branch `KAC-141` создан в `kacho-iam`
- [ ] **RED phase commit**: all §6 integration tests + §6.5 newman cases written, regenerated, CI red — RED evidence in PR description per finding
- [ ] **GREEN phase commits** (one logical commit per finding, ordered by dependency):
  - [ ] #47/#48 — `authzmap.PermissionsToRelations` + delete `roleNameToRelation` family (RED W1.5-47, W1.5-48, W1.5-MAP-01..04 → GREEN)
  - [ ] #16 — `fgaoutbox.EmitWriteTx` helper + AccessBinding.Create rewrite (RED W1.5-16, W1.5-ROLLBACK-01 → GREEN)
  - [ ] #8 — AccessBinding.Delete rewrite (RED W1.5-08, W1.5-ROLLBACK-02 → GREEN)
  - [ ] #50 — JIT auto-grant emit (RED W1.5-50, W1.5-ROLLBACK-03 → GREEN)
  - [ ] #51 — JIT pending Approve + Expiry emit (RED W1.5-51-APPROVE, W1.5-51-EXPIRY → GREEN)
  - [ ] #52 — BreakGlass.ApproveB emit (RED W1.5-52, W1.5-ROLLBACK-04 → GREEN)
- [ ] Concurrent tests (§6.3 W1.5-CONCURRENT-01/02) GREEN
- [ ] Newman cases (§6.5 W1.5-NM-01..06) GREEN; coverage gate W0.1 still satisfied
- [ ] `make e2e` smoke on dev-kind shows: bootstrap-admin → drainer applies → AB.Create grant → drainer applies → Check ALLOW → AB.Delete revoke → drainer applies → Check DENY (≤ 2s end-to-end)
- [ ] kacho-iam CI green (unit + integration + race)
- [ ] PR merged
- [ ] Vault обновлён:
  - [ ] `obsidian/kacho/KAC/KAC-141.md` (создать) — trail + PR + acceptance checklist
  - [ ] `obsidian/kacho/edges/iam-to-openfga-grant-write.md` — table row "AccessBindingService.Create/Delete" → outbox emit (W1.5); "JIT auto/pending-approve" → outbox emit; "BreakGlass.ApproveB" → cluster_admin_grants + outbox emit
  - [ ] `obsidian/kacho/resources/iam-access-binding.md` — Lifecycle: remove "sync `WriteTuples` / `DeleteTuples`", replace with "atomic `fga_outbox` emit-in-tx, drainer applies"
  - [ ] `obsidian/kacho/resources/iam-jit-eligibility.md` — Lifecycle: ActivateJIT auto-grant emits fga_outbox; Approve/Expiry emit fga_outbox
  - [ ] `obsidian/kacho/resources/iam-cluster-break-glass-grant.md` — ApproveB lifecycle step: writes cluster_admin_grants + fga_outbox in same tx; mirror bootstrap_admin
  - [ ] `obsidian/kacho/packages/iam-service-jit.md` (создать если нет) — note new EmitWriteTx port
  - [ ] `obsidian/kacho/packages/iam-service-breakglass.md` — note new EmitWriteTx port + cluster_admin_grants write in ApproveB
- [ ] YouTrack KAC-141:
  - [ ] In Progress on impl start
  - [ ] PR links commented
  - [ ] Done on merge + smoke
- [ ] W1 tracker `2026-05-23-iam-prod-ready-wave1.md` updated: W1.5 row → ✅ done + date

---

## 8. Open questions (DECISION-NEEDED) — нужно разрешить до старта impl

| ID | Вопрос | Рекомендация автора |
|---|---|---|
| **OQ-W1.5-1** | Granular FGA relations (`vpc_network_get`, `compute_instance_delete`, …) — seed их в W1.5 (расширить FGA model) или **только tier mapping** (admin/editor/viewer/system_admin) на W1.5, granular — backlog'ом в W2/W3? | **Tier mapping only в W1.5**. Расширение FGA model = `fga_model.fga` DSL + регенерация `model.json` + bootstrap-job re-apply + breaking-проверки. Out of scope для bug-fix chunk. Granular relations — отдельный feature ticket (W2 #45 catalog unification — естественно ляжет туда). |
| **OQ-W1.5-2** | JIT auto-grant — emit `subject_change_outbox` `binding_grant` event для cache-invalidate? | **Да, для consistency**. Без emit'а возможен race: gateway authz cache имеет ALLOW from prior session — нет, наоборот, проблема в негативном кэше: gateway имеет DENY (Check DENY 30s назад) → ActivateJIT → drainer добавляет tuple → но gateway всё ещё кэширует DENY до TTL. Emit `binding_grant` инвалидирует негативный кэш. Реализация — тот же `SubjectChangeEmitter.EmitTx` (W1.2). |
| **OQ-W1.5-3** | `fgaoutbox` helper — где жить: `internal/repo/kacho/pg/fga_outbox/` (parity с `subject_change_emitter.go`) или `internal/clients/`? | **`internal/repo/kacho/pg/fga_outbox/`** — это DB-write adapter, не clients. Stateless, mirror W1.2 паттерна. Test'ы рядом. |
| **OQ-W1.5-4** | BG.ApproveB — `cluster_admin_grants` INSERT может породить SQLSTATE 23505 (concurrent ApproveB winners). Treat как graceful idempotent (как bootstrap_admin) или как ошибку? | **Graceful idempotent** (parity с bootstrap_admin §111-118). Если row уже есть — другой ApproveB-call уже всё сделал; current tx безопасно rollback'нём (но fga_outbox в этой же tx тоже rollback'нётся — это OK, другой winner emit'нул свой). Альтернатива — `ON CONFLICT DO NOTHING` + skip fga_outbox emit when nothing INSERTed; разница нюанс. Идём с idempotent rollback (проще читать). |
| **OQ-W1.5-5** | Добавить UNIQUE на `cluster_admin_grants (cluster_id, subject_id)` для строгой idempotency (DB-уровень вместо software CHECK)? | **Да, но отдельный migration** `0024_cluster_admin_grants_subject_unique.sql`. Включаем в W1.5 если acceptance-reviewer не возражает (low-risk additive — backfill сейчас минимален). Если решено НЕТ — оставляем software-idempotency через 23505-catch (см. OQ-4). |
| **OQ-W1.5-6** | `roles.GetTx(ctx, tx, roleID)` — этот port не существует на JITService / BreakGlassService / Writer. Добавить в W1.5 или предположить уже доступен? | Verified: `Writer.RolesW()` есть в `internal/repo/kacho/access_binding/iface.go` (грязно проверить); `s.roles` port'а на JITService нет → нужно добавить. **Добавляем в W1.5** (одна-две строки в composition root + interface). Minimal scope. |
| **OQ-W1.5-7** | Удалять ли `roleNameToRelation` сразу или depricate на 1 release cycle? | **Deprecate annotation** в `authzmap.RoleNameToRelation` (тесты могут на неё опираться); из `access_binding/` — **удалить** (там single-source-of-truth — `PermissionsToRelations`). Финальное удаление — W3 cleanup. |
| **OQ-W1.5-8** | `EmitSubjectErasure` — оставить ли его только в GDPR-пути или удалить совсем? | **Оставить в GDPR** (`phase7_gdpr_service.go::EraseSubject` — реальный subject-deletion CAEP event). Удалить **из** JIT-paths (там подмена была — finding #51). Если grep после W1.5 покажет 1 callsite (GDPR) — OK. |

> **Ответы на OQ — за `acceptance-reviewer`.** OQ-W1.5-1/2/3/5/8 — критичны для public API/integration теста shape; impl не стартует без явных ответов на них.

---

## 9. Out of scope (явно — на следующие chunks)

| Что | Куда |
|---|---|
| In-service authz holes + identity spoofing (#9/#11/#12/#13/#35/#36/#37/#39/#43/#53) | **W1.6** (Remediation Chunk 2) |
| Gateway wiring + permission catalog (#19/#28/#29/#30/#31/#32/#33/#34/#38/#44/#45/#49) | **W2 Chunk 3** |
| Spec-drift KAC-119/121 (#1/#3/#4/#5/#6/#7/#14/#15/#27/#46/#55) | **W2 Chunk 4** |
| Federation / SSO / AuthZ internals (#20/#21/#23/#25/#26/#40/#41/#42 + OPA-VERIFY) | **W3 Chunk 5** |
| Granular permission-relations in FGA model (`vpc_network_get` set seed) | W2 (после catalog unification) |
| Extraction `fgaoutbox` helper → `kacho-corelib/outbox/fga/` | Backlog (один consumer = kacho-iam; ждём второго) |
| Newman cases for #19/#28-#34/#37-#45 RPC reachability | W2 |

---

## 10. Traceability — finding-id ↔ scenario-id ↔ source-line

| Finding (rem. plan §1.3) | GWT Scenarios | Code-сайт (verified 2026-05-24) | Тест-имя |
|---|---|---|---|
| #8 (P0) | W1.5-08, W1.5-ROLLBACK-02, W1.5-NM-01 | `internal/apps/kacho/api/access_binding/delete.go:116-130` | `Test_AB_Delete_EmitsFGAOutbox_AtomicWithBindingDelete` |
| #16 (P2) | W1.5-16, W1.5-ROLLBACK-01 | `internal/apps/kacho/api/access_binding/create.go:146-172` | `Test_AB_Create_EmitsFGAOutbox_AtomicWithBindingInsert` |
| #47 (P0) | W1.5-47, W1.5-MAP-01..04, W1.5-NM-02 | `create.go:158-225` + `tuples.go:24-115` | `Test_PermissionsToRelations_TableDriven` |
| #48 (P2) | W1.5-48 | duplicate mapper paths | `Test_NoDuplicateRoleMapper_Lint` |
| #50 (P0) | W1.5-50, W1.5-ROLLBACK-03, W1.5-NM-03 | `internal/service/phase7_jit_service.go:333-360` | `Test_JIT_AutoActivate_EmitsFGAOutbox` |
| #51 (P0) | W1.5-51-APPROVE, W1.5-51-EXPIRY, W1.5-NM-04, W1.5-NM-05 | `internal/service/jit_pending_service.go:285-287, ~412` + `phase7b_workers.go::Tick` | `Test_JITPending_Approve_EmitsFGAOutbox`, `Test_JITPending_Expiry_EmitsFGAOutbox` |
| #52 (P0) | W1.5-52, W1.5-ROLLBACK-04, W1.5-NM-06 | `internal/service/phase7_break_glass_service.go:248-296` | `Test_BG_ApproveB_WritesClusterAdminGrants_AndFGAOutbox` |

---

## 11. Ссылки

- Workspace правила: `../../CLAUDE.md` (запреты #1/#10/#11; vault discipline)
- IAM-specific: `../../project/kacho-iam/CLAUDE.md` (Phase 7 § 4.4 atomic CAS; § 5 error map)
- Source of findings: `../superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` §1.3 Chunk 1 + §2 Chunk 1
- Master plan: `../superpowers/plans/2026-05-23-iam-prod-ready-master.md`
- Wave 1 plan: `../superpowers/plans/2026-05-23-iam-prod-ready-wave1.md` §W1.5
- Predecessor acceptance docs:
  - `sub-phase-W1.1-fga-outbox-drainer-acceptance.md` (drainer mechanics)
  - `sub-phase-W1.2-subject-change-cache-invalidation-acceptance.md` (atomic emit-in-tx pattern reference; `SubjectChangeEmitter`)
- Vault entries to update (DoD):
  - `obsidian/kacho/edges/iam-to-openfga-grant-write.md`
  - `obsidian/kacho/resources/iam-access-binding.md`
  - `obsidian/kacho/resources/iam-jit-eligibility.md`
  - `obsidian/kacho/resources/iam-cluster-break-glass-grant.md`
- Reference impl (parity for #52): `project/kacho-iam/internal/apps/kacho/seed/bootstrap_admin.go:90-176`
- Existing fga_outbox writer pattern (для §4.1 helper): same file `bootstrap_admin.go:122-151`
- W1.2 atomic emit-in-tx parity: `project/kacho-iam/internal/repo/kacho/pg/subject_change_emitter.go`
