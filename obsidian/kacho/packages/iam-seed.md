---
title: "iam internal/apps/kacho/seed"
aliases:
  - iam seed
  - iam-seed
  - bootstrap admin
  - permissions registry
category: packages
path: services/iam/internal/apps/kacho/seed
repo: kacho-iam
layer: app
status: done
related_tickets:
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-iam
  - bootstrap
verified_against: "состав каталога `embedded/` сверен с деревом продукта 1653387b (2026-08-06); поток bootstrap-админа и перечень permissions построчно не пересматривались"
---

# iam `internal/apps/kacho/seed`

Startup-time bootstrap пакет: permissions registry + cluster admin seed. Запускается из composition root `cmd/kacho-iam/main.go` ДО RPC serving.

## Files

- **`bootstrap_admin.go`** — startup-time bootstrap admin grant + fga_outbox enqueue.
- **`permissions.go`** — generated permissions registry (`<module>.<resource>.<verb>` enumeration from proto annotations).
- **`embedded/`** — ровно **один** отслеживаемый файл:
  `services/iam/internal/apps/kacho/seed/embedded/permission_catalog.json`,
  вшиваемый директивой `go:embed` из `permissions.go`. Это **генерируемый** каталог
  прав, и у него есть вторая embedded-копия на крае
  (`gateway/internal/middleware/embed/permission_catalog.json`); байт-идентичность
  двух копий и их свежесть относительно proto стережёт цель `permission-catalog-check`
  в `gateway/Makefile`.

> [!note] Прежние два имени входов Phase 1 — координаты сняты (1653387b, 2026-08-06)
> Ни одного из них в каталоге нет; здесь они намеренно не воспроизводятся в обратных
> кавычках, иначе разбор снова читался бы как живое утверждение о дереве. Предмет
> разошёлся по двум разным местам: перечень прав — это тот самый каталог выше (имя
> другое), а **системные роли вообще не сеются из встроенного JSON** — их содержимое
> задаётся и правится миграциями (`0031_reseed_system_roles_rules.sql`,
> `0053_system_role_rule_selectors.sql`, `0057_storage_sa_least_priv.sql`,
> `0060_storage_system_role_selectors.sql` и соседние), а backfill живёт в
> `services/iam/internal/apps/kacho/seed/migrate_backfill.go`.

## Bootstrap admin flow (`bootstrap_admin.go`)

Acceptance §2.8 + §6.10 (Scenarios 6.10.1-6.10.5).

Input: `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL` env.

```
1. email empty → skip (no-op, log DEBUG).
2. Lookup user by email.
3. NOT found → log INFO + idempotent retry on next boot.
4. Found → atomic TX:
   INSERT cluster_admin_grant (subject=user, granted_by='bootstrap')
   INSERT fga_outbox (event_type='fga.tuple.write', payload={tuple})
   INSERT audit_outbox (event_type='iam.cluster_admin.granted', payload={...})
5. SQLSTATE 23505 (partial UNIQUE на cluster_admin_grants_subject_unique) → graceful WARN
   (concurrent HA cold-start; винёр уже создал grant per Scenario 6.10.5).
6. Other errors → return — fail-closed для unknown DB-state.
```

**HA-race-safety**: 23505 → graceful skip (acceptance §6.10.5). Idempotent re-run: 23505 → graceful skip (parity).

## Exported API

- `BootstrapAdminInput{Email, ClusterID, NowFn}` — параметры запуска.
- `BootstrapAdminResult{Skipped, SkipReason, GrantID, FGAOutboxID, ...}` — итог.
- `BootstrapAdmin(ctx, pool, in) (*BootstrapAdminResult, error)` — main entrypoint.

## Permissions registry (`permissions.go`)

Перечисление всех `<module>.<resource>.<verb>` permissions из proto-annotations (Phase 1 generated):
- `iam.accounts.read|write|delete|list`
- `iam.projects.read|write|delete|list`
- `iam.users.read|write|delete|list|invite`
- `iam.service_accounts.read|write|delete|list|create_oauth_client`
- `iam.groups.read|write|delete|list`
- `iam.roles.read|write|delete|list`
- `iam.access_bindings.read|write|delete|list|activate_jit`
- `iam.cluster_admin.grant|revoke|read`
- `iam.break_glass.request|approve|deny|revoke|read`
- `iam.federation.exchange|create_trust_policy|...`
- `iam.organizations.read|write|delete|list|claim_domain`
- `iam.access_reviews.read|write|complete`
- `iam.gdpr.request_erasure|cancel|process`
- ... + vpc.*, compute.*, loadbalancer.* (other services).

Используется:
- Phase 3 для OpenFGA model generation (permissions → relations).
- Custom Role.Create — валидация `permissions` array содержит только known values (если strict mode).

## System roles seed

Phase 1 reuses KAC-121/KAC-122 catalog (migration 0008). KAC-127 migration 0011 §6.4 backfill'ил `roles.cluster_id = 'cluster_kacho_root'` для system rows.

## Imports

- `crypto/rand`, `encoding/json`, `errors`, `log/slog`, `time`
- `github.com/jackc/pgx/v5`, `pgconn`, `pgxpool`
- `internal/domain` (newtypes, NewKac127ID, GrantedByBootstrap).

## Imported by

- `cmd/kacho-iam/main.go` — bootstrap-step before RPC serving.

## See also

[[iam-domain]] [[iam-repo-kacho-pg]] [[iam-jobs]] [[../resources/iam-cluster]] [[../resources/iam-cluster-admin-grant]] [[../KAC/KAC-127]]

#packages #kacho-iam #bootstrap
