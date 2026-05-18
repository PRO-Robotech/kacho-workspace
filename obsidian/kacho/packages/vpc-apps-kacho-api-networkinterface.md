---
title: vpc-apps-kacho-api-networkinterface
category: package
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - ni
---

# kacho-vpc/internal/apps/kacho/api/networkinterface

**Path**: `kacho-vpc/internal/apps/kacho/api/networkinterface/`
**Implements**: [[../rpc/vpc-networkinterface-service|NetworkInterfaceService]]

## Files

| File | Содержание |
|---|---|
| `handler.go` | gRPC adapter |
| `iface.go` | ports |
| `helpers.go` | subnet+SG validation + mac auto-gen (через [[vpc-repo-helpers]] `nic.go`) |
| `create.go` | subnet FK + SG validate + IPAM allocate (primary IP через [[vpc-apps-kacho-services-addressref]]) |
| `update.go` | name/labels/desc/sg-list (replace всю SG-привязку) |
| `delete.go` | FailedPrecondition если attached |
| `attach.go` | **CAS attach** — `UPDATE ... WHERE used_by_id = '' OR = $new` (KAC-52 fix 0017) |
| `detach.go` | CAS detach — set `used_by_id = ''` |
| `get.go` / `list.go` | std |
| `usecase_test.go` | + race-test integration coverage |

## Critical race notes

Software-side `if cur.UsedByID != ""` запрещён (CLAUDE.md «Запреты» #10) — все ownership-changes через single-statement CAS в repo. См. [[../resources/vpc-networkinterface]].

## See also

[[../rpc/vpc-networkinterface-service]] [[../resources/vpc-networkinterface]] [[../edges/compute-to-vpc-nic-validate]]

#packages #kacho-vpc #handler #ni
