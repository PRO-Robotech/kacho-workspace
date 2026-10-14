---
title: "kaname#296: эпик identity-own — своя личность в службе доступа"
aliases:
  - issue-296-kaname
ticket_id: 296
category: kac
status: done
type: epic
repos:
  - kaname
areas:
  - docs
  - proto
  - internal
  - tests/newman
prs:
  - https://github.com/PRO-Robotech/kaname/pull/582
  - https://github.com/PRO-Robotech/kaname/pull/599
  - https://github.com/PRO-Robotech/kaname/pull/607
  - https://github.com/PRO-Robotech/kaname/pull/623
  - https://github.com/PRO-Robotech/kaname/pull/629
  - https://github.com/PRO-Robotech/kaname/pull/640
  - https://github.com/PRO-Robotech/kaname/pull/658
  - https://github.com/PRO-Robotech/kaname/pull/668
  - https://github.com/PRO-Robotech/kaname/pull/702
  - https://github.com/PRO-Robotech/kaname/pull/704
  - https://github.com/PRO-Robotech/kaname/pull/714
issue_url: https://github.com/PRO-Robotech/kaname/issues/296
opened: 2026-09-18
closed: 2026-10-14
tags:
  - kac
  - kacho-iam
  - epic
verified_against: "kaname 296@77dae639 (коммит слияния PR #599, родители d2f6f182 + 594af5af; голова origin/296 = этот коммит, 2026-10-04): состав — git log d2f6f182..77dae639 --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям задачи и телу PR #599; пробы и конвейер этой записью не перезапускались; 2026-10-06 — волны 3–4: голова origin/296 = 2cf9c8528b1f (git ls-remote), волны — gh api …/issues/296/sub_issues (#535–#538 closed, #539–#541 open); 2026-10-07 — волна 5: голова origin/296 = d9e233f42051 (git ls-remote), волны — gh api …/issues/296/sub_issues (#535–#539 closed, #540–#541 open); 2026-10-08 — волна 6, три сборки: голова origin/296 = aa253fa9bcad (git ls-remote), коммиты слияния PR #640 = 76ca2c8aa6e0, #658 = b729affb6a80, #668 = 8b0379e2a9c5 (gh pr view), волны — gh api …/issues/296/sub_issues (#535–#539 и #541 closed, #540 open; #541 — NOT_PLANNED, снята); 2026-10-14 — посадка в main: PR #714 MERGED, коммит слияния 9ccdc8d86275 (родители 8a84dcff6eb1 + 278ac4c0835e, gh pr view 714 и комментарий закрытия эпика), задача — gh issue view 296 → CLOSED COMPLETED, sub-issue — gh api …/issues/296/sub_issues (16, open 0; #541 и #784 — NOT_PLANNED)"
---

# kaname#296: эпик identity-own — своя личность в службе доступа

