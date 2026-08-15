---
title: Compute module — пересборка 2026
aliases:
  - compute-redesign-2026
ticket_id: (pending — sub-эпик kacho-workspace#132)
status: planned
type: refactor
repos:
  - kacho-proto
  - kacho-compute
prs: []
yt_url: ""
opened: 2026-07-19
closed: ""
category: kac
tags:
  - kac
  - refactor
  - kacho-compute
  - planned
---

# Compute module — пересборка 2026

**Status:** planned · alignment-doc (ban #1 — код ПОСЛЕ `acceptance-reviewer` APPROVED). Sub-эпик [[KAC/CS-1-storage-network-disk|kacho-workspace#132]] (compute/storage split).

## Что и зачем
Владелец назвал 5 дизайн-косяков текущего compute (2026-07-19). Пересобрано через multi-agent design (3 линзы: cloud-native-2026 / kacho-purist / growth-maximalist → судейство → синтез; основа-победитель kacho-purist). Полный дизайн: `docs/plans/compute-module-redesign-2026.md` (559 строк, полный JSON каждого ресурса public+Internal\*).

## 5 дефектов → фиксы
1. **image vs boot_volume** дублируют «откуда ОС» → `bootSource⊘`(polymorphic Referrer) → materialized `bootVolume°` (VM only; Container ephemeral). Развязка по lifecycle.
2. **digest + tag** избыточны → один immutable `bootSourceDigest⊘`; `bootSourceTag°` provenance-echo.
3. **PlacementGroup single-enum** не композится → `constraints[]` `{topologyKey,mode(SPREAD|PACK),maxSkew,enforcement(REQUIRED|PREFERRED)}`.
4. **node_selector течёт на гиперы** → `capabilityRequirements[]` над curated `CapabilityVocabulary` (+ `TopologyVocabulary`); node-targeting невыразим by construction.
5. **ref-разнобой** → **the reference law**: A within-service flat+FK · B scope-coord flat+peer-validate · C dependency `Referrer`(fwd)/`Reference`(rev).

## Бонус
Разбирает YC-derived cruft текущего proto (`platform_id`, `host_affinity_rules{yc.hostId}`, `MetadataOptions{gce_*/aws_*}`, free-form `Resources`) — нарушения ban #2.

## Затронутые сущности vault
- [[resources/compute-instance]] (пересборка) · [[resources/compute-placementgroup]] (+ Capability/TopologyVocabulary)
- [[edges/compute-to-registry-image-resolve]] (НОВОЕ ребро — OS-delivery via OCI)
- baseline: `docs/plans/storage-compute-iaas-overview.md §1` · [[KAC/CS-1-storage-network-disk]] · `kacho-storage-volume-and-instance-attach-spec.md`

## DoD-чеклист
- [ ] `acceptance-author` Given-When-Then → `acceptance-reviewer` APPROVED (ban #1)
- [ ] proto (kacho-proto) — `instance.proto`/`placement_group.proto` пересборка + `Referrer`/`Reference` refs; retire legacy Image/YC-cruft
- [ ] TDD-red → GREEN (migration/repo/handler/outbox), топо-порядок proto→corelib→compute→gateway
- [ ] newman (VM/Container create, bootSource resolve, placement composition, capability match, anti-node-targeting negatives)
- [ ] KAC-номер + ветки + PR-ссылки сюда

## Связанные
[[KAC/CS-1-storage-network-disk]] · [[KAC/RG-1-registry-repository-overlay]] · [[resources/registry-repository]]

## Прогресс — COMP-1 (landed 2026-07-20, `project/kacho`)

**COMP-1 core = Instance core + MachineType sync-каталог — GREEN, committed** (ветка `redesign/compute-1`, не запушено).
- F7 MachineType sync-каталог + `InternalMachineTypeService` (:9091) — landed (prior commit) → [[resources/compute-machinetype]].
- Instance redesign — landed: `instanceKind` oneof `vmSpec`/`containerSpec`; `machineTypeId` single sizing channel + `effectiveResources°`; `bootSource{type,id}`+`imageKind` **form-only** (grammar/type-whitelist/bare-reject, resolve/materialize→COMP-2); `serviceAccountId`→class-C `reference.Referrer{iam.service_account}` (B2, per acceptance F4 — переклассифицирован из §reference-law class-B); vendor-agnostic `metadataOptions`; **massive vendor-cruft retire** (ban 2, buf-breaking намеренный); unreachable-guard; launch-`*Specs` skeleton; `placementGroupId` opaque passthrough; two-projection; Create rests **PROVISIONING**; Update mutability-классы + **STOPPED-gate always-reject**; Delete **hard-delete + name-recycle**; `ins-` prefix (B3); migration `0016_instance_redesign.sql`.
- **compute ↔ storage раскол соблюдён**: 0 новых Image/Volume-таблиц в compute, ссылки на storage/registry/iam — только Referrer (form-only). Легаси power-ops/attach сохранены рабочими до COMP-2/4.
- Верификация: `go build ./...`, full integration (testcontainers, repo 158s), `-race` (name-race COMP-1-30 + name-recycle COMP-1-37), golangci-lint(0), govulncheck(clean), buf lint, buf breaking(intended). Тесты: COMP-1 service unit + repo integration (COMP-1-01..37), адаптированы kept-legacy тесты.
- **Deferred**: COMP-2 (attach-саги/materialize/power/Reinstall) · COMP-3 (PlacementGroup spread + discovery + validateOnly) · COMP-4 (Internal\* infra + legacy-RPC/`fd8`-Image retire) · gateway-регистрация public RPC · newman.

#kac #refactor #kacho-compute #planned
