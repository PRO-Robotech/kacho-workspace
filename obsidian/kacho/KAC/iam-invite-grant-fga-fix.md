---
title: IAM invite/grant FGA — anchor-grant emits 0 + invite-activation no member-tuple + every-user default account
ticket_id: iam-invite-grant-fga-fix
status: in-progress
type: fix
repos:
  - kacho-iam
prs: []
yt_url: ""
opened: 2026-06-23
tags:
  - kac
  - kacho-iam
  - fix
  - authz
  - usecase
  - race-fix
---

# IAM invite/grant FGA fix (anchor-grant + invite-activation + every-user default account)

**Status**: **in-progress** (code-complete on branch `fix-invite-grant-fga`, awaiting role-reviews + merge). Acceptance `docs/specs/iam-anchor-grant-and-invite-activation-fga-acceptance.md` (✅ APPROVED round 2). Single-repo **kacho-iam** (no proto/gateway/migration). Strict TDD RED→GREEN done.

> [!warning] T-I4 / D-R3 acceptance discrepancy (flag for `acceptance-reviewer` re-review)
> Against the REAL canonical `fga_model.fga`, `vpc_network.viewer` = `… or viewer from project …`, so the RC-1 concrete `project:P#viewer@subj` tuple **does** cascade `viewer` onto in-scope children of P — **by model design**, identical to ARM_NAMES and the legacy permissions path. The acceptance T-I4/D-R3 assertion «concrete project-tier does NOT cascade to sibling vpc/compute» is factually wrong (it conflates the #177 scope_grant-CARRIER over-cascade with the model's intrinsic `viewer from project` edge). `system-design-reviewer` confirmed (CRIT-1/CRIT-2): RC-1 code is correct; the genuine #177-guard RC-1 preserves is G1 (no `sg_*` carrier on tier-only) + G2 (no `v_*`) + G3 (in-scope cascade by-design True) + G4 (scope containment — no leak to sibling project P2 / account A2). The T-I4 integration test was reframed to assert G1–G4 (GREEN against real model). D-R3 §39 + T-I4 §162-165 of the acceptance need correcting via acceptance-reviewer re-approval.

## Что и зачем (live-диагностика на fe3455 + Workflow-синтез)

Симптом (владелец): приглашённый+зарегистрированный юзер `we@dobry-kot.ru` не видит ни своего base-аккаунта/проекта, ни выданного через кастом-роль «test» доступа к проекту/аккаунту. Live: у нового юзера **0 FGA-tuple**, AccessBinding (роль test на project) эмитнул субъекту **ничего**.

### Root causes (подтверждены по исходникам)
- **RC-1** `access_binding/scope_grant_tuples.go:159-161` — ARM_ANCHOR-правило на **tier-only тип** (`iam.account`/`iam.project`, не в `authzmap.verbBearingTypes`) попадает в `if !TypeHasVerbRelations(objType){continue}` → **0 tuple субъекту** (silent zero-grant). Фикс: в `emitAnchorRule` при `objType==anchorType` ∈ tier-only эмитить concrete-object tier-tuple `{subject, tier, anchorType:anchorID}` (форма из `emitNamesRule`, #177-safe); mismatched tier-type → keep SKIP (wrong-direction, нет `from project` на account).
- **RC-2** `user/internal_upsert.go:204-232` — активация invite коммитит только `ActivateInvite`+audit, **без** member-hierarchy-tuple. Фикс: `w.EmitFGARelationWrite(ctx,[{User:"account:<A>",Relation:"account",Object:"iam_user:<id>"}])` в Step-1 writer-tx (НЕ `relationhook.WriteHierarchyTuple` — он post-commit best-effort, ban #10).
- **RC-5** (owner-mandated) — **каждый** юзер, включая приглашённого, получает персональный default Account + «default» Project. Gate `internal_upsert.go:257` `!activatedAny && len(existing)==0` → предикат «owns zero accounts» (новый reader над `accounts.owner_user_id`). Нюанс: invitee-row уже существует → bootstrap НЕ делает повторный `InsertActive` (иначе 23505 на UNIQUE external_id) — только Account/Project/AB/tuples для существующего id. Итог: owner@personal **И** member@inviter сосуществуют.
- **RC-4** (deploy follow-up, не код) — на fe3455 stale FGA-model-ревизия (`viewer from cluster`→`user:*`) → ложный `Check(viewer)=True` при 0 tuple. Текущая `fga_model.fga` уже `system_viewer from cluster` (non-wildcard). Нужен re-bootstrap модели + drift-gate.

## Тесты (TDD, в тех же PR — ban #12)
- integration T-I1 (emitAnchorRule 0→tuple, no dangling/over-cascade), T-I2 (Create→outbox→Check/ListObjects), T-I3 (activation in-tx member-tuple atomically with audit), T-I4 (#177 guard: viewer on project НЕ даёт child vpc_network, Check+ListObjects), T-I5 (activation+bootstrap consistency, 23505-guard RED-first, 1 owned account) + owner-count reader test.
- newman T-E1 (invite→activate→grant→invitee видит P+A И имеет свой default account+project), T-E2 (scope containment), T-E3 (ARM_NAMES parity), T-E4 (idempotent re-activate).

## Затронутые сущности vault
- [[iam-access-binding]] — anchor-grant emission на tier-only (RC-1).
- [[iam-user-service]] / [[iam-internal-iam-service]] — UpsertFromIdentity invite-activation (RC-2) + every-user bootstrap (RC-5).
- [[iam-account]] / [[iam-project]] — каждый юзер получает свой default (RC-5); viewer-grant на anchor (RC-1).

## DoD
- [x] APPROVED acceptance (round 2).
- [x] RC-1 + RC-2 + RC-5 реализованы (kacho-iam), TDD RED→GREEN (branch `fix-invite-grant-fga`).
  - RC-1: `emitAnchorRule` tier-only `objType==anchorType` → concrete tier-tuple; mismatched → SKIP. Unit T-I1 RED(0 tuples)→GREEN.
  - RC-2: `EmitFGARelationWrite` member-tuple co-commit in Step-1 writer-tx. Integration T-I3 RED(0 member intents)→GREEN.
  - RC-5: gate → owns-zero-accounts (new `CountAccountsByOwner` reader over `accounts.owner_user_id`); bootstrap for existing activated user-id WITHOUT 2nd `InsertActive`. Integration T-I5 RED(0 owned)→GREEN.
- [x] integration green: T-I1 (unit), T-I2/T-I4 (real OpenFGA model semantics, G1–G4 guard), T-I3/T-I5/T-E4-int (Postgres outbox/bootstrap), CountAccountsByOwner reader test, pg user/account subset (`ok 269.6s`). `go build`/`go vet`/`gofmt`/golangci-lint(changed files) clean.
- [x] regression sweep: full access_binding suite caught one stale FGA-integration test (`...I1_AccountAnchorSkipped`) asserting the pre-RC-1 SKIP contract for the account-anchor twin → renamed `_AccountAnchorMatchingScope` + updated to RC-1 contract (commit `5691dcb`); both renamed FGA tests GREEN.
- [x] newman T-E1..T-E4 authored (`tests/newman/cases/iam-invite-grant-fga.py`, gen.py OK, 5 cases) — RED-against-stale-stand per RC-4 (need re-bootstrap before live-green, acceptance §RC-4 / ban #13).
- [x] system-design review (RC-1 #177-cascade): RC-1 correct; T-I4/D-R3 acceptance error flagged (see warning above).
- [ ] db-architect review (Step-1 co-commit `fga_outbox`+`audit_outbox`; CountAccountsByOwner reader; no-2nd-InsertActive 23505-guard) + go-style review.
- [ ] acceptance-reviewer re-review of D-R3/T-I4 wording (model-cascade correction).
- [ ] merge → redeploy fe3455 + **RC-4 re-bootstrap FGA-модели** + drift-gate.
- [ ] live-verify (OpenFGA Check + emission; invitee sees granted P/A + own default account/project).

#kac #kacho-iam #fix #authz #usecase #race-fix
