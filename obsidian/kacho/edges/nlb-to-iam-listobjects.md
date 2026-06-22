---
title: "nlb → iam: AuthorizeService.ListObjects"
aliases:
  - nlb listobjects
  - nlb fga listobjects
  - nlb list-filter
category: edge
caller_repo: kacho-nlb
callee_repo: kacho-iam
sync_async: sync
protocol: gRPC
status: done
related_tickets:
  - "[[rbac-rules-model-2026-subphase-D-nlb-consumer]]"
tags:
  - edge
  - kacho-nlb
  - cross-service
  - authz
  - fga
---

# nlb → iam: AuthorizeService.ListObjects

**Caller**: `kacho-nlb` List use-cases (NetworkLoadBalancer / Listener / TargetGroup — 3 public List* RPCs).
**Callee**: `kacho-iam` AuthorizeService.ListObjects ([[../rpc/iam-authorize-service]]) — **public** listener (:9090), reuse `iamPublicConn` (тот же, которым nlb зовёт `ProjectService.Get`).
**Protocol**: gRPC, sync, request-path.
**Status**: **DONE** (RBAC sub-phase D §11, GitHub workspace issue [#111](https://github.com/PRO-Robotech/kacho-workspace/issues/111) — D-consumer; ≠ YouTrack KAC-111 vpc-squash). Mirror of [[compute-to-iam-listobjects]] для nlb-домена.

## Object types + action (D-consumer)

Consumer передаёт `(subject, resource_type, action)` — iam-сервер сам резолвит action в FGA relation (`v_list`, каскадит из `viewer`/`scope_grant`, та же tuple-база, что per-RPC Check). Consumer НЕ передаёт relation напрямую.

| Object type (`resource_type`) | action (`<domain>.<resource>.list`) |
|---|---|
| `lb_network_load_balancer` | `loadbalancer.networkLoadBalancers.list` |
| `lb_listener` | `loadbalancer.listeners.list` |
| `lb_target_group` | `loadbalancer.targetGroups.list` |

> [!important] verb=`list` ⇒ read==enforce
> action-verb — **`list`** (НЕ `read`): iam мапит на ту же relation-семантику, что per-RPC Check на `Get` (relation `viewer`/`v_list`, одна materialized tuple-база) ⇒ **read==enforce** паритет (D-45). FGA object-type префикс — `lb_` (НЕ `nlb_`), совпадает с `fga_model.fga` (KAC-178 §2).

## Flow per-request

1. List use-case извлекает subject из ctx (`operations.PrincipalFromContext` → `domain.FGASubjectFromPrincipal` → `user:…`/`service_account:…`; system/anon → `""` → bypass).
2. `authzfilter.Resolve(ctx, filter, resourceType, action)` → `iam.AuthorizeService.ListObjects` (ctx обёрнут `auth.PropagateOutgoing` — иначе iam видит `system:bootstrap` и отбивает).
3. Decision → `filter.AllowedIDs` → repo `WHERE id = ANY($allowed)` **ВНУТРИ SQL ДО LIMIT** → pagination плотная по отфильтрованному набору (D-46, LST-6).
4. Empty grant → `[]` (no-leak, не ошибка). `wildcard_grant=true` (KAC-214) → bypass (все строки).

## Failure modes

- **iam down / ListObjects error** → `UNAVAILABLE` (fail-closed, D-47; `FailOpen=false` default, security.md). НЕ нефильтрованный список.
- **Get вне гранта** → `NOT_FOUND` (no-leak, D-44) — обеспечивается **существующим** per-RPC Check ([[nlb-to-iam-check]], relation `viewer`, `no-path`→DecisionNoPath→404), НЕ этим ребром. List-фильтр и Get-Check используют одну tuple-базу ⇒ read==enforce.

## Config / cache

- Toggle `authz.list-filter.enabled` (default **true**; `KACHO_NLB_AUTHZ__LIST_FILTER__ENABLED`). disabled / нет iam conn → use-case'ы делают unfiltered project-scoped passthrough.
- In-proc decision-cache 5s TTL keyed `(subject, resourceType, action)`, bound 10000, MaxResults cap 10000.
- mTLS — через `mtls.iam-project` (тот же conn, что ProjectService.Get).
- CI-гейт `make audit-list-filter` (`tools/audit-list-filter.sh`) — каждый `<res>/list.go` обязан нести `authzfilter.Filter` + `authzfilter.Resolve(`.

## Notes

- **НЕ новое cross-service ребро**: `nlb → iam` уже существует ([[nlb-to-iam-check]] / [[nlb-to-iam-fga-register]]); это расширение по тому же `iamPublicConn`. Цикла нет (iam не зовёт nlb обратно по этому пути; D-13 lifecycle — отдельный iam→nlb subscribe).
- Package: `internal/authzfilter/` (Filter port + FGAFilter + BypassFilter + iam_authorize_client + actions + subject; зеркало `kacho-compute/internal/authzfilter`).

## See also

[[compute-to-iam-listobjects]] [[vpc-to-iam-listobjects]] [[nlb-to-iam-check]] [[api-gateway-to-iam-authorize]] [[../rpc/iam-authorize-service]] [[../rpc/nlb-network-load-balancer-service]] [[../KAC/rbac-rules-model-2026-subphase-D-iam]] [[../KAC/rbac-rules-model-2026-subphase-D-nlb-consumer]]

#edge #kacho-nlb #cross-service #authz #fga
