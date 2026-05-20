---
title: Runbooks
aliases:
  - Runbooks index
category: hub
tags:
  - runbooks
  - operations
---

# Runbooks index

Operational runbooks для kacho-iam production deployment ([[../KAC/KAC-127]]).
Each runbook canonical location — kacho-iam repo (`docs/runbooks/`); vault links — reference catalog.

> [!warning] Tabletop-tested quarterly
> Phase 12 DoD (KAC-127): "All runbooks tabletop-tested". Each runbook должен иметь dated execution log в Vault `runbooks/log/YYYY-MM-DD-<runbook>.md`.

## Phase 7 — JIT / Break-glass / GDPR

- **`break-glass-procedure.md`** — emergency cluster-admin grant (2-person approve, 2h TTL, mandatory justification, alerts).
  Canonical: `project/kacho-iam/docs/runbooks/break-glass-procedure.md`.
  Used by: security on-call + senior engineering manager.
- **`gdpr-erasure-workflow.md`** — Article 17 right-to-erasure pipeline (30d cool-off → cross-domain hard-delete).
  Canonical: `project/kacho-iam/docs/runbooks/gdpr-erasure-workflow.md`.
  Used by: DPO + privacy team.

## Phase 9 — Audit pipeline

- **`audit-pipeline-incident.md`** — Kafka producer halt, ClickHouse ingestion lag, S3 sink failure recovery.
  Canonical: `project/kacho-iam/docs/runbooks/audit-pipeline-incident.md`.
- **`hsm-failover.md`** — HSM cluster failover (primary → standby).
  Canonical: `project/kacho-iam/docs/runbooks/hsm-failover.md`.
- **`key-rotation-procedure.md`** — manual JWKS / CAEP SET / audit-signing key rotation outside cadence (compromise scenario).
  Canonical: `project/kacho-iam/docs/runbooks/key-rotation-procedure.md`.

## Phase 8 — CAEP

- **`caep-backlog-recovery.md`** — DLQ drain после subscriber outage / configuration drift.
  Canonical: `project/kacho-iam/docs/runbooks/caep-backlog-recovery.md`.

## Phase 3 — FGA

- **`fga-drift-reconciliation.md`** — when access_bindings table diverges from OpenFGA tuple store (outbox drainer failure).
  Canonical: `project/kacho-iam/docs/runbooks/fga-drift-reconciliation.md`.

## Phase 11 — Production deployment

- **`regional-failover.md`** — active-active multi-region failover (eu-west-1 → us-east-1).
  Canonical: `project/kacho-deploy/docs/runbooks/regional-failover.md`.
- **`cert-renewal-failure.md`** — cert-manager / Let's Encrypt issuance failure recovery.
  Canonical: `project/kacho-deploy/docs/runbooks/cert-renewal-failure.md`.
- **`argocd-sync-failure.md`** — Argo CD app stuck в Degraded / OutOfSync.
  Canonical: `project/kacho-deploy/docs/runbooks/argocd-sync-failure.md`.

## Phase 12 — Conformance + Chaos

- **`chaos-gameday-report-template.md`** — quarterly Litmus chaos game-day. Pre-flight checklist + post-mortem template.
  Canonical: `project/kacho-iam/docs/runbooks/chaos-gameday-report-template.md`.
- **`supply-chain-incident.md`** — image tampering / dependency CVE / cosign signature invalid response procedure.
  Canonical: `project/kacho-iam/docs/runbooks/supply-chain-incident.md`.

## Quarterly tabletop schedule

| Quarter | Runbooks rehearsed |
|---|---|
| Q1 | break-glass-procedure, hsm-failover |
| Q2 | regional-failover, caep-backlog-recovery |
| Q3 | gdpr-erasure-workflow, audit-pipeline-incident, fga-drift-reconciliation |
| Q4 | supply-chain-incident, key-rotation-procedure, chaos-gameday |

Logs: `runbooks/log/2026-Q1-<runbook>.md` — record participant, scenario variant, time-to-recovery, gaps identified.

## See also

[[../KAC/KAC-127]] [[../architecture]] [[../README]]

#runbooks #operations
