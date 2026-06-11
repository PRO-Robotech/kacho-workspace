---
title: "SEC-A: proto Internal IAM FGA-proxy (RegisterResource / UnregisterResource)"
aliases:
  - SEC-A
  - SEC-A-proto-fga-proxy
ticket_id: SEC-A
category: kac
status: in-progress
type: feature
repos:
  - kacho-proto
prs: []
yt_url: https://prorobotech.youtrack.cloud/issue/EPIC-SEC
opened: 2026-06-11
tags:
  - kac
  - feature
  - kacho-proto
  - security
  - proto
  - internal
---

# SEC-A: proto Internal IAM FGA-proxy (RegisterResource / UnregisterResource)

**Status**: in-progress (proto+buf готовы, закоммичены на ветку; ждёт push/PR/merge оркестратором)
**Type**: feature (proto + buf only — без Go-handler)
**Repos**: kacho-proto
**Branch**: `SEC-A-proto-fga-proxy`
**Commit**: `489326c` feat(iam): SEC-A Internal RegisterResource/UnregisterResource (FGA-proxy, exempt)
**Acceptance**: `docs/specs/sub-phase-SEC-A-proto-fga-proxy-acceptance.md` (APPROVED — эпик acceptance-фаза 7/7; header `Статус: DRAFT` stale, см. note ниже)
**Эпик**: [[EPIC-SEC-mtls-iam-authz]]

## Что и зачем

Два **Internal-only** RPC добавлены в существующий `InternalIAMService`
(`proto/kacho/cloud/iam/v1/internal_iam_service.proto`, package `kacho.cloud.iam.v1`):
`RegisterResource` / `UnregisterResource`. Это контракт **FGA-proxy** — через него
vpc/compute/nlb перестанут писать owner-hierarchy-tuple напрямую в OpenFGA (эпик #6:
«модули не ходят в FGA напрямую, только через IAM») и начнут декларировать намерение
«зарегистрировать/снять owner-tuple» через IAM. Подфаза — **proto + buf только**, без
Go-реализации (handler — SEC-C; transactional-outbox drainer в модулях — SEC-D).

## Контрактные свойства (зафиксированы в proto)

- Оба RPC **sync unary** (как `Check`/`WriteCreatorTuple`), НЕ async через `Operation`.
- **Internal-only :9091** — нет `google.api.http` (ban #6); gw-handler по default-FQN-пути
  (как `WriteCreatorTuple`), не tenant-facing REST-роут.
- authz `<exempt>` в permission-каталоге (как все Internal IAM RPC); least-priv энфорсится
  в handler (SEC-C) через ReBAC `fga_writer` @ `iam_fgaproxy:system` — НЕ permission-строкой
  (`iam.fgaproxy.write` запрещена, проверяется тестом SEC-A-03).
- **Идемпотентность контракта**: повтор Register → OK (не AlreadyExists); снятие отсутствующего
  Unregister → OK (не NotFound). Опора для at-least-once outbox-retry (SEC-D).
- Request: `subject_id` (`<=128`, required), `relation` (`<=32`, required), `object`
  (`<=128`, required), `trace_id` (`<=64`, optional). Response — пустой message.

## Затронутые сущности vault

- [[../rpc/iam-internal-iam-service]] — methods_count 7→9; +RegisterResource/UnregisterResource (Internal-only, exempt, идемпотентны)
- [[../edges/vpc-to-iam-fgaproxy]] (planned) — vpc→iam owner-tuple write/delete
- [[../edges/compute-to-iam-fgaproxy]] (planned) — compute→iam owner-tuple write/delete
- `.claude/rules/polyrepo.md` — runtime-edge vpc→iam / compute→iam (fgaproxy) + инвариант «vpc⇄compute не семантический цикл»

## Acceptance / Definition of Done

- [x] Test-first (ban #12): descriptor-assert conformance-тесты (SEC-A-01/02/03) — RED до proto, GREEN после (`kacho-proto/internal/conformance/`).
- [x] Два RPC + request/response messages в `InternalIAMService`; поля/numbers/annotations по acceptance.
- [x] `<exempt>` в каталоге для обоих RPC; `iam.fgaproxy.write` НЕ введена (SEC-A-03 зелёный).
- [x] Internal-only: нет `google.api.http`; не async Operation (SEC-A-11).
- [x] `make buf-lint` зелёный; `make buf-breaking` (against main) зелёный — additive only.
- [x] `make verify-no-yandex` зелёный; `make generate` — без drift (regenerate byte-identical).
- [x] `go build ./...` зелёный; `go test ./internal/conformance/... -run TestSECA` — 3/3 PASS.
- [x] Нет TODO/FIXME/skip в diff (ban #11/#13).
- [x] Закоммичено на ветку `SEC-A-proto-fga-proxy` (`489326c`); НЕ push, НЕ merge (оркестратор).
- [x] vault обновлён (этот trail + rpc/iam-internal-iam-service) + polyrepo.md runtime-edge.
- [ ] push ветки + PR в kacho-proto (оркестратор).
- [ ] merge в main + status→done.

## Note: stale acceptance-header

Header acceptance-дока (`docs/specs/sub-phase-SEC-A-proto-fga-proxy-acceptance.md`) всё ещё
читается `Статус: DRAFT`, хотя коммит `d1e7e76` («acceptance-фаза 7/7 **APPROVED**») и тело
v2-дока («закрывает acceptance-review v1») фиксируют, что SEC-A APPROVED. STOP-gate (ban #1)
удовлетворён по committed-истории; header-строку стоит флипнуть на APPROVED отдельной правкой.

## Связанные тикеты

- [[EPIC-SEC-mtls-iam-authz]] (родитель)
- [[SEC-B-corelib-mtls]] (kacho-corelib, параллельно волна 1)
- SEC-C (kacho-iam, handler RegisterResource/UnregisterResource — зависит от A+B) · SEC-D (outbox-drainer в модулях — зависит от A+C)

#kac #feature #kacho-proto #security #proto #internal
