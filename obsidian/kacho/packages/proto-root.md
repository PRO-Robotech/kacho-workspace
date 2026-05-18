---
title: proto-root
category: package
repo: kacho-proto
layer: proto
tags:
  - proto
  - buf
  - common
---

# proto/root (common + validation + google)

**Path**: `kacho-proto/proto/`
**Owner**: общая инфра proto-сборки.

## Top-level files

- `kacho/cloud/validation.proto` — встроенные validation options (если используется `protoc-gen-validate` / `buf validate`).
- `kacho/cloud/common/v1/` — placeholder для cross-domain общих типов (пустой на момент индексации — все common перенесены в per-domain `package_options.proto` либо в `proto/reference`).

## Vendor'ed google protos

- `google/api/` — annotations.proto (для grpc-gateway `google.api.http`), http.proto, …
- `google/rpc/` — status.proto, error_details.proto (для [[corelib-errors]] errdetails).

## Build

Регенерация Go-stubs: `cd kacho-proto && make gen`. Stubs commit-ятся в `gen/go/...`. `buf breaking` запускается в CI (см. `.github/workflows/ci.yaml`).

## See also

[[../kacho-proto/README]] [[proto-vpc]] [[proto-rm]]

#proto #buf #common
