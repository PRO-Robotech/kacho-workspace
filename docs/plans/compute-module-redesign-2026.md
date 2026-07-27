
---

# Adjudication — три линзы по 6 критериям

| Критерий | cloud-native-2026 | kacho-purist | growth-maximalist |
|---|---|---|---|
| **convention-fit** | ⚠️ Средне — использует `Reference{referrer{…}}` как **forward**-указатель, что противоречит реальному proto (`Reference` reverse-only, `Referrer` forward). Референсифицирует within-service на wire. | ✅ **Высшая** — верно читает proto (Referrer↔forward, Reference↔reverse), верно применяет ban #10 (within-service = flat-id + FK, НЕ реф), крисп три-классовый reference-**закон**. | ✅ Высоко — верно Referrer/Reference, но референсифицирует агрессивнее (machineType как Referrer на wire) — легально, но менее pure. |
| **2026-best-practice** | ✅ Высоко | ✅ Высоко | ✅ **Высшая** (polymorphic bootSource, soft-constraint `PREFERRED`, reference-graph-узлы) |
| **growth/future-proof** | ✅ Высоко (vocab как admin-data) | ✅ Высоко | ✅ **Высшая** («рост = новый type-string / vocab-токен, не смена формы поля») |
| **изоляция/anti-leak** | ✅ **Высшая** — вводит **отдельную** `TopologyVocabulary` (2 ортогональных плоскости) | ✅ Высоко | ✅ Высоко |
| **когерентность-5-фиксов** | ✅ Высоко концептуально, слабее по reference-закону | ✅ **Высшая** — «designed out by construction», каждый фикс обоснован законом | ✅ Высоко |
| **реализм-под-TDD** | ⚠️ Средне (много новых ресурсов) | ✅ **Высшая** — крисп DB-инвариант-таблица делает TDD/DB конкретным | ⚠️ Средне (максимум поверхности) |

**Основа-победитель: `kacho-purist`.** Высшая convention-fit + когерентность + TDD-реализм — load-bearing критерии для alignment-дока перед `acceptance-reviewer`/`db-architect-reviewer`. Её три-классовый reference-**закон** — единственная защитимая развязка «ЕДИНООБРАЗНО vs FK», корректно уважающая реальный proto И ban #10, и следующая директиве storage-spec «переиспользуем существующий тип, не изобретаем UsedByRef».

**Прививаю от `growth-maximalist`:** (a) **polymorphic `bootSource`** (`registry.image` | `storage.snapshot` | `storage.volume`) — лучший future-proof для reinstall/clone/snapshot-lineage; (b) `enforcement {REQUIRED|PREFERRED}` soft-constraints; (c) `placementBindings[]` (multi-policy) как growth-hook; (d) framing «рост = добавить Referrer-type/vocab-токен»; (e) reserved growth-узлы (InstanceGroup/GpuCluster/ReservedInstancePool/Quota) как reference-граф; (f) опциональный compute-owned **Image-catalog + lineage** как growth-hook (не v1).

**Прививаю от `cloud-native-2026`:** (a) **отдельная `TopologyVocabulary`** (топология ≠ capability — две curated-плоскости); (b) counts-only `constraintStatus[].spreadWidth/packedInto` shape; (c) явные `bootSourceTag°`/provenance-echo naming; (d) `materialization`-ясность VM-vs-Container.

**Отвергаю:** cloud-native misuse `Reference` как forward-pointer (противоречит proto).

