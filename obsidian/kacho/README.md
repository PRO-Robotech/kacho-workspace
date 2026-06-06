---
title: "Kachō — vault hub"
aliases:
  - Kacho
  - Kachō
  - README
category: hub
tags:
  - kacho
  - polyrepo
  - kacho-vpc
  - grpc
  - proto
  - go
---

# Kachō — index

Облачная управляющая платформа, polyrepo на Go + React. См. [[architecture]] для cross-repo графа.

> [!tip] Быстрый lookup
> Открой [[INDEX]] — алфавитный список всех узких файлов (~140). Каждый файл 1-3KB, самодостаточен. Не загружай per-repo README, если нужна конкретная деталь.

## Quick start

- **Bases** (Obsidian native database views):
    - [[KAC/all-tickets|all KAC tickets]] (`KAC/all-tickets.base`) — filter by status/type/repo
    - [[resources/all-resources|all resources]] (`resources/all-resources.base`) — filter by domain/folder_level
    - [[rpc/all-services|all gRPC services]] (`rpc/all-services.base`) — filter by visibility/backend
    - [[packages/all-packages|all packages]] (`packages/all-packages.base`) — groupBy repo+layer
- **Canvas** (visual architecture): [[architecture.canvas]] — repo cards + build/runtime edges
- **Текстовая архитектура**: [[architecture]] (mermaid graphs)
- **Соглашения vault**: [[CLAUDE|local CLAUDE.md]]

## Recent KAC

- [[KAC/KAC-127]] — **Production-Ready Next-Gen IAM** (epic, 13 phases): Kratos+Hydra+OpenFGA+OPA+Conditions+Federation+SCIM+SAML+CAEP+SPIFFE+Audit pipeline+Chaos+Pentest+Bug bounty (in-progress: Phase 1-12 implementation complete, Phase 13 docs closeout)
- [[KAC/KAC-125]] — User per-Account + Invite (done)
- [[KAC/KAC-124]] — kacho-resource-manager deprecated → kacho-iam (done)
- [[KAC/KAC-116]] — Keto AuthZ + Kratos session + DoD #3/4/5 closeout (done)
- [[KAC/KAC-115]] — refactor: Zitadel+OpenFGA → Ory Kratos+Hydra+Keto (done)
- [[KAC/KAC-113]] — IAM E0 follow-up: sync `principal_*` (done)
- [[KAC/KAC-112]] — IAM E0 follow-up: backend для Project/User/SA/Group/Role/AccessBinding (done)
- [[KAC/KAC-111]] — Squash kacho-vpc migrations 0001..0034 → 0001 (done)
- [[KAC/KAC-105]] — IAM E0: kacho-iam skeleton + Account end-to-end (merged)
- [[KAC/KAC-104]] — Kachō IAM epic: Account/Project + Zitadel + OpenFGA REBAC (parent of KAC-127)
- [[KAC/KAC-94]] — Skill `evgeniy` 100% эталон в kacho-vpc (done)
- [[KAC/KAC-71]] — AddressPool v4/v6 split (done)
- [[KAC/KAC-56]] — RouteTable ↔ Subnet auto-association (done)
- [[KAC/KAC-55]] — NIC v4/v6 cardinality ≤ 1 (done)
- [[KAC/KAC-52]] — NIC attach race fix (done)
- [[KAC/KAC-50]] — api-gateway listener split (done)
- [[KAC/KAC-15]] — Geography moved kacho-vpc → kacho-compute (done)
- [[KAC/KAC-2]] — NetworkInterface first-class ресурс (done)

## KAC-127 — Production IAM (Phase 1-13)

Production-ready IAM в 13 фазах. Key vault entries:

- **Resources**: [[resources/iam-cluster]], [[resources/iam-organization]], [[resources/iam-federation-trust-policy]], [[resources/iam-condition]], [[resources/iam-jit-eligibility]], [[resources/iam-cluster-break-glass-grant]], [[resources/iam-caep-subscriber]], [[resources/iam-audit-signing-batch]], [[resources/iam-scim-user-mapping]], [[resources/iam-gdpr-erasure-request]], [[resources/iam-access-review]], [[resources/iam-session-revocation]], [[resources/iam-oidc-jwks-key]] + extended [[resources/iam-account|account]] / [[resources/iam-role|role]] / [[resources/iam-access-binding|access-binding]]
- **RPC**: [[rpc/iam-authorize-service]], [[rpc/iam-internal-authorize-service]], [[rpc/iam-conditions-service]], [[rpc/iam-federation-exchange-service]], [[rpc/iam-trust-policy-service]], [[rpc/iam-sa-key-service]], [[rpc/iam-scim-v2]], [[rpc/iam-saml-sp]], [[rpc/iam-caep-subscriber-service]], [[rpc/iam-opa-bundle-service]]
- **Edges**: [[edges/iam-to-hydra-admin]], [[edges/iam-to-kratos-admin]], [[edges/iam-to-opa]], [[edges/iam-to-jackson-saml]], [[edges/iam-to-scim-okta]] / [[edges/iam-to-scim-azure]] / [[edges/iam-to-scim-google]], [[edges/iam-to-spire]], [[edges/iam-to-cilium-mesh]], [[edges/iam-to-kafka-audit]] / [[edges/iam-to-clickhouse-audit]] / [[edges/iam-to-s3-audit]], [[edges/iam-to-hsm]], [[edges/iam-to-siem-datadog]] / [[edges/iam-to-siem-splunk]], [[edges/iam-caep-to-subscriber]], [[edges/api-gateway-to-iam-authorize]], [[edges/vpc-to-iam-listobjects]] / [[edges/compute-to-iam-listobjects]]
- **Packages**: [[packages/iam-handler-iamhooks]], [[packages/iam-service-federation]], [[packages/iam-service-scim]], [[packages/iam-service-caep]], [[packages/iam-service-jit]], [[packages/iam-service-breakglass]], [[packages/iam-service-access-review]], [[packages/iam-service-gdpr]], [[packages/iam-clients-jackson]], [[packages/iam-clients-hsm-pkcs11]], [[packages/iam-clients-idp-jwks-cache]], [[packages/corelib-authz-listobjects]], [[packages/api-gateway-middleware-authz]], [[packages/api-gateway-middleware-dpop]]
- **Operational**: [[runbooks/README|runbooks index]]
- **Public docs**: [[docs/user-iam-guide]], [[docs/admin-iam-guide]], [[docs/dev-iam-integration]]

