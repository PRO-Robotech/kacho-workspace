---
title: AuditSigningBatch
aliases:
  - AuditSigningBatch (iam)
  - audit_signing_batch
  - merkle batch
category: resource
domain: iam
id_prefix: asb
owner_table: kacho_iam.audit_signing_batches
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

# AuditSigningBatch

**Domain**: iam — HSM-signed batch manifest для tamper-evident audit cold-storage (S3 → Glacier). Merkle chain (`previous_batch_hash` ссылается на предыдущий `batch_hash` → tamper-evident sequence).
**ID prefix**: `asb_` + 20..30 char crockford → `^asb_[0-9A-HJKMNP-TV-Za-hjkmnp-tv-z]{20,30}$`.
**Owner table**: `kacho_iam.audit_signing_batches` (migration 0013).
**Phase 1**: schema-only. HSM-sign worker — Phase 9 audit pipeline.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^asb_[0-9A-HJKMNP-TV-Za-hjkmnp-tv-z]{20,30}$` | |
| `batch_hash` | BYTEA | length 16..64 bytes | content hash (SHA-256 ≥256 bits) |
| `previous_batch_hash` | BYTEA NULL | length 16..64 bytes when set | NULL для genesis row; chain link |
| `signature` | BYTEA | length 32..1024 bytes | HSM-produced signature |
| `signed_at` | TIMESTAMPTZ | server-set | |
| `signer_kid` | TEXT | length 1..128 | HSM key-id |
| `s3_object_key` | TEXT | length 1..1024 | S3 key пакета audit-events |

## Constraints / indexes

- `audit_signing_batches_pkey` PRIMARY KEY (id)
- CHECK: id-regex, batch_hash length 16..64, previous_batch_hash length 0 OR 16..64, signature length 32..1024, signer_kid length 1..128, s3_object_key length 1..1024
- Index: `(signed_at)` — для chronological lookup
- Index: `(previous_batch_hash)` — для chain traversal

## Lifecycle (Phase 9)

1. **Drainer** периодически собирает audit_outbox rows за период → формирует batch (chunked S3 upload).
2. **Hash + Sign**: compute `batch_hash = SHA-256(serialized_events)`, `previous_batch_hash = (prev row).batch_hash`, отправляет в HSM → получает `signature`.
3. **Persist**: INSERT row + upload to S3.
4. **Verify (continuous)**: independent verifier worker proverify-ит цепочку: для каждого row перечитывает S3 object, проверяет signature по signer_kid (JWKS / KMS pub-key), сверяет `previous_batch_hash`. Несоответствие → alert.
5. **Glacier transition**: S3 lifecycle policy → Glacier через 30-90 дней.

## Gotchas

- Merkle chain — tamper-evident, не tamper-proof: можно увидеть, что что-то изменилось, но не предотвратить. Защита через HSM-signature ↔ независимый verifier.
- Genesis row: `previous_batch_hash IS NULL` (один такой row на установку).
- `signer_kid` — KID HSM key'а; rotation Phase 9 cron генерирует new key, старый остаётся для verification.
- BYTEA для hash/signature — НЕ сериализуется наружу как hex/base64 на публичный API (internal-only). Любые public endpoints — opaque opaque string `<batch_id>:<signed_at>` для customer support.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[iam-oidc-jwks-key]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam #internal
