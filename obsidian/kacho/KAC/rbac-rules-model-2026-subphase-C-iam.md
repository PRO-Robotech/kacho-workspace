---
title: RBAC rules-model 2026 — sub-phase C (iam)
ticket_id: gh-kacho-iam-189
status: test
type: feature
repos:
  - kacho-iam
prs: []
yt_url: https://github.com/PRO-Robotech/kacho-iam/issues/189
opened: 2026-06-21
tags:
  - kac
  - kacho-iam
  - feature
  - domain
  - migrations
  - usecase
  - repo
---

# RBAC rules-model 2026 — sub-phase C (iam)

**Status**: test (code-complete on branch `rbac-rules-c-iam`, not committed)
**Type**: feature (epic «RBAC rules-model 2026», sub-phase C — ARM_LABELS materialization)
**Repos**: kacho-iam (this); no proto/FGA-model change (scope_grant + v_* already from B)
**Issue**: PRO-Robotech/kacho-iam#189
**Acceptance**: `docs/specs/rbac-rules-model-2026-acceptance.md` (APPROVED раунд 2) — C-20..C-26, design §5/§7

## Что и зачем

Sub-phase B suppressed ARM_LABELS (`case ArmLabels: continue` in `scope_grant_tuples.go`).
C **materializes** it: the AccessBinding reconciler (epic-103/γ) is re-pointed from
`binding.selector` (legacy) to **`role.rules` ARM_LABELS selectors**. A thin all_in_scope
binding carrying a rules-role with matchLabels rules → reconciler matches each rule against
`resource_mirror` (+ iam-direct project/account) → per-object FGA tuples on matched-and-
contained objects, reusing the B per-verb (`v_*`) + tier emit semantics. NO broad anchor
(fix #8). Membership keyed by **rule_fp (content-hash)**, not positional index (mutable rules).

## Сделано (C)

- **domain** (`rule_fingerprint.go`, `rule_verbs.go`): `Rule.Fingerprint()` (order-stable
  sha256 content-hash = rule_fp), `Rules.LabelSelectors()` (→ per-rule `RuleLabelSelector{fp,
  types, matchLabels, verbs}`), `LegacySelectorFP` sentinel, `ResolveVerbsAndTier`/`IsClosedVerb`
  (shared per-rule verb→tier, mirrors B's private helpers). `TargetMember` += `RoleID, RuleFP`.
- **migrations** (new ≥0026): `0026_role_rule_selectors.sql` (`role_rule_selectors(role_id,
  rule_fp, object_types[], match_labels) PK(role_id,rule_fp)` FK CASCADE + GIN); `0027_target_
  members_rule_rekey.sql` (ALTER `access_binding_target_members` ADD role_id,rule_fp; backfill
  legacy rows → `legacy-selector` sentinel; PK → `(binding_id,role_id,rule_fp,object_type,object_id)`).
- **reconciler** (`reconcile/reconcile.go`,`tuples.go`): `BindingScope.LabelSelectors`+`RoleID`;
  `desiredRuleMembers` (per ARM_LABELS rule: match feed → IsContainedIn → ACTIVE/REJECTED +
  per-object tuples from rule verbs via `ruleObjectTuples`); `applyDiff` keyed by `(rule_fp,
  object)`; fell-out/removed-rule revoke via the **saved ledger** (`LedgerTuplesForObject`),
  not re-derive (C-20/C-21). Legacy selector/byName arms stamp `LegacySelectorFP` — coexist.
- **adapter** (`reconcile_adapter.go`, `target_members/store.go`): LoadBinding loads
  `role.Rules.LabelSelectors()`; member CRUD rule-aware; `SelectorBindingsMatchingObject` +
  `ListSelectorBindingIDs` UNION the `role_rule_selectors` fast-path/sweep; new `LedgerTuplesForObject`.
- **role Create/Update** (`role/create.go`,`update.go`,`role_repo.go`): `ReplaceRuleSelectors`
  syncs `role_rule_selectors` with the role's ARM_LABELS rules in the writer-tx (ban #10).
  Role.Update rules-change → post-commit membership fan-out over ACTIVE bindings
  (`RoleMembershipFanout`), bounded ≤10000 (`MaxRoleFanoutBindings`, C-21) — over-limit →
  sync FAILED_PRECONDITION "too many bindings…split role". Create triggers reconcile for
  rules-role bindings (thin all_in_scope) too.

## Затронутые сущности vault

- [[../resources/iam-access-binding]] — reconciler rekey (rule_fp), role.rules-driven membership, ledger revoke
- [[../resources/iam-role]] — role_rule_selectors sync, Role.Update fan-out + 10000 bound
- [[rbac-rules-model-2026-subphase-A-iam]] — predecessor (compile/validate); [[rbac-rules-model-2026-subphase-B-iam]] — emit

## RED → GREEN proof

- **domain unit** (`rule_fingerprint_test.go`): RED `Fingerprint`/`LabelSelectors` undefined → GREEN.
- **reconcile unit** (`reconcile_rules_test.go`, mock store): RED `BindingScope.LabelSelectors`/
  `TargetMember.RuleFP` undefined → GREEN (C-22 per-object no anchor; containment REJECTED; C-21 eager-revoke by rule_fp).
- **migration integration** (`migration_0026_0027_…`, testcontainers, NOT -short): RED 42P01
  `role_rule_selectors does not exist` → GREEN (table+FK CASCADE+PK; member 5-tuple PK).
- **reconcile integration** (`reconcile_rules_integration_test.go`): C-20/C-21 (rule removed →
  no residual + ledger empty), C-22 (per-object, later-label flip materializes), C-23 (expiry
  eager-revoke), C-24 (foreign scope REJECTED+audit), C-25 (containment re-verify no injection),
  C-26 (concurrent reconcile idempotent, one member row).
- **FGA Check (real OpenFGA)** (`TestIntegration_ScopeGrant_C22_MatchLabels_PerObjectCheck`):
  matched object allow (v_get/v_create), non-matched + foreign type + ungranted verb deny.
- **fan-out bound unit** (`role_fanout_bound_test.go`): >10000 → FAILED_PRECONDITION, no fan-out;
  within-bound runs.
- **newman** (`iam-rbac-rules-labels.py`): matchLabels on fed type accepted; non-fed (iam.role)
  feed-gate rejected. (matched-object Check is cross-repo e2e — RegisterResource is internal-only.)

## DoD

- [x] migrations 0026/0027 (role_rule_selectors + member rekey + backfill)
- [x] domain rule_fp + label selectors + shared verb/tier
- [x] reconciler role.rules-driven + adapter + ledger revoke
- [x] role Create/Update selector-sync + Role.Update fan-out (bounded 10000)
- [x] RED→GREEN unit + integration (-p 1, non-short, colima) + newman gen
- [x] no proto/FGA-model change (scope_grant/v_* already from B)
- [ ] commit/push (НЕ делалось по инструкции)
- [ ] reviews: db-architect (rekey migration), system-design (reconciler redrive/OCC/fan-out), go-style

## Остаточные риски / follow-up

- **Legacy `binding.selector` reconcile COEXISTS** (design §7 INERT window): legacy γ bindings keep
  the `access_binding_selector` path (sentinel `legacy-selector` rule_fp); role.rules path is a
  parallel feed. Full migration of legacy γ bindings to role.rules = sub-phase F (re-author).
- **condition (C-23) conditional-tuple-on-emit not wired**: NON_EXPIRED enforced via the D9
  expiry eager-revoke (tuple removed). Request-context time/IP/MFA conditional-tuples on the
  grant-emit path don't exist in ANY sub-phase (B emits plain tuples) — follow-up if needed.
- **Fan-out is post-commit synchronous loop** (not `resource_reconcile_outbox` async-drain as
  design §339 sketches) — deterministic + bounded ≤10000; outbox-drained fan-out is a scale follow-up.

#kac #kacho-iam #feature
