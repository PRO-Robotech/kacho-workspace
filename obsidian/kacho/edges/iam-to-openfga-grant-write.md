---
title: "kacho-iam → OpenFGA (grant/revoke write)"
category: edges
caller_repo: kacho-iam
callee_repo: openfga
sync_async: sync
protocol: http
status: experimental
related_tickets:
  - KAC-134
  - KAC-135
tags:
  - edge
  - kacho-iam
  - kacho-deploy
---

# kacho-iam → OpenFGA (grant/revoke write)

Прямой sync HTTP-вызов OpenFGA `/stores/{id}/write` для grant/revoke FGA-tuples из mutation path'ов kacho-iam.

## Bootstrap (umbrella-level, KAC-127 Phase 3, верифицирован W0.4)

Store + AuthorizationModel поднимаются **умbrellой** (не kacho-iam):

- `kacho-deploy/helm/umbrella/templates/openfga-bootstrap-job.yaml` — post-install/post-upgrade Job (hook-weight 10). sha256-DSL fast-path: если sha256(model.fga) == annotation `kacho-deploy/last-applied-dsl-sha256` на `openfga-model-id` Secret → skip-write (идемпотентно).
- `openfga-model-stub-configmap.yaml` — `model.fga` + `model.json` inline (регенерация: `make openfga-model-json` из `kacho-proto/.../fga_model.fga`).
- `openfga-model-id-secret.yaml` — Secret c `store_id` + `current` model_id (patches by bootstrap-job).
- `openfga-bootstrap-rbac.yaml`, `openfga-postgres-init-job.yaml` (pre-install DB init, gated `initDatabase`), `openfga-pdb.yaml` (≥3 replicas в prod).

KAC-135 W0.4: `values.dev.yaml` → `openfga.replicaCount: 2` (HA-mini для kind). Prod уже имел 3.

## Текущее runtime-поведение (после W0 закрытия)

| Путь | Поведение |
|---|---|
| `AccessBindingService.Create` | sync `WriteTuples` (relation + project-hierarchy); KAC-127 — `non-fatal Warn` на FGA error → split-brain DB/FGA (finding #16). |
| `AccessBindingService.Delete` ([[../KAC/KAC-128]]/[[../KAC/KAC-131]]/[[../KAC/KAC-133]]) | sync `DeleteTuples` — частично исправлен (account+project scope, account-scoped binding bug fixed). |
| JIT auto/pending-approve | НЕ пишет в FGA ([[../KAC/KAC-127]] findings #50/#51) — pure DB INSERT, no tuple. |
| BreakGlass.ApproveB | НЕ пишет в FGA (finding #52). |
| ComplianceReport foreign-deny ([[../KAC/KAC-133]]) | 4 intentional RED #37 — починим в W1 Chunk 2 root-cause. |

## Цель W1 (next Wave)

Заменить прямой sync HTTP-write на запись через `fga_outbox` (in-process drainer на corelib outbox-pattern). Атомарно с DB-row в одной tx; drainer применяет к OpenFGA с retry + идемпотенцией. Закрывает findings #8/#16/#47/#48/#50/#51/#52.

> [!important] Outbox-таблица `fga_outbox` существует (migration 0002) с NOTIFY-триггером, но **drainer'а, который её читает, НЕТ** — только `bootstrap_admin` пишет в неё, никто не дренит. W1 задача — построить drainer (corelib outbox-pattern + LISTEN `kacho_iam_fga_outbox`).

## История

- 2026-05-23 (W0): bootstrap-job верифицирован (Secret `openfga-model-id`, sha256 annotation, HA-mini 2 replicas).
- Планируется W1: sync writes → `fga_outbox` + drainer; cache invalidation на revoke.

#edge #kacho-iam #kacho-deploy
