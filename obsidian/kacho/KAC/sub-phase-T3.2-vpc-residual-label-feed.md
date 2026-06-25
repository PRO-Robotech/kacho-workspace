---
title: "vpc residual label-feed: routeTable/address/gateway/NIC (T3.2 / #113-residual)"
aliases:
  - sub-phase-T3.2-vpc-residual-label-feed
  - "#113 residual label-feed"
ticket_id: "GH PRO-Robotech/kacho-vpc#10"
category: kac
status: done
type: fix
repos:
  - kacho-vpc
  - kacho-iam
prs:
  - "https://github.com/PRO-Robotech/kacho-vpc/pull/11"
  - "https://github.com/PRO-Robotech/kacho-deploy/pull/134"
tags:
  - kac
  - fix
  - kacho-vpc
  - kacho-iam
  - cross-service
  - security
---

# vpc residual label-feed: routeTable/address/gateway/NIC (T3.2 / #113-residual)

> [!note] Трек
> GitHub issue `PRO-Robotech/kacho-vpc#10` (bug). Закрывает явно отложенный «остаточный gap» родительского T3.1 §3.1. Acceptance ✅ APPROVED (`acceptance-reviewer`, 2026-06-25): `docs/specs/sub-phase-T3.2-vpc-residual-label-feed-acceptance.md`. Найдено живым прогоном fe3455 (under-show).

**Status**: ✅ done — vpc PR [kacho-vpc#11](https://github.com/PRO-Robotech/kacho-vpc/pull/11) merged; image `main-4987b56e` live via fe3455 ([kacho-deploy#134](https://github.com/PRO-Robotech/kacho-deploy/pull/134)). Все 7 vpc-типов теперь питают labels+parent в IAM mirror (4 остаточных типа закрыты).
**Type**: fix

## Что и зачем

4 vpc-ресурса — **routeTable / address / gateway / networkInterface** — регистрировали owner-tuple в kacho-iam `resource_mirror` через bare `RegisterIntent(ProjectHierarchy(...))`: **без labels и без parent_project_id** на Create, и **не переэмитили вообще** на Update. labels корректно лежат в vpc DB, но IAM-зеркало их не получало → label-селекторный ARM_LABELS-грант **никогда не материализовался** (granted-юзер: 0 в List, 403 на detail даже для matching-label) и **не ревокался** при смене метки. Тот же класс, что securityGroup/listener double-bug из T3.1 — но эти 4 типа T3.1 осознанно отложил (меньший spread).

## Фикс (эталон network/subnet/securityGroup)

- **Create** ×4 → `RegisterItems(ProjectHierarchyItem(projectID, <vpc_type>, id, LabelsToMap(labels)))` — labels + parent_project_id в той же writer-TX, что и Insert.
- **Update** ×4 → `labelsInMask`-gated re-emit `RegisterItems` в той же writer-TX, что и UPDATE (revoke при снятии метки; полное снятие → upsert с пустыми labels, НЕ Unregister; не-label Update → no-op, G-2; empty mask full-PATCH → emit).
- **parent_project_id для всех 4 = собственный ProjectID ресурса** (G-9) — parent в mirror-смысле всегда project, не network/subnet.
- FGA-типы: `vpc_route_table` / `vpc_address` / `vpc_gateway` / `vpc_network_interface`.
- proto / схема БД — без изменений (`RegisterResourceRequest` уже несёт labels/parent_project_id/source_version; миграций нет).

## Ключевые решения (reuse G-1..G-5, G-7 из T3.1; NEW G-9)

- G-2: эмит только при labels-в-маске (gated); empty-mask full-PATCH ⇒ эмитить.
- G-3: полное снятие меток → upsert с пустым labels, НЕ Unregister (ресурс жив).
- G-4: intent в той же writer-tx (SEC-D, no dual-write).
- G-9 (NEW): parent_project_id = собственный ProjectID для всех 4.

## TDD RED→GREEN (integration, testcontainers Postgres 16)

`internal/repo/{routetable,address,gateway,networkinterface}_fga_register_integration_test.go`:
- `Test<R>Repo_T32Create01_CreateEmitsLabels_UpdateRevokes` ×4 — Create-emits-labels + Update-revoke + non-label-idempotency.
- `Test<R>Repo_T32FullPatch01_EmptyMaskEmits` ×4.
- `TestNetworkInterfaceRepo_T32Atom01_RollbackNoIntent` — atomicity (rollback → no intent).
- `TestRouteTableRepo_T32Conc01_ConcurrentLabelFlip_LastSourceWins` — race, `-race` clean, last-source-wins (data-integrity §5).
RED: на origin/main баг живой (bare tuple, нет re-emit). GREEN после фикса. T31 network+SG non-regression зелёные.

## Затронутые сущности vault

[[../resources/iam-resource-mirror]] [[../edges/vpc-to-iam-fgaproxy]] [[../resources/vpc-routetable]] [[../resources/vpc-address]] [[../resources/vpc-gateway]] [[../resources/vpc-networkinterface]]

## DoD

- [x] GitHub Issue остаточного gap ([kacho-vpc#10](https://github.com/PRO-Robotech/kacho-vpc/issues/10))
- [x] acceptance APPROVED (T3.2)
- [x] KAC-trail
- [x] kacho-vpc: Create+Update emit ×4 + integration RED→GREEN (PR [kacho-vpc#11](https://github.com/PRO-Robotech/kacho-vpc/pull/11)) — merged
- [x] fe3455 deploy bump (`main-4987b56e`, [kacho-deploy#134](https://github.com/PRO-Robotech/kacho-deploy/pull/134))
- [x] vault trail после merge (edges History — [[../edges/vpc-to-iam-fgaproxy]])

## Связанные

- [[sub-phase-T3.1-cross-service-label-revoke]] — родитель (#113); тот же эталон-паттерн + IAM revoke-путь
- [[KAC-113]]

#kac #fix #cross-service #kacho-vpc #kacho-iam #security
