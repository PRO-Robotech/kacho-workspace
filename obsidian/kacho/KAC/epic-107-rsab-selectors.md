---
ticket_id: epic-107
status: done
type: epic
repos:
  - kacho-iam
  - kacho-vpc
  - kacho-nlb
  - kacho-ui
prs:
  - "https://github.com/PRO-Robotech/kacho-iam/pull/176"
  - "https://github.com/PRO-Robotech/kacho-vpc/pull/160"
  - "https://github.com/PRO-Robotech/kacho-nlb/pull/34"
  - "https://github.com/PRO-Robotech/kacho-ui/pull/103"
  - "https://github.com/PRO-Robotech/kacho-ui/pull/101"
yt_url: "https://github.com/PRO-Robotech/kacho-workspace/issues/107"
opened: 2026-06-20
closed: 2026-06-20
tags:
  - kac
  - epic
  - kacho-iam
  - feature
---

# epic-107 — RSAB selectors all-services + type-dedup + role-grouping

Продолжение [[epic-103-rsab-beta-gamma]] (α/β/γ/δ live fe3455 rev30). Распространяет
selector на ВСЕ домены + устраняет дубли формы. **DONE, live fe3455 rev32 (2026-06-20).**

## Треки

### T2 — role-grouping (ui#101) ✅
`RolesPage` плоский список ~70 system-ролей → `Collapse`-секции по module
(IAM/VPC/Compute/Load Balancer/Geography) + module-фильтр; system/custom табы сохранены.

### T1 — type-dedup: selector.types выводимы из роли (iam#176, ui#103) ✅
Был дубль «тип в роли (permissions→RoleCoversType) vs `selector.types`». Теперь:
- `selector.types` ОПЦИОНАЛЬНЫ → derive из role-coverage (concrete-типы permissions ∩
  selectableTypes; `domain.DeriveSelectorTypes`). wildcard-роль + пустые types →
  sync `INVALID_ARGUMENT` (нельзя вывести «все»). mixed-роль → concrete, wildcard игнор.
- explicit types → текущий γ-гейт (⊆ role-coverage). matchLabels НЕ ослаблен.
- ui: bySelector types опциональны (hint про derive); `Get` отдаёт эффективный derived-набор.

### T3 — selectors all-services (iam#176, vpc#160, nlb#34) ✅
γ-selector (был только compute.instance) → все mirror-fed + iam-direct:
- **reconciler feed-generalize:** per-type дескриптор `domain.FeedSourceForType` →
  `{MIRROR | IAM_DIRECT; containment-rule}`. Не hardcode compute.instance.
- **selectableTypes:** compute.{instance,disk,image,snapshot} + vpc.{network,subnet,
  securityGroup,routeTable,address,gateway,networkInterface} + loadbalancer.{networkLoadBalancers,
  targetGroups,listeners} + iam.{project,account}.
- **vpc/nlb label-emit:** Network/Subnet (vpc), NLB/TargetGroup (nlb) эмитят labels+parent
  в `RegisterResource` на Create + Update(labels-mask) → `resource_mirror` (зеркало compute β).
- **iam-direct (project/account):** reconciler матчит iam-таблицы НАПРЯМУЮ (labels @> matchLabels,
  same-DB, НЕ через mirror, НЕТ self-ребра iam→iam); containment iam-hierarchy; no-PENDING.
  Project/Account.Update(labels) → reconcile-outbox event в writer-tx.
- GIN 0023 на projects/accounts.labels (jsonb_path_ops); reconcile binding `FOR UPDATE`
  (сериализация, no dup tuple-emit).

### T4 — postman byName+bySelector (iam#176) ✅
17 newman-кейсов: byName (vpc/nlb/iam) + bySelector (compute/vpc/nlb/iam) + T1 derive +
coverage/non-selectable negatives. Устаревшие γ-кейсы (vpc.subnet был «non-selectable»)
обновлены (→ iam.group/iam.user; EMPTY-TYPES retired т.к. T1 разрешил derive).

## Арх-инварианты (подтверждены ревью)
- **Ацикличность:** vpc→iam/nlb→iam — расширение payload существующих RegisterResource-рёбер
  (НЕ новые); iam-direct — same-DB (НЕТ ребра iam→iam). Циклов нет (system-design APPROVED).
- No dual-write (reconcile/Update/Register — single writer-tx). Idempotent (β monotonic
  source_version + FOR UPDATE + ON CONFLICT). Containment per feed-source same-DB.
- Ревью: db-architect / system-design / go-style / proto-api — все APPROVED, находки закрыты.

## DoD
- [x] T2 role-grouping → ui#101 (rev31)
- [x] T1 type-dedup → iam#176 + ui#103 (selector.types derive)
- [x] T3 selectors all-services → iam#176 (reconciler-generalize + iam-direct + GIN 0023) + vpc#160 + nlb#34 (label-emit)
- [x] T4 postman byName+bySelector all-domains → iam#176 (17 cases)
- [x] live fe3455 **rev32**: iam `main-2b4d92a0`, vpc `main-5aceb0e4`, nlb `main-fe637462`, ui `main-4fdd53a8`; migration 0023; smoke vpc.subnet selectable ✓
- [x] **ЭПИК ЗАВЕРШЁН.** Follow: iam#173 (Scope.ResourceType dedup); selector для iam.{user,group,role} (Q4 — при появлении labels+юзкейса); SelectorTargetPanel ReplaceTargetSelector types-optional (ui follow); ListTargetMembers RPC (UI verification-бейджи)

## Связанные
[[epic-100-resource-scoped-access-binding]] (α), [[epic-103-rsab-beta-gamma]] (β/γ/δ),
[[../resources/iam-resource-mirror]], [[../resources/iam-access-binding]],
[[../edges/compute-to-iam-fgaproxy]], [[../edges/nlb-to-iam-fga-register]].
