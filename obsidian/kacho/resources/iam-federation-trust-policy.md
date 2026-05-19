---
title: FederationTrustPolicy
aliases:
  - FederationTrustPolicy (iam)
  - FTP
  - federation_trust_policy
category: resource
domain: iam
id_prefix: ftp
owner_table: kacho_iam.federation_trust_policies
owner_db: kacho_iam
folder_level: false
status: planned
related_rpc:
  - "[[rpc/iam-federation-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
---

# FederationTrustPolicy

**Domain**: iam — OIDC Token Exchange (RFC 8693) trust для Class B Workload Identity Federation (GitHub Actions / AWS / GCP / GitLab / CircleCI / Buildkite / Bitbucket).
**ID prefix**: `ftp_` + 17-char crockford → `^ftp_[0-9a-hjkmnp-tv-z]{17}$`.
**Owner table**: `kacho_iam.federation_trust_policies` (migration 0012).
**Phase 1**: schema-only. Token Exchange RPC — Phase 5.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^ftp_[0-9a-hjkmnp-tv-z]{17}$` | |
| `service_account_id` | TEXT | FK → service_accounts(id) CASCADE | identity, в кого федерируем |
| `issuer` | TEXT | length 1..512, `^https://` | OIDC issuer URL |
| `audience` | TEXT | length 1..512 | expected `aud` claim |
| `subject_pattern` | TEXT | **no `*` wildcard**, length 1..512 | anchored regex (Phase 5 compile) |
| `additional_claims_filter` | JSONB | object | extra claim asserts |
| `conditions` | JSONB | object | CEL-like predicates |
| `max_token_ttl` | INTERVAL | **(0s, 15min]** CHECK | issued token max-TTL |
| `enabled` | BOOL | | |
| `expires_at` | TIMESTAMPTZ | **NOT NULL**, `> created_at`, `≤ created_at + 1y` CHECK | policy expiry |
| `created_at` | TIMESTAMPTZ | server-set | |
| `created_by` | TEXT | length <=64 | user_id |

## Constraints / indexes

- `federation_trust_policies_pkey` PRIMARY KEY (id)
- `federation_trust_policies_sva_fk` FK → `service_accounts(id)` ON DELETE CASCADE
- `federation_trust_policies_unique` UNIQUE (`issuer`, `subject_pattern`) — идемпотентность
- CHECK: id-regex, `issuer ~ '^https://'`, `subject_pattern !~ '\*'`, `max_token_ttl ∈ (0, '15 minutes')`, expires_at NOT NULL и `> created_at` и `<= created_at + INTERVAL '1 year'`

## Lifecycle (Phase 5)

- **Create / Update / Delete** — async через `Operation`.
- **Exchange (Phase 5)**: external JWT (GitHub OIDC) → validate against trust-policy → issue kacho JWT с TTL ≤ `max_token_ttl`.

## Gotchas

- `subject_pattern` **запрещает `*` wildcard** — это поверхность для confused-deputy. Только anchored regex.
- `max_token_ttl ≤15min` — DB-enforced. Production принцип: federation tokens short-lived (refresh через re-exchange).
- `expires_at ≤ 1 year` — policy сам по себе rotation-обязательный.
- CASCADE FK от ServiceAccount: удаление SA автоматически чистит trust-policies (нет orphans).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-federation-service]] [[iam-service-account]] [[iam-service-account-oauth-client]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
