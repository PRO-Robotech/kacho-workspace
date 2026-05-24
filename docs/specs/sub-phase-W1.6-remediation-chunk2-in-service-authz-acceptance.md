# Sub-phase W1.6 — Remediation Chunk 2: In-service authz holes + identity spoofing — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` per workspace `CLAUDE.md` §Запреты #1).
> **Date**: 2026-05-24
> **YouTrack**: [KAC-164](https://prorobotech.youtrack.cloud/issue/KAC-164) W1.6 (subtask of [KAC-136](https://prorobotech.youtrack.cloud/issue/KAC-136), child of epic [KAC-134](https://prorobotech.youtrack.cloud/issue/KAC-134) "kacho-iam → production-ready").
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-iam` —
>     - `internal/handler/operation_handler.go` (#9)
>     - `internal/authzguard/interceptor.go` (#43)
>     - `internal/apps/kacho/api/access_binding/{list_by_subject,list_by_resource,delete,helpers}.go` (#12, #13)
>     - `internal/apps/kacho/api/access_review/handler.go` + `internal/service/phase7_access_review_service.go` (#35)
>     - `internal/service/jit_pending_service.go` + handler (#36)
>     - `internal/apps/kacho/api/compliance_report/handler.go` + `cmd/kacho-iam/phase7b_wiring.go` (#37)
>     - `internal/apps/kacho/api/jit_eligibility/handler.go` (#39)
>     - `internal/apps/kacho/api/sa_keys/{handler,usecases}.go` (#11, #53)
>   - **NOT touched (verified)**: `kacho-corelib` (no new helper required — pure handler/middleware code); `kacho-proto` (no new RPC / no new field); `kacho-api-gateway` (anti-anon stays in iam since gateway already mediates per-RPC authz). Migration storage: **no new DB migration**.
> **Branch (kacho-iam)**: `KAC-164` (off `main`).
> **Parent epic plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 1.
> **Wave plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-wave1.md` §W1.6.
> **Source of finding-level requirements**: `docs/superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` §1.3 Chunk 2 (findings #9, #11, #12, #13, #35, #36, #37, #39, #43, #53).
> **Predecessors (must be `main`-merged before impl starts)**:
> - W1.4 — principal propagation cross-service ([[KAC-140]]) — **MERGED**. Required so iam handlers can rely on `authzguard.PrincipalFromCtx` returning the *true* caller (not `user:bootstrap`) on cross-service paths.
> - W1.5 — Remediation Chunk 1 ([[KAC-163]]) — **PR open** ([kacho-iam#35](https://github.com/PRO-Robotech/kacho-iam/pull/35)). W1.6 can begin once W1.5 merges (no source-file overlap, but W1.6 newman cases want the W1.5 fga_outbox grant-write path to be GREEN — otherwise NM cases that grant→check would fail for unrelated reasons).
>
> **Why W1.6 closes the 87 newman failures**: per master plan and W1.5 acceptance §0, the 87 failing newman cases break down as `iam-jit-pending`(33) + `iam-user`(25) + `iam-compliance-report`(10) + `iam-internal-only-check`(10) + `iam-access-binding`(8) + `authz-deny`(1). W1.5 makes grants reach FGA atomically. **W1.6 makes the corresponding handlers enforce caller identity** — without it: ListPending leaks across users (33 failures), compliance reports leak cross-tenant (10), AB.ListBySubject by other user (the 8 remaining), spoofed CreatedBy fails audit-shape assertions (jit-eligibility + sa-keys cases), and anti-anon misses Approve* paths (a portion of jit-pending). Together W1.5+W1.6 close the gap.

---

## 0. Преамбула — что эта sub-итерация (précis)

W1.6 закрывает **в-сервисную** прослойку authz, которую W1.1–W1.5 не трогали: правильные tuple
теперь летят в OpenFGA (W1.5), но **handler-слой iam** всё ещё (a) принимает identity-поля
(`reviewer_user_id`, `created_by_user_id`, `created_by`) из request-body вместо authenticated
principal'а — это **identity spoofing** через REST/gRPC, (b) отдаёт чужие данные в `List*`-вызовах
без scope-фильтра — это **information disclosure** на уровне tenant boundary, (c) leak'ает
plaintext `client_secret` в `Operation.response` объекте, к которому может пройти **anonymous**
GET через operation-id (комбо #9 + #11), (d) пропускает мутирующие RPC мимо anti-anon
interceptor'а (Approve/Deny/Issue/Revoke/Generate/Cancel suffix not in match list — #43).

W1.6 поставляет **десять** конкретных handler-/middleware-fix'ов (по findings из remediation plan
§1.3 Chunk 2). Не вводит новых ресурсов, миграций, proto-полей; не меняет drainer/cache/FGA. Pure
handler/usecase/middleware enforcement.

| # | Sev | File:line (verified 2026-05-24) | Симптом | Fix |
|---|---|---|---|---|
| **#9** | P0 | `internal/handler/operation_handler.go:49`, `:62` (`if !authzguard.IsAnonymous(ctx) && !authzguard.IsSelf(...)`) | Ownership-check короткозамкнут на anonymous: `!IsAnonymous(ctx) && !IsSelf(...)` для anonymous возвращает `false && X = false` → guard НЕ срабатывает → anonymous GET'ит **любую** operation по id (включая JIT/AB/SA mutations с принципалом-владельцем в `Operation.response`). | Инвертировать guard: `if authzguard.IsAnonymous(ctx) { return NotFound }` → затем ВСЕГДА выполнять `IsSelf` check. (Bonus: anonymous GET даже **существующей** op'ы → `NotFound` — anti-info-leak parity с KAC-122 CRIT-27 для известных principal'ов.) Симметрично для `Cancel`. |
| **#11** | P0 | `internal/apps/kacho/api/sa_keys/usecases.go:191-199` (`ClientSecret: hydraClient.ClientSecret` встроено в `Operation.response`) | Plaintext `client_secret` живёт в `Operation.response` навечно (operations не удаляются). В комбинации с #9 anonymous может вытащить secret по operation-id. | После закрытия #9 secret уже недоступен anonymous. Дополнительно: **редактировать** `Operation.response` через `(N+1)-фаза masking` — после первого успешного return клиенту во время `Issue`, secret обнуляется в БД (`UPDATE operations SET response = jsonb_set(response, '{client_secret}', '"<redacted>"') WHERE id = $id`). Документировать: «secret returned ONCE on Issue; subsequent `Operation.Get` returns redacted response». См. OQ-W1.6-2. |
| **#12** | P1 | `internal/apps/kacho/api/access_binding/list_by_subject.go:31-36` (`!IsAnonymous && string(subjectType)=="user" && !IsSelf(...)`); `list_by_resource.go:33-37` (`requireGrantAuthority`) | **Частично закрыто** KAC-131/133: ListBySubject self-only **только для user-subjects**; ListByResource — `requireGrantAuthority` (owner или FGA-admin). Остаточный gap: (a) ListBySubject для `subjectType=service_account` / `group` **не scope-filter** (proceeds для любого authenticated); (b) anonymous идёт по `!IsAnonymous && …` short-circuit (false-AND-X = false → guard пропускает) если `RequireAuthenticated` не сработал бы (но он сработал на стр.24 — OK для anonymous). Для **service-account / group** subject — open. | Расширить ListBySubject self-check: для всех subject-types — `IsSelf(ctx, subject_id)` ИЛИ `requireGrantAuthority(ctx, resource_of_binding)` (parity с ListByResource). Symmetric для group: caller должен быть `member` группы ИЛИ resource-admin. ListByResource — already correct, just add explicit table-test to prevent regression. |
| **#13** | P0 | `internal/apps/kacho/api/access_binding/delete.go:78-80` (`if !authzguard.IsSelf(ctx, string(binding.SubjectID)) { return PermissionDenied() }`) | Authority-проверка на Delete = **self-only**: пользователь может удалить ТОЛЬКО binding'и, где `subject_id == principal`. Resource-admin (имеющий `requireGrantAuthority` на resource) **не может** delete'нуть чужой binding на свой же resource — несимметрично с Create (которое использует `requireGrantAuthority`). Side-effect: account-admin не может удалить binding инвайтнутого user'а. | Заменить `IsSelf`-only check на `requireGrantAuthority(ctx, repo, fga, string(binding.ResourceType), binding.ResourceID)` — точное зеркало `create.go::Execute` authority-проверки. Self-binding (subject==principal) — тривиально проходит через grant-authority. Negative-тест: stranger (не self, не admin) → 403. |
| **#35** | P0 | `internal/apps/kacho/api/access_review/handler.go:51,93,134` (`ReviewerUserID: domain.UserID(req.GetReviewerUserId())`); `internal/service/phase7_access_review_service.go::ApproveItem/RevokeItem/AddReviewer` принимает reviewer параметром доверием | Handler пробрасывает `reviewer_user_id` **из тела запроса** в service: каждый authenticated user может decid'ить от имени любого reviewer'а в audit-log. Spoofing audit-identity. | Handler берёт reviewer из `authzguard.PrincipalFromCtx(ctx)`; поле `reviewer_user_id` в `Decide*Request` ([[KAC-127]] proto frozen — поле остаётся для wire-compat) — если non-empty И ≠ principal → `InvalidArgument` («Illegal argument reviewer_user_id: must match authenticated principal or be empty»). Service-layer signature остаётся, handler фиксит источник. |
| **#36** | P1 | `internal/service/jit_pending_service.go:425-433` (`GetPending → s.pending.Get`, `ListPending → s.pending.List` — оба passthrough, scope-фильтра нет) | `GetPending(id)`: любой authenticated user может прочитать любую pending-row → видит requester, approver, justification, resource — pre-decision leak. `ListPending(filter)`: без filter возвращает **все** pending'и cluster-wide. | Filter в caller-scoping (без новых полей в proto, добавляем server-side enforcement): `GetPending` — caller обязан быть `requester` ИЛИ `approver` ИЛИ resource-admin; иначе `NotFound` (anti-info-leak). `ListPending` — авто-filter `requester_user_id == principal OR approver_user_id == principal`; cluster-admin bypass через explicit `JitPendingListFilter.AllScopes=true` доступен только bootstrap/cluster-admin principal'у (KAC-122 §5). |
| **#37** | P0 | `internal/apps/kacho/api/compliance_report/handler.go` (`GetReport`, `GetReportDownloadURL`); `cmd/kacho-iam/phase7b_wiring.go` (wiring без `WithVisibleScopeProvider`); `internal/service/compliance_report_service.go:32-77` (`scopes ComplianceScopeChecker` — есть, но не используется на read-paths) | `GetReport(reportID)`: handler возвращает отчёт **без** scope-проверки — report про project в одном tenant'е доступен всем authenticated. **Cross-tenant leak P0**. Закрытие 10 newman failures из `iam-compliance-report`. | Wiring: расширить `ComplianceScopeChecker` → `VisibleScopeProvider` (метод `IsScopeVisibleToPrincipal(ctx, scope_type, scope_id) bool`). Handler `GetReport`: после `s.Get(id)` — `if !provider.IsScopeVisibleToPrincipal(ctx, report.ScopeType, report.ScopeID) { return NotFound }`. Provider реализация: caller имеет `viewer/admin/auditor` relation на (account|project|organization). `GetReportDownloadURL` — same gate **до** генерации URL. `List` — filter via WHERE на provider-returned visible scopes. |
| **#39** | P0 | `internal/apps/kacho/api/jit_eligibility/handler.go:75-100` (`Create` builds `CreateJITEligibilityRequest` БЕЗ `CreatedBy`); `internal/service/phase7_jit_service.go:137,171,194` (`CreatedBy domain.UserID` в request struct, в DB row, в audit-log) | Handler не задаёт `CreatedBy` → в DB row `created_by=''` → audit-log пишет empty creator. Бонус-симптом: если бы handler пробрасывал из тела (gen-spec позволяет `created_by_user_id` поле в request) — был бы spoofable. **Дыра: audit-identity gap.** | Handler перед `svc.CreateEligibility`: `createReq.CreatedBy = domain.UserID(authzguard.PrincipalUserID(ctx))`. Если proto имеет request-field `created_by_user_id`: handler **игнорирует** body, всегда из principal (parity с #35). Integration test: created row `created_by == principal`. |
| **#43** | P0 | `internal/authzguard/interceptor.go:33-39` (`mutatingSuffixes = ["Create","Update","Delete","Move","Invite","AddMember","RemoveMember","Activate","Block","Unblock","SetPoolSelector","UnsetPoolSelector"]`) | Suffix matcher НЕ покрывает: `Issue` (SA key), `Revoke` (SA key, SessionRevocations, RevokeReviewItem), `Approve*` (ApproveBreakGlassA/B, ApproveJITActivation, ApproveReviewItem), `Deny*` (DenyBreakGlass, DenyJITActivation), `Generate*` (GenerateAccessReport), `Cancel*` (CancelErasureRequest, CancelAccessReviewCampaign), `ActivateJIT`. Anonymous может вызывать все эти мутирующие RPC. P0 — bypass всей anti-anon защиты по широкому surface. | Заменить suffix-matching на **explicit read-only allowlist + default-deny anonymous для всего, что не в allowlist**. Allowlist suffixes: `Get`, `List`, `Watch`, `Resolve`, `BatchGet`, `Search`, `Check`, `Whoami`. Любой RPC, не попавший в allowlist (regardless of mutation suffix), → anonymous-deny. Существующий `whitelistFullMethod` (для legitimate anon RPCs типа `Account.RegisterMyself`, `Federation.Login`) остаётся. Integration: table-test по всем FullMethod'ам из iam protos. |
| **#53** | P0 | `internal/apps/kacho/api/sa_keys/handler.go:41` (`CreatedByUserID: req.GetCreatedByUserId()` — берётся из тела); `usecases.go::IssueSAKey` принимает trustingly | Любой authenticated user может выписать SA-key и заэдоутить любой `created_by_user_id` → audit-log искажён, attribution невозможно. Identity-spoofing. | Handler: `createdBy := authzguard.PrincipalUserID(ctx); if req.GetCreatedByUserId() != "" && req.GetCreatedByUserId() != createdBy { return InvalidArgument }`. UseCase signature остаётся; источник — principal. (#11 redaction — отдельный fix.) |

### 0.1 W1.6 НЕ включает

- **No new proto / no new RPC** — pure handler/middleware fixes. `kacho-proto` не трогаем.
- **No new migration** — все изменения в Go-code (operations row-update для #11 — handwritten `UPDATE operations` через corelib `operations.Repo` extension, см. §4.2 — но это **не миграция схемы**; jsonb-set на existing column).
- **Не меняет fga_outbox / drainer** (W1.1) и не меняет fga_outbox emit-paths (W1.5) — переиспользуем as-is. W1.6 — про **handler-уровень enforcement**, не data-plane.
- **Не реализует SAML/SCIM/SSO внутренности** — #40/#41/#42 → W3 Chunk 5. W1.6 #40 рассматривает только защиту-guard на ACS endpoint (501 / explicit-disabled), см. OQ-W1.6-5.
- **Не меняет gateway authz-middleware** (W1.3) — anti-anon живёт в iam interceptor (`internal/authzguard/interceptor.go`), per-RPC authz live в gateway middleware. W1.6 трогает только iam-side.
- **Не закрывает другие findings раундов 1-2** — #14/#15/#27/#46/#55 → W2 spec-drift; #19/#28-34/#38/#44/#45/#49 → W2 catalog/gateway; #20-26/#41-42/#40 → W3.
- **Не пересматривает уже-закрытые** — #8/#13/#47/#48/#50/#51/#52 — закрыты в W1.5; #16 — закрыт в W1.5. **Уточнение про #13**: рекомендация раунд-1 — `requireGrantAuthority` уже частично применена в `delete.go` для READ-path (#12), но **Delete-path** в `delete.go:78-80` остался self-only — W1.6 завершает.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** | gate данного doc; impl стартует только после APPROVED. |
| **Запрет #2** | в коде/комментариях/тестах не упоминается. |
| **Запрет #3** | handwritten pgx — для #11 redaction (`UPDATE operations … SET response = jsonb_set(...)`). Никакого ORM. |
| **Запрет #4** | within-iam-DB только. Cross-service authority — через peer-API (gateway/iam-internal `Check`), не cross-DB. |
| **Запрет #5** | applied migrations не редактируем. W1.6 — **no new migration**. (Если acceptance-reviewer решит, что `redacted_at` колонка нужна для #11 audit — отдельная миграция; default — без, см. §4.2.) |
| **Запрет #6** | `Internal.*` separation сохраняется. Anti-anon interceptor работает на **обоих** listener'ах (public + internal); internal listener mTLS-gated в proд, но default-deny anonymous остаётся в силе. |
| **Запрет #7** | broker отсутствует. |
| **Запрет #8** | DB-per-service. Cross-service authority-check для VisibleScopeProvider (#37) — через peer-API (`InternalIAMService.Check` локально, для project/account scopes — own DB). |
| **Запрет #9** | мутации остаются async via Operation. `Issue/Approve*/Deny*/Cancel*/Generate*` возвращают `*operation.Operation` без изменений. |
| **Запрет #10** (within-service refs DB-level) | для #11 (redaction `UPDATE`) — single-statement UPDATE на одной row, race-free. CAS не требуется (idempotent redaction: `jsonb_set` повторно с `<redacted>` — no-op). |
| **Запрет #11** (test-first + tests-in-PR + RED→GREEN) | каждый из 10 findings закрывается одной парой `RED (failing integration/newman) → GREEN (impl)`. См. §5/6 для распределения; §6.5 для NM closing strategy. |
| **CLAUDE.md §Принцип переиспользования через kacho-corelib** | новый helper `authzguard.PrincipalUserID(ctx) string` (если ещё нет — есть `PrincipalFromCtx`; добавить тонкую обёртку) живёт в kacho-iam `internal/authzguard/`, не в corelib (используется единственным сервисом). |
| **CLAUDE.md §«Within-service refs DB-уровень обязателен»** | #11 redaction — atomic single-statement UPDATE. Прочие #-fix'ы — handler/usecase enforcement, не trogают invariant DB-shape. |
| **Vault discipline** | KAC-164.md заметка; обновление `edges/iam-anti-anon-interceptor.md` (создать если нет) — explicit read-only allowlist policy; `resources/iam-operation.md` — note про redaction post-first-read; `resources/iam-access-binding.md` — Delete authority = grant-authority (mirror Create); `resources/iam-compliance-report.md` — Get/List scope-filtered; `resources/iam-jit-pending.md` — Get/List caller-scoped; `resources/iam-access-review.md` — reviewer from principal; `resources/iam-sa-key.md` — created_by from principal. |

---

## 2. Глоссарий

- **`authzguard.PrincipalFromCtx(ctx)`** — existing function in `internal/authzguard/`; returns `Principal` struct (Type, ID, …).
- **`authzguard.PrincipalUserID(ctx) string`** (NEW thin helper, §4.0) — convenience: returns empty for anonymous/non-user, returns ID for user/service-account principal.
- **`authzguard.IsAnonymous(ctx)`** — existing; true если principal-type == anonymous.
- **`authzguard.IsSelf(ctx, id)`** — existing; true если principal-type == user и principal.ID == id.
- **`requireGrantAuthority(ctx, repo, fga, resource_type, resource_id) error`** — existing in `access_binding/helpers.go`; allow если caller — account-owner ИЛИ FGA-admin на resource.
- **Identity spoofing** — handler принимает `<role>_user_id` поле в request-body и доверяет ему (использует для DB-INSERT, audit, FGA-tuple). W1.6 фиксит: source-of-truth = authenticated principal.
- **VisibleScopeProvider** (NEW, §4.7) — port на handler-уровне `compliance_report`: `IsScopeVisibleToPrincipal(ctx, scope_type, scope_id) bool` + `ListVisibleScopes(ctx, scope_type) []string`. Реализация — over existing IAM repos (project membership + access bindings).
- **Read-only allowlist** (NEW, §4.9) — explicit set of method-suffixes that don't require authentication. Default-deny everything else for anonymous principals.
- **Redacted Operation response** (NEW, §4.2) — после первого успешного return из `SAKeyService.Issue`, `client_secret` field в `operations.response` jsonb замещается `"<redacted>"`. Single-statement UPDATE; idempotent.

---

## 3. Data model — без изменений

W1.6 **не вводит** новых таблиц, колонок, индексов или migrations. Все enforcement-fix'ы — на handler/usecase уровне.

> **Исключение (acceptance-reviewer call)**: возможно опциональная колонка `operations.response_redacted_at timestamptz` для audit-trail (когда secret обнулён). Если решено добавить — отдельная migration `0025_operations_response_redacted_at.sql`. **Default — без**, см. OQ-W1.6-2.

---

## 4. Изменения по файлам (impl spec)

### 4.0 NEW helper — `internal/authzguard/principal.go::PrincipalUserID`

```go
// PrincipalUserID returns the principal's user-id for user/service-account
// principals; empty string for anonymous, system, or other principal types.
// Use this when you need the caller-id-as-string for DB writes (created_by,
// reviewer, etc) — never trust a request-body field for these.
func PrincipalUserID(ctx context.Context) string {
    p, ok := PrincipalFromCtx(ctx)
    if !ok { return "" }
    switch p.Type {
    case "user", "service_account":
        return string(p.ID)
    default:
        return ""
    }
}
```

If `PrincipalFromCtx` doesn't exist with this exact shape — adapt to actual signature; the goal is one canonical accessor that maps **principal → DB-storable user-id**.

### 4.1 `internal/handler/operation_handler.go` (#9)

- **Get** (`:49`): inversion of guard.

  ```go
  // BEFORE:
  if !authzguard.IsAnonymous(ctx) && !authzguard.IsSelf(ctx, op.Principal.ID) {
      return nil, status.Errorf(codes.NotFound, "operation %s not found", req.OperationId)
  }
  // AFTER:
  if authzguard.IsAnonymous(ctx) {
      return nil, status.Errorf(codes.NotFound, "operation %s not found", req.OperationId)
  }
  if !authzguard.IsSelf(ctx, op.Principal.ID) {
      return nil, status.Errorf(codes.NotFound, "operation %s not found", req.OperationId)
  }
  ```

  Anonymous → NotFound (anti-info-leak); known-other-principal → NotFound (existing behaviour).

- **Cancel** (`:62`): same pattern. Anonymous → NotFound.

### 4.2 `internal/apps/kacho/api/sa_keys/usecases.go` (#11)

After successful `Issue` (line ~199, where `ClientSecret: hydraClient.ClientSecret` is returned to caller):

1. Build response with plaintext secret as today.
2. **Before returning** to handler — schedule (or perform inline as part of operations.Repo.Done) `UPDATE operations SET response = jsonb_set(response, '{client_secret}', '"<redacted>"') WHERE id = $opID` via new method `operations.Repo.RedactResponseField(ctx, opID, fieldPath, value)`.

Net effect: `Issue` returns secret once to direct caller; subsequent `Operation.Get(opID)` returns response with `client_secret = "<redacted>"`.

If `operations.Repo` extension is not desirable (touches corelib): inline `tx.Exec(...)` in sa_keys usecase against `kacho_iam.operations` — within-service same-DB allowed.

> **Caveat**: this is defence-in-depth on top of #9 fix. Once #9 closes the anonymous bypass, only the issuer can ever GET the operation. Redaction protects against compromised issuer-token replay too.

### 4.3 `internal/apps/kacho/api/access_binding/list_by_subject.go` (#12)

Replace current self-only-for-user guard (`:31-36`) with:

```go
if err := authzguard.RequireAuthenticated(ctx); err != nil {
    return nil, "", err
}
// Caller may list bindings if:
//  (a) caller is the subject (parity with KAC-133 self-rule), OR
//  (b) caller is account-owner / FGA-admin on at least one resource bound
//      to subject in this page — handled per-row by ListByResource filter.
//
// For ListBySubject specifically: enforce subject==principal as the simplest
// closure. Stronger surface (admin-can-list-others-bindings) is closed by
// ListByResource (admin scope) and access_review (campaign-driven view).
if !authzguard.IsSelf(ctx, string(subjectID)) {
    // anti-info-leak: NotFound, not PermissionDenied — same shape as #9.
    return nil, "", authzguard.PermissionDenied()
}
```

Cover all subjectTypes (user, service_account, group). Group: caller must be member; we currently lack group-membership-check in iam — fall back to self-only for groups (admin tooling uses InternalListBySubject).

### 4.4 `internal/apps/kacho/api/access_binding/list_by_resource.go` (#12)

Already enforces `requireGrantAuthority`. **W1.6 task**: add explicit **table-driven integration test** preventing regression. No code change.

### 4.5 `internal/apps/kacho/api/access_binding/delete.go` (#13)

Replace `:78-80`:

```go
// BEFORE:
if !authzguard.IsSelf(ctx, string(binding.SubjectID)) {
    return nil, authzguard.PermissionDenied()
}
// AFTER (mirror Create authority — KAC-128/131 paths):
if err := requireGrantAuthority(ctx, u.repo, u.fga, string(binding.ResourceType), binding.ResourceID); err != nil {
    return nil, err
}
```

Self-binding (subject==principal) trivially passes `requireGrantAuthority` because caller is account-owner of their own account. Admin-revoking-strangers-binding-on-own-resource: passes. Stranger-revoking-other-binding-on-not-own-resource: 403.

### 4.6 `internal/apps/kacho/api/access_review/handler.go` + `internal/service/phase7_access_review_service.go` (#35)

- Handler (`:51`, `:93`, `:134` — three call sites for `ReviewerUserID: domain.UserID(req.GetReviewerUserId())`): replace with:

  ```go
  principal := authzguard.PrincipalUserID(ctx)
  if principal == "" {
      return nil, authzguard.PermissionDenied()
  }
  if rv := req.GetReviewerUserId(); rv != "" && rv != principal {
      return nil, status.Error(codes.InvalidArgument,
          "Illegal argument reviewer_user_id: must match authenticated principal or be empty")
  }
  // …
  ReviewerUserID: domain.UserID(principal),
  ```

  Proto-field оставляем (wire-compat, KAC-127 frozen): non-empty must == principal, иначе InvalidArgument.

- Service signatures (`phase7_access_review_service.go`) — без изменений.

### 4.7 `internal/service/jit_pending_service.go` + handler (#36)

`GetPending(id)` — добавить caller-scope:

```go
func (s *JitPendingService) GetPending(ctx context.Context, id domain.JitPendingID) (domain.JitPending, error) {
    p, err := s.pending.Get(ctx, id)
    if err != nil { return domain.JitPending{}, err }
    caller := authzguard.PrincipalUserID(ctx)
    if caller == "" {
        return domain.JitPending{}, authzguard.PermissionDenied()
    }
    // Visible if caller is requester OR approver OR has admin on resource.
    if caller != string(p.RequesterUserID) && caller != string(p.ApproverUserID) {
        // resource-admin bypass — check FGA admin on (p.ResourceType, p.ResourceID)
        if !s.hasResourceAdmin(ctx, p.ResourceType, p.ResourceID) {
            // anti-info-leak: NotFound, not PermissionDenied
            return domain.JitPending{}, domain.ErrJitPendingNotFound
        }
    }
    return p, nil
}
```

`ListPending(filter)` — авто-scope:

```go
if !s.isClusterAdminCaller(ctx) {
    filter.RequesterOrApproverUserID = authzguard.PrincipalUserID(ctx) // server-side WHERE
}
```

Filter-struct field is new (no proto change — server-side enforcement); pending repo's `List` SQL filters: `WHERE requester_user_id = $X OR approver_user_id = $X`.

### 4.8 `internal/apps/kacho/api/compliance_report/handler.go` + `cmd/kacho-iam/phase7b_wiring.go` (#37)

- Wiring: extend `ComplianceScopeChecker` to `VisibleScopeProvider`:

  ```go
  type VisibleScopeProvider interface {
      ComplianceScopeChecker
      IsScopeVisibleToPrincipal(ctx context.Context, scopeType, scopeID string) bool
      ListVisibleScopes(ctx context.Context, scopeType string, principalID string) ([]string, error)
  }
  ```

  Impl: query `access_bindings` for `(subject=principal, resource_type=scopeType, resource_id=scopeID, relation IN ('admin','auditor','viewer'))` + project-of-account hierarchy.

- Handler `GetReport`: after `s.Get(reportID)`, call `provider.IsScopeVisibleToPrincipal(ctx, report.ScopeType, report.ScopeID)` — if false → `NotFound` (anti-info-leak parity).
- `GetReportDownloadURL`: same gate **before** URL generation (don't generate signed URL for invisible report).
- `List`: replace open select with `WHERE scope_id IN (provider.ListVisibleScopes(ctx, ...))`.

### 4.9 `internal/apps/kacho/api/jit_eligibility/handler.go` (#39)

`Create` handler (`:75-100`): append `CreatedBy` from principal:

```go
createReq := service.CreateJITEligibilityRequest{
    UserID:           domain.UserID(req.GetUserId()),
    RoleID:           domain.RoleID(req.GetRoleId()),
    // … unchanged …
    CreatedBy:        domain.UserID(authzguard.PrincipalUserID(ctx)), // NEW
}
if createReq.CreatedBy == "" {
    return nil, authzguard.PermissionDenied() // anonymous can't create eligibility
}
```

If proto has `created_by_user_id` in `CreateJITEligibilityRequest` (TODO: verify; if absent — no body-field to ignore, just enforce-from-principal). If present, ignore body value (already done by W1.6 above — no `req.GetCreatedByUserId()` read).

### 4.10 `internal/apps/kacho/api/sa_keys/{handler,usecases}.go` (#53)

Handler (`handler.go:41`): replace `CreatedByUserID: req.GetCreatedByUserId()` with:

```go
principal := authzguard.PrincipalUserID(ctx)
if principal == "" {
    return nil, authzguard.PermissionDenied()
}
if rv := req.GetCreatedByUserId(); rv != "" && rv != principal {
    return nil, status.Error(codes.InvalidArgument,
        "Illegal argument created_by_user_id: must match authenticated principal or be empty")
}
// …
CreatedByUserID: principal,
```

UseCase signature unchanged.

### 4.11 `internal/authzguard/interceptor.go` (#43)

Replace suffix-based `isMutating` (`:54-66`) with read-only allowlist:

```go
// readonlySuffixes — методы которые НЕ требуют authenticated principal
// (read-only по контракту). Anything not in this set is treated as a
// mutating / sensitive RPC and gated by anti-anon.
var readonlySuffixes = []string{
    "Get", "List", "Watch", "Resolve",
    "BatchGet", "Search", "Check", "Whoami",
}

func isReadOnly(fullMethod string) bool {
    parts := strings.Split(fullMethod, "/")
    if len(parts) < 3 {
        return false
    }
    name := parts[len(parts)-1]
    for _, s := range readonlySuffixes {
        if strings.HasSuffix(name, s) || strings.HasPrefix(name, s) {
            return true
        }
    }
    return false
}

// AntiAnonymousUnary — default-deny anonymous unless in whitelistFullMethod
// or has a read-only suffix.
func AntiAnonymousUnary(logger *slog.Logger) grpc.UnaryServerInterceptor {
    return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
        if _, ok := whitelistFullMethod[info.FullMethod]; ok {
            return handler(ctx, req)
        }
        if isReadOnly(info.FullMethod) {
            return handler(ctx, req)
        }
        if authzguard.IsAnonymous(ctx) {
            logger.Warn("authz_anonymous_mutation_denied",
                slog.String("method", info.FullMethod))
            return nil, status.Errorf(codes.PermissionDenied,
                "anonymous calls to %s are not permitted", info.FullMethod)
        }
        return handler(ctx, req)
    }
}
```

Note: `whitelistFullMethod` (legitimate anon RPCs like `Account.RegisterMyself`, `Federation.Login`, `BreakGlass.Request` if explicit-allowed) remains. Stream interceptor: symmetric pattern.

---

## 5. Test discipline (запрет #11) — RED first

PR обязан содержать **в указанном порядке**:

1. **RED phase commit** (testing-only): all §6 integration tests + §6.5 newman cases written and committed BEFORE any impl. CI red on this commit (compile-fail OR test-fail).
2. **GREEN phase commits**: per-finding impl driving each RED test → GREEN. PR description shows per-finding RED→GREEN evidence (test name, before-output, after-output).
3. **Newman cases** added to `project/kacho-iam/tests/newman/cases/authz-deny.py` (new cases) and per-domain files where appropriate (jit-pending.py, compliance-report.py, sa-keys.py, etc.); regenerate via `gen.py`; verify `run.sh` picks up; verify CI matrix gate (W0.3) still green.
4. **Anti-spoof integration tests obligatory** (§6.4): for each spoof-fix (#35/#39/#53), assert (a) body-supplied identity is rejected if ≠ principal, (b) row written by handler has identity = principal, (c) audit emit has identity = principal. No exceptions.
5. **Anti-anon table test obligatory** (§6.6 W1.6-ANON-TABLE): enumerate every gRPC FullMethod registered in iam (use reflection on `RegisterServiceServer` or proto-descriptors), assert: with anonymous ctx → only allowlisted methods reach handler, all others return `PermissionDenied`.

---

## 6. Сценарии (Given-When-Then) — основа интеграционных тестов

> All scenarios use Postgres testcontainer (kacho-iam migrations 0001-0024 applied) + fake OpenFGAClient (already in repo) + bufconn gRPC server with `AntiAnonymousUnary` interceptor mounted.

### 6.1 Per-finding happy + negative

#### Сценарий W1.6-09-HAPPY — known principal GETs own operation

**ID**: W1.6-09-HAPPY (closes #9 happy path)

**Given** principal `usr_owner` created Operation `op_t9a` (e.g. AccessBinding.Create returned op)
**And** Operation row has `principal_id = usr_owner`

**When** ctx contains principal=`usr_owner`, call `OperationService.Get(op_t9a)`

**Then** returns `*operationpb.Operation` with id=`op_t9a` (200 OK shape)

---

#### Сценарий W1.6-09-ANON-DENY — anonymous GET → NotFound

**ID**: W1.6-09-ANON-DENY (closes #9 anonymous bypass)

**Given** Operation `op_t9b` exists with `principal_id = usr_alice`
**And** ctx is anonymous

**When** `OperationService.Get(op_t9b)`

**Then** returns `codes.NotFound` (анти-info-leak: anonymous никогда не должен видеть существование чужой operation)

---

#### Сценарий W1.6-09-OTHER-DENY — known-different principal → NotFound

**ID**: W1.6-09-OTHER-DENY (closes #9 cross-user leak)

**Given** Operation `op_t9c` exists with `principal_id = usr_alice`
**And** ctx principal = `usr_bob`

**When** `OperationService.Get(op_t9c)`

**Then** returns `codes.NotFound` (parity with existing pre-W1.6 behaviour for known principals)

---

#### Сценарий W1.6-09-CANCEL — anonymous Cancel → NotFound

**ID**: W1.6-09-CANCEL

Mirror W1.6-09-ANON-DENY for `OperationService.Cancel(...)`.

---

#### Сценарий W1.6-11-REDACT — SA key Issue returns secret once, subsequent Get returns redacted

**ID**: W1.6-11-REDACT (closes #11)

**Given** principal `usr_issuer`
**When** call `SAKeyService.Issue(sa=sva_test)` → Operation completes with response containing `client_secret="ABCDEFG…"` (plaintext)
**And** `usr_issuer` calls `OperationService.Get(op_issue_id)`

**Then** first call returns `client_secret = "ABCDEFG…"` (the original plaintext)
**And** **immediately after** (sub-second), DB row `operations.response.client_secret` = `"<redacted>"`
**And** второй call `OperationService.Get(op_issue_id)` returns `client_secret = "<redacted>"`
**And** anonymous call to `OperationService.Get(op_issue_id)` → `NotFound` (W1.6-09)

---

#### Сценарий W1.6-12-LISTBYSUBJECT-FOREIGN-DENY — caller cannot list other user's bindings

**ID**: W1.6-12-LISTBYSUBJECT-FOREIGN (closes #12 user-subject leak by service-account or other path)

**Given** binding rows exist for subject `usr_alice` (user) and `sva_zeus` (service-account)
**And** ctx principal = `usr_bob`

**When** `AccessBindingService.ListAccessBindingsBySubject(subjectType=user, subjectId=usr_alice)`

**Then** returns `PermissionDenied`

**When** `ListAccessBindingsBySubject(subjectType=service_account, subjectId=sva_zeus)`

**Then** returns `PermissionDenied` (pre-W1.6 проходило бы для SA-subject)

---

#### Сценарий W1.6-12-LISTBYRESOURCE-REGRESSION — already-correct path stays correct

**ID**: W1.6-12-LISTBYRESOURCE-REGRESSION (closes #12 regression-prevention)

Table-test: 3-pronged matrix (owner, FGA-admin, stranger) × resource → expected (200, 200, 403).

---

#### Сценарий W1.6-13-DELETE-BY-ADMIN-ALLOW — account-admin can revoke stranger's binding on own resource

**ID**: W1.6-13-DELETE-BY-ADMIN (closes #13 admin-can't-delete)

**Given** binding `acb_t13a` (subject=`usr_alice`, resource=`project:prj_corp`, granted by `usr_corp_admin`)
**And** ctx principal = `usr_corp_admin` (has admin FGA on `project:prj_corp`)

**When** `AccessBindingService.Delete(acb_t13a)`

**Then** Operation completes successfully, binding row deleted, FGA tuple revoke emitted (W1.5 path)

---

#### Сценарий W1.6-13-DELETE-BY-STRANGER-DENY — stranger cannot revoke binding

**ID**: W1.6-13-DELETE-BY-STRANGER (closes #13 authority-mismatch)

**Given** binding `acb_t13b` (subject=`usr_alice`, resource=`project:prj_corp`)
**And** ctx principal = `usr_random_outsider` (no admin on `project:prj_corp`, not subject)

**When** `AccessBindingService.Delete(acb_t13b)`

**Then** returns `PermissionDenied`

---

#### Сценарий W1.6-35-REVIEWER-IS-PRINCIPAL — reviewer field from principal

**ID**: W1.6-35-PRINCIPAL (closes #35 happy path)

**Given** access-review campaign `arc_t35` exists; principal = `usr_reviewer_actual`
**When** `AccessReviewService.ApproveItem(campaign=arc_t35, item=ari_x, reviewer_user_id="")` (empty body)

**Then** campaign-item row decided_by = `usr_reviewer_actual`
**And** audit log shows `reviewer_user_id = usr_reviewer_actual`

---

#### Сценарий W1.6-35-SPOOF-DENY — reviewer spoof from body → InvalidArgument

**ID**: W1.6-35-SPOOF (closes #35 identity spoofing)

**Given** principal = `usr_reviewer_actual`
**When** `AccessReviewService.ApproveItem(..., reviewer_user_id="usr_someone_else")`

**Then** returns `codes.InvalidArgument` with text containing `"reviewer_user_id"` and `"authenticated principal"`

---

#### Сценарий W1.6-36-GET-FOREIGN-DENY — non-participant cannot GET pending

**ID**: W1.6-36-GET-FOREIGN (closes #36 read-leak)

**Given** `jit_pending` row `jp_t36` (requester=`usr_alice`, approver=`usr_admin`, resource=`project:prj_y`)
**And** ctx principal = `usr_outsider` (not requester, not approver, no admin on `project:prj_y`)

**When** `JitPendingService.GetPending(jp_t36)`

**Then** returns `domain.ErrJitPendingNotFound` (handler → NotFound)

---

#### Сценарий W1.6-36-LIST-SCOPED — list returns only own pending rows

**ID**: W1.6-36-LIST-SCOPED (closes #36 list-leak)

**Given** 3 pending rows: A (requester=usr_alice), B (approver=usr_alice), C (requester=usr_bob, approver=usr_charlie)
**And** ctx principal = `usr_alice`

**When** `JitPendingService.ListPending(filter={})`

**Then** returns exactly 2 rows (A + B), not C

---

#### Сценарий W1.6-37-GET-FOREIGN-DENY — caller without scope-visibility → NotFound

**ID**: W1.6-37-FOREIGN (closes #37 cross-tenant leak — primary)

**Given** ComplianceReport `cr_t37` (scope=project:prj_corp_X)
**And** ctx principal = `usr_other_tenant` (no admin/viewer/auditor binding on prj_corp_X)

**When** `ComplianceReportService.GetReport(cr_t37)`

**Then** returns `codes.NotFound`

**When** `GetReportDownloadURL(cr_t37)`

**Then** returns `codes.NotFound` (no signed URL leaked)

---

#### Сценарий W1.6-37-LIST-SCOPED — list filtered to visible scopes

**ID**: W1.6-37-LIST-SCOPED

3 reports across 3 scopes; principal has visibility on 1 → List returns only that one.

---

#### Сценарий W1.6-39-CREATEDBY-AUDIT — Create stamps CreatedBy from principal

**ID**: W1.6-39 (closes #39)

**Given** principal = `usr_creator`
**When** `JITEligibilityService.Create(user_id=usr_target, role_id=rol_x, …)`

**Then** Operation completes; DB row `jit_eligibilities.created_by = "usr_creator"`
**And** audit row `created_by = "usr_creator"`

---

#### Сценарий W1.6-43-ANON-DENY-APPROVE — anonymous cannot ApproveJITActivation

**ID**: W1.6-43-APPROVE (closes #43 — sample anti-anon coverage)

**Given** ctx anonymous; pending row `jp_t43`
**When** `JitPendingService.ApproveJITActivation(jp_t43)` — gRPC call through `AntiAnonymousUnary`

**Then** interceptor returns `codes.PermissionDenied` BEFORE handler reached

---

#### Сценарий W1.6-43-ANON-DENY-ISSUE — anonymous cannot Issue SA key

**ID**: W1.6-43-ISSUE

Same shape: `SAKeyService.Issue` → PermissionDenied via interceptor.

---

#### Сценарий W1.6-43-ANON-ALLOW-READ — anonymous can still GET (read-only allowlist works)

**ID**: W1.6-43-READ-OK

Anonymous → `RoleService.List` (existing public catalog assumption from KAC-121) → 200 OK (interceptor passes through readonly).

---

#### Сценарий W1.6-53-SAKEY-PRINCIPAL — created_by_user_id from principal

**ID**: W1.6-53 (closes #53)

**Given** principal = `usr_actual_creator`
**When** `SAKeyService.Issue(sa=sva_x, created_by_user_id="")`

**Then** DB row `service_account_keys.created_by_user_id = "usr_actual_creator"`

**When** `Issue(..., created_by_user_id="usr_someone_else")`

**Then** returns `codes.InvalidArgument`

---

### 6.2 Anti-anon enumeration table-test

#### Сценарий W1.6-ANON-TABLE — every FullMethod tested with anonymous ctx

**ID**: W1.6-ANON-TABLE-01

**Given** iam gRPC server stood up with all real handlers + `AntiAnonymousUnary` interceptor
**And** complete list of FullMethods extracted via `reflection.NewServer(grpcSrv).ListServices()`

**When** for each FullMethod, call with anonymous ctx (and minimum-valid request body)

**Then** every FullMethod NOT in `whitelistFullMethod` AND NOT matching readonly-suffix → `codes.PermissionDenied`
**And** every FullMethod IN `whitelistFullMethod` OR matching readonly-suffix → reaches handler (allowed at interceptor; may still fail downstream — that's OK)

This test must enumerate **every iam RPC** — currently ~100+ methods across 25+ services. Catches forgotten Approve*/Deny*/Generate*/Cancel*/Issue/Revoke methods.

---

### 6.3 Anti-spoof property tests

#### Сценарий W1.6-SPOOF-PROPERTY-01 — table-driven for #35, #39, #53

**ID**: W1.6-SPOOF-PROPERTY-01

For each handler (`access_review.ApproveItem`, `access_review.RevokeItem`, `access_review.AddReviewer`, `jit_eligibility.Create`, `sa_keys.Issue`):
- empty body field + principal=`X` → row.creator/reviewer = `X` ✓
- body field == principal → row.field = principal ✓
- body field ≠ principal → `InvalidArgument` ✓
- anonymous → `PermissionDenied` ✓

---

### 6.4 Scope-filter integration tests (compliance_report)

#### Сценарий W1.6-SCOPE-VISIBILITY-01 — VisibleScopeProvider returns expected scopes

**ID**: W1.6-SCOPE-01

Seeds: `usr_p1` has admin-binding on `project:prj_A`, viewer on `account:acc_B`, nothing on `project:prj_C`.

`VisibleScopeProvider.ListVisibleScopes(ctx, "project")` → `[prj_A]` (admin includes); `ListVisibleScopes(ctx, "account")` → `[acc_B]`.

`IsScopeVisibleToPrincipal(ctx, "project", "prj_A")` → true; `(..., "project", "prj_C")` → false.

---

### 6.5 Newman E2E — closing strategy per failing-suite

> **Goal**: close all 87 currently-failing newman cases (87 → 0). Per master plan baseline (1057/1144 GREEN; 87 RED). Distribution: jit-pending (33), user (25), compliance-report (10), internal-only-check (10), access-binding (8), authz-deny (1).

#### Newman W1.6-NM-01 — `OP-GET-ANON-DENY` (NEW; closes #9)

**ID**: W1.6-NM-01

**Given** AAA creates AB → returns op_id
**When** anonymous `GET /operation/v1/operations/{op_id}`

**Then** 404 NotFound (anti-info-leak)

---

#### Newman W1.6-NM-02 — `OP-CANCEL-ANON-DENY` (NEW; closes #9)

**ID**: W1.6-NM-02

Symmetric: anonymous `POST /operation/v1/operations/{op_id}:cancel` → 404.

---

#### Newman W1.6-NM-03 — `SAKEY-SECRET-NOT-LEAKED-VIA-OP` (NEW; closes #11)

**ID**: W1.6-NM-03

AAA `IssueSAKey` → op completes with `client_secret` plaintext returned ONCE. Immediately AAA `GET /operation/v1/operations/{op_id}` → response.client_secret = `"<redacted>"`. Anonymous GET → 404.

---

#### Newman W1.6-NM-04 — `JIT-ACTIVATE-ANON-DENY` (NEW; closes #43)

**ID**: W1.6-NM-04

Anonymous calls `POST /iam/v1/jit_pending:activate` → 403 (interceptor).

---

#### Newman W1.6-NM-05 — `REVIEW-APPROVE-ANON-DENY` (NEW; closes #43)

**ID**: W1.6-NM-05

Anonymous `POST /iam/v1/access_review_campaigns/{id}/items/{item}:approve` → 403.

---

#### Newman W1.6-NM-06 — `BIND-LIST-BY-SUBJECT-FOREIGN-DENY` (NEW; closes #12, **closes 8 iam-access-binding failures**)

**ID**: W1.6-NM-06

INV (user B) `GET /iam/v1/accessBindings:listBySubject?subjectType=user&subjectId=<userA>` → 403.

---

#### Newman W1.6-NM-07 — `BIND-LIST-BY-RESOURCE-SCOPED` (regression; closes #12)

**ID**: W1.6-NM-07

Matrix: owner / FGA-admin / stranger × `GET /iam/v1/accessBindings:listByResource` → 200/200/403.

---

#### Newman W1.6-NM-08 — `BIND-DELETE-BY-ADMIN-ALLOW` (NEW; closes #13)

**ID**: W1.6-NM-08

Account-admin DELETEs stranger's binding on own project → 200; binding gone (verify ListByResource); FGA tuple revoked (verify Check DENY post-drainer).

---

#### Newman W1.6-NM-09 — `BIND-DELETE-BY-STRANGER-DENY` (NEW; closes #13)

**ID**: W1.6-NM-09

Outsider DELETEs binding → 403.

---

#### Newman W1.6-NM-10 — `REVIEW-DECIDE-REVIEWER-IS-PRINCIPAL` (NEW; closes #35)

**ID**: W1.6-NM-10

AAA decides item with empty `reviewer_user_id` → audit shows AAA's id.

---

#### Newman W1.6-NM-11 — `REVIEW-DECIDE-SPOOF-DENY` (NEW; closes #35)

**ID**: W1.6-NM-11

AAA decides with `reviewer_user_id = INV.id` → 400 InvalidArgument.

---

#### Newman W1.6-NM-12 — `JITPENDING-LIST-SCOPED` (NEW; closes #36, **major portion of 33 iam-jit-pending failures**)

**ID**: W1.6-NM-12

USER-A creates pending; USER-B's `GET /iam/v1/jit_pending` returns 0 rows (filtered).

---

#### Newman W1.6-NM-13 — `JITPENDING-GET-FOREIGN-DENY` (NEW; closes #36)

**ID**: W1.6-NM-13

USER-B `GET /iam/v1/jit_pending/{USER-A-pending-id}` → 404.

---

#### Newman W1.6-NM-14 — `COMPLIANCE-GET-FOREIGN-DENY` (NEW; closes #37, **closes 10 iam-compliance-report failures**)

**ID**: W1.6-NM-14

User B (no admin on tenant A's project) `GET /iam/v1/complianceReports/{tenant_A_report_id}` → 404.

---

#### Newman W1.6-NM-15 — `COMPLIANCE-LIST-SCOPED` (NEW; closes #37)

**ID**: W1.6-NM-15

Two tenants with reports; principal sees only own tenant's reports.

---

#### Newman W1.6-NM-16 — `JITELIG-CREATEDBY-AUDIT` (NEW; closes #39)

**ID**: W1.6-NM-16

AAA POSTs new eligibility; GET back the eligibility → `createdByUserId == AAA.id`.

---

#### Newman W1.6-NM-17 — `SAKEY-CREATEDBY-NOT-SPOOFABLE` (NEW; closes #53)

**ID**: W1.6-NM-17

AAA tries POST `IssueSAKey` with `created_by_user_id=INV.id` → 400 InvalidArgument.

---

#### Newman W1.6-NM-18..N — iam-user (25 failures) + iam-internal-only-check (10 failures) — closing strategy

**ID**: W1.6-NM-USER, W1.6-NM-INTERNAL-CHECK

These suites' failures need investigation during impl: most likely **anti-anon + scope-filter cascades** from #36/#37/#43 will close them as side-effect (User RPCs do member-lookups that pass-through anti-anon now; internal-only-check enforces gateway internal-listener separation, was failing because of missing anti-anon on read paths). Specific case-by-case closing strategy decided in impl-time triage; acceptance-reviewer enforces all 25 + 10 GREEN as DoD §7.

> **Suite-level commitment**: post-W1.6 merge, `iam-jit-pending`, `iam-user`, `iam-compliance-report`, `iam-internal-only-check`, `iam-access-binding`, `authz-deny` **all GREEN** (87 → 0).

---

### 6.6 Cancel/Revoke edge-cases

#### Сценарий W1.6-CANCEL-OPS — anonymous Operation.Cancel coverage

Already in W1.6-09-CANCEL.

#### Сценарий W1.6-REVOKE-SAKEY — anonymous SAKey.Revoke → PermissionDenied via interceptor

Covered by W1.6-ANON-TABLE.

---

## 7. Definition of Done

- [ ] `acceptance-reviewer` ✅ APPROVED данного doc; all OQs resolved
- [ ] Branch `KAC-164` создан в `kacho-iam`
- [ ] **RED phase commit**: all §6 integration tests + §6.5 newman cases written, regenerated, CI red — RED evidence in PR description per finding
- [ ] **GREEN phase commits** (one logical commit per finding, ordered by independence; some can land together):
  - [ ] #9 — operation_handler.go guard inversion (RED W1.6-09-* → GREEN)
  - [ ] #11 — sa_keys redaction (RED W1.6-11-REDACT → GREEN)
  - [ ] #12 — list_by_subject self-only (all subject types) (RED W1.6-12-* → GREEN)
  - [ ] #13 — delete.go requireGrantAuthority (RED W1.6-13-* → GREEN)
  - [ ] #35 — access_review reviewer-from-principal (RED W1.6-35-* → GREEN)
  - [ ] #36 — JitPending caller-scoping (RED W1.6-36-* → GREEN)
  - [ ] #37 — VisibleScopeProvider wiring + compliance_report gates (RED W1.6-37-*, W1.6-SCOPE-01 → GREEN)
  - [ ] #39 — jit_eligibility CreatedBy from principal (RED W1.6-39 → GREEN)
  - [ ] #43 — interceptor read-only allowlist (RED W1.6-43-*, W1.6-ANON-TABLE → GREEN)
  - [ ] #53 — sa_keys CreatedByUserID from principal (RED W1.6-53 → GREEN)
- [ ] Anti-anon table-test (W1.6-ANON-TABLE) enumerates 100% iam FullMethods, all expected outcomes GREEN
- [ ] Anti-spoof property tests (W1.6-SPOOF-PROPERTY-01) GREEN for all 3 spoof-fix handlers
- [ ] Newman cases (§6.5 W1.6-NM-01..17) GREEN
- [ ] **87 newman failures closed**: post-W1.6 baseline `iam-jit-pending(0)+iam-user(0)+iam-compliance-report(0)+iam-internal-only-check(0)+iam-access-binding(0)+authz-deny(0) = 1144/1144 GREEN`. Verify via `tests/newman/run.sh` summary + W0.1 coverage gate.
- [ ] `make e2e` smoke on dev-kind shows: anonymous can't list/get cross-tenant data; reviewer cannot be spoofed; SA-key creator stamped from principal; SAKey secret returned ONCE then redacted
- [ ] kacho-iam CI green (unit + integration + race)
- [ ] PR merged
- [ ] Vault обновлён:
  - [ ] `obsidian/kacho/KAC/KAC-164.md` — trail + PR + acceptance checklist
  - [ ] `obsidian/kacho/edges/iam-anti-anon-interceptor.md` — create new edge note (policy = explicit read-only allowlist + whitelist FullMethod)
  - [ ] `obsidian/kacho/resources/iam-operation.md` — note про redaction-post-first-read (#11)
  - [ ] `obsidian/kacho/resources/iam-access-binding.md` — Delete authority = grant-authority (mirror Create) (#13)
  - [ ] `obsidian/kacho/resources/iam-compliance-report.md` — Get/List scope-filtered (#37); create if missing
  - [ ] `obsidian/kacho/resources/iam-jit-pending.md` — Get/List caller-scoped (#36); create if missing
  - [ ] `obsidian/kacho/resources/iam-access-review.md` — reviewer from principal (#35); create if missing
  - [ ] `obsidian/kacho/resources/iam-sa-key.md` — created_by from principal (#53), secret redacted post-Issue (#11); create if missing
  - [ ] `obsidian/kacho/resources/iam-jit-eligibility.md` — CreatedBy from principal (#39)
  - [ ] `obsidian/kacho/packages/iam-authzguard.md` — note new `PrincipalUserID` helper + allowlist policy change
- [ ] YouTrack KAC-164:
  - [ ] In Progress on impl start
  - [ ] PR links commented
  - [ ] Done on merge + smoke + newman 1144/1144 verified
- [ ] W1 tracker `2026-05-23-iam-prod-ready-wave1.md` updated: W1.6 row → ✅ done + date; baseline metrics updated (newman 87→0)
- [ ] W1 closure note in master plan / W2 unblock signal

---

## 8. Open questions (DECISION-NEEDED) — нужно разрешить до старта impl

| ID | Вопрос | Рекомендация автора |
|---|---|---|
| **OQ-W1.6-1** | Anti-anon scope: `whitelistFullMethod` сейчас содержит регистрационные методы (`Account.RegisterMyself`, `Federation.Login`, etc). Какие именно RPC должны остаться в whitelist'е после перехода на read-only allowlist? | Сохранить минимальный набор: register-myself, federation login/callback, OIDC discovery, JWKS, health. Все остальные `Create*` — даже legitimate self-registration — фильтруются через explicit-allow. Полный список — review с acceptance-reviewer (extract из current whitelistFullMethod + проверить каждый). |
| **OQ-W1.6-2** | #11 redaction: добавить колонку `operations.response_redacted_at timestamptz` для audit (когда secret обнулён)? | **Не нужна для W1.6**. `jsonb_set` идемпотентен; повторный redact не меняет состояния. Если позже понадобится audit-trail когда именно секрет был выдан / редактирован → отдельный ticket. **Default — без миграции**. |
| **OQ-W1.6-3** | #35 strict body-validation: если `reviewer_user_id` в теле non-empty И не-равен principal — InvalidArgument (отказ) ИЛИ silent-override (молча заменить на principal)? | **InvalidArgument**. Silent-override маскирует client-bug (клиент думает, что отправил review от X, но прошло от Y). Жёсткий fail на mismatch заставит клиентов отправлять пустое поле / point правильный. Parity с update-mask discipline (CLAUDE.md preamble: «known fields → mutate; mismatch → InvalidArgument»). |
| **OQ-W1.6-4** | #37 VisibleScopeProvider — реализация в iam-service слое или delegate в gateway-authz через FGA Check? | **iam-service слое** (новый `compliance_visibility.go`). Reason: compliance_report — internal-only-check (KAC-127), gateway authz не на пути. iam уже имеет direct access к `access_bindings`/`projects`-данным; FGA Check добавит сетевой hop per-row. |
| **OQ-W1.6-5** | #40 SAML / #42 SCIM — реализовать verify в W1.6 (latent-P0) или guard ACS/SCIM endpoints (return 501)? | **Guard в W1.6** (501 / explicit-disabled с явным config-flag `iam.federation.saml.enabled=false` default). Real verify (XML-DSig + assertion validation) — W3. Latent-P0 не остаётся: endpoint возвращает 501, не ALLOW. **Уточнение scope: W1.6 brief не upstream'ит SAML/SCIM как Chunk-2 finding**; #40/#41/#42 — Chunk 5 (W3). Этот OQ — на случай если acceptance-reviewer хочет тактический guard добавить в W1.6 как defensive measure; recommendation — **отдельный мелкий ticket** parallel к W1.6 (одна-две строки в SAML/SCIM handler'ах: `return Unimplemented("SAML verify not yet implemented; see KAC-XXX")` если config-flag disabled). |
| **OQ-W1.6-6** | #36 cluster-admin bypass для `ListPending(AllScopes=true)`: как принципал помечен как cluster-admin? FGA Check на `cluster:default, relation=system_admin`? | **Да**. Существующий FGA path (`bootstrap_admin`-grant; KAC-163 W1.5 для BG.ApproveB). Helper `isClusterAdminCaller(ctx)` в jit_pending_service.go: lazy FGA Check. Кэшируется через gateway authz cache (W1.2). |
| **OQ-W1.6-7** | #43 readonly-suffixes list — нужны ли `Stream*` (server-streaming watches)? | Уже покрыто `Watch`. Дополнительно: если есть `<Resource>Stream` методы — добавить `Stream` в allowlist. Проверить proto'ы; на 2026-05-24 нет server-streaming watches в iam — пропускаем. |
| **OQ-W1.6-8** | Anti-anon — **closes 87 newman failures** — но каков формальный gate, что мы не сломали ALREADY-GREEN newman cases? | W0.1 coverage gate + diff `tests/newman/run.sh` summary до/после: новые GREEN ≥ 87 (sufficient); 0 регрессий из existing GREEN (necessary). Acceptance-reviewer обязан проверить diff и отказать при регрессиях. |
| **OQ-W1.6-9** | `PrincipalUserID` — должен ли он возвращать что-то для system-principal (`user:bootstrap`)? Без этого bootstrap-paths упадут на enforcement. | **Да**, возвращать `"bootstrap"` для system-type. Helper-policy: «principal-id-as-string для DB-storage / audit». bootstrap-principal — legitimate identity (initial seeds), audit-row `created_by="bootstrap"` — корректно. Если в DB FK на `users.id` есть — bootstrap должен иметь row там же (KAC-118 seed). |
| **OQ-W1.6-10** | Test format для anti-anon table-test (§6.2 W1.6-ANON-TABLE): reflection-based discovery vs hardcoded method list? | **Reflection-based** (preferred): future-proof against new RPCs added without updating allowlist. Catches forgotten-to-allowlist regression in **same PR** that adds the new RPC. Implementation: enumerate `grpcSrv.GetServiceInfo()` (Go gRPC API), pull all methods, run table-test. |

> **Ответы на OQ — за `acceptance-reviewer`.** OQ-W1.6-1/3/4/8/9 — критичны для public-API/integration теста shape; impl не стартует без явных ответов на них. OQ-W1.6-2/5/6/7/10 — implementation-detail, acceptance-reviewer может принять рекомендацию without re-debate.

---

## 9. Out of scope (явно — на следующие chunks)

| Что | Куда |
|---|---|
| Spec-drift KAC-119/121 (#1/#3/#4/#5/#6/#7/#14/#15/#27/#46/#55) | **W2 Chunk 4** |
| Gateway wiring + permission catalog (#19/#28/#29/#30/#31/#32/#33/#34/#38/#44/#45/#49) | **W2 Chunk 3** |
| Federation / SSO / AuthZ internals — SAML XML-DSig (#40), SCIM endpoints (#41/#42), MFA-fresh (#23), session-IP (#25/#26), OPA-VERIFY | **W3 Chunk 5** |
| Granular permission-relations в FGA model | W2 (after catalog unification) |
| API token rotation / JIT-revoke-on-rotation | W2 |
| Observability metrics за anti-anon denies / scope-filter misses | W3 |
| Cross-service authz-cache invalidation на binding `Update` (currently only Create/Delete invalidate) | W2 |

---

## 10. Traceability — finding-id ↔ scenario-id ↔ source-line

| Finding (rem. plan §1.3) | GWT Scenarios | Code-сайт (verified 2026-05-24) | Тест-имя |
|---|---|---|---|
| #9 (P0) | W1.6-09-HAPPY, W1.6-09-ANON-DENY, W1.6-09-OTHER-DENY, W1.6-09-CANCEL, NM-01, NM-02 | `internal/handler/operation_handler.go:49,62` | `Test_OperationHandler_Get_AnonymousDenied`, `..._OtherPrincipalDenied`, `Test_OperationHandler_Cancel_AnonymousDenied` |
| #11 (P0) | W1.6-11-REDACT, NM-03 | `internal/apps/kacho/api/sa_keys/usecases.go:191-199` | `Test_SAKey_Issue_RedactsSecretAfterFirstReturn` |
| #12 (P1) | W1.6-12-LISTBYSUBJECT-FOREIGN, W1.6-12-LISTBYRESOURCE-REGRESSION, NM-06, NM-07 | `internal/apps/kacho/api/access_binding/list_by_subject.go:31-36`; `list_by_resource.go:33-37` (already correct — regression test) | `Test_AB_ListBySubject_ForeignSubjectDenied`, `Test_AB_ListByResource_AuthorityMatrix` |
| #13 (P0) | W1.6-13-DELETE-BY-ADMIN, W1.6-13-DELETE-BY-STRANGER, NM-08, NM-09 | `internal/apps/kacho/api/access_binding/delete.go:78-80` | `Test_AB_Delete_AdminCanRevokeOthers`, `Test_AB_Delete_StrangerDenied` |
| #35 (P0) | W1.6-35-PRINCIPAL, W1.6-35-SPOOF, W1.6-SPOOF-PROPERTY-01, NM-10, NM-11 | `internal/apps/kacho/api/access_review/handler.go:51,93,134` | `Test_AccessReview_Decide_ReviewerFromPrincipal`, `Test_AccessReview_Decide_SpoofDenied` |
| #36 (P1) | W1.6-36-GET-FOREIGN, W1.6-36-LIST-SCOPED, NM-12, NM-13 | `internal/service/jit_pending_service.go:425-433` | `Test_JitPending_Get_NonParticipantNotFound`, `Test_JitPending_List_AutoScopedToCaller` |
| #37 (P0) | W1.6-37-FOREIGN, W1.6-37-LIST-SCOPED, W1.6-SCOPE-01, NM-14, NM-15 | `internal/apps/kacho/api/compliance_report/handler.go` + `cmd/kacho-iam/phase7b_wiring.go` + `internal/service/compliance_report_service.go:32-77` | `Test_ComplianceReport_Get_CrossTenantHidden`, `Test_ComplianceReport_List_ScopeFiltered`, `Test_VisibleScopeProvider_AdminAndAuditorAndViewer` |
| #39 (P0) | W1.6-39, W1.6-SPOOF-PROPERTY-01, NM-16 | `internal/apps/kacho/api/jit_eligibility/handler.go:75-100` (no CreatedBy set) + `internal/service/phase7_jit_service.go:137,171,194` | `Test_JITEligibility_Create_CreatedByFromPrincipal` |
| #43 (P0) | W1.6-43-APPROVE, W1.6-43-ISSUE, W1.6-43-READ-OK, W1.6-ANON-TABLE, NM-04, NM-05 | `internal/authzguard/interceptor.go:33-39,54-66` | `Test_AntiAnonymous_FullMethodEnumeration` (table-driven), `Test_AntiAnonymous_ReadOnlyAllowlist` |
| #53 (P0) | W1.6-53, W1.6-SPOOF-PROPERTY-01, NM-17 | `internal/apps/kacho/api/sa_keys/handler.go:41` | `Test_SAKey_Issue_CreatedByFromPrincipal`, `Test_SAKey_Issue_SpoofDenied` |

---

## 11. Ссылки

- Workspace правила: `../../CLAUDE.md` (запреты #1/#10/#11; vault discipline; security-sensitivity)
- IAM-specific: `../../project/kacho-iam/CLAUDE.md`
- Source of findings: `../superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` §1.3 Chunk 2
- Master plan: `../superpowers/plans/2026-05-23-iam-prod-ready-master.md`
- Wave 1 plan: `../superpowers/plans/2026-05-23-iam-prod-ready-wave1.md` §W1.6
- Predecessor acceptance docs:
  - `sub-phase-W1.4-principal-propagation-acceptance.md` (principal propagation primitive)
  - `sub-phase-W1.5-remediation-chunk1-fga-grant-write-acceptance.md` (grant→FGA atomic; required for NM-08 verification path)
- Vault entries to update (DoD):
  - `obsidian/kacho/edges/iam-anti-anon-interceptor.md` (NEW)
  - `obsidian/kacho/resources/iam-operation.md`
  - `obsidian/kacho/resources/iam-access-binding.md`
  - `obsidian/kacho/resources/iam-compliance-report.md` (NEW if missing)
  - `obsidian/kacho/resources/iam-jit-pending.md` (NEW if missing)
  - `obsidian/kacho/resources/iam-access-review.md` (NEW if missing)
  - `obsidian/kacho/resources/iam-sa-key.md` (NEW if missing)
  - `obsidian/kacho/resources/iam-jit-eligibility.md`
  - `obsidian/kacho/packages/iam-authzguard.md`
- Reference impl (parity for #13 authority-check): `internal/apps/kacho/api/access_binding/create.go::Execute` (requireGrantAuthority call site)
- Reference impl (parity for #43 interceptor pattern): `internal/authzguard/interceptor.go::AntiAnonymousUnary` (current shape — replace suffix-based)
