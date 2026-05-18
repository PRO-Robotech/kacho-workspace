---
title: OrganizationService (om alias)
aliases:
  - OrganizationService (om)
category: rpc
backend: kacho-resource-manager
backend_port: 9090
visibility: public
domain: organizationmanager
status: alias
related_resource: "[[resources/rm-organization]]"
tags:
  - rpc
  - kacho-rm
  - organization
  - alias
---

# OrganizationService (om) — alias

См. [[rm-organization-service]] — это тот же сервис; «om» (organization-manager) — отдельный proto-package, но обслуживается тем же сервисом `kacho-resource-manager`.

## Path mapping

- gRPC service: `kacho.cloud.organizationmanager.v1.OrganizationService`
- REST префикс: `/organization-manager/v1/organizations`

## See also

[[rm-organization-service]] [[../packages/proto-organizationmanager]]

#rpc #kacho-rm #organization
