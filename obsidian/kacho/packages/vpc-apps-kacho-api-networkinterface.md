---
title: vpc-apps-kacho-api-networkinterface
category: packages
repo: kacho-vpc
layer: use-case
tags:
  - packages
  - kacho-vpc
  - handler
  - ni
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов каталога против перечня RPC в proto домена и против package-doc пакета; текст записки построчно не пересматривался"
---

# kacho-vpc/internal/apps/kacho/api/networkinterface

**Каталог**: `services/vpc/internal/apps/kacho/api/networkinterface/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/apps/kacho/api/networkinterface/`)
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
| `get.go` / `list.go` | std |
| `*_test.go` | unit-тесты пакета |

> [!warning] Отдельных use-case'ов привязки/отвязки в пакете нет — соответствующих RPC не существует
> Записка называла два файла под CAS-привязку интерфейса к машине. В каталоге их нет, и
> это не переезд: **RPC под них не существует** — package-doc пакета и godoc его `Handler`
> говорят это прямым текстом («NIC-ресурс и `used_by`-колонки остаются, но через эти RPC
> не выставляются»). Перечень методов сервиса — `Get`, `List`, `Create`, `Update`,
> `Delete`, `ListOperations`, и `Move` у NIC тоже нет (интерфейс привязан к подсети,
> перемещение между проектами не поддерживается).
>
> **Сам CAS при этом жив** — он просто не здесь. Атомарная смена владельца реализована
> в repo-слое (`services/vpc/internal/repo/kacho/pg/network_interface.go`, методы
> `AttachToInstance` / `DetachFromInstance`), а привязка адреса при `Create`/`Update`
> идёт `SetReference`-CAS'ом в **той же** writer-TX, что вставка интерфейса, outbox и
> запись в очередь регистраций. Спутать эти два уровня легко, и цена ошибки конкретная:
> искать «почему привязка не атомарна» стали бы в use-case, где кода нет вовсе.

## Critical race notes

Software-side `if cur.UsedByID != ""` запрещён (CLAUDE.md «Запреты» #10) — все ownership-changes
через single-statement CAS в repo. Регрессия на это свойство —
`services/vpc/internal/repo/kacho/pg/network_interface_attach_integration_test.go`
(конкурентные горутины на общем барьере, под `-race`). См. [[../resources/vpc-networkinterface]].

## See also

[[../rpc/vpc-networkinterface-service]] [[../resources/vpc-networkinterface]] [[../edges/compute-to-vpc-nic-validate]]

#packages #kacho-vpc #handler #ni
