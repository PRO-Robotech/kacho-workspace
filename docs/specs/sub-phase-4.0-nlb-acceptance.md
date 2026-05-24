# Sub-phase 4.0 — kacho-nlb (L4 Network Load Balancer control-plane, production rewrite) — Acceptance

> **Status**: DRAFT v1 — awaiting `acceptance-reviewer`
> **Date**: 2026-05-23
> **YouTrack**: KAC-NLB (epic to be created; ~21 subtasks per design §8.2)
> **Design source**: `docs/superpowers/specs/2026-05-23-kacho-nlb-design.md` (8-section consolidated brainstorming output)
> **Predecessor (obsolete)**: `sub-phase-0.5-loadbalancer-acceptance.md` — JSONB-envelope era, full-replace `attachedTargetGroups[]`, simulated reconciler, no FGA. This document **supersedes** 0.5 entirely: NLB is rewritten greenfield as a production-grade service aligned with current paradigm (flat resources + Operation LRO + FGA REBAC + plain SQL columns + outbox/LISTEN/NOTIFY lifecycle). No backward-compat with 0.5 is required.
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`
> **Approval gate**: workspace `CLAUDE.md` запрет #1 — without `✅ APPROVED` here, кодирование не начинается.

---

## 0. Преамбула

`kacho-nlb` — новый сервис L4-балансировщика для control-plane Kachō. Три публичных ресурса (`NetworkLoadBalancer`, `Listener`, `TargetGroup`), одна embedded child-таблица (`targets`) и одна M:N pivot-таблица (`attached_target_groups`). Сервис production-ready, без data-plane sibling-репо, без tech debt. Единственный отложенный пункт — `GlobalLoadBalancer` (cross-region композитный layer): только зарезервированные proto-field-numbers + `glb` id-prefix + architecture doc, **без** имплементации.

Архитектурно соблюдается paradigm Kachō 2026 (post-1.0):
- **flat resources** (`metadata` плоский в proto, без `spec`/`status` JSONB envelope; status — отдельный enum-столбец);
- **Operation LRO** на каждую мутацию (запрет #9; sync read OK);
- **FGA REBAC** для authz (KAC-108 model: per-RPC Check через `iam.InternalIAMService.Check`);
- **outbox + LISTEN/NOTIFY** для resource-lifecycle events (D-13 stream к `kacho-iam` для tuple-sync);
- **DB-уровень FK / CHECK / UNIQUE / EXCLUDE / atomic-CAS** для within-service инвариантов (запрет #10);
- **3-char-prefix + 17 base32** id-формат (`kacho-corelib/ids`): `nlb` / `lst` / `tgr`, reserved `glb`;
- **VIP allocation** — auto через `vpc.InternalAddressService` ИЛИ BYO существующий `vpc.Address` (cross-service, sync precheck + `SetReference` atomic CAS);
- **4-way Target identity oneof** — `instance_id` | `nic_id` | `ip_ref` (in-cloud raw IP) | `external_ip` (out-of-cloud);
- **same-region constraint** — LB и каждая прикреплённая TG обязаны быть в одном `region_id`;
- **FK RESTRICT** на каждом ребре — удаление снизу вверх (Target → AttachedTG → Listener → TargetGroup → LoadBalancer);
- **2-phase RemoveTargets drain** — Phase A immediate `DRAINING`-mark, Phase B background `DELETE` после `deregistration_delay_seconds`.

После APPROVE этого документа стартует rpc-implementer chain (21 subtask, ~6-8 недель).

### 0.1 Что НЕ входит

- `GlobalLoadBalancer` (cross-region композитный LB, AWS-style) — только reserved slot (proto-field-numbers + id-prefix `glb` + `docs/architecture/12-future-cross-region.md` design-only). См. §16 "Out-of-scope".
- Реальная L4-датаплейн (eBPF / SRv6 / kernel-native forwarding) — `kacho-nlb` это control-plane only; data-plane sibling-репо не создаётся.
- Реальные healthcheck-probes к бэкендам (TCP/HTTP/HTTPS/gRPC) — `HealthCheck` хранится как desired config; `GetTargetStates` возвращает **детерминированный computed-ramp**: `INITIAL` пока `age < interval × healthy_threshold`, затем `HEALTHY` (либо `DRAINING` / `INACTIVE` по состоянию LB/target).
- Cross-region NLB. LB и все его TG обязаны быть в одном `region_id`. Cross-region — `GlobalLoadBalancer` (out-of-scope).
- `kacho-yc-shim` compat-слой (необязательный поздний adapter).
- Per-permission fine-grained FGA-relation expansion для custom-roles на partition `start+stop only` — резолвится через 3 FGA relations (`viewer`/`editor`/`owner`); fine-grained expansion остаётся за iam team (KAC-108 follow-up). NLB MVP пользуется existing model.

### 0.2 Зафиксированные соглашения

- `Upsert`-семантика **не используется**. Все мутации — explicit `Create` / `Update` / `Delete` (запрет #9 + design §3.1 contract).
- Все мутации возвращают `operation.Operation` (async LRO); reads sync.
- `status` — отдельный enum-столбец в БД (не JSONB envelope) — записывается **только** worker'ом операции и DB-side trigger'ом `lb_status_recompute` (для transitions `INACTIVE ↔ ACTIVE`). Клиент **не** может пропихнуть `status` через `Create`/`Update` — игнорируется handler'ом (handler читает только whitelisted `spec`-эквивалентные поля).
- `attached_target_groups` — M:N pivot-таблица с **idempotent `INSERT ... ON CONFLICT DO NOTHING`** через `AttachTargetGroup` RPC. Это **полностью отменяет** старую full-replace семантику `attached_target_groups[]` из 0.5 (нет такого поля в proto NLB-message; есть отдельные RPC Attach/Detach).
- `targets` — embedded child-таблица с **partial UNIQUE NULLS NOT DISTINCT** на 4-way identity → `AddTargets` идемпотентен (`INSERT ... ON CONFLICT DO NOTHING`).
- `RemoveTargets` — 2-phase:
  - **Phase A** (синхронно в worker, latency <500 ms): `UPDATE targets SET status='DRAINING', drain_started_at=now()` → `ops.MarkDone(true)` (client gets done=true immediately).
  - **Phase B** (background `target_drain_runner` job, period 10s): `DELETE FROM targets WHERE status='DRAINING' AND drain_started_at < now() - tg.deregistration_delay_seconds`. Outbox event `nlb_target_group:<tg_id> UPDATED` emitted после успешного DELETE.
- All временны́е assertions используют timeout 60 s (≥ 2× expected worker latency).
- Newman case-id префиксы: `NLB-*` / `LST-*` / `TGR-*` / `TGT-*` / `OP-*` / `AZD-*`.
- **Permission catalog** — 30 строк под namespace `loadbalancer.*` (design §6.2), registered в `kacho-iam/internal/authzmap/permission_catalog.go`. Custom roles `iam.Role.permissions[]` валидируются против catalog (`InvalidArgument` на unknown).

### 0.3 Глоссарий

| Термин | Расшифровка |
|---|---|
| **LB** / **NLB** | NetworkLoadBalancer ресурс (id-prefix `nlb`) |
| **TG** | TargetGroup ресурс (id-prefix `tgr`) |
| **Listener** | Listener ресурс (id-prefix `lst`) |
| **VIP** | Virtual IP — публичный IPv4/v6 на котором слушает Listener |
| **BYO** | Bring-Your-Own — клиент указал `address_id` существующего `vpc.Address` |
| **drain** | Phase B 2-phase remove — реальный DELETE из БД после `deregistration_delay_seconds` |
| **FGA** | OpenFGA REBAC модель (KAC-108) — для authz Check |
| **D-13 stream** | `InternalResourceLifecycleService.Subscribe` — server-stream к `kacho-iam` для tuple-sync |
| **CAS** | Compare-And-Swap — atomic conditional `UPDATE ... WHERE <expected-state>` |

---

## 1. Связь с регламентом и запретами (нормативно)

| # | Запрет workspace `CLAUDE.md` | Применение в NLB |
|---|---|---|
| 1 | Не начинать кодинг до APPROVED acceptance | Этот документ + reviewer cycle → APPROVED → `superpowers:writing-plans` → integration-tester → rpc-implementer chain |
| 2 | Не упоминать `yandex` | Все error-text / env / комментарии / id — `kacho.cloud.*` / `KACHO_NLB_*` / `nlb`. Стиль (camelCase JSON, error-format) — YC-like; **структурные** различия (Listener как first-class, 4-way Target identity, FGA per-RPC) — by-design |
| 3 | Не ORM | sqlc + pgx; все queries — handwritten / sqlc-generated |
| 4 | Не каскадно удалять через границу сервиса | Cross-service refs (`region_id`, `project_id`, `address_id`, `subnet_id`, `instance_id`, `nic_id`) — soft (sync `Get` precheck в request-path; dangling read graceful). Same-DB FK — все `RESTRICT` |
| 5 | Не редактировать применённую миграцию | Baseline `0001_initial.sql` squashed inline (kacho-vpc convention). Any post-merge change — новая миграция |
| 6 | `Internal.*` не на external endpoint | `InternalResourceLifecycleService` — port 9091, cluster-internal. Не маршрутизируется через api-gateway на TLS 443 |
| 7 | Не broker (Kafka/NATS) | LISTEN/NOTIFY на dedicated pgx-conn (`nlb_outbox` channel) — godzila §16 outbox pattern |
| 8 | Не cross-DB FK | Все cross-service FK невозможны (database-per-service). Соблюдается через peer-API Get + outbox-pattern |
| 9 | Не sync возврат ресурса из мутаций | Все мутации возвращают `operation.Operation`. Client polls `OperationService.Get(id)` |
| 10 | Не software refcheck для within-DB инвариантов | DB-level FK/UNIQUE/CHECK/atomic-CAS: `attached_target_groups` ON CONFLICT idempotent; `targets` partial UNIQUE NULLS NOT DISTINCT per identity-type; `listeners` UNIQUE `(region_id, allocated_address, port, protocol) WHERE status!='DELETING'` |
| 11 | Не мёрджить новый RPC без тестов в том же PR | Каждый из 5 implementation PR'ов (Foundation / Repo+Ops / LB+Listener / TG+Targets+Attach / Authz+Lifecycle+CI) содержит integration + newman + RED-before-GREEN proof |

**Связь с evgeniy / godzila** (skills):
- §1.A — repo layout (`cmd/<svc>` + `cmd/migrator`; `internal/apps/kacho/api/<resource>/` per-resource UseCase; thin handler).
- §2.B — UseCase pattern (slice-per-RPC files: `create.go`/`update.go`/`delete.go`/`start.go`/...).
- §4.D — self-validating domain newtypes (`LbName`, `LbPort`, `IPVersion`, ...); голый `string` запрещён.
- §6.G — CQRS Repository (`Reader`/`Writer` TX split; atomic Writer-TX с outbox-emit в той же TX).
- §16 — outbox + LISTEN/NOTIFY на dedicated pgx-conn (`nlb_outbox` channel).

---

## 2. Архитектурный обзор (компактно)

### 2.1 Resources

```
NetworkLoadBalancer  (id: nlb…)  ──┬── 1:N → Listener (id: lst…)            FK RESTRICT
                                   └── M:N → TargetGroup (id: tgr…)         pivot attached_target_groups
