---
title: "ws#767: запись схождения волны 0 identity-own на дайджесте — в волне-3"
aliases:
  - issue-767-ws
ticket_id: 767
category: kac
status: to-do
type: docs
repos:
  - kacho-workspace
areas:
  - docs/changes/wave-identity-own-w0
prs: []
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/767
opened: 2026-09-22
tags:
  - kac
  - docs
verified_against: "PRO-Robotech/kacho-workspace, 2026-09-26: трекер — задача открыта, родитель ws#786 (`gh issue view 767`, `gh api .../parent`), меток status:* нет; в #853 коммитов с её номером нет (`git log 27eb0775..a9159c46`). Довод о том, что запись посадку не держит, — из комментария задачи 2026-09-22, мной не перемерялся"
---

# ws#767: запись схождения волны 0 identity-own на дайджесте — в волне-3

**Состояние на момент записи**: `to-do` — 2026-09-26. Задача **открыта**, метки: `tech-debt`,
`P1`, `size:S`, `area:tooling`, `release:identity-own`. 2026-09-26 переведена из волны 0
[[KAC/issue-778-ws|#778]] в волну-3 ws#786: запись схождения делает convergence-reviewer, в волне 0
её никто не вёл, и посадку волны она не держит. `status:in-progress` снята — задача свободна для
захвата. Роль — `convergence-reviewer`.

## Что и зачем

У волны 0 identity-own продукта (запрос PRO-Robotech/kacho#2787) нет записи схождения на
дайджесте: в последнем заходе convergence-reviewer запись не выпустил — две роли не удовлетворены
и не освобождены, а возврат wave-reviewer на том дайджесте стоял вне реестра полномочий.

Предпосылки записи — записи пост-дифф ролей на новом дайджесте: go-style
([[KAC/issue-783-ws|#783]], в `771`), system-design ([[KAC/issue-779-ws|#779]], в `main`) и
wave-reviewer ([[KAC/issue-775-ws|#775]], не влита). Блокеры ws#766 и PRO-Robotech/kacho#2788
закрыты 2026-09-22.

## DoD

Из тела задачи, «ПРЕДИКАТ СНЯТИЯ»:

- [ ] в ветке пакета изменения волны лежит запись схождения на новом дайджесте;
- [ ] в записи нет ролей со статусом `unresolved`, и ни одна роль не поставила возврат на этот
  дайджест.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах по этой задаче нет.

- [[KAC/issue-778-ws]] — волна, из которой переведена.
- [[KAC/wave-identity-own-w0-2026-09-22]] — волна 0 продукта.

#kac #docs
