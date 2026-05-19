# KAC-122 Iteration 1 — Fixes Report (2026-05-19)

**Цикл**: probe → fix → deploy → re-probe → fix newly-found. Этот документ —
снимок состояния после первой итерации.

## 1. Закрытые findings

| # | Finding | Severity | Fix | Verified |
|---|---|---|---|---|
| CRIT-1 | anonymous Account.Create с произвольным owner | CRITICAL | anti-anon interceptor + `RequireAuthenticated` в Account.Create | ✅ 403 |
| CRIT-2 | anonymous AccessBinding.Create iam.admin → escalation | CRITICAL | anti-anon + `RequireSelfGrant` | ✅ 403 |
| CRIT-3 | NOB (authenticated) Account.Create с victim'ом как owner | CRITICAL | `RequireOwnerMatchesPrincipal` | ✅ 403 |
| CRIT-3' | NOB cross-grant роли другому user'у | CRITICAL | `RequireSelfGrant` (subject_id == principal.ID) | ✅ 403 |
| CRIT-4 | anonymous Project.Create в чужой Account | CRITICAL | anti-anon interceptor | ✅ 403 |
| CRIT-5 | anonymous ServiceAccount.Create | CRITICAL | anti-anon interceptor | ✅ 403 |
| CRIT-6 | anonymous VPC Network.Create через breakglass=true | CRITICAL | corelib `isAnonymousSubject` в breakglass path | ✅ 403 |
| CRIT-7 | anonymous Compute Disk.Create через breakglass=true | CRITICAL | corelib breakglass anti-anon | ✅ 403 |
| **CRIT-8** | **HEADER INJECTION** — client-supplied X-Kacho-Principal-* | **CRITICAL** | api-gateway HTTP middleware + gRPC interceptor strip incoming | ✅ 403 |
| HIGH-1 | `User.List` без accountId возвращал ВСЕХ users | HIGH | `authzguard.IsAnonymous` ловит system+bootstrap fallback | ✅ empty |
| HIGH-3 | anonymous Role.Create с iam.*.* permissions | HIGH | anti-anon interceptor | ✅ 403 |

**Итого: 7 CRITICAL + 2 HIGH закрыты на live стенде.**

## 2. Реализация (по файлам)

### kacho-iam

| Файл | Изменение |
|---|---|
| `internal/authzguard/authzguard.go` | Новый пакет: `IsAnonymous`, `RequireAuthenticated`, `RequireOwnerMatchesPrincipal`, `RequireSelfGrant` |
| `internal/authzguard/interceptor.go` | gRPC unary+stream interceptor: reject anonymous на mutating RPC (suffix matcher) |
| `cmd/kacho-iam/main.go` | Wiring anti-anon interceptor на public listener (internal — bypass, network-segregated) |
| `internal/apps/kacho/api/account/create.go` | `RequireAuthenticated` + `RequireOwnerMatchesPrincipal` |
| `internal/apps/kacho/api/project/create.go` | `RequireAuthenticated` |
| `internal/apps/kacho/api/group/create.go` | `RequireAuthenticated` |
| `internal/apps/kacho/api/service_account/create.go` | `RequireAuthenticated` |
| `internal/apps/kacho/api/role/create.go` | `RequireAuthenticated` |
| `internal/apps/kacho/api/access_binding/create.go` | `RequireAuthenticated` + `RequireSelfGrant` |
| `internal/apps/kacho/api/user/list.go` | Используем canonical `authzguard.IsAnonymous` (HIGH-1) |

### kacho-corelib

| Файл | Изменение |
|---|---|
| `authz/interceptor.go` | Breakglass path: reject anonymous через `isAnonymousSubject()` |
| `authz/subject_extract.go` | Helper `isAnonymousSubject` (closed-list match: empty / anonymous / bootstrap / system:anonymous / system:bootstrap) |

### kacho-api-gateway

