---
title: vpc-repo-kacho-kachomock
category: package
repo: kacho-vpc
layer: repo
tags:
  - packages
  - kacho-vpc
  - repo
  - mock
  - testing
---

# kacho-vpc/internal/repo/kacho/kachomock

**Path**: `kacho-vpc/internal/repo/kacho/kachomock/`
**Imported by**: service-layer unit-тесты (`internal/apps/kacho/api/<resource>/usecase_test.go`)

Mock-реализации port-интерфейсов из [[vpc-repo-kacho]] — для unit-тестов service-layer без БД (skill `evgeniy` rule).

## Files

Per-entity mock structs:
- `repository.go` — aggregator mock implementing full `Repository`.
- `network.go`, `subnet.go`, `address.go`, `route_table.go`, `security_group.go`, `gateway.go`, `private_endpoint.go`, `network_interface.go`, `address_pool.go`, `address_pool_binding.go`, `cloud_pool_selector.go`.

## Pattern

Не gomock-generated — handwritten для лучшего test-DSL (записываем какие вызовы ожидаются + что вернуть). Каждый mock содержит `On<Method>`-helpers.

## See also

[[vpc-repo-kacho]] [[vpc-repo-repomock]] [[vpc-repo-cqrsadapter]]

#packages #kacho-vpc #repo #mock #testing