## Проекты

- [[kacho-proto/README|kacho-proto]] — центральная директория `.proto` + сгенерированные Go-stubs
- [[kacho-corelib/README|kacho-corelib]] — общая Go-библиотека (ids, operations, db, outbox, …)
- [[kacho-vpc/README|kacho-vpc]] — VPC control-plane (Network/Subnet/Address/RT/SG/Gateway/PE/NIC + admin AddressPool)
- [[kacho-resource-manager/README|kacho-resource-manager]] — **removed (KAC-124)**: Organization / Cloud / Folder → Account / Project в `kacho-iam`
- [[kacho-api-gateway/README|kacho-api-gateway]] — edge (gRPC-proxy + grpc-gateway REST)
- [[kacho-deploy/README|kacho-deploy]] — Helm charts + docker-compose dev/CI стенды

## Категории детальных файлов (см. [[INDEX]])

- **Resources** (20) — поведение ресурса, FK contract, lifecycle, gotchas. Напр. [[resources/vpc-networkinterface|NetworkInterface]], [[resources/vpc-address|Address]], [[resources/operation|Operation]], [[resources/iam-account|Account (iam)]], [[resources/iam-project|Project (iam)]], [[resources/iam-access-binding|AccessBinding (iam)]].
- **RPCs** (29) — список методов + REST mapping. Напр. [[rpc/vpc-network-service|NetworkService]], [[rpc/vpc-internal-address-pool-service|InternalAddressPoolService]], [[rpc/operation-service|OperationService]], [[rpc/iam-account-service|AccountService (iam)]], [[rpc/iam-internal-iam-service|InternalIAMService]].
- **Packages** (68) — per-Go-package: exported types, imports, imported-by. Группы:
    - proto (11): [[packages/proto-vpc]], [[packages/proto-rm]], [[packages/proto-operation]], …
    - corelib (15): [[packages/corelib-operations]], [[packages/corelib-ids]], [[packages/corelib-validate]], …
    - vpc (27): [[packages/vpc-domain]], [[packages/vpc-repo-kacho-pg]], [[packages/vpc-apps-kacho-api-network]], …
    - rm (7): [[packages/rm-service]], [[packages/rm-handler]], …
    - apigw (8): [[packages/apigw-restmux]], [[packages/apigw-proxy]], …
- **Edges** (12) — cross-service gRPC runtime-ребра. Напр. [[edges/vpc-to-rm-folder-exists]], [[edges/compute-to-vpc-nic-validate]], [[edges/apigw-internal-vs-tls]], [[edges/iam-to-zitadel-oidc|iam → zitadel (planned)]], [[edges/iam-to-openfga-check|iam ↔ openfga (planned)]], [[edges/vpc-to-iam-project-exists|vpc → iam (planned)]].
- **KAC tickets** — trail работы по YouTrack-тикетам. Каждый эпик/feature/fix получает свой `KAC/KAC-<N>.md`. См. [[KAC/README]], шаблон [[KAC/_TEMPLATE]], пример [[KAC/KAC-94]].

> [!important] Обязательное правило для Claude
> (workspace `CLAUDE.md` §«Obsidian vault»): прочитай узкий файл (1-3KB) ДО кода, обнови ПОСЛЕ. Каждый KAC-тикет = заметка в `KAC/`. См. [[CLAUDE|local CLAUDE.md]] для свода.

## Документы вне scope этих 6 проектов

- `kacho-compute` (Instance/Disk/Image/…) — отдельный сервис, не индексируется в этой версии.
- `kacho-loadbalancer` — frozen в 1.0 (proto verbatim YC, backend ещё не переписан).
- `kacho-vpc-implement` — data-plane sibling kacho-vpc; spec-only, вне build-графа, control-plane его не касается.
- `kacho-ui` — Vite + React SPA.
- `kacho-test` — сводный e2e/regression стенд.

## Ключевые архитектурные правила

- Polyrepo связан `replace ../kacho-*` в `go.mod` (для dev) + `COPY ../kacho-*` в Dockerfile'ах (для CI builds).
- **Database-per-service** — нет общей БД, нет cross-DB FK.
- **Within-service refs** — обязательно DB-уровень (FK / UNIQUE / EXCLUDE / CAS), не software check-then-act.
- **Cross-service refs** — через peer-API на request-path, dangling-ref грациозен на чтении.
- **Async-всё**: каждая мутация возвращает `Operation`, клиент поллит `OperationService.Get`.
- **Skill `evgeniy`**: 48 архитектурных правил (CQRS Reader/Writer + repo-leaf entities + self-validating domain + DTO table-driven + YAML config через viper + cobra CLI + atomic outbox-in-TX + Equal-методы). См. эпик `KAC-94` в YouTrack.

## Тэги

#kacho #polyrepo #kacho-vpc #grpc #proto #go
