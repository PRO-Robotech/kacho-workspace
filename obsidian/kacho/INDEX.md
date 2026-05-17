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

## Resources (20)

- [[resources/iam-access-binding|AccessBinding (iam)]]
- [[resources/iam-account|Account (iam, KAC-105)]]
- [[resources/iam-group|Group (iam)]]
- [[resources/iam-project|Project (iam)]]
- [[resources/iam-role|Role (iam, 12 system seed)]]
- [[resources/iam-service-account|ServiceAccount (iam)]]
- [[resources/iam-user|User (iam, mirror Zitadel)]]
- [[resources/operation|Operation (LRO envelope)]]
- [[resources/rm-cloud|Cloud (rm)]]
- [[resources/rm-folder|Folder (rm)]]
- [[resources/rm-organization|Organization (organizationmanager)]]
- [[resources/vpc-address|Address (vpc)]]
- [[resources/vpc-addresspool|AddressPool (vpc, kacho-only)]]
- [[resources/vpc-gateway|Gateway (vpc)]]
- [[resources/vpc-network|Network (vpc)]]
- [[resources/vpc-networkinterface|NetworkInterface (vpc, KAC-2)]]
- [[resources/vpc-privateendpoint|PrivateEndpoint (vpc)]]
- [[resources/vpc-routetable|RouteTable (vpc)]]
- [[resources/vpc-securitygroup|SecurityGroup (vpc)]]
- [[resources/vpc-subnet|Subnet (vpc)]]

## RPCs (29)

- [[rpc/iam-access-binding-service|AccessBindingService (iam)]]
- [[rpc/iam-account-service|AccountService (iam, KAC-105)]]
- [[rpc/iam-group-service|GroupService (iam)]]
- [[rpc/iam-internal-iam-service|InternalIAMService (iam, internal)]]
- [[rpc/iam-internal-user-service|InternalUserService (iam, internal)]]
- [[rpc/iam-project-service|ProjectService (iam)]]
- [[rpc/iam-role-service|RoleService (iam)]]
- [[rpc/iam-service-account-service|ServiceAccountService (iam)]]
- [[rpc/iam-user-service|UserService (iam, mirror)]]
- [[rpc/om-organization-service|OrganizationService (om alias)]]
- [[rpc/om-user-account-service|UserAccountService (TBD)]]
- [[rpc/operation-service|OperationService]]
- [[rpc/rm-cloud-service|CloudService (rm)]]
- [[rpc/rm-folder-service|FolderService (rm)]]
- [[rpc/rm-organization-service|OrganizationService (rm)]]
- [[rpc/vpc-address-service|AddressService (vpc)]]
- [[rpc/vpc-gateway-service|GatewayService (vpc)]]
- [[rpc/vpc-internal-address-pool-service|InternalAddressPoolService (vpc)]]
- [[rpc/vpc-internal-address-service|InternalAddressService (vpc)]]
- [[rpc/vpc-internal-cloud-service|InternalCloudService (vpc)]]
- [[rpc/vpc-internal-network-interface-service|InternalNetworkInterfaceService (deprecated)]]
- [[rpc/vpc-internal-network-service|InternalNetworkService (vpc)]]
- [[rpc/vpc-internal-watch-service|InternalWatchService (deprecated)]]
- [[rpc/vpc-network-service|NetworkService (vpc)]]
- [[rpc/vpc-networkinterface-service|NetworkInterfaceService (vpc)]]
- [[rpc/vpc-privateendpoint-service|PrivateEndpointService (vpc)]]
- [[rpc/vpc-routetable-service|RouteTableService (vpc)]]
- [[rpc/vpc-securitygroup-service|SecurityGroupService (vpc)]]
- [[rpc/vpc-subnet-service|SubnetService (vpc)]]

## Packages — proto (11)

- [[packages/proto-access|cloud/access — IAM shared]]
- [[packages/proto-api|cloud/api — legacy]]
- [[packages/proto-compute|cloud/compute/v1]]
- [[packages/proto-loadbalancer|cloud/loadbalancer/v1]]
- [[packages/proto-maintenance|cloud/maintenance/v2]]
- [[packages/proto-operation|cloud/operation — LRO envelope]]
- [[packages/proto-organizationmanager|cloud/organizationmanager/v1]]
- [[packages/proto-reference|cloud/reference]]
- [[packages/proto-rm|cloud/resourcemanager/v1]]
- [[packages/proto-root|proto root + google + common]]
- [[packages/proto-vpc|cloud/vpc/v1]]

## Packages — kacho-corelib (15)

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

## Packages — kacho-vpc (27)

