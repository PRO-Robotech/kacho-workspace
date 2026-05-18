---
title: proto-organizationmanager
category: package
repo: kacho-proto
layer: proto
tags:
  - proto
  - kacho-rm
  - organizationmanager
---

# proto/organizationmanager

**Path**: `kacho-proto/proto/kacho/cloud/organizationmanager/v1/`
**Package**: `kacho.cloud.organizationmanager.v1`
**Go import**: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/organizationmanager/v1`
**Owner service**: `kacho-resource-manager` (organization-domain — отдельный proto-package, но обслуживается тем же сервисом)

## Resource protos

- `organization.proto` — [[../resources/rm-organization|Organization]] (`bpf`-id)

## Service protos

- [[../rpc/om-organization-service]] — `organization_service.proto`
- [[../rpc/om-user-account-service]] — (proto часто включает UserAccount RPCs; см. файл).

## Hierarchy

```
Organization (bpf, organizationmanager)
  └─ Cloud (b1g, resourcemanager)
       └─ Folder (b1f, resourcemanager)
            └─ <Network/Subnet/Instance/...>
```

#proto #kacho-rm #organizationmanager
