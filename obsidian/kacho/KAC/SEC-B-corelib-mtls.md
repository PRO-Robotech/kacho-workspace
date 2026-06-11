---
title: "SEC-B: corelib mTLS transport (grpcsrv/grpcclient + identity-extractor)"
aliases:
  - SEC-B
  - SEC-B-corelib-mtls
ticket_id: SEC-B
category: kac
status: test
type: feature
repos:
  - kacho-corelib
prs: []
yt_url: https://prorobotech.youtrack.cloud/issue/EPIC-SEC
opened: 2026-06-11
tags:
  - kac
  - feature
  - kacho-corelib
  - security
  - grpc
---

# SEC-B: corelib mTLS transport (grpcsrv/grpcclient + identity-extractor)

**Status**: test (код готов, тесты зелёные, ждёт ревью + merge оркестратором)
**Type**: feature
**Repos**: kacho-corelib
**Branch**: `SEC-B-corelib-mtls`
**Acceptance**: `docs/specs/sub-phase-SEC-B-corelib-mtls-acceptance.md` (APPROVED, эпик acceptance-фаза 7/7)
**Эпик**: [[EPIC-SEC-mtls-iam-authz]]

## Что и зачем

Транспортная основа mTLS для всех kacho-сервисов как **opt-in** (эпик #1/#2/#5). corelib
получает TLS server/client-creds + config-структуры + cert-identity extractor + инвариант
доверия principal⟺mTLS. `enable=false` повсеместно ⇒ текущее insecure-поведение byte-for-byte;
SEC-B мёржится в `main`, ничего не включая. Реальные рёбра включаются в SEC-D/E/G; PKI — SEC-F.

## Реализация

- `grpcsrv/tls.go` — `TLSServer{enable,cert_file,key_file,client_ca_files}` + `TLSServerCreds`
  (server-cert + client-CA + `RequireAndVerifyClientCert`, FD-2; misconfig→error, FD-6).
- `grpcclient/tls.go` — `TLSClient{enable,cert_file,key_file,ca_files,server_name}` + `TLSClientCreds`
  (client-cert + server-CA + server_name-SAN-check; пустая cert/key пара ⇒ one-way TLS для
  require-and-verify-reject теста; misconfig→error).
- `grpcsrv/cert_identity.go` — `CertIdentity` (verbatim opaque `spiffe://kacho.cloud/...` из verified
  client-cert, FD-5), `WithCertIdentity`/`CertIdentityFromContext`, `UnaryCertIdentityExtract`,
  `UnaryTrustedPrincipalExtract`/`TrustedPrincipalFromContext` (инвариант FD-4).
- `grpcsrv/principal_extract.go` — выделен `principalFromIncomingMetadata` (reuse, без дублирования).

## Затронутые сущности vault

- [[../packages/corelib-grpcsrv]] — +TLS server-creds, +cert-identity extractor + trust-invariant
- [[../packages/corelib-grpcclient]] — создан: +TLS client-creds (+ keepalive)
- [[../packages/corelib-config]] — +TLSServer/TLSClient структуры
- [[../packages/corelib-auth]] — помечен инвариант principal⟺mTLS (FD-4)

Новых edges SEC-B не вводит (рёбра включаются в SEC-D/E/G).

## Acceptance / Definition of Done

- [x] Test-first (ban #12): RED→GREEN показан (extractor undefined→OK; config-load tag fail→OK;
      handshake; require-client-cert; SEC-B-19 guard RED при bare `credentials.NewTLS`).
- [x] TLSServer/TLSClient определены и загружаемы config-механизмом (per-instance, FD-3).
- [x] Helper'ы TLSServerCreds/TLSClientCreds: enable=false→insecure (FD-1); enable=true→mTLS (FD-2);
      misconfig→error (FD-6); единая точка истины (FD-7), покрыты unit (SEC-B-18).
- [x] cert-identity: SAN→string, no-SAN→empty, multi-SAN детерминизм, opaque без resolve (FD-5).
- [x] Инвариант доверия (FD-4): principal ⟺ verified client-cert; insecure dev-compat; оба логируются.
- [x] Backward-compat: оба enable=false ⇒ insecure byte-for-byte (SEC-B-04); существующие тесты зелёные.
- [x] fail-closed: handshake-fail/mismatch/misconfig → Unavailable/error, нет silent-fallback.
- [x] Анти-регресс guard SEC-B-19 зелёный (RED→GREEN продемонстрирован).
- [x] Нет TODO/FIXME/skip в diff (ban #11/#13).
- [x] `go test ./... -race` зелёный; `golangci-lint run` (v2.1.6/go1.25) 0 issues.
      govulncheck: 19 findings — все stdlib toolchain (go1.25.1, fixed 1.25.2/.3), не из SEC-B
      (те же GO-2025-4007/4008/4009 присутствуют в pre-existing `db` пакете) → toolchain-bump вне scope.
- [x] vault обновлён (этот trail + 4 packages-файла).
- [ ] PR в kacho-corelib (оркестратор), ветка `SEC-B-corelib-mtls`; downstream не трогаются.
- [ ] merge в main + status→done.

## Связанные тикеты

- [[EPIC-SEC-mtls-iam-authz]] (родитель)
- SEC-A (kacho-proto, параллельно волна 1) · SEC-C (kacho-iam, зависит от A+B) · SEC-D/E (зависят от B)

#kac #feature #kacho-corelib #security #grpc
