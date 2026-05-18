---
title: proto-reference
category: package
repo: kacho-proto
layer: proto
tags:
  - proto
  - reference
---

# proto/reference

**Path**: `kacho-proto/proto/kacho/cloud/reference/reference.proto`
**Package**: `kacho.cloud.reference`
**Go import**: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/reference`

Shared `Reference` message — переиспользуемый pointer на typed-resource (id + type) для cross-domain ссылок (например, target в NLB TargetGroup может быть `Reference{type=instance, id=ef3xxx}`).

## Files

- `reference.proto` — `Reference` message.

## Usage

```protobuf
import "kacho/cloud/reference/reference.proto";

message Target {
  kacho.cloud.reference.Reference target = 1;
}
```

#proto #reference
