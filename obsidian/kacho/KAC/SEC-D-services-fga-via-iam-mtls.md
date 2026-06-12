---
title: "SEC-D: vpc/compute/nlb — FGA via IAM (transactional-outbox) + opt-in mTLS"
aliases:
  - SEC-D
  - SEC-D-services-fga-via-iam-mtls
ticket_id: SEC-D
category: kac
status: test
type: feature
repos:
  - kacho-compute
  - kacho-vpc
  - kacho-nlb
prs: []
yt_url: https://prorobotech.youtrack.cloud/issue/EPIC-SEC
opened: 2026-06-11
tags:
  - kac
  - feature
  - kacho-compute
  - kacho-vpc
  - security
  - internal
---

# SEC-D: services FGA via IAM (transactional-outbox) + opt-in mTLS

**Status**: test (kacho-compute код готов, тесты зелёные; vpc/nlb — параллельно)
**Type**: feature
**Repos**: kacho-compute, kacho-vpc, kacho-nlb
**Branch**: `SEC-D-kacho-compute-fga-via-iam-mtls` (compute)
**Acceptance**: `docs/specs/sub-phase-SEC-D-services-fga-via-iam-mtls-acceptance.md`
**Эпик**: [[EPIC-SEC-mtls-iam-authz]] (зависит от [[SEC-A-proto-fga-proxy]] + [[SEC-B-corelib-mtls]] + [[SEC-C-iam-fga-proxy-sa-roles]])

## Что и зачем

