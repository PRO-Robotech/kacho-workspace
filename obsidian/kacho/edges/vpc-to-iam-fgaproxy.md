---
title: "vpc → iam: FGA-proxy RegisterResource/UnregisterResource (SEC)"
aliases:
  - vpc to iam fgaproxy
  - vpc register resource
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: planned
related_tickets:
  - "[[../KAC/SEC-A-proto-fga-proxy]]"
  - "[[../KAC/SEC-C-iam-fga-proxy-sa-roles]]"
tags:
  - edge
  - kacho-vpc
  - kacho-iam
  - cross-service
  - security
  - internal
---

> [!note] Callee-сторона готова в SEC-C; caller-сторона — SEC-D
> `kacho-iam.InternalIAMService.RegisterResource/UnregisterResource` реализован
> ([[../KAC/SEC-C-iam-fga-proxy-sa-roles]]). kacho-vpc начнёт вызывать это ребро в
> SEC-D (удаление прямого OpenFGA-клиента → outbox-intent в writer-tx ресурса →
> drainer→IAM.RegisterResource по mTLS). Контракт «FGA за IAM» (эпик #6).

# vpc → iam: FGA-proxy owner-tuple write/delete

**Protocol**: gRPC cluster-internal :9091 (Internal-only, ban #6; нет на external).
**Direction**: усиление существующего `vpc → iam` (ацикличность: iam не зовёт vpc).

## Контракт

- `RegisterResource({subject_id, relation, object, trace_id})` → пустой response (sync).
  IAM эмитит owner-hierarchy tuple в `kacho_iam.fga_outbox` в одной writer-tx; drainer
  применяет к OpenFGA. **Идемпотентно**: повтор → OK (не AlreadyExists).
- `UnregisterResource(...)` — симметричный revoke; снятие отсутствующего → OK (не NotFound).
- **at-least-once**: vpc-сторона (SEC-D) пишет intent в свой outbox в той же tx, что и
  Insert ресурса (no dual-write); drainer ретраит при IAM `Unavailable` — tuple не теряется.

## Authz (least-priv, SEC-C)

mTLS client-cert SAN `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc` → `sva`-id vpc →
ReBAC `Check(service_account:<sva-vpc>, fga_writer, iam_fgaproxy:system)`. vpc-SA несёт этот
relation-tuple (seed `0009`). Нет relation → `PermissionDenied`.

## Mirror-feed (labels + parent_project_id)

`RegisterResource`-intent несёт не только tuple, но и mirror-feed (`labels` +
`parent_project_id` + монотонный `source_version`) для IAM `resource_mirror` —
это питает ARM_LABELS-селектор (rsab reconciler материализует/ревокает
membership на `mirror.upsert`). Эмит-точка обязана использовать
`RegisterItems(ProjectHierarchyItem(projectID, <vpc_type>, id, LabelsToMap(labels)))`,
а не bare `RegisterIntent(ProjectHierarchy(...))` (последний оставляет mirror без
labels → селектор не матчит, under-show). На Update — `labelsInMask`-gated
re-emit с обновлёнными labels (revoke при снятии метки). `parent_project_id` =
собственный ProjectID ресурса.

## op-gating: Create-op ждёт read-after-register confirm (owner-tuple opgate P3)

Create-op **Network/SecurityGroup/Subnet** достигает `done=true, response` **только
после** read-after-register confirm owner-tuple: sync-registrar регистрирует tuple
внутри worker-fn (post-commit), затем worker прогоняет `InternalIAMService.Check`
(`subject=creator(op.Principal)`, `relation=v_update`, `object=vpc_<type>:<id>`) до
ALLOW. Так закрыто окно 403 «no direct relations granted» на **немедленной** мутации
создателя (op-done обгонял видимость tuple в FGA).

- **Confirm-ребро — REUSE** существующего `vpc→iam Check` (:9091, тот же `authzConn`,
  `check.OwnerConfirmer` поверх `IAMCheckClient`). **Нового cross-service ребра нет**
  (ацикличность: iam не зовёт vpc). `relation=v_update` — canonical mutate-relation;
  owner-tuple (project-parent-pointer) резолвит все `v_*` сразу → и immediate Delete не 403.
- **fail-closed**: confirm не достигнут за `KACHO_VPC_OWNER_CONFIRM_DEADLINE` (default 30s,
  ≪ op-timeout 4m ≪ OrphanGrace 5m) → `op.error(Unavailable, "owner-tuple registration
  not confirmed")` (**не** `DeadlineExceeded`); success-done без confirm **никогда**.
- **supersede SEC-D-11** (осознанно): op-completion теперь gated на confirm — при IAM/FGA
  outage дольше deadline op завершается error, а **не** ложным success. **Durability
  SEC-D-11 сохранена**: ресурс-строка + register-intent durable во всех ветках,
  register-drainer добивает tuple at-least-once (resource-ref в `Create<R>Metadata` на
  всех терминалах, вкл. error → клиент повторяет мутацию, не пере-создаёт).
- Confirm-gate активен только когда есть sync-registrar И `authzConn` (production);
  dev/no-iam → gate off (прежнее поведение). Update/Delete существующего ресурса **не**
  gated (нового owner-tuple не создаётся).

## History

- **T3.1 (#113)**: network Update + securityGroup Create+Update переведены на
  mirror-feed (labels). subnet — эталон.
- **T3.2 ([kacho-vpc#10](https://github.com/PRO-Robotech/kacho-vpc/issues/10))**:
  закрыт остаточный gap — routeTable / address / gateway / networkInterface
  переведены с bare tuple на `RegisterItems(ProjectHierarchyItem(... labels))` на
  Create + `labelsInMask`-gated re-emit на Update. proto/схема без изменений.
  PR [kacho-vpc#11](https://github.com/PRO-Robotech/kacho-vpc/pull/11). См.
  [[../KAC/sub-phase-T3.2-vpc-residual-label-feed]].
- **owner-tuple opgate P3 (монорепо)**: Network/SG/Subnet Create переведены на
  `operations.RunWithConfirm` — success-done gated на read-after-register confirm
  owner-tuple (reuse `Check`, без нового ребра). fail-closed Unavailable по
  `KACHO_VPC_OWNER_CONFIRM_DEADLINE`. Acceptance
  `docs/specs/sub-phase-owner-tuple-opgate-acceptance.md` (OTG-03/04/05/05b/13/16).
  Фундамент P1 — `pkg/operations` confirm-gate (commit 25a047f).

## See also

[[../rpc/iam-internal-iam-service]] [[../resources/iam-service-account]] [[vpc-to-iam-check]] [[compute-to-iam-fgaproxy]] [[iam-to-openfga-grant-write]] [[../KAC/EPIC-SEC-mtls-iam-authz]] [[../KAC/sub-phase-T3.2-vpc-residual-label-feed]]

#edge #kacho-vpc #kacho-iam #cross-service #security #internal
