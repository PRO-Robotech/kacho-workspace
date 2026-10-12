---
title: "ws#947: landing-precheck: skipped законен только по разобранному условию на голове"
aliases:
  - issue-947-ws
  - ws#947
ticket_id: 947
category: kac
status: done
type: fix
repos:
  - kacho-workspace
areas:
  - scripts/landing-precheck.sh
  - scripts/landing-precheck-fixtures
  - scripts/merge-readiness.sh
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/948
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/947
opened: 2026-10-06
closed: 2026-10-06
tags:
  - kac
  - conventions
verified_against: "kacho-workspace main@29712d6d0493 (коммит слияния PR #948; gh pr view 948 → MERGED 2026-10-06); состояние задачи — gh issue view 2026-10-07; DoD — по комментарию DoD-proof задачи; самопробы этой записью не перезапускались"
---

# ws#947: landing-precheck: skipped законен только по разобранному условию на голове

> [!note] Состояние — `done`: влито в `main` воркспейса
> Запрос [ws#948](https://github.com/PRO-Robotech/kacho-workspace/pull/948) влит коммитом слияния `29712d6d0493` 2026-10-06; задача закрыта как completed.

## Что и зачем

После [[KAC/issue-943-ws]] снимался ЛЮБОЙ `skipped` необязательного задания, в том числе пропущенный по упавшей зависимости. Теперь `skipped` законен, только если условие задания, прочитанное из файла workflow на голове запроса, невыполнимо для события прогона; иной — причина `CI-NOT-SUCCESS`; масок по именам нет. Найдено на посадке kaname#629 (волна-5).

## Затронутые каталоги

`scripts/landing-precheck.sh`, `scripts/landing-precheck-fixtures`, `scripts/merge-readiness.sh` (PRO-Robotech/kacho-workspace).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в `main` — коммит слияния `29712d6d0493` ([ws#948](https://github.com/PRO-Robotech/kacho-workspace/pull/948));
- [x] DoD-proof @`fff599153787` — [комментарий задачи](https://github.com/PRO-Robotech/kacho-workspace/issues/947#issuecomment-6024726023): `landing-precheck-inject.sh` — пробы зелёные; живой прогон `landing-precheck.sh PRO-Robotech/kaname 629` — вердикт по разобранному условию.

## Затронутые сущности vault

- — (узких записок предмет не трогает: оснастка воркспейса)

## Связанные задачи

- [[KAC/issue-1266]] — релиз, на волнах которого найдено
- [[KAC/issue-2968]] · [[KAC/issue-539-kaname]] — волна-5, где оснастка работала

#kac #conventions
