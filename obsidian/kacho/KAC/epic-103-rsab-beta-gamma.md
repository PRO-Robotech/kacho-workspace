---
ticket_id: epic-103
status: done
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
  - "https://github.com/PRO-Robotech/kacho-proto/pull/69"
  - "https://github.com/PRO-Robotech/kacho-iam/pull/171"
  - "https://github.com/PRO-Robotech/kacho-api-gateway/pull/90"
  - "https://github.com/PRO-Robotech/kacho-ui/pull/98"
yt_url: "https://github.com/PRO-Robotech/kacho-workspace/issues/103"
opened: 2026-06-19
closed: 2026-06-19
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

### δ — DONE ✅ (2026-06-19, live fe3455 rev30) — чистая форма
proto#71 / iam#174 / ui#100 merged (api-gateway — no-op, поля проходят generic).
Образы iam `main-5db25bf6`, ui `main-6766f623`. δ — форма-only (без миграций).
- proto: `ScopeRef{tier,id}` (scope_ref) + `AccessTargetRef{all|by_name|by_selector}`
  (target_ref) — **отдельные поля** (не arms-в-oneof, чтобы конфликт legacy≠canonical
  был wire-distinguishable, δ-04); legacy resource_type/resource_id/scope/target —
  comment-deprecated (заполняются на чтении для pre-δ клиентов; удаление = future major).
- iam: двусторонняя проекция в handler/dto (Dδ8 форма-over-data, без domain/repo/migration):
  Create принимает обе формы (canonical приоритет, конфликт старое≠новое → INVALID_ARGUMENT,
  derived-equivalent OK); Get/List заполняют ОБА представления; pre-δ binding read-time.
  targetsEqual order-insensitive (no false δ-04 on reorder).
- ui: Create шлёт canonical scopeRef/targetRef; read canonical-preferred + legacy fallback.
- Ревью: proto-api / go-style — APPROVED. condition-форма (5-е измерение явный oneof) —
  отложено в **ε** (condition_id field-9 уже populated, oneof не выразим без breaking; non_expired уже работает).
- Smoke fe3455: canonical форма принята (401 authN, не 400-unknown-field).

## DoD
- [x] β: proto+compute+iam merged + fe3455 rev28 + migration 0019
- [x] γ: reconciler + containment + expiry + ReplaceTargetSelector → fe3455 rev29 (migrations 0020-0022; proto#69/iam#171/gw#90/ui#98)
- [x] condition: `non_expired` рабочий (expiry eager-revoke в γ); прочие builtin — schema-forward (ε)
- [x] δ: чистая форма non-breaking (scope_ref/target_ref + двусторонняя проекция) → fe3455 rev30 (proto#71/iam#174/ui#100)
- [x] CI proto/gateway-pin reverted (β + γ + δ — сделано)
- [x] **ЭПИК ЗАВЕРШЁН** — α+β+γ+δ live fe3455. Открытые follow: #170 (reconcile_outbox TTL), `ListTargetMembers` RPC (γ-07 UI бейджи), #173 (Scope.ResourceType dedup), condition-форма (ε)

## Связанные
[[epic-100-resource-scoped-access-binding]] (α), [[KAC-127]] (lifecycle), [[KAC-214]] (RBAC v2 FGA).