- [[packages/vpc-apps-kacho-api-address|apps/kacho/api/address]]
- [[packages/vpc-apps-kacho-api-addresspool|apps/kacho/api/addresspool]]
- [[packages/vpc-apps-kacho-api-gateway|apps/kacho/api/gateway]]
- [[packages/vpc-apps-kacho-api-network|apps/kacho/api/network]]
- [[packages/vpc-apps-kacho-api-networkinterface|apps/kacho/api/networkinterface]]
- [[packages/vpc-apps-kacho-api-privateendpoint|apps/kacho/api/privateendpoint]]
- [[packages/vpc-apps-kacho-api-routetable|apps/kacho/api/routetable]]
- [[packages/vpc-apps-kacho-api-securitygroup|apps/kacho/api/securitygroup]]
- [[packages/vpc-apps-kacho-api-subnet|apps/kacho/api/subnet]]
- [[packages/vpc-apps-kacho-config|apps/kacho/config]]
- [[packages/vpc-apps-kacho-services-addressref|apps/kacho/services/addressref]]
- [[packages/vpc-apps-kacho-services-networkinternal|apps/kacho/services/networkinternal]]
- [[packages/vpc-apps-kacho-shared-macutil|apps/kacho/shared/macutil]]
- [[packages/vpc-apps-kacho-shared-serviceerr|apps/kacho/shared/serviceerr]]
- [[packages/vpc-apps-migrator|apps/migrator]]
- [[packages/vpc-clients|internal/clients]]
- [[packages/vpc-cmd-migrator|cmd/migrator]]
- [[packages/vpc-cmd-vpc|cmd/vpc]]
- [[packages/vpc-domain|internal/domain]]
- [[packages/vpc-dto|internal/dto]]
- [[packages/vpc-dto-toproto|internal/dto/toproto]]
- [[packages/vpc-handler|internal/handler (internal admin)]]
- [[packages/vpc-repo-cqrsadapter|internal/repo/cqrsadapter (legacy)]]
- [[packages/vpc-repo-helpers|internal/repo/helpers]]
- [[packages/vpc-repo-kacho|internal/repo/kacho — CQRS ports]]
- [[packages/vpc-repo-kacho-kachomock|internal/repo/kacho/kachomock]]
- [[packages/vpc-repo-kacho-pg|internal/repo/kacho/pg]]
- [[packages/vpc-repo-repomock|internal/repo/repomock (legacy)]]

## Packages — kacho-resource-manager (7)

- [[packages/rm-bootstrap|bootstrap]]
- [[packages/rm-cmd|cmd]]
- [[packages/rm-config|config]]
- [[packages/rm-domain|domain]]
- [[packages/rm-handler|handler]]
- [[packages/rm-repo|repo]]
- [[packages/rm-service|service]]

## Packages — kacho-api-gateway (8)

- [[packages/apigw-allowlist|allowlist]]
- [[packages/apigw-cmd|cmd]]
- [[packages/apigw-config|config]]
- [[packages/apigw-health|health]]
- [[packages/apigw-middleware|middleware]]
- [[packages/apigw-opsproxy|opsproxy]]
- [[packages/apigw-proxy|proxy]]
- [[packages/apigw-restmux|restmux]]

## Cross-service edges (12)

- [[edges/apigw-internal-vs-tls|api-gateway: TLS edge vs cluster-internal listener (KAC-50)]]
- [[edges/apigw-to-compute|api-gateway → compute proxy]]
- [[edges/apigw-to-rm|api-gateway → rm proxy]]
- [[edges/apigw-to-vpc|api-gateway → vpc proxy]]
- [[edges/compute-to-rm-folder-check|compute → rm: folder check]]
- [[edges/compute-to-vpc-nic-validate|compute → vpc: NIC validate + attach (CAS)]]
- [[edges/iam-to-openfga-check|iam ↔ openfga: REBAC tuple sync + Check (planned, E3)]]
- [[edges/iam-to-zitadel-oidc|iam → zitadel: OIDC identity (planned, E2)]]
- [[edges/ui-to-zitadel-redirect|ui → zitadel: OIDC redirect signup-flow (planned, E2/E4)]]
- [[edges/vpc-implement-to-vpc|vpc-implement → vpc: ReportNiDataplane (deprecated)]]
- [[edges/vpc-to-compute-zone-validate|vpc → compute: zone_id validation (KAC-15)]]
- [[edges/vpc-to-iam-project-exists|vpc → iam: project existence (planned, E1)]]
- [[edges/vpc-to-rm-folder-exists|vpc → rm: folder check]]

## KAC tickets — trail

- [[KAC/README|KAC trail index]]
- [[KAC/_TEMPLATE|template]]
- [[KAC/all-tickets|all-tickets.base]] — table view
- [[KAC/KAC-2]] — NetworkInterface first-class (done)
- [[KAC/KAC-15]] — Geography moved (done)
- [[KAC/KAC-50]] — api-gateway listener split (done)
- [[KAC/KAC-52]] — NIC attach race fix (done)
- [[KAC/KAC-55]] — NIC v4/v6 cardinality (done)
- [[KAC/KAC-56]] — RouteTable auto-association (done)
- [[KAC/KAC-71]] — AddressPool v4/v6 split (done)
- [[KAC/KAC-94|KAC-94 (Skill evgeniy в kacho-vpc)]] (done)
- [[KAC/KAC-104]] — Kachō IAM epic: Account/Project + Zitadel + OpenFGA REBAC (in-progress)
- [[KAC/KAC-105]] — IAM E0: kacho-iam skeleton + Account end-to-end (done; 6 остальных ресурсов в KAC-112)
- [[KAC/KAC-106]] — IAM E1: folder_id → project_id миграция (done)
- [[KAC/KAC-107]] — IAM E2: Zitadel OIDC + auth-interceptor (acceptance APPROVED v1)
- [[KAC/KAC-108]] — IAM E3: OpenFGA REBAC + Check-interceptor (in-progress, foundation merged)
- [[KAC/KAC-109]] — IAM E4: UI IAM block + Operations principal column (UI deployed, signup follow-up)
- [[KAC/KAC-110]] — IAM E5: deprecate kacho-resource-manager (acceptance DRAFT v1)
- [[KAC/KAC-111]] — Squash kacho-vpc migrations 0001..0034 → 0001 (done)
- [[KAC/KAC-112]] — E0 follow-up: backend для Project/User/SA/Group/Role/AccessBinding (done)
- [[KAC/KAC-113]] — E0 follow-up: sync principal_* в kacho-vpc/compute/rm/loadbalancer (done)
- [[KAC/KAC-115]] — refactor: migrate Zitadel+OpenFGA → Ory Kratos+Hydra+Keto (test, 6/6 Playwright)

#index
