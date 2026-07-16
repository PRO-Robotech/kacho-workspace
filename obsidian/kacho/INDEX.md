---
title: INDEX
aliases:
  - Index
category: hub
tags:
  - index
---

# INDEX

Alphabetical index всех узких файлов. Использовать для quick-lookup — открой нужный, не загружай README/architecture.

## Bases (table views)

- [[KAC/all-tickets|KAC/all-tickets.base]] — KAC tickets table
- [[resources/all-resources|resources/all-resources.base]] — resources table
- [[rpc/all-services|rpc/all-services.base]] — gRPC services table
- [[packages/all-packages|packages/all-packages.base]] — packages table

## Canvas

- [[architecture.canvas]] — visual architecture (repo cards + build/runtime edges)

## Hub / catalog

- [[README]] — categorical hub
- [[architecture]] — text architecture (Mermaid graphs Phase 1-12)
- [[runbooks/README]] — operational runbooks index

## Resources (~35)

### Core (legacy)

- [[resources/operation|Operation (LRO envelope)]]
- [[resources/rm-cloud|Cloud (rm, deprecated)]]
- [[resources/rm-folder|Folder (rm, deprecated)]]
- [[resources/rm-organization|Organization (om, deprecated)]]

### kacho-iam (Phase 1 + KAC-127)

- [[resources/iam-account|Account]]
- [[resources/iam-access-binding|AccessBinding]] (extended Phase 1: status/condition/expires_at)
- [[resources/iam-access-binding-condition|AccessBindingCondition (per-binding)]]
- [[resources/iam-access-review|AccessReview]]
- [[resources/iam-access-review-item|AccessReviewItem]]
- [[resources/iam-audit-signing-batch|AuditSigningBatch]]
- [[resources/iam-caep-subscriber|CAEPSubscriber]]
- [[resources/iam-cluster|Cluster (singleton)]]
- [[resources/iam-cluster-admin-grant|ClusterAdminGrant]]
- [[resources/iam-cluster-break-glass-grant|ClusterBreakGlassGrant]]
- [[resources/iam-condition|Condition (reusable CEL)]]
- [[resources/iam-federation-trust-policy|FederationTrustPolicy]]
- [[resources/iam-gdpr-erasure-request|GDPRErasureRequest]]
- [[resources/iam-group|Group]] (extended)
- [[resources/iam-jit-eligibility|JITEligibility]]
- [[resources/iam-jwks-key|JWKSKey alias]]
- [[resources/iam-oidc-jwks-key|OIDCJwksKey]]
- [[resources/iam-organization|Organization (B2B tier)]]
- [[resources/iam-project|Project]]
- [[resources/iam-role|Role]] (extended Phase 1: multi-scope)
- [[resources/iam-scim-user-mapping|SCIMUserMapping]]
- [[resources/iam-service-account|ServiceAccount]] (extended)
- [[resources/iam-service-account-oauth-client|SAOAuthClient]]
- [[resources/iam-session-revocation|SessionRevocation]]
- [[resources/iam-user|User]] (extended SCIM/GDPR)

### kacho-vpc

- [[resources/vpc-address|Address]]
- [[resources/vpc-addresspool|AddressPool (kacho-only)]]
- [[resources/vpc-gateway|Gateway]]
- [[resources/vpc-network|Network]]
- [[resources/vpc-networkinterface|NetworkInterface (KAC-2)]]
- [[resources/vpc-privateendpoint|PrivateEndpoint]]
- [[resources/vpc-routetable|RouteTable]]
- [[resources/vpc-securitygroup|SecurityGroup]]
- [[resources/vpc-subnet|Subnet]]

### kacho-geo (эпик #82)

- [[resources/geo-region|Region (geo)]]
- [[resources/geo-zone|Zone (geo)]]

## RPCs (~40)

### kacho-iam (KAC-127)

- [[rpc/iam-access-binding-service|AccessBindingService]]
- [[rpc/iam-account-service|AccountService (KAC-105)]]
- [[rpc/iam-authorize-service|AuthorizeService (Phase 3)]]
- [[rpc/iam-caep-subscriber-service|CAEPSubscriberService (Phase 8, internal)]]
- [[rpc/iam-conditions-service|ConditionsService (Phase 3)]]
- [[rpc/iam-federation-exchange-service|FederationExchangeService (Phase 5)]]
- [[rpc/iam-federation-service|FederationService (planned, schema-only Phase 1)]]
- [[rpc/iam-group-service|GroupService]]
- [[rpc/iam-internal-authorize-service|InternalAuthorizeService (Phase 3, internal)]]
- [[rpc/iam-internal-cluster-service|InternalClusterService (Phase 1, internal)]]
- [[rpc/iam-internal-iam-service|InternalIAMService (legacy)]]
- [[rpc/iam-internal-user-service|InternalUserService (legacy)]]
- [[rpc/iam-opa-bundle-service|OPABundleService (Phase 3, internal)]]
- [[rpc/iam-organization-service|OrganizationService (Phase 1)]]
- [[rpc/iam-project-service|ProjectService]]
- [[rpc/iam-role-service|RoleService]]
- [[rpc/iam-sa-key-service|SAKeyService (Phase 5)]]
- [[rpc/iam-saml-sp|SAML SP endpoints (Phase 6, REST :9094)]]
- [[rpc/iam-scim-v2|SCIM 2.0 (Phase 6, REST :9093)]]
- [[rpc/iam-service-account-service|ServiceAccountService]]
- [[rpc/iam-trust-policy-service|TrustPolicyService (Phase 5, internal)]]
- [[rpc/iam-user-service|UserService]]

