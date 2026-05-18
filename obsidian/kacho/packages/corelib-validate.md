---
title: corelib-validate
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - validation
---

# corelib/validate

**Path**: `kacho-corelib/validate/`
**Imports**: `corelib/errors`, `grpc/codes`, `grpc/status`, `net`, `regexp`, `unicode/utf8`
**Imported by**: `kacho-vpc` (72 files — service-layer), `kacho-resource-manager` (6)

Field-level validators YC-стиля. Каждый возвращает `error` уже как gRPC `InvalidArgument` с `BadRequest`-details (через [[corelib-errors]]).

## Constants

- `MaxNameLen = 63` — стандарт YC для resource-имён.

## Validators (все возвращают `error`)

- `Name(field, value)` / `NameVPC` / `NameCompute` / `NameGateway` — YC-regex `^[a-z][-a-z0-9]{1,61}[a-z0-9]$`, доменные различия.
- `Description(field, value)` — `<=256` chars, utf8-валидный.
- `Labels(field, labels map[string]string)` — `<=64` пар, key regex, value регex.
- `ResourceID(resourceType, expectedPrefix, id)` — формат `<prefix><crockford-base32>`, см. [[corelib-ids]].
- `IPAddress(field, value)` — IPv4/IPv6 via `net.ParseIP`.
- `UpdateMask(field, mask []string, known map[string]struct{})` — discipline: unknown path → `InvalidArgument`, см. workspace CLAUDE.md.
- `PageSize(field, value int64) (int64, error)` — clamp + default.
- `ZoneId(field, value)`, `DdosProvider`, `DhcpDomainName`, `SmtpCapability` — доменные предикаты.

## Usage

```go
if err := validate.NameVPC("name", req.GetName()); err != nil { return nil, err }
if err := validate.UpdateMask("update_mask", req.UpdateMask.Paths, knownFields); err != nil { return nil, err }
```

## See also

[[corelib-errors]] [[corelib-ids]] [[vpc-domain]]

#packages #kacho-corelib #validation
