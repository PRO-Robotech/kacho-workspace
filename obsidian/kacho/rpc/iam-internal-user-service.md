---
title: InternalUserService
aliases:
  - InternalUserService (iam)
proto_file: kacho/cloud/iam/v1/internal_user_service.proto
category: rpc
backend: kacho-iam
backend_port: 9091
visibility: internal
domain: iam
related_resource: "[[resources/iam-user]]"
methods_count: 2
async_methods: 1
status: planned
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - internal
  - mirror
---

# InternalUserService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/internal_user_service.proto`
**Backend**: `kacho-iam:9091` (**internal-only**; запрет #6)
**Visibility**: internal — частично через api-gateway internal mux.
**Status**: backend в [[KAC-112]]; реальный заполнятель — OIDC-callback в E2.

## Methods

| Method | Request | Response | Sync/Async | Transport (E0) | Transport (E2) |
|---|---|---|---|---|---|
| **UpsertFromIdentity** | UpsertFromIdentityRequest | operation.Operation | **async** | **gRPC direct only** (admin через `grpcurl -plaintext kacho-iam:9091`) | REST `/iam/v1/internal/users:upsertFromIdentity` (вызывается OIDC-callback handler в api-gateway) |
| Get | GetUserRequest | User | sync | internal REST + gRPC | (same) — нужен E2 auth-interceptor для резолва principal без auth |

## REST mapping (internal mux only)

| HTTP | Method | Available since |
|---|---|---|
| `GET /iam/v1/internal/users/{id}` | Get | E0 |
| `POST /iam/v1/internal/users:upsertFromIdentity` | UpsertFromIdentity | **E2** (на E0 — только gRPC direct) |

## UpsertFromIdentity семантика

- Key — `external_id` (Zitadel `sub`).
- UPSERT: если row с `external_id` есть → UPDATE `email`, `display_name`; иначе INSERT новой row.
- ID-генерация — `ids.NewID("usr")` при INSERT.

## Notes

- E0: stub-заполнение admin'ом для bootstrap (создать User → создать Account). E2 переключит на OIDC-callback автоматически после первого успешного логина.
- `external_id` UNIQUE — UPSERT атомарен; CAS не нужен (PK insert либо UPDATE matched).
- Newman кейс `iam-internal-only-check` проверяет, что REST endpoint не доступен на external TLS.

## See also

[[../packages/iam-domain]] [[../resources/iam-user]] [[../edges/iam-to-zitadel-oidc]] [[iam-user-service]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam #internal #mirror

## OnRecoveryCompleted (KAC-127 Phase 2 / sub-phase 5.3) — IMPLEMENTED

Третий метод сервиса (был `Unimplemented` → Kratos recovery нерабочий). Реализован
в Wave R (PR в kacho-iam, ветка `wave-r-on-recovery`).

| Method | Request | Response | Sync/Async | Transport |
|---|---|---|---|---|
| **OnRecoveryCompleted** | OnRecoveryCompletedRequest (`external_id`, `recovery_jti`, `email`) | operation.Operation (metadata `OnRecoveryCompletedMetadata`, response `User`) | **async** | **gRPC :9091 only** (нет `google.api.http` в proto → НЕТ REST-маршрута через api-gateway; Kratos бьёт api-gateway, gateway re-dial'ит :9091 своим mTLS-cert'ом) |

Семантика (one writer-tx, запрет #10): idempotency-INSERT `recovery_completions`
(PK `recovery_jti`, ON CONFLICT DO NOTHING) → re-enable BLOCKED→ACTIVE (idempotent;
ACTIVE no-op) → revoke-all cutoff `user_token_revocations` (reason `password-change`,
монотонный GREATEST) → audit `iam.user.recovery_completed` (`tenant_account_id` =
`User.AccountID`). Sync-gates до спавна Operation: malformed→INVALID_ARGUMENT,
unknown external_id→NOT_FOUND, email-mismatch→FAILED_PRECONDITION (no side-effects).

> [!warning] Spec-vs-schema конфликт (5.3-09)
> APPROVED 5.3-09 предполагал 2 non-PENDING row (BLOCKED+ACTIVE) одной identity,
> оба re-enabled. Это НЕВОЗМОЖНО: migration 0011 `users_active_external_id_uniq`
> (global partial UNIQUE на external_id WHERE invite_status='ACTIVE') допускает
> ОДИН ACTIVE-row на external_id глобально. Реализация: re-enable
> constraint-bounded (23505 на BLOCKED→ACTIVE рядом с ACTIVE-sibling → skip,
> identity уже имеет канонический ACTIVE-row); revoke-all + audit идут всегда.
> Multi-account identity на этой схеме = один non-PENDING row + PENDING-siblings
> (external_id='') которые не matched. Требует ре-ревью acceptance-reviewer'ом.

Auth (5.3-08): уже было на месте — `caller_policy.go` GatewayFrontedInternalRPCs
(gateway-only), exempt от `system_viewer`-floor, `<exempt>` в permission_catalog.

Новые within-iam DB-конструкции: таблица `recovery_completions` (migration 0015,
PK-dedup); reader `FindByExternalIDInStatuses({ACTIVE,BLOCKED})` (BLOCKED-aware);
writer `ReEnable` (CAS через `UPDATE … FROM (SELECT … FOR UPDATE)`); tx-scoped
`InsertRecoveryCompletion` + `UpsertUserTokenRevokeAll` на `kacho.Writer`.
