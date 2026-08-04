---
title: PlacementGroup + Vocabularies (compute) — пересборка 2026
aliases:
  - PlacementGroup (compute)
  - CapabilityVocabulary
  - TopologyVocabulary
  - compute placement
category: resource
domain: compute
id_prefix: "plg (заявлен планом; NewID его не эмитит)"
owner_table: "нет — таблицы placement_groups в дереве не существует"
owner_db: kacho_compute
project_level: false
status: planned
verified_against: "ствол redesign/integration, сверено 2026-08-05"
related_rpc:
  - "[[rpc/compute-instance-service]]"
related_tickets:
  - "[[KAC/compute-redesign-2026]]"
tags:
  - resource
  - kacho-compute
  - compute
  - planned
---

# PlacementGroup + Vocabularies (compute) — ЗАМЫСЕЛ, не дерево

> [!warning] Ресурса `PlacementGroup` в продукте НЕТ — читать как проект, а не как описание
> Сверено по стволу 2026-08-05, три независимых предиката:
>
> 1. **Схема**: в `services/compute/internal/migrations/` таблицы `placement_groups` нет
>    (живых таблиц compute семь: `instances`, `machine_types`, `instance_network_interfaces`,
>    `operations`, `compute_outbox`, `compute_fga_register_outbox`, `compute_watch_cursors`).
> 2. **Контракт**: файла `placement_group.proto` в `proto/kacho/cloud/compute/v1/` нет;
>    сообщение `PlacementPolicy` **отозвано целиком** — комментарий в `instance.proto`
>    объясняет почему: оно несло `placement_group_id`, `host_affinity_rules`,
>    `placement_group_partition`, и **ни одно поле ни одного message ни в одном пакете
>    не имело этого типа** — сирота. Плюс правило hosts/host-groups — инфра-чувствительная
>    поверхность, которой на публичном контракте не место (`security.md`).
> 3. **Замок в обе стороны**: `pkg/api/kacho/cloud/compute/v1/placement_contract_test.go`
>    несёт `TestWithdrawnPlacementMessagesAreGone` (отозванное не вернулось) **и**
>    `TestLivePlacementGroupIdSurvives` (живое не снесли заодно).
>
> **Что живо и это омоним, а не тот же предмет**: `Instance.placement_group_id` (поле 41) —
> **непрозрачный slug-passthrough** COMP-1; существование и когерентность отложены до COMP-3.
> Он не ссылается ни на какой ресурс и ресурсом не управляет. Плюс отдельный
> `DiskPlacementPolicy`, доступный через `Relocate`, — тоже другой предмет.
>
> Ниже — **проектная запись** (замысел пересборки), а не контракт. Ни одна её координата не
> должна использоваться как утверждение о нынешнем состоянии: ни `kacho_compute.placement_groups`,
> ни `InternalPlacementGroupService`, ни словари `capability`/`topology` в дереве не заведены.

Tenant placement-**intent** над непрозрачными failure-domain. Задумывался как замена
single-`oneof{spread|partition}` из снятого `placement_group.proto`. Полный дизайн —
`docs/plans/compute-module-redesign-2026.md §1.4-1.6, §4` (в воркспейсе).

## PlacementGroup (`plg`) — композируемые constraints (фикс defect 3)
`constraints[]` — **конъюнктивный** список (ANDed), а не одна стратегия:
```jsonc
{ "placementType": "REGIONAL", "regionId": "ru-1",   // ⊘ ZONAL|REGIONAL coherence-дискриминатор
  "constraints": [
    { "topologyKey": "availability",     "mode": "SPREAD", "maxSkew": 1, "enforcement": "REQUIRED"  },
    { "topologyKey": "network-locality", "mode": "PACK",                 "enforcement": "PREFERRED" } ] }
```
- `topologyKey` — **A: FK → topology_vocabulary** (opaque curated, тенант видит абстракцию, не rack/switch).
- `mode ∈ {SPREAD (anti-affinity), PACK (affinity)}`; `maxSkew` (SPREAD); PARTITION = SPREAD+maxSkew=k (не отдельная стратегия).
- `enforcement ∈ {REQUIRED (hard, reject), PREFERRED (soft, weights)}`.
- «spread-зоны + pack-стойка» = **один PG, два constraint'а**.
- Instance вступает: `Instance.placementGroupId` (class-A FK, SET NULL).

**Что видит тенант** — `status ∈ {SATISFIED|DEGRADED|PENDING}` + `constraintStatus[]` **ТОЛЬКО счётчики** (`spreadWidth`/`packedInto`), НИКОГДА идентичности домена. `members[]` = C-reverse Reference. Реальные домены+ноды — `InternalPlacementGroupService.GetInternal.memberAssignments` (:9091).

## CapabilityVocabulary (slug key, Mixed) — фикс defect 4
Admin-curated allow-list абстрактных capability, которые тенант может *требовать* через `Instance.capabilityRequirements[]`. `{key, kind(GPU|ACCELERATOR|STORAGE_CLASS|CPU_ARCH|FEATURE), valueType(ENUM|QUANTITY|BOOL), allowedValues[], operators[]}`. Секрет `capability→host-label` (`nvidia.com/gpu.product`) — **Internal-only**. Тенант узнаёт лишь match/no-match (`FAILED_PRECONDITION "insufficient capacity for capability %s in zone %s"`), никогда host-label/node-id.

## TopologyVocabulary (slug key, Mixed)
**Ортогональная** плоскость (топология ≠ capability — привито от cloud-native-линзы). Curated opaque failure-domain *tier*-ключи для PlacementGroup: `{key, tier, spreadSupported, packSupported}`. Секрет `topologyKey→real-axis` (rack/power-feed) — **Internal-only**.

## NodePool / NodePoolBinding — Internal\* only (mold AddressPool)
Нет публичного API. `system_admin` + `required_acr_min=2` + `scope object_type='cluster'`. Тенант тянет слот вслепую: `FOR UPDATE SKIP LOCKED LIMIT 1` + capacity-CAS `UPDATE…SET used=used+1 WHERE free>0 RETURNING`. `NodePoolBinding` confine project→pool label-каскадом (project_default → zone_default → global). Growth-seam: reconciler `ClaimWork`/`ReportStatus`.

## DB-инварианты (ban #10)
`placement_type` CHECK биконд. `(ZONAL∧zone_id<>''∧region_id='')∨(REGIONAL∧…)` · SPREAD `EXCLUDE (placement_group_id WITH =, failure_domain WITH =)` · `capability_requirements` FK значение∈vocab · `topology_key` FK→topology_vocabulary · Instance⇄PlacementGroup zone-coherence в link-CAS predicate. Concurrent-race integration-тест обязателен (ban #12).

**Рост = curated-data:** новое железо → строка в vocab (без proto-изменений); новый constraint-`mode`/`enforcement` — additive; `placementBindings[]` (multi-policy) — growth-hook.

#resource #kacho-compute #compute #planned
