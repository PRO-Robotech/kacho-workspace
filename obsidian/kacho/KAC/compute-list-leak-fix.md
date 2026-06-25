---
title: "compute List label-scope over-show leak fix — subject-source mismatch"
ticket_id: compute-list-leak-fix
status: done
type: fix
repos:
  - kacho-compute
prs:
  - https://github.com/PRO-Robotech/kacho-compute/pull/65
  - https://github.com/PRO-Robotech/kacho-deploy/pull/134
opened: 2026-06-25
closed: 2026-06-25
tags:
  - kac
  - kacho-compute
  - fix
  - authz
  - fga
  - handler
  - race-fix
---

# compute List label-scope over-show leak — subject-source mismatch

**Status**: done — PR [`kacho-compute#65`](https://github.com/PRO-Robotech/kacho-compute/pull/65) merged; image `main-e5634e60` live via fe3455 ([kacho-deploy#134](https://github.com/PRO-Robotech/kacho-deploy/pull/134)). List subject теперь из `operations.PrincipalFromContext`, fail-closed на пустом subject.
**Type**: fix — критический security (over-show leak), найден live-E2E на ревизии fe3455
**Acceptance**: `docs/specs/sub-phase-compute-list-leak-fix-acceptance.md` (✅ APPROVED, CLL-01..07)

## Что и зачем

Публичный `List` (Instance/Disk/Image/Snapshot) под label-scoped FGA-грантом возвращал **все**
ресурсы проекта вместо разрешённого подмножества — утечка existence+metadata чужих ресурсов мимо
list-authz. Per-RPC `Check` на detail (`Get`) работал (403); утечка только в листинге.

**Корень (subject-source mismatch):** `internal/handler/list_filter.go::resolveListFilter` брал
FGA-subject через `authzfilter.SubjectFromCtx` из gRPC-метадаты `x-kacho-subject` /
`x-kacho-subject-type`+`-id` / `x-kacho-actor`. api-gateway этих заголовков **не шлёт** (шлёт
`x-kacho-principal-type`/`-id`; actor=email с `@` отбрасывался). Итог: subject="" →
короткозамыкание на `bypass:true` → возврат всех строк **до** FGA-фильтра (который сам fail-closed'ит
на subject=""). kacho-vpc/kacho-nlb корректны — берут subject из principal.

## Фикс

- subject из **request Principal**: `authzfilter.SubjectFromPrincipal` →
  `operations.PrincipalFromContext` → `"type:id"` (единый источник с per-RPC Check и эталоном
  kacho-vpc `pbconv.SubjectFromContext`). Мёртвый header-источник `x-kacho-subject*` удалён.
- **subject="" → fail-closed** (пустой allow-list → пустой List), НЕ bypass-all.
- cluster-admin/owner видят всё через сам IAM `ListObjects(viewer)` (owner→viewer каскад);
  compute-side `x-kacho-admin` header-bypass удалён (dead в prod).
- `filter==nil` (FGA disabled) — осознанный config-off bypass.

## TDD RED→GREEN

- RED: `SubjectFromPrincipal` undefined (compile-fail); handler CLL-тесты на principal-пути давали
  bypass-all (broken impl не видел principal) → CLL-02 no-principal возвращал все 3 диска (точная prod-утечка).
- GREEN: principal-subject + fail-closed → label-scoped видит ровно подмножество; no-principal → пусто.

## Затронутые сущности vault

- [[../edges/compute-to-iam-listobjects]] — identity-source + fail-closed (History 2026-06-25).
- [[../edges/compute-to-iam-check]] — тот же principal-источник subject.
- [[../edges/apigw-to-compute]] — api-gateway шлёт `x-kacho-principal-*`, не `x-kacho-subject*`.

## DoD

- [x] APPROVED acceptance (gate ban #1).
- [x] RED→GREEN unit (authzfilter + handler) + integration (testcontainers) + newman (`LF-INST-LST-OVERSHOW-LEAK-GUARD`).
- [x] `go build`/`vet`/`gofmt`/`-race` + `make audit-list-filter` зелёные локально.
- [x] PR #65 merged, CI зелёный.
- [x] Merge + deploy fe3455 (`main-e5634e60`, [kacho-deploy#134](https://github.com/PRO-Robotech/kacho-deploy/pull/134)).

## Связанные

[[KAC-127]] (Phase 4 list-filter wiring) · [[rbac-2026-contract-a-fix-iam-content-forward]] (label-grant content forward).

#kac #kacho-compute #fix #authz #fga #handler #race-fix