### Legacy / deprecated

- [[rpc/operation-service|OperationService]]
- [[rpc/om-organization-service|OrganizationService (om alias)]]
- [[rpc/om-user-account-service|UserAccountService]]
- [[rpc/rm-cloud-service|CloudService (rm, deprecated)]]
- [[rpc/rm-folder-service|FolderService (rm, deprecated)]]
- [[rpc/rm-organization-service|OrganizationService (rm, deprecated)]]

### kacho-vpc

- [[rpc/vpc-address-service|AddressService]]
- [[rpc/vpc-gateway-service|GatewayService]]
- [[rpc/vpc-internal-address-pool-service|InternalAddressPoolService]]
- [[rpc/vpc-internal-address-service|InternalAddressService]]
- [[rpc/vpc-internal-cloud-service|InternalCloudService (removed, KAC-266)]]
- [[rpc/vpc-internal-network-service|InternalNetworkService]]
- [[rpc/vpc-internal-watch-service|InternalWatchService (deprecated)]]
- [[rpc/vpc-network-service|NetworkService]]
- [[rpc/vpc-networkinterface-service|NetworkInterfaceService]]
- [[rpc/vpc-privateendpoint-service|PrivateEndpointService]]
- [[rpc/vpc-routetable-service|RouteTableService]]
- [[rpc/vpc-securitygroup-service|SecurityGroupService]]
- [[rpc/vpc-subnet-service|SubnetService]]

### kacho-geo (эпик #82)

- [[rpc/geo-region-service|RegionService + InternalRegionService]]
- [[rpc/geo-zone-service|ZoneService + InternalZoneService]]

## Packages — монорепа (2)

