---
title: vpc-repo-kacho-pg
category: package
repo: kacho-vpc
layer: repo
tags:
  - packages
  - kacho-vpc
  - repo
  - pg
  - postgres
---

# kacho-vpc/internal/repo/kacho/pg

**Path**: `kacho-vpc/internal/repo/kacho/pg/`
**Imports**: pgxpool, [[vpc-repo-helpers]], [[vpc-repo-kacho]] (entities + ports), [[vpc-domain]]
**Imported by**: [[vpc-cmd-vpc]] (wiring), integration-тесты

pgxpool-реализация всех CQRS port-интерфейсов из [[vpc-repo-kacho]].

## Files

| File | Реализует |
|---|---|
| `repository.go` | aggregator — composes per-entity pg-repos |
| `network.go` | NetworkReader + NetworkWriter |
| `subnet.go` | SubnetReader/Writer + EXCLUDE-constraint mapping |
| `address.go` | AddressReader/Writer + IPAM-allocate |
| `route_table.go` | RouteTableReader/Writer |
| `security_group.go` | SG + OCC (xmin) |
| `gateway.go` | |
| `private_endpoint.go` | |
| `network_interface.go` | NIC + CAS (Attach/Detach) |
| `address_pool.go` | AddressPool + freelist (`FOR UPDATE SKIP LOCKED`) |
| `address_pool_binding.go` | network-default + address-override |
| `cloud_pool_selector.go` | |
| `repository_slave_test.go` | read-replica routing smoke |
| `<entity>_integration_test.go` | testcontainers — concurrent race scenarios для CAS/UNIQUE/EXCLUDE |

## Integration tests

Каждый entity имеет integration_test.go (testcontainers Postgres). Critical race-tests находятся в `internal/repo/`:
- `network_interface_attach_race_integration_test.go` — CAS attach (KAC-52).
- `address_pool_freelist_integration_test.go` — concurrent allocate.
- `address_repo_set_reference_race_integration_test.go` — used_by CAS.
- `security_group_occ_integration_test.go` — xmin OCC.

## See also

[[vpc-repo-helpers]] [[vpc-repo-kacho]] [[corelib-db]]

#packages #kacho-vpc #repo #pg #postgres
