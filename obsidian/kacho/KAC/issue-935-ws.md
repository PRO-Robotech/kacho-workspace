---
title: "ws#935: landing-precheck несёт scripts/lib к merge-readiness; номер PR в шаблоне волны"
aliases:
  - issue-935-ws
  - ws#935
ticket_id: 935
category: kac
status: done
type: fix
repos:
  - kacho-workspace
areas:
  - scripts/landing-precheck.sh
  - .claude/workflows
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/936
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/935
opened: 2026-10-06
closed: 2026-10-06
tags:
  - kac
  - conventions
verified_against: "kacho-workspace main@24c623bcb960 (коммит слияния PR #936; gh pr view 936 → MERGED 2026-10-06); состояние задачи — gh issue view 2026-10-07; DoD — по комментарию DoD-proof задачи; самопробы этой записью не перезапускались"
---

# ws#935: landing-precheck несёт scripts/lib к merge-readiness; номер PR в шаблоне волны

> [!note] Состояние — `done`: влито в `main` воркспейса
> Запрос [ws#936](https://github.com/PRO-Robotech/kacho-workspace/pull/936) влит коммитом слияния `24c623bcb960` 2026-10-06; задача закрыта как completed.

## Что и зачем

Предпроверка посадки извлекала проверку готовности к слиянию без её библиотеки, и та выходила кодом «нет распознавателя» на каждой посадке — пункт о доказательстве DoD не судился ни разу. Шаблон волны подставлял номер запроса строкой.

## Затронутые каталоги

`scripts/landing-precheck.sh`, `.claude/workflows` (PRO-Robotech/kacho-workspace).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в `main` — коммит слияния `24c623bcb960` ([ws#936](https://github.com/PRO-Robotech/kacho-workspace/pull/936));
- [x] DoD-proof @`733ed9a00548` — [комментарий задачи](https://github.com/PRO-Robotech/kacho-workspace/issues/935#issuecomment-6008429965): `landing-precheck-inject.sh` — проб 39, сошлось 39 (до правки — 5 не сошлись); `wave-template-inject.sh` — мутантов 18, красных 18; живой прогон на kacho#3043 дал вердикт по существу (код 1), а не код 2.

## Затронутые сущности vault

- — (узких записок предмет не трогает: оснастка воркспейса)

## Связанные задачи

- [[KAC/issue-1266]] — релиз, на волнах которого найдено
- [[KAC/issue-2968]] · [[KAC/issue-539-kaname]] — волна-5, где оснастка работала

#kac #conventions
