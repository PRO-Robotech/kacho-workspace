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
  - KAC-137
  - KAC-163
tags:
  - edge
  - kacho-iam
  - kacho-deploy
  - kacho-corelib
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

## Текущее runtime-поведение (после W1.5 [[../KAC/KAC-163]])

| Путь | Поведение |
|---|---|
| `bootstrap_admin` | ✅ INSERT в `fga_outbox` → **drainer** ([[../packages/corelib-outbox-drainer]]) применяет к OpenFGA. End-to-end verified. |
| `AccessBindingService.Create` | ✅ atomic via `fga_outbox` (KAC-163 W1.5) — emit-in-tx с domain INSERT. |
| `AccessBindingService.Delete` ([[../KAC/KAC-128]]/[[../KAC/KAC-131]]/[[../KAC/KAC-133]]) | ✅ atomic via `fga_outbox` (KAC-163 W1.5) — emit-in-tx с domain DELETE. |
| JIT auto-grant / pending-approve / expiry | ✅ atomic via `fga_outbox` (KAC-163 W1.5) — был wrong `EmitSubjectErasure` (CAEP-deletion!), заменён на правильный FGA grant/revoke. |
| BreakGlass.ApproveB | ✅ atomic via `fga_outbox` (KAC-163 W1.5) — `cluster_admin_grants` INSERT + FGA emit в одной tx (mirror bootstrap_admin). |
| ComplianceReport foreign-deny ([[../KAC/KAC-133]]) | 4 intentional RED #37 — починим в W1.6 (Chunk 2). |

## ✅ W1.1 ([[../KAC/KAC-137]]) — drainer foundation done

corelib generic `Drainer[T]` + concrete `FGAApplier` в kacho-iam + wiring в main.go.
**Bootstrap-admin tuple реально применяется к OpenFGA** — root cause 87 newman failures (без drainer ВСЕ authz Check fails-because-no-tuple на свежем стенде).

## Цель W1.5 (next chunk)

Заменить sync `WriteTuples` в AccessBinding/JIT/BreakGlass → atomic `outbox.Emit` в той же tx + drainer применяет с retry + идемпотенцией. Закрывает findings #8/#16/#47/#48/#50/#51/#52 (DB/FGA grant-write desync).

## История

- 2026-05-23 (W0): bootstrap-job верифицирован (Secret `openfga-model-id`, sha256 annotation, HA-mini 2 replicas).
- 2026-05-23 (W1.1, [[../KAC/KAC-137]]): **drainer foundation done** — bootstrap-admin grants реально применяются. corelib `outbox/drainer/` (3 commits) + kacho-iam wiring (2 commits). 17/17 tests GREEN.
- 2026-05-24 (W1.5, [[../KAC/KAC-163]]): ALL grant/revoke routed через fga_outbox в same writer-tx (AB Create/Delete + JIT activate/approve/expire + BG.ApproveB). PermissionsToRelations supersedes name-based mapping. Closes 7 findings.

#edge #kacho-iam #kacho-deploy
