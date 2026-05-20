---
title: "iam → hsm: PKCS#11 signing"
aliases:
  - iam to hsm
  - hsm signing
  - pkcs11
category: edge
caller_repo: kacho-iam
callee_repo: hsm
sync_async: sync
protocol: PKCS#11 (or KMS HTTPS facade)
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - hsm
  - signing
---

# iam → hsm: PKCS#11 signing

**Caller**: `kacho-iam`:
- Phase 8 — CAEP SET signing (sub-key for outbound subscribers).
- Phase 9 — Merkle batch signing (audit pipeline tamper-evidence).

**Callee**: Hardware Security Module — options:
- AWS CloudHSM (FIPS 140-2 Level 3).
- Azure Dedicated HSM (Thales Luna).
- GCP Cloud KMS HSM-backed keys.
- On-prem YubiHSM 2.

**Protocol**: PKCS#11 v2.40 (via `github.com/ThalesIgnite/crypto11` Go binding) — for cloud HSMs that expose PKCS#11; or KMS REST/gRPC facade (asymm sign).
**Sync/Async**: sync (per-batch signing).
**Status**: **Phase 8 + Phase 9 planned**.

## Architecture (Phase 9)

```
audit-drainer fetches 1000 events  →  Merkle tree build (in-memory)
                                       ↓ root hash 32-byte
                                  HSM.Sign(merkle_root, KEY=audit-signing-2026-q2, ALG=ECDSA-P384)
                                       ↓ signature
                                  INSERT audit_signing_batches (merkle_root, signature, key_id, batch_id)
                                       ↓
                                  Emit batch к Kafka topic kacho.iam.audit
                                       (events include signature reference)
```

## Key management

| Key purpose | Algorithm | Rotation cadence |
|---|---|---|
| audit_signing | ECDSA P-384 | 12 months |
| caep_set_signing | EdDSA Ed25519 | 6 months |
| token_signing (JWT) | RSA-2048 (legacy) / ECDSA P-256 (new) | 90 days (см. [[../resources/iam-jwks-key]]) |
| backup_kek (KEK for DB JWKS private wrapping) | AES-256 | 12 months |

## PKCS#11 wrapper

```go
// pseudocode — internal/clients/hsm_pkcs11.go (Phase 8/9)
ctx, err := crypto11.Configure(&crypto11.Config{
    Path:        "/opt/cloudhsm/lib/libcloudhsm_pkcs11.so",
    TokenLabel:  "audit-cluster-2026",
    Pin:         os.Getenv("KACHO_IAM_HSM_PIN"),
    UseGCMIVFromHSM: true,
})

key := ctx.FindKeyPair(label="audit-signing-2026-q2")
sig := key.Sign(rand.Reader, merkleRoot, crypto.SHA384)
```

## Resilience

- HSM failover: 2 HSMs in cluster (active/standby). On-prem CloudHSM AZ-redundant.
- Cache nothing in app — every sign call hits HSM (audit tampering risk).
- If HSM unreachable >5min → CAEP-drainer pauses (rather than emit unsigned), audit-drainer pauses batches → DLQ.
- Phase 11 ops runbook: HSM failover tested quarterly (chaos game-day).

## Key ceremony (Phase 9 production)

- Key generation в presence of 2 operators (M-of-N quorum, default 2-of-3).
- Public-key portion committed в `audit_signing_batches.signing_key_pem` для verifier.
- Independent daily verifier re-fetches public key + Merkle leaves → audit pipeline integrity check.

## Notes

- На dev/CI — software fallback (`crypto.ecdsa` in-process), но production deploy `KACHO_IAM_HSM_REQUIRE_HARDWARE=true` (fail-closed if soft).
- HSM access — kacho-iam pod identity (Cilium mTLS [[iam-to-cilium-mesh]] + SPIFFE SVID [[iam-to-spire]]) → restricted ingress.

## See also

[[iam-to-kafka-audit]] [[iam-to-clickhouse-audit]] [[iam-to-s3-audit]] [[../resources/iam-audit-signing-batch]] [[../resources/iam-jwks-key]] [[../packages/iam-clients-hsm-pkcs11]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #hsm #signing
