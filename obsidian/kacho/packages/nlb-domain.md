---
title: nlb-domain
category: packages
repo: kacho-nlb
layer: domain
tags:
  - packages
  - kacho-nlb
  - domain
---

# kacho-nlb/internal/domain

**Path**: `kacho-nlb/internal/domain/`
**Imports**: stdlib only (`net/netip`, `time`, `regexp`) + corelib `dict`/`option`/`ids`
**Imported by**: [[nlb-apps-kacho-api-loadbalancer]], [[nlb-apps-kacho-api-listener]], [[nlb-apps-kacho-api-targetgroup]], [[nlb-repo-kacho-pg]], [[nlb-dto]]

Self-validating domain (evgeniy §D — newtypes + `Validate()` everywhere). No bare `string` for business fields.

## Files

| File | Содержание |
|---|---|
| `types.go` | newtypes: `ResourceID`, `ProjectID`, `RegionID`, `LbName`, `LbDescription`, `LbLabels`, `LbPort`, `LbProto`, `IPVersion`, `IPAddress`, `LbWeight`, `LbDuration` |
| `constants.go` | enum strings (LBType, LBStatus, SessionAffinity, ListenerStatus, TargetGroupStatus, TargetHealthStatus) |
| `status.go` | status state machine helpers (`CanTransition`, `IsTerminal`) |
| `loadbalancer.go` | `LoadBalancer` struct + `Validate()` + `Equal()` |
| `listener.go` | `Listener` struct + `Validate()` (VIP rules, INTERNAL→subnet required) |
| `target_group.go` | `TargetGroup` struct + `Validate()` |
| `target.go` | `Target` struct + `Validate()` (4-way oneof exactly-one + bogon-check для external_ip) |
| `health_check.go` | `HealthCheck` + 4 variants (TCP/HTTP/HTTPS/GRPC) exactly-one + ranges |
| `builders.go` | typed constructors `NewLoadBalancer(...)`, `NewListener(...)` + защита invariants |
| `errors.go` | sentinel-errors `ErrInvalidArgument`, `ErrConflict`, `ErrNotFound`, `ErrFailedPrecondition` |
| `*_test.go` | unit-tests (≥85% coverage; per evgeniy gate) |

## Coverage

98%+ (target ≥85%). Включает race-cases для concurrent Validate (pure functions, no race possible).

## Validate() pattern

```go
func (t *Target) Validate() error {
    setCount := 0
    if t.InstanceID.IsSet() { setCount++ }
    if t.NicID.IsSet()      { setCount++ }
    if t.IPRef != nil       { setCount++ }
    if t.ExternalIP != nil  { setCount++ }
    if setCount != 1 {
        return fmt.Errorf("%w: target identity must be exactly one", ErrInvalidArgument)
    }
    if t.ExternalIP != nil {
        if err := bogonCheck(t.ExternalIP.Address); err != nil { return err }
    }
    if err := t.Weight.Validate(); err != nil { return err }
    return nil
}
```

## See also

[[../resources/nlb-load-balancer]] [[../resources/nlb-listener]] [[../resources/nlb-target-group]] [[../resources/nlb-target]] [[nlb-dto]]

#packages #kacho-nlb #domain
