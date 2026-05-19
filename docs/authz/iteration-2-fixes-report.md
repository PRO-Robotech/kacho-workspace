# KAC-122 Iteration 2 — Fixes Report (2026-05-19)

Continuing the security-iteration loop. Iter-1 закрыл anonymous vectors;
**iter-2** обнаружил что authenticated NOB user **может уничтожать и
модифицировать чужие ресурсы** через Delete/Update/AccessBinding mutations
— anti-anon пропускал, но не было ownership-checks.

## Newly discovered CRITICAL (12 findings)

| # | Vector | Probe (NOB authenticated) | Status |
|---|---|---|---|
| CRIT-9 | NOB Account.Delete чужой | `Delete {accountId:<victim>}` → 200 OP | 🔒 NotFound |
| CRIT-12 | NOB Project.Delete чужой | `Delete {projectId:<victim>}` → 200 OP | 🔒 NotFound |
| CRIT-14 | NOB Account.Update чужой (rename/phish) | `Update {accountId:<victim>, name:phish}` → 200 | 🔒 NotFound |
| CRIT-15 | NOB Group.Delete чужой | → 200 OP | 🔒 |
| CRIT-16 | NOB AccessBinding.Delete чужой | → 200 OP | 🔒 (требует self-binding) |
| CRIT-17 | NOB ServiceAccount.Delete чужой | → 200 OP | 🔒 |
| CRIT-18 | NOB Role.Delete custom-role чужой | → 200 OP | 🔒 |
| CRIT-19 | NOB User.Delete bootstrap (или любого) | → 200 OP | 🔒 (self OR owner-of-user.account) |
| **CRIT-20** | **NOB AccessBinding.Create iam.admin на чужой account** (persistent backdoor — будет live grant когда Keto enforce) | → 200 OP, binding row created | 🔒 PermissionDenied |
| CRIT-22 | NOB Project.Update description чужой | → 200 OP | 🔒 |
| CRIT-23 | NOB Group.Update чужой | → 200 OP (если ID валидный) | 🔒 |
| CRIT-24 | NOB Role.Update custom-role чужой | → 200 OP (если ID валидный) | 🔒 |

**12 новых CRITICAL** closed via ownership-check pattern.

## Implementation

### Pattern (per use-case)

```go
func (u *DeleteXxxUseCase) Execute(ctx, id) (*Operation, error) {
    if err := validateXxxID(id); err != nil { return nil, err }  // sync format
    if err := authzguard.RequireAuthenticated(ctx); err != nil { return nil, err }  // defense-in-depth
    rd := repo.Reader(ctx)
    current := rd.Xxx().Get(id)  // NotFound if not visible (hide existence)
    acct := rd.Accounts().Get(current.AccountID)  // multi-hop resolve
    if err := authzguard.RequireOwnerMatchesPrincipal(ctx, acct.OwnerUserID); err != nil { return nil, err }
    ...
}
```

### AccessBinding.Create resource-ownership

`requireOwnerOfResource(ctx, resourceType, resourceID)`:
- `account` → load account → check owner_user_id == principal.ID
- `project` → load project → load account → check
- other → DENY (KAC-126 will extend для cross-service)

### Touched files (iter-2)

| Service | File |
|---|---|
| kacho-iam | `internal/authzguard/authzguard.go` — добавлены `IsSelf`, `PermissionDenied`, `RequireOwnerMatchesPrincipal` |
| | `internal/apps/kacho/api/account/{delete,update}.go` |
| | `internal/apps/kacho/api/project/{delete,update}.go` |
| | `internal/apps/kacho/api/group/{delete,update}.go` |
| | `internal/apps/kacho/api/service_account/{delete,update}.go` |
| | `internal/apps/kacho/api/role/{delete,update}.go` |
| | `internal/apps/kacho/api/user/delete.go` (self OR owner-of-account.user) |
| | `internal/apps/kacho/api/access_binding/{create,delete,helpers}.go` |

## Remaining (deferred KAC-126)

| Vector | Status |
|---|---|
| AccessBinding cross-service resource_id (e.g. `compute:disk`) | DENY на E0; KAC-126 — Keto Check |
| NOB self-grant на own account | currently ALLOWED (NOB owns своё account через bootstrap-create) — OK |
| gRPC reflection enabled на public listener | MED-3 info leak — disable in production-strict mode |
| Direct gRPC к kacho-iam:9090 bypass api-gateway | requires NetworkPolicy / mTLS в production |
| JWT algorithm confusion / expired / forged | jwt-go HS256-only, валидация работает; expired check тоже |
| Group.AddMember / RemoveMember ownership | TODO — apply same pattern |
| User.Update | TODO — пока нет; KAC-126 |
| Operation.Cancel cross-user | not exploitable (validates op.principal_id) |

## Deployed Images

```
kacho-iam:      ttl.sh/kac122-fix6-<ts>/kacho-iam:24h
kacho-vpc:      ttl.sh/kac122-vpc-<ts>/kacho-vpc:24h
kacho-compute:  ttl.sh/kac122-cmp-<ts>/kacho-compute:24h
kacho-api-gateway: ttl.sh/kac122-apigw-<ts>/kacho-api-gateway:24h
```

## Verified на live стенде

```bash
$ grpcurl -H "x-kacho-principal-type: user" -H "x-kacho-principal-id: $USER_NOB" \
  -d '{"accountId":"<victim>"}' localhost:19090 kacho.cloud.iam.v1.AccountService/Delete
ERROR: Code: NotFound  Message: Account <victim> not found   ✅ (был 200)

$ grpcurl -H "x-kacho-principal-type: user" -H "x-kacho-principal-id: $USER_NOB" \
  -d '{"subjectType":"user","subjectId":"<nob>","roleId":"iamad","resourceType":"account","resourceId":"<victim>"}' \
  localhost:19090 kacho.cloud.iam.v1.AccessBindingService/Create
ERROR: Code: PermissionDenied  Message: permission denied   ✅ (CRIT-20, был 200)

$ grpcurl -H "x-kacho-principal-type: user" -H "x-kacho-principal-id: $USER_BOOT" \
  -d '{"subjectType":"user","subjectId":"<boot>","roleId":"iamvw","resourceType":"account","resourceId":"<boot-own-acct>"}' \
  localhost:19090 kacho.cloud.iam.v1.AccessBindingService/Create
{...}   ✅ (legit owner can self-bind on own account)
```

## Aggregate (iter-1 + iter-2)

- **20+ CRITICAL** closed
- **3 HIGH** closed (User.List leak / Role.Create / cross-grant)
- **1 NEW CRITICAL** (CRIT-8 header injection) — closed
- Test infrastructure (846 newman cases) — CI зелёное во всех 4 PR'ах
- Ownership-based pre-Keto authz model работает на E0/E1; полный Keto-based authz в KAC-126.

## Roadmap к KAC-126 (full ReBAC)

1. `InternalIAMService.Check` real implementation (Keto-backed)
2. Per-method permission_map с relations cascade
3. AccessBinding.Create — Keto-Check `principal admin on resource_id`
4. Cross-service resource ownership via Keto namespaces
5. Audit trail для всех authz decisions
6. Replace temporary `RequireOwnerMatchesPrincipal` helpers с Keto Check calls