Consumer-сторона «FGA за IAM» (эпик #6) + устранение dual-write-бага N5 (эпик §3.1 C1).
Прямой OpenFGA-write удалён; owner-tuple intent пишется в outbox в writer-tx ресурса
(no dual-write), register-drainer применяет его через IAM.RegisterResource по opt-in mTLS.
IAM down → intent durable + retry → tuple не теряется (раньше best-effort → потеря навсегда → DENY).

## Реализация (kacho-compute)

- `internal/migrations/0010_fga_register_outbox.sql` — таблица `compute_fga_register_outbox`
  (BIGSERIAL, event_type CHECK `fga.register|fga.unregister`, payload JSONB, sent_at/last_error/
  attempt_count, partial pending-idx, NOTIFY-trigger). up/down/up зелёный.
- `internal/fgaintent/fgaintent.go` — leaf-пакет: `Tuple`/`Payload` + `ProjectHierarchyTuple`
  (`project:<projectId> #project @compute_<kind>:<id>`) + Encode/Decode. Unit-тест.
- `internal/repo/outbox.go::emitFGARegisterIntent` — intent в writer-tx; вызван из Insert/Delete
  всех 4 repo (Instance/Disk/Image/Snapshot + inline boot/secondary disks). Delete → `… RETURNING project_id`.
- `internal/clients/iam_register_applier.go` — drainer.Applier → `RegisterResource`/`UnregisterResource`;
  `InvalidArgument`→poison, прочее→transient retry.
- `cmd/compute/main.go::startRegisterDrainer` — corelib drainer wiring (default-on) + opt-in mTLS
  server/client creds (`cfg.{IAMRegisterMTLS,VPCMTLS,PublicServerMTLS,InternalServerMTLS}`).
- `internal/config/config.go` — per-edge `grpcclient.TLSClient`/`grpcsrv.TLSServer` (LoadPrefixed
  `KACHO_COMPUTE`, env `*_MTLS_*`); `Load`→`LoadPrefixed`; `LoadInto` тест-хелпер.
- **Удалено**: `internal/clients/openfga_write_client.go`, `internal/fgawrite/`, `AuthZTupleWrite*` config,
  `WithFGAWriter`/`fgaWriter` из 4 сервисов.

## Реализация (kacho-nlb) — ветка `SEC-D-kacho-nlb-fga-via-iam-mtls`

- `internal/migrations/0002_fga_register_outbox.sql` — таблица `kacho_nlb.fga_register_outbox`
  (BIGSERIAL, event_type CHECK `fga.register|fga.unregister`, payload JSONB + `jsonb_typeof=object` CHECK,
  resource_kind/resource_id для observability, sent_at/last_error/attempt_count, partial pending-idx,
  NOTIFY-trigger `kacho_nlb_fga_register_outbox`). Отдельная таблица (OQ-SEC-D-1) — изолирует от D-13 `nlb_outbox`.
- `internal/domain/fga_intent.go` — pure-Go domain value-types: `FGATuple`/`FGARegisterIntent` (Marshal/Valid) +
  object-type (`lb_*`, KAC-178) / relation (`admin`/`project`/`load_balancer`) консты + tuple-builders
  (`FGAProjectTuple`/`FGACreatorTuple`/`FGAParentLinkTuple`) + `FGASubjectFromPrincipal`. Single source of truth
  для FGA-vocabulary nlb (бывшие `internal/fgawrite` консты переехали сюда).
- `internal/repo/kacho/iface_fga_register_outbox.go` (`FGARegisterEmitter`) + `pg/fga_register_outbox_emitter.go`
  (INSERT в writer-tx; пустой tuple-set → no-op). Вызван из Create/Delete worker всех 3 ресурсов
  (LoadBalancer/Listener/TargetGroup) в той же writer-tx, что и Insert/Delete.
- `internal/clients/iam/register_applier.go` — `drainer.Applier`+`Decoder` → `RegisterResource`/`UnregisterResource`;
  `InvalidArgument`/malformed-payload → poison (`ErrPermanent`), `Unavailable`/`Deadline`/`PermissionDenied` → transient retry.
- `cmd/kacho-loadbalancer/main.go` — register-drainer task (corelib `outbox/drainer`, default-on OQ-SEC-D-5,
  FOR UPDATE SKIP LOCKED) + opt-in mTLS server creds (`grpcsrv.TLSServerCreds(cfg.MTLS.Server)`) +
  per-edge client creds (`cfg.MTLS.{IAMRegister,VPC,Compute}`); `peers.Register` → IAM internal conn.
- `internal/apps/kacho/config/config.go` — `MTLSConfig` per-edge (`grpcsrv.TLSServer`/`grpcclient.TLSClient`,
  ENV `KACHO_NLB_MTLS__*`, default `enable=false`=insecure) + `FGARegisterDrainerConfig`.
  **Удалён dead direct-FGA config** (`FGAConfig.Endpoint/StoreID/ModelID`, `FGATupleWriteConfig`).
- **Удалено**: `internal/fgawrite/` (весь пакет), `internal/clients/iam/hierarchy_client*.go`. grep-gate SEC-D-07
  (`grep -rn openfga internal/clients/`) = 0.

## kacho-nlb DoD

- [x] Test-first: листенер тест-пакет починен под SEC-D (outbox-intent вместо `suite.fga.creatorCalls`; 6-арг конструкторы).
- [x] S1: migration 0002; intent в writer-tx (Create→register, Delete→unregister; 3 ресурса); direct-FGA удалён.
- [x] S2: register-drainer + applier; SEC-D-09/10 happy, **SEC-D-11 IAM-down→durable→recover (КРИТ)**, SEC-D-12 idempotent-reapply,
  **SEC-D-13 concurrent 2-replicas exactly-once (ban #10)**, SEC-D-14 poison.
- [x] S3: opt-in mTLS server+client per-edge (SEC-D-16 disabled-default-insecure, SEC-D-17/server-creds, fail-closed missing-CA).
- [x] `go build ./...` 0; `go vet ./...` 0 (все тест-пакеты компилируются); listener/loadbalancer/targetgroup/config/check/domain/clients `-race` GREEN.
- [x] Fix: goose package-global race (`SetBaseFS`/`SetDialect`/`Up`) под parallel testcontainers → `gooseMu` guard в listener/loadbalancer/targetgroup integration_test (test-infra only).
- [~] golangci-lint v2.1.6 (== CI v7 action): 0 SEC-D-issues; остаются 5 pre-existing `internal_lifecycle` underscore-package (KAC-157, не трогали). Установленный v1.59.1/go1.22 даёт spurious typecheck vs repo go1.25 (env mismatch).
- [~] govulncheck: только stdlib go1.25.7 (fixed go1.25.8) — вне SEC-D-кода.
- [x] vault trail: [[../edges/nlb-to-iam-fga-register]] (новый) + [[../edges/nlb-to-iam-creator-tuple]] (deprecated) + этот файл.
- [ ] Commit на ветке `SEC-D-kacho-nlb-fga-via-iam-mtls` (Closes Issue N5); PR + merge — оркестратор.

## Затронутые сущности vault

- [[../edges/compute-to-iam-fgaproxy]] — caller-сторона реализована (outbox→drainer→RegisterResource, mTLS, History)
- [[../edges/nlb-to-iam-fga-register]] — новый SEC-D edge nlb→iam (заменяет [[../edges/nlb-to-iam-creator-tuple]])
- [[../rpc/iam-internal-iam-service]] — RegisterResource/Unregister consumed-by kacho-compute + kacho-nlb
- [[../resources/iam-service-account]] — compute/nlb-SA fga_writer relation (callee, SEC-C)

## Definition of Done (kacho-compute)

- [x] Test-first (ban #12): RED (undefined config/clients API) → GREEN продемонстрирован.
- [x] S1: outbox-миграция; intent в writer-tx (Create/Delete, 4 ресурса); прямой FGA удалён (grep-gate SEC-D-07 зелёный).
- [x] S2: register-drainer + applier; идемпотентность; IAM-down→recover (SEC-D-11 КРИТ); concurrent 2-replicas (SEC-D-13, ban #10).
- [x] S3: opt-in mTLS server+client per-edge (enable=false=insecure); fail-closed missing-CA.
- [x] go test ./... -race зелёный (repo+drainer testcontainers); go vet 0; gofmt clean; миграция up/down/up зелёная; go mod tidy.
- [~] golangci-lint: установленный 1.59.1/go1.22 vs repo go1.25 → spurious typecheck (env mismatch); golangci-lint v2.1.6 (go run) → 0 issues на изменённых пакетах. govulncheck: только stdlib go1.25.7 (fixed go1.25.8+) — не из SEC-D-кода.
- [x] Newman: `tests/newman/cases/sec-d.py` (happy SEC-D-15 + negative) → gen OK.
- [x] GitHub Issue N5 (best-effort dual-write) — `Closes` в коммите (концретный номер — оркестратор через gh).
- [x] vault trail (этот файл + edge).
- [ ] PR в kacho-compute (оркестратор), ветка `SEC-D-kacho-compute-fga-via-iam-mtls`; merge + status→done.

## Связанные тикеты

- [[EPIC-SEC-mtls-iam-authz]] (родитель) · [[SEC-A-proto-fga-proxy]] + [[SEC-B-corelib-mtls]] + [[SEC-C-iam-fga-proxy-sa-roles]] (deps)
- SEC-F (PKI/SA helm-wiring) · SEC-E (api-gateway mTLS backend)

#kac #feature #kacho-compute #kacho-vpc #security #internal
