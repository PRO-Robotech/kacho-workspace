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
verified_against: "координаты записки (файл эмиссии, канонический .fga, цель регенерации) сверены с деревом продукта 1653387b (2026-08-06); состав отношений модели построчно не пересматривался — канон читать в proto"
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

## Emit (kacho-iam, `internal/apps/kacho/api/access_binding/tuples.go`)

> [!note] Координата поправлена по дереву (1653387b, 2026-08-06)
> Отдельного файла под эмиссию scope-grant'ов нет; его прежнее имя здесь не
> воспроизводится в обратных кавычках — цитата несуществующего файла читается как живое
> утверждение о дереве и потому сама числится находкой хука свежести. Эмиссия живёт в
> `tuples.go` того же каталога (рядом — `scope_coordinate.go` и
> `role_tuple_reconciler.go`).

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

FGA model must be **re-bootstrapped** (new model id) on deploy: цель `openfga-model-json`
(она живёт в `deploy/Makefile` монорепо, а не в отдельном репозитории развёртывания)
перегенерирует configmap из канонического `proto/kacho/cloud/iam/v1/fga_model.fga`, и
bootstrap-job перезаписывает модель. JSON модели — **производный** артефакт: отслеживаемого
файла с этим именем в дереве нет (`git ls-files | grep -c model.json` → 0), поэтому и само
имя здесь координатой не приводится — иначе строка, объясняющая «файла нет», сама читалась
бы как утверждение, что он есть. Old anchor-tier relations stay valid in the rollback window
(additive).

## See also

[[iam-to-openfga-check]] [[iam-to-openfga-grant-write]] [[../resources/iam-access-binding]] [[../resources/iam-role]] [[../KAC/KAC-186]]

#edge #kacho-iam #kacho-proto #cross-service #rebac #done
