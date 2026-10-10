---
title: "ws#930: ритуалы потока скриптами — тело PR, закрытие волны, событие одобрения, trail"
aliases:
  - issue-930-ws
  - ws#930
ticket_id: 930
category: kac
status: done
type: feature
repos:
  - kacho-workspace
areas:
  - scripts/rituals
  - scripts/lib
  - scripts/merge-readiness.sh
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/932
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/930
opened: 2026-10-05
closed: 2026-10-06
tags:
  - kac
  - conventions
verified_against: "kacho-workspace main@a290f8c60679 (коммит слияния PR #932; gh pr view 932 → MERGED 2026-10-06); состояние задачи — gh issue view 2026-10-07; DoD — по комментарию DoD-proof задачи; самопробы этой записью не перезапускались"
---

# ws#930: ритуалы потока скриптами — тело PR, закрытие волны, событие одобрения, trail

> [!note] Состояние — `done`: влито в `main` воркспейса
> Запрос [ws#932](https://github.com/PRO-Robotech/kacho-workspace/pull/932) влит коммитом слияния `a290f8c60679` 2026-10-06; задача закрыта как completed.

## Что и зачем

Решение владельца 2026-10-06: механика ритуалов — скриптами, а не агентами. Четыре скрипта: тело запроса из коммитов (`Closes` только задаче с комментарием `DoD-proof @<ревизия>`), закрытие волны с переносом остатка, событие одобрения вместе с правкой блока записи ревью, trail vault.

## Затронутые каталоги

`scripts/rituals`, `scripts/lib`, `scripts/merge-readiness.sh` (PRO-Robotech/kacho-workspace).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в `main` — коммит слияния `a290f8c60679` ([ws#932](https://github.com/PRO-Robotech/kacho-workspace/pull/932));
- [x] DoD-proof @`08de3a440512` — [комментарий задачи](https://github.com/PRO-Robotech/kacho-workspace/issues/930#issuecomment-6003745593): `scripts/rituals/run-all.sh` — проверок 4, провалено 0; `inject.sh` — доказательств 11, прошло 11 (контроль и мутанты M1–M7); хук отправки на голове — 11 наборов, провалено 0.

## Затронутые сущности vault

- — (узких записок предмет не трогает: оснастка воркспейса)

## Связанные задачи

- [[KAC/issue-1266]] — релиз, на волнах которого найдено
- [[KAC/issue-2968]] · [[KAC/issue-539-kaname]] — волна-5, где оснастка работала

#kac #conventions
