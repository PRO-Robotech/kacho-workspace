---
title: "iam internal/clients/hsm_pkcs11"
aliases:
  - hsm client
  - pkcs11 client
category: packages
repo: kacho-iam
layer: clients
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-iam
  - clients
  - hsm
  - signing
---

# iam `internal/clients/hsm_pkcs11`

Phase 8 + Phase 9 — adapter для Hardware Security Module via PKCS#11 v2.40. Port-interface defined в `internal/service/{caep,audit}`, impl here.

## Exported API

```go
type HSMSigner interface {
    Sign(ctx context.Context, keyLabel string, data []byte, alg SignAlg) ([]byte, error)
    GetPublicKey(ctx context.Context, keyLabel string) (pubKeyPEM []byte, err error)
    HealthCheck(ctx context.Context) error  // fail-closed gate
}

type SignAlg int
const (
    AlgECDSA_P256_SHA256 SignAlg = iota
    AlgECDSA_P384_SHA384
    AlgEd25519
    AlgRSA_PSS_2048_SHA256
)
```

## Implementation

```go
type pkcs11HSM struct {
    ctx        *crypto11.Context        // github.com/ThalesIgnite/crypto11
    keyCache   sync.Map                 // keyLabel → cached crypto11.KeyPair (1h TTL)
    metrics    *prometheus.HistogramVec
    requireHW  bool                     // fail-closed if software fallback
}

func (h *pkcs11HSM) Sign(ctx, keyLabel string, data []byte, alg SignAlg) ([]byte, error) {
    start := time.Now()
    defer h.metrics.WithLabelValues(keyLabel, alg.String()).Observe(time.Since(start).Seconds())
    
    key, err := h.resolveKey(ctx, keyLabel)
    if err != nil { return nil, err }
    
    digest := hashFor(alg).Sum(data)
    sig, err := key.Sign(rand.Reader, digest, hashFor(alg))
    if err != nil { return nil, fmt.Errorf("hsm sign %s: %w", keyLabel, err) }
    return sig, nil
}
```

## Configuration

| ENV | Default | Description |
|---|---|---|
| `KACHO_IAM_HSM_PKCS11_LIB` | (required) | `.so` path (e.g. `/opt/cloudhsm/lib/libcloudhsm_pkcs11.so`) |
| `KACHO_IAM_HSM_TOKEN_LABEL` | (required) | partition label |
| `KACHO_IAM_HSM_PIN` | (required, Kubernetes Secret) | crypto-officer PIN |
| `KACHO_IAM_HSM_REQUIRE_HARDWARE` | `true` (prod) / `false` (dev) | fail-closed gate |
| `KACHO_IAM_HSM_HEALTH_INTERVAL_S` | 30 | health check cadence |

## Software fallback (dev/CI only)

```go
type softFallback struct {
    keys sync.Map  // keyLabel → *ecdsa.PrivateKey (in-process, ephemeral)
}

// only enabled if KACHO_IAM_HSM_REQUIRE_HARDWARE=false
// CI test suites generate ephemeral keys per-test
```

## Health check

```go
func (h *pkcs11HSM) HealthCheck(ctx) error {
    _, err := h.Sign(ctx, "health-check-key", []byte("ping"), AlgECDSA_P256_SHA256)
    return err
}
// Invoked every 30s by composition root; if 3 consecutive failures → halt drainers + alert.
```

## Key cache

- `keyLabel → crypto11.KeyPair` (1h TTL); reduces PKCS#11 `FindKeyPair` overhead.
- Invalidated on `HSMSigner.RefreshKeys()` call (admin endpoint).

## Imports

- `github.com/ThalesIgnite/crypto11` — PKCS#11 binding
- `crypto/rand`, `crypto/sha256`, etc. — stdlib digests
- `github.com/prometheus/client_golang`

## Imported by

- `internal/service/caep/signer` — SET signing
- `internal/service/audit/signer` — Merkle batch signing
- `cmd/kacho-iam/main.go`

## Metrics

- `kacho_iam_hsm_sign_seconds{key_label, alg}` — histogram
- `kacho_iam_hsm_errors_total{op, kind}`
- `kacho_iam_hsm_health{status}` — gauge 0/1

## See also

[[iam-service-caep]] [[../edges/iam-to-hsm]] [[../resources/iam-audit-signing-batch]] [[../resources/iam-jwks-key]] [[../KAC/KAC-127]]

#packages #kacho-iam #clients #hsm #signing
