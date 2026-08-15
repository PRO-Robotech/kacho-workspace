---
title: nlb-clients-vpc
category: packages
repo: kacho-nlb
layer: clients
tags:
  - packages
  - kacho-nlb
  - clients
  - cross-service
  - vpc
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов каталога и отсутствие кэша в клиентах nlb; текст записки построчно не пересматривался"
---

# kacho-nlb/internal/clients/vpc

**Каталог**: `services/nlb/internal/clients/vpc/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-nlb/internal/clients/vpc/`)
**Imports**: `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/vpc/v1`, [[corelib-retry]]
**Imported by**: [[nlb-apps-kacho-api-loadbalancer]] (VIP acquire/release + subnet/SG peer-validate), [[nlb-apps-kacho-api-targetgroup]] (Subnet + NIC resolve), `jobs/free_ip_runner.go` (release-backstop)

Typed peer-service gRPC client adapters для kacho-vpc.

## Files

| File | Содержание |
|---|---|
| `address_client.go` | wraps `vpcpb.AddressServiceClient.Get` — публичное чтение адреса |
| `internal_address_client.go` | wraps `InternalAddressServiceClient` — аллокация/освобождение и CAS-привязка (internal-only, :9091) |
| `subnet_client.go` | wraps `vpcpb.SubnetServiceClient.Get` — для INTERNAL Listener + Target ip_ref CIDR check |
| `network_interface_client.go` | wraps `vpcpb.NetworkInterfaceServiceClient.Get` — для Target.nic_id resolve → primary IP |
| `security_group_client.go` | wraps `vpcpb.SecurityGroupServiceClient.Get` — peer-validate SG балансировщика |
| `doc.go` | overview пакета |
| `*_test.go` | unit-tests (полосы own/peer-видимости, zone-independent alloc, идемпотентность, маппинг отказов) |

> [!warning] Кэша подсетей в пакете нет — прежняя редакция называла файл под LRU
> Записка перечисляла отдельный файл с LRU-кэшем подсети на 30s. Его нет, и кэша нет
> **ни в одном** клиенте nlb: перепись по каталогу `services/nlb/internal/clients/`
> даёт ноль упоминаний. То же и у соседа — [[nlb-clients-iam]], [[nlb-clients-compute]];
> для geo это прямо записано нормой («sync precheck на request-path, кэша нет»).
> Утверждение о кэше опасно тем, что объясняет собой чужой симптом: расхождение
> «создал → сразу не видно» приходит из eventually-consistent материализации прав, а
> не из TTL, которого нет, — и поиск ушёл бы не туда.

## Pattern

Port-interfaces в service-layer (`AddressClient`, `SubnetClient`, `NICClient`); adapter в `clients/vpc/` реализует через gRPC stub + `corelib/retry.OnUnavailable`.

## Address client surface

```go
type AddressClient interface {
    Get(ctx, addressID) (*Address, error)
    AllocateExternalIP(ctx, owner string) (*Address, error)
    AllocateInternalIP(ctx, subnetID, owner string) (*Address, error)
    FreeIP(ctx, addressID string) error  // idempotent
    SetReference(ctx, addressID, usedBy string) error  // CAS
    ClearReference(ctx, addressID, prevUsedBy string) error  // CAS
}
```

CAS pattern (SetReference/ClearReference) — vpc-side single-statement `UPDATE ... WHERE used_by IN ('', $prev) RETURNING ...`. 0 rows → conflict → `FailedPrecondition` (TOCTOU-free, workspace CLAUDE.md §«Within-service refs»).

## See also

[[../edges/nlb-to-vpc-vip-allocation]] [[../edges/nlb-to-vpc-byo-address]] [[../edges/nlb-to-vpc-subnet-validation]] [[../edges/nlb-to-vpc-nic-resolve]] [[nlb-apps-kacho-api-listener]] [[nlb-apps-kacho-api-targetgroup]]

#packages #kacho-nlb #clients #cross-service #vpc
