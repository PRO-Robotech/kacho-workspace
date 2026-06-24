---
title: "RBAC Contract-A fix — forward-materialize owner/creator access on iam-native content (flat FGA no-access-loss)"
ticket_id: rbac-2026-contract-a-fix
status: test
type: fix
repos:
  - kacho-iam
  - kacho-deploy
prs:
  - https://github.com/PRO-Robotech/kacho-iam/pull/228
  - https://github.com/PRO-Robotech/kacho-deploy/pull/122
opened: 2026-06-24
tags:
  - kac
  - kacho-iam
  - kacho-deploy
  - fix
  - domain
  - usecase
  - repo
  - migrations
---

# RBAC Contract-A fix — iam-native content forward-materialization

**Status**: test (iam branch `rbac-contract-a-fix` → PR #228; deploy PR #122 pins `REF_IAM`)
**Type**: fix — Contract-A no-access-loss BLOCKER (continues [[rbac-2026-224-owner-wildcard-content]])
**Acceptance**: `docs/specs/rbac-explicit-model-2026-acceptance.md` — D-4 / D-8a / C-01b (forward-materialization), D-5 (flat model), D-7/D-9

## Класс потери (из artifact run 28081766667, kacho-deploy)

11 umbrella newman suites red on the flat model: iam-project, iam-group, iam-role, iam-user,
iam-service-account, iam-access-binding, iam-rbac-subjects, iam-authz-grant-check-propagation,
authz-deny, label-revoke-vpc, label-revoke-compute. Symptom: `get-confirms` → `expected 403 to
deeply equal 200` right after Create; deny `lacks relation "viewer/editor" on iam_*:...; no
direct relations granted`. (sec-c-fga-proxy 9/9 + label-revoke-nlb were pre-existing known-RED,
whitelisted in `assert-suites-green.sh` via `^SEC-C-A-` / `^T31-LBLREVOKE-NLB-` — NOT regression.)

## Первопричина

Flat model (Contract-A, proto#85, proto main `256383c`) removed `<rel> from account|project|
cluster` ACCESS cascades on iam leaf types. Per-object materialization replaces the cascade for
vpc/compute/nlb content via RegisterResource → resource_mirror → resource_reconcile_outbox →
ReconcileObject. But kacho-iam's OWN content Creates emitted ONLY the now-inert hierarchy
parent-pointer (`account:<acc>#account@iam_role:<id>`) and NO reconcile trigger → account-owner
`*.*` binding never re-evaluated against new iam content → creator/owner held no relation → 403.
Additionally `domain.AllMaterializableTypes()` excluded iam.role/group/serviceAccount/user/
accessBinding. The .proto model was NOT the problem — it carries every needed relation; the
task hypothesis "re-add a removed relation" was refuted.

## Фикс (forward, model untouched)

- reconcile-event emit (`mirror.upsert`) co-committed in the writer-tx on each iam-native content
  Create (role/group/serviceAccount/user/project/accessBinding) — reuses `writeTx.EmitReconcileEvent`.
- split `AllMaterializableTypes()` (`*.*` expansion) from `labelSelectableTypes` (O-4 feed-gate,
  unchanged): new `iamContentMaterializableTypes` = the 5 iam content types (ANCHOR/NAMES, NOT labels).
- extend iam-direct pg scans + `IAMDirectSelectorBindingsMatchingObject` (arm='anchor' match within
  scope; containment re-asserted by use-case) to the iam content tables.
- migration 0039: re-seed owner role `role_rule_selectors` anchor row → 21-type object_types
  (idempotent UPSERT, rule_fp unchanged).
- fixed stale "<rel> from account cascade resolves" comments.

## #193 test fallout (flat-model) — re-anchored на per-object, НЕ revert каскада

Снятие каскада вскрыло 2 детерминированно-красных integration-теста (объявлены #229 как
"pre-existing flakiness, unrelated" — ни flaky, ни unrelated):
`TestIntegration_ListObjects_Role_OwnerViewerCascade_193` и `..._ViewerReadEnforce_193`
(`internal/apps/kacho/api/access_binding/list_objects_role_owner_fga_integration_test.go`).
Ассертили viewer-КАСКАД на роль через `viewer from account` (account-tier admin-tuple →
`ListObjects(viewer, iam_role)` содержит own role). Flat убрал каскад by-design →
`ListObjects(viewer)` пуст → RED (подтверждено на main: `[]string{} does not contain rol_owner_193`).

Фикс = per-object материализация (НЕ revert каскада): setup теперь пишет ровно тот tuple-set,
что reconciler материализует для owner `*.*` ARM_ANCHOR над iam.role (tier `admin`
admin→editor→viewer + закрытые v_* verb-relations — выход `reconcile.ruleObjectTuples`), а НЕ
inert account-hierarchy-pointer. Суть сохранена: owner видит свою роль (viewer через admin-tier
+ v_list direct per-object); no-leak (чужой owner — ни viewer, ни v_list); read==enforce parity.
RED на main → GREEN на ветке (real OpenFGA testcontainers, flat fga_model.fga). Также исправлен
stale-комментарий в `account/create.go` (введён #229) про `viewer/editor from account` cascade на
owner-binding-OBJECT: под flat доступ к owner-binding-объекту идёт через post-commit
ReconcileBinding (owner `*.*` ARM_ANCHOR над iam.accessBinding, iam-direct scan access_bindings в
scope). Без behaviour change.

**Доставка:** ветка `rbac-contract-a-fix` (PR #228) перебазирована на main (`86faefc`, несёт #229)
без конфликтов; поверх — commit `test(iam): re-anchor #193 ...`. PR #228 = [forward-mat, gofmt,
#193 re-anchor] на main.

## Затронутые сущности vault

[[iam-access-binding-service]] · [[iam-role-service]] · owner-binding reconciler (D-8a) ·
[[compute-to-iam-fgaproxy]] (the RegisterResource→reconcile pattern mirrored for iam-native content)

## Валидация

go build / go vet ./... clean; unit tests green; new `reconcile_owner_iam_content_integration_test.go`
(forward + backfill + scope-boundary + access-binding-forward) GREEN; full
`internal/repo/kacho/pg` integration suite GREEN (196s). Main gate: deploy PR #122 umbrella
newman with `REF_IAM=rbac-contract-a-fix`.

## DoD

- [x] diagnosis from artifact (exact class + root cause)
- [x] forward fix in iam (trigger + materializable set + iam-direct scans + mig 0039)
- [x] TDD integration tests GREEN
- [x] iam PR #228 + deploy PR #122 REF_IAM pin
- [ ] umbrella newman green (owner re-checks) → merge iam#228 then deploy#122
- [ ] revert REF_IAM to main after iam#228 merges
