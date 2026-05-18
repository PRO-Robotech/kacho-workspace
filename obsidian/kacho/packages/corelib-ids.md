---
title: corelib-ids
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - ids
---

# corelib/ids

**Path**: `kacho-corelib/ids/`
**Imports**: `crypto/rand`, `encoding/binary`, `strings`
**Imported by**: `kacho-vpc` (97 files), `kacho-resource-manager` (7), `kacho-api-gateway` (1)

ID generator + validator: префикс домена (`enp`/`e9b`/`apl`/`b1g`/`bpf`/...) + base32-crockford от crypto/rand.

## Constants (domain prefixes)

```
PrefixCloud         = "b1g"   // resource-manager Cloud
PrefixFolder        = "b1f"   // resource-manager Folder
PrefixOrganization  = "bpf"   // organization-manager
PrefixNetwork       = "enp"   // vpc Network
PrefixSubnet        = "e9b"   // vpc Subnet
PrefixAddress       = "e9a"
PrefixGateway       = "enpg"
PrefixSG            = "enpsg"
PrefixRouteTable    = "enprt"
PrefixPE            = "enpe"
PrefixNI            = "enpni"
PrefixAddressPool   = "apl"
PrefixOperation     = "oper"
PrefixInstance      = "ef3"   // compute
PrefixDisk          = "ef4"
```

(Полный список — `ids.go`; не дублируй наизусть, читай файл.)

## Exported functions

- `NewID(prefix string) string` — `<prefix><base32-крипто-rand>`.
- `NewUID() string` — opaque без префикса (для page-token, idempotency-key).
- `IsValid(id, prefix string) bool` — проверяет, что строка начинается с `prefix` и хвост — валидная base32.
- `HasKnownPrefix(id string) bool` — true если префикс зарегистрирован в const-блоке.

## See also

[[corelib-validate]] (`ResourceID`)

#packages #kacho-corelib #ids