TargetGroup          (id: tgr…)  ──── 1:N → Target (4-way oneof)            FK RESTRICT, embedded child
```

Status enums:

| Resource | Enum values |
|---|---|
| `NetworkLoadBalancer.status` | `CREATING` / `STARTING` / `ACTIVE` / `STOPPING` / `STOPPED` / `DELETING` / `INACTIVE` |
| `Listener.status` | `CREATING` / `ACTIVE` / `UPDATING` / `DELETING` |
| `TargetGroup.status` | `ACTIVE` / `DELETING` |
| `Target.status` (computed via `GetTargetStates`) | `INITIAL` / `HEALTHY` / `UNHEALTHY` / `DRAINING` / `INACTIVE` |

### 2.2 Services × RPC count

| Service | Port | Visibility | Mutating | Read | Stream | Total |
|---|---|---|---|---|---|---|
| `NetworkLoadBalancerService` | 9090 | public | 8 | 4 | — | **12** |
| `ListenerService` | 9090 | public | 3 | 3 | — | **6** |
| `TargetGroupService` | 9090 | public | 6 | 3 | — | **9** |
| `OperationService` | 9090 | public | 1 (`Cancel`) | 2 | — | **3** |
| `InternalResourceLifecycleService` | 9091 | cluster-internal | — | — | 1 | **1** |
|  |  |  |  |  | **Total RPC** | **31** |

Authz: каждый из 30 публичных RPC проходит через FGA Check-interceptor (1 Check per RPC, NFR-3 from KAC-108); 1 `OperationService.Cancel` — owner-scope check (только creator может cancel свою op); `InternalResourceLifecycleService.Subscribe` — system-only через cluster-internal port + SPIRE/mTLS (см. §13).

### 2.3 Cross-service edges (runtime)

| Edge | Direction | Sync / Async | Purpose |
|---|---|---|---|
| `nlb → iam.InternalIAMService.Check` | sync gRPC | sync ≤20ms | per-RPC FGA Check (interceptor) |
| `nlb → iam.ProjectService.Get` | sync gRPC | sync | `project_id` validation на Create |
| `nlb → compute.RegionService.Get` | sync gRPC | sync | `region_id` validation на NLB/TG.Create |
| `nlb → vpc.AddressService.Get + InternalAddressService.SetReference` | sync gRPC | sync | BYO `address_id`: ownership-check + atomic CAS `used_by=nlb_listener:<id>` |
| `nlb → vpc.InternalAddressService.AllocateExternalIP/AllocateInternalIP` | sync gRPC | sync | auto-allocate VIP при Listener.Create без BYO |
| `nlb → vpc.InternalAddressService.FreeIP` | sync gRPC | sync (best-effort) | free VIP на Listener.Delete + compensation на Create failure |
| `nlb → vpc.SubnetService.Get` | sync gRPC | sync | INTERNAL Listener subnet validation + `Target.ip_ref.subnet_id` |
| `nlb → vpc.NetworkInterfaceService.Get` | sync gRPC | sync | `Target.nic_id` → primary IP resolve |
| `nlb → compute.InstanceService.Get` | sync gRPC | sync | `Target.instance_id` → primary NIC → primary IP |
| `nlb → iam.InternalIAMService.WriteCreatorTuple` | sync gRPC | sync (in worker, before commit) | D-11 sync creator-tuple FGA write |
| `iam → nlb.InternalResourceLifecycleService.Subscribe` | gRPC server-stream | async (long-lived) | D-13 lifecycle event stream for FGA tuple-sync (`CREATED` / `UPDATED` / `DELETED` / `MOVED`) |

Циклы запрещены — все направления `nlb → *`, обратно только `iam` subscribe.

### 2.4 ID prefixes (`kacho-corelib/ids`)

| Resource | Const | Prefix |
|---|---|---|
| LoadBalancer | `PrefixLoadBalancer` | `nlb` |
| Listener | `PrefixListener` | `lst` |
| TargetGroup | `PrefixTargetGroup` | `tgr` |
| Operation (NLB) | `PrefixOperationNLB` (alias = `PrefixLoadBalancer`) | `nlb` |
| **GlobalLoadBalancer (reserved)** | `PrefixGlobalLoadBalancer` | `glb` |

### 2.5 Outbox events (одна TX с мутацией)

| RPC | Events emitted |
|---|---|
| `NLB.Create` | `nlb_load_balancer:<id> CREATED` |
| `NLB.Update` / `Start` / `Stop` / `Move` | `nlb_load_balancer:<id> UPDATED` (Move дополнительно `MOVED`) |
| `NLB.Delete` | `nlb_load_balancer:<id> DELETED` |
| `NLB.AttachTargetGroup` / `DetachTargetGroup` | `nlb_load_balancer:<id> UPDATED` |
| `Listener.Create` | `nlb_listener:<id> CREATED` + `nlb_load_balancer:<lb_id> UPDATED` |
| `Listener.Update` / `Delete` | `nlb_listener:<id> UPDATED/DELETED` + `nlb_load_balancer:<lb_id> UPDATED` |
| `TG.Create` | `nlb_target_group:<id> CREATED` |
| `TG.Update` / `Move` | `nlb_target_group:<id> UPDATED/MOVED` |
| `TG.Delete` | `nlb_target_group:<id> DELETED` |
| `TG.AddTargets` / `RemoveTargets` Phase A | `nlb_target_group:<id> UPDATED` |
| `TG.RemoveTargets` Phase B (background DELETE) | `nlb_target_group:<id> UPDATED` |

---

## 3. NetworkLoadBalancer scenarios (NLB-*)

### GWT-NLB-001 — Create LB (happy path, EXTERNAL, idempotent ops)

**Given**
- Project `prj-acme-prod` (`project_id = <prj-id>`) существует в `kacho-iam`.
- Region `ru-central1` существует в `kacho-compute`.
- Subject `user:alice` имеет FGA-tuple `project:<prj-id>#editor@user:alice`.

**When** subject вызывает `kacho.cloud.loadbalancer.v1.NetworkLoadBalancerService.Create`:
```
project_id      = <prj-id>
region_id       = "ru-central1"
name            = "edge-public"
description     = "edge L4 entry-point"
labels          = {env: "prod"}
type            = EXTERNAL
session_affinity = FIVE_TUPLE
cross_zone_enabled = true
deletion_protection = false
```

**Then**
- gRPC status = `OK`.
- Response: `operation.Operation` с `id` ∈ `nlb\d{17}` format, `done = false`, `metadata = CreateNetworkLoadBalancerMetadata{network_load_balancer_id: <nlb-id>}`.
- В течение 60 s polling `OperationService.Get(id)` возвращает `done = true`, `response.value = NetworkLoadBalancer{id=<nlb-id>, status=INACTIVE, ...}`.
- В БД `load_balancers` есть row с `id=<nlb-id>`, `status='INACTIVE'` (нет listeners + нет attached TG → trigger `lb_status_recompute` оставляет `INACTIVE`).
- Outbox: 1 row `nlb_load_balancer:<nlb-id> CREATED` с тем же `sequence_no`, доставлен через D-13 stream к `kacho-iam`.
- FGA tuples (sync D-11 + lifecycle):
  - `nlb_load_balancer:<nlb-id>#owner@user:alice` (sync, до commit).
  - `nlb_load_balancer:<nlb-id>#project@project:<prj-id>` (async via D-13).

### GWT-NLB-002 — Create LB (INTERNAL type)

**Given** Project + Region as NLB-001; subject editor.

**When** Create с `type=INTERNAL`, остальные поля как в 001.

**Then** OK; resulting LB has `type=INTERNAL`. (Note: INTERNAL не требует никаких subnet/network полей на LB-уровне — это уровень Listener-а через `subnet_id`.)

### GWT-NLB-003 — Create LB validation: invalid name regex

**Given** subject editor on project.

**When** Create с `name="Edge_Public!"` (содержит `_` и `!`).

**Then** gRPC status = `INVALID_ARGUMENT`; `details[0]` = `BadRequest.field_violations[0].field = "name"`; verbatim error text contains `"<LbName> must match ^[a-z][-a-z0-9]{1,61}[a-z0-9]$"` (`LbName.Validate()`). LB **не создана**.

### GWT-NLB-004 — Create LB validation: name length boundary (BVA)

**Given** subject editor.

**When** Create с (a) `name=""`, (b) `name="ab"` (2 chars), (c) `name="a"+62*"b"+"c"` (64 chars).

**Then** все три → `INVALID_ARGUMENT`. (a) `"name is required"`; (b)/(c) regex/length violation. Boundary `name="abc"` (3 chars) and `name="a"+61*"b"+"c"` (63 chars) — `OK` (covered separately).

### GWT-NLB-005 — Create LB: missing region_id → INVALID_ARGUMENT

**Given** subject editor.

**When** Create без `region_id` (пустая строка).

**Then** `INVALID_ARGUMENT`; field `"region_id"`.

### GWT-NLB-006 — Create LB: unknown region_id → NOT_FOUND (cross-service)

**Given** subject editor; `region_id="ru-doesnt-exist"`; `compute.RegionService.Get` returns `NotFound`.

**When** Create.

**Then** gRPC status = `NOT_FOUND`; `details[]` содержит `ResourceInfo{resource_type:"Region", resource_id:"ru-doesnt-exist"}`. LB не создана.

### GWT-NLB-007 — Create LB: unknown project_id → NOT_FOUND (cross-service)

**Given** subject editor (на каком-то другом project; здесь FGA Check выполнен на target project, который не существует).

**When** Create с `project_id="prj00000000000000xxx"` (несуществующий).

**Then** `NOT_FOUND` (`iam.ProjectService.Get` → `NotFound`); либо `PermissionDenied` если subject **не** имеет editor на этом несуществующем project — fail-closed FGA pattern; конкретно — `PermissionDenied` (Check выполняется первым в interceptor, FGA не находит path → DecisionNoPath → fail-closed). Acceptance: одно из двух фиксированных значений (см. §15 fail-mode), depending на whether subject имел editor-tuple. Newman tests cover both branches explicitly.

### GWT-NLB-008 — Create LB: peer kacho-compute unavailable → UNAVAILABLE

**Given** `kacho-compute` недоступен (network partition imitation).

**When** Create with valid `region_id`.

**Then** gRPC status = `UNAVAILABLE`; `details[]` содержит `RequestInfo{request_id}`. LB **не** создана. Outbox **не** записал ничего.

### GWT-NLB-009 — Create LB: duplicate (project_id, name) → ALREADY_EXISTS

**Given** LB `name="edge-public"` уже существует в `project=<prj-id>`.

**When** subject editor вызывает Create с тем же `name` в том же project.

**Then** Operation worker возвращает `error.value = Status{code: ALREADY_EXISTS}`, verbatim message `"NetworkLoadBalancer 'edge-public' already exists in project <prj-id>"`. SQL: partial UNIQUE `(project_id, name) WHERE name <> ''` отлавливает 23505 → `mapRepoErr` → `ALREADY_EXISTS`. LB-2 не создана. `ops.MarkDone(error)` — client получает `done=true` с error.

### GWT-NLB-010 — Get LB (happy path)

**Given** LB `<nlb-id>` существует в `ACTIVE`; subject `user:bob` имеет `viewer` на project.

**When** `NetworkLoadBalancerService.Get(network_load_balancer_id=<nlb-id>)`.

**Then** OK; response = `NetworkLoadBalancer{id, project_id, region_id, name, description, labels, type, status=ACTIVE, session_affinity, cross_zone_enabled, deletion_protection, created_at, updated_at}`. No `address`/`vip` поля (это уровень Listener).

### GWT-NLB-011 — Get LB: unknown id → NOT_FOUND

**Given** subject editor.

**When** Get с `network_load_balancer_id="nlb00000000000000xx"`.

**Then** `NOT_FOUND`; `ResourceInfo{resource_type:"NetworkLoadBalancer", resource_id:"<id>"}`. (FGA Check returns `DecisionNoPath` for non-existent object → passthrough to DB → NotFound, KAC-133 pattern.)

### GWT-NLB-012 — List LB (filter name=, paginate)

**Given** В project `<prj-id>` существуют 5 LB: `edge-public`, `edge-private`, `api-v1`, `api-v2`, `internal-grpc`; subject viewer.

**When** `List(project_id=<prj-id>, filter='name=edge-*', page_size=2)` (filter — substring/glob по spec).

**Then** OK; `network_load_balancers[]` содержит 2 LB с `name` начинающимися с `edge-`; `next_page_token` непустой.

### GWT-NLB-013 — List LB: pagination next page

**Given** Following NLB-012.

**When** Repeat List с `page_token = <next_page_token>`.

**Then** OK; remaining matching LBs returned; `next_page_token` пустой если this is last page.

### GWT-NLB-014 — List LB: empty project → empty list

**Given** project `<prj-empty>` без LB; subject viewer.

**When** `List(project_id=<prj-empty>)`.

**Then** OK; `network_load_balancers = []`, `next_page_token = ""`.

### GWT-NLB-015 — Update LB: mutable fields (name/description/labels/session_affinity/cross_zone_enabled/deletion_protection)

**Given** LB `<nlb-id>` в `ACTIVE`; subject editor.

**When** `Update(network_load_balancer_id=<nlb-id>, update_mask=["name","description","labels","session_affinity"], name="edge-public-v2", description="updated", labels={env:"prod",tier:"edge"}, session_affinity=CLIENT_IP_ONLY)`.

**Then** OK; Operation done=true; `Get` returns LB с обновлёнными полями. Outbox: 1 row `nlb_load_balancer:<id> UPDATED`.

### GWT-NLB-016 — Update LB: immutable type → INVALID_ARGUMENT

**Given** LB `<nlb-id>` `type=EXTERNAL`.

**When** Update с `update_mask=["type"]`, `type=INTERNAL`.

**Then** `INVALID_ARGUMENT`; verbatim `"type is immutable after NetworkLoadBalancer.Create"`; LB не изменена.

### GWT-NLB-017 — Update LB: immutable region_id → INVALID_ARGUMENT

**Same as NLB-016** для `region_id`. Verbatim text: `"region_id is immutable after NetworkLoadBalancer.Create"`.

### GWT-NLB-018 — Update LB: immutable project_id → INVALID_ARGUMENT (Move is separate RPC)

**Same** для `project_id`. Verbatim text: `"project_id is immutable after NetworkLoadBalancer.Create; use Move to transfer between projects"`.

### GWT-NLB-019 — Update LB: empty update_mask → INVALID_ARGUMENT

**Given** subject editor.

**When** Update без `update_mask` (или empty list).

**Then** `INVALID_ARGUMENT`; `"update_mask is required"`.

### GWT-NLB-020 — Update LB: unknown field в update_mask → INVALID_ARGUMENT

**When** Update с `update_mask=["nonexistent_field"]`.

**Then** `INVALID_ARGUMENT`; `"unknown field 'nonexistent_field' in update_mask"`.

