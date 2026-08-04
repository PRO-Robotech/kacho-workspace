---
title: "NLB-1b EXPAND — LoadBalancer + Listener core (parallel-change)"
tags: [kac, nlb, redesign, expand-contract]
status: done
type: sub-phase
category: kac
---

# NLB-1b EXPAND — LoadBalancer + Listener core (parallel-change)

> [!important] Статус приведён к дереву продукта — волна сверки vault 2026-08-05
> Сверено с `PRO-Robotech/kacho@96b2879a` (ствол `redesign/integration` — её предок).
> Прежний статус — `in-progress`; он пережил свой предмет и держался на списке
> пунктов, часть которых больше не существует как единица работы.
>
> **done.** Расширяющая фаза доехала и перестала быть отдельной: балансировщик и слушатель живут в контракте (`network_load_balancer*.proto`, `listener*.proto`, шесть RPC у слушателя). Ветка `redesign/nlb-1b`, к которой привязана записка, разошлась со стволом по модели внешнего адреса ещё тогда — судить по ней нельзя.

**Status**: done · было при заведении: EXPAND phase committed on branch; MIGRATE/CONTRACT pending
**Type:** sub-phase (carve of KAC-NLB-1, redesign of `kacho-nlb`)
**Repo:** `project/kacho` (monorepo `github.com/PRO-Robotech/kacho`), `services/nlb`
**Branch:** `redesign/nlb-1b` (continues from F6 commit `25f0e82`)
**Acceptance:** `docs/specs/sub-phase-NLB-1b-loadbalancer-listener-core-acceptance.md` (APPROVED)

## Что и зачем

NLB-1b core (`NetworkLoadBalancer` + `Listener` redesign) is an **entangled atomic
cascade** with no intermediate green slice under atomic-replace. Split into
**expand-contract (parallel-change)**: EXPAND → MIGRATE → CONTRACT. This note tracks
the **EXPAND** phase — purely ADDITIVE, nothing removed, green at every step, buf
breaking clean vs the branch base.

### Landed in EXPAND (additive, fresh proto field numbers, buf-clean)

- **NetworkLoadBalancer.admin_state** (enum `ENABLED|DISABLED`, field 41) — LIVE-mutable
  administrative state (redesign replacement for `:start`/`:stop`). Stored + echoed +
  Create/Update input. NOT yet status-authoritative (0013 trigger untouched;
  Start/Stop RPCs retained). Migration `0016`.
- **NetworkLoadBalancer.placement** (enum `EXTERNAL_REGIONAL|INTERNAL_REGIONAL|
  INTERNAL_ZONAL`, field 40) — merged placement discriminator, persisted
  derived-consistent with legacy `type`/`placement_type`; `placement°` derived on read
  when the column is empty; immutable in Update; optional Create input validated for
  consistency. type°/placement_type° still echoed unchanged. Migration `0017`.
- **Listener.target_group_id** (field 19) — maps to the existing `default_target_group_id`
  reference (both coexist); LIVE-mutable repoint; precedence over the legacy field.
- **Listener.resolved_backend_port°** (field 20) + **Listener.substatus°** (field 21) —
  derived read-only: echo of the wired `TargetGroup.port` (scalar subquery in the repo
  read; works in INSERT ... RETURNING and Get/List) → `OK`, else `MISCONFIGURED`.

### EXPAND invariant (not touched)

M:N pivot `attached_target_groups`, `AttachTargetGroup`/`DetachTargetGroup`,
`Start`/`Stop`, VIP-on-LB, `type`/`placement_type` inputs, `target_port` — all
**retained**. No removals, no authority switch, no `0013` trigger rewrite.

### Deferred to MIGRATE / CONTRACT (honest scope)

- **LB `securityGroupIds` + `crossZoneEnabled`** — reviving the reserved proto names is
  buf-**breaking** (`RESERVED_FIELD_NO_DELETE`), so they belong in the breaking phase
  (CONTRACT), grouped with the acceptance's declared breaking set. Deferred.
- **Listener VIP anchor** — ✅ **LANDED (MIGRATE F5, see below)**. Full VIP saga wired.
- **type/placement_type → derived-authority + write-reject** (NLB-1-08 full) — MIGRATE.
- **admin_state → status DISABLED recompute** (0013 trigger rewrite) — ✅ **LANDED (MIGRATE F3, @1887f3c)**.
- **targetGroupId authoritative FK-RESTRICT** (replace pivot) — MIGRATE.
- **Removal** of pivot/attach/detach/start/stop/VIP-on-LB/target_port — CONTRACT.

## Затронутые сущности vault

- [[nlb-load-balancer]] — new additive fields `adminState`, `placement` (derived
  `type°`/`placementType°` unchanged in EXPAND).
- [[nlb-listener]] — new additive fields `targetGroupId`, `resolvedBackendPort°`,
  `substatus°`.
- [[nlb-network-load-balancer-service]] — Create/Update accept `adminState`/`placement`.
- [[nlb-listener-service]] — Create/Update accept `targetGroupId`.

(Full resource/rpc contract updates land with CONTRACT, when the transitional
coexistence collapses to the final authoritative shape.)

## MIGRATE F5 — Listener VIP: НЕ приземлился (только мёртвая половина)