> [!note] Состояние — `done`: эпик посажен в `main` службы и закрыт 2026-10-14
> PR [kaname#714](https://github.com/PRO-Robotech/kaname/pull/714) `296` → `main`, коммит слияния `9ccdc8d86275`;
> комментарий закрытия — [kaname#296](https://github.com/PRO-Robotech/kaname/issues/296#issuecomment-6164799470).
> Ветка эпика `296` снята при вливании. Sub-issue эпика — 16, открытых 0 (`gh api …/issues/296/sub_issues`, 2026-10-14).

## Что и зачем

Дочерний эпик [[KAC/issue-1266]] в доме службы доступа: своя личность — после снятия внешнего стека
([[KAC/issue-357-kaname]], влит в `main`). Записка заведена сжато при закрытии волны-1.

| волна | состояние на 2026-10-14 |
|---|---|
| [[KAC/issue-535-kaname]] волна-1 — приёмки, модель прав, ключи доступа, проза | влита в `296` (PR kaname#582, `d2f6f182`) |
| [[KAC/issue-536-kaname]] волна-2 — отсечка, авторитет отзыва, рукоятка ключа, гейты, почта | влита в `296` (PR kaname#599, `77dae639`) |
| [[KAC/issue-537-kaname]] волна-3 — Ф13, чарт, проза | влита в `296` (PR kaname#607, `115db76949bd`) |
| [[KAC/issue-538-kaname]] волна-4 — регистрация и приглашение, мигратор, рукоятка, Ф13 | влита в `296` (PR kaname#623, `2cf9c8528b1f`); 15 задач — в #539 |
| [[KAC/issue-539-kaname]] волна-5 — перепись AWI-13, кейс Ф4-27, носитель окна темпа, приёмка службы ред. 8 | влита в `296` (PR kaname#629, `d9e233f42051`); 16 задач — в #540 |
| [[KAC/issue-540-kaname]] волна-6 — формы отказов, ведомость долга, гейт материала, свои сессии, смена адреса, публичная служба администраторов кластера | влита в `296` (PR kaname#640, #658, #668), закрыта 2026-10-12 |
| kaname#541 волна-7 — Ф5-14 после доставки письма | **снята** 2026-10-06 (NOT_PLANNED): полоса NA20 перенесена в волну-6 задачей [[KAC/issue-633-kaname]] — комментарий закрытия |
| [[KAC/issue-678-kaname]] волна-7 — перенесённые задачи для фиксации состава волны 6 | влита в `296` (PR kaname#702 `8a13a6a4b7bb`, #704 `d33a3b866abc`), закрыта каскадом посадки 2026-10-14 |

Прочие sub-issue эпика (сборки и задачи вне волн) — kaname#570, #764, #769, #770, #772, #780, #785 закрыты, #784 — NOT_PLANNED;
состав — по трекеру, этой записью не разбирался.

## Затронутые каталоги

Ветка эпика `296`; по волнам — [[KAC/issue-535-kaname]], [[KAC/issue-536-kaname]].

## DoD

Отметка `[x]` — измерено этой записью на ревизии из `verified_against` либо предъявлено артефактом, названным в строке; `[ ]` — не перепроверено этой записью либо не выполнено, причина в строке.

- [x] волна-1 влита в ветку эпика — [[KAC/issue-535-kaname]].
- [x] волна-2 влита в ветку эпика — [[KAC/issue-536-kaname]].
- [x] волна-3 влита в ветку эпика — [[KAC/issue-537-kaname]].
- [x] волна-4 влита в ветку эпика — [[KAC/issue-538-kaname]].
- [x] волна-5 влита в ветку эпика — [[KAC/issue-539-kaname]].
- [x] волна-6 влита в ветку эпика и закрыта — [[KAC/issue-540-kaname]].
- [x] волна-7 снята, её полоса — в волне-6 (kaname#541 CLOSED NOT_PLANNED).
- [x] волна-7 влита в ветку эпика и закрыта — [[KAC/issue-678-kaname]], DoD-proof [@278ac4c0](https://github.com/PRO-Robotech/kaname/issues/678#issuecomment-6162263805).
- [x] дочерние закрыты до посадки — `cascade-census.sh --children-closed PRO-Robotech/kaname 296`: код 0, открытых 0 (комментарий закрытия эпика).
- [x] эпик влит в `main` службы — PR kaname#714, коммит слияния `9ccdc8d86275`; задача CLOSED COMPLETED.

## Затронутые сущности vault

- [[KAC/issue-535-kaname]] — волна-1 и узкие записки, которые она тронула
- [[KAC/issue-536-kaname]] — волна-2 и узкие записки, которые она тронула
- [[KAC/issue-538-kaname]] — волна-4 и узкие записки, которые она тронула
- [[KAC/issue-539-kaname]] — волна-5 и узкие записки, которые она тронула
- [[KAC/issue-540-kaname]] — волна-6 и узкие записки, которые она тронула
- [[KAC/issue-678-kaname]] — волна-7 (перечня узких записок вход не нёс)

## History

- 2026-10-12 — волна-6 закрыта; внесена волна-7 kaname#678 и trail её задач #458, #664, #710, #711; утверждение «#540 открыта» исправлено (ws#1035).
- 2026-10-14 — эпик посажен в `main` (PR kaname#714) и закрыт, волна-7 kaname#678 закрыта каскадом; статус `done`; строка волны-6 таблицы восстановлена в две ячейки (ws#1077).

## Связанные задачи

- [[KAC/issue-1266]] — эпик платформы
- [[KAC/issue-357-kaname]] — снятие внешнего стека в службе, предшественник

#kac #kacho-iam #epic
