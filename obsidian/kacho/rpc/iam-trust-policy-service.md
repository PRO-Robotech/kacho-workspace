---
title: TrustPolicyService
aliases:
  - TrustPolicy (iam, internal)
proto_file: kacho/cloud/iam/v1/internal_trust_policy_service.proto
category: rpc
backend: kacho-iam
backend_port: 9091
visibility: internal
domain: iam
related_resource: "[[resources/iam-federation-trust-policy]]"
methods_count: 5
async_methods: 3
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - internal
  - federation
---

# TrustPolicyService (iam, internal)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/internal_trust_policy_service.proto` (Phase 5).
**Backend**: `kacho-iam:9091` — cluster-internal listener.
**Visibility**: **Internal** — admin / account-owner CRUD (§Запреты #6). Tenant-CLI читает через public read-only RPC (планируется в `FederationService.ListTrustPolicies` если acceptance Phase 5 одобрит).
**Status**: **Phase 5 planned**. CRUD federation_trust_policies. Exchange-flow — отдельно [[iam-federation-exchange-service]].

## Methods (Phase 5)

| Method | Sync/Async | Description |
|---|---|---|
| CreateTrustPolicy | async | INSERT. Required: `service_account_id`, `issuer`, `subject_pattern` (regex без `*`), `audience`, `max_token_ttl` (DB CHECK ≤15min). Optional: `additional_claims_filter` (JSONB), `condition_id`. |
| GetTrustPolicy | sync | by id |
| UpdateTrustPolicy | async | mutable: `audience`, `additional_claims_filter`, `enabled`, `expires_at`, `max_token_ttl`. **Immutable**: `issuer`, `subject_pattern` (re-create если меняется). |
| DeleteTrustPolicy | async | hard-delete |
| ListTrustPolicies | sync | filter by `service_account_id` / `issuer` / `enabled`. |

## REST mapping (internal mux only)

| HTTP | Method |
|---|---|
| `POST /iam/v1/internal/federation/trustPolicies` | CreateTrustPolicy |
| `GET /iam/v1/internal/federation/trustPolicies/{id}` | GetTrustPolicy |
| `PATCH /iam/v1/internal/federation/trustPolicies/{id}` | UpdateTrustPolicy |
| `DELETE /iam/v1/internal/federation/trustPolicies/{id}` | DeleteTrustPolicy |
| `GET /iam/v1/internal/federation/trustPolicies` | ListTrustPolicies |

## Security guardrails

- `subject_pattern` парсится как RE2 regex; reject если содержит `.*` без anchor `^` / `$`.
- `max_token_ttl` DB-CHECK ≤ 900s (15min).
- `audience` — список fully-qualified URL'ов; reject wildcard.
- `expires_at` REQUIRED — TTL trust-policy ≤ 1 год (cluster-policy в Phase 5 admin acceptance).
- `account_id` принадлежности — берётся через `service_account_id` → SA.project → project.account, dual-write disabled.

## Notes

- Создание trust-policy — audit-event `iam.federation.policy.created` (Phase 9 audit pipeline).
- Delete — CAEP `iam.federation.policy.revoked` push subscribers'у ([[../edges/iam-caep-to-subscriber]]).
- Mutating через api-gateway → internal listener (port 9091 only) → не на api.kacho.cloud.

## See also

[[iam-federation-exchange-service]] [[../resources/iam-federation-trust-policy]] [[../resources/iam-service-account]] [[../packages/iam-service-federation]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #internal #federation
