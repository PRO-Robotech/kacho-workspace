---
title: vpc-repo-kacho-pg
category: packages
repo: kacho-vpc
layer: repo
tags:
  - packages
  - kacho-vpc
  - repo
  - pg
  - postgres
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов реализации, имена и расположение четырёх гоночных integration-тестов; текст записки построчно не пересматривался"
---

# kacho-vpc/internal/repo/kacho/pg

**Каталог**: `services/vpc/internal/repo/kacho/pg/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/repo/kacho/pg/`)
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
| `network_interface.go` | NIC + CAS (`AttachToInstance` / `DetachFromInstance`) |
| `address_pool.go` | AddressPool + freelist (`FOR UPDATE SKIP LOCKED`) |
| `address_pool_binding.go` | network-default |
| `existence_probe.go` | проба существования строки без раскрытия содержимого |
| `fga_reconcile_adapter.go` | адаптер реконсиляции owner-tuple |
| `repository_slave_test.go` | read-replica routing smoke |
| `<entity>_integration_test.go` | testcontainers — concurrent race scenarios для CAS/UNIQUE/EXCLUDE |

Итого **двенадцать** файлов реализации. Пары под приватную конечную точку и под выбор
пула здесь нет — предметы сняты, разбор не дублируется, он в [[vpc-repo-kacho]] (снятые
имена там намеренно не цитируются координатой, и здесь тоже).

## Integration tests

Каждый entity имеет свой `*_integration_test.go` (testcontainers Postgres). Четыре
гоночных теста, и **лежат они в двух разных местах** — это стоит знать до поиска:

- **в этом пакете**, `services/vpc/internal/repo/kacho/pg/network_interface_attach_integration_test.go`
  — CAS привязки интерфейса (KAC-52): конкурентные горутины на общем барьере, не `time.Sleep`,
  под `-race`; там же соседний `network_interface_attach_region_integration_test.go` про
  региональную когерентность. **В имени нет слова про гонку** — прежняя редакция вставляла
  его и потому не резолвилась;
- **уровнем выше**, в `services/vpc/internal/repo/` — `address_pool_freelist_integration_test.go`
  (конкурентная аллокация), `address_repo_set_reference_race_integration_test.go`
  (CAS `used_by`), `security_group_occ_integration_test.go` (OCC по `xmin`). Для этих трёх
  прежнее утверждение «лежат уровнем выше» **верно** — неверным было только четвёртое имя.

## See also

[[vpc-repo-helpers]] [[vpc-repo-kacho]] [[corelib-db]]

#packages #kacho-vpc #repo #pg #postgres