> [!warning] Ревизия 2026-07-25 — запись исправлена по факту кода
> Прежняя редакция утверждала «VIP-анкер вернулся на Listener (LANDED @ f2a1330)». Это **неверно**:
> в `redesign/integration` приземлилась только **DB-половина** (коммит `f2adb4d` — миграция `0021`
> + repo-level integration-тесты). Proto/use-case-половина **никогда не landed**: `listener.proto`
> держит `reserved 4, 12, 13, 14, 15` (`region_id`/`ip_version`/`address_id`/`allocated_address`/
> `subnet_id`), `CreateListenerRequest` — `reserved 8, 9`, а `Listener.Create` — чистый INSERT без
> обращения к vpc. Ни `Listener.Address`-message, ни `vip_zone_id`-колонки, ни `PinVIPZoneCAS`
> в дереве нет.

**Следствие — мёртвая конструкция в схеме.** `0021` пересоздала partial-UNIQUE
`listeners_region_vip_uniq (region_id, allocated_address, port, protocol) WHERE status<>'DELETING'
AND allocated_address<>''` под контракт, которого нет. `listeners.allocated_address` прод-кодом не
пишется (`SetAllocatedAddress`/`SetVIP` в repo — без прод-вызывающих), поэтому partial-предикат не
матчил ни одной строки: индекс не энфорсил ничего и документировал ложный инвариант.

**Сведение (2026-07-25):**

- **миграция `0025`** снимает `listeners_region_vip_uniq` (`DROP INDEX CONCURRENTLY`; Down
  восстанавливает состояние `0021` с self-heal INVALID-остатка). `0021` не редактируется (ban #5).
- **repo-тесты** `listener_vip_uniq_integration_test.go` (NLB-1-30/31/55 на листенере) удалены —
  они выставляли `AllocatedAddress` вручную и локали контракт, которого продукт не даёт.
  Действующие эквиваленты уже есть на LB: `TestLB_AttachVIP_Concurrent*` (per-region double-claim,
  single-VIP-per-LB CAS, cross-region scope).
- **спека** перепривязана: `module-nlb.md` §«VIP — свойство LoadBalancer'а»,
  `sub-phase-NLB-1b-…` §F5, `sub-phase-NLB-1-…` §F5; сценарии 4.0 (`GWT-LST-001/002/…/022/023`,
  `GWT-DB-007`, `GWT-FAIL-004/005`) помечены **[СУПЕРСЕЖЕН]** с указанием перепривязки.

**Действующая модель** (что реально в коде): VIP — на `NetworkLoadBalancer`, один `vpc.Address` на
семейство; источник per-family на Create (`v4_source`/`v6_source`: `subnet_id` | `address_id` |
`public{}`), immutable input-only; наружу `v4AddressId°`/`v6AddressId°`. Uniqueness —
`load_balancers_region_v4_uniq`/`_v6_uniq` + `AttachVIP` CAS. Release — `LoadBalancer.Delete` /
компенсация Create-саги / free-ip-reconciler, ветка по `vip_origin` (`auto`|`linked`).
Детали — [[../edges/nlb-to-vpc-vip-allocation]], [[../resources/nlb-load-balancer]].

## MIGRATE F3 — status auto-recompute glossary (LANDED, `redesign/nlb-1b` @ 1887f3c)

`lb_status_recompute()` переписан под новый глоссарий (NLB-1-13/17/18) — **0023-successor**
(0013 не редактировался, ban #5):

- **DISABLED** ⟺ `admin_state=DISABLED`; **INACTIVE** ⟺ enabled ∧ нет listeners;
  **DEGRADED** ⟺ enabled ∧ ≥1 listener с пустым `default_target_group_id`;
  **ACTIVE** ⟺ enabled ∧ ≥1 listener ∧ каждый резолвит TG.
- ACTIVE переключён `has_attached`(pivot) → **listener-TG-resolution** (`default_target_group_id`
  non-empty; FK RESTRICT гарантирует существование TG).
- **admin_state → status feed**: новый триггер `AFTER UPDATE OF admin_state ON load_balancers`,
  recursion-safe (recompute пишет только `status`). Never-auto-ENABLE (NLB-1-14) держится:
  на DISABLED-LB listener-события оставляют DISABLED.
- **CAS-guard** сохранён (sec-hardening r3 lost-update); eligible-set расширен
  `{INACTIVE,ACTIVE,DEGRADED,DISABLED}`; explicit lifecycle (CREATING/STARTING/STOPPING/
  STOPPED/DELETING) не затирается. `load_balancers_status_check` расширен (+DEGRADED/DISABLED).
- **proto** `NetworkLoadBalancer.Status` +`DEGRADED=8`/`DISABLED=9` (additive), domain-consts,
  `type2pb.lbStatusToPb` mapping.
- TDD RED→GREEN: new pg glossary tests (Inactive→Active-via-wired-listener / Degraded /
  Disabled-feed) + rewrite `TestLB_StatusRecomputeTrigger` / `TestLBStatusRecompute_PreservesConcurrentStop`
  (lost-update CAS) / `TestIntegration_AttachTargetGroup_HappyPath_AndStatusRecompute` под новый глоссарий.

## DoD (EXPAND)

- [x] additive proto (fresh numbers) — buf lint + buf breaking (vs branch base) clean
- [x] domain newtypes + Validate + Equal; migrations 0016/0017 (ADD COLUMN + CHECK, ban #10; 0001-0015 untouched, ban #5)
- [x] repo scan/insert/update + derived read subquery; type2pb echo/derive
- [x] use-case additive inputs (non-authoritative); update immutable/mutable discipline
- [x] TDD RED→GREEN per field; integration (testcontainers pg16) round-trip + CHECK + RETURNING-subquery
- [x] `go build ./...`, `go test ./services/nlb/...`, `golangci-lint`, `go vet` green
- [ ] MIGRATE + CONTRACT phases (separate work)
