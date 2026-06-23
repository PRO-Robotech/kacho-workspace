---
title: RBAC rules-model 2026 — sub-phase H (Rule.module scalar) — proto/iam/gateway/ui
ticket_id: rbac-rules-model-2026-H-rule-module-scalar
status: done
type: feature
repos:
  - kacho-proto
  - kacho-iam
  - kacho-api-gateway
  - kacho-ui
prs:
  - "PRO-Robotech/kacho-proto#80"
  - "PRO-Robotech/kacho-iam#210"
  - "PRO-Robotech/kacho-api-gateway#95"
  - "PRO-Robotech/kacho-ui#107"
yt_url: ""
opened: 2026-06-22
tags:
  - kac
  - kacho-iam
  - kacho-proto
  - kacho-api-gateway
  - kacho-ui
  - feature
  - proto
  - migrations
  - domain
  - authz
---

# RBAC rules-model 2026 — sub-phase H (Rule.module scalar)

**Status**: **done** — proto **#80** + iam **#210** + gateway **#95** + ui **#107** merged + **deployed to fe3455** 2026-06-22.
**Type**: feature (breaking core-model refinement). Acceptance `docs/specs/rbac-rules-model-2026-H-rule-module-scalar-acceptance.md` (✅ APPROVED, round 3).

## Deploy — fe3455-client (2026-06-22)

