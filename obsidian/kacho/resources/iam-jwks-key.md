---
title: JWKS Key (alias)
aliases:
  - JWKSKey
  - iam JWKS Key
  - JWKS rotation
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

# JWKS Key (iam)

> [!note] Alias note
> Это alias-документ для [[iam-oidc-jwks-key]] — каноническая страница ресурса. Здесь резюме flow rotation 90d из Phase 2.

**Domain**: iam — signing key для kacho-issued JWT (DPoP-bound access_tokens, federation Exchange output).
**ID prefix**: `kid` (key id, kebab-case `kacho-rsa-2026-q2`).
**Owner table**: `kacho_iam.oidc_jwks_keys` (Phase 1 migration 0014).
**Visibility**: **internal** (только public part эксплуатируется через JWKS endpoint `/.well-known/jwks.json` на api-gateway).

## Rotation policy (Phase 2 implemented)

- **Cadence**: 90 дней (configurable env `KACHO_IAM_JWKS_ROTATE_INTERVAL_DAYS`).
- **Algorithms**: ES256 (primary, EC P-256), RS256 (compat), Ed25519 (Phase 11 PQ-readiness slot).
- **Grace period**: новый ключ active 7 дней до того как сюда переключатся token-issuance (overlap для in-flight tokens).
- **Worker**: `cmd/jwks-rotator/main.go` CronJob (kacho-deploy Phase 2). Использует `pg_advisory_xact_lock` per-alg → одна реплика крутит за раз.
- **Tamper detect**: AES-GCM encryption private key material (KEK rotated separately); HSM signing для production (Phase 9).

## Active key selection

- `oidc_jwks_keys.is_active = true` — current signing key.
- Partial UNIQUE `WHERE is_active = true` per `algorithm` — atomicity invariant (max 1 active per alg).
- Old keys retained для verify-window: TTL `not_after` = activated_at + 30 дней.

## JWKS endpoint

- `GET https://api.kacho.cloud/.well-known/jwks.json` — публикует public keys (filter `is_active OR not_after > now()`).
- Cache-Control: `max-age=300` (5min); CDN-edge cached.
- Тестировано: federation Exchange выпустил token с key X → key X revoked → 401 на verify в течение ≤5min.

## Notes

- Каноническая entry — [[iam-oidc-jwks-key]] (полная таблица полей, FK contract, миграции).
- Этот файл — quick-reference rotation flow.

## See also

[[iam-oidc-jwks-key]] [[iam-audit-signing-batch]] [[../packages/iam-handler-iamhooks]] [[../packages/iam-clients-hsm-pkcs11]] [[../packages/api-gateway-middleware-dpop]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam #internal
