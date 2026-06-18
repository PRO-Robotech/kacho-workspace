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
  - "[[../KAC/sub-phase-1.4-tuple-resource-guarantee]]"
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

## Текущее runtime-поведение (после W1.5 [[../KAC/KAC-163]] + sub-phase 1.4 S2)

| Путь | Поведение |
|---|---|
| `bootstrap_admin` | ✅ INSERT в `fga_outbox` → **drainer** ([[../packages/corelib-outbox-drainer]]) применяет к OpenFGA. End-to-end verified. |
| `AccessBindingService.Create` | ✅ atomic via `fga_outbox` (KAC-163 W1.5) — emit-in-tx с domain INSERT. |
| `AccessBindingService.Delete` ([[../KAC/KAC-128]]/[[../KAC/KAC-131]]/[[../KAC/KAC-133]]) | ✅ atomic via `fga_outbox` (KAC-163 W1.5) — emit-in-tx с domain DELETE. |
| JIT auto-grant / pending-approve / expiry | ✅ atomic via `fga_outbox` (KAC-163 W1.5) — был wrong `EmitSubjectErasure` (CAEP-deletion!), заменён на правильный FGA grant/revoke. |
| BreakGlass.ApproveB | ✅ atomic via `fga_outbox` (KAC-163 W1.5) — `cluster_admin_grants` INSERT + FGA emit в одной tx (mirror bootstrap_admin). |
| **Owner/hierarchy tuple для СОБСТВЕННЫХ iam-ресурсов** (Account/Project/Group/ServiceAccount/Role + bootstrap `UpsertFromIdentity`) | ✅ **atomic via `fga_outbox` (sub-phase 1.4 S2, iam #161)** — был **best-effort POST-COMMIT** `relationhook.WriteHierarchyTuple` (терялся при крэше между commit'ом ресурса и tuple-write). Перенесён ВНУТРЬ writer-tx через новые `Writer.EmitFGARelationWrite` / `EmitFGARelationDelete` → co-commit в существующий `kacho_iam.fga_outbox`; тот же in-process live drainer (`clients/fga_applier.go` → `RelationStore.WriteTuples`, idempotent FGA-409→success) доставляет. **Без новой миграции** (`fga_outbox` уже в `0001`). Гарантирует: owner-access tuple НИКОГДА не теряется при Create ресурса. |
| ComplianceReport foreign-deny ([[../KAC/KAC-133]]) | 4 intentional RED #37 — починим в W1.6 (Chunk 2). |

> [!note] iam делает SEC-D-паттерн для своих ресурсов in-process
> Это тот же owner-tuple co-commit, что consumer-сервисы делают через api ребро
> [[vpc-to-iam-fgaproxy]] / [[compute-to-iam-fgaproxy]] (RegisterResource по mTLS).
> Разница: iam — leaf-owner своих ресурсов, поэтому пишет tuple **in-process**
> (свой `fga_outbox` + свой drainer), не через сетевой RPC к самому себе.

## ✅ W1.1 ([[../KAC/KAC-137]]) — drainer foundation done

corelib generic `Drainer[T]` + concrete `FGAApplier` в kacho-iam + wiring в main.go.
**Bootstrap-admin tuple реально применяется к OpenFGA** — root cause 87 newman failures (без drainer ВСЕ authz Check fails-because-no-tuple на свежем стенде).

## Цель W1.5 (next chunk)

Заменить sync `WriteTuples` в AccessBinding/JIT/BreakGlass → atomic `outbox.Emit` в той же tx + drainer применяет с retry + идемпотенцией. Закрывает findings #8/#16/#47/#48/#50/#51/#52 (DB/FGA grant-write desync).

## История

- 2026-05-23 (W0): bootstrap-job верифицирован (Secret `openfga-model-id`, sha256 annotation, HA-mini 2 replicas).
- 2026-05-23 (W1.1, [[../KAC/KAC-137]]): **drainer foundation done** — bootstrap-admin grants реально применяются. corelib `outbox/drainer/` (3 commits) + kacho-iam wiring (2 commits). 17/17 tests GREEN.
- 2026-05-24 (W1.5, [[../KAC/KAC-163]]): ALL grant/revoke routed через fga_outbox в same writer-tx (AB Create/Delete + JIT activate/approve/expire + BG.ApproveB). PermissionsToRelations supersedes name-based mapping. Closes 7 findings.
- 2026-06-18 (sub-phase 1.4 S2, iam #161): owner/hierarchy-tuple для **собственных** iam-ресурсов (Account/Project/Group/SA/Role + bootstrap UpsertFromIdentity) перенесён из best-effort POST-COMMIT `relationhook.WriteHierarchyTuple` ВНУТРЬ writer-tx (`Writer.EmitFGARelationWrite`/`EmitFGARelationDelete` → co-commit в `fga_outbox`). Без новой миграции (fga_outbox в 0001). Гарантия: owner-access tuple не теряется при Create. AccessBinding.Create + seed bootstrap уже были атомарны. Merged + live `fe3455` rev13.
- 2026-06-18 (sub-phase 1.4, corelib #26 — INCIDENT A07 starvation): S0 `attempt_count`-cap + старый claim `ORDER BY id` дали head-of-line starvation (backlog transient-low-id затеняет свежие higher-id intent → at-least-once нарушен). Фикс — claim `ORDER BY attempt_count, id`. Поймано red-тестом `kacho-iam/TestRegisterResource_A07_FGADownIntentPersistsAcrossRestart` на main; гард `Test_1_4_24_TransientBacklog_DoesNotStarveFreshIntent`. Детали — [[../packages/corelib-outbox-drainer]].

#edge #kacho-iam #kacho-deploy