**Ключевая развязка defect-5 (отвечаю на «ВСЕ ссылки reference.Reference» прямо):** «единообразие» — это **единообразие ЗАКОНА**, применённого идентично, а НЕ единообразие wire-формы. Тенант получает **единый reference-ГРАФ**: каждое cross-service dependency-ребро — типизированный `Referrer`/`Reference` (полиморфный, reverse-index, graceful-dangling). Within-service рёбра — flat-id + **DB FK** (там граф — это сама БД, ban #10). Референсифицировать `machineTypeId`/`projectId`/`zoneId` = uniformity-ради-uniformity: спрятать FK, сломать placement-coherence-правила, добавить константный `type` в каждую запись — **менее** convention-pure, не более.

---

# Compute module — пересборка 2026 (Kachō)

**Status:** draft · alignment-only (acceptance-доки + код следуют, ban #1)
**Scope:** `kacho-compute` control-plane (Instance + sizing-каталог + placement + boot-source), рёбра к `kacho-storage`/`kacho-vpc`/`kacho-geo`/`kacho-registry`/`kacho-iam`.
**Замещает:** `storage-compute-iaas-overview.md §1` (compute-часть) + разбирает YC-derived cruft текущего `instance.proto`/`placement_group.proto`/`image.proto` (ban #2).

Все дизайны обязаны конвенциям Kachō: **flat message + async `Operation`**, own-product термины (ban #2), DB-инварианты (ban #10), one-owner-per-type + peer-validate (data-integrity.md), two-projection изоляция (security.md), ацикличность (compute зовёт всех — никто не зовёт compute обратно).

Легенда JSON: `⊘` immutable after Create · `°` output-only (SoT elsewhere / derived) · `Referrer` = `reference.Referrer{type,id,name°}` (forward) · `Reference` = `reference.Reference{referrer,type(MANAGED_BY|USED_BY),owned}` (reverse).

---

## 0. Резюме решений

### 0.1 The reference law — спина всего дизайна (фикс defect 5)

Каждый указатель классифицируется **одним трёхчастным предикатом**, применяемым идентично везде:

| Класс | Предикат | Wire-форма | Механизм целостности |
|---|---|---|---|
| **A. Within-service** | цель в compute-БД | **flat `<x>Id` string** | **same-DB FK** (ban #10) — FK *и есть* целостность и reverse-index |
| **B. Scope/placement-координата** | cross-service, единственный фикс. тип, кормит authz-scope или DB-CHECK coherence | **flat slug/id** | peer-validate fail-closed; raw-значение нужно `scope_extractor`/CHECK; mandatory, hard-fail (НЕ graceful-dangling), НЕ в used_by-графе |
| **C. Dependency-указатель** | cross-service на *owned-ресурс*, чьё имя/lineage/status тенант читает; graceful-dangling; polymorphism; кормит `usedBy` | forward = **`Referrer`** / reverse = **`Reference`** | peer-validate; без FK; dangling толерантен |

Uniform reference-граф = закон единообразен; wire-shape различна там, где ссылки структурно различны. Ноль нового proto (переиспуем `Referrer`/`Reference`).

### 0.2 Таблица «дефект → фикс»

| # | Дефект | Фикс | Ключ |
|---|---|---|---|
| 1 | `image` vs `boot_volume` дублируют «откуда ОС» | `bootSource⊘` (Referrer, immutable источник) → materialized `bootVolume°` (storage-owned, VM only; Container — ephemeral, поля нет) | source→materialized разведены по lifecycle, не по полю |
| 2 | `digest`+`tag` избыточны | Один immutable пин `bootSourceDigest⊘` (резолв tag→digest на Create через registry); `bootSourceTag°` — non-authoritative provenance-echo | content-address единственный, tag растворяется |
| 3 | `PlacementGroup` single-`oneof{spread\|partition}` не композится | `constraints[]` — конъюнктивный список `{topologyKey, mode(SPREAD\|PACK), maxSkew, enforcement}` над opaque-vocab | «spread-зоны + pack-стойка» = один PG, два constraint'а |
| 4 | `node_selector`/`host_affinity_rules(yc.hostId)` течёт на гиперы | `capabilityRequirements[]` над curated `CapabilityVocabulary`; ноль node-targeting **by construction** | тенант декларирует «ЧТО нужно», не «КУДА» |
| 5 | Не все ссылки через reference | The reference law (0.1) — uniform C-граф Referrer/Reference; A flat+FK; B flat scope | единообразие закона, не формы |

### 0.3 Что изменилось vs overview §1

| overview §1 | пересборка 2026 |
|---|---|
| `image + image_digest°` (flat string) | `bootSource⊘`(Referrer, **polymorphic** registry.image\|storage.snapshot\|storage.volume) + `bootSourceDigest⊘`(единый пин) + `bootSourceTag°`(provenance) |
| `node_selector{labels}` | `capabilityRequirements[]` (operators + curated-FK + enforcement) |
| `strategy{SPREAD\|PACK\|PARTITION}` single | `constraints[]` composable + `enforcement{REQUIRED\|PREFERRED}` |
| только `CapabilityVocabulary` | + **`TopologyVocabulary`** (ортогональная плоскость топологии) |
| cross-service refs flat string (`volume_id`,`nic_id`) | uniform **`Referrer`** (class C) + reverse `usedBy` **`Reference`**; within-service (`machineTypeId`,`placementGroupId`) — flat + **FK** (класс A явно) |
| Instance-kind/MachineType/boot-model — open (§5 q1/q2/q8) | **resolved**: instanceKind VM(v1)/CONTAINER(struct)/BAREMETAL(enum-reserved); MachineType-каталог YES; boot = polymorphic bootSource (без compute Image-каталога в v1) |

Разрешённые open-decisions overview §5: **q1** instanceKind сейчас · **q2** MachineType YES · **q3** placement owned by compute-`Internal*` (не geo, не новый svc) · **q4** control-plane slot-accounting v1 · **q8** polymorphic bootSource, Image-каталог retiring · **q9** `placementType` growth-hook reserved · **q10** discard YC-proto · **q11** idempotency-key → growth.

---

## 1. Resource model

| Resource | Owner | Prefix | Proj. | Назначение |
|---|---|---|---|---|
| **Instance** | compute | `ins` | Mixed | Унифицированный compute-unit (VM / Container / →Baremetal). Держит intent + read-only зеркала; attach-state НЕ владеет |
| **MachineType** | compute | slug | Mixed | Bookable sizing-каталог (vcpu/mem/gpu families); DiskType-parity; quota/capacity-якорь |
| **PlacementGroup** | compute | `plg` | Mixed | Tenant placement-intent — **composable** constraints над opaque topology-tiers |
| **CapabilityVocabulary** | compute | slug key | Mixed | Admin-curated allow-list абстрактных capability, которые тенант может *требовать* |
| **TopologyVocabulary** | compute | slug key | Mixed | Admin-curated allow-list opaque failure-domain *tier*-ключей (для PlacementGroup) |
| **NodePool** | compute | `npl` | **Internal\*** | Admin capacity-pool; тенант тянет слоты вслепую (AddressPool-mold) |
| **NodePoolBinding** | compute | — | **Internal\*** | Confine project→NodePool(s) label-каскадом |
| **Operation** | compute | `epd` | Public | Async LRO-envelope каждой мутации |
| *registry.image / storage.volume / storage.snapshot / vpc.networkInterface / geo.zone,region / iam.project,serviceAccount* | (peer) | — | — | Referenced (class B/C), не compute-owned |

**Two-projection контракт (load-bearing):** каждый `Mixed`-ресурс несёт lean-public message (id/name/labels/bindings/intent/`status`) **плюс** отдельную `Internal*`-message с placement/underlay/capacity/numeric-infra-id. Ни одно infra-поле не добавляется на public-message additively — gateway projection-audit (аналог `make -C services/compute audit-list-filter`) гейтит.

### 1.1 Instance — **public**

```jsonc
// compute.v1 · prefix "ins" · GET /compute/v1/instances/{instanceId}
{
  "id": "ins-7f3k9m2p4q8r1s6t",              // ⊘
  "projectId": "prj-2m8x…",                  // ⊘  B: iam scope-anchor (flat, peer→iam)
  "createdAt": "2026-07-19T10:00:00Z",       // °  Truncate(sec)
  "updatedAt": "2026-07-19T10:05:00Z",       // °  Truncate(sec)
  "name": "web-01",
  "description": "",
  "labels": { "app": "web" },

  "instanceKind": "VM",                      // ⊘  enum {VM | CONTAINER | BAREMETAL°growth}
  "placementType": "ZONAL",                  // ⊘  enum {ZONAL | REGIONAL} — coherence-дискриминатор (v1 ZONAL; REGIONAL — growth-hook)
  "zoneId": "ru-1-a",                        // ⊘  B: geo-anchor (flat, peer→geo); '' iff REGIONAL
  "regionId": "",                            // ⊘  B: '' iff ZONAL

  // ── sizing: booked catalog + derived echo (defect: free-form Resources убран) ──
  "machineTypeId": "std-v3-2",               //     A: flat + FK → machine_types (RESTRICT)
  "effectiveResources": {                    // °  DERIVED-зеркало MachineType (SoT=MachineType), НЕ free-form input
    "vcpus": 2, "memoryBytes": 8589934592, "gpus": 0, "gpuType": "", "cpuArch": "x86_64"
  },
  "cpuGuaranteePercent": 100,                //     0=burstable | 1..100 (DB CHECK); mutable только STOPPED

  // ── DEFECT 1+2: source→materialized lineage, единственный digest-пин ──
  "bootSource": {                            // ⊘  C-forward Referrer — ЕДИНСТВЕННЫЙ ответ «откуда ОС»; POLYMORPHIC:
    "type": "registry.image",                //        registry.image | storage.snapshot | storage.volume
    "id": "reg/lib/ubuntu@sha256:9f2c…", "name": "lib/ubuntu:24.04"   // name° best-effort
  },
  "bootSourceDigest": "sha256:9f2c…",        // ⊘  ЕДИНСТВЕННЫЙ content-пин (резолв на Create; воспроизводимо)
  "bootSourceTag": "24.04",                  // °  provenance-echo ONLY: «из чего резолвилось» — НЕ пин, может устареть
  "bootVolume": {                            // °  C-reverse Reference — MATERIALIZED runtime-state; VM only, ОТСУТСТВУЕТ для CONTAINER
    "referrer": { "type": "storage.volume", "id": "vol-a1…", "name": "web-01-boot" },
    "type": "USED_BY", "owned": true         //    owned=autoDelete; SoT=storage Volume.attachments
  },

  // ── DEFECT 4: capability-requirements ВМЕСТО node_selector/host_affinity_rules ──
  "capabilityRequirements": [                //     декларативные требования над curated CapabilityVocabulary
    { "capabilityKey": "gpu.model", "operator": "IN",     "values": ["a100"], "quantity": 1, "enforcement": "REQUIRED" },
    { "capabilityKey": "local.nvme", "operator": "EXISTS", "values": [],       "quantity": 0, "enforcement": "PREFERRED" }
  ],                                         //     capabilityKey — A: FK → capability_vocabulary; ноль host-label на wire

  // ── DEFECT 3: composable placement (Instance ссылается группу class-A) ──
  "placementGroupId": "plg-4b…",             //     A: flat + FK → placement_groups (SET NULL); v1 single, growth → placementBindings[]

  // ── attach-зеркала (output-only, SoT у owner'а, batched read, graceful-dangling) ──
  "secondaryVolumes": [                      // °  C-forward; SoT=storage Volume.attachments
    { "volume": { "type": "storage.volume", "id": "vol-b2…", "name": "data" },
      "deviceName": "vdb", "isBoot": false, "mode": "READ_WRITE", "autoDelete": false, "attachedAt": "2026-07-19T10:02:00Z" }  // °
  ],
  "networkInterfaces": [                      // °  SoT=vpc NetworkInterface; nic — C-forward Referrer, остальное denorm-mirror
    { "index": 0,
      "nic": { "type": "vpc.networkInterface", "id": "enp-c3…", "name": "eth0" },
      "subnetId": "e9b-sub1", "primaryV4Address": "10.0.0.5", "primaryV6Address": "",
      "securityGroupIds": ["e9b-sg1"], "macAddress": "0a:…" }
  ],

  "serviceAccountId": "sac-5t…",             //     B: iam identity-binding (flat, single-type)
  "userData": "#cloud-config\n…",            //     opaque cloud-init/ignition blob (control-plane не парсит; рендер — growth)
  "status": "RUNNING",                       // °  enum 11-state (см. ниже)
  "statusReason": "",                        // °  человекочитаемая причина (без инфра-leak)

  "usedBy": [                                // °  C-reverse Reference — polymorphic зависимые ОТ этого инстанса
    { "referrer": { "type": "loadbalancer.targetGroup", "id": "tgp-…", "name": "web-tg" }, "type": "USED_BY", "owned": false }
  ]
}
// УДАЛЕНО vs текущий instance.proto: platform_id · image+image_digest(flat) · boot_disk · secondary_disks/local_disks/filesystems(legacy)
//   · host_affinity_rules(yc.hostId/yc.hostGroupId) · MetadataOptions(gce_*/aws_*) · gpu_settings.gpu_cluster_id · fqdn(→Internal)
//   · reserved_instance_pool_id/maintenance_policy/application/scheduling_policy/network_settings/serial_port_settings/hardware_generation(→growth/Internal)
```

**`status` enum (11):** `PROVISIONING · RUNNING · STOPPING · STOPPED · STARTING · RESTARTING · UPDATING · REINSTALLING · DELETING · ERROR · CRASHED`.

**Create-input (показывает defect-1/2 развязку):**

```jsonc
// POST /compute/v1/instances → Operation
{
  "projectId": "prj-2m8x…", "instanceKind": "VM", "zoneId": "ru-1-a",
  "machineTypeId": "std-v3-2",
  "bootSource": { "type": "registry.image", "id": "reg/lib/ubuntu" },   // Referrer-цель источника
  "bootSourceTag": "24.04",                  // tag XOR digest на вход; резолв→digest на Create
  // "bootSourceDigest": "sha256:9f2c…"      // если дан digest — verbatim (уже immutable)
  "capabilityRequirements": [ { "capabilityKey": "gpu.model", "operator": "IN", "values": ["a100"], "quantity": 1 } ],
  "placementGroupId": "plg-4b…",
  "bootVolumeSpec": { "sizeBytes": 21474836480, "diskTypeId": "ssd" }    // VM: сервер материализует Volume ИЗ bootSource
  // CONTAINER: bootVolumeSpec отсутствует → ephemeral rootfs из образа, boot-Volume нет
}
```

### 1.2 Instance — **Internal\*** (`InternalInstanceService.GetInternal`, :9091)

```jsonc
{
  "instance": { /* …полный public Instance выше… */ },
  "placement": {                             // ← существует ТОЛЬКО на :9091 (by construction, не «скрыто фильтром»)
    "nodeId": "nd-88…",                      //    реальная нода
    "hostClass": "gpu-a100-8x",
    "nodePoolId": "npl-7d…",
    "numericInfraId": 480213,                //    числовой инфра-id (ban: инфра-sensitive)
    "failureDomainAssignments": [            //    per-topology-key назначенный домен (ИДЕНТИЧНОСТИ)
      { "topologyKey": "availability",     "domainId": "az-ru-1-a" },
      { "topologyKey": "network-locality", "domainId": "rack-B14" },
      { "topologyKey": "power",            "domainId": "pdu-B14-3" }
    ],
    "schedulerState": "PLACED"               //    {PENDING|PLACED|EVICTING}
  },
  "materialization": {                       // как разложено на железо
    "bootBackend": "nvme-ns-12", "wiringStatus": "PROGRAMMED", "kernelState": "…"
  },
  "fqdn": "ins-7f….ru-1-a.internal"          // internal DNS (не на public)
}
```

### 1.3 MachineType — Mixed

```jsonc
// PUBLIC (MachineTypeService.Get/List — read-only каталог)
{
  "id": "std-v3-2",                          // ⊘  slug
  "name": "Standard v3 · 2 vCPU",
  "description": "General purpose, guaranteed baseline",
  "family": "STANDARD",                      //     enum {STANDARD|COMPUTE_OPTIMIZED|MEMORY_OPTIMIZED|GPU|BURSTABLE|CUSTOM°growth}
  "vcpus": 2, "memoryBytes": 8589934592, "gpus": 0, "gpuType": "", "cpuArch": "x86_64",
  "cpuGuaranteeOptions": [0, 20, 50, 100],   //     допустимый набор cpuGuaranteePercent
  "offeredCapabilities": ["cpu.arch=x86_64"],// °  какие curated-capability даёт
  "availableZones": [                        // °  DERIVED — где bookable (из NodePool coverage)
    { "type": "geo.zone", "id": "ru-1-a", "name": "ru-1-a" }   // C-forward Referrer[]
  ],
  "usedBy": [ /* ° C-reverse Reference[] — Instance'ы на этом типе (retire-safety/quota-tooling) */ ],
  "status": "AVAILABLE"                       // °  enum {AVAILABLE|DEPRECATED|RETIRED}
}
// INTERNAL* (InternalMachineTypeService.GetInternal + admin CRUD)
{
  "machineType": { /* public выше */ },
  "backingHostClass": "epyc-9004",           // ← :9091 only
  "oversubscriptionRatio": 1.0,
  "perNodeCapacity": 24,
  "numericInfraId": 12
}
```

### 1.4 PlacementGroup — Mixed (**composable**, defect 3)

```jsonc
// PUBLIC
{
  "id": "plg-4b2c…",                         // ⊘
  "projectId": "prj-2m8x…",                  // ⊘  B: scope-anchor
  "createdAt": "…", "updatedAt": "…",        // °
  "name": "web-ha", "description": "", "labels": {},

  "placementType": "REGIONAL",               // ⊘  enum {ZONAL|REGIONAL} — coherence-дискриминатор (mirror Subnet/NLB)
  "zoneId": "", "regionId": "ru-1",          // ⊘  B: ровно один set (DB-CHECK биконд.)

  "constraints": [                           //     КОМПОЗИРУЕМЫЙ конъюнктивный список (ANDed) — вместо single-oneof
    { "topologyKey": "availability",     "mode": "SPREAD", "maxSkew": 1, "partitionCount": 0, "enforcement": "REQUIRED"  },
    { "topologyKey": "network-locality", "mode": "PACK",   "maxSkew": 0, "partitionCount": 0, "enforcement": "PREFERRED" }
  ],                                         //     topologyKey — A: FK → topology_vocabulary; PARTITION = SPREAD+maxSkew=k

  "status": "SATISFIED",                     // °  enum {SATISFIED|DEGRADED|PENDING} (агрегат REQUIRED-constraint'ов)
  "constraintStatus": [                      // °  per-constraint — ТОЛЬКО СЧЁТЧИКИ, НИКОГДА идентичности домена
    { "topologyKey": "availability",     "satisfied": true, "spreadWidth": 3 },   // «по 3 доменам»
    { "topologyKey": "network-locality", "satisfied": true, "packedInto": 1 }     // «упаковано в 1»
  ],
  "members": [                               // °  C-reverse Reference — SoT=Instance.placementGroupId
    { "referrer": { "type": "compute.instance", "id": "ins-7f…", "name": "web-01" }, "type": "USED_BY", "owned": false }
  ]
}
// INTERNAL* (InternalPlacementGroupService.GetInternal)
{
  "placementGroup": { /* public */ },
  "memberAssignments": [                      // ← :9091 only: реальные домены + ноды
    { "instanceId": "ins-7f…",
      "domains": { "availability": "az-ru-1-a", "network-locality": "rack-B14" },
      "nodeId": "nd-88…" }
  ]
}
```

`PlacementConstraint.mode`: `SPREAD` (anti-affinity по tier) · `PACK` (affinity внутри tier). `enforcement`: `REQUIRED` (hard) · `PREFERRED` (soft — scheduler weights, не reject).

### 1.5 CapabilityVocabulary — Mixed (defect 4 инфраструктура)

```jsonc
// PUBLIC (read-only allow-list)
{
  "key": "gpu.model",                        // ⊘  opaque curated ключ (НЕ host-label!)
  "displayName": "GPU model",
  "description": "Accelerator model class",
  "kind": "ACCELERATOR",                     //     enum {GPU|ACCELERATOR|STORAGE_CLASS|CPU_ARCH|FEATURE}
  "valueType": "ENUM",                       //     enum {ENUM|QUANTITY|BOOL}
  "allowedValues": ["a100", "h100", "l4"],   //     curated opaque токены (для ENUM)
  "operators": ["EXISTS", "EQUALS", "IN"]    //     какие operator валидны
}
// INTERNAL* (секрет: capability → host-label)
{
  "capability": { /* public */ },
  "hostLabelMapping": { "a100": { "nvidia.com/gpu.product": "NVIDIA-H100-80GB" } },  // ← :9091 only
  "offeredByPools": ["npl-7d…"]
}
```

### 1.6 TopologyVocabulary — Mixed (defect 3/4 инфраструктура)

```jsonc
// PUBLIC (read-only allow-list абстрактных failure-domain tier-ключей)
{
  "key": "network-locality",                 // ⊘  opaque curated ключ (НЕ rack/switch/host!)
  "displayName": "Network locality",
  "description": "Low-latency locality failure domain below the zone",
  "tier": 3,                                 //     порядок вложенности (zone > locality > …)
  "spreadSupported": true, "packSupported": true
}
// INTERNAL* (секрет: topologyKey → node-label / real axis)
{
  "topology": { /* public */ },
  "realDomainClass": "rack",                 // ← :9091 only — {rack|power-feed|network-spine}
  "nodeLabelKey": "kacho.io/physical-rack",
  "domainCount": 128
}
```

### 1.7 NodePool / NodePoolBinding — **Internal\*** only (mold AddressPool)

```jsonc
// NodePool (InternalNodePoolService, :9091, system_admin + required_acr_min=2, scope object_type='cluster')
{
  "id": "npl-7d…", "name": "gpu-a100-pool", "labels": {},
  "zoneId": "ru-1-a", "kind": "GPU",         // enum {SHARED|DEDICATED°growth|GPU|BAREMETAL°growth|RESERVED°growth}
  "isDefault": false,                        // partial-UNIQUE per (zoneId, kind)
  "selectorLabels": { "tier": "gpu" }, "selectorPriority": 100,   // какие проекты обслуживает (каскад)
  "capabilityLabels": { "nvidia.com/gpu.product": "NVIDIA-H100-80GB", "local-nvme": "true" },  // РЕАЛЬНЫЕ host-labels
  "topologyDomains": [ { "topologyKey": "network-locality", "domainIds": ["rack-B14", "rack-B15"] } ],  // РЕАЛЬНЫЕ идентичности
  "capacity": { "total": 96, "used": 40, "free": 56 },
  "hostInventory": [ { "hostId": "nd-88…", "rack": "rack-B14" } ]
}
// NodePoolBinding — confine project→pool (project_default → zone_default → global_default каскад)
{ "projectId": "prj-2m8x…", "nodePoolId": "npl-7d…", "priority": 100 }   // nodePoolId: A flat+FK; projectId: B scope
```

**Operation** — стандартный `kacho.cloud.operation.v1.Operation` (`epd`): `id, description, createdAt, done, metadata:Any, oneof result{Status error|Any response}`. Поллинг `OperationService.Get`; Watch не существует.

---

## 2. Разбор 5 дефектов

### Defect 1 — `image` vs `boot_volume` дублируют «откуда ОС» → source→materialized lineage

Роли развязаны по **lifecycle**, не по полю. «Где ОС» — структурно однозначно: source = **всегда** `bootSource`; runtime-state = VM: `bootVolume`, Container: ephemeral.

```jsonc
// ДО (текущий instance.proto — двусмысленно, дрейф source/state):
{ "image": "reg/lib/ubuntu:24.04",  "image_digest": "sha256:9f2c…",
  "boot_disk": { "volume_id": "vol-a1…", "auto_delete": true, "mode": "READ_WRITE" } }
// ПОСЛЕ:
{ "bootSource": { "type": "registry.image", "id": "reg/lib/ubuntu@sha256:9f2c…", "name": "lib/ubuntu:24.04" },  // ⊘ ИСТОЧНИК (immutable рецепт)
  "bootSourceDigest": "sha256:9f2c…",                                                                            // ⊘ пин
  "bootVolume": { "referrer": {"type":"storage.volume","id":"vol-a1…"}, "type":"USED_BY", "owned": true } }      // ° MATERIALIZED (storage-owned, VM only)
```

- **`bootSource`** (⊘) — immutable источник ОС. **VM**: worker материализует storage.Volume ИЗ источника на Create (compute→storage) → `bootVolume°`. **Container** (`instanceKind=CONTAINER`): ephemeral rootfs из образа, `bootVolume` **отсутствует** (диска нет).
- `image` **никогда** не first-class mutable-поле рядом с `bootVolume` — источник живёт в `bootSource`, `bootVolume` — его материализованный выход. Нет двух представлений одного факта (защита от дрейфа).

### Defect 2 — `digest`+`tag` избыточны → один immutable пин + provenance-echo

```jsonc
// ДО: два first-class поля (input tag + output digest), но оба «живут» на верхнем уровне
{ "image": "reg/lib/ubuntu:24.04", "image_digest": "sha256:9f2c…" }
// ПОСЛЕ: пин ОДИН immutable; tag растворяется в digest на Create
{ "bootSourceDigest": "sha256:9f2c…",   // ⊘ ЕДИНСТВЕННЫЙ authoritative пин (воспроизводимо)
  "bootSourceTag": "24.04" }            // ° provenance ONLY — «из чего резолвилось», НЕ пин, может устареть на re-tag в registry
```

Input несёт `bootSourceTag` **XOR** `bootSourceDigest`. На Create compute резолвит tag→digest через registry (compute→registry, sync, fail-closed) и сторит **только** `bootSourceDigest⊘`. Если дан digest — verbatim (идемпотентно). `bootSourceTag°` — non-authoritative audit-echo. Ноль двух mutable image-полей.

### Defect 3 — single-`oneof` не композится → composable constraints

```jsonc
// ДО (placement_group.proto — exactly_one, «spread-зоны + pack-стойка» невыразимо):
{ "placement_strategy": { "spread_placement_strategy": {} } }   // ЛИБО spread, ЛИБО partition
// ПОСЛЕ (конъюнктивный список):
{ "constraints": [
    { "topologyKey": "availability",     "mode": "SPREAD", "maxSkew": 1, "enforcement": "REQUIRED"  },
    { "topologyKey": "network-locality", "mode": "PACK",                 "enforcement": "PREFERRED" } ] }
```

`constraints[]` — независимые, ANDed. `topologyKey` — opaque curated (TopologyVocabulary; тенант видит абстракцию, не идентичности); `mode{SPREAD|PACK}`; `maxSkew` (SPREAD); `enforcement{REQUIRED|PREFERRED}`. PARTITION = `SPREAD` + `maxSkew=k` (не отдельная стратегия). «spread-зоны + pack-стойка» = один PG, два constraint'а (§4).

### Defect 4 — node_selector течёт на гиперы → capability-requirements

```jsonc
// ДО (instance.proto PlacementPolicy.host_affinity_rules — node-targeting, leak гипервизор-абстракции):
{ "host_affinity_rules": [ { "key": "yc.hostId", "op": "IN", "values": ["host-4471"] } ] }
// ПОСЛЕ (декларативные требования над curated-vocab; ноль node-targeting by construction):
{ "capabilityRequirements": [ { "capabilityKey": "gpu.model", "operator": "IN", "values": ["a100"], "quantity": 1, "enforcement": "REQUIRED" } ] }
```

`host_affinity_rules`/`node_selector` **удалён из схемы** — node-targeting больше **не выразим**. Тенант декларирует «ЧТО нужно» над admin-curated `CapabilityVocabulary` (`capabilityKey` A-FK). Реальный маппинг `capability → host-label` (`nvidia.com/gpu.product`) — **Internal-only** (CapabilityVocabulary/NodePool). Scheduler матчит server-side; тенант узнаёт лишь match/no-match (`FAILED_PRECONDITION "insufficient capacity for capability %s in zone %s"`), никогда host-label/node-id. Ни одного поля/RPC/filter, именующего хост/стойку/pool на public — by construction (two-projection).

### Defect 5 — ref-разнобой → the reference law (§0.1)

```jsonc
// A within-service (flat + FK): "machineTypeId":"std-v3-2"  "placementGroupId":"plg-4b…"  "capabilityRequirements[].capabilityKey":"gpu.model"
// B scope-coord   (flat + peer-validate): "projectId":"prj-…"  "zoneId":"ru-1-a"  "serviceAccountId":"sac-…"
// C-forward Referrer: "bootSource":{type,id,name}  "secondaryVolumes[].volume":{…}  "networkInterfaces[].nic":{…}
// C-reverse Reference: "bootVolume":{referrer,type,owned}  "usedBy":[{referrer,type,owned}]  "members":[…]
```

Uniform reference-**граф** на всех cross-service dependency-рёбрах (Referrer forward / Reference reverse — реальные proto-типы, ноль нового proto). Within-service integrity — DB FK (ban #10). Даёт: polymorphism (`bootSource` варьирует registry/storage), единый reverse-index/`usedBy`, graceful-dangling. Референсифицировать `machineTypeId`/`projectId` — отвергнуто (§8): спрятало бы FK, сломало placement-coherence, uniformity-ради-uniformity.

---

## 3. RPC surface

**`InstanceService`** (public :9090; REST `/compute/v1/instances`) — read sync, мутации async→`Operation` (`epd`):

| RPC | sync/async | Заметки |
|---|---|---|
| `Get`/`List`/`ListOperations` | sync | malformed id → `InvalidArgument "invalid instance id '<X>'"` первым стейтментом; List listauthz-filtered, cursor `(createdAt,id)`, `filter name=`; pagination-validate **до** empty-grant short-circuit |
| `GetSerialPortOutput` | sync | synthetic (нет data-plane) |
| `Create` | async | `bootSource` tag→digest (registry, fail-closed); VM: материализация boot-Volume (storage); capabilityReq+placementGroup → NodePool slot+domain allocate в worker-TX; metadata `CreateInstanceMetadata{instanceId}` |
| `Update` | async | mutable: name/desc/labels/userData; sizing (`machineTypeId`/`cpuGuaranteePercent`), `capabilityRequirements`, `placementGroupId` — **только STOPPED**; immutable-switch **до** UpdateMask; `⊘`: zoneId/instanceKind/placementType/bootSource*/bootSourceDigest |
| `Delete` | async | crash-safe идемпотентная saga: MarkDeleting → detach NIC → detach volumes (autoDelete honored) → release slot → delete row last |
| `Start`/`Stop`/`Restart` | async | lifecycle |
| `Reinstall` | async | re-pin `bootSource` (новый digest) → re-materialize boot-Volume; единственный путь «сменить ОС» |
| `AttachDisk`/`DetachDisk` | async | compute→storage saga; object-scoped authz на `instanceId` **и** `volumeId` (anti-BOLA) |
| `AttachNetworkInterface`/`DetachNetworkInterface` | async | compute→vpc saga; multi-NIC; object-scoped на `instanceId` **и** `nicId` |

**Каталоги (public :9090, sync read):** `MachineTypeService.Get/List`; `PlacementGroupService.Get/List/ListOperations` + `Create/Update/Delete`(async); `CapabilityVocabularyService.Get/List`; `TopologyVocabularyService.Get/List`.

**`Internal*` (:9091 only, mTLS + per-RPC authz на обоих листенерах, ban #6 + security.md):**
- `InternalInstanceService.GetInternal` (node/host/failure-domain/materialization)
- `InternalMachineTypeService.{Create,Update,Delete,GetInternal}` (`system_admin`)
- `InternalPlacementGroupService.GetInternal` (per-member реальные домены+ноды)
- `InternalCapabilityVocabularyService`/`InternalTopologyVocabularyService` — admin CRUD + curated-mapping
- `InternalNodePoolService.{Create,Update,Delete,GetUtilization,BindProject,UnbindProject,AllocateSlot}` — no public API; `system_admin`+`required_acr_min=2`+`scope_extractor object_type='cluster'`
- growth-seam: reconciler `ClaimWork`/`ReportStatus` над `FOR UPDATE SKIP LOCKED`

**Инвариант везде:** per-RPC `InternalIAMService.Check` на **обоих** листенерах (read→`system_viewer`-floor, мутации→admin-tier); mTLS internal / TLS+JWT public; object-scoped `scope_extractor` на Attach*; INTERNAL-ветка mapper → фикс. `"internal error"` (без pgx-leak, regression на **сообщение**).

**DB-инварианты (ban #10):** `machine_type_id` FK RESTRICT · `placement_group_id` FK SET NULL · `placement_type` CHECK биконд. `(ZONAL∧zone_id<>''∧region_id='')∨(REGIONAL∧zone_id=''∧region_id<>'')` · Instance⇄PlacementGroup zone-coherence в link-CAS predicate `… AND (plg.placement_type='REGIONAL' OR plg.zone_id=$my_zone)` · `capability_requirements(instance_id,capability_key)` PK + `FK(capability_key,value)→capability_vocabulary_values(key,value)` (значение ∈ vocab на DB) · `placement_group_constraints(group_id,topology_key)` PK + `topology_key` FK→`topology_vocabulary` · NodePool slot `FOR UPDATE SKIP LOCKED LIMIT 1` + capacity CAS `UPDATE…SET used=used+1 WHERE free>0 RETURNING` · SPREAD `EXCLUDE (placement_group_id WITH =, failure_domain WITH =)` · `UNIQUE(project_id,name) WHERE name<>''` · `cpu_guarantee_percent` CHECK 0..100 · `bootSourceDigest` immutable (no update-path). Concurrent-race integration-тест обязателен (ban #12).

---

## 4. Placement — композиция constraint'ов

**«spread по зонам + pack внутри стойки»** — один PlacementGroup, ДВА constraint'а:

```jsonc
// POST /compute/v1/placementGroups
{ "projectId": "prj-2m8x…", "name": "ha-low-latency", "placementType": "REGIONAL", "regionId": "ru-1",
  "constraints": [
    { "topologyKey": "availability",     "mode": "SPREAD", "maxSkew": 1, "enforcement": "REQUIRED"  },  // HARD: члены по разным availability-доменам, дисбаланс ≤1
    { "topologyKey": "network-locality", "mode": "PACK",                 "enforcement": "PREFERRED" }   // SOFT: где можно — одна locality (low-latency)
  ] }
```

Инстансы вступают: `Instance.placementGroupId = "plg-…"`.

**Композиция (ANDed) в scheduler'е (Internal, control-plane slot-accounting, worker-TX):**
1. `availability/SPREAD/maxSkew=1` (REQUIRED): аллокатор бронит домен `EXCLUDE (placement_group_id, availability_domain)` + skew-счётчик → два члена не в одном availability-домене сверх skew. 0 rows → `FAILED_PRECONDITION "insufficient capacity in region ru-1"`.
2. `network-locality/PACK` (PREFERRED): аллокатор пинит первый выбранный locality-домен группы, фильтрует ноды `WHERE network_locality_domain = $group_locality`; при недоступности **не** блокирует (soft, weights).
3. Capacity-CAS `FOR UPDATE SKIP LOCKED LIMIT 1` + `UPDATE…SET used=used+1 WHERE free>0 RETURNING` на выбранной ноде.

**Placement-coherence:** `placementType` DB-CHECK биконд.; Instance.zoneId когерентен с группой (zonal↔zonal same-zone; zonal↔regional zone∈region) — within-service DB-CHECK + attach-CAS predicate; zone/region-существование peer-validate geo fail-closed.

**Что видит тенант** (public `PlacementGroup.Get`):
```jsonc
{ "status": "SATISFIED",
  "constraintStatus": [ { "topologyKey": "availability", "satisfied": true, "spreadWidth": 3 },
                        { "topologyKey": "network-locality", "satisfied": true, "packedInto": 1 } ],
  "members": [ /* 3 инстанса, USED_BY refs */ ] }
```
«Разнесено по 3 доменам, упаковано в 1» — **счётчиками**. Идентичности availability/rack/node — только `InternalPlacementGroupService.GetInternal.memberAssignments` (:9091). Скомпрометированный public-API не ответит «мой и чужой инстанс на одном железе»: нет поля/RPC/filter, отдающего идентичность домена/host/pool/capacity. Третий constraint (`power/SPREAD`) — одна строка, ноль schema-break.

---

## 5. Image/boot lifecycle (source→materialize, VM vs Container, reinstall, snapshot-lineage)

```
bootSource (⊘ immutable источник)  ──materialize──▶  runtime-state
   registry.image @digest                              VM:        storage.Volume (mutable, storage-owned) = bootVolume°
   storage.snapshot  (growth: reinstall-from-snapshot) CONTAINER: ephemeral rootfs (диска нет, bootVolume отсутствует)
   storage.volume    (growth: clone)
```

- **VM Create:** worker резолвит `bootSource` tag→digest (compute→registry) → материализует boot-Volume в storage ИЗ источника (`bootVolumeSpec.sizeBytes/diskTypeId`) → attach как `isBoot=true`. Volume несёт `sourceImage` lineage на storage-стороне. Runtime-запись идёт в Volume; источник immutable.
- **Container Create:** `instanceKind=CONTAINER`, `bootVolumeSpec` отсутствует → ephemeral rootfs из образа. Персистентность — только *attached* data-Volumes. `bootVolume` поля нет (структурная разница VM/Container).
- **Reinstall:** re-pin `bootSource` (новый digest) → re-materialize boot-Volume. Growth: `bootSource` полиморфен → reinstall-from-snapshot / clone-from-volume как новые Referrer-цели, ноль изменений формы.
- **Snapshot-lineage (growth):** `bootSource(registry.image) → Volume(sourceImage) → Snapshot(sourceVolume) → (promote) registry.image` — цепь Referrer'ов, walkable единым reverse-index/`usedBy`. Опциональный compute-owned **Image-каталог** (`img`, digest-pinned handle на `registry.repository` + `lineage: Referrer` на parent) добавляется как **новая Referrer-цель** `bootSource` — не v1, ноль breaking (bootSource уже полиморфен).

---

## 6. Growth headroom (v1-ядро vs extension-hooks)

Всё additive — новые enum-значения / optional-поля / `Internal*`-поля / новые Referrer-цели / vocab-строки, **никогда** breaking на public-message. Load-bearing свойство: **рост не меняет тип поля** — добавляет `Referrer.type`-string, enum-значение или curated-токен.

| Ось роста | Как приземляется (ноль breaking) |
|---|---|
| **Baremetal / sole-tenant** | `instanceKind=BAREMETAL` + `NodePool.kind=DEDICATED\|BAREMETAL`. Дискриминатор уже есть |
| **Container↔VM** | Уже в модели: `instanceKind=CONTAINER` (bootVolume отсутствует, ephemeral rootfs). Общий Instance/lifecycle |
| **Regional/anycast instance** | `placementType=REGIONAL` уже дискриминирован (mirror Subnet/NLB); coherence-CHECK биконд. Флип — значение, не schema |
| **GPU-cluster** | `capabilityRequirements` уже выражают GPU; `GpuCluster` = NodePool-kind + новая Referrer-цель. Форма Instance неизменна |
| **Multi-attach / RWX** | `secondaryVolumes[]`/`bootVolume` уже reference[]; storage добавляет `shareable`/`maxAttachments` (composite-PK) — на compute 0 изменений |
| **Live-migration / maintenance** | `Instance.Relocate`/`SimulateMaintenanceEvent` → меняет только `Internal*` `nodeId`/`failureDomainAssignments`; **ноль** public-изменений (node не на public) |
| **Image-lineage граф** | `bootSource.previousDigest` (Reinstall-цепь) + опциональный compute Image-каталог как новая Referrer-цель; snapshot→image promotion |
| **Custom sizing** | `MachineType.family=CUSTOM` (явные vcpu/mem) — тот же каталог-path, ноль free-form leak |
| **InstanceGroup + autoscaling** | Новый `igr`-ресурс; члены через `Reference{MANAGED_BY}`; переиспользует MachineType+PlacementGroup+capabilityRequirements verbatim |
| **ReservedInstancePool** | `NodePool.kind=RESERVED` + `ReservedInstancePool` Referrer-цель; scheduler предпочитает reserved-слоты |
| **Новые capability/topology-оси** | Строка в CapabilityVocabulary/TopologyVocabulary — **без proto-изменений** (главный extensibility-выигрыш: новое железо = curated-data) |
| **Composable-placement расширения** | Новые `mode` (weighted-PREFERRED с priority), `enforcement`-уровни, `placementBindings[]` (multi-policy на Instance) — additive в `constraints[]` |
| **Idempotency-key** | Request-level ключ на Create/heavy-мутации (конвенция-headroom, overview §5 q11) |
| **Quota** | Per-project caps (iam-owned или `kacho-quota`), keyed off `machineTypeId` (уже атрибутируемо); fail-closed на Create/Start → `FAILED_PRECONDITION "quota exceeded for %s"` |

---

## 7. Cross-service рёбра + ацикличность + placement-coherence

**Все рёбра one-way; compute — консумер (никто не зовёт compute обратно):**

| Ребро | Протокол | Ошибка |
|---|---|---|
| `compute → storage` | материализация boot-Volume из `bootSource` (VM) + attach/detach; **storage владеет attach-state** (`volume_attachments`), compute — read-only mirror | storage `Unavailable` → мутация `Unavailable` (fail-closed) |
| `compute → vpc` | NIC attach/IPAM; **vpc владеет attach-state** (`used_by_id` CAS, multi-NIC via `used_by_index`), mirror | vpc `Unavailable` → `Unavailable` |
| `compute → geo` | `ZoneService.Get`/`RegionService.Get` — существование zone/region, placement-coherence anchor | geo `Unavailable` → `Unavailable` |
| **`compute → registry` (NEW)** | resolve `bootSource` tag→digest + existence + digest-pin на Create; **sync** request-path; **fail-closed** (registry down/5xx → `Unavailable`, никогда allow) | registry `Unavailable` → мутация `Unavailable` |
| `compute → iam` | `InternalIAMService.Check` (оба листенера) + `ProjectService.Get` (existence/owner) + fgaproxy `RegisterResource`/`UnregisterResource` (owner-tuple `compute_instance:<id>`, transactional-outbox + drainer, at-least-once) | iam `Unavailable` → `Unavailable` |

**Ацикличность (holds):** `compute → {storage, vpc, geo, registry, iam}`; никто не зовёт compute обратно. `registry → iam` (jwks/Check) — не к compute. `storage`/`vpc` валидируют self-describing payload'ы (не зовут compute). `geo` — leaf. Новое ребро `compute→registry` — фиксируется в `polyrepo.md` (runtime-edge) + vault `edges/compute-to-registry-image-resolve.md`. Циклов нет.

**`Operation.done` НЕ гейтит downstream-видимость** (ban #9): `done=true` = Instance-row durable. owner-tuple (iam) / boot-Volume-mirror (storage) / attach-mirror материализуются eventually-consistent; owner-доступ в кратком окне — bounded client-retry (newman `retry_until_authorized`), не серверный confirm-барьер.

**Placement-coherence (ВСЕ ресурсы зонально ИЛИ регионально):**
- Instance ⇄ PlacementGroup — zonal↔zonal same-zone; zonal↔regional zone∈region; DB-CHECK биконд. + link-CAS predicate.
- Instance ⇄ Volume — та же зона (storage self-describing CAS: `VolumeAttachment` несёт `zone_id`, attach-CAS `… AND vol.zone_id=$my_zone`).
- Instance ⇄ NIC(subnet) — та же зона, **кроме** REGIONAL/anycast subnet (`peer.placement_type='REGIONAL' OR peer.zone_id=$my_zone`).
- zone/region-существование — peer-validate geo fail-closed (не локально).
- Error-тексты (контракт): zone mismatch → `"<A> is in zone %s, <B> zone is %s"` → `FailedPrecondition`; region mismatch → `"... must be in the same region"`.
- Negative-тест (ban #12): zone/region mismatch → точный код+текст; anycast/REGIONAL-ветка → zone-check пропущен.

---

## 8. Trade-offs / отвергнутые альтернативы

1. **Референсифицировать `machineTypeId`/`projectId`/`zoneId` в `Referrer` (наивное «ВСЕ через reference»).** Отклонено: within-service integrity обязана быть DB FK (ban #10), не software-typed-handle — wrapping спрятал бы FK, пригласил software-dangling-handling там, где БД гарантирует existence, добавил константный `type` в каждую запись; scope-координаты hard-fail (не graceful-dangling), кормят `scope_extractor`/CHECK raw-значением, сломали бы parity со всей платформой (Subnet/Volume/NIC flat `zone_id`). Pure-выбор = единый **закон** (§0.1), не идентичная wire-форма.
2. **Новый `reference.ResourceRef` proto для forward-указателей.** Отклонено: storage-spec запрещает переизобретать ref-типы («не изобретаем UsedByRef»). Top-level `reference.Referrer{type,id,name}` уже *есть* typed forward-handle. Ноль нового proto.
3. **`reference.Reference` (reverse) как forward-указатель** (линза cloud-native). Отклонено: proto делает `Reference` reverse-by-construction (`referrer` = кто указывает на меня, `USED_BY`/`owned`) — forward-использование инвертирует семантику («volume uses the instance»). Forward=`Referrer`, reverse=`Reference`.
4. **Держать `image`+`image_digest`+`boot_disk` first-class.** Отклонено: двусмысленно «где ОС», дрейф source/state, нет lineage → `bootSource⊘` (immutable) + `bootVolume°` (derived).
5. **Отдельное `bootVolume`-поле рядом с `secondaryVolumes`.** Отклонено: два представления одного факта → дрейф. `bootVolume` — reverse-mirror boot-Volume'а, единственное представление; VM only.
6. **Сторить tag И digest как mutable-пины.** Отклонено: dual-pin дрейф, невоспроизводимость → один immutable `bootSourceDigest` + provenance-echo `bootSourceTag°`.
7. **Single-`oneof` PlacementGroup.** Отклонено: «spread-зоны + pack-стойка» невыразимо → конъюнктивный `constraints[]`.
8. **K8s-style topologySpreadConstraints с полным labelSelector + именами доменов.** Отклонено: течёт топология, envelope-стиль → opaque curated `topologyKey` + counts-only `constraintStatus`, flat.
9. **`node_selector`/`host_affinity_rules{yc.hostId}`.** Отклонено: node-targeting, компрометация гипервизор-абстракции, topology-BOLA → `capabilityRequirements` над curated CapabilityVocabulary, ноль node-targeting.
10. **Единый `SchedulingVocabulary` (capability + topology вместе).** Отклонено: конфляция двух ортогональных концернов (what-I-need vs how-members-relate), блокирует независимую эволюцию → **две** vocabularies (CapabilityVocabulary + TopologyVocabulary). Merge — только если останутся изоморфны.
11. **Free-form `Resources{vcpus,memory}` вместо MachineType.** Отклонено: не bookable, не quota-атрибутируемо, нет capacity-планирования/GPU-families, sizing-truth раздваивается → MachineType-каталог + `effectiveResources°` echo; `CUSTOM`-family как единственный free-form escape-hatch.
12. **Compute-owned Image-каталог обязателен в v1.** Отклонено для v1: overview retire'ит legacy Image; OS доставляется из OCI registry напрямую (`bootSource: Referrer{registry.image}`). Image-каталог + lineage — **growth-hook** (новая Referrer-цель, ноль breaking).
13. **Tenant-visible идентичность домена** («spread across rack-7») ради UX. Отклонено: existence/topology-oracle, разведка lateral-movement → counts-only `spreadWidth`/`packedInto`; идентичности :9091.
14. **NodePool/scheduler в geo или новом `kacho-placement`.** Отклонено (overview §5 q3): compute владеет Instance-placement; NodePool в compute-`Internal*` сохраняет `compute→geo` one-way (zone existence) без нового цикла. AddressPool-mold; `ClaimWork/ReportStatus` — seam для выноса reconciler'а позже без tenant-facing изменений.
15. **Instance владеет attach-таблицами дисков/NIC.** Отклонено (storage-spec): потеря owner-side CAS/FK, дубль-состояние, cross-DB-невозможность FK → attach-state у owner'а (storage/vpc), compute — read-only mirror через reference.
16. **Гейтить `Operation.done` на видимость scheduler/материализации.** Отклонено (ban #9): phantom-ресурс. `done` = row durable; downstream — eventually-consistent + bounded client-retry.

---

**Артефакты для сверки:** `docs/plans/storage-compute-iaas-overview.md §1` (baseline) · `kacho-storage-volume-and-instance-attach-spec.md` (attach/used_by pattern) · `proto/kacho/cloud/reference/reference.proto` (`Referrer` forward / `Reference` reverse) · разбираемый legacy `proto/kacho/cloud/compute/v1/{instance,placement_group,image}.proto` (YC-derived: `platform_id`, `host_affinity_rules{yc.hostId}`, `MetadataOptions{gce_*/aws_*}`, single-`oneof`, free-form `Resources` — замещаются Kachō-native формой, ban #2). Следующий gate: `acceptance-author` → `acceptance-reviewer` (Given-When-Then) ПЕРЕД кодом (ban #1).