- [[packages/kacho-monorepo|kacho — монорепа (замещает polyrepo)]]
- [[packages/kacho-ci-runners|CI: ранеры и раскладка job'ов (beget-runner / ubuntu-latest)]]

## Packages — proto (11)

- [[packages/proto-access|cloud/access — IAM shared]]
- [[packages/proto-api|cloud/api — legacy]]
- [[packages/proto-compute|cloud/compute/v1]]
- [[packages/proto-geo|cloud/geo/v1 (эпик #82)]]
- [[packages/proto-loadbalancer|cloud/nlb proto (legacy 1.0, frozen) — current repo kacho-nlb]]
- [[packages/proto-maintenance|cloud/maintenance/v2]]
- [[packages/proto-operation|cloud/operation — LRO envelope]]
- [[packages/proto-organizationmanager|cloud/organizationmanager/v1]]
- [[packages/proto-reference|cloud/reference]]
- [[packages/proto-rm|cloud/resourcemanager/v1 (deprecated)]]
- [[packages/proto-root|proto root + google + common]]
- [[packages/proto-vpc|cloud/vpc/v1]]

## Packages — kacho-corelib (16)

- [[packages/corelib-authz|authz]]
- [[packages/corelib-authz-listobjects|authz/listobjects (Phase 4)]]
- [[packages/corelib-backoff|backoff]]
- [[packages/corelib-baggage|baggage]]
- [[packages/corelib-config|config]]
- [[packages/corelib-db|db]]
- [[packages/corelib-errors|errors]]
- [[packages/corelib-filter|filter]]
- [[packages/corelib-grpcsrv|grpcsrv]]
- [[packages/corelib-ids|ids]]
- [[packages/corelib-observability|observability]]
- [[packages/corelib-operations|operations (LRO)]]
- [[packages/corelib-outbox|outbox]]
- [[packages/corelib-retry|retry]]
- [[packages/corelib-selector|selector]]
- [[packages/corelib-shutdown|shutdown]]
- [[packages/corelib-validate|validate]]

## Packages — kacho-iam (KAC-127, ~15)

- [[packages/iam-clients-hsm-pkcs11|clients/hsm_pkcs11 (Phase 8/9)]]
- [[packages/iam-clients-idp-jwks-cache|clients/idp_jwks_cache (Phase 5)]]
- [[packages/iam-clients-jackson|clients/jackson (Phase 6)]]
- [[packages/iam-domain|internal/domain]]
- [[packages/iam-handler-iamhooks|handler/iamhooks (Phase 2)]]
- [[packages/iam-jobs|internal/apps/kacho/jobs]]
- [[packages/iam-repo-kacho-pg|repo/kacho/pg]]
- [[packages/iam-seed|seed (bootstrap)]]
- [[packages/iam-service-access-review|service/access_review (Phase 7)]]
- [[packages/iam-service-breakglass|service/breakglass (Phase 7)]]
- [[packages/iam-service-caep|service/caep (Phase 8)]]
- [[packages/iam-service-federation|service/federation (Phase 5)]]
- [[packages/iam-service-gdpr|service/gdpr (Phase 7)]]
- [[packages/iam-service-jit|service/jit (Phase 7)]]
- [[packages/iam-service-scim|service/scim (Phase 6)]]

## Packages — kacho-vpc (~27)

См. категориальный список в [[README#Категории-детальных-файлов]] либо `obsidian/kacho/packages/vpc-*.md` glob.

## Packages — kacho-geo (эпик #82)

- [[packages/proto-geo|proto/geo (kacho-proto)]]
- [[packages/geo-domain|internal/domain]]

## Packages — kacho-api-gateway (10)

- [[packages/apigw-allowlist|allowlist]]
- [[packages/apigw-cmd|cmd]]
- [[packages/apigw-config|config]]
- [[packages/apigw-health|health]]
- [[packages/apigw-middleware|middleware]]
- [[packages/api-gateway-middleware-authz|middleware/authz (Phase 3)]]
- [[packages/api-gateway-middleware-dpop|middleware/dpop (Phase 2)]]
- [[packages/apigw-opsproxy|opsproxy]]
- [[packages/apigw-proxy|proxy]]
- [[packages/apigw-restmux|restmux]]

## Packages — legacy RM repo (replaced by kacho-iam, KAC-124)

- [[packages/rm-bootstrap]] [[packages/rm-cmd]] [[packages/rm-config]] [[packages/rm-domain]] [[packages/rm-handler]] [[packages/rm-repo]] [[packages/rm-service]]

## Cross-service edges (~30)

### Backbone

- [[edges/apigw-internal-vs-tls]] — api-gateway: TLS edge vs cluster-internal listener (KAC-50)
- [[edges/apigw-to-compute]] — api-gateway → compute proxy
- [[edges/apigw-to-rm]] — api-gateway → rm proxy (removed, KAC-124)
- [[edges/apigw-to-vpc]] — api-gateway → vpc proxy

### kacho-iam (KAC-127)

- [[edges/iam-to-openfga-check]] — iam ↔ openfga: tuple sync + Check
- [[edges/iam-to-zitadel-oidc]] — iam → zitadel (deprecated; replaced by Kratos/Hydra)
- [[edges/iam-to-hydra-admin]] — iam → Hydra Admin (Phase 2 + 5)
- [[edges/iam-to-kratos-admin]] — iam → Kratos Admin (Phase 2 + 6)
- [[edges/iam-to-opa]] — iam ↔ OPA sidecar (Phase 3)
- [[edges/iam-to-jackson-saml]] — iam → Jackson (Phase 6)
- [[edges/iam-to-scim-okta]] — Okta → iam SCIM (Phase 6)
- [[edges/iam-to-scim-azure]] — Entra → iam SCIM (Phase 6)
- [[edges/iam-to-scim-google]] — Google → iam SCIM (Phase 6)
- [[edges/iam-to-spire]] — iam ↔ SPIRE (Phase 10)
- [[edges/iam-to-cilium-mesh]] — Cilium mesh mTLS (Phase 10)
- [[edges/iam-to-kafka-audit]] — iam → Kafka audit (Phase 9)
- [[edges/iam-to-clickhouse-audit]] — iam ↔ ClickHouse audit (Phase 9)
- [[edges/iam-to-s3-audit]] — iam → S3 + Glacier (Phase 9)
- [[edges/iam-to-hsm]] — iam → HSM PKCS#11 (Phase 8/9)
- [[edges/iam-to-siem-datadog]] — iam → Datadog SIEM (Phase 9)
- [[edges/iam-to-siem-splunk]] — iam → Splunk HEC (Phase 9)
- [[edges/iam-caep-to-subscriber]] — iam → CAEP subscriber outbound (Phase 8)
- [[edges/api-gateway-to-iam-authorize]] — api-gateway → iam AuthorizeService (Phase 3)
- [[edges/vpc-to-iam-listobjects]] — vpc → iam ListObjects (Phase 4)
- [[edges/compute-to-iam-listobjects]] — compute → iam ListObjects (Phase 4)
- [[edges/compute-to-iam-check]] — compute → iam Check
- [[edges/vpc-to-iam-check]] — vpc → iam Check
- [[edges/vpc-to-iam-project-exists]] — vpc → iam project existence

### Cross-service runtime (other)

- [[edges/ui-to-zitadel-redirect]] — ui → zitadel: OIDC redirect (deprecated)
- [[edges/compute-to-rm-folder-check]] — compute → rm: folder check (removed, KAC-124; → iam project check)
- [[edges/compute-to-vpc-nic-validate]] — compute → vpc: NIC validate + attach (CAS)
- [[edges/vpc-implement-to-vpc]] — legacy data-plane sibling → vpc: NI dataplane writeback (removed, KAC-36/79/80; data-plane sibling is now kacho-vpc-operator)
- [[edges/vpc-operator-to-kubeovn]] — kacho-vpc-operator → kube-ovn / Multus: data-plane materialization (experimental)
- [[edges/vpc-to-geo-zone-validate]] — vpc → geo: zone_id validation (эпик #82)
- [[edges/compute-to-geo-zone-validate]] — compute → geo: Instance.zone_id validation (эпик #82)
- [[edges/nlb-to-geo-region-validate]] — nlb → geo: Region validation (эпик #82)
- [[edges/geo-to-iam-check]] — geo → iam: per-RPC authz Check (эпик #82)
- [[edges/vpc-to-compute-zone-validate]] — vpc → compute: zone_id validation (KAC-15, **superseded** by vpc→geo, эпик #82)
- [[edges/nlb-to-compute-region-validation]] — nlb → compute: Region validation (**superseded** by nlb→geo, эпик #82)
- [[edges/vpc-to-rm-folder-exists]] — vpc → rm: folder check (deprecated)

## Public docs (KAC-127 Phase 13)

- [[docs/user-iam-guide]] — User onboarding (Passkey, projects, role assignment)
- [[docs/admin-iam-guide]] — Admin guide (SCIM, SAML, audit, PIM/JIT, break-glass)
- [[docs/dev-iam-integration]] — Developer integration (DPoP, ListObjects, Federation, Conditions, CAEP)

## KAC tickets — trail

- [[KAC/README|KAC trail index]]
- [[KAC/_TEMPLATE|template]]
- [[KAC/all-tickets|all-tickets.base]] — table view
- [[KAC/EPIC-geo-extraction]] — Geography → kacho-geo leaf-service (эпик #82, in-progress)
- [[KAC/KAC-2]] — NetworkInterface first-class (done)
- [[KAC/KAC-15]] — Geography moved vpc → compute (done; теперь надстроено эпиком #82)
- [[KAC/KAC-50]] — api-gateway listener split (done)
- [[KAC/KAC-52]] — NIC attach race fix (done)
- [[KAC/KAC-55]] — NIC v4/v6 cardinality (done)
- [[KAC/KAC-56]] — RouteTable auto-association (done)
- [[KAC/KAC-71]] — AddressPool v4/v6 split (done)
- [[KAC/KAC-94|KAC-94 (Skill evgeniy в kacho-vpc)]] (done)
- [[KAC/KAC-104]] — Kachō IAM epic: Account/Project + Zitadel + OpenFGA REBAC (parent of KAC-127)
- [[KAC/KAC-105]] — IAM E0: kacho-iam skeleton (done)
- [[KAC/KAC-106]] — IAM E1: folder_id → project_id миграция (done)
- [[KAC/KAC-107]] — IAM E2: Zitadel OIDC (deprecated)
- [[KAC/KAC-108]] — IAM E3: OpenFGA REBAC (in-progress)
- [[KAC/KAC-109]] — IAM E4: UI IAM block (done)
- [[KAC/KAC-110]] — IAM E5: deprecate legacy RM repo → kacho-iam (done in KAC-124)
- [[KAC/KAC-111]] — Squash kacho-vpc migrations (done)
- [[KAC/KAC-112]] — E0 follow-up: backend (done)
- [[KAC/KAC-113]] — E0 follow-up: sync principal_* (done)
- [[KAC/KAC-115]] — refactor: Zitadel+OpenFGA → Ory Kratos+Hydra+Keto (done)
- [[KAC/KAC-116]] — Keto + Kratos DoD closeout (done)
- [[KAC/KAC-122]] — authz-deny matrix newman suite
- [[KAC/KAC-123]] — production-IAM YT id (== vault KAC-127)
- [[KAC/KAC-124]] — legacy RM repo → kacho-iam Account/Project (done)
- [[KAC/KAC-125]] — User per-Account + Invite (done)
- [[KAC/KAC-127]] — **Production-Ready Next-Gen IAM (epic, 13 phases)** — in-progress

#index
