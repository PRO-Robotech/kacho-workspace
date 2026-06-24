---
title: "RBAC Contract-A flat — bootstrap signup owner-binding fallout (ROOT flat-403)"
ticket_id: rbac-2026-contract-a-flat-fallout
status: test
type: fix
repos:
  - kacho-iam
  - kacho-deploy
prs:
  - https://github.com/PRO-Robotech/kacho-iam/pull/230
  - https://github.com/PRO-Robotech/kacho-deploy/pull/122
opened: 2026-06-24
tags:
  - kac
  - kacho-iam
  - fix
  - domain
  - usecase
  - repo
---

# RBAC Contract-A flat — bootstrap signup owner-binding fallout

**Status**: test (iam branch `rbac-contract-a-flat-fallout` → PR #230; deploy PR #122 flat-configmap pin)
**Type**: fix — ROOT of remaining flat-403 (~90%); continues [[rbac-2026-contract-a-fix-iam-content-forward]] / [[rbac-2026-224-owner-wildcard-content]]
**Acceptance**: `docs/specs/rbac-explicit-model-2026-acceptance.md` — D-4 / D-8a / C-01 / C-01b
**Commit**: `685b1ad`

## Первопричина (ОДИН механизм, ~90% остаточных flat-403)

`bootstrapPersonalResources` (`internal/apps/kacho/api/user/internal_upsert.go`) — LIVE signup /
Kratos-provision путь И activated-invitee owns-zero путь — был рассинхронизирован с
Account.Create owner-путём (`account/create.go doCreate`) под flat-моделью:

1. создавал account-scoped self-binding с **admin**-ролью (`rol21232f297a57a5a74`), не **owner**
   (`OwnerRoleID rol72122…`) → `ownerBindingFor` / owner `*.*` forward-mat движок его НЕ видел;
2. эмитил только хардкод `bootstrapTuples` (tier + hierarchy pointers), НИ ОДНОГО per-object
   content-tuple;
3. НЕ вызывал `ReconcileBinding` (use-case не имел reconciler-поля).

Под flat hierarchy-pointer'ы доступа не дают → bootstrap-юзер 403 на content своего аккаунта
(project / access_binding / group / cross-service). Класс-3 (get-self) — отдельная D-4-дыра: self-tuple
`iam_user:<U>#subject@user:<U>` нигде в проде не эмитился (модель `iam_user.viewer = subject or editor`).

## Фикс (parity с account/create.go; переиспользует owner forward-mat движок + индекс 0038/0039)

- bootstrap account-scoped binding → **owner**-binding (OwnerRoleID, scope=ACCOUNT,
  deletion_protection, Subjects, OWNER-BINDING ledger, grant-audit) — co-commit в bootstrap writer-tx (ban #10);
- post-commit `ReconcileBinding(ownerBindingID)` → scope-self verbs на `account:<A>` + owner `*.*`
  ARM_ANCHOR forward над содержимым (default project, iam-native, cross-service mirror);
- reconciler прокинут в ОБА composition root — gRPC InternalUserService (`wiring.go`) И
  Kratos provision-hook (`hooks_mux.go`, LIVE signup путь);
- self-tuple `iam_user:<U>#subject@user:<U>` эмитится в `bootstrapTuples` (D-4 get-self);
- дроп redundant `admin@account` bootstrap-tuple (tier материализует owner-binding reconcile — D-4 single path).

Activated-invitee bootstrap переиспользует ту же функцию; `invite.go doInvite` уже forward-mat'ит
свежеприглашённого user + project AB через reconcile-events.

## TDD (testcontainers) RED→GREEN

`internal/repo/kacho/pg/bootstrap_owner_mat_integration_test.go` гоняет РЕАЛЬНЫЙ UpsertFromIdentity
use-case wired с reconciler. **RED** (5/5 fail на pre-fix: admin-binding, нет owner-binding, нет
content-tuples, нет self-tuple — диагностированный flat-403). **GREEN** после фикса:
owner-binding shape; per-object owner mat на project (`project:<id>` admin+v_get) / own
access_binding / cross-service network; self-tuple emit.
**Регрессия GREEN**: Account.Create owner-path, upsert/invite (T-I3/T-I5/T-E4), owner-iam-content,
#224 owner-wildcard, review1 dual-member ledger, emitted-tuples.

## Затронутые сущности vault

[[iam-user]] · [[iam-access-binding]] · [[iam-account]] · [[rbac-2026-contract-a-fix-iam-content-forward]] · [[rbac-2026-224-owner-wildcard-content]]
edge: [[api-gateway-to-iam-authorize]] (signup провижн → bootstrap)

## DoD

- [x] owner-binding + ReconcileBinding в bootstrap (оба composition root)
- [x] self-tuple emit (get-self)
- [x] integration RED→GREEN + регрессия
- [x] go build / vet / gofmt / golangci-lint (CI) / govulncheck (CI) зелёные
- [ ] flat-newman forward-mat-класс зелёный (CI #230 in-flight)
- [ ] coordinated merge с kacho-deploy#122 (revert flat-pin → main после deploy#122)
