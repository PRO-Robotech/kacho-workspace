---
title: OIDCJwksKey
aliases:
  - JWKSKey
  - iam OIDC JWKS Key
  - oidc_jwks_key
category: resource
domain: iam
id_prefix: (kid)
owner_table: kacho_iam.oidc_jwks_keys
owner_db: kacho_iam
folder_level: false
status: planned
related_rpc: []
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
---

# OIDCJwksKey

**Domain**: iam — JWKS rotation tracking. Хранит current + старые keys для JWT verification (старые остаются valid до natural `exp`).
**ID**: `kid` (PK; `[A-Za-z0-9._:-]+`, length 1..128) — без префикса (JWKS standard).
**Owner table**: `kacho_iam.oidc_jwks_keys` (migration 0014).
**Phase 1**: schema-only. Rotation flow (CTE single-statement) — Phase 2 AuthN.
**SENSITIVE**: `private_key_pem_encrypted` — encrypted at rest; **никогда не сериализуется в публичные ответы** (workspace §«Инфра-чувствительные данные»).

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `kid` | TEXT PK | `[A-Za-z0-9._:-]+`, length 1..128 | JWKS Key ID |
| `alg` | TEXT | CHECK enum (RS256/ES256/EdDSA) | signing alg |
| `current` | BOOL | | true → используется для нового подписания |
| `rotated_at` | TIMESTAMPTZ NULL | CHECK ⇔ `current=false` | NULL пока current=true |
| `expires_at` | TIMESTAMPTZ | NOT NULL, `> created_at` | hard expiry (validation тоже отказывает после этого) |
| `public_key_pem` | TEXT | length 1..16384 | PEM-encoded public key (exposed via /.well-known/jwks.json) |
| `private_key_pem_encrypted` | BYTEA | length 1..32768 | **SENSITIVE** — encrypted with KMS/HSM master key |
| `created_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- `oidc_jwks_keys_pkey` PRIMARY KEY (kid)
- `oidc_jwks_keys_current_per_alg` **partial UNIQUE (alg) WHERE current=true** — гарантирует **один current key per alg** (RS256/ES256/EdDSA — independent).
- `oidc_jwks_keys_alg_check` CHECK `alg IN ('RS256','ES256','EdDSA')`
- CHECK: kid-regex, kid-length, `expires_at > created_at`, `(current=true AND rotated_at IS NULL) OR (current=false AND rotated_at IS NOT NULL)` — consistency invariant
- Index: `(alg, current)` для JWKS endpoint lookup; `(expires_at)` для cleanup-cron

## Rotation flow (Phase 2 CTE single-statement)

```sql
WITH rotated AS (
  UPDATE kacho_iam.oidc_jwks_keys
     SET current=false, rotated_at=now()
   WHERE alg=$alg AND current=true
  RETURNING kid
)
INSERT INTO kacho_iam.oidc_jwks_keys (kid, alg, current, expires_at, public_key_pem, private_key_pem_encrypted)
VALUES ($new_kid, $alg, true, $expires, $pub, $priv);
```

Atomic single-statement: либо обе строки (rotation + new), либо ни одной. Partial UNIQUE предотвращает race (concurrent rotate → 23505).

## Lifecycle

- **Rotate (Phase 2 cron / on-demand)**: single-statement CTE выше. Старый key остаётся в таблице для JWT verification (старые токены остаются validатыми до `expires_at`).
- **Verify**: AuthN-interceptor lookup'ит kid в WHERE clause `kid=$jwt_kid AND now() <= expires_at` — independent of `current` flag.
- **Cleanup (Phase 8 cron)**: `DELETE WHERE expires_at < now() - retention_window`.

## Gotchas

- `private_key_pem_encrypted` — bytea, **encrypted at rest** (KMS envelope или HSM-wrapped DEK). Decryption — только in-memory in signing-service.
- НИКОГДА не serialize'ить `private_key_pem_encrypted` в gRPC responses / logs / audit-events.
- partial UNIQUE per alg — корректно: можно держать current RS256 + current ES256 + current EdDSA одновременно.
- /.well-known/jwks.json публикует ТОЛЬКО `kid + alg + public_key_pem` (NOT private). Phase 2 will implement.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[iam-session-revocation]] [[iam-audit-signing-batch]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam #internal
