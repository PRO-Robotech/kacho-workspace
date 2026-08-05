---
title: vpc-repo-kacho
category: packages
repo: kacho-vpc
layer: repo
tags:
  - packages
  - kacho-vpc
  - repo
  - cqrs
  - ports
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов каталога портов и сущностей; текст записки построчно не пересматривался"
---

# kacho-vpc/internal/repo/kacho

**Каталог**: `services/vpc/internal/repo/kacho/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/repo/kacho/`)
**Imported by**: service-layer ([[vpc-apps-kacho-api-network]] и т.п.), [[vpc-cmd-vpc]] для wiring.

CQRS-разделённые **port-интерфейсы** для всех VPC ресурсов. Skill `evgeniy`: «service зависит от Reader+Writer интерфейсов, не от concrete repo».

## Files (по entity)

| File | Тип | Содержание |
|---|---|---|
| `iface.go` | aggregator | union интерфейс `Repository` (все Reader+Writer per resource) |
| `iface_network.go` | port | `NetworkReader`, `NetworkWriter` |
| `iface_subnet.go` | port | `SubnetReader`, `SubnetWriter` |
| `iface_address.go` | port | `AddressReader`, `AddressWriter` |
| `iface_route_table.go` | port | `RouteTableReader`, `RouteTableWriter` |
| `iface_security_group.go` | port | + CAS-методы (OCC xmin) |
| `iface_gateway.go` | port | |
| `iface_network_interface.go` | port | + Attach/Detach CAS |
| `iface_address_pool.go` | port | |
| `iface_address_pool_binding.go` | port | network-default |
| `entity_network.go` | entity-projection (shared между Reader/Writer) | thin row representation |
| `entity_subnet.go` | | |
| `entity_address.go` | | |
| `entity_route_table.go` | | |
| `entity_security_group.go` | | |
| `entity_gateway.go` | | |
| `entity_network_interface.go` | | |
| `entity_address_pool.go` | | |
| `pg/` | | pgxpool-impl ([[vpc-repo-kacho-pg]]) |
| `kachomock/` | | handwritten test mock ([[vpc-repo-kacho-kachomock]]) |

Итого на сверенной ревизии: **девять** портов (`iface.go` + восемь `iface_<entity>.go`)
и **восемь** проекций-сущностей.

> [!warning] Двух семейств файлов нет — оба предмета сняты, и по-разному
> Прежняя редакция несла порт и проекцию под **приватную конечную точку** и порт под
> **выбор пула**. Ни одного из трёх файлов в каталоге нет, и это не переезд:
>
> - **выбор пула** снят вместе с таблицей — миграция
>   `services/vpc/internal/migrations/0002_drop_override_and_cloud_pool_selector.sql`
>   дропает её и парную ей таблицу привязки «на конкретный адрес», а соответствующие RPC
>   убраны из proto и реализации. Поэтому же у `iface_address_pool_binding.go` осталась
>   только привязка умолчания сети;
> - **приватная конечная точка** отсутствует в дереве **целиком** — ноль вхождений во
>   всех `services/` и `proto/`, ни таблицы, ни ресурса, ни RPC. Это не «удалили
>   реализацию, оставив контракт»: предмета нет нигде.
>
> Сами снятые имена здесь не воспроизводятся в обратных кавычках — цитата мёртвого адреса
> читается как живое утверждение о дереве. Те же два семейства были записаны и у
> [[vpc-repo-kacho-pg]], и у [[vpc-repo-kacho-kachomock]]: расхождение тиражировалось по
> трём запискам разом, потому что все три перечисляли **один** набор портов.

## Pattern

```go
type NetworkReader interface {
    Get(ctx context.Context, id string) (Network, error)
    List(ctx context.Context, filter ListFilter) ([]Network, string, error)  // (items, next_token, err)
}
type NetworkWriter interface {
    Create(ctx context.Context, n Network) error
    Update(ctx context.Context, n Network) error  // OCC через xmin если нужно
    Delete(ctx context.Context, id string) error
}
```

## See also

[[vpc-repo-kacho-pg]] [[vpc-repo-kacho-kachomock]] [[vpc-repo-cqrsadapter]] [[vpc-domain]]

#packages #kacho-vpc #repo #cqrs #ports
