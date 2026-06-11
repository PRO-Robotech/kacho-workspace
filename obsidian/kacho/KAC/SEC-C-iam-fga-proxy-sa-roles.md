---
title: "SEC-C: IAM FGA-proxy (Register/UnregisterResource) + least-priv SA-roles (ReBAC) + cert→SA"
aliases:
  - SEC-C
  - SEC-C-iam-fga-proxy-sa-roles
ticket_id: SEC-C
category: kac
status: test
type: feature
repos:
  - kacho-iam
prs: []
yt_url: https://prorobotech.youtrack.cloud/issue/EPIC-SEC
opened: 2026-06-11
tags:
  - kac
  - feature
  - kacho-iam
  - security
  - internal
---

# SEC-C: IAM FGA-proxy + least-priv SA-identities (ReBAC) + cert→SA

**Status**: test (код готов, тесты зелёные, ждёт ревью + merge оркестратором)
**Type**: feature
**Repos**: kacho-iam
**Branch**: `SEC-C-iam-fga-proxy-sa-roles`
**Acceptance**: `docs/specs/sub-phase-SEC-C-iam-fga-proxy-sa-roles-acceptance.md`
**Эпик**: [[EPIC-SEC-mtls-iam-authz]] (зависит от [[SEC-A-proto-fga-proxy]] + [[SEC-B-corelib-mtls]], волна 1 в main)

## Что и зачем

Серверная (callee) половина «FGA за IAM» (эпик #6) + server-side энфорсмент least-priv
service-identity в модели ReBAC (эпик §4.1 п.1/п.2). Реализует Internal RPC
`RegisterResource`/`UnregisterResource` (owner-tuple через `kacho_iam.fga_outbox`+drainer,
идемпотентно), ReBAC authz-гейт `fga_writer@iam_fgaproxy:system`, cert-SAN→SA mapping
(SPIRE-формат), и seed-миграцию least-priv SA-identity 5 модулей.

## Реализация

- `internal/apps/kacho/api/internal_iam/register_resource.go` — `RegisterResourceUseCase`
  (валидация tuple-грамматики → emit в `fga_outbox` в одной writer-tx через
  `FGAOutboxEmitter`+`TxBeginner`; sync per SEC-A proto, пустой response). Порты в `handler.go`.
- `internal/apps/kacho/api/internal_iam/handler.go` — `RegisterResource`/`UnregisterResource`
  + `WithFGAProxy(registrar, gate)`; authz-гейт перед эмитом.
- `internal/authzguard/fgaproxy.go` — `FGAProxyGate` (cert-SAN→`sva`-id → ReBAC `Check fga_writer`;
  dev insecure→allow / prod fail-closed) + `SANToServiceAccountID` + `ServiceAccountIDForService`
  (детерминированный `'sva'||substr(md5('kacho-<svc>'),1,17)`, OQ-C-5). Reuse существующего
  `RelationChecker` (метод `Check`, satisfied by OpenFGA client).
- `internal/migrations/0009_sec_c_module_sa_least_priv.sql` — система-account+user anchor + 5
  module-SA + 5 backing 4-сегментных ролей (из `permission_catalog.json`) + 5 cluster-scope
  AccessBinding + 3 fga_writer relation-tuples (vpc/compute/nlb; operator/api-gateway — без).
  Идемпотентно (`ON CONFLICT DO NOTHING`); goose up/down/up зелёный.
- `internal/repo/kacho/pg/seed_module_sa_identity.go` — `SeedModuleSAIdentity` (идемпотентный
  re-apply, single-source-of-truth для HA cold-start + B-06 тест).
- `cmd/kacho-iam/serve.go` — internal listener +`UnaryCertIdentityExtract` (SEC-B) перед principal.
- `cmd/kacho-iam/wiring.go` — composition: register-UC + ReBAC gate (prod-mode из AuthN config).

## Затронутые сущности vault

- [[../rpc/iam-internal-iam-service]] — RegisterResource/Unregister handler реализован (SEC-C)
- [[../resources/iam-service-account]] — module-SA identity + ReBAC relation-tuples + backing 4-сегментные роли + SAN-mapping
- [[../edges/vpc-to-iam-fgaproxy]] / [[../edges/compute-to-iam-fgaproxy]] — callee-сторона готова (consumer — SEC-D)
- [[../packages/corelib-grpcsrv]] — потребитель cert-identity extractor (SEC-B)

## Definition of Done

- [x] Test-first (ban #12): RED (compile-fail / unwired RPC) → GREEN продемонстрирован.
- [x] RegisterResource/UnregisterResource: outbox-в-tx, идемпотентность как контракт (A-01..A-04).
- [x] Concurrency A-06 (ban #10): 8 конкурентных Register → все OK, at-least-once, `-race` чисто.
- [x] ReBAC gate (B-07/B-08/B-09) + cert-SAN→SA (C-01..C-05) — unit (verified/unverified/malformed/unknown).
- [x] Seed (B-01..B-06): 5 SA + byte-for-byte 4-сегментные наборы + fga_writer tuples + binding idempotency.
- [x] A-07/A-08 (fail-safe 5xx-retry / poison) — наследуется из W1.1 drainer (`fga_applier_*test.go`), AS-IS.
- [x] Backward-compat (D-01/D-02): dev insecure→allow, prod→fail-closed.
- [x] go test ./... -race зелёный; go vet 0; gofmt clean; миграция up/down/up зелёная.
- [~] golangci-lint: tool-version mismatch (1.59.1/go1.22 vs repo go1.25) → spurious typecheck across ВСЕХ файлов; go vet authoritative-зелёный. govulncheck: только stdlib (fixed go1.25.8) + pre-existing imports — не из SEC-C.
- [x] Newman: `tests/newman/cases/sec-c-fga-proxy.py` (6 кейсов, happy+negative+internal-only) → gen OK.
- [x] vault trail (этот файл + rpc + resources + edges).
- [ ] PR в kacho-iam (оркестратор), ветка `SEC-C-iam-fga-proxy-sa-roles`; merge + status→done.

## Связанные тикеты

- [[EPIC-SEC-mtls-iam-authz]] (родитель) · [[SEC-A-proto-fga-proxy]] + [[SEC-B-corelib-mtls]] (deps, волна 1)
- SEC-D (consumer-сторона: vpc/compute/nlb outbox→IAM.RegisterResource) · SEC-F (PKI/SA helm-wiring)

#kac #feature #kacho-iam #security #internal
