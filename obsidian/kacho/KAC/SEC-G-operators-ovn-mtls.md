---
title: "SEC-G: operators on mTLS (operator→{vpc,iam} client-cert) + least-priv SA + full-stack"
aliases:
  - SEC-G
  - SEC-G-operators-ovn-mtls
ticket_id: SEC-G
category: kac
status: test
type: feature
repos:
  - kacho-vpc-operator
  - kacho-deploy
prs: []
yt_url: https://prorobotech.youtrack.cloud/issue/EPIC-SEC
opened: 2026-06-11
tags:
  - kac
  - feature
  - kacho-vpc-operator
  - kacho-deploy
  - security
  - cross-service
---

# SEC-G: operators + kube-ovn on mTLS, least-priv operator SA

**Status**: test (код готов, Go + helm-assertion тесты зелёные; ждёт ревью + merge)
**Type**: feature
**Repos**: kacho-vpc-operator, kacho-deploy
**Branch**: `SEC-G-operator-mtls` (оба репо)
**Acceptance**: `docs/specs/sub-phase-SEC-G-operators-ovn-mtls-acceptance.md`
**Эпик**: [[EPIC-SEC-mtls-iam-authz]] (deps в main: [[SEC-B-corelib-mtls]], [[SEC-C-iam-fga-proxy-sa-roles]], SEC-D, SEC-F)

## Что и зачем

Финал security-эпика: перевод **operator→control-plane dial** с insecure на **mTLS
с отдельным client-cert оператора** (req #5). Оператор получает персональный
least-priv SA в kacho-iam (read-only ReBAC viewer, никаких мутаций, req #4).
`enable=false` (default) = insecure dev backward-compat (#1).

## Реализация

### kacho-vpc-operator (S1)
- `internal/upstream/client.go` — `Dial`/`DialIAM` принимают `grpcclient.TLSClient`
  (corelib SEC-B): enable=false → insecure; enable=true → mTLS (op client-cert +
  internal-CA + server_name). Handshake-mismatch → `codes.Unavailable` (§6.7).
  `principalInterceptor` сохранён поверх mTLS (инвариант I2).
- `internal/config/config.go` — per-edge `KACHO_VPCOPERATOR_{VPC,IAM}_MTLS_*`
  через `config.LoadPrefixed` (FD-3 per-edge prefixing).
- `cmd/{main,nsoperator,synconce}` — грузят config, передают per-edge TLSClient.
- `config/certmanager/certificate-webhook-internal-ca.yaml` — webhook server-cert
  через внутренний CA `kacho-internal-ca` (§4.1.6), отдельный канал от gRPC
  client-cert (#5). `config/dev/operator-mtls.yaml` — mTLS pod-spec (mount +
  per-edge env + operator least-priv SA principal).
- `go.mod` — добавлен `kacho-corelib` (replace ../kacho-corelib).

### kacho-deploy (S1/S3)
- `cert-manager-config` chart — рендерит **client-only** leaf cert для оператора
  (`vpc-operator`); шаблон теперь учитывает per-service `namespace`/`spiffeNamespace`/
  `clientOnly`. Cert в ns `kacho-vpc-operator`, URI-SAN
  `spiffe://kacho.cloud/ns/kacho-vpc-operator/sa/kacho-vpc-operator` (§4.1.4),
  отдельный secret `vpc-operator-client-tls` (#5).
- `values.mtls.yaml` — рёбра `operator_to_vpc` / `operator_to_iam`.

### kacho-iam (S2) — БЕЗ изменений
Operator-SA seed (read-only role `module.vpc_operator_sa`: `vpc.subnetses.*.list`,
`vpc.networks.*.get`, `vpc.network_interfaces.*.get`, `iam.projectses.*.list`; **нет**
fga_writer tuple; AccessBinding cluster-scope) + cert→SA mapping для SAN оператора —
**уже в main** (SEC-C migration 0009 + `authzguard/fgaproxy.go` `SANToServiceAccountID`).
Отдельная SEC-G миграция НЕ нужна (acceptance OQ#2). Тесты `fgaproxy_test.go`
(SAN→SA, unknown-SAN→DENY, no-relation→DENY) + `seed_module_sa_identity_integration_test.go`
покрывают S2 DoD в main.

## Тесты (TDD RED→GREEN)

- `kacho-vpc-operator/internal/upstream/client_mtls_test.go` (SEC-G-01/02/03/04):
  mTLS handshake OK с op client-cert + principal over mTLS; enable=true vs insecure
  backend → Unavailable; enable=false → insecure path; DialIAM mirror.
- `kacho-vpc-operator/internal/config/config_test.go` (SEC-G-01/03/04): per-edge env
  prefixing, default insecure, независимые vpc/iam рёбра.
- `kacho-deploy/tests/helm/operator-mtls-test.sh` (SEC-G-01/12): operator client-cert
  рендерится, internal-CA issuer, own namespace, SPIRE SAN, client-only, distinct id,
  absent при internalCA off. + расширены SEC-F `cert-manager-internal-ca` (6th id) и
  `mtls-values-profile` (operator edges).

## Затронутые сущности vault

- [[../edges/vpc-operator-to-vpc-mtls]] — новая записка: operator→{vpc,iam} mTLS + least-priv SA
- [[../edges/vpc-operator-to-kubeovn]] — mTLS-граница + webhook internal-CA (History)
- [[../resources/iam-serviceaccount]] / [[../rpc/iam-service-account-service]] — operator SA seed (SEC-C, ссылка)
- `.claude/rules/polyrepo.md` — operator→{vpc,iam} mTLS runtime-edges (S4-03)

## Definition of Done

- [x] S1: operator→vpc/iam dial на mTLS с отдельным op client-cert; per-edge enable; enable=false=insecure (#1).
- [x] S2: operator-SA least-priv ReBAC viewer + cert→SA mapping — в main (SEC-C); SEC-G миграции нет (OQ#2).
- [x] S3: webhook-cert через internal-CA overlay (§4.1.6); operator client-cert mount + per-edge env (config/dev/operator-mtls.yaml); helm-assertion зелёный.
- [x] S4: polyrepo.md operator→{vpc,iam} mTLS-рёбра (workspace).
- [x] Публичные контракты не тронуты (#8); JWT не тронут (#7).
- [x] go build/test ./... -race (operator) зелёный; gofmt/vet clean. helm lint/template + 5 helm-тестов зелёные.
- [~] golangci-lint: локальный tool/go-version mismatch (как в SEC-E) → go vet authoritative-зелёный.
- [ ] PR в kacho-vpc-operator + kacho-deploy (оркестратор); merge + status→done.
- [ ] e2e mTLS-профиль на стенде (S3-02/03/04) — после merge на kind.

## Связанные тикеты

- [[EPIC-SEC-mtls-iam-authz]] (родитель) · [[SEC-B-corelib-mtls]] · [[SEC-C-iam-fga-proxy-sa-roles]] · [[SEC-D-services-fga-via-iam-mtls]] · [[SEC-E-gateway-mtls]]

#kac #feature #kacho-vpc-operator #kacho-deploy #security #cross-service
