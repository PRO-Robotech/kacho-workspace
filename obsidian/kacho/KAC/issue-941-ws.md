---
title: "ws#941: событие одобрения: первая строка коммита ритуала с номером из имени ветки"
aliases:
  - issue-941-ws
  - ws#941
ticket_id: 941
category: kac
status: done
type: fix
repos:
  - kacho-workspace
areas:
  - scripts/rituals
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/942
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/941
opened: 2026-10-06
closed: 2026-10-06
tags:
  - kac
  - conventions
verified_against: "kacho-workspace main@67d02648cd60 (коммит слияния PR #942; gh pr view 942 → MERGED 2026-10-06); состояние задачи — gh issue view 2026-10-07; DoD — по комментарию DoD-proof задачи; самопробы этой записью не перезапускались"
---

# ws#941: событие одобрения: первая строка коммита ритуала с номером из имени ветки

> [!note] Состояние — `done`: влито в `main` воркспейса
> Запрос [ws#942](https://github.com/PRO-Robotech/kacho-workspace/pull/942) влит коммитом слияния `67d02648cd60` 2026-10-06; задача закрыта как completed.

## Что и зачем

Коммит ритуала события одобрения отвергался хуком префикса номера ветки уже ПОСЛЕ публикации события, и блок записи докоммичивался руками (kaname 526, ws F6b). Первая строка берёт номер из имени ветки; ветка без номера или отсоединённая голова — отказ до публикации, событий 0.

## Затронутые каталоги

`scripts/rituals` (PRO-Robotech/kacho-workspace).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в `main` — коммит слияния `67d02648cd60` ([ws#942](https://github.com/PRO-Robotech/kacho-workspace/pull/942));
- [x] DoD-proof @`344d573c` — [комментарий задачи](https://github.com/PRO-Robotech/kacho-workspace/issues/941#issuecomment-6018785714): `check-03-approval-event.py` — проб 54, провалено 0; `inject.sh` до правки — 2 выживших мутанта, после — 0.

## Затронутые сущности vault

- — (узких записок предмет не трогает: оснастка воркспейса)

## Связанные задачи

- [[KAC/issue-1266]] — релиз, на волнах которого найдено
- [[KAC/issue-2968]] · [[KAC/issue-539-kaname]] — волна-5, где оснастка работала

#kac #conventions
