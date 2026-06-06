---
title: vpc-domain
category: package
repo: kacho-vpc
layer: domain
tags:
  - packages
  - kacho-vpc
  - domain
---

# kacho-vpc/internal/domain

**Path**: `kacho-vpc/internal/domain/`
**Imports**: stdlib + `kacho-corelib/ids`/`validate` + `kacho-proto` (только для константных enum mapping)
**Imported by**: всё в `kacho-vpc/internal/{service,repo,apps,clients}` (entities — единые)

Чистые domain-entities + newtype'ы + конструкторы + `Equal`-методы. Self-validating: конструктор отвергает invalid state (skill `evgeniy` rule).

## Files

| File | Содержание |
|---|---|
| `types.go` | newtypes: `RcNameVPC`, `RcDescription`, `RcLabels`, `RcID(prefix)`, `CIDR`, `MacAddress`, … |
| `types_test.go` | unit-тесты конструкторов newtype'ов |
| `constants.go` | enum/string constants (статусы, kind'ы) |
| `network.go` | `Network` struct + `NewNetwork` ctor + `(*Network).Equal` |
| `subnet.go` | `Subnet` + ctor + Equal |
| `address.go` | `Address` + ctor + Equal |
| `route_table.go` | `RouteTable` |
| `security_group.go` | `SecurityGroup` + Equal |
| `security_group_builders.go` | rule-builders |
| `security_group_builders_test.go` | |
| `gateway.go` | `Gateway` |
| `private_endpoint.go` | `PrivateEndpoint` |
| `network_interface.go` | `NetworkInterface` |
| `address_pool.go` | `AddressPool` |
| ~~`cloud_pool_selector.go`~~ | `CloudPoolSelector` — удалён в [[../KAC/KAC-266]] (InternalCloudService removed) |
| `geography.go` | helpers (после KAC-15 — read-only mirror types) |
| `persistence.go` | shared persistence-side types (created_at truncate, jsonb wrappers) |
| `equal_test.go` | unit-тесты `.Equal` для всех entity |

## Rules (skill `evgeniy`)

- Newtypes вместо bare-string — `RcNameVPC` не принимает `validate.NameVPC` invalid.
- `New<Entity>(...)` — единственный путь создания; нет `&Entity{}` снаружи pkg.
- `.Equal(other)` для diff'ов / OCC checks.

## See also

[[vpc-dto]] [[vpc-repo-kacho]] [[corelib-ids]] [[corelib-validate]]

#packages #kacho-vpc #domain
