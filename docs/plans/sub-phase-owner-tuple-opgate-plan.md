# Owner-tuple op-gating — implementation plan (монорепо)

Source acceptance (✅ APPROVED): `docs/specs/sub-phase-owner-tuple-opgate-acceptance.md` (OTG-01..16).
Полный план — в транскрипте Plan-агента (a76eabc9c6a4cad4c); здесь — конденсат + монорепо-пути.

## Гарантия
Create-Operation owner-ресурса (iam AccessBinding, vpc Network/SG/Subnet, compute Instance/Disk,
storage Volume) достигает `done=true,result=response` ТОЛЬКО после подтверждения owner-tuple в FGA
(read-after-register). Fail-closed: deadline→`op.error(codes.Unavailable,"owner-tuple registration
not confirmed")`, resource-ref в `Create<Resource>Metadata` на ВСЕХ терминалах вкл. error;
success-done никогда без confirm.

## Решения (D1-D5)
- **D1 corelib-shared confirm-gate** (DRY): `ConfirmFunc func(ctx)(confirmed bool,err error)` в
  `pkg/operations` Worker; confirm-loop в `execute()` после `fn` success, до `MarkDone`; deadline→MarkError.
- **D2 in-worker bounded loop** (v1; watcher-hand-off — escalation для system-design-reviewer).
- **D3 proto:** PENDING = done=false + существующий `Create<R>Metadata` (НЕТ нового поля). +ОДНО
  additive `iam.v1.CheckRequest.consistency` (enum, HIGHER_CONSISTENCY) — buf-breaking=0 (internal-only msg).
- **D4 deadline 30s** (≪ opTimeout 4m ≪ OrphanGrace 5m); per-attempt = CheckTimeout; env
  `KACHO_<SVC>_OWNER_CONFIRM_DEADLINE`; тесты override 500ms.
- **D5 confirm реплицирует gateway scope_extractor Check**: subject=creator(op.Principal),
  object=`<fga-object>:<id>`, relation=та, что gateway требует на mutate (v_update/v_delete).

## Монорепо-пути (транслировано из polyrepo-плана)
- corelib operations: **`pkg/operations/worker.go`** (+ types.go, repo.go[MarkError уже сохраняет metadata], helpers.go, metrics.go)
- iam: `services/iam/internal/apps/kacho/api/access_binding/create.go` (in-process confirm через `u.relations`/openfga_client; после γ-01 `ReconcileObject`); `services/iam/internal/clients/openfga_client.go` (+consistency, если D3); iam Check-handler forwarding.
- vpc: `services/vpc/internal/apps/kacho/api/network/create.go` (+SG+Subnet); `services/vpc/internal/apps/kacho/check/check_client.go` (owner-confirmer через IAMCheckClient/authzConn, HIGHER_CONSISTENCY); `cmd/vpc` wiring.
- compute: `services/compute/internal/service/{instance,disk}.go` (`runOpWithConfirm`); confirmer; **add `iam_sync_registrar.go` (parity — compute его НЕ имеет)**.
- storage: `services/storage/internal/service/volume/volume.go`; confirmer.
- proto (D3): `services/iam/.../internal_iam_service.proto` (монорепо proto — уточнить путь) или `kacho-proto` sibling — проверить где proto в монорепо.

## Фазы (TDD RED первым)
- **P0** (если D3): proto additive CheckRequest.consistency, buf breaking=0, regen. Gate proto-api-reviewer.
- **P1** corelib `pkg/operations`: RED `worker_confirm_test.go` (confirm-pending→done=false→ALLOW→MarkDone ordering; deadline→MarkError Unavailable точный текст, code!=DeadlineExceeded, no success-done; nil confirm=MarkDone back-compat; -race; shutdown mid-confirm done=false). Затем ConfirmFunc+WithConfirmationDeadline+RunWithConfirm+loop. Блокирует всё.
- **P2** iam AccessBinding (leaf, канонический): RED OTG-03/-05b (in-process fake FGA). Switch Create→RunWithConfirm после ReconcileObject; nil-safe.
- **P3** vpc (полная матрица): RED OTG-03/-04(крит)/-05(крит)/-05b(крит)/-06/-07/-08/-16/-13(-race)/-09..12. Confirmer+switch Network/SG/Subnet+cmd wiring.
- **P4** compute Instance/Disk: RED OTG-03/-04/-05/-05b/-16. `runOpWithConfirm`+confirmer+sync-registrar.
- **P5** storage Volume: RED OTG-03/-04/-05. Confirmer+switch.
- **P6** newman (§6.2): RED OTG-01/02/14/04 → green post-fix. buf breaking=0, vpc `make audit-list-filter`.
- **P7** trail: vault edges/rpc/resources/KAC + follow-up Issue idempotency-key-на-Create (FIX-3).

Merge-блокеры (DoD): RED→GREEN пары OTG-04/-05/-05b/-13.

## Риски
Confirm-навечно→30s deadline≪OrphanGrace (worker терминализует первым, resource durable, drainer backstop).
Slot-exhaustion на FGA-outage→bounded+backlog-backpressure (эскалация: watcher hand-off).
Residual 403-окно→HIGHER_CONSISTENCY (D3)+реплика gateway Check (D5); OTG-04 lock. Concurrency→terminalWrite CAS+ClaimForExecution+-race.
