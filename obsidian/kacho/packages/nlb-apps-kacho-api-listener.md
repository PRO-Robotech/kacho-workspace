---
title: nlb-apps-kacho-api-listener
category: packages
repo: kacho-nlb
layer: use-case
tags:
  - packages
  - kacho-nlb
  - handler
  - usecase
  - listener
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# kacho-nlb/internal/apps/kacho/api/listener

**Каталог**: `services/nlb/internal/apps/kacho/api/listener/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-nlb/internal/apps/kacho/api/listener/`)
**Implements**: [[../rpc/nlb-listener-service|ListenerService]]
**Imports**: [[nlb-domain]], [[nlb-repo-kacho-pg]], [[corelib-operations]], [[corelib-outbox]], [[nlb-clients-vpc]], [[nlb-internal-fgawrite]]

## Files

| File | Содержание |
|---|---|
| `handler.go` | thin gRPC adapter |
| `iface.go` | port-интерфейсы (Repo, AddressClient, SubnetClient, Emitter) |
| `helpers.go` | shared validation + mapErr |
| `get.go` / `list.go` | sync reads |
| `create.go` | `CreateListenerUseCase` — LB.Get + TG-precheck + Validate + spawn worker (чистый INSERT) |
| `create.go` (worker) | одна writer-TX: listeners.Insert (`ACTIVE`) → outbox (CREATED + LB UPDATED) → FGA-register-intent → Commit. Внешних side-effect'ов и компенсации нет. |
| `update.go` | UpdateMask; immutable: lb_id/protocol/port |
| `delete.go` | spawn worker: listeners.Delete → outbox DELETED. VIP не освобождает (принадлежит LB); legacy release-ветка по `listeners.address_id` мертва — колонка всегда пуста |
| `list_operations.go` | per-resource history |
| `*_test.go` | unit-tests (TG-wiring, immutable update reject, malformed id, port BVA) |

## VIP — не здесь

Аллокация/release VIP живут в `apps/kacho/api/loadbalancer` (+ `jobs/free_ip_runner.go`):
[[../edges/nlb-to-vpc-vip-allocation]]. Порт `AddressClient` в этом пакете остался только под
мёртвую legacy-release-ветку `delete.go` — прод-путь его не задействует.

## See also

[[../rpc/nlb-listener-service]] [[../resources/nlb-listener]] [[nlb-clients-vpc]] [[../edges/nlb-to-vpc-vip-allocation]]

#packages #kacho-nlb #handler #usecase #listener
