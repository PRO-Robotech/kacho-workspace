---
title: "kacho#3011: запись перечня переноса пережила предмет — ствол красный"
aliases:
  - issue-3011
ticket_id: 3011
category: kac
status: done
verified_against: "PR #3014, состояние задачи и push-прогон 37160208278 сверены `gh` 2026-10-04: PR MERGED merge-коммитом 14a09acd6f6 (два родителя), задача CLOSED; задание проверки «перенос ветки не откатил ствол» на 14a09acd6f6 — success; прогоны мной не перезапускались"
type: fix
repos:
  - kacho
areas:
  - tools/carrydrift
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3014
issue_url: https://github.com/PRO-Robotech/kacho/issues/3011
opened: 2026-10-04
closed: 2026-10-03
tags:
  - kac
---

# kacho#3011: запись перечня переноса пережила предмет — ствол красный

**Состояние на момент записи**: `done`. PR
https://github.com/PRO-Robotech/kacho/pull/3014 влит в `main` merge-коммитом
`14a09acd6f6abf910dbb7db03b4c0273a976e2c5` (2026-10-03T22:58Z); задача **закрыта**
(`gh issue view 3011 --repo PRO-Robotech/kacho --json state` → `CLOSED`, 2026-10-04).
Состав PR — один файл, `tools/carrydrift/declared-removals.txt`. Способ вливания —
merge-коммит: решение владельца 2026-10-04, squash в репозитории выключен.

**Роль исполнителя:** `tooling-maintainer`.

## Что и зачем

Обязательная проверка «перенос ветки не откатил ствол» красная на голове `main`
`ba01514b98b` — и на push, и на pull_request (прогоны названы в теле задачи). Красный ствол
блокирует вливание любого PR, отсюда `P1`.

Предмет — запись без предмета в `tools/carrydrift/declared-removals.txt`: строка 148 на
`ba01514b98b`, запись о `.github/scripts/assert-workflow-run-publish-guard.py`. Судья
переноса отказывает с признаком «пережила предмет» и требует снять запись. Устройство
судьи — [[KAC/issue-295]].

Класс дефекта — `kacho#1921` (запись перечня не снимается при схлопывании линии в ствол):
эта задача снимает один его случай, а не класс.

## DoD (из тела задачи)

- [x] запись снята — PR #3014;
- [x] проверка «перенос ветки не откатил ствол» зелёная на посадке: push-прогон
      `37160208278` на `14a09acd6f6`, задание — `success`.

Артефакт — PR в `main` и зелёный прогон проверки на его посадке. До вливания в `main`
статус записки не выше `test`.

## Связанные задачи

- https://github.com/PRO-Robotech/kacho/issues/1921 — класс, к которому относится случай.

## History

- 2026-10-04 — trail заведён вместе с веткой; PR и sha посадки нет.
- 2026-10-04 — PR #3014 влит merge-коммитом `14a09acd6f6` (2026-10-03T22:58Z), задача
  закрыта; push-прогон `37160208278` — проверка переноса `success`; статус `done`.

## Затронутые сущности vault

- [[KAC/issue-295]] — судья переноса и его вынос в `tools/carrydrift/`.

#kac