### GWT-NLB-021 — Update LB concurrency (atomic xmin OCC)

**Given** Two concurrent clients C1, C2 read LB `<nlb-id>` simultaneously. Both call Update.

**When** C1 commit succeeds first.

**Then** C2 commit → 0 rows affected (xmin no-match) → worker maps to `ABORTED` (verbatim `"concurrent update; please retry"`); C2 retries with fresh Get → succeeds. Integration test: spawn 2 goroutines, assert exactly one OK + one ABORTED.

### GWT-NLB-022 — Start LB (precondition: STOPPED or INACTIVE)

**Given** LB `<nlb-id>` в `INACTIVE`; subject editor.

**When** `Start(network_load_balancer_id=<nlb-id>)`.

**Then** OK; Operation worker → `status` транзитит `STARTING` → after trigger `lb_status_recompute` оценивает `has_listener && has_attached_tg`: если оба true → `ACTIVE`, иначе остаётся в `INACTIVE` после `STARTING` mark. Outbox: `UPDATED`.

### GWT-NLB-023 — Start LB: already ACTIVE → FAILED_PRECONDITION

**Given** LB `<nlb-id>` в `ACTIVE`.

**When** `Start`.

**Then** `FAILED_PRECONDITION`; `"NetworkLoadBalancer is not in STOPPED or INACTIVE state (current: ACTIVE)"`.

### GWT-NLB-024 — Stop LB (precondition: ACTIVE or INACTIVE)

**Given** LB `<nlb-id>` в `ACTIVE`.

**When** `Stop`.

**Then** OK; worker transitions `STOPPING` → `STOPPED`. Outbox: `UPDATED`.

### GWT-NLB-025 — Stop LB: already STOPPED → FAILED_PRECONDITION

**Given** LB в `STOPPED`.

**When** `Stop`.

**Then** `FAILED_PRECONDITION`; `"NetworkLoadBalancer is already in STOPPED state"`.

### GWT-NLB-026 — Stop LB: status=DELETING → FAILED_PRECONDITION

**Given** LB в `DELETING`.

**When** `Stop`.

**Then** `FAILED_PRECONDITION`; `"NetworkLoadBalancer is being deleted"`.

### GWT-NLB-027 — Move LB cross-project (same-region; no attached TG)

**Given** LB `<nlb-id>` в `project=<prj-src>`; `project=<prj-dst>` существует; subject имеет `editor` на **обоих** projects.

**When** `Move(network_load_balancer_id=<nlb-id>, destination_project_id=<prj-dst>)`.

**Then** OK; worker `UPDATE load_balancers SET project_id=<prj-dst>` + same TX `UPDATE listeners SET project_id=<prj-dst> WHERE load_balancer_id=<nlb-id>` (denorm sync); outbox `MOVED`; FGA tuples rewritten (delete old project tuple, write new). Get returns LB с новым `project_id`.

### GWT-NLB-028 — Move LB: subject lacks editor on dst project → PERMISSION_DENIED

**Given** LB в `<prj-src>`; subject `editor` only on `<prj-src>`, **viewer** on `<prj-dst>`.

**When** Move.

**Then** `PERMISSION_DENIED`. Scope-conditional check: interceptor выполняет 2 Check (`editor` on src + `editor` on dst). Verbatim `"permission denied: editor on project <prj-dst>"`.

### GWT-NLB-029 — Move LB: has attached TG → FAILED_PRECONDITION

**Given** LB has ≥1 attached TG.

**When** Move.

**Then** `FAILED_PRECONDITION`; `"NetworkLoadBalancer has attached target group(s); detach before moving"`. LB не moved.

### GWT-NLB-030 — Move LB: dst project in different region (region_id is denormed on TG; constraint on LB itself is no-op here)

**Note:** LB `region_id` immutable (NLB-017). Move меняет только `project_id`, не `region_id`. Если `dst project` ассоциирован с другим default region — это OK на уровне Move (project-region link не существует в Kachō; project = namespace, region = LB self-attribute).

**Given** Move выполняется как в NLB-027.

**Then** OK; `region_id` LB не изменился; pre-existing attached_target_groups (если бы существовали) — заблокировали бы (NLB-029).

### GWT-NLB-031 — AttachTargetGroup (same-region, idempotent ON CONFLICT)

**Given** LB `<nlb-id>` в region `ru-central1`; TG `<tg-id>` в region `ru-central1`, project совпадает; subject editor on LB + viewer on TG.

**When** `AttachTargetGroup(network_load_balancer_id=<nlb-id>, target_group_id=<tg-id>, priority=100)`.

**Then** OK; Operation done; in БД `attached_target_groups` row `(<nlb-id>, <tg-id>, 100)`. Outbox: `nlb_load_balancer:<nlb-id> UPDATED`. trigger `attached_tg_lb_status_recompute` пересчитывает: если has_listener+has_attached_tg → LB transitions `INACTIVE → ACTIVE`.

### GWT-NLB-032 — AttachTargetGroup: TG в другом региона → FAILED_PRECONDITION

**Given** LB в `ru-central1`; TG в `ru-central2`.

**When** Attach.

**Then** `FAILED_PRECONDITION`; verbatim `"target group region <ru-central2> does not match load balancer region <ru-central1>"`. Row не добавлен.

### GWT-NLB-033 — AttachTargetGroup: repeat (idempotent)

**Given** Уже существует attached (<nlb>, <tg>, priority=100).

**When** Repeat Attach с тем же `(nlb, tg, priority=100)`.

**Then** OK; `INSERT ... ON CONFLICT (load_balancer_id, target_group_id) DO NOTHING`; одна row в БД (без duplicate); outbox event эмиттится повторно (UPDATED — это OK; D-13 consumer идемпотентен).

### GWT-NLB-034 — AttachTargetGroup: same TG with different priority → updates priority (ON CONFLICT DO UPDATE)

**Given** Attached (<nlb>, <tg>, priority=100).

**When** Attach с `priority=50`.

**Then** OK; SQL `ON CONFLICT (load_balancer_id, target_group_id) DO UPDATE SET priority=EXCLUDED.priority`; row updated to priority=50. Outbox `UPDATED`.

### GWT-NLB-035 — AttachTargetGroup: priority out-of-range → INVALID_ARGUMENT

**When** Attach с `priority=2000` (max=1000).

**Then** `INVALID_ARGUMENT`; `"priority must be in range [0, 1000]"`.

### GWT-NLB-036 — AttachTargetGroup: unknown TG → NOT_FOUND

**When** Attach с `target_group_id="tgr00000000000000xx"` (несуществующий).

**Then** `NOT_FOUND`; `ResourceInfo{resource_type:"TargetGroup"}`.

### GWT-NLB-037 — AttachTargetGroup: TG в DELETING → FAILED_PRECONDITION

**Given** TG в `status=DELETING`.

**When** Attach.

**Then** `FAILED_PRECONDITION`; `"target group is being deleted"`.

### GWT-NLB-038 — DetachTargetGroup (respects deregistration delay)

**Given** Attached (<nlb>, <tg>); TG `deregistration_delay_seconds=300`; TG has 2 active targets in `HEALTHY` state on this LB.

**When** `DetachTargetGroup(network_load_balancer_id=<nlb>, target_group_id=<tg>)`.

**Then** Operation done immediately; in БД `attached_target_groups` row deleted. Active targets на other LB attachments не affected. Outbox `UPDATED`. trigger `attached_tg_lb_status_recompute` может перевести LB в `INACTIVE` если был последний attached + no listeners.

**Note**: deregistration_delay_seconds is a per-TG setting that applies during `TG.RemoveTargets` (Phase B drain). On `DetachTargetGroup`, the pivot row is removed immediately — targets themselves are not deleted (they remain in TG, just no longer routed via this LB). Verified explicitly: TG row count == before; only `attached_target_groups` row removed.

### GWT-NLB-039 — DetachTargetGroup: not attached → FAILED_PRECONDITION (idempotency variant)

**Given** No row `(<nlb>, <tg>)` в `attached_target_groups`.

**When** Detach.

