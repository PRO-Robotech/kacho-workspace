---
title: "kacho#1274: экраны входа рисует своя консоль вместо чужого приложения"
aliases:
  - issue-1274
ticket_id: 1274
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - ui-future/shared
  - ui-future/e2e
  - ui-future/host
  - ui-future/dashboard
  - ui-future/iam
  - ui-future/compute
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2861
  - https://github.com/PRO-Robotech/kacho/pull/2869
issue_url: https://github.com/PRO-Robotech/kacho/issues/1274
opened: 2026-08-24
tags:
  - kac
  - feature
  - kacho-ui
verified_against: "PRO-Robotech/kacho: голова задачи d500b05c5a3 — предок коммита слияния волны 7190c3e5274 в ветку эпика 2564 и не предок origin/main 1d42a6728bf (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# kacho#1274: экраны входа рисует своя консоль вместо чужого приложения

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `enhancement`, `status:test`, `P1`, `size:M`, `area:ui`, `release:identity-own`. Работа влита в ветку волны [[KAC/issue-2796|#2796]], волна — в ветку эпика `2564` (координата, не живая ссылка) запросом PR #2869; в `main` **не** доехала: закроет её посадка эпика #2564 в ствол.

## Что и зачем

Вход в продукт рисовало чужое приложение личности, а написанные страницы консоли не были смонтированы ни на один маршрут. Задача монтирует свои экраны церемоний в маршрутизатор консоли, дописывает недостающие и снимает чужой подчарт с полосой раздачи. Приёмка — F8 (`docs/specs/sub-phase-F8-console-identity-ceremony-screens-acceptance.md` воркспейса, ведёт [[KAC/issue-773-ws|ws#773]]).

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `d500b05c5a3` → слияние в ветку сборки `2857` `df432a42559` — «#2857 merge #1274: печенье службы доходит до http-стенда» |
| запрос сборки | PR #2861 `2857` → `2796`, голова `86d8244838f`, коммит слияния `ec8f4f445b4`; прогоны головы — 9 прогонов, все `success` |
| запрос волны | PR #2869 `2796` → `2564`, голова `ec8f4f445b4`, коммит слияния `7190c3e5274`; прогоны головы — 8 прогонов, все `success` |

## DoD

Из тела задачи, раздел «ПРЕДИКАТ СНЯТИЯ» (перечислено как есть, мной не перемерялось):

Все потоки рисует консоль; подчарта чужого UI в дереве нет; браузерная проба проходит вход и регистрацию на наших экранах.

Сверено мной:

- [ ] «подчарта чужого UI в дереве нет» — на голове эпика не выполнено: `git ls-tree -d --name-only 7190c3e5274 deploy/helm/umbrella/charts/` называет `kratos-selfservice-ui`. Физическое снятие шаблонов поставщика перенесено в #1276 решением 2026-09-24 в комментариях [[KAC/issue-2735|#2735]] и [[KAC/issue-2777|#2777]]; в самой задаче #1274 такого решения нет;
- [x] голова задачи — предок коммита слияния волны `7190c3e5274` в ветку эпика `2564`;
- [ ] предмет в стволе: `main` — посадкой эпика #2564.

## Затронутые сущности vault

Возвраты исполнителей по задаче называют: ui-future/shared (api/carrier-order, lib/redirect, organisms/PageFrame, pages/auth), ui-future/host (AccountPanel, HostRail, ReachabilityPage, ModulePlaceholderPage); ребро консоль → край → служба доступа по полосе формы — не новое.

- [[KAC/issue-2796]] — волна.
- [[packages/ui-pages-auth]]
- [[KAC/issue-2780]]
- [[KAC/issue-773-ws]]

#kac #feature #kacho-ui
