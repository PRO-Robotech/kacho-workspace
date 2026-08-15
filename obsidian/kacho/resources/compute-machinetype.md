---
title: MachineType (compute) — sync sizing catalog
aliases:
  - MachineType (compute)
  - machineType
  - machine_types
category: resource
domain: compute
id_prefix: "mt- (hyphen-канон B3; NewHyphenID)"
owner_table: kacho_compute.machine_types
owner_db: kacho_compute
project_level: false
status: done
verified_against: "ствол redesign/integration, сверено 2026-08-05 (machine_type.proto, machine_type_service.proto, internal_machine_type_service.proto, migrations 0015/0017)"
related_rpc:
  - "[[rpc/compute-machinetype-service]]"
related_tickets:
  - "[[KAC/compute-redesign-2026]]"
tags:
  - resource
  - kacho-compute
  - compute
  - done
---

# MachineType (compute) — sync sizing catalog

**Единственный канал sizing** для redesign-Instance (COMP-1 F2/F7): tenant выбирает размер из каталога до launch; `Instance.machineTypeId` резолвит `effectiveResources°` из этой записи (retire raw `ResourcesSpec`/`platform_id`, ban 2). Landed COMP-1 F7 (`services/compute/internal/{domain,repo,service,handler}/machine_type*`, migration `0015_machine_types.sql`).

## Модель
- Flat: `id`(`mt-<base32>`, canonical), `name`(стабильный slug, `UNIQUE` кластер-scoped — альт-референс на `machineTypeId`), `description`, `family∈{STANDARD,COMPUTE,MEMORY,GPU}`, `effectiveResources°{vCpu,memoryMiB(**MiB** не байты),gpus,gpuType}`, `availableZones°[]`, `status∈{AVAILABLE,DEPRECATED,RETIRED}`, `labels`, `createdAt°`.
- `effective_resources` распакованы в скалярные колонки (`v_cpu`/`memory_mib`/`gpus`/`gpu_type`) → `minGpus=` индексируемый предикат. `family`/`status` — DB-CHECK enums.
- **GPU-count = гранулярность каталога** (`gpu-a100-1/-2/-4/-8`), НЕ поле запроса. `cpuGuaranteePercent` применим только к STANDARD/COMPUTE/MEMORY (GPU — accepted-and-ignored).

## Поверхность / lifecycle
- Public read **ambient** (project-scope EXEMPT, как geo-каталог): `MachineTypeService.Get`/`List` (:9090, filter `name=`/`family=`/`minGpus=`). malformed `mt-` id → InvalidArgument first-statement; well-formed-нет → NotFound.
- Admin CRUD — **`InternalMachineTypeService`** (:9091, `/compute/v1/internal/machineTypes`, `system_admin`, mTLS), НИКОГДА на external mux (ban 6; парити geo `/geo/v1/internal/…`). Мутации async `Operation`.
- Bookable: AVAILABLE+DEPRECATED (DEPRECATED discouraged, compat); **RETIRED → reject на Instance.Create** (FailedPrecondition).

Trail: [[KAC/compute-redesign-2026]]. Acceptance: `docs/specs/sub-phase-COMP-1-instance-machinetype-acceptance.md`.

#resource #kacho-compute #compute #done
