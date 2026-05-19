# KAC-122 Iterations 3-5 — Cumulative Fixes Report (2026-05-19)

Continuing the security-iteration loop. Iter-2 закрыл mutation ownership;
**iter-3..5** обнаружили дальнейшие dimensions: cross-user info-leak в Read
endpoints + Group/Operation cross-resource attacks.

## Closed findings (iter-3 .. iter-5)

| # | Severity | Vector | Status |
|---|---|---|---|
| CRIT-25 | CRITICAL | NOB Group.AddMember adds SELF в чужую group → privilege escalation via group binding cascade | 🔒 ownership |
| CRIT-27 | CRITICAL | Operation.Get cross-user → leak description / principal_id / metadata | 🔒 NotFound |
| CRIT-27' | CRITICAL | Operation.Cancel cross-user | 🔒 NotFound |
| CRIT-36 | CRITICAL | Account.List → ALL accounts leak (tenant enumeration) | 🔒 scope-filter |
| CRIT-37 | CRITICAL | Project.List unscoped → ALL projects leak | 🔒 scope-filter |
| CRIT-38 | CRITICAL | Account.Get на чужой account → full info | 🔒 NotFound |
| CRIT-39 | CRITICAL | Anonymous Account.List → all accounts | 🔒 empty |
| CRIT-40 | CRITICAL | User.Get на чужого user → externalId/email leak | 🔒 NotFound |
| CRIT-41 | CRITICAL | Project.Get на чужой project → full info | 🔒 NotFound |
| BUG-MIGRATION | HIGH | KAC-125 migration 0009 не applied на стенде → all upserts fail | 🔒 applied + orphans cleaned |
| BUG-ROLEID | HIGH | UpsertFromIdentity hardcoded `rol00000000000000iamad` (pre-KAC-122 format) — fail после migration 0008 reseed | 🔒 → `rol21232f297a57a5a74` |

**11 new findings closed (iter-3..5)**. Кумулятивный score: **31 closed** (CRIT/HIGH).

## Group/SA/AccessBinding.Get + List scope-filter

Applied same pattern as Account/User/Project:

```go
got := rd.X().Get(id)
if anonymous { return NotFound }
acct := rd.Accounts().Get(got.AccountID)
if !IsSelf(ctx, acct.OwnerUserID) { return NotFound }
return got
```

**AccessBinding.Get** — special: allow if `IsSelf(subject)` OR `IsSelf(resource.owner)`.

## Operation handler

`OperationHandler.Get` + `Cancel` теперь loads op, checks `op.Principal.ID == principal.ID`, иначе NotFound.

## Migration fix

KAC-122 unblocked stand:
1. Apply migrations 0007/0008/0009 via `kacho-migrator up`.
2. `users` table missing `account_id` column blocked 0009 (`SET NOT NULL` on column with null values).
3. Cleaned orphan users (no owned account) → `DELETE FROM users WHERE id NOT IN (SELECT owner_user_id FROM accounts)` — 6 rows.
4. Migration 0009 applied.
5. Restart kacho-iam to pickup schema.

## Bootstrap role-id fix

`internal_upsert.go` hardcoded `rol00000000000000iamad` — pre-KAC-122 deterministic seed. KAC-122 migration 0008 reseed'нул role IDs на MD5-based hashes. Switched to `rol21232f297a57a5a74` (=MD5("admin")[:17] per migration).

## VPC/Compute deferred to KAC-126

Probe revealed: **vpc/compute не знают про IAM-ресурс ownership**. Network.Delete by id — repo.Get finds network → delete proceeds. Без IAM-lookup мы не можем check ownership на vpc/compute level.

Это **architectural gap**: real fix — Keto cascade (owner-of-project → owner-of-network/disk/etc.). KAC-126 task.

Short-term mitigation: anti-anon работает (anonymous denied). Authenticated users могут писать в любой project — limitation deferred.

## Deployed Images

```
kacho-iam:         ttl.sh/kac122-iam-fix11-<ts>/kacho-iam:24h
kacho-vpc:         ttl.sh/kac122-vpc-fix3-<ts>/kacho-vpc:24h (PrincipalExtract added)
kacho-compute:     ttl.sh/kac122-cmp-fix3-<ts>/kacho-compute:24h (PrincipalExtract added)
kacho-api-gateway: ttl.sh/kac122-apigw-<ts>/kacho-api-gateway:24h (strip headers)
```

## Roadmap KAC-126 (full ReBAC)

1. Implement `InternalIAMService.Check` (Keto-backed)
2. Keto namespaces для cross-service resource ownership (vpc:network owned-by project owned-by account)
3. Replace `RequireOwnerMatchesPrincipal` с Keto Check (per-RPC permission_map)
4. Add `OwnerUserID` к repo ListFilter → SQL-level scope-filter (vs current in-memory post-filter)
5. Implement Service-Account авторизация (key-based JWT)
6. Group cascade (user member-of-group → group binding granted)

## Pattern Summary

| Operation Type | Defense |
|---|---|
| Mutation Create | anti-anon interceptor + per-use-case `RequireOwnerMatchesPrincipal` |
| Mutation Update/Delete | load → resolve owner → ownership-check |
| Mutation AccessBinding | self-grant + owner-of-resource |
| Read Get | scope-filter (NotFound if not owner) |
| Read List | scope-filter (post-filter в Go OR repo-WHERE) |
| Anonymous | always denied на mutations; List → empty; Get → NotFound |
