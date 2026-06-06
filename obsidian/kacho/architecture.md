---
title: "Архитектура — cross-repo граф"
aliases:
  - architecture
category: hub
tags:
  - architecture
  - dependencies
  - polyrepo
---

# Архитектура — cross-repo граф

## Build-зависимости (Go-replace + Dockerfile COPY)

```mermaid
graph TD
    proto[kacho-proto<br/>«центр всех .proto»]
    corelib[kacho-corelib<br/>ids/operations/db/outbox/authz-listobjects/...]
    iam[kacho-iam<br/>Account/Project/User/SA/<br/>Group/Role/AccessBinding<br/>+ Cluster/Org/Federation<br/>+ JIT/BreakGlass/CAEP/SCIM/<br/>SAML/GDPR/AccessReviews]
    vpc[kacho-vpc]
    compute[kacho-compute]
    nlb[kacho-loadbalancer]
    apigw[kacho-api-gateway<br/>+DPoP/JWT/mTLS/step-up<br/>+per-RPC authz Check]
    deploy[kacho-deploy]
    ui[kacho-ui]
    test[kacho-test]

    proto --> corelib
    corelib --> iam
    corelib --> vpc
    corelib --> compute
    corelib --> nlb
    corelib --> apigw
    proto --> iam
    proto --> vpc
    proto --> compute
    proto --> nlb
    proto --> apigw

    iam --> deploy
    vpc --> deploy
    compute --> deploy
    apigw --> deploy
    ui --> deploy

    deploy -.runtime.- apigw
    apigw -.runtime.- ui
    test -.runtime.- apigw
```

Источник истины — `replace github.com/PRO-Robotech/...` в `*/go.mod` + `COPY ../kacho-*` в `*/Dockerfile`.

> [!note] KAC-124
> `kacho-resource-manager` упразднён в KAC-124 (E5 sub-phase 2.0). Organization/Cloud/Folder заменены Account/Project в `kacho-iam`.

## Runtime cross-domain edges (gRPC service → service)

### Backbone — Phase 1-2 (KAC-104, KAC-127 Phase 1-2)

```mermaid
graph LR
    apigw[api-gateway:8080/443] --> iam[iam:9090/9091/9092/9093/9094]
    apigw --> vpc[vpc:9090/9091]
    apigw --> compute[compute:9090/9091]
    vpc -.zone validate.-> compute
    compute -.NIC validate + IPAM.-> vpc
    vpc -.project exists.-> iam
    compute -.project exists.-> iam
```

### Phase 2 added (AuthN core, KAC-127 Phase 2 implemented)

```mermaid
graph LR
    apigw -.DPoP/JWT verify.-> jwks[(JWKS endpoint)]
    iam -.token_hook/refresh_hook.-> hydra[Ory Hydra Admin:4445]
    iam -.identity/sessions.-> kratos[Ory Kratos Admin:4434]
    ui -.WebAuthn enroll.-> kratos
    apigw -.BCL propagate.-> iam
```

### Phase 3 added (AuthZ core)

```mermaid
graph LR
    apigw -.per-RPC Check.-> iam-authorize[iam.AuthorizeService.Check]
    iam-authorize -.REBAC tuple Check.-> openfga[OpenFGA]
    iam-authorize -.cluster-deny gate.-> opa[OPA sidecar :8181]
    opa -.bundle poll.-> iam-bundle[iam.OPABundleService]
```

### Phase 4 added (List filtering)

```mermaid
graph LR
    vpc-list[vpc List handler] -.ListObjects.-> iam-authorize
    compute-list[compute List handler] -.ListObjects.-> iam-authorize
```

### Phase 5 added (Workload Identity Federation)

```mermaid
graph LR
    github[GitHub Actions / AWS / GCP / GitLab CI / ...] -.RFC 8693 token exchange.-> iam-fed[iam.FederationExchangeService]
    iam-fed -.JWKS fetch (cached).-> idp[(IdP JWKS)]
    iam -.SA OAuth client CRUD.-> hydra
```

### Phase 6 added (Enterprise SSO)

```mermaid
graph LR
    okta[Okta / Entra / Google] -.SCIM 2.0.-> iam-scim[iam.SCIM endpoints :9093]
    iam-scim -.identity sync.-> kratos
    saml-idp[SAML 2.0 IdP] -.SP-init/IdP-init.-> iam-saml[iam.SAML endpoints :9094]
    iam-saml -.bridge.-> jackson[Boxyhq Jackson]
    jackson -.session.-> kratos
```

### Phase 8 added (CAEP push)

```mermaid
graph LR
    iam -.outbox.-> caep-drainer[iam CAEP drainer]
    caep-drainer -.SET signing.-> hsm[(HSM PKCS#11)]
    caep-drainer -.signed SET POST.-> external-rs[external Resource Servers<br/>Salesforce / Slack / M365]
```

### Phase 9 added (Audit pipeline)

```mermaid
graph LR
    iam -.audit outbox.-> kafka[(Kafka kacho.iam.audit)]
    kafka -.Kafka Engine.-> ch[ClickHouse]
    kafka -.S3 sink.-> s3[S3 + Glacier 7y WORM]
    kafka -.SIEM forwarder.-> dd[Datadog SIEM]
    kafka -.SIEM forwarder.-> splunk[Splunk HEC]
    iam -.Merkle batch signing.-> hsm
```

### Phase 10 added (SPIFFE + Cilium)

```mermaid
graph LR
    all-pods[все kacho pods] -.SVID fetch.-> spire[SPIRE Agent unix:///]
    spire -.attest.-> spire-server[SPIRE Server HA]
    all-pods -.mTLS transparently.-> cilium[Cilium mesh<br/>eBPF + SPIFFE]
```

Циклы запрещены (workspace `CLAUDE.md` §«Кросс-доменные ссылки на ресурсы»).
`kacho-iam` — leaf-owner (Account/Project): в него только звонят.

## Порядок merge'а для cross-repo фичи

Топологическая сортировка build-графа:
1. `kacho-proto` — proto changes + регенерация Go-stubs (commit `gen/`).
2. `kacho-corelib` — общие пакеты (если меняются).
3. Сервисы (`kacho-iam` / `kacho-vpc` / `kacho-compute` / `kacho-loadbalancer`) — в любом порядке между собой (DB-per-service).
4. `kacho-api-gateway` — регистрация новых RPC.
5. `kacho-deploy` — helm/compose tweaks.
6. `kacho-workspace` — docs/specs.

Пока вышестоящие изменения не в `main` — нижестоящий CI **временно пиннит siblings** к feature-веткам (`ref:`-строки в `.github/workflows/ci.yaml`).

## Tracking кросс-репо эпика

Через [[../docs/specs/|spec docs]] + tracking-issue в `PRO-Robotech/kacho-workspace` (метка `epic`). Per-repo issue/PR помечает `Blocked by PRO-Robotech/<repo>#<n>`.

KAC-127 — производный эпик 13 фаз, ссылается на [[KAC/KAC-127]].

## См. также

- [[README|hub]]
- [[KAC/KAC-127|KAC-127 — Production IAM (epic, 13 phases)]]
- [[kacho-vpc/README]] — most active service
- [[kacho-deploy/README]] — orchestration
- [[runbooks/README]] — operational runbooks

#architecture #dependencies #polyrepo
