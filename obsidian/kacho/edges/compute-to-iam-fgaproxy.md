---
title: "compute → iam: FGA-proxy RegisterResource/UnregisterResource (SEC)"
aliases:
  - compute to iam fgaproxy
  - compute register resource
category: edge
caller_repo: kacho-compute
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: done
related_tickets:
  - "[[../KAC/SEC-A-proto-fga-proxy]]"
  - "[[../KAC/SEC-C-iam-fga-proxy-sa-roles]]"
  - "[[../KAC/SEC-D-services-fga-via-iam-mtls]]"
tags:
  - edge
  - kacho-compute
  - kacho-iam
  - cross-service
  - security
  - internal
---

> [!note] Реализовано в SEC-D (caller); callee — SEC-C
> `kacho-iam.InternalIAMService.RegisterResource/UnregisterResource` реализован
> ([[../KAC/SEC-C-iam-fga-proxy-sa-roles]]). kacho-compute вызывает это ребро с SEC-D:
> прямой OpenFGA-клиент удалён, owner-tuple intent пишется в `compute_fga_register_outbox`
> в writer-tx ресурса, register-drainer → IAM.RegisterResource по (opt-in) mTLS.
> Контракт «FGA за IAM» (эпик #6); dual-write баг N5 устранён.

# compute → iam: FGA-proxy owner-tuple write/delete

**Protocol**: gRPC cluster-internal :9091 (Internal-only, ban #6; нет на external).
**Direction**: усиление существующего `compute → iam` (ацикличность сохранена).

## Контракт

Идентичен [[vpc-to-iam-fgaproxy]]: `RegisterResource`/`UnregisterResource` с
`{subject_id, relation, object, trace_id}`, идемпотентность как контракт (write
`already_exists`→OK, delete absent→OK), at-least-once через transactional-outbox (SEC-D).
IAM эмитит owner-tuple в `kacho_iam.fga_outbox`+drainer для compute-ресурсов
(`compute_instance:<...>` и т.п.).

## Authz (least-priv, SEC-C)

mTLS client-cert SAN `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-compute` → `sva`-id compute
→ ReBAC `Check(service_account:<sva-compute>, fga_writer, iam_fgaproxy:system)`. compute-SA
несёт relation-tuple (seed `0009`). Нет relation → `PermissionDenied`.

## Caller-side mechanics (SEC-D, kacho-compute)

- **Intent в writer-tx**: `internal/repo/outbox.go::emitFGARegisterIntent` пишет строку в
  `compute_fga_register_outbox` (миграция `0010`) В ТОЙ ЖЕ tx, что Insert/Delete ресурса
  (Instance/Disk/Image/Snapshot + inline boot/secondary disks). `event_type ∈
  {fga.register, fga.unregister}`; payload — set из `fgaintent.Tuple`
  (`project:<projectId> #project @compute_<kind>:<id>`) + (RSAB β) `labels` + `parent_project_id`
  для наполнения IAM `resource_mirror`. Tx abort → intent откатывается (no orphan).
- **Update-on-labels trigger (RSAB β / T3.1 #113)**: register-intent эмитится и на `Update`,
  когда `labels` в update-mask (gated `emitLabelsRegister`, full-PATCH ⇒ true), чтобы mirror не
  протух и ARM_LABELS-грант ревокался. Instance — с β; **Disk/Image/Snapshot — с T3.1**
  (`{disk,image,snapshot}_repo.go::Update(…, emitLabelsRegister)`). Полное снятие меток → upsert
  `labels={}` (НЕ Unregister — ресурс жив, G-3). Эмит в той же writer-tx, что UPDATE.
- **Drainer**: corelib `outbox/drainer` (`cmd/compute/main.go::startRegisterDrainer`,
  default-on `KACHO_COMPUTE_FGA_REGISTER_DRAINER_ENABLED`), channel/table
  `compute_fga_register_outbox`. Applier — `internal/clients/iam_register_applier.go`
  (`RegisterResource`/`UnregisterResource`). CAS-claim/advisory-lock → exactly-once across replicas.
- **Error-маппинг**: `InvalidArgument` → poison (no retry); прочее (Unavailable/mTLS-mismatch)
  → transient retry с backoff. IAM down → intent durable, Operation не падает (tuple не теряется).
- **mTLS (opt-in)**: `cfg.IAMRegisterMTLS` (`grpcclient.TLSClient`, env
  `KACHO_COMPUTE_IAM_REGISTER_MTLS_*`); `enable=false` → insecure (dev). Server-listener creds —
  `PUBLIC_SERVER_MTLS`/`INTERNAL_SERVER_MTLS` (`grpcsrv.TLSServer`).
- **Удалено**: `internal/clients/openfga_write_client.go`, `internal/fgawrite/` (прямой HTTP-write FGA).

## owner-tuple op-gating (P4) — Create-op ждёт read-after-register confirm

owner-tuple-opgate (`docs/specs/sub-phase-owner-tuple-opgate-acceptance.md`, APPROVED): Instance/Disk
`Create`-Operation достигает `done=true,result=response` **только после** read-after-register confirm
owner-tuple в FGA (нет окна 403 «no direct relations granted» на немедленной мутации создателем).

- **Confirm** — reuse существующего `InternalIAMService.Check` (тот же authz-conn, [[compute-to-iam-check]]);
  **нового ребра нет** (OTG-08). `check(subject=creator, relation=v_update, object=compute_<kind>:<id>)`:
  owner-tuple `project #project @compute_<kind>:<id>` — единый parent-pointer, каскадящий всю verb-связку,
  поэтому confirm `v_update` подтверждает эффективность и для Delete. Порт `ports.OwnerConfirmer`,
  impl — `internal/check/IAMCheckClient`, wiring — `cmd/compute` (только когда authzConn сконфигурирован).
- **Sync-registrar (NEW, compute его раньше НЕ имел)** — `internal/clients/iam_sync_registrar.go`
  (`ports.OwnerRegistrar`): post-commit синхронно регистрирует тот же owner-tuple через `RegisterResource`
  (тот же fga-proxy edge/creds, что drainer), чтобы confirm-gate happy-path'а резолвился немедленно, не
  ожидая poll'а register-drainer'а. Best-effort: ошибка → WARN, durable outbox-intent + drainer — backstop.
- **Gate-механизм** — corelib P1 `pkg/operations.RunWithConfirm` + `WithConfirmationDeadline`
  (env `KACHO_COMPUTE_OWNER_CONFIRM_DEADLINE`, default 30s ≪ opTimeout 4m). Timeout → `op.error(codes.Unavailable,
  "owner-tuple registration not confirmed")` (fail-closed, FIX-1; НЕ DeadlineExceeded). resource-ref в
  `Create<R>Metadata` durable на ВСЕХ терминалах вкл. error (FIX-3, orphan-guard). `Update`/`Delete`
  существующего — НЕ gated (нового owner-tuple не создают, OTG-16). **Supersede SEC-D-11**: timeout-ветка
  теперь `op.error`, durability ресурса/intent сохранена (drainer добивает at-least-once).

## History

- **SEC-D** ([[../KAC/SEC-D-services-fga-via-iam-mtls]]): caller-сторона реализована — прямой FGA
  удалён, transactional-outbox + register-drainer + opt-in mTLS. Закрыт dual-write баг N5.
- **owner-tuple-opgate P4** (compute Instance/Disk): Create-op gated на read-after-register confirm
  (reuse `Check`, sync-registrar добавлен) — окно 403 «no direct relations» на немедленной мутации закрыто.
  Тесты: `internal/service/owner_opgate_integration_test.go` (OTG-03/-04/-05/-05b/-16, testcontainers),
  `internal/clients/iam_sync_registrar_test.go`.
- **T3.1 / #113** ([[../KAC/sub-phase-T3.1-cross-service-label-revoke]], PR kacho-compute#62):
  Update-on-labels emit достроен на Disk/Image/Snapshot (раньше — только Instance) → ARM_LABELS
  revoke на снятие/смену метки. G-3 upsert-not-unregister. Create-эмит compute уже нёс labels
  (bare-create-бага, как у vpc.SG/nlb.listener, у compute нет). by-design compute §9.1.

## See also

[[../rpc/iam-internal-iam-service]] [[../resources/iam-service-account]] [[compute-to-iam-check]] [[vpc-to-iam-fgaproxy]] [[iam-to-openfga-grant-write]] [[../KAC/EPIC-SEC-mtls-iam-authz]]

> [!note] iam применяет тот же owner-tuple-co-commit к СВОИМ ресурсам (sub-phase 1.4 S2)
> Consumer'ы (vpc/compute/nlb) делают owner-tuple write через это сетевое ребро (`RegisterResource` по mTLS);
> iam как leaf-owner своих ресурсов делает ровно тот же co-commit **in-process** (свой `fga_outbox` + drainer) —
> см. [[iam-to-openfga-grant-write]].

#edge #kacho-compute #kacho-iam #cross-service #security #internal
