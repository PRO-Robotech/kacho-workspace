---
title: "iam internal/domain"
aliases:
  - iam domain
  - iam-domain
category: packages
repo: kacho-iam
layer: domain
status: done
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-iam
  - domain
---

# iam `internal/domain`

Entities + self-validating newtypes + `Validate()` методы. Импортирует только stdlib + `multierr` (skill evgeniy §4 D.1–D.2). НИКАКОГО pgx / grpc / sqlc — это утечка adapter в use-case.

## Entities (22 — KAC-127 Phase 1)

### Core (KAC-105/KAC-112)
- `User` — Zitadel/Kratos mirror
- `Account` — KAC-127: +`cluster_id`/`organization_id` FK
- `Project` — folder-replacement (account-scoped)
- `ServiceAccount` — KAC-127: +`project_id`/`enabled`
- `Group` + `GroupMember` (soft polymorphic ref через trigger)
- `Role` — KAC-127: multi-scope refactor (cluster/organization/account/project XOR)
- `AccessBinding` — KAC-127: +`status`/`condition_id`/`expires_at`/`granted_by`/`revoked_at`/`revoked_by`

### KAC-127 Phase 1 new (16)
- `Cluster` — singleton (literal id `cluster_kacho_root`)
- `Organization` — B2B tier (SCIM/SAML config + domain claim)
- `ClusterAdminGrant` — permanent root grant (partial UNIQUE)
- `ClusterBreakGlassGrant` — 6-state machine (2-person approve)
- `FederationTrustPolicy` — RFC 8693 OIDC trust
- `AccessBindingCondition` — CEL-like overlay (7-value Kind enum)
- `AccessBindingJITEligibility` — PIM/JIT eligibility (max 8h)
- `ServiceAccountOAuthClient` — Class A Hydra static (1:1)
- `CAEPSubscriber` — webhook registration (per-Account CASCADE)
- `SessionRevocation` — token_jti blocklist with TTL
- `AuditSigningBatch` — HSM-signed Merkle chain
- `OIDCJwksKey` — JWKS rotation (partial UNIQUE per alg)
- `SCIMUserMapping` — (org, scim_external_id) → user
- `GDPRErasureRequest` — 30d cool-off pipeline
- `AccessReview` — quarterly recertification
- `AccessReviewItem` — per-binding decision

### Phase 1 ancillary
- `AuditOutboxEntry`, `CAEPOutboxEntry` — outbox table rows (`evt_`, `cev_` prefixes; ULID-based 20..30)

## ID prefixes (acceptance §2.2, +16 в KAC-127)

| Resource | Prefix | Length |
|---|---|---|
| Account | `acc` | 20 |
| Project | `prj` | 20 |
| User | `usr` | 20 |
| ServiceAccount | `sva` | 20 |
| Group | `grp` | 20 |
| Role | `rol` | 20 |
| AccessBinding | `acb` | 20 |
| Operation | `iop` | 20 |
| **KAC-127** | | |
| Cluster | literal `cluster_kacho_root` | — |
| Organization | `org_` | 17-char body |
| ClusterAdminGrant | `cag_` | 17-char body |
| BreakGlassGrant | `bgg_` | 17-char body |
| FederationTrustPolicy | `ftp_` | 17-char body |
| Condition | `cond_` | 1..40 |
| JITEligibility | `jite_` | 1..40 |
| SAOAuthClient | `soc_` | 17-char body |
| CAEPSubscriber | `cps_` | 17-char body |
| AuditBatch | `asb_` | 20..30 |
| SCIMMap | `scim_` | 1..40 |
| GDPRRequest | `gdpr_` | 1..40 |
| AccessReview | `arv_` | 1..40 |
| ReviewItem | `ari_` | 1..40 |
| AuditEvent | `evt_` | 20..30 ULID |
| CAEPEvent | `cev_` | 20..30 ULID |

## ID generators

- `kacho-corelib/ids.NewID(prefix)` — legacy 3-char prefix + 17-char crockford (KAC-105 ресурсы).
- `domain.NewKac127ID(prefix)` — KAC-127 format `<prefix>_<17-char crockford>` (длиннее prefix допустимо). Uses `crypto/rand`. DB CHECK regex per-table в миграциях 0011-0014.

## Newtypes (selected)

- IDs: `ClusterID`, `OrganizationID`, `ClusterAdminGrantID`, `BreakGlassGrantID`, `FederationTrustPolicyID`, `AccessBindingConditionID`, `JITEligibilityID`, `SAOAuthClientID`, `CAEPSubscriberID`, `AuditBatchID`, `SCIMMappingID`, `GDPRRequestID`, `AccessReviewID`, `AccessReviewItemID`.
- Enum-newtypes: `GrantSubjectType`, `BreakGlassState`, `AccessBindingStatus`, `ConditionKind`, `JWKSAlg`, `GDPRStatus`, `AccessReviewStatus`, `AccessReviewDecision`.
- Validation newtypes: `OrgDomain` (RFC 1035), `OIDCIssuer` (`https://`), `SubjectPattern` (no `*`), `CAEPEndpointURL` (`https://`), `HydraClientID`, `SCIMEndpoint`, `SAMLMetadataURL`.
- `ClaimsFilter` / `ConditionParams` — JSONB `json.RawMessage` newtype (opaque в Phase 1; CEL-evaluated в Phase 3).

## Imports

- `time`, `regexp`, `crypto/rand`, `encoding/binary`, `encoding/json`, `fmt`, `strings`
- `go.uber.org/multierr` — cumulative-error pattern.

## Imported by

- `internal/repo/kacho/pg` — DTO mapping → SQL.
- `internal/apps/kacho/*` — use-cases.
- `internal/dto` — generic DTO transfer.
- `internal/handler` — proto→domain parsing.

## See also

[[iam-repo-kacho-pg]] [[iam-seed]] [[../resources/iam-cluster]] [[../resources/iam-organization]] [[../resources/iam-role]] [[../resources/iam-access-binding]] [[../KAC/KAC-127]]

#packages #kacho-iam #domain
