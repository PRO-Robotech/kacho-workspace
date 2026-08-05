---
title: "iam internal/repo/kacho/pg"
aliases:
  - iam repo pg
  - iam-repo-kacho-pg
category: packages
path: services/iam/internal/repo/kacho/pg
repo: kacho-iam
layer: repo
status: done
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
  - "[[KAC-108]]"
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-iam
  - repo
verified_against: "перечень файлов пакета сверен с деревом продукта 1653387b (2026-08-06) переписью non-test файлов каталога; DB-инварианты и CAS-разделы построчно не пересматривались"
---

# iam `internal/repo/kacho/pg`

CQRS Repository / Reader / Writer adapter — реализация port-интерфейсов из `internal/repo/kacho/<resource>` через `pgxpool`. Реализует pg-adapter strategy: pgx + dto-mapping без ORM (workspace §запрет #3).

## Layer rules

- Импортирует только `pgxpool`, `pgconn`, `internal/domain`, `internal/errors`, `kacho-corelib/db`.
- НЕ импортирует proto-stubs / grpc — этим занимается handler.
- SQLSTATE → sentinel mapping — централизованно в `maperr.go` (workspace §запрет #10 / §«Within-service refs — DB-уровень»).

## Files (per resource)

### Core (KAC-105/KAC-112)
- `account_repo.go` + `account_integration_test.go`
- `project_repo.go` + `project_integration_test.go`
- `user_repo.go` + `user_integration_test.go` + `user_invite_integration_test.go`
- `service_account_repo.go` + `service_account_integration_test.go`
- `group_repo.go` + `group_integration_test.go`
- `role_repo.go` + `role_integration_test.go`
- `access_binding_repo.go` + `access_binding_integration_test.go` — сюда же переехал
  emit в очередь FGA: `INSERT INTO kacho_iam.fga_outbox` идёт прямо из writer-TX этого
  файла (см. [[iam-pg-fga-outbox]])

### Что стало с блоком «KAC-127 Phase 1» — шести файлов нет, предмет разошёлся (1653387b, 2026-08-06)

Перепись `git ls-files` по каталогу даёт **ноль** файлов с прежним префиксом имени, и
поиск этого префикса по всему дереву тоже даёт ноль. Мёртвые имена здесь не
воспроизводятся координатой — цитата в обратных кавычках читается как живое утверждение
о дереве. Куда разошёлся предмет:

- **Cluster + ClusterAdminGrant** — живы: `iam_core_repos.go` (синглтон Cluster +
  общий сканер строки гранта), `cluster_reader.go`, `cluster_admin_grant_reader.go`,
  `cluster_admin_grant_writer.go`.
- **ServiceAccountOAuthClient** — жив: `iam_extension_repos.go`. Шапка этого файла сама
  фиксирует убыль соседей: репозиториев федерации, пригодности к JIT и условия привязки
  «больше не существует».
- **AuditOutbox + SessionRevocation** — живы: `audit_session_revocation_repos.go`.
- **Organization · FederationTrustPolicy · JITEligibility · AccessBindingCondition ·
  BreakGlass · CAEP · SCIM · GDPRErasure · AccessReview · OIDCJwksKey** — сняты
  вместе со своими таблицами, каждый своей миграцией:
  `services/iam/internal/migrations/0006_drop_scim_saml_break_glass.sql`,
  `0007_drop_caep_pipeline.sql`, `0008_drop_organizations.sql`,
  `0013_drop_jit_breakglass_condition_whitelist.sql`,
  `0065_drop_oidc_jwks_keys.sql`.
- **Операции (LRO)** — отдельного репозитория операций у iam нет: общая таблица и её
  репозиторий живут в фундаменте (`pkg/operations/repo.go`,
  `pkg/migrations/common/0001_operations.sql`); iam-специфика — надстройки
  `ops_response_redactor.go` / `ops_secret_sweeper.go`.
- **Заглушки нереализованных методов** — предмета нет: сентинела «не реализовано» в
  слое репозитория iam не осталось ни одного вхождения.

> [!warning] Номера миграций 0011-0014 в прежней редакции указывали не туда
> Она привязывала эти файлы к «таблицам миграций 0011-0014». Сегодня под этими номерами
> в iam стоит совсем другое: `0011_users_drop_global_email_uniqueness.sql`,
> `0012_user_token_revocations.sql`, `0013_drop_jit_breakglass_condition_whitelist.sql`,
> `0014_reader_sa_system_viewer.sql`. Номер миграции — не устойчивая ссылка на предмет:
> нумерация продолжается, а прежние DDL могут быть сняты более поздней миграцией.

### Helpers
- `repository.go` — Repository struct + constructor.
- `tx.go` — Writer-TX wrapper (`Repository.RunInTx(ctx, func(WriterCtx) error)`).
- `helpers.go` — shared dto-mapping utilities.
- `maperr.go` — SQLSTATE → sentinel mapping (23503 → FailedPrecondition, 23505 → AlreadyExists/FailedPrecondition по контексту, 23514 → InvalidArgument, 23P01 → FailedPrecondition).
- `dto/` — DTO row-types (1:1 с DB columns).

(Файла-заглушки с нереализованными методами в каталоге больше нет; сентинел «не
реализовано» в слое репозитория iam не встречается ни разу — см. разбор выше.)

## DB-уровень enforcement (KAC-127 highlights)

- `cluster_admin_grants_subject_unique` partial UNIQUE WHERE granted_until IS NULL.
- `access_binding_conditions_binding_unique` UNIQUE — 1:1 enforcement.
- `service_account_oauth_clients_sva_unique` UNIQUE — 1:1 SA→client.
- `oidc_jwks_keys_current_per_alg` partial UNIQUE WHERE current=true — JWKS rotation atomic CTE.
- `roles_scope_xor` CHECK + 4 partial UNIQUEs per scope (cluster/organization/account/project).
- `access_bindings_status_ck` + `access_bindings_revoked_consistency_ck` + `access_bindings_expires_ck` — KAC-127 lifecycle invariants.

## Concurrency / atomic CAS patterns

- **JWKS rotate**: single-statement CTE `WITH rotated AS (UPDATE ... WHERE current=true RETURNING) INSERT new`.
- **AccessBinding revoke**: idempotent CAS `UPDATE ... WHERE id=$id AND status IN ('PENDING','ACTIVE')` → REVOKED.
- **Project.Move** (KAC-105): atomic CAS UPDATE с `WHERE account_id=$expected`.
- **BreakGlass state transitions** (Phase 7): atomic CAS UPDATE per state-transition.
- **Bootstrap admin grant** (Phase 1): 23505 → graceful WARN (concurrent HA cold-start, acceptance §6.10.5).

## Imports

- `github.com/jackc/pgx/v5`, `pgxpool`, `pgconn`
- `internal/domain`, `internal/errors`, `internal/dto`
- `kacho-corelib/db` (transactor).

## Imported by

- `cmd/kacho-iam/main.go` — composition root.
- `internal/apps/kacho/api/*` — use-case через port-interfaces (mock via `repomock/`).

## See also

[[iam-domain]] [[iam-seed]] [[iam-jobs]] [[../resources/iam-cluster]] [[../resources/iam-role]] [[../resources/iam-access-binding]] [[../KAC/KAC-127]]

#packages #kacho-iam #repo
