---
title: proto-rm
category: package
repo: kacho-proto
layer: proto
tags:
  - proto
  - kacho-rm
---

# proto/resourcemanager

**Path**: `kacho-proto/proto/kacho/cloud/resourcemanager/v1/`
**Package**: `kacho.cloud.resourcemanager.v1`
**Go import**: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/resourcemanager/v1`
**Owner service**: [[../README#kacho-resource-manager|kacho-resource-manager]]

## Resource protos

- `cloud.proto` — [[../resources/rm-cloud|Cloud]] (b1g-id)
- `folder.proto` — [[../resources/rm-folder|Folder]] (b1f-id)

(Organization — отдельный proto-domain [[proto-organizationmanager]].)

## Service protos

- [[../rpc/rm-cloud-service]] — `cloud_service.proto`
- [[../rpc/rm-folder-service]] — `folder_service.proto`

## Position в domain-графе

- Leaf-owner для **Folder** — leaf-сервис в edge-графе: его зовут (vpc/compute/nlb для folder-validation), он сам никуда не зовёт. См. [[../edges/vpc-to-rm-folder-exists]], [[../edges/compute-to-rm-folder-check]].
- Cloud — root level; держит cloud_id; используется как parent у Folder.

#proto #kacho-rm