`kubectl set image` (ns `kacho`), all rollouts green, pods 1/1.
- iam `main-4ffca09e` (app + `migrate` init) — **migration 0033 applied** (`goose: successfully migrated database to version: 33`); **64 роли переписаны** `modules:[x]`→`module:x`, **0 legacy** `modules` (verified в БД). Тестовая роль `roln9kgzrj` → `{module:"vpc", resources:["address"], ...}`.
- api-gateway `main-d1afb89e` (rebuild), ui `main-f19a92c5` → **`main-2a0ae017`** (после фикса #2). vpc/compute/geo/nlb unchanged.
- gateway #95 umbrella-e2e (full module-scalar поток через gateway) = SUCCESS — end-to-end доказательство.
- kacho-deploy `values.fe3455.yaml` bumped to live tags (kacho-deploy `807d6b0` + ui-bump для #2).

## Follow-up fix #2 — «созданная кастомная роль не видна» (ui #109 + #110, LIVE-verified в браузере)

Реальный UI-баг (НЕ backend), **3 слоя**, найдены только логином в живой fe3455-UI + инспекцией реального `GET /iam/v1/roles` (mocked-playwright это НЕ ловил — мок отдаёт custom безусловно):
1. `/iam/roles` (route 53a3ed9 → bare `ResourceListPage`) слал listRoles **без `accountId`** → backend by-contract отдаёт только system. Фикс (ui **#109**): `RolesListShell` скоупит по context-store account.
2. **PAGE-BOUNDARY** (главный): даже с accountId — ~56 system-ролей сортируются первыми (created_at ASC), дефолтный pageSize=50 → стр.1 вся system, custom на стр.2; Segmented «Кастомные» фильтрует **client-side** загруженную страницу → пусто. Фикс (ui **#110**): `useResourceList`+`ResourceListPage` получили опц. `pageSize`; `RolesListShell` шлёт `pageSize=1000` → все роли одной страницей → custom видны.
3. **auto-default**: `RolesListShell` дефолтит на `listAccounts[0]` без выбранной шапочной пилюли → custom видны БЕЗ ручного выбора (single-account кейс репортёра). (ui **#111**: ранее добавленный page-level Account `<Select>` убран — дублировал шапочную пилюлю; переключение account'а только через неё.)
LIVE PROOF: залогинился через chrome-devtools (свой PF svc/ui 28099; fe3455 отвергает dev-HS256-JWT → пришлось гнать реальный браузерный логин), /iam/roles → клик «Кастомные» → **rowCount 2, `["test","treska"]`**. Первый WRONG attempt (#108 re-route на старый RolesPage) реверсил намеренный ResourceListPage+Segmented дизайн + ломал playwright → закрыт.

## Что и зачем (owner-mandated)

`Rule.modules` (`repeated string`) → **`Rule.module` (single string)** — ровно ОДИН модуль на
правило. Декартово `modules × resources` позволяло правилу охватывать несколько модулей и
порождать невалидные `(module,resource)`-пары (компилятор fail-closed-SKIP-ил их) — «каша».
Один модуль на правило делает `resources` чисто отображаемыми на модуль; роль на несколько
модулей = несколько правил.

Батч включает **#1 labelSelectable** (caps gap фичи G): каталог несёт `label_selectable`
(=`domain.IsLabelSelectableType`), UI гейтит арм «По меткам» только label-selectable
ресурсами (addressPool / iam.role|group|sa|user|condition больше нельзя выбрать под matchLabels).

## Изменения

- **proto #80** (BREAKING, one-time): `message Rule` — `repeated string modules = 1` → `reserved 1; reserved "modules";` (tombstone, F-precedent PR #77) + `string module = 6 [(length)="1-64"]`. buf breaking absorbed via CI `continue-on-error`. (labelSelectable поле — отдельный merged proto #79.)
- **iam #210**: `domain.Rule.Module string`; new `domain.module_set.go` (`IsKnownModule`, domain владеет closed-set `{iam,vpc,compute,loadbalancer}`); `Validate` reject'ит unknown module на request-path (`Illegal argument module (unknown module '%s')`) + `invalid token` для грамматики; single-module compiler/emit (нет cartesian); `authzmap` drift-test (module-set lockstep). Миграция **0033**: rewrite 64 live ролей `modules:[x]`→`module:x` + `CREATE OR REPLACE iam_rules_valid` scalar-shape (drop-constraint→rewrite→replace-fn→re-add `roles_rules_valid`, одна tx); идемпотентна; reversible Down. + catalog `label_selectable` (#1).
- **gateway #95**: rebuild-only (нет ссылок на `Rule.Modules`) — новые proto-stubs, чтобы REST Create/Update маршалили scalar `module` + catalog `label_selectable`.
- **ui #107**: RulesEditor single-select module + арм «По меткам» только label-selectable + role-detail scalar; vitest 59.

## RED→GREEN

- proto: buf lint clean; breaking = ровно 1 ожидаемый (field 1 deleted); tombstone_enforce PASS.
- iam: domain unit (single-module compile/grant, empty/unknown/invalid-token, wildcard system-only, multierr оба текста) + authzmap drift-test + migration 0033 integration (5/5: array→scalar, defensive split, idempotent, CHECK accept/reject, Up→Down→Up) + newman (scalar happy + unknown-module negative). 3 ревью APPROVED (proto-api / db-architect / go-style).
- ui: vitest RED 36 → GREEN 59 (H-09 single-select/scoped/add-rule/detail + #1 labels-gating).

## Cross-repo (топо + deadlock-урок)

- Порядок: proto #80 → iam #210 → gateway #95 (rebuild) → ui #107 → redeploy.
- **proto-main (module-scalar) ломает iam-main** (ссылки на removed `modules`) до merge iam #210 — стандартный topo-window.
- **iam #210 umbrella-e2e зелёный** (строит gateway из исходников против proto-main → у него есть `module`). **gateway #95 e2e сначала red** (строил iam из iam-main, ещё сломанного) → зелёный после merge iam #210 + re-trigger. Deployed gateway-образ (main-495c01a3) построен против старого proto → нужен rebuild для live (#95).

## Затронутые сущности vault

- [[iam-role]] — `Rule.module` scalar (был `modules[]`); миграция 0033.
- [[iam-role-service]] — Create/Update rules[].module scalar; Validate reject unknown module.
- [[iam-permission-catalog-service]] — `labelSelectable` per resource (#1).
- [[rbac-rules-model-2026-subphase-G-iam]] — предшествующая (H stacks on G).

## DoD

- [x] APPROVED acceptance (ban #1).
- [x] proto #80 + iam #210 merged; TDD RED→GREEN; 3 ревью.
- [x] gateway #95 + ui #107 merged (CI зелёные, gateway umbrella-e2e SUCCESS).
- [x] redeploy fe3455 (миграция 0033 → 64 роли scalar, 0 legacy) + verified.
- [x] vault resources/rpc + memory обновлены.

#kac #kacho-iam #kacho-proto #kacho-api-gateway #kacho-ui #feature #proto #migrations #domain #authz
