---
title: "iam → openfga: type-scoped scope_grant + per-verb (fix #177)"
aliases:
  - scope_grant
  - per-verb fga
  - escalation-177
category: edge
caller_repo: kacho-iam
callee_repo: openfga
sync_async: async
protocol: gRPC
status: done
related_tickets:
  - "[[KAC-186]]"
tags:
  - edge
  - kacho-iam
  - kacho-proto
  - cross-service
  - rebac
  - done
---

# iam → openfga: type-scoped `scope_grant` + per-verb (fix #177)

RBAC rules-model 2026 **sub-phase B** (PRO-Robotech/kacho-iam#186, closes #177).
Closes the escalation-engine: an `all_in_scope` role grant no longer collapses the
whole role to its strongest tier on the **bare** `account:X` / `project:X` anchor
(which cascaded `admin from account` onto EVERY type). Instead it emits a
**type-scoped `scope_grant`** that cascades the tier / per-verb relations **only
onto its own object type** within the scope.

## FGA model (`kacho-proto/.../iam/v1/fga_model.fga`) — strictly additive

- **New leaf type `scope_grant`** — object id = `"<anchorType>|<anchorId>|<objType>"`
  (e.g. `scope_grant:account|acc_A|compute_instance`). Pipe `|` is illegal in Kacho
  ids/types ⇒ unambiguous 3-field split. Carries directly-assignable relations:
  `viewer/editor/admin` (back-compat tier) + `v_get/v_list/v_create/v_update/v_delete`
  (per-verb). No `from` → leaf, no tuple cycle.
- **Anchor types** (`cluster`/`account`/`project`): per resource type a
  directly-assignable `sg_<rt>: [scope_grant]` pointer (linking tuple lands here) +
  grant **resolvers** `g_<tier>_<rt>` / `g_v<verb>_<rt>` = `<rel> from sg_<rt> or
  <resolver> from <broader anchor>` (pull-up: cluster⊃account⊃project).
- **Resource types**: tier disjuncts gain `or g_<tier>_<rt> from <parent>` (tupleset =
  the pure-direct hierarchy parent pointer — OpenFGA forbids a TTU-bearing tupleset).
  Per-verb `v_<verb>: [user,service_account,group#member] or g_v<verb>_<rt> from
  <parent>` — directly-assignable (ARM_NAMES writes a per-object tuple) AND cascades
  from the scoped grant. `v_*` deliberately does NOT cascade `or <tier>` (else a
  back-compat editor tier would satisfy `v_update` and defeat delete≠create).
- `lb_listener` (nested under `lb_network_load_balancer`) gets pass-through resolvers
  from its parent's project chain.

## Emit (kacho-iam `access_binding/scope_grant_tuples.go`)

`rulesBindingTuples(b, role)` dispatched from `buildBindingTuples` when `role.Rules`
is non-empty (legacy permission-only roles keep the old path). Per rule, per arm:

- **ARM_ANCHOR** → linking `account:X#sg_<objType>@scope_grant:<key>` + per-verb
  `scope_grant:<key>#v_<verb>@subj` (granted verbs only) + back-compat tier
  `scope_grant:<key>#<tier>@subj` (per-rule strongest verb-class, NOT whole-role).
  `verbs:["*"]` → full closed per-verb set (O-3, bounded).
- **ARM_NAMES** → per-object `<objType>:<id>#v_<verb>@subj` + tier `<objType>:<id>#<tier>@subj`.
- **ARM_LABELS** → suppressed (materialization is sub-phase C, fix #8).
- `*.*` system superuser @ CLUSTER → `cluster:root#system_admin@subj` (unchanged).

Verb→tier (back-compat, mirrors `resolveActionToRelation`): get/list→viewer,
create/update→editor, **delete→admin**.

## Back-compat

Strictly additive. Tier relations (`viewer/editor/admin`) preserved ⇒ consumer Check
(`vpc/compute/geo/nlb` via `resolveActionToRelation`) unchanged. Per-verb consumer-Check
migration is a SEPARATE scope (not in B). Revoke is symmetric via the `#178` emitted-set
ledger (`access_binding_emitted_tuples`) — no re-derive.

## Deploy

FGA model must be **re-bootstrapped** (new model id) on deploy: `kacho-deploy`
`make openfga-model-json` regenerated the configmap (`.fga` + transformed `model.json`),
the bootstrap job re-writes the model. Old anchor-tier relations stay valid in the
rollback window (additive).

## See also

[[iam-to-openfga-check]] [[iam-to-openfga-grant-write]] [[../resources/iam-access-binding]] [[../resources/iam-role]] [[../KAC/KAC-186]]

#edge #kacho-iam #kacho-proto #cross-service #rebac #done
