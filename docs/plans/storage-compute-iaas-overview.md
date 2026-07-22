# Kachō IaaS — Compute + Storage Overview (alignment doc)

**Status:** draft · alignment only (acceptance docs + code follow, per ban #1)
**Scope:** the tenant-facing IaaS surface of `kacho-compute` + `kacho-storage`, with
peer edges to `kacho-vpc` (NIC/Address), `kacho-geo` (Region/Zone), `kacho-iam` (authz).
**Goal:** a full, maximally-flexible IaaS — create VMs / containers / (later) bare-metal;
attach network disks + network interfaces; pod-like placement (affinity / anti-affinity /
node-selectors / placement-group) — **without ever exposing where-on-which-host on the public
surface**. Control-plane only; every physical fact lives on `Internal*` (:9091).

All designs obey Kachō conventions: **flat resource message + async `Operation`**, own-product
terms only (no foreign-cloud names, ban #2), DB-level invariants (ban #10), one-owner-per-type +
peer-validate (data-integrity.md), two-projection isolation (security.md).

---

## 1. Resource model

Legend — **Proj.** column: `Public` = tenant-facing intent+result on external TLS + REST;
`Internal*` = :9091 admin/scheduler only; `Mixed` = one flat resource with a lean public
projection **plus** a separate `Internal*` full projection carrying infra fields.

| Resource | Owner | Prefix | Purpose | Key fields (public unless noted) | Proj. |
|---|---|---|---|---|---|
| **Instance** | compute | `ins` | VM / container / (later) bare-metal compute unit | `id, project_id⊘, created_at, name, labels, zone_id⊘, instance_type{VM\|CONTAINER\|BAREMETAL}⊘, machine_type_id, resources{vcpus,memory_bytes,gpus}, cpu_guarantee_percent(0..100), image+image_digest°, status(11-state), boot_volume°/secondary_volumes°/network_interfaces°(read-only mirrors), placement_group_id, node_selector{labels}, user_data. **Internal-only:** node_id, host_id, failure_domain, kernel/wiring status** | Mixed |
| **MachineType** | compute | slug | Bookable sizing catalog (vcpu/mem/gpu families, parity with DiskType) | `id(slug), name, description, family, vcpus, memory_bytes, gpus, zone_ids[]°`. **Internal-only:** backing host-class, oversubscription ratio, per-node capacity | Mixed |
| **PlacementGroup** | compute | `plg` | **Tenant-facing placement intent** — spread / pack / partition over opaque failure-domains | `id, project_id⊘, created_at, name, labels, placement_type{ZONAL\|REGIONAL}⊘, zone_id/region_id⊘, strategy{SPREAD\|PACK\|PARTITION}, partition_count, member_instance_ids°, status{SATISFIED\|DEGRADED\|PENDING}, spread_width°(count only)`. **Internal-only:** per-member failure-domain + node assignment | Mixed |
| **NodePool** | compute | `npl` | **Admin capacity pool** tenants draw slots from *blind* (AddressPool precedent) | *(no public API)* `id, name, labels, zone_id, kind, is_default, selector_labels{}+selector_priority, capability_labels{}, failure_domains[], capacity{total,used,free}, host inventory` | Internal* |
| **NodePoolBinding** | compute | — | Confines a project/tenant to NodePool(s) by label cascade | *(no public API)* `project_id, node_pool_id, priority` (mirrors `address_pool_network_default`) | Internal* |
| **CapabilityVocabulary** | compute | — | Admin-curated allow-list of abstract labels a tenant may `node_selector` on | *(read-only public list of opaque capability keys)* `key, description`. Hides real host labels behind curated capabilities | Mixed |
| **Volume** | storage | `vol` | Network block disk (persistent state; OS comes from OCI image, not the volume) | `id, project_id⊘, created_at, updated_at, name, labels, zone_id⊘, disk_type_id⊘, size_bytes(>0,grow-only), block_size⊘, source_snapshot_id⊘, status{…AVAILABLE\|IN_USE derived}, attachments[]°, used_by[]°`. **Internal-only (`GetInternal`):** backend-LUN, NVMe-namespace, storage-node, pool-id, numeric infra-id, capacity | Mixed |
| **VolumeAttachment** | storage | — | Volume↔Instance binding (join-table owned by storage) | `volume_id(PK), instance_id, instance_name°, device_name, is_boot, mode, auto_delete, attached_at`. **Internal-only:** project_id, zone_id (self-describing CAS coherence) | Mixed |
| **Snapshot** | storage | `snp` | Point-in-time backup of a Volume (persistent-state backup only, not OS delivery) | `id, project_id⊘, created_at, name, labels, source_volume_id⊘, size_bytes, status` | Public |
| **DiskType** | storage | slug | Volume QoS/type catalog | `id(slug), name, description, zone_ids[]°, performance_tier` (+ proposed `iops_*/throughput_*/min/max/step`). Admin CRUD Internal-only | Mixed |
| **NetworkInterface (NIC)** | vpc | `enp` | First-class ENI-like NIC; attach-state owner | `id, subnet_id, mac°, primary_v4/v6°, security_group_ids[], used_by_*`(attach CAS). Zone inherited via subnet. **Internal-only:** host-iface, netns, kernel wiring | Mixed |
| **Subnet** | vpc | `e9b` | Canonical **placement anchor** (`placement_type` discriminator) | `id, network_id, placement_type{ZONAL\|REGIONAL}, zone_id/region_id, cidr_blocks` | Public |
| **Address / AddressPool** | vpc | `e9b`/`apl` | Tenant address (public) drawn blindly from admin pool (Internal-only) | Address: allocated leaf only. AddressPool: Internal admin, SKIP-LOCKED freelist | Mixed |
| **Region / Zone** | geo | slug | Topology owner/leaf (failure-domain root) | `id(slug), name` / `id, region_id, status{UP\|DOWN}`. Public read + Internal admin CRUD; existence peer-validated fail-closed | Mixed |
| **Quota** | *(fork, §5)* | — | Per-project capacity caps (vCPU/RAM/instances/volumes/GiB/snapshots) | `project_id, dimension, limit, used°`; enforced fail-closed on Create/Start | Internal*/Mixed |
| **Operation** | per-svc | `epd`/`sop` | Async LRO envelope for every mutation | `id, description, created_at, done, metadata:Any, oneof result{Status error\|Any response}`. Poll `OperationService.Get`; no Watch | Public |

`⊘` = immutable after Create · `°` = output-only (source-of-truth elsewhere or derived).

**Two-projection contract (the load-bearing isolation rule):** every `Mixed` resource ships a
lean public message (id / name / labels / bindings / allocated tenant resource / `status`) **and**
a separate `Internal*` message or `internal-only, unset-in-public` fields carrying placement /
underlay / wiring / capacity / numeric-infra-id. Precedent already live: `Instance.host_id/host_group_id`
are reserved-out of the public proto; `InternalVolumeService.GetInternal` carries backend-LUN.
A gateway-level projection audit (analogous to `make audit-list-filter`) should gate that no
additively-added field leaks infra data onto the external surface.

---

## 2. Functionality set (grouped capability checklist)

**Lifecycle (Instance)** — `Create` (VM/Container; Baremetal later) · `Start` · `Stop` ·
`Restart` · `Reinstall` (re-pin image) · `Update` (sizing mutable only while `STOPPED`) ·
`UpdateMetadata` · `Delete` (crash-safe idempotent saga: MarkDeleting → release NICs → release
volume attachments → delete row last) · `Get`/`List`/`ListOperations` (sync) · `GetSerialPortOutput`
(synthetic) · `SimulateMaintenanceEvent`. All mutations → `Operation`.

**Lifecycle (Volume / Snapshot)** — Volume `Create`/`Update`(grow-only CAS, online)/`Delete`
(FK-RESTRICT-blocked while attached) · Snapshot `Create`(from `READY` Volume)/`Update`/`Delete`.
Status `AVAILABLE`/`IN_USE` **derived** from attachment presence.

**Disk-attach** — `Instance.AttachDisk(volume_id)` / `DetachDisk` (cross-service saga to storage;
compute holds zero attach-state; boot volume cannot be detached; idempotent). Single-attach today
(PK=volume_id); multi-attach/RWX = growth. Boot vs data via `VolumeAttachment.is_boot` (≤1 boot/instance,
EXCLUDE-enforced). `auto_delete` recorded; delete = detach-only (no cross-service cascade, ban #4).

**NIC-attach** — `Instance.AttachNetworkInterface(nic_id)` / `Detach` (binds existing first-class
vpc NIC via `used_by` CAS; multi-NIC per instance; `index==0` → vpc assigns first free slot).
NAT/addressing edited on the vpc NIC directly (`AddOneToOneNat` on Instance is Unimplemented **by
design** — single owner of addressing).

**Placement** — see §3. `PlacementGroup` (spread / pack / partition) · `node_selector` (abstract
capability labels) · zone/region placement-coherence (Instance ⇄ Volume ⇄ NIC same zone; anycast
= REGIONAL subnet) · blind NodePool slot allocation · insufficient-capacity fail-closed.

**Tenant-isolation** — two-projection (public-lean vs `Internal*`-full) · infra fields only on
:9091 · tenant draws NodePool slot without seeing the pool/host/failure-domain · admin confines a
tenant to a node-group by label cascade (NodePoolBinding) · per-RPC `InternalIAMService.Check` on
**both** listeners (mTLS / TLS+JWT everywhere, incl :9091) · object-scoped `scope_extractor`
(anti-BOLA: AttachDisk checks *both* instance_id and volume_id) · public `List` filtered via
listauthz (CI gate) · no PII in logs.

**Quotas & capacity** — per-project aggregate caps (vCPU / RAM / instance-count / volume-count /
disk-GiB / snapshot-count) · placement rejects on insufficient capacity → new
`FAILED_PRECONDITION "insufficient capacity in zone %s"` convention · capacity counted in NodePool
(Internal*), never exposed as tenant-visible inventory.

**Ops / observability** — every mutation returns pollable `Operation` (no Watch; poll `Get` /
`List` 2–5 s) · transactional outbox + LISTEN/NOTIFY feeds `InternalWatchService.Watch` (admin) ·
cursor pagination `(created_at,id)` + `filter` whitelist · idempotency-key on Create (fork §5) ·
metering/usage + audit = growth (§4). Serial-port output synthetic (no data-plane).

---

## 3. Placement design — tenant intent → hidden node-groups

The whole design is **one analogy**: *PlacementGroup is to NodePool what Address is to AddressPool.*
The tenant declares intent and receives a result; the pool, the hosts, and the failure-domains are
server-side and `Internal*`-only.

### 3.1 Tenant-facing surface (three knobs, all intent/label-based, zero topology)

1. **PlacementGroup** (`plg`, project-scoped, flat + Operation). Declares an *intra-group
   relationship* over **opaque failure-domains**:
   - `SPREAD` — each member on a distinct failure-domain (anti-affinity / HA).
   - `PACK` — co-locate members (affinity / low-latency).
   - `PARTITION` — `partition_count` groups, spread across domains (sharded workloads).
   Instance references it via `placement_group_id`. The tenant sees only: strategy, its own
   membership, `status ∈ {SATISFIED, DEGRADED, PENDING}`, and `spread_width` **as a count**
   (e.g. "spread across 3 domains") — **never** which rack/host/domain-identity.

2. **`node_selector`** on Instance — a map of **abstract capability labels** (e.g.
   `{capability: gpu}`, `{tier: performance}`) drawn from an admin-curated
   **CapabilityVocabulary** (public read-only allow-list). This is the node-selector/affinity knob.
   Selectors match server-side against hidden NodePool `capability_labels`; the tenant learns only
   match / no-match (→ insufficient-capacity), never a host label.

3. **Zone/region binding** — `placement_type {ZONAL|REGIONAL}` discriminator on PlacementGroup
   (mirrors the Subnet anchor and NLB), so a group is either pinned to a `zone_id` or is a
   REGIONAL/anycast group. Coherence: an Instance's `zone_id` must be consistent with its group
   (`zonal↔zonal` same zone; `zonal↔regional` zone∈region), enforced within-service by DB-CHECK
   biconditional + attach-CAS predicate, with zone existence peer-validated via `geo` fail-closed.

Selecting a raw host, host-group id, rack, or numeric infra id is **not expressible** on the public
surface — by construction, not by filtering.

### 3.2 Hidden infra (Internal*, :9091, admin/scheduler only) — the AddressPool mold

- **NodePool** (`npl`) — admin-managed capacity pool: `selector_labels` (which projects it serves)
  + `selector_priority`, `capability_labels` (what it offers), `failure_domains[]` (real
  rack/power/switch identities), `capacity{total,used,free}`, host inventory. All RPC
  `system_admin` + `required_acr_min=2`, `scope_extractor object_type='cluster'`. `is_default`
  partial-UNIQUE per `(zone,kind)`.
- **Tenant confinement** = **NodePoolBinding** label cascade, byte-for-byte the AddressPool
  precedent: `project_default → zone_default → global_default`. An admin confines tenant *T* to a
  labelled node-group by binding *T*'s project to the matching NodePool(s); the tenant stays blind.
- **Slot allocation** under concurrency = `FOR UPDATE SKIP LOCKED LIMIT 1` + capacity CAS
  (`UPDATE … SET used=used+1 WHERE free>0 RETURNING`), the exact AddressPool freelist pattern.
  Failure-domain assignment for `SPREAD`/`PARTITION` = `EXCLUDE`/CAS over `(placement_group_id,
  failure_domain)` so two members never collide on one domain. 0 rows → `FAILED_PRECONDITION
  "insufficient capacity"`. Concurrent-race integration test mandatory (ban #12).
- **Internal projections** — `PlacementGroupInternal` surfaces per-member failure-domain + node
  assignment; `Instance` internal projection surfaces `node_id/host_id/failure_domain`;
  `NodePool.GetUtilization` surfaces total/used/free. None of these fields exist on any public
  message.

### 3.3 Why isolation holds

Even a fully-compromised public API cannot map physical topology: it can read intent (strategy,
opaque capability labels, zone) and result (`SATISFIED`/`DEGRADED`, a spread **count**), but there
is no field, RPC, or filter that returns a host, rack, pool, capacity number, or another tenant's
placement. The scheduler and pool live behind mTLS + per-RPC authz on :9091. This is
defense-in-depth against lateral-movement reconnaissance ("is my instance on the same iron as
tenant *A*?" is unanswerable).

### 3.4 Placement without a data-plane (control-plane semantics for now)

There is no hypervisor/scheduler daemon yet. In this increment placement is **control-plane
slot-accounting**: the allocator books a slot + a failure-domain in the NodePool inside the Create
`Operation` worker TX (synthetic, like the current instant `PROVISIONING→RUNNING`). This gives real,
enforced spread/anti-affinity/capacity/quota semantics and a stable tenant contract **today**, and
becomes the desired-state input to a real reconciler/hypervisor later (the beget-draft
`ClaimWork + ReportStatus` over `FOR UPDATE SKIP LOCKED` pattern) with **no tenant-facing change**.

---

## 4. Growth areas (headroom, not v1)

- **Instance kinds** — Container (locked as an Instance sibling, OCI-delivered) then Baremetal /
  dedicated (sole-tenant) tenancy via NodePool `kind=DEDICATED`.
- **Real scheduler + reconciler / data-plane** — hypervisor/kubelet-like agent consuming the
  control-plane desired state; live-migration (`Instance.Relocate`), maintenance
  drain/evacuate/windows, `MIGRATE` maintenance policy.
- **Storage depth** — multi-attach / RWX (composite PK + `max_attachments`/`shareable`); QoS-rich
  DiskType (`iops_*`, `throughput_*`, min/max/step); snapshot restore/clone/incremental/schedules;
  at-rest encryption + CMK (kacho-kms); boot-from-Volume canonical flow; local ephemeral disks.
- **Compute depth** — GPU/accelerator inventory + scheduling (GpuCluster); InstanceGroup + managed
  autoscaling; ReservedInstancePool / capacity reservations; Filesystem (shared/network FS);
  cloud-init/ignition `user_data` rendering + IMDS metadata service (data-plane); SSH-key resource.
- **Platform** — metering/usage + billing hooks (vCPU-s / GiB-month / egress; off the tenant infra
  surface); Object storage (kacho-object); per-resource AccessBindings (currently stubs);
  region/anycast instances if multi-zone placement is desired.
- **Registry** — real OCI content-pinning (`image_digest` resolve, currently deferred/empty).

---

## 5. Open design decisions to confirm

1. **Instance-kind discriminator** — add `instance_type {VM|CONTAINER|BAREMETAL}` on `Instance`
   now (with per-kind spec), or keep VM-only and branch later? Does **Container ship in v1** or is
   it the next phase?
2. **Sizing catalog** — introduce a first-class **MachineType** catalog (queryable/bookable, DiskType
   parity) or keep free-form `resources{vcpus,memory}` validated by an in-code platform table?
3. **Placement ownership** — does `kacho-compute` own **NodePool + PlacementGroup + scheduler**, or
   do failure-domains live in a **geo** host-inventory leaf (geo already owns Region/Zone), or a new
   dedicated `kacho-placement`/`kacho-capacity` service? (Affects the build-graph + edges.)
4. **Placement semantics now** — accept **control-plane slot-accounting** (real spread/quota, no
   data-plane) as the v1 contract, deferring the actual scheduler daemon? Or block placement until a
   reconciler exists?
5. **Quota owner** — new `Quota` resource in `kacho-iam` (project-scoped), per-service local quotas,
   or a central `kacho-quota`? And confirm the `FAILED_PRECONDITION "insufficient capacity"` /
   quota-exceeded error convention (absent from rules today).
6. **Two-projection enforcement** — add a corelib helper + a gateway projection-audit gate
   (analogous to `make audit-list-filter`) so no additive field leaks infra data onto the public
   surface — build it as part of this epic?
7. **Multi-attach / RWX volumes** — v1 or growth? (Drives Volume `shareable` + composite-PK model
   vs current single-attach PK=volume_id.)
8. **Boot model** — canonical **ephemeral OCI rootfs** (Image retiring), with optional persistent
   boot-overlay via `AttachedVolume.is_boot`, or a fully-specified **boot-from-Volume** flow?
9. **Regional/anycast instances** — add `placement_type` to `Instance` (mirror Subnet/NLB) for
   regional placement, or keep compute strictly zonal?
10. **Foreign-cloud cleanup** — confirm we discard the unbacked YC-derived placement protos
    (`placement_group/host_group/reserved_instance_pool` with `cloud_id`/`folder`/`yc.*` keys) and
    author fresh Kachō-native ones (ban #2) rather than adapt them.
11. **Idempotency-key** — adopt a request-level idempotency-key convention on Create/heavy mutations
    (beget-draft §11.4), currently unspecified in `api-conventions.md`?
12. **Stale-rule reconciliation** — confirm `kacho-geo` as Geography owner and `kacho-storage` as
    Volume owner, and fix `data-integrity.md` rule 5 + `00-core`/`security.md` `/compute/v1/{regions,zones}`
    residues before coding.
