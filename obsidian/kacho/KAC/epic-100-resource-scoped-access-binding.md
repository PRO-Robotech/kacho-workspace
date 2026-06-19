---
ticket_id: epic-100
status: in-progress
type: epic
repos:
  - kacho-proto
  - kacho-iam
  - kacho-api-gateway
  - kacho-ui
prs:
  - "https://github.com/PRO-Robotech/kacho-proto/pull/65"
  - "https://github.com/PRO-Robotech/kacho-iam/pull/165"
  - "https://github.com/PRO-Robotech/kacho-api-gateway/pull/88"
  - "https://github.com/PRO-Robotech/kacho-ui/pull/96"
yt_url: "https://github.com/PRO-Robotech/kacho-workspace/issues/100"
opened: 2026-06-19
closed:
tags:
  - kac
  - epic
  - kacho-iam
  - feature
---

# epic-100 — Resource-scoped AccessBinding (target-в-binding)

> [!note] Трекинг
> YouTrack KAC недоступен в сессии → эпик-трекинг через GitHub Issue
> `PRO-Robotech/kacho-workspace#100` (метка `epic`). Per-repo issues:
> proto#64, iam#164, api-gateway#87, ui#95. Ветка во всех репо:
> `epic100-resource-scoped-ab-alpha`.

## Status
`in-progress` (sub-phase α — реализация).

## Что и зачем
Дать доступ к **конкретному** ресурсу в рамках одного `AccessBinding`, без
выпечки одноразовой custom-роли на каждый объект. Role → чистый verb-bundle
(`module.resource.*.verb`); конкретику даёт новое поле `AccessBinding.target`
(oneof). Корень боли — 4-сегментная грамматика permission (KAC-214/216)
склеила «что можно» (reusable Role) и «над чем» (instance-specific).

## Декомпозиция
- **α (текущая):** `target` oneof — рабочие `all_in_scope` + `resources[]`;
  `selector` forward-declared (`UNIMPLEMENTED`). Три детерминированных гейта на
  Create: (1) 1.5 `IsRoleAssignable` scope-tier, (2) role-coverage
  `target.type ⊆ role-types`. Containment → γ.
- **β:** governance-managed IAM Tags (`Tag`/`TagBinding`, permission
  `iam.tags.bind`) — НЕ resource labels (privilege-escalation).
- **γ:** рабочий `selector` + materialized reconciler (selector→per-object FGA
  tuples, outbox, eager-revoke) + target-containment.

## Арх-инварианты (зафиксированы)
- **НЕТ ребра `iam→compute`/`iam→vpc`** — был бы цикл (`compute→iam`/`vpc→iam`
  уже есть). `target.id` — opaque soft-ref без existence/containment (как
  сегодняшний `resource_id`, запрет #8); dangling graceful.
- Membership (γ) — **materialized reconciler**, не lazy-на-Check (poll-модель,
  нет fan-out на authz-пути).
- Теги (β) — governance-managed IAM-слой, не resource labels.
- FGA-эмиссия переиспользует `fga_tuple_writer_v2.go` §3.5; источник
  `resourceName` = `binding.target`, не `role.permissions`.

## Acceptance
α APPROVED — `docs/specs/epic-resource-scoped-access-binding-alpha-acceptance.md`
(acceptance-reviewer, 2026-06-19; 25 сценариев `α-NN`, решения D-1..D-15).

## Затронутые сущности vault
- [[../resources/iam-access-binding]] — новое поле `target` (oneof), таблица
  `access_binding_targets`, role-coverage гейт.
- [[../resources/iam-role]] — Role → verb-bundle (`resourceName` уходит в target).
- [[../rpc/iam-access-binding-service]] — +3 RPC (AddTargetResources /
  RemoveTargetResources / ListGrantableResources).
- [[../packages/iam-domain]] — `AccessTarget`, role-coverage предикат.

### UI (kacho-ui, ui#95)
- `src/api/iam.ts` — типы `AccessTarget`/`TargetResourceRef`/`GrantableResource`,
  `AccessBinding.target`; helpers `listGrantableResources` / `addTargetResources`
  / `removeTargetResources`. Wire camelCase: `{target:{allInScope:{}}}` |
  `{target:{resources:{resources:[{type,id}]}}}`; query camelCase
  `scopeType/scopeId/objectType`.
- `src/lib/iam-target-types.ts` (новый) — closed-table object-type metadata
  (зеркало `authzmap/fga_types.go`) + `parseTarget` (legacy/без target →
  all_in_scope, D-8) + `isIamObjectType` (iam → picker, non-iam → ручной ввод id).
- `src/components/iam/AccessBindingCreateForm.tsx` — секция «Цель» (α-06):
  Radio all_in_scope/resources; object-picker (α-07): listGrantableResources для
  iam-типов, tags-input для non-iam (D-14); submit кладёт `target` в Create.
- `src/components/iam/TargetResourcesPanel.tsx` (новый) — add/remove target на
  detail-странице resources-binding'а (опц. 4-й пункт).
- `src/lib/resource-registry.tsx` + `src/components/resource-detail-extensions.tsx`
  — колонка/строка «Цель» (α-20, устойчиво к legacy).

## DoD-чеклист (α)
- [x] proto: `AccessTarget` oneof + 3 RPC, buf lint/breaking/generate (proto#64 → PR #65, proto-api-reviewer APPROVED)
- [x] iam: migration 0018 + domain + repo + use-case + handler + fga + outbox;
      integration+newman (iam#164 → PR #165). Docker недоступен локально → integration/newman прогон в CI.
- [x] api-gateway: регистрация 3 public RPC (gw#87 → PR #88)
- [x] ui: target-mode + object-picker + display (ui#95) — код-комплит на ветке
      `epic100-resource-scoped-ab-alpha`; build+typecheck зелёные; 23 vitest
      зелёные (включая α-06/07/20 + parseTarget). Визуальная проверка на стенде —
      follow-up при деплое.
- [x] reviews: proto-api (APPROVED) / db-architect / system-design / go-style — все находки закрыты
- [ ] vault trail обновлён + status → test/done (после merge + CI green)
- [ ] CI: revert kacho-proto pin `ref: epic100-...` → `ref: main` (во всех iam+gateway workflows) после merge proto#65

## Связанные
[[KAC-127]] (lifecycle AccessBinding), [[KAC-214]] (RBAC v2 grammar / FGA emission).