**Then** `FAILED_PRECONDITION`; verbatim `"target group is not attached to this load balancer"`. (Alternative: OK idempotent — design §3.2 says idempotent via ON CONFLICT — but Detach has no ON CONFLICT, it's a DELETE; if 0 rows affected → FailedPrecondition is the chosen contract.)

### GWT-NLB-040 — GetTargetStates (sync, computed)

**Given**
- LB `<nlb-id>` `ACTIVE`, region `ru-central1`.
- Attached TG `<tg-id>` с 3 targets:
  - T1 `{instance_id: <inst-1>}` — created 10 min ago (`age > interval × healthy_threshold`).
  - T2 `{nic_id: <nic-2>}` — created 5 s ago (`age < interval × healthy_threshold = 4s`; just inside ramp).
  - T3 `{external_ip: 8.8.8.8}` — `status=DRAINING` (recently RemoveTargets Phase A).
- HealthCheck `interval=2s`, `healthy_threshold=2`.

**When** `NetworkLoadBalancerService.GetTargetStates(network_load_balancer_id=<nlb-id>)`.

**Then** OK; `target_states[]` (3 элемента):
- T1 → `HEALTHY` (`status != DRAINING && LB.status=ACTIVE && age >= 2×2=4s`).
- T2 → `INITIAL`.
- T3 → `DRAINING`.

### GWT-NLB-041 — GetTargetStates: LB STOPPED → all INACTIVE

**Given** LB в `STOPPED`; attached TG с 2 healthy targets.

**When** GetTargetStates.

**Then** OK; both targets → `INACTIVE`.

### GWT-NLB-042 — GetTargetStates: empty (no attached TG)

**Given** LB без attached TG.

**When** GetTargetStates.

**Then** OK; `target_states = []`.

### GWT-NLB-043 — Delete LB (happy path, bottom-up cascade prerequisite)

**Given** LB `<nlb-id>` без listeners + без attached TG (или после Detach всех + Delete всех Listener); `deletion_protection=false`; subject editor.

**When** `Delete(network_load_balancer_id=<nlb-id>)`.

**Then** OK; Operation done; row deleted from `load_balancers`. Outbox `DELETED`. FGA tuples cleaned via D-13 (kacho-iam consumes `DELETED` event → `openfga.DeleteByObject(nlb_load_balancer:<nlb-id>)`).

### GWT-NLB-044 — Delete LB: deletion_protection=true → FAILED_PRECONDITION

**Given** LB `deletion_protection=true`.

**When** Delete.

**Then** `FAILED_PRECONDITION`; verbatim `"deletion_protection is enabled; disable via Update before deleting"`. LB не удалена.

### GWT-NLB-045 — Delete LB: has listener → FAILED_PRECONDITION (sync precheck)

**Given** LB has ≥1 listener.

**When** Delete.

**Then** `FAILED_PRECONDITION`; verbatim `"NetworkLoadBalancer has N listener(s); delete them first"`. (Sync precheck в UseCase даёт UX-friendly text; final FK 23503 в worker fallback на TOCTOU.)

### GWT-NLB-046 — Delete LB: has attached TG → FAILED_PRECONDITION

**Given** LB has ≥1 attached TG; no listeners.

**When** Delete.

**Then** `FAILED_PRECONDITION`; `"NetworkLoadBalancer has N attached target group(s); detach them first"`.

### GWT-NLB-047 — Delete LB: concurrent attach during Delete → final FK_VIOLATION → FAILED_PRECONDITION (TOCTOU fallback)

**Given** Sync precheck passes (no attached TG); between precheck and DELETE, another client calls `AttachTargetGroup`.

**When** Worker executes `DELETE FROM load_balancers WHERE id=<nlb-id>`.

**Then** SQL returns `23503` (FK violation from `attached_target_groups.load_balancer_id`); `mapRepoErr` → `FAILED_PRECONDITION`; verbatim text wraps SQL detail without leaking pgx (`"NetworkLoadBalancer has dependent resource; cannot delete"`). LB **не** удалена (TX rollback). Integration test reproduces race with two goroutines.

### GWT-NLB-048 — ListOperations for LB

**Given** LB `<nlb-id>` has history: Create + Update + Start; subject viewer.

**When** `NetworkLoadBalancerService.ListOperations(network_load_balancer_id=<nlb-id>, page_size=10)`.

**Then** OK; 3 operations returned, ordered by `created_at DESC`. Each row has full `Operation` envelope.

---

## 4. Listener scenarios (LST-*)

### GWT-LST-001 — Create Listener EXTERNAL (auto VIP allocation)

**Given**
- LB `<nlb-id>` EXTERNAL, region `ru-central1`, project `<prj-id>`; subject `editor` on LB.
- AddressPool `pool-default-v4` в `ru-central1` имеет free IPs.

**When** `ListenerService.Create`:
```
load_balancer_id = <nlb-id>
name             = "http"
protocol         = TCP
port             = 80
target_port      = 8080
ip_version       = IPV4
proxy_protocol_v2 = false
# address_id omitted (auto-alloc)
# subnet_id omitted (EXTERNAL)
```

**Then** OK; Operation done. Worker outcomes:
- Sync call `vpc.InternalAddressService.AllocateExternalIP(owner="nlb_listener:<lst-id>", region_id="ru-central1", ip_version=IPV4)` returns allocated IP (e.g. `203.0.113.42`).
- INSERT listener row with `allocated_address='203.0.113.42'`, `address_id=<address-id>` (the kacho-vpc Address id returned by alloc), `status='ACTIVE'`.
- Outbox: `nlb_listener:<lst-id> CREATED` + `nlb_load_balancer:<nlb-id> UPDATED`.
- FGA tuple D-11 sync write before commit: `nlb_listener:<lst-id>#owner@<subject>` + via D-13 `nlb_listener:<lst-id>#load_balancer@nlb_load_balancer:<nlb-id>`.

### GWT-LST-002 — Create Listener BYO address (sync CAS SetReference)

**Given**
- LB EXTERNAL; subject editor.
- `vpc.Address` `<addr-id>` exists, `used_by=""`, `ip_version=IPV4`, same `project_id` as LB.

**When** Create с `address_id=<addr-id>`, остальные поля как в LST-001.

**Then** OK; worker calls:
1. `vpc.AddressService.Get(<addr-id>)` — confirms exists + same project + `ip_version=IPV4`.
2. `vpc.InternalAddressService.SetReference(<addr-id>, used_by="nlb_listener:<lst-id>")` — atomic CAS `WHERE used_by='' OR used_by=<self>`; succeeds.
3. INSERT listener with `allocated_address=<addr.allocated_ipv4>`, `address_id=<addr-id>`.

Outbox + FGA as LST-001.

### GWT-LST-003 — Create Listener BYO: address already used → FAILED_PRECONDITION

**Given** Address `<addr-id>` `used_by="nlb_listener:lst000...other"` (другая listener).

**When** Create с `address_id=<addr-id>`.

**Then** `FAILED_PRECONDITION`; verbatim `"address <addr-id> is already in use by nlb_listener:lst000...other"`. Listener не создана.

### GWT-LST-004 — Create Listener BYO: ip_version mismatch → INVALID_ARGUMENT

**Given** Address `<addr-id>` `ip_version=IPV6`; Create с `ip_version=IPV4`.

**When** Create.

**Then** `INVALID_ARGUMENT`; `"address ip_version IPV6 does not match listener ip_version IPV4"`.

### GWT-LST-005 — Create Listener BYO: cross-project → INVALID_ARGUMENT

**Given** Address `<addr-id>` в `project=<prj-other>`; LB в `project=<prj-id>`.

**When** Create.

**Then** `INVALID_ARGUMENT`; `"address project_id does not match listener load_balancer project_id"`.

### GWT-LST-006 — Create Listener INTERNAL: requires subnet_id

**Given** LB type=INTERNAL.

**When** Create без `subnet_id`.

**Then** `INVALID_ARGUMENT`; `"subnet_id is required for INTERNAL load balancer"`.

### GWT-LST-007 — Create Listener INTERNAL: subnet_id valid + auto-alloc internal IP

**Given** LB INTERNAL; subnet `<subnet-id>` в `vpc.Network` того же project + region; subject editor.

**When** Create с `subnet_id=<subnet-id>`, без `address_id`.

**Then** OK; worker calls `vpc.InternalAddressService.AllocateInternalIP(owner="nlb_listener:<lst-id>", subnet_id=<subnet-id>, ip_version=IPV4)` → allocated internal IP. INSERT listener with `allocated_address=<int-ip>`, `subnet_id=<subnet-id>`.

### GWT-LST-008 — Create Listener: port out of range → INVALID_ARGUMENT (BVA)

**When** Create с (a) `port=0`, (b) `port=65536`, (c) `port=-1`.

**Then** все три → `INVALID_ARGUMENT`; `"port must be in range [1, 65535]"`. (LST-001 covers port=80; boundary tests port=1 + port=65535 → OK.)

### GWT-LST-009 — Create Listener: unsupported protocol → INVALID_ARGUMENT

**When** Create с `protocol="HTTP"` (only TCP/UDP supported for L4).

**Then** `INVALID_ARGUMENT`; `"protocol must be one of: TCP, UDP"`.

### GWT-LST-010 — Create Listener: duplicate (lb_id, port, protocol) → ALREADY_EXISTS

**Given** Listener `(<nlb-id>, port=80, protocol=TCP)` уже существует.

**When** Create second listener с теми же `(load_balancer_id, port, protocol)`.

**Then** `ALREADY_EXISTS`; verbatim `"listener with port 80 and protocol TCP already exists on this load balancer"`. SQL UNIQUE `(load_balancer_id, port, protocol)` enforces.

### GWT-LST-011 — Create Listener: duplicate (region, vip, port, protocol) across LBs → ALREADY_EXISTS

**Given** Listener `lst-A` на LB-A с `allocated_address=203.0.113.42, port=80, protocol=TCP`. BYO same `address_id`.

**When** Create на LB-B с тем же `address_id`.

**Then** First, `SetReference` CAS fails (LST-003 path) — `FAILED_PRECONDITION`. Cross-check: even if hypothetically reached INSERT, partial UNIQUE `(region_id, allocated_address, port, protocol) WHERE status!='DELETING'` enforces.

### GWT-LST-012 — Create Listener: trigger lb_status_recompute (INACTIVE → ACTIVE if has attached TG)

**Given** LB `INACTIVE` (no listeners, has 1 attached TG).

**When** Create first listener.

**Then** OK; trigger fires `AFTER INSERT listeners`; LB.status `INACTIVE → ACTIVE`. Outbox: 2 events (`listener CREATED`, `lb UPDATED`).

### GWT-LST-013 — Create Listener: trigger no-op for LB in CREATING/STARTING/STOPPING/STOPPED/DELETING

**Given** LB `STOPPED`.

**When** Create listener.

**Then** OK; LB.status remains `STOPPED` (trigger preserves explicit transitions). Outbox events emitted.

### GWT-LST-014 — Create Listener: VIP alloc fails → operation error + compensation

**Given** AddressPool exhausted; subject editor.

**When** Create EXTERNAL Listener (auto-alloc).

**Then** Operation worker: `vpc.InternalAddressService.AllocateExternalIP` returns `RESOURCE_EXHAUSTED`. Worker `ops.MarkDone(error)`. No listener row in БД. **No** outbox events. Subject sees `done=true` with `error.code=RESOURCE_EXHAUSTED`.

### GWT-LST-015 — Create Listener: INSERT fails after VIP allocated → defer FreeIP compensation

**Given** VIP allocated (sync) successfully; subsequent INSERT fails (e.g. CHECK constraint on health_check schema validation if added to default_target_group_id refs).

**When** Worker runs.

**Then** Defer `vpc.InternalAddressService.FreeIP(<addr-id>)` best-effort runs before MarkDone(error). VIP returned to pool. (Integration test: inject INSERT failure via psql `ALTER TABLE listeners ADD CONSTRAINT fail_test CHECK (false);` then drop after.)

### GWT-LST-016 — Get Listener

**Given** Listener `<lst-id>`; subject viewer.

**When** `Get(listener_id=<lst-id>)`.

**Then** OK; full Listener message.

### GWT-LST-017 — List Listeners (filter by load_balancer_id)

**Given** LB `<nlb-id>` has 3 listeners; another LB `<nlb-2>` has 2.

**When** `List(load_balancer_id=<nlb-id>)`.

**Then** OK; 3 listeners returned; не включены `<nlb-2>` listeners.

### GWT-LST-018 — Update Listener: mutable fields (name, description, labels, default_target_group_id, proxy_protocol_v2)

**Given** Listener `<lst-id>`.

**When** Update с `update_mask=["name","proxy_protocol_v2"]`, `name="https"`, `proxy_protocol_v2=true`.

**Then** OK; fields updated; `status='UPDATING'` transient → back to `ACTIVE` after worker MarkDone. Outbox `UPDATED`.

### GWT-LST-019 — Update Listener: immutable load_balancer_id → INVALID_ARGUMENT

**When** Update с `update_mask=["load_balancer_id"]`.

**Then** `INVALID_ARGUMENT`; `"load_balancer_id is immutable after Listener.Create"`.

### GWT-LST-020 — Update Listener: immutable protocol/port/ip_version/address_id → INVALID_ARGUMENT

**Same as LST-019** для каждого immutable field. Each tested individually (4 sub-cases).

### GWT-LST-021 — Update Listener: default_target_group_id = TG в другом region → FAILED_PRECONDITION

**Given** Listener в `ru-central1`; TG `<tg-id>` в `ru-central2`.

**When** Update с `default_target_group_id=<tg-id>`.

**Then** `FAILED_PRECONDITION`; `"default target group region <ru-central2> does not match listener region <ru-central1>"`.

### GWT-LST-022 — Delete Listener (auto VIP-alloc): free VIP back to pool

**Given** Listener `<lst-id>` created via auto-alloc (LST-001); `allocated_address=203.0.113.42`, `address_id=<addr-id>`.

**When** `Delete(listener_id=<lst-id>)`.

**Then** OK; worker: (1) UPDATE listener status='DELETING' (outbox UPDATED); (2) call `vpc.InternalAddressService.FreeIP(<addr-id>)` — returns IP к pool; (3) DELETE listener row; outbox `DELETED` + `nlb_load_balancer:<nlb-id> UPDATED`. trigger `listeners_lb_status_recompute` may transition LB `ACTIVE → INACTIVE`.

### GWT-LST-023 — Delete Listener (BYO address): clear used_by, do NOT free

**Given** Listener created via BYO (`address_id=<addr-id>` from external Address).

**When** Delete.

**Then** OK; worker calls `vpc.InternalAddressService.SetReference(<addr-id>, used_by="")` — clears reference; Address itself remains in `vpc` (BYO лежит к tenant'у — not nlb's to free). Listener row DELETE'd.

### GWT-LST-024 — Delete Listener: vpc.FreeIP fails → outbox FAILED + retry job

**Given** Auto-alloc listener; `vpc` unavailable when Delete worker runs.

**When** Delete.

**Then** Worker emits `nlb_listener:<lst-id> FAILED` outbox event; ops.MarkDone(error UNAVAILABLE); listener row remains in БД with `status='DELETING'`. Background job `free_ip_runner` (period 30s) retries `FreeIP` + DELETE row when vpc recovers. Eventually consistent — listener removed.

### GWT-LST-025 — Delete Listener: trigger recompute may move LB INACTIVE

**Given** LB `ACTIVE` with 1 listener + 1 attached TG.

**When** Delete listener.

**Then** LB.status transitions to `INACTIVE` (lost last listener). Outbox `nlb_load_balancer UPDATED`.

### GWT-LST-026 — ListOperations for Listener

**Given** Listener has 3 ops history; subject viewer.

**When** `ListenerService.ListOperations(listener_id=<lst-id>)`.

**Then** OK; 3 ops returned.

---

## 5. TargetGroup scenarios (TGR-*)

### GWT-TGR-001 — Create TG (inline targets + health_check)

**Given** Project `<prj-id>`, Region `ru-central1`; subject editor on project.

**When** `TargetGroupService.Create`:
```
project_id = <prj-id>
region_id  = "ru-central1"
name       = "backend-web"
labels     = {tier: "web"}
deregistration_delay_seconds = 300
slow_start_seconds = 30
health_check = {
  name: "http-200", interval: "2s", timeout: "1s",
  unhealthy_threshold: 3, healthy_threshold: 2,
  http: { port: 8080, path: "/healthz", expected_statuses: [200] }
}
targets = [
  { instance_id: "epd-i1", weight: 100 },
  { external_ip: { address: "203.0.113.50" }, weight: 50 }
]
```

**Then** OK; Operation done; TG with `id=<tg-id>` created. Targets table has 2 rows. health_check JSONB persisted. Outbox: `nlb_target_group:<tg-id> CREATED`. FGA tuple D-11 sync `nlb_target_group:<tg-id>#owner@<subject>` + via D-13 `#project@project:<prj-id>`.

### GWT-TGR-002 — Create TG: empty targets allowed

**When** Create с `targets=[]`.

**Then** OK; TG created without targets. Allowed (targets can be added later via AddTargets).

### GWT-TGR-003 — Create TG: invalid health_check (multiple of TCP/HTTP/HTTPS/GRPC set) → INVALID_ARGUMENT

**Given** subject editor.

**When** Create with `health_check.tcp = {port: 8080}` AND `health_check.http = {port: 8080, path:"/"}`.

**Then** `INVALID_ARGUMENT`; `"health_check must specify exactly one of: tcp, http, https, grpc"`.

### GWT-TGR-004 — Create TG: invalid health_check (none set) → INVALID_ARGUMENT

**When** Create без всех 4 health_check probe types.

**Then** `INVALID_ARGUMENT`; same text as TGR-003.

### GWT-TGR-005 — Create TG: health_check.interval out of bounds → INVALID_ARGUMENT (BVA)

**When** Create с `interval="0s"` или `interval="601s"`.

**Then** `INVALID_ARGUMENT`; `"health_check.interval must be in range [1s, 600s]"`.

### GWT-TGR-006 — Create TG: unhealthy_threshold/healthy_threshold out of bounds → INVALID_ARGUMENT

**When** Create с `unhealthy_threshold=1` (min=2) or `=11` (max=10).

**Then** `INVALID_ARGUMENT`; verbatim `"unhealthy_threshold must be in range [2, 10]"`.

### GWT-TGR-007 — Create TG: deregistration_delay_seconds out of bounds → INVALID_ARGUMENT

**When** Create с `deregistration_delay_seconds=-1` или `=3601`.

**Then** `INVALID_ARGUMENT`; `"deregistration_delay_seconds must be in range [0, 3600]"`.

### GWT-TGR-008 — Create TG: slow_start_seconds out of bounds → INVALID_ARGUMENT

**When** Create с `slow_start_seconds=-1` или `=901`.

**Then** `INVALID_ARGUMENT`; `"slow_start_seconds must be in range [0, 900]"`.

### GWT-TGR-009 — Create TG: invalid target (4-way oneof не указан) → INVALID_ARGUMENT

**When** Create с `targets[0]={weight:100}` (нет identity).

**Then** `INVALID_ARGUMENT`; `"target[0] must specify exactly one of: instance_id, nic_id, ip_ref, external_ip"`.

### GWT-TGR-010 — Create TG: invalid target (multiple of 4-way oneof) → INVALID_ARGUMENT

**When** Create с `targets[0]={instance_id:"epd-x", external_ip:{address:"8.8.8.8"}}`.

**Then** `INVALID_ARGUMENT`; same text as TGR-009.

### GWT-TGR-011 — Create TG: target external_ip is bogon → INVALID_ARGUMENT

**When** Create с `targets[0]={external_ip:{address:"127.0.0.1"}}` (loopback).

**Then** `INVALID_ARGUMENT`; verbatim `"external_ip 127.0.0.1 is a bogon (loopback) and is not allowed as a target"`. Also tested: `0.0.0.0` (unspecified), `169.254.x.x` (link-local), `224.0.0.0/4` (multicast), `255.255.255.255` (broadcast).

### GWT-TGR-012 — Create TG: target instance_id unknown (deferred peer-validate in worker)

**Given** subject editor; `instance_id="epd-doesnt-exist"`.

**When** Create.

**Then** Operation worker calls `compute.InstanceService.Get` → `NotFound`. Worker `ops.MarkDone(error InvalidArgument)`; verbatim `"target[0].instance_id 'epd-doesnt-exist' not found"`. TG **не** создана (worker rolls back TX). Or alternative: TG created without that target + per-target error in metadata — design §4.3 chose "per-target peer fail → ops.error InvalidArgument с per-target reason". Acceptance: TX rollback; nothing committed.

### GWT-TGR-013 — Create TG: same-region constraint vs LB on future Attach

**Given** TG created in `ru-central1` (validated against `compute.RegionService.Get`).

**When** Later `AttachTargetGroup` to LB in `ru-central2` — covered NLB-032.

**Then** Same-region enforced at attach-time; TG.Create itself only validates region against `kacho-compute`.

### GWT-TGR-014 — Create TG: duplicate (project_id, name) → ALREADY_EXISTS

**Given** TG `name="backend-web"` exists in project.

**When** Create another TG same name same project.

**Then** `ALREADY_EXISTS`; verbatim `"TargetGroup 'backend-web' already exists in project <prj-id>"`. Partial UNIQUE `(project_id, name) WHERE name <> ''`.

### GWT-TGR-015 — Get TG

**Given** TG `<tg-id>` with 3 targets; subject viewer.

**When** `Get(target_group_id=<tg-id>)`.

**Then** OK; full TG message including embedded `targets[]` (3) and `health_check{}`.

### GWT-TGR-016 — List TG (filter by project, region)

**Given** project `<prj-id>` has 5 TG (3 в `ru-central1`, 2 в `ru-central2`).

**When** `List(project_id=<prj-id>, filter='region_id="ru-central1"')`.

**Then** OK; 3 TG returned. Pagination tested separately (TGR-017).

### GWT-TGR-017 — List TG: pagination

**Given** Following TGR-016.

**When** Repeat List с small `page_size=2`.

**Then** OK; 2 TG returned; non-empty `next_page_token`; Get next page → 1 remaining TG.

### GWT-TGR-018 — Update TG: mutable (name/description/labels/health_check/dereg/slow_start)

**Given** TG `<tg-id>`.

**When** Update с `update_mask=["health_check","deregistration_delay_seconds"]`, `health_check.interval="5s"`, `deregistration_delay_seconds=600`.

**Then** OK; fields updated. Outbox `UPDATED`. Active drains (Phase B) continue with **old** delay until completion (cron picks up new dereg_delay value at next tick for newly-added DRAINING targets).

### GWT-TGR-019 — Update TG: immutable project_id/region_id → INVALID_ARGUMENT

**When** Update с `update_mask=["region_id"]`.

**Then** `INVALID_ARGUMENT`; `"region_id is immutable after TargetGroup.Create"`. Same for `project_id`.

### GWT-TGR-020 — Update TG: targets via update_mask=["targets"] → INVALID_ARGUMENT

**When** Update с `update_mask=["targets"]`, `targets=[...]`.

**Then** `INVALID_ARGUMENT`; `"targets must be modified via AddTargets / RemoveTargets"`.

### GWT-TGR-021 — Delete TG (sync precheck: no attached LB, no targets)

**Given** TG with no attachments + no targets; subject editor.

**When** Delete.

**Then** OK; row deleted from `target_groups`. Outbox `DELETED`. FGA cleanup via D-13.

### GWT-TGR-022 — Delete TG: has attached LB → FAILED_PRECONDITION

**Given** TG attached to ≥1 LB.

**When** Delete.

**Then** `FAILED_PRECONDITION`; verbatim `"TargetGroup is attached to N load balancer(s); detach first"`.

### GWT-TGR-023 — Delete TG: has targets → FAILED_PRECONDITION

**Given** TG with no attached LB but ≥1 target row.

**When** Delete.

**Then** `FAILED_PRECONDITION`; verbatim `"TargetGroup has N target(s); remove them first via RemoveTargets"`.

### GWT-TGR-024 — Delete TG: concurrent AddTargets during Delete → final FK 23503 → FAILED_PRECONDITION

**Given** Sync precheck shows no targets. Between precheck and DELETE, another client calls `AddTargets`.

**When** Worker `DELETE FROM target_groups WHERE id=<tg-id>`.

**Then** SQL 23503 (FK from `targets.target_group_id`); `mapRepoErr` → `FAILED_PRECONDITION`. TG не удалена.

### GWT-TGR-025 — Move TG cross-project (no attached LB)

**Given** TG `<tg-id>` in `<prj-src>`; subject editor on both src+dst; no attached LB.

**When** `Move(target_group_id=<tg-id>, destination_project_id=<prj-dst>)`.

**Then** OK; worker `UPDATE target_groups SET project_id=<prj-dst>`. Outbox `MOVED`. FGA tuples rewritten.

### GWT-TGR-026 — Move TG: has attached LB → FAILED_PRECONDITION

**Given** TG attached to LB.

**When** Move.

**Then** `FAILED_PRECONDITION`; `"TargetGroup is attached to N load balancer(s); detach before moving"`.

### GWT-TGR-027 — Move TG: subject lacks editor on dst project → PERMISSION_DENIED

(Same as NLB-028.)

### GWT-TGR-028 — ListOperations for TG

**Given** TG history: Create + AddTargets + RemoveTargets + Update; subject viewer.

**When** `TargetGroupService.ListOperations(target_group_id=<tg-id>)`.

**Then** OK; 4 ops returned ordered by `created_at DESC`.

---

## 6. Target operations scenarios (TGT-*)

### GWT-TGT-001 — AddTargets (4-way oneof, all variants)

**Given** TG `<tg-id>` empty; subject editor on TG; Instance `epd-i1` exists; NIC `enp-nic1` exists; Subnet `e9b-sub1` exists with CIDR `10.0.0.0/24`.

**When** `TargetGroupService.AddTargets`:
```
target_group_id = <tg-id>
targets = [
  { instance_id: "epd-i1", weight: 100 },        # variant 1
  { nic_id: "enp-nic1", weight: 100 },           # variant 2
  { ip_ref: { subnet_id: "e9b-sub1", address: "10.0.0.5" }, weight: 50 },  # variant 3
  { external_ip: { address: "203.0.113.99" }, weight: 100 }                # variant 4
]
```

**Then** OK; Operation done. 4 target rows in `targets` table. Worker peer-validates each:
- `compute.InstanceService.Get("epd-i1")` → resolves primary NIC IP, stored as denorm `resolved_ipv4` (or similar; design §4.3 says "resolve" — stored для GetTargetStates).
- `vpc.NetworkInterfaceService.Get("enp-nic1")` → resolves primary IP.
- `vpc.SubnetService.Get("e9b-sub1")` + verify `10.0.0.5 ∈ 10.0.0.0/24`.
- `external_ip 203.0.113.99` — sync bogon-check passes (public IPv4).

Outbox `nlb_target_group:<tg-id> UPDATED`.

### GWT-TGT-002 — AddTargets: idempotent on duplicate identity (ON CONFLICT DO NOTHING)

**Given** TG has target `{instance_id:"epd-i1", weight:100}`.

**When** AddTargets с тем же target.

**Then** OK; row count unchanged (partial UNIQUE NULLS NOT DISTINCT on `(target_group_id, instance_id) WHERE instance_id IS NOT NULL` catches). No new outbox event (worker detects 0 rows inserted → skip outbox.Emit).

### GWT-TGT-003 — AddTargets: idempotent on duplicate ip_ref

**Given** TG has target `{ip_ref:{subnet_id:"e9b-sub1", address:"10.0.0.5"}}`.

**When** AddTargets с тем же ip_ref.

**Then** OK; idempotent. partial UNIQUE `(target_group_id, ip_ref_subnet_id, ip_ref_address)`.

### GWT-TGT-004 — AddTargets: ip_ref outside subnet CIDR → INVALID_ARGUMENT (worker peer-validate)

**Given** Subnet `<sub-id>` CIDR `10.0.0.0/24`.

**When** AddTargets с `ip_ref={subnet_id:<sub-id>, address:"10.1.0.5"}`.

**Then** Operation `ops.MarkDone(error InvalidArgument)`; verbatim `"target[0].ip_ref.address 10.1.0.5 is not in subnet <sub-id> CIDR 10.0.0.0/24"`. Target не добавлен.

### GWT-TGT-005 — AddTargets: weight out of bounds → INVALID_ARGUMENT (BVA)

**When** AddTargets с `weight=-1` или `weight=1001`.

**Then** `INVALID_ARGUMENT`; `"weight must be in range [0, 1000]"`. Boundary `weight=0` and `weight=1000` — OK (weight=0 means "drain effectively without remove" по semantics).

### GWT-TGT-006 — AddTargets: instance in different region than TG → INVALID_ARGUMENT

**Given** TG region=`ru-central1`; Instance `epd-i2` zone=`ru-central2-a`.

**When** AddTargets с `instance_id="epd-i2"`.

**Then** Worker resolves Instance, finds region mismatch → `ops.MarkDone(error InvalidArgument)`; `"target[0].instance_id 'epd-i2' region 'ru-central2' does not match target_group region 'ru-central1'"`.

### GWT-TGT-007 — AddTargets: nic in different region — INVALID_ARGUMENT

**Same as TGT-006** для NIC.

### GWT-TGT-008 — AddTargets: ip_ref.subnet in different region → INVALID_ARGUMENT

**Same** для subnet.

### GWT-TGT-009 — AddTargets: empty list → INVALID_ARGUMENT

**When** AddTargets с `targets=[]`.

**Then** `INVALID_ARGUMENT`; `"at least one target is required"`.

### GWT-TGT-010 — AddTargets: TG in DELETING → FAILED_PRECONDITION

**Given** TG `status=DELETING` (mid-Delete worker).

**When** AddTargets.

**Then** `FAILED_PRECONDITION`; `"target group is being deleted"`.

### GWT-TGT-011 — RemoveTargets Phase A (immediate DRAINING-mark)

**Given** TG with 3 targets; subject editor.

**When** `RemoveTargets(target_group_id=<tg-id>, targets=[{instance_id:"epd-i1"}, {external_ip:{address:"203.0.113.99"}}])`.

**Then** OK; Operation done **fast** (latency <500ms per design §4.4). In БД:
- 2 matching rows have `status='DRAINING'`, `drain_started_at=<now>`.
- Third target unchanged.

Outbox `nlb_target_group:<tg-id> UPDATED`. GetTargetStates returns those 2 as `DRAINING`.

### GWT-TGT-012 — RemoveTargets: target identity not in TG → no-op (idempotent)

**Given** TG without target `{instance_id:"epd-x"}`.

**When** RemoveTargets с `targets=[{instance_id:"epd-x"}]`.

**Then** OK; 0 rows updated; **no** outbox event (worker skips emit when 0 affected). Operation done.

### GWT-TGT-013 — RemoveTargets Phase B (background drain after deregistration_delay)

**Given** TG `deregistration_delay_seconds=2` (short for test); target `{instance_id:"epd-i1"}` in `DRAINING`, `drain_started_at = now - 3s`.

**When** `target_drain_runner` job runs (period 10s; or invoked directly in integration test).

**Then** SQL `DELETE FROM targets WHERE status='DRAINING' AND drain_started_at < now() - tg.deregistration_delay_seconds * '1 second'::interval`. Row deleted. Outbox `nlb_target_group:<tg-id> UPDATED`.

### GWT-TGT-014 — RemoveTargets Phase B: target still in delay → no DELETE yet

**Given** Target `DRAINING`, `drain_started_at = now - 1s`, dereg_delay=300.

**When** Drain runner runs.

**Then** Row remains. Will be deleted после 300s.

### GWT-TGT-015 — AddTargets re-add of DRAINING target — promotes back to active

**Given** Target `{instance_id:"epd-i1"}` in `DRAINING`.

**When** AddTargets с тем же `{instance_id:"epd-i1"}`.

**Then** OK; SQL `INSERT ... ON CONFLICT (target_group_id, instance_id) WHERE instance_id IS NOT NULL DO UPDATE SET status='ACTIVE', drain_started_at=NULL`. Outbox `UPDATED`. Target re-promoted.

### GWT-TGT-016 — AddTargets + concurrent Delete TG → FAILED_PRECONDITION on Delete

**Given** Race: client A starts AddTargets; client B calls Delete TG.

**When** Both execute simultaneously.

**Then** One of two atomic outcomes:
- (a) AddTargets commits first → Delete sees targets count >0 → FAILED_PRECONDITION (TGR-023).
- (b) Delete commits first → AddTargets sees TG status='DELETING' → FAILED_PRECONDITION (TGT-010).
- Or Delete reaches DB level → 23503 FK fallback (TGR-024).

Integration test verifies one of these branches occurs deterministically (no torn state).

---

## 7. Operation scenarios (OP-*)

### GWT-OP-001 — Get Operation (in-flight)

**Given** Operation `<op-id>` exists in `nlb` ops; subject viewer on the parent resource.

**When** `OperationService.Get(operation_id=<op-id>)`.

**Then** OK; Operation message: `id, description, created_at, done=false, metadata{...}`.

### GWT-OP-002 — Get Operation (completed)

**Given** Operation done.

**When** Get.

**Then** OK; `done=true, response.value = <Resource proto>` (or `error.value = google.rpc.Status` if error).

### GWT-OP-003 — Get Operation: unknown id → NOT_FOUND

**When** Get unknown op-id.

**Then** `NOT_FOUND`.

### GWT-OP-004 — List Operations (across all resources in project)

**Given** project with 5 in-flight ops.

**When** `OperationService.List(project_id=<prj-id>, page_size=10)`.

**Then** OK; 5 ops returned.

### GWT-OP-005 — Cancel Operation (in-flight, supported)

**Given** Long-running op in-flight; subject = creator of op.

**When** `OperationService.Cancel(operation_id=<op-id>)`.

**Then** OK; worker observes cancel-flag, calls `ops.MarkDone(error CANCELLED)`. (For NLB MVP, Cancel may only be effective for ops that haven't started side-effects yet; for Create-LB worker that already allocated VIP, Cancel attempts compensation. Acceptance: returns OK; eventual op state `done=true, error=CANCELLED`.)

### GWT-OP-006 — Cancel Operation: already done → FAILED_PRECONDITION

**When** Cancel an op already `done=true`.

**Then** `FAILED_PRECONDITION`; `"operation is already completed"`.

---

## 8. Authorization scenarios (AZD-*)

### GWT-AZD-001 — NLB.Create: subject without editor on project → PERMISSION_DENIED

**Given** subject `user:bob` has only `viewer` on `project:<prj-id>`.

**When** `NetworkLoadBalancerService.Create` in that project.

**Then** `PERMISSION_DENIED`; verbatim from FGA interceptor `"permission denied: loadbalancer.networkLoadBalancers.create on project:<prj-id>"`. No DB row, no outbox event. (Fail-closed before reaching repo.)

### GWT-AZD-002 — NLB.Get: viewer OK

**Given** subject `viewer` on project.

**When** Get LB in project.

**Then** OK.

### GWT-AZD-003 — NLB.Get: stranger subject → PERMISSION_DENIED

**Given** subject without any tuple to project.

**When** Get LB.

**Then** `PERMISSION_DENIED`.

### GWT-AZD-004 — NLB.Start/Stop: editor required, viewer rejected

**Given** subject viewer on LB.

**When** `Start` or `Stop`.

**Then** `PERMISSION_DENIED`; permission `loadbalancer.networkLoadBalancers.start` (or `stop`).

### GWT-AZD-005 — NLB.Delete: owner required (или editor depending policy)

**Given** subject editor (not owner).

**When** Delete.

**Then** Per design §6.3 — `loadbalancer.networkLoadBalancers.delete` is in `roles/loadbalancer.editor`; relation `editor`. So editor is OK. AZD verifies viewer rejected and editor OK.

### GWT-AZD-006 — NLB.Move scope-conditional (src + dst)

(See NLB-028.) Newman case: subject editor on src, viewer on dst → PERMISSION_DENIED with verbatim `"permission denied: loadbalancer.networkLoadBalancers.move on project:<prj-dst>"`.

### GWT-AZD-007 — NLB.AttachTargetGroup: editor on LB + viewer on TG required

**Given** subject editor on LB but no tuple on TG.

**When** Attach.

**Then** `PERMISSION_DENIED`; permission `loadbalancer.networkLoadBalancers.attachTargetGroup` requires also `loadbalancer.targetGroups.get` on TG (via viewer relation).

### GWT-AZD-008 — TG.AddTargets: editor on TG required

**Given** subject viewer on TG.

**When** AddTargets.

**Then** `PERMISSION_DENIED`.

### GWT-AZD-009 — Listener.Create: editor on parent LB required

**Given** subject viewer on LB.

**When** Create Listener.

**Then** `PERMISSION_DENIED`; permission `loadbalancer.listeners.create` requires `editor` on parent LB (cascades through nlb_listener.load_balancer relation).

### GWT-AZD-010 — Operation.Get: viewer on parent resource required

**Given** Operation belongs to LB `<nlb-id>`; subject viewer on that LB.

**When** Get Operation.

**Then** OK.

### GWT-AZD-011 — Operation.Cancel: only operation creator can cancel

**Given** Operation created by user:alice; subject user:bob is editor on parent LB.

**When** Bob calls Cancel.

**Then** `PERMISSION_DENIED`; `"only the operation creator may cancel"`. (Owner-scope; outside FGA relation tree.)

### GWT-AZD-012 — FGA unavailable → fail-closed PERMISSION_DENIED

**Given** `kacho-iam:9091` unreachable; subject editor (verified).

**When** Any RPC.

**Then** `PERMISSION_DENIED`; cache returns no entry (positive cache only); upstream Check fails → fail-closed. Verbatim `"authorization service unavailable"` (RFC-style; verifies operators get clear signal).

### GWT-AZD-013 — Breakglass env var bypasses Check (dev only)

**Given** `KACHO_NLB_AUTHZ__BREAKGLASS=true`; subject without any tuple.

**When** NLB.Create.

**Then** OK; service logs WARN `breakglass-enabled bypass: subject=<id>, rpc=<method>`. (Production config-validation rejects this flag — covered separately.)

### GWT-AZD-014 — RPC not in PermissionMap → fail-closed (drift test catches)

**Given** Hypothetical RPC `loadbalancer.v1.NetworkLoadBalancerService.NewlyAddedMethod` not in `permission_map.go`.

**When** Subject calls it (even owner).

**Then** `PERMISSION_DENIED`. **Build-time drift-test** (`permission_map_drift_test.go`) fails CI before merge: ensures every public RPC has either Permission entry OR explicit `Public: true`. (Drift-test is in unit-test category — verified separately, not via runtime newman case.)

### GWT-AZD-015 — D-11 creator-tuple sync write fails → operation aborts (fail-closed)

**Given** OpenFGA WriteCreatorTuple returns error during Create worker.

**When** worker tries to commit.

**Then** Worker aborts TX before commit. `ops.MarkDone(error UNAVAILABLE)`. Resource NOT created. Outbox NOT emitted. Subject sees `done=true` with error.

### GWT-AZD-016 — Cache invalidation ≤10s (NFR from KAC-108)

**Given** subject editor on project; performs Get LB → cached. Then admin revokes binding via `iam.AccessBindingService.Delete`.

**When** Within ≤10s, subject retries Get LB.

**Then** `PERMISSION_DENIED`. Cache invalidated via `pg_notify('kacho_iam_subjects', '<subject-id>')`. Newman: poll Get LB at 1-second intervals; assert PERMISSION_DENIED ≤10s after revoke ack.

### GWT-AZD-017 — Custom role granting only `loadbalancer.networkLoadBalancers.start` — resolves to editor

**Given** `iam.Role` `custom-lb-restarter` с `permissions=["loadbalancer.networkLoadBalancers.start","loadbalancer.networkLoadBalancers.stop"]`. AccessBinding writes tuple `nlb_load_balancer:<id>#editor@user:bob` (narrowest covering, design §6.4).

**When** Bob calls Start on that LB.

**Then** OK. Bob can also Update LB (since editor covers it) — semantically narrower fine-grained partition would prevent this, but NLB MVP uses 3-relation expansion (design accepts this trade-off; fine-grained = follow-up).

### GWT-AZD-018 — Custom role with unknown permission → INVALID_ARGUMENT (at iam.Role.Create)

**Given** Subject creates `iam.Role` with `permissions=["loadbalancer.foo.bar"]`.

**When** iam.RoleService.Create.

**Then** `INVALID_ARGUMENT`; verbatim from iam `"unknown permission: loadbalancer.foo.bar"`. (Validation against `permission_catalog.go` which includes all 30 loadbalancer.* strings.)

### GWT-AZD-019 — Permission catalog completeness — 30 permissions registered

**Given** Static drift test or runtime introspection.

**When** Query `iam.PermissionCatalogService.List(prefix="loadbalancer.")` (or equivalent).

**Then** Returns exactly 30 entries matching design §6.2. Mapped 1:1 to RPC methods via `permission_map.go`.

### GWT-AZD-020 — Predefined system role seeds (5 seed roles)

**Given** Fresh deploy of `kacho-iam` with NLB enabled.

**When** Query iam roles by prefix.

**Then** 5 system roles exist: `roles/loadbalancer.admin`, `roles/loadbalancer.editor`, `roles/loadbalancer.viewer`, `roles/loadbalancer.operator` (new seed), `roles/loadbalancer.targetManager` (new seed). Each with permissions per design §6.3.

### GWT-AZD-021 — Owner relation: creator has owner on created LB

**Given** alice creates LB.

**When** Alice queries Check `owner` on `nlb_load_balancer:<lb-id>`.

**Then** Allowed=true (D-11 sync wrote `nlb_load_balancer:<lb-id>#owner@user:alice`).

### GWT-AZD-022 — Lifecycle DELETED tuple cleanup

**Given** LB deleted; D-13 emits `DELETED` event.

**When** kacho-iam D-13 subscriber consumes.

**Then** Within ≤10s, `openfga.DeleteByObject(nlb_load_balancer:<lb-id>)` removes all tuples referencing this object. Check `viewer` for any subject on this object → `DecisionNoPath` → fail-closed.

### GWT-AZD-023 — Authz cache hit ratio ≥95% steady-state (NFR)

**Given** k6 baseline scenario, steady 500 RPS over 5 minutes.

**When** Measure cache hit ratio (Prometheus metric `kacho_nlb_authz_check_cache_hits_total / total`).

**Then** ≥0.95 after warm-up (60s). Cache miss only on TTL=5s expiry, new subjects, or NOTIFY invalidate.

### GWT-AZD-024 — Authz check p95 latency ≤20ms (NFR)

**Given** k6 baseline.

**When** Measure `kacho_nlb_authz_check_duration_seconds` histogram.

**Then** p95 ≤ 0.020 (20ms).

### GWT-AZD-025 — InternalResourceLifecycleService.Subscribe restricted (kacho-iam only)

**Given** External client connects to internal port :9091 with non-mTLS identity.

**When** Subscribe.

**Then** `PERMISSION_DENIED` (mTLS SPIRE check fails — depending on phase-3.10 deployment). For NLB MVP without mTLS: at minimum the port is k8s-NetworkPolicy-isolated; cluster-internal traffic only.

### GWT-AZD-026 — Operations: cross-resource ops listing requires owner on parent

**Given** Op related to LB `<nlb-1>`; subject viewer on `<nlb-1>` but not on `<nlb-2>`.

**When** `OperationService.List(project_id=<prj>)`.

**Then** Returns only ops for resources subject can view. Per-op extractor resolves parent resource and Checks. (Design: 1 Check per List call returns scope, then per-row filter — acceptable here since op-list is admin-bounded.)

### GWT-AZD-027 — Anonymous request → UNAUTHENTICATED (not PERMISSION_DENIED)

**Given** No Authorization header.

**When** Any RPC.

**Then** `UNAUTHENTICATED` (auth-interceptor rejects before authz-interceptor).

### GWT-AZD-028 — Service account subject

**Given** Service account `sa:nlb-deployer` has `editor` on project.

**When** SA calls NLB.Create.

**Then** OK. FGA tuple `project:<prj>#editor@service_account:<sa-id>` resolves.

### GWT-AZD-029 — Group membership cascade

**Given** Group `grp-platform-admins` has `editor@project:<prj>`. user:alice ∈ group.

**When** Alice calls NLB.Create.

**Then** OK. FGA resolves group#member transitively.

### GWT-AZD-030 — Concurrent revoke + Check race

**Given** Subject has tuple. Concurrently: (A) admin calls Delete AccessBinding; (B) subject calls Get LB.

**When** Within the window before cache invalidation propagates.

**Then** Either (a) (A) commits first → (B) cache hit returns OK once (within ≤10s thereafter rejected), or (b) (B) executes first → OK; (A) commits → next request ≤10s rejected. **Eventual consistency** within ≤10s is the contract; no torn state.

---

## 9. Cross-resource integration scenarios (XRES-*)

### GWT-XRES-001 — Full happy-path end-to-end

**Given** Fresh deploy; `<prj-id>`, `ru-central1`, free address pool, `epd-i1` instance.

**When** Subject executes sequence:
1. `NLB.Create(EXTERNAL, edge-public)` → LB created `INACTIVE`.
2. `Listener.Create(load_balancer_id=<lb>, port=80, protocol=TCP, ip_version=IPV4)` → auto-VIP allocated; LB transitions `INACTIVE` (still no attached TG).
3. `TG.Create(project, region, backend-web)` → TG `ACTIVE`.
4. `TG.AddTargets(<tg>, [{instance_id:"epd-i1"}])` → 1 target added.
5. `NLB.AttachTargetGroup(<lb>, <tg>, priority=100)` → trigger recompute → LB `INACTIVE → ACTIVE`.
6. `NLB.GetTargetStates(<lb>)` → returns 1 target. After ramp (4s) — `HEALTHY`.

**Then** All ops succeed; LB `ACTIVE`; outbox events emitted in order; FGA tuples present.

### GWT-XRES-002 — Bottom-up teardown

**Given** Following XRES-001 final state.

**When** Subject executes teardown:
1. `TG.RemoveTargets(<tg>, [{instance_id:"epd-i1"}])` → Phase A done; Phase B drain after dereg_delay.
2. After dereg_delay → target row deleted.
3. `NLB.DetachTargetGroup(<lb>, <tg>)` → OK; LB → `INACTIVE`.
4. `NLB.Delete(<lb>)` → blocked (listener) → `FAILED_PRECONDITION`.
5. `Listener.Delete(<lst>)` → OK; VIP freed.
6. `NLB.Delete(<lb>)` → OK.
7. `TG.Delete(<tg>)` → OK.

**Then** All steps succeed in order; final state — empty.

### GWT-XRES-003 — End-to-end через api-gateway REST

**Given** api-gateway registered `/nlb/v1/*` routes.

**When** newman POST `/nlb/v1/networkLoadBalancers` with body.

**Then** HTTP 200 OK; response is `Operation`. Poll `/nlb/v1/operations/{id}` until `done=true`.

### GWT-XRES-004 — D-13 stream subscription end-to-end

**Given** kacho-iam connected to `nlb.InternalResourceLifecycleService.Subscribe` long-running stream.

**When** NLB.Create executes.

**Then** Within ≤5s, kacho-iam observer logs `received LifecycleEvent{resource_type:NetworkLoadBalancer, resource_id:<nlb-id>, action:CREATED}`. FGA tuples written.

### GWT-XRES-005 — D-13 stream resume after kacho-iam restart

**Given** Subscriber catched up to sequence_no=42; kacho-iam restarts.

**When** On restart, Subscribe sends `last_event_id=42`.

**Then** Stream sends events 43+ in order. Cursor stored in `nlb_watch_cursors` per design §5.2. No event lost.

### GWT-XRES-006 — D-13 stream semaphore (max 32 concurrent streams)

**Given** `KACHO_NLB_LIFECYCLE_MAX_STREAMS=32`; 32 active streams.

**When** 33rd client connects.

**Then** `RESOURCE_EXHAUSTED`; `"max concurrent lifecycle streams reached (32); retry later"`.

### GWT-XRES-007 — Service restart resumes drain-runner

**Given** 5 targets DRAINING; drain_started_at=now-1s; dereg_delay=2s; service restart.

**When** Service comes back up; drain_runner ticks.

**Then** After ≤10s + 1s (next tick), targets deleted; outbox events emitted.

---

## 10. Storage / migrations scenarios (DB-*)

### GWT-DB-001 — Migration 0001 applies idempotently

**Given** Fresh `kacho_nlb` database.

**When** `kacho-migrator up` runs.

**Then** All tables created; `goose_db_version` row at v1. Re-run idempotent (no-op).

### GWT-DB-002 — `kacho_labels_valid` helper rejects >64 pairs

**Given** Insert LB with `labels` containing 65 entries.

**When** INSERT.

**Then** CHECK constraint violation 23514; `mapRepoErr` → `INVALID_ARGUMENT`; `"labels exceed maximum of 64 entries"`.

### GWT-DB-003 — `nlb_outbox_notify_trg` fires on insert

**Given** psql `LISTEN nlb_outbox` active.

**When** Worker INSERT into `nlb_outbox`.

**Then** Notification received with payload = `sequence_no` decimal string.

### GWT-DB-004 — `lb_status_recompute()` only transitions INACTIVE ↔ ACTIVE

**Given** LB in `STARTING`.

**When** AttachTargetGroup INSERT fires trigger.

**Then** LB remains `STARTING` (trigger preserves explicit transitions).

### GWT-DB-005 — Partial UNIQUE `(project_id, name) WHERE name <> ''` on load_balancers

**Given** Two LB inserts with same `(project_id, name)`.

**When** Second INSERT.

**Then** 23505 → `ALREADY_EXISTS`. (NLB-009)

### GWT-DB-006 — UNIQUE `(load_balancer_id, port, protocol)` on listeners

(See LST-010.)

### GWT-DB-007 — UNIQUE `(region_id, allocated_address, port, protocol) WHERE status!='DELETING'` on listeners

(See LST-011.)

### GWT-DB-008 — Partial UNIQUE NULLS NOT DISTINCT for 4-way target identity

**Given** Insert two targets `{instance_id:"epd-i1"}` into same TG.

**When** Second INSERT (via AddTargets).

**Then** 23505 from `targets_instance_id_uniq WHERE instance_id IS NOT NULL`. ON CONFLICT handles to NO-OP.

### GWT-DB-009 — CHECK target 4-way exactly-one

**Given** Insert target with both `instance_id` and `external_ip` set in DB-level (manual psql, bypassing service).

**When** INSERT.

**Then** CHECK constraint violation 23514: `"targets_identity_exactly_one"`. Defense-in-depth even if service-layer validation slips.

### GWT-DB-010 — FK RESTRICT on all 4 within-DB edges

**Given** Tables populated.

**When** Attempt cascade DELETE at DB level (e.g. `DELETE FROM load_balancers WHERE id=<lb> CASCADE` — not actually supported by SQL since FK is RESTRICT, only direct DELETE).

**Then** Direct DELETE fails 23503 if child exists. NLB-047, TGR-024 verify this from service-side.

### GWT-DB-011 — `attached_target_groups` PK composite `(load_balancer_id, target_group_id)`

**Given** AttachTargetGroup called twice with same pair.

**When** Second call.

**Then** ON CONFLICT DO NOTHING (NLB-033) or DO UPDATE for priority (NLB-034) — idempotent.

### GWT-DB-012 — `targets.drain_started_at` NULL when status='ACTIVE'; NOT NULL when status='DRAINING'

**Given** CHECK constraint `(status='DRAINING' AND drain_started_at IS NOT NULL) OR (status<>'DRAINING' AND drain_started_at IS NULL)`.

**When** Attempt invalid state via manual psql.

**Then** 23514.

### GWT-DB-013 — labels GIN index allows efficient filter

**Given** 10000 LB rows with random labels.

**When** `SELECT FROM load_balancers WHERE labels @> '{"env":"prod"}'::jsonb`.

**Then** EXPLAIN ANALYZE shows index scan; p95 ≤10ms.

### GWT-DB-014 — Migrator binary runs independently of API server

**Given** `kacho-migrator up --dsn=...` invoked from init-container.

**When** Run.

**Then** Migrations applied; API server starts after.

### GWT-DB-015 — Goose schema version stored in `kacho_nlb.goose_db_version`

**Given** Fresh deploy.

**When** Migrator runs.

**Then** Table `kacho_nlb.goose_db_version` has 1 row v1. (Not in `public.goose_db_version`.)

---

## 11. Reliability / failure-mode scenarios (FAIL-*)

### GWT-FAIL-001 — Service restart mid-Operation: in-progress op recovers

**Given** Operation `<op-id>` in-flight (Create LB worker writing VIP).

**When** Service restarts.

**Then** Operation row remains in `operations` table; worker pool on restart picks up undone ops via `WHERE done=false ORDER BY created_at LIMIT N`. Worker reads current state from DB, idempotently resumes. Op eventually `done=true`.

### GWT-FAIL-002 — Postgres connection lost mid-mutation → operation marked error UNAVAILABLE

**Given** Connection terminated by pg_terminate_backend mid-INSERT.

**When** Worker retries N=3 times with exponential backoff.

**Then** After retries exhausted, `ops.MarkDone(error UNAVAILABLE)`.

### GWT-FAIL-003 — Outbox NOTIFY channel full / subscriber disconnect

**Given** D-13 subscriber crashes.

**When** Subscriber reconnects with `last_event_id`.

**Then** Worker catch-up: SELECT `nlb_outbox WHERE sequence_no > last_event_id ORDER BY sequence_no LIMIT 100`. Replay batch; transition to NOTIFY-loop.

### GWT-FAIL-004 — vpc transient unavailability during Listener.Create

**Given** Worker mid-VIP-alloc; `vpc` returns `UNAVAILABLE`.

**When** Worker retry 3× with backoff.

**Then** If still UNAVAILABLE → `ops.MarkDone(error UNAVAILABLE)`. No listener row; no VIP held (no successful alloc).

### GWT-FAIL-005 — vpc returns success but worker crashes before INSERT → orphan VIP

**Given** VIP allocated; worker pod OOM-killed before INSERT listener row.

**When** Restart.

**Then** Detectable via reconciler/cleanup job: `vpc.InternalAddressService.List(used_by="nlb_listener:*")` minus existing listener rows → orphan candidates. Background `orphan_vip_runner` calls `FreeIP` on orphans older than 5 minutes. (Note: this job is part of design DoD; may be deferred-but-tracked.)

### GWT-FAIL-006 — Drain runner running on two replicas — advisory lock prevents double-DELETE

**Given** 2 NLB replicas; both run `target_drain_runner`.

**When** Both attempt DELETE on same target row.

**Then** `pg_advisory_xact_lock(hashtext('kacho_nlb_drain_runner'))` taken by one; other waits or skips this tick.

### GWT-FAIL-007 — Migration failure rolls back via goose transaction

**Given** Bad migration introduced.

**When** Migrator runs.

**Then** Migration TX rolls back; goose_db_version unchanged. Service pod stays in init-container failure state. Helm rollback recovers.

### GWT-FAIL-008 — Idempotent operations under retry

**Given** Client retries Create with same idempotency_key (if exposed) or by re-issuing Create with same name.

**When** Second call.

**Then** ALREADY_EXISTS (NLB-009) — client treats as success-equivalent (or uses Get). No double-Create.

---

## 12. Newman regression matrix (production-readiness criterion)

### 12.1 Domain prefixes and counts

| Prefix | Resource | Classes covered | Min cases |
|---|---|---|---|
| `NLB-*` | NetworkLoadBalancer | CRUD/VAL/NEG/BVA/CONF/STATE/IDEM/LSG | ~70 |
| `LST-*` | Listener | CRUD/VAL/NEG/BVA/CONF/STATE/IDEM | ~50 |
| `TGR-*` | TargetGroup | CRUD/VAL/NEG/BVA/CONF/STATE/IDEM/LSG | ~55 |
| `TGT-*` | Target operations | CRUD/VAL/NEG/BVA/CONF/STATE/IDEM | ~45 |
| `OP-*` | Operation | CRUD/VAL/NEG/IDEM | ~20 |
| `AZD-*` | Authz (deny + grant edges) | All RPCs × {deny, grant, lifecycle} | ~50 |
| `XRES-*` | Cross-resource integration | E2E flows | ~15 |
| `DB-*` | Storage edge-cases (selected, mostly unit) | (covered in integration tests) | ~15 |
| `FAIL-*` | Failure modes / chaos | (subset of newman + k6) | ~10 |

**Target ≥320 newman cases**; with helper-block expansion (BVA per field × per-RPC) realistic 350-450.

### 12.2 Classes

| Class | Meaning |
|---|---|
| **CRUD** | basic Create/Read/Update/Delete happy paths |
| **VAL** | input validation (regex, enum, structural) |
| **NEG** | negative auth (PermissionDenied) + cross-service NotFound/Unavailable |
| **BVA** | boundary value analysis (min, max, off-by-one) |
| **CONF** | concurrency / race / OCC |
| **STATE** | state-transition preconditions (Start when ACTIVE, etc.) |
| **IDEM** | idempotency (re-call with same key) |
| **LSG** | list/selector/getfilter pagination |
| **AZD** | authz deny + grant + cache invalidation |

### 12.3 Test-first discipline (workspace запрет #11)

Newman cases written **per use-case PR** with RED-before-GREEN pair. CI fails PR without explicit `Tests: <NLB-XXX, NLB-YYY, …>` in description.

### 12.4 Coverage targets

- Unit (domain + service): **≥80% overall**, **≥85% domain**.
- Integration (testcontainers): every CHECK / partial UNIQUE / EXCLUDE / atomic CAS has a positive + negative integration test.
- Newman: 100% of RPC × class matrix per §12.1.
- k6: baseline pass per design §7.4 SLO (500 RPS / 5min / p95 ≤100ms / p99 ≤300ms / error <1%).

---

## 13. Non-functional requirements (NFR-*)

| NFR | Metric | Target |
|---|---|---|
| **NFR-1** | API p95 latency on Read (Get/List) | ≤100ms |
| **NFR-2** | Authz Check p95 latency | ≤20ms (design §3.5 budget) |
| **NFR-3** | Authz Check count per RPC | exactly 1 (scope-conditional RPCs = exactly 2) |
| **NFR-4** | Outbox-to-D13-delivery p95 latency | ≤5s steady-state |
| **NFR-5** | Cache hit ratio steady state | ≥95% |
| **NFR-6** | Mutation handler latency (sync portion only, до return Operation) | ≤200ms |
| **NFR-7** | Newman matrix pass rate | 100% (0 failures) |
| **NFR-8** | k6 baseline SLO | p95 ≤100ms / p99 ≤300ms / error <1% at 500 RPS |
| **NFR-9** | Cache invalidation propagation on revoke | ≤10s (KAC-108) |
| **NFR-10** | Service cold-start to ready | ≤30s (init-container migration + main-container start) |

---

## 14. Observability scenarios (OBS-*)

### GWT-OBS-001 — Prometheus metrics exposed

**Given** Service running.

**When** GET `/metrics`.

**Then** Required metrics present:
- `kacho_nlb_rpc_duration_seconds{service, method}` (histogram)
- `kacho_nlb_rpc_total{service, method, code}` (counter)
- `kacho_nlb_authz_check_duration_seconds` (histogram)
- `kacho_nlb_authz_check_cache_hits_total` / `_misses_total`
- `kacho_nlb_outbox_pending_count` (gauge)
- `kacho_nlb_drain_runner_targets_deleted_total` (counter)
- `kacho_nlb_lifecycle_streams_active` (gauge)

### GWT-OBS-002 — Structured JSON logs with request_id

**Given** RPC call.

**When** Inspect logs.

**Then** Each log entry has `request_id`, `trace_id`, `subject`, `rpc_method`. JSON format.

### GWT-OBS-003 — OpenTelemetry trace propagation

**Given** Client sends trace header.

**When** RPC executes.

**Then** Trace spans: `nlb.handler` → `nlb.usecase` → `nlb.repo` → cross-service spans (`vpc.AllocateExternalIP`, etc.) → linked to parent trace.

### GWT-OBS-004 — Alert rules defined (selected)

| Alert | Condition |
|---|---|
| `KachoNLBAuthzCheckLatencyHigh` | p95 >20ms for 5 min |
| `KachoNLBOutboxPendingHigh` | gauge >1000 for 5 min |
| `KachoNLBDrainRunnerStalled` | no DELETE for 10 min while pending DRAINING >0 |
| `KachoNLBLifecycleStreamsExhausted` | active == max for 5 min |
| `KachoNLBRPCErrorRateHigh` | error rate >5% for 5 min |

---

## 15. Fail-mode policy summary (canonical reference)

| Failure | Behavior | Subject visible result |
|---|---|---|
| FGA Check service unavailable | fail-closed | `PermissionDenied` |
| RPC not in PermissionMap | fail-closed; drift-test catches in CI | `PermissionDenied` |
| `FGA ErrNoPath` | passthrough to repo (KAC-133 pattern) | NotFound (от DB) |
| OpenFGA Write fails (D-11 sync) | abort worker, no commit | `done=true, error=UNAVAILABLE`; resource не создан |
| Outbox write fails | TX rollback, abort worker | `done=true, error=UNAVAILABLE` |
| D-13 subscriber disconnect | catch-up на reconnect via cursor | (no client-visible effect) |
| vpc/compute peer Get unavailable on Create | retry 3× → fail-closed | `done=true, error=UNAVAILABLE` |
| vpc.FreeIP unavailable on Delete Listener | mark `FAILED` outbox + retry job | listener stuck в DELETING; eventual consistency |
| Postgres unavailable | retry 3× → fail-closed | `done=true, error=UNAVAILABLE` |
| breakglass env var (`KACHO_NLB_AUTHZ__BREAKGLASS=true`) | bypass + WARN log | OK (production config-validation rejects this flag) |

---

## 16. Out-of-scope (explicit, with reserved slots)

### 16.1 GlobalLoadBalancer (cross-region composite layer) — RESERVED ONLY

**Status**: Design-only; **not implemented** in NLB MVP.

**Reserved**:
- Proto field-numbers `NetworkLoadBalancer.30-39` and `Target.10-19` (`reserved 30 to 39;` / `reserved 10 to 19;` directives in proto files).
- ID prefix `glb` in `kacho-corelib/ids.PrefixGlobalLoadBalancer`.
- Architecture doc `docs/architecture/12-future-cross-region.md` (plan, no code).
- No DB tables, no migrations, no proto messages — only the reservation.

**Future types** (when implemented, separate epic):
- `DNS_GEO` / `DNS_FAILOVER` / `DNS_WEIGHTED` — blocked by `kacho-dns` service (does not yet exist).
- `ANYCAST` — blocked by real BGP data-plane.

**Rejected approaches** (documented for trail):
- In-place `Target.region_override` — no industry precedent, breaks 4-way oneof clarity.

### 16.2 L4 data-plane sibling repo

Not created. No `kacho-nlb-implement`, no `kacho-nlb-controllers`. Control-plane only — real forwarding is out-of-scope for Kachō demo MVP.

### 16.3 Real healthcheck probes to backends

Not implemented. `HealthCheck` config persisted as desired-state; `GetTargetStates` returns deterministic computed ramp (per design §4.6).

### 16.4 Fine-grained custom-role expansion (start-only / stop-only)

Resolves through 3 existing FGA relations (`viewer`/`editor`/`owner`). Fine-grained partition is iam follow-up (KAC-108 follow-up); not blocking NLB MVP.

### 16.5 kacho-yc-shim adapter

Optional later compat layer; not part of NLB acceptance.

---

## 17. Definition of Done (DoD)

This document is **APPROVED** by `acceptance-reviewer` before implementation begins. The implementation epic (KAC-NLB ~21 subtasks) is **DONE** when all of the following are true:

- [ ] **D-1**: This acceptance document `✅ APPROVED` by `acceptance-reviewer` (no open `❌ CHANGES REQUESTED`).
- [ ] **D-2**: All 21 KAC subtasks per design §8.2 merged to main in their respective repos (`kacho-proto`, `kacho-corelib`, `kacho-iam`, `kacho-nlb` PRs #1-#5, `kacho-api-gateway`, `kacho-deploy`, `kacho-workspace`).
- [ ] **D-3**: CI green on every PR: build / vet / lint / unit (≥80% coverage; domain ≥85%) / govuln / integration (testcontainers) / security-scan (gitleaks + trivy SARIF) / drift-test (`permission_map_drift_test.go`).
- [ ] **D-4**: Newman matrix 100% pass — minimum **320 cases** + **≥30 AZD cases** + 0 failures; both prerequisite-stage (NLB-*/LST-*/TGR-*/TGT-*/OP-*) and authz-stage (AZD-*) green in `kacho-deploy` newman-e2e job.
- [ ] **D-5**: k6 baseline passes SLO (`p95 ≤100ms / p99 ≤300ms / error <1% at 500 RPS for 5 minutes`).
- [ ] **D-6**: All 30 permissions in `loadbalancer.*` catalog registered in `kacho-iam/internal/authzmap/permission_catalog.go`; drift-test validates uniqueness + regex + map coverage.
- [ ] **D-7**: 5 system roles seeded in `kacho-iam` migrations: `roles/loadbalancer.{admin,editor,viewer,operator,targetManager}`.
- [ ] **D-8**: api-gateway routes `/nlb/v1/*` registered (NLB/Listener/TG/OperationService public; opsproxy `nlb` prefix). `InternalResourceLifecycleService` exposed only on cluster-internal mux.
- [ ] **D-9**: Helm deployable end-to-end via `kacho-deploy make dev-up` from a clean cluster; init-container `kacho-migrator up` applies 0001_initial; main container `kacho-loadbalancer serve` starts < NFR-10.
- [ ] **D-10**: D-13 stream subscriber wired in `kacho-iam` (lifecycle-subscriber worker); FGA tuple-sync verified end-to-end (NLB.Create → kacho-iam consumes within ≤5s → openfga.Write succeeds).
- [ ] **D-11**: Vault notes (~28) created/updated: `KAC/KAC-NLB.md` (epic trail) + `resources/nlb-load-balancer.md` + `resources/nlb-listener.md` + `resources/nlb-target-group.md` + `resources/nlb-target.md` + `rpc/nlb-network-load-balancer-service.md` + `rpc/nlb-listener-service.md` + `rpc/nlb-target-group-service.md` + `rpc/nlb-operation-service.md` + `edges/nlb-to-vpc-address.md` + `edges/nlb-to-vpc-subnet.md` + `edges/nlb-to-vpc-nic.md` + `edges/nlb-to-compute-instance.md` + `edges/nlb-to-compute-region.md` + `edges/nlb-to-iam-project.md` + `edges/nlb-to-iam-check.md` + `edges/iam-to-nlb-lifecycle.md` + `packages/nlb-*` (~12 internal package notes).
- [ ] **D-12**: `docs/architecture/12-future-cross-region.md` (GlobalLoadBalancer reservation doc) created in `kacho-nlb/docs/architecture/`; proto reserves field-numbers 30-39 / 10-19; `ids.PrefixGlobalLoadBalancer="glb"` defined.
- [ ] **D-13**: All 4 within-DB invariants tested for concurrency race (testcontainers, 2 goroutines, deterministic): NLB-021 (xmin OCC), NLB-047 (FK fallback), TGR-024 (FK fallback), TGT-016 (Add vs Delete race).
- [ ] **D-14**: Observability — 7 metrics per OBS-001, JSON structured logs per OBS-002, OTel traces per OBS-003, 5 alerts per OBS-004.
- [ ] **D-15**: No mention of `yandex` anywhere in handwritten code, comments, env-vars, error texts, README, or migration files (запрет #2). Stylistic YC-likeness in tone/regex/error-format remains (per workspace YC-style вrвe врезка).

---

## 18. Traceability (acceptance ↔ test ↔ code)

Каждый GWT-XXX-NNN сценарий маппится 1-к-1 на:
1. **Newman case** в `kacho-nlb/tests/newman/cases/<domain>/<XXX>_<short_desc>.py` (декларативный → `gen.py` собирает Postman collection).
2. **Integration test** (для DB-уровневых сценариев) в `kacho-nlb/internal/repo/pg/<resource>_integration_test.go` (testcontainers Postgres).
3. **Unit test** (для domain validation) в `kacho-nlb/internal/domain/<resource>_test.go`.

Test naming convention: `Test<Resource>_<ScenarioID>_<ShortDescription>`. Например:
- `TestLoadBalancer_GWT_NLB_009_DuplicateNameAlreadyExists`
- `TestListener_GWT_LST_011_VIPRegionUniqueAcrossLBs_Race`
- `TestTarget_GWT_TGT_011_RemoveTargetsPhaseAImmediate`

Acceptance — **источник истины** для тестов. Изменения контракта **сначала** в этом документе → re-review → APPROVED → потом в коде.

---

## 19. Open questions for reviewer

None for v1 draft. All design decisions resolved in the brainstorming phase and consolidated in `2026-05-23-kacho-nlb-design.md`. Reviewer should focus on:
1. **Completeness** of RPC × class matrix (no RPC missing).
2. **Verbatim error texts** match design §3 / §6 / §15 (style consistency with kacho-vpc / kacho-iam).
3. **FGA permission strings** all 30 are referenced explicitly somewhere (catalog completeness — AZD-019).
4. **Reserved slots** for GlobalLoadBalancer clearly out-of-scope but tracked (D-12).
5. **DoD checklist** is operational (each item is verifiable post-implementation).

---

**End of acceptance document — DRAFT v1.**

> Дата следующего шага: после `✅ APPROVED` — старт `superpowers:writing-plans` → 21 KAC-subtask creation → rpc-implementer chain. До APPROVED — **код не пишется** (запрет #1).
