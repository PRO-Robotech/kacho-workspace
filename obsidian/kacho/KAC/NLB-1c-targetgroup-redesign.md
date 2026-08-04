---
title: "NLB-1c — TargetGroup HealthCheck redesign"
tags: [kac, kacho-nlb, redesign, targetgroup]
status: done
type: sub-phase
category: kac
---

# NLB-1c — TargetGroup HealthCheck redesign

> [!important] Статус приведён к дереву продукта — волна сверки vault 2026-08-05
> Сверено с `PRO-Robotech/kacho@96b2879a` (ствол `redesign/integration` — её предок).
> Прежний статус — `in-progress`; он пережил свой предмет и держался на списке
> пунктов, часть которых больше не существует как единица работы.
>
> **done.** Группа целей и её проверка здоровья в дереве: отдельный `health_check.proto`, у типа проверки четыре ветви взаимоисключающего выбора — то самое, ради чего заводилась подфаза.

**Status**: done · было при заведении: F6 landed + tested + committed on `redesign/integration`; F7-inline N/A on integration; NLB-1d newman migrated
**Type:** sub-phase (carve of KAC-NLB-1, redesign of `kacho-nlb`)
**Repo:** `project/kacho` (monorepo `github.com/PRO-Robotech/kacho`), `services/nlb`
**Branch:** `redesign/integration`
**Acceptance:** `docs/specs/sub-phase-NLB-1c-targetgroup-redesign-acceptance.md` (APPROVED) · `...-NLB-1d-...` (APPROVED)

## Что и зачем

Завершает редизайн `TargetGroup` — 3-й ядровый ресурс nlb. Реализовано на
`redesign/integration` (не на stale `redesign/nlb-1b` ветке — та расходится с
integration по VIP-модели). Ground-truth integration: HealthCheck domain уже нёс
4-way oneof, но proto был AS-IS (name, только tcp/http). NLB-1c закрыл gap.

### Landed (F6, PRs → integration bca9100, dafc795)

- **HealthCheck redesign** (proto+domain+mapping): снят `name` (embedded value-object);
  oneof расширен `tcp` / `http{path,expected_codes,host,headers}` / `https{...}` /
  `grpc{service_name}`; probe.port опционален (0 → inherit `TG.port`) → output-only
  `effective_port°` (NLB-1-34/39). Закрыл kacho#8 (https/grpc теперь на wire).
- **Durations [B8]**: `deregistration_delay_seconds`/`slow_start_seconds` int32 →
  `deregistration_delay`/`slow_start` `Duration`. DB-колонки остаются int-seconds
  (drain-runner `make_interval` цел) — конверсия на repo-boundary
  (`dto.DurationToSeconds`/`SecondsToDuration`). **Миграция не нужна.**
- **Update oneof-replace дисциплина** (NLB-1-36/37/38): dotted `health_check.<scalar>`
  merge-validated PATCH; probe atomic-replace с сохранением sibling-скаляров;
  probe-путь без дискриминатора → `INVALID_ARGUMENT` (не silent-clear).
- **port LIVE-mutable** (NLB-1-56): добавлен в `UpdateTargetGroupRequest` + repo UPDATE
  SET → re-echo в `Listener.resolved_backend_port°` (derived SQL subselect; integration
  `TestListener_NLB_1_22_RepointTargetGroup`).
- **immutables** `region_id`/`project_id` — "<field> is immutable after TargetGroup.Create"
  (NLB-1-40, ДО UpdateMask).
- **teardown RESTRICT blocker-list** (NLB-1-41): `ReferencingListenerIDs` repo-метод →
  `FailedPrecondition "target group is referenced by listeners: [ids]"` (FK 0018 — backstop).

### F7-inline (NLB-1-57/58) — N/A на integration

Acceptance предполагала one-shot inline `listenerSpec.targetGroup` (lineage nlb-1b).
На integration `listener_specs`/`attached_target_groups` **зарезервированы** в
`CreateNetworkLoadBalancerRequest` — inline-at-Create заменён отдельными RPC
(TG.Create + Listener.Create, wired by id). Design integration **superseded**
acceptance F7-inline → инлайн не реинтродуцируем (был бы re-add removed feature).

### NLB-1d (частично, PR d82b128)

- Newman TG-кейсы мигрированы на redesigned shape (tcp/http, durations-строки,
  effectivePort); негативы `*-VAL-{HTTPS,GRPC}-PROBE-UNSUPPORTED` → позитивы
  `*-CRUD-{HTTPS,GRPC}-PROBE` (kacho#8 закрыт). gen.py регенерил 367 кейсов.
- Gateway: TargetGroupService RPC не менялись (только поля) → доп. регистрация не нужна.
- Live newman — CI (стенд не port-forward'ится локально).

## Verify

- `go build ./...` + nlb short tests + golangci-lint + `go test -p1` integration
  (repo/pg, dto, targetgroup, listener, loadbalancer) — все GREEN.
- Integration подтвердил: HC JSONB 4-way roundtrip, durations roundtrip, port CHECK,
  resolved_backend_port re-echo, teardown FK RESTRICT, ReferencingListenerIDs.

## Затронутые сущности vault

[[resources/nlb-target-group]] · [[resources/nlb-listener]] · [[rpc/nlb-target-group-service]] · [[NLB-1b-expand-loadbalancer-listener-core]]

## Остаток (CONTRACT — следующий этап)

LB-side legacy removal (start/stop/attach/detach RPC, VipSource pivot, type/placement_type
authority-switch) — 1b-CONTRACT tail, breaking, отдельный chunk. См. proto-comment
`network_load_balancer.proto` "authority switch land in NLB-1c" — фактически LB-редизайн, не TG.
