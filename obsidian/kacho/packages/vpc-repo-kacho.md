---
title: vpc-repo-kacho
category: package
repo: kacho-vpc
layer: repo
tags:
  - packages
  - kacho-vpc
  - repo
  - cqrs
  - ports
---

# kacho-vpc/internal/repo/kacho

**Path**: `kacho-vpc/internal/repo/kacho/`
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
| `iface_private_endpoint.go` | port | |
| `iface_network_interface.go` | port | + Attach/Detach CAS |
| `iface_address_pool.go` | port | |
| `iface_address_pool_binding.go` | port | network-default + address-override |
| `iface_cloud_pool_selector.go` | port | |
| `entity_network.go` | entity-projection (shared между Reader/Writer) | thin row representation |
| `entity_subnet.go` | | |
| `entity_address.go` | | |
| `entity_route_table.go` | | |
| `entity_security_group.go` | | |
| `entity_gateway.go` | | |
| `entity_private_endpoint.go` | | |
| `entity_network_interface.go` | | |
| `entity_address_pool.go` | | |
| `pg/` | | pgxpool-impl ([[vpc-repo-kacho-pg]]) |
| `kachomock/` | | mockgen-generated test mock ([[vpc-repo-kacho-kachomock]]) |

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
