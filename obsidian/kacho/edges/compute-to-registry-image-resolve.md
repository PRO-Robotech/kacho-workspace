---
title: compute → registry (bootSource image resolve)
aliases:
  - compute-to-registry
  - bootSource resolve
category: edge
caller_repo: kacho-compute
callee_repo: kacho-registry
sync_async: sync
protocol: gRPC (request-path)
status: planned
related_tickets:
  - "[[KAC/compute-redesign-2026]]"
tags:
  - edge
  - kacho-compute
  - kacho-registry
  - cross-service
  - planned
---

# compute → registry (bootSource image resolve)

**НОВОЕ ребро** пересборки-2026 (`docs/plans/compute-module-redesign-2026.md §7`). Возникает из фикса defect 1+2: доставка ОС Instance унифицирована на **OCI-image из registry** (`bootSource: Referrer{registry.image}`), block-`Image`(qcow2) ретайрен.

## Что делает
На `Instance.Create` (и `Reinstall`) compute резолвит `bootSource` **tag → digest** через registry + проверяет existence:
- input несёт `bootSourceTag` **XOR** `bootSourceDigest`;
- compute зовёт registry (sync, request-path) → резолвит tag в content-address;
- сторит **только** `bootSourceDigest⊘` (immutable пин, воспроизводимо); `bootSourceTag°` — provenance-echo.

## Протокол / контракт
- **sync** на request-path (мутация ждёт резолв).
- **fail-closed**: registry недоступен/5xx → мутация `Unavailable` (fail-closed для мутаций, никогда allow/silent-skip).
- Далее (VM) compute материализует boot-Volume в storage ИЗ разрешённого digest ([[edges/compute-to-vpc-nic-validate]]-подобный owner-паттерн, но к storage).

## Ацикличность (holds)
`compute → registry` одностороннее. registry зовёт iam (jwks/Check) — **не** compute. Циклов нет. Фиксируется в `polyrepo.md` как runtime-edge.

## History
- **2026-07 (redesign-2026)**: ребро введено — унификация OS-delivery на OCI (bootSource polymorphic Referrer). Pre-acceptance (ban #1). Growth: `bootSource` полиморфен → reinstall-from-snapshot / clone-from-volume как новые Referrer-цели без изменения ребра.

Связано: [[resources/compute-instance]], [[edges/compute-to-iam-check]], [[resources/registry-repository]].

#edge #kacho-compute #kacho-registry #cross-service #planned
