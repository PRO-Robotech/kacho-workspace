---
title: "IAM operations visibility (sub-phase 1.2)"
aliases:
  - sub-phase-1.2-iam-operations
  - iam-operations-visibility
ticket_id: "(none — sub-phase acceptance doc)"
category: kac
status: done
type: feature
repos:
  - kacho-proto
  - kacho-corelib
  - kacho-iam
  - kacho-api-gateway
  - kacho-ui
tags:
  - kac
  - feature
  - kacho-iam
  - kacho-ui
  - kacho-api-gateway
  - kacho-corelib
---

# IAM operations visibility (sub-phase 1.2)

> [!note] Трек без KAC-номера
> Работа ведётся по acceptance-доку `docs/specs/sub-phase-1.2-iam-operations-acceptance.md` (✅ APPROVED rev 5), YouTrack-тикет не заводился.

**Status**: ✅ done — merged на `main` + live на внешнем кластере `fe3455` (helm **rev14**, 2026-06-18; включает backfill 0017).
**Type**: feature
**Repos / PRs**: kacho-proto (merged), kacho-corelib [#24](https://github.com/PRO-Robotech/kacho-corelib/pull/24), kacho-iam [#160](https://github.com/PRO-Robotech/kacho-iam/pull/160), kacho-api-gateway [#85](https://github.com/PRO-Robotech/kacho-api-gateway/pull/85), kacho-ui [#81](https://github.com/PRO-Robotech/kacho-ui/pull/81). **Backfill**: kacho-iam [#162](https://github.com/PRO-Robotech/kacho-iam/pull/162) (migration 0017).

## Что и зачем

Заказчик: «у iam модуля при создании ресурсов нету operations». Две дыры:
1. Per-resource `ListOperations` отсутствовал для **User** и **AccessBinding** (был у Account/Project/SA/Group/Role) → UI таб «Операции» бил в 404.
2. Не было module-level «все операции account» и cluster-wide admin-фида.

## Сделано

- **proto** (`kacho.cloud.iam.v1`): `account_id`-денормализация на ~14 category-(I) metadata; RPC `UserService.ListOperations`, `AccessBindingService.ListOperations`, `AccountService.ListAllOperations` (`GET .../accounts/{account_id}/operations:all`), `InternalOperationsService.ListIamOperations` (cluster-wide, internal-only :9091, `GET /iam/v1/internal/operations`). Per-resource: `GET .../users/{user_id}/operations`, `GET .../accessBindings/{access_binding_id}/operations`.
- **corelib #24**: `CreateWithPrincipal` штампует `account_id` (`extractAccountID`) + `ListFilter.AccountID` + partial cursor index; `migrations/common/0003`.
- **iam #160**: 4 RPC-handler'а + `account_id`-стамп category-(I) + migration `0016` (additive nullable + partial index) + `InternalOperationsService` (`requireClusterSystemAdmin`) + by-design doc `operations-visibility-privacy.md` (D-12 per-scope-viewer).
- **api-gateway #85**: public RPC в allowlist+routes; `InternalOperationsService` только internal-mux (ban #6).
- **ui #81**: таб «Операции» на 7 IAM-деталях; module `/iam/operations` (`ListAllOperations`); admin `/system/operations` (`InternalOperationsService`).
- **iam #162 — backfill `0017`**: `0016` добавил `account_id` nullable, но pre-1.2 строки остались NULL → account-scoped `/iam/operations` отдавал пусто. `0017_backfill_operations_account_id` бэкфилит, джойня заполненный `resource_id` к owning-ресурсу: account ops → self; project/group/service_account/user → `resource.account_id`. **Category-II** (`access_binding`/`role`) остаются NULL. Verified live `fe3455` rev14: 50 ops, `account_id` 0→39 → исторические данные `/iam/operations` теперь видны. (Тот же PR #162 несёт 1.3b group privileges — см. [[sub-phase-1.3-subject-privileges]].)

## Затронутые сущности vault

[[../rpc/iam-user-service]] [[../rpc/iam-access-binding-service]] [[../rpc/iam-account-service]] [[../rpc/iam-internal-operations-service]] [[../packages/corelib-operations]] [[../resources/operation]] [[../resources/iam-account]]

## DoD

- [x] proto + corelib #24 + iam #160 (4 RPC RED→GREEN, migration 0016, privacy doc) merged
- [x] api-gateway #85 (allowlist+routes, internal mux, `external_isolation_test`) + ui #81 merged
- [x] iam #162 backfill `0017` — pre-1.2 `account_id` заполнен (0→39 live), `/iam/operations` исторические видны
- [x] всё на `main` + live `fe3455` rev14; vault обновлён

## Инцидент 42703 (merge-order)

corelib #24 дал **безусловный** `account_id`-INSERT и смержен **раньше** consumer-миграций → `42703` на КАЖДОМ operations-INSERT fleet-wide (iam/vpc/compute/nlb владеют своей operations-DDL, corelib `migrations/common` не применяют). Замаскировалось под bootstrap-flake. Фикс: iam `0016` + vpc `0009` + compute `0012` + nlb `0003`. Детали — [[../packages/corelib-operations]] / [[sub-phase-1.4-tuple-resource-guarantee]].

## Связанные тикеты

- [[sub-phase-1.3-subject-privileges]] — привилегии-таб (та же IAM-эпопея)
- [[sub-phase-1.4-tuple-resource-guarantee]] — 100% tuple↔resource (та же фаза, S0–S3)
- [[iam-ui-vpc-parity]] — UI registry-движок IAM (поверхность тех же ресурсов)

#kac #feature #kacho-iam #kacho-ui #kacho-api-gateway #kacho-corelib
