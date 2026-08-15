---
title: nlb-tests-newman
aliases:
  - nlb newman suite
category: packages
repo: kacho-nlb
layer: tests
tags:
  - packages
  - kacho-nlb
  - tests
  - newman
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): имя и триггеры рабочего процесса e2e, число коллекций суиты nlb; текст записки построчно не пересматривался"
---

# kacho-nlb/tests/newman

**Каталог**: `services/nlb/tests/newman/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-nlb/tests/newman/`)
**Tooling**: Python `cases/*.py` → `gen.py` → newman collection JSON → `newman run` against api-gateway.
**Pattern**: Adopted from kacho-vpc/tests/newman (declarative case-py → collection generator).

## Files

| File | Coverage |
|---|---|
| `_helpers.py` | shared utilities: project fixture, auth bootstrap, polling helpers |
| `load-balancer.py` | NLB-* cases: CRUD + Start/Stop/Move/Attach/Detach + GetTargetStates |
| `listener.py` | LST-* cases: create/wire targetGroupId, immutable Update reject, port BVA, delete |
| `target-group.py` | TGR-* cases: CRUD + Move, embedded health_check ranges |
| `targets.py` | TGT-* cases: AddTargets (4 identity-types × idempotent), RemoveTargets 2-phase drain |
| `operation.py` | OP-* cases: poll done=true + Cancel idempotent |
| `authz-deny.py` | AZD-* cases: ≥30 authz-deny scenarios (no-role, wrong-project, ErrNoPath race) |

## Coverage matrix (~320 cases)

100% RPC × class matrix:
- 4 services × ~3 method-classes (sync read / async mutation / authz) × ~12 cases each
- + ≥30 authz-deny (AZD-*) per acceptance D-1..D-6
- + 4-way Target identity matrix × 4 happy + 4 negative each
- + 5 health_check types × ranges
- + Operation polling + Cancel
- + 2-phase drain timing (Phase A immediate, Phase B after dereg_delay)

**Total**: 320+ cases / 0 failures (KAC-141 DoD).

## Case-id prefixes

- `NLB-NNN` — NetworkLoadBalancer
- `LST-NNN` — Listener
- `TGR-NNN` — TargetGroup CRUD
- `TGT-NNN` — Targets Add/Remove
- `OP-NNN` — Operation
- `AZD-NNN` — Authz deny

## CI integration

`.github/workflows/e2e-newman.yml` (имя именно в таком порядке — прежняя редакция
переставляла половины местами, и координата не резолвилась) — стенд поднимается **в kind**,
не docker-compose: шардированная матрица, 82 коллекции восьми суит, из них **9 — nlb**.
Триггеры: `pull_request` в `main`, `push` в `redesign/integration`, ручной запуск. То есть
gating для merge в `main` — да, но стенд и раскладка другие, чем описывала записка.

## See also

[[nlb-tests-k6]] [[../KAC/KAC-141]] [[../rpc/nlb-network-load-balancer-service]]

#packages #kacho-nlb #tests #newman