| Файл | Изменение |
|---|---|
| `internal/middleware/auth.go::HTTP` | Strip incoming `X-Kacho-Principal-*` / `Grpc-Metadata-X-Kacho-Principal-*` HTTP headers ДО auth-flow (CRIT-8 HTTP path) |
| `internal/middleware/auth.go::authorize` | Strip incoming x-kacho-principal-* gRPC metadata (CRIT-8 gRPC-proxy path) |
| `internal/proxy/shimproxy.go` | Local stub взамен удалённого `kacho-yc-shim/shimproxy` |
| `internal/proxy/server.go` | Use local shimproxy.MethodResolver |
| `cmd/api-gateway/main.go` | Drop yc-shim imports + remove `endpointpb.RegisterApiEndpointServiceServer` / `iampb.RegisterIamTokenServiceServer` (yc CLI compat deprecated) |
| `go.mod` / `Dockerfile` | Remove kacho-yc-shim dependency |

## 3. Что осталось (TODO для KAC-126 / next iter)

| Risk | Описание | Severity | Mitigation план |
|---|---|---|---|
| **NOB self-grant без real enforcement** | NOB может create binding row `{subject:self, role:iam.admin, resource:any}` — без Keto enforcement binding бесполезен, но если/когда Keto switched on без bootstrap-tuples cleanup, эти rows могут стать live grants | HIGH (latent) | KAC-126 ReBAC v2: Keto-Check before AccessBinding.Create (`principal admin/owner на resource`) |
| **Project/Group/SA/Role.Create не проверяют ownership account_id** | NOB authenticated может create Project в чужом account (только anti-anon, нет per-resource Keto-Check) | MEDIUM | KAC-126: per-RPC permission_map с проверкой `principal admin on account_id` |
| Update/Delete handlers на existing ресурсах | NOB может Update/Delete чужие ресурсы (anti-anon пропускает; нет ownership-check) | MEDIUM | KAC-126: Keto-Check + scope-filter (404 если не member) |
| Operation.Get на чужие операции | Может leak'ать info о чужих ops | MEDIUM | Scope-filter в Operation.Get repo |
| AddressPool на public listener | Admin-only ресурс exposed | HIGH | api-gateway listener split (KAC-126) или NetworkPolicy |
| gRPC reflection на public listener | Info leak — schema discovery | MEDIUM | reflection.Register только на internal listener |
| HTTP method override / large body DoS | Не нашли активных, но рекомендуется hardening | LOW | rate-limit middleware + max-body-size |

## 4. Deployed images

```
kacho-iam:      ttl.sh/kac122-fix3-<ts>/kacho-iam:24h
kacho-vpc:      ttl.sh/kac122-vpc-<ts>/kacho-vpc:24h
kacho-compute:  ttl.sh/kac122-cmp-<ts>/kacho-compute:24h
kacho-api-gateway: ttl.sh/kac122-apigw-<ts>/kacho-api-gateway:24h
```

Все 4 deployed на stand `e2c825` (namespace `kacho`). `breakglass=true` на
vpc/compute (с corelib fix — semantically "all-authenticated-allowed").

## 5. Open PRs

- workspace [#20](https://github.com/PRO-Robotech/kacho-workspace/pull/20) (KAC-122 base — newman suite, design, original matrix)
- vpc [#102](https://github.com/PRO-Robotech/kacho-vpc/pull/102) (newman cases)
- iam [#12](https://github.com/PRO-Robotech/kacho-iam/pull/12) (newman cases)
- compute [#25](https://github.com/PRO-Robotech/kacho-compute/pull/25) (newman cases)
- **NEW iam [#13](https://github.com/PRO-Robotech/kacho-iam/pull/13)** — authzguard + interceptor + per-use-case guards (CRIT-1..5 + HIGH-1/3 fix)
- **NEW corelib [#9](https://github.com/PRO-Robotech/kacho-corelib/pull/9)** — breakglass anti-anon (CRIT-6/7)
- **NEW api-gateway [#18](https://github.com/PRO-Robotech/kacho-api-gateway/pull/18)** — CRIT-8 strip-headers + yc-shim drop

Все 4 newman CI зелёные ✅; новые security-fix PR'ы — на review.

## 6. Iterate-loop (per user goal)

Этот документ — снимок iter-1. После merge новых PR'ов — следующая итерация:

1. Re-probe API на ещё-не-найденные vectors:
   - Operations.Get на чужие ops
   - Update/Delete с чужими id
   - SQL/JSON injection через filter param
   - Pagination token forgery
   - Outbox stream subscription без auth
2. Если find — fix → deploy → re-probe.

Это работа KAC-126 (ReBAC v2) ground.
