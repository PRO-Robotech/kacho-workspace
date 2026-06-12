---
title: "SEC-E: api-gateway backend-dial mTLS (per-edge), JWT/principal/Check preserved"
aliases:
  - SEC-E
  - SEC-E-gateway-mtls
ticket_id: SEC-E
category: kac
status: test
type: feature
repos:
  - kacho-api-gateway
prs: []
yt_url: https://prorobotech.youtrack.cloud/issue/EPIC-SEC
opened: 2026-06-11
tags:
  - kac
  - feature
  - kacho-api-gateway
  - security
  - cross-service
---

# SEC-E: api-gateway backend-dial mTLS (per-edge)

**Status**: test (код готов, Go-тесты зелёные, ждёт ревью + merge оркестратором)
**Type**: feature
**Repos**: kacho-api-gateway
**Branch**: `SEC-E-gateway-mtls`
**Acceptance**: `docs/specs/sub-phase-SEC-E-gateway-mtls-acceptance.md` (APPROVED в эпике §4.1 — «APPROVED B, D, E»)
**Эпик**: [[EPIC-SEC-mtls-iam-authz]] (зависит от [[SEC-B-corelib-mtls]] + [[SEC-C-iam-fga-proxy-sa-roles]], волна 1-2 в main)

## Что и зачем

Клиентская (caller) сторона mTLS на исходящем backend-dial api-gateway (эпик req #3,
decision §6.4). Все 4 production dial-площадки переведены на **per-edge** transport-creds
(mTLS client-cert идентичности «api-gateway» через corelib `grpcclient.TLSClientCreds`,
SEC-B) под независимыми флагами `KACHO_API_GATEWAY_MTLS_<EDGE>_ENABLE`. `enable=false`
(default) = текущий insecure (dev backward-compat). JWT-верификация (Hydra/dev HMAC),
principal-propagation (`x-kacho-principal-*`) и per-RPC `InternalIAMService.Check` —
**не тронуты** (#7), работают поверх mTLS (epic invariant I2: cert=модуль ⊥ principal=пользователь).

## Реализация

- `internal/config/config.go` — per-edge mTLS env-контракт (`MTLS_CLIENT_CERT_FILE`/`_KEY_FILE`/
  `_CA_FILE` shared + `MTLS_<EDGE>_ENABLE` + `MTLS_<EDGE>_SERVER_NAME`) + `EdgeTLSClient(edge,addr)`
  (собирает `grpcclient.TLSClient`; fail-fast при enable без cert-материала, SEC-E-03; server-name
  derive из dial-host или override).
- `cmd/api-gateway/mtls_config.go` — `backendEdge(key)` (vpc/vpcInternal→vpc, …, loadbalancer→nlb),
  `buildBackendDialCreds` (per-edge creds-map, fail-fast), `loopbackDialCreds` (всегда insecure,
  SEC-E-07), `iamEdgeDialCreds` (для iam-subject + iam-authorize), `dialBackends` (composition-root:
  открывает ClientConn per-edge + opsLoopback insecure, keepalive+round-robin сохранены).
- `cmd/api-gateway/main.go` — backend-цикл → `dialBackends`; iam-subject + iam-authorize → iam-edge creds.
- `internal/clients/iam_subject_client.go` / `iam_authorize_client.go` — добавлен инжектируемый
  `transportCreds grpc.DialOption` (nil → insecure default, backward-compat).

## Тесты (TDD RED→GREEN)

- `internal/config/mtls_test.go` — SEC-E-01/02/03/03b/09 + server-name override + unknown-edge.
- `cmd/api-gateway/mtls_config_test.go` — per-edge creds-selection (SEC-E-01/02/03/09).
- `cmd/api-gateway/mtls_dial_bufconn_test.go` — in-memory mTLS handshake: principal+peer-cert over
  mTLS (SEC-E-05), mTLS-client vs insecure-server fail-closed (SEC-E-09/§3.12), untrusted-CA reject
  (SEC-E-11), opsLoopback insecure (SEC-E-07).
- `cmd/api-gateway/mtls_wiring_test.go` — `dialBackends` default-insecure / fail-fast / mixed-profile.
- `internal/clients/iam_mtls_creds_test.go` — iam-subject + iam-authorize принимают transport-creds.
- `tests/newman/cases/sec_e_gateway_mtls.py` — `SEC-E-GATEWAY-MTLS-A` (happy Create over mTLS) +
  `-NEG-A` (cross-tenant 403 поверх mTLS) + `-BAN6-ADDRESSPOOL` (Internal не на external).

## Затронутые сущности vault

- [[../edges/api-gateway-to-iam-authorize]] — backend-dial → mTLS client-cert под MTLS_IAM_ENABLE (History)
- [[../edges/api-gateway-to-iam-subject-change]] — то же ребро gateway→iam, тот же флаг (History)
- [[../packages/api-gateway-backend-dial-mtls]] — новая записка: per-edge creds-выбор
- [[../packages/corelib-grpcclient]] — потребитель `TLSClientCreds` (SEC-B)

## Definition of Done

- [x] Конфиг: per-edge env (§1.1), default выкл/пусто; enable без cert → fail-fast (SEC-E-03).
- [x] Dial: per-edge creds (vpc/compute/iam/nlb + internal-порты); iam-subject+authorize под MTLS_IAM_ENABLE; opsLoopback всегда insecure.
- [x] JWT/principal/Check не изменены (#7): `internal/middleware/*`, `internal/allowlist/*` не тронуты.
- [x] TDD RED→GREEN: clients-creds seam + dialBackends wiring — RED показан до кода, GREEN после.
- [x] Integration (bufconn + ephemeral cert/CA): principal-over-mTLS, fail-closed mismatch, untrusted-CA reject, loopback insecure.
- [x] Newman: happy + negative + ban#6 control → `gen.py` OK.
- [x] go test ./... -race зелёный; go build ./...; go vet 0; gofmt clean.
- [~] golangci-lint: tool-version mismatch (1.59.1/go1.22 vs repo go1.25) → spurious typecheck; go vet authoritative-зелёный. govulncheck: только stdlib (crypto/x509 fixed go1.25.3) + pre-existing imports — не из SEC-E.
- [ ] e2e mTLS-профиль (заказчик §7) — после merge SEC-C/SEC-D server-side на стенд (§2.2 edge enable когда обе стороны включены).
- [x] vault trail (этот файл + edges History + новая packages-записка).
- [ ] PR в kacho-api-gateway (оркестратор); merge + status→done.

## Связанные тикеты

- [[EPIC-SEC-mtls-iam-authz]] (родитель) · [[SEC-B-corelib-mtls]] + [[SEC-C-iam-fga-proxy-sa-roles]] (deps, волна 1-2)
- SEC-D (backend server-side mTLS vpc/compute/nlb — позволяет включить эти рёбра e2e) · SEC-F (PKI/cert-manager helm-wiring)

#kac #feature #kacho-api-gateway #security #cross-service
