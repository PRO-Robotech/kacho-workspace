---
ticket_id: epic-103
status: in-progress
type: epic
repos:
  - kacho-proto
  - kacho-compute
  - kacho-iam
  - kacho-ui
prs:
  - "https://github.com/PRO-Robotech/kacho-proto/pull/67"
  - "https://github.com/PRO-Robotech/kacho-compute/pull/59"
  - "https://github.com/PRO-Robotech/kacho-iam/pull/168"
yt_url: "https://github.com/PRO-Robotech/kacho-workspace/issues/103"
opened: 2026-06-19
closed:
tags:
  - kac
  - epic
  - kacho-iam
  - feature
---

# epic-103 — Resource-scoped AccessBinding β/γ/condition/δ

Продолжение [[epic-100-resource-scoped-access-binding]] (α DONE, live fe3455 rev27).
Финальная модель — 5 измерений:
`{ subject, role(verb-bundle), scope{tier,id}, target<all|byName|bySelector>, condition<none|expiry|forward> }`.

## Зафиксированные решения (только прод-код / best-2026 / польза)
- **D1 containment** — hybrid sync+eventual (объект в mirror → sync-гейт; не в mirror →
  `PENDING_VERIFICATION` + eventual verify reconciler'ом; не под scope → REJECTED+audit, не silent). γ.
- **D2 target mutable** — subject/role/scope immutable; target mutable (byName add/remove есть, selector `ReplaceTargetSelector` CAS). γ.
- **D3 δ** — аддитивная non-breaking чистка формы (`scope{tier,id}` + `target.all/byName/bySelector`; старые поля deprecated через проекцию). Отдельная волна.

## Под-фазы

### β — label+parent sync (DONE 2026-06-19) ✅
proto#67 / compute#59 / iam#168 — merged, live fe3455 helm **rev28** (compute `main-b545a45e`,
iam `main-8e486763`, migration 0019 `resource_mirror` applied → version 19).
- `RegisterResource`/`Unregister` += `labels`, `parent_project_id`, `parent_account_id`, `source_version`.
- compute: emit на Instance Create + Update(labels-mask); Disk/Image/Snapshot несут labels.
- iam: `resource_mirror` UPSERT co-commit с owner-tuple (ban #10); **monotonic `source_version`**
  (last-source-state-wins — закрыл system-design lost-update finding, no tech-debt).
- Ревью: proto-api / db-architect / system-design / go-style — все APPROVED.
- Затронутые vault: [[../resources/iam-resource-mirror]] (NEW), [[../edges/compute-to-iam-fgaproxy]], [[../rpc/iam-internal-iam-service]].

### γ — reconciler (NEXT)
снять `UNIMPLEMENTED` с `bySelector`; reconciler `matchLabels` по mirror → per-object FGA
tuples (+hierarchyParentTuple); **containment** hybrid (D1, дополнить parent_account_id из
`projects.account_id` same-DB); **expiry** eager-revoke (`condition=non_expired`); Delete-после-Update
reconcile-sweep dangling. `match_tags`→`match_labels` rename (γ, pre-activation, 0 wire-clients).

### condition — 5-е измерение (с γ)
oneof в модель; прокид в conditional-tuples (`ConditionalTuple.Condition` инфра есть); рабочий
только `non_expired`(TTL→eager-revoke); прочие builtin schema-only forward.

### δ — чистая форма (отдельная волна, после γ)
`scope{tier,id}` + `target.all/byName/bySelector` канонические; старые поля deprecated/проекция.

## DoD
- [x] β: proto+compute+iam merged + fe3455 rev28 + migration 0019
- [ ] γ: reconciler + containment + expiry → fe3455
- [ ] condition: non_expired рабочий
- [ ] δ: чистая форма non-breaking
- [ ] CI proto-pin reverted (β — сделано)

## Связанные
[[epic-100-resource-scoped-access-binding]] (α), [[KAC-127]] (lifecycle), [[KAC-214]] (RBAC v2 FGA).
