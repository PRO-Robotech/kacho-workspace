---
title: "ws#943: landing-precheck: задание, не запускаемое на запросе, не провал"
aliases:
  - issue-943-ws
  - ws#943
ticket_id: 943
category: kac
status: done
type: fix
repos:
  - kacho-workspace
areas:
  - scripts/landing-precheck.sh
  - scripts/merge-readiness.sh
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/945
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/943
opened: 2026-10-06
closed: 2026-10-06
tags:
  - kac
  - conventions
verified_against: "kacho-workspace main@4242144fd19e (коммит слияния PR #945; gh pr view 945 → MERGED 2026-10-06); состояние задачи — gh issue view 2026-10-07; DoD — по комментарию DoD-proof задачи; самопробы этой записью не перезапускались"
---

# ws#943: landing-precheck: задание, не запускаемое на запросе, не провал

> [!note] Состояние — `done`: влито в `main` воркспейса
> Запрос [ws#945](https://github.com/PRO-Robotech/kacho-workspace/pull/945) влит коммитом слияния `4242144fd19e` 2026-10-06; задача закрыта как completed.

## Что и зачем

Предпроверка посадки останавливала запросы kaname на заданиях, пропущенных по условию события (они запускаются только на стволе). Первая редакция: `skipped` не провал, если задания нет в наборе обязательных контекстов. Её сузила [[KAC/issue-947-ws]].

## Затронутые каталоги

`scripts/landing-precheck.sh`, `scripts/merge-readiness.sh` (PRO-Robotech/kacho-workspace).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в `main` — коммит слияния `4242144fd19e` ([ws#945](https://github.com/PRO-Robotech/kacho-workspace/pull/945));
- [x] DoD-proof @`3a74e44d5b20` — [комментарий задачи](https://github.com/PRO-Robotech/kacho-workspace/issues/943#issuecomment-6019486533): `landing-precheck-inject.sh` — пробы зелёные; `skipped` обязательного, `neutral` и `failure` — по-прежнему причина.

## Затронутые сущности vault

- — (узких записок предмет не трогает: оснастка воркспейса)

## Связанные задачи

- [[KAC/issue-1266]] — релиз, на волнах которого найдено
- [[KAC/issue-2968]] · [[KAC/issue-539-kaname]] — волна-5, где оснастка работала

#kac #conventions
