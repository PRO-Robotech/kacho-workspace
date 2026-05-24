---
title: kacho-nlb permissions catalog
aliases:
  - loadbalancer.* permissions
category: packages
repo: kacho-iam
layer: seed
tags:
  - packages
  - kacho-iam
  - kacho-nlb
  - fga
  - permissions
---

# kacho-nlb permissions catalog (`loadbalancer.*`)

~30 permission strings namespace `loadbalancer.*`. **Source of truth**: `kacho-iam/internal/authzmap/permission_catalog.go` (namespace `loadbalancer.`). Seeded в `kacho-iam` migrations + Helm chart bootstrap.

## Full list

### NetworkLoadBalancer (12)
- `loadbalancer.networkLoadBalancers.get`
- `loadbalancer.networkLoadBalancers.list`
- `loadbalancer.networkLoadBalancers.create`
- `loadbalancer.networkLoadBalancers.update`
- `loadbalancer.networkLoadBalancers.delete`
- `loadbalancer.networkLoadBalancers.start`
- `loadbalancer.networkLoadBalancers.stop`
- `loadbalancer.networkLoadBalancers.move`
- `loadbalancer.networkLoadBalancers.attachTargetGroup`
- `loadbalancer.networkLoadBalancers.detachTargetGroup`
- `loadbalancer.networkLoadBalancers.getTargetStates`
- `loadbalancer.networkLoadBalancers.listOperations`

### Listener (6)
- `loadbalancer.listeners.get`
- `loadbalancer.listeners.list`
- `loadbalancer.listeners.create`
- `loadbalancer.listeners.update`
- `loadbalancer.listeners.delete`
- `loadbalancer.listeners.listOperations`

### TargetGroup (9)
- `loadbalancer.targetGroups.get`
- `loadbalancer.targetGroups.list`
- `loadbalancer.targetGroups.create`
- `loadbalancer.targetGroups.update`
- `loadbalancer.targetGroups.delete`
- `loadbalancer.targetGroups.move`
- `loadbalancer.targetGroups.addTargets`
- `loadbalancer.targetGroups.removeTargets`
- `loadbalancer.targetGroups.listOperations`

### Operation (3)
- `loadbalancer.operations.get`
- `loadbalancer.operations.list`
- `loadbalancer.operations.cancel`

## Seed roles (kacho-iam)

Из kacho-iam PR #37 (KAC-NLB seed roles):
- `roles/loadbalancer.viewer` — все `.get` / `.list` / `.listOperations`
- `roles/loadbalancer.editor` — viewer + `.create` / `.update` / `.delete` / `.move` / mutations
- `roles/loadbalancer.admin` — editor + reserved (Start/Stop priv-ops + Cancel ops)

## Custom roles flow

Tenant создаёт custom role в `kacho-iam.RoleService.Create` с подмножеством `loadbalancer.*` → биндит через `AccessBinding.Create` на `project:<id>` или `nlb_load_balancer:<id>` → FGA Check валидирует.

## See also

[[nlb-internal-check]] [[../edges/nlb-to-iam-check]] [[../KAC/KAC-141]]

#packages #kacho-iam #kacho-nlb #fga #permissions
