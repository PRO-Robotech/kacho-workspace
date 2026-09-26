---
title: "ws#783: записи go-style волны 0 identity-own — в ветке эпика 771"
aliases:
  - issue-783-ws
ticket_id: 783
category: kac
status: test
type: docs
repos:
  - kacho-workspace
areas:
  - docs/changes/wave-identity-own-w0/reviews/post-diff/go-style-reviewer
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/853
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/783
opened: 2026-09-22
closed: 2026-09-26
tags:
  - kac
  - docs
verified_against: "PRO-Robotech/kacho-workspace, 2026-09-26: коммиты f2b60adf, 4cb08bc7, 7a767df0, 360309a2, b7707a3b — предки origin/771 3956217c и не предки origin/main 6eddaa5e (`git merge-base --is-ancestor`); `git ls-tree -r origin/771 -- docs/changes/wave-identity-own-w0/reviews/post-diff/go-style-reviewer/` → 4 записи, на origin/main → 0; ветка review/wave0-post-diff-go на origin отсутствует (`git ls-remote`); PR #808 закрыт без вливания 2026-09-26T19:20:07Z (`gh pr view 808`); трекер — закрыта 2026-09-26T19:23:18Z, меток status:* нет (`gh issue view 783`)"
---

# ws#783: записи go-style волны 0 identity-own — в ветке эпика 771

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере
2026-09-26T19:23:18Z каскадом волны [[KAC/issue-778-ws|#778]]: запрос волны PR #853 влит в ветку
эпика `771` (координата, не живая ссылка) коммитом слияния `3956217c`; `status:test` снята, метки:
`P1`, `size:S`, `area:tooling`, `release:identity-own`. В `main` записи **не** доехали: туда они
уходят посадкой эпика #771, тогда состояние — `done`.

## Что и зачем

Четыре записи go-style-reviewer пост-дифф по запросу PRO-Robotech/kacho#2787 лежали только в ветке
`review/wave0-post-diff-go` (координата, не живая ссылка): круг 1 — возврат по C1, круги 2–4 —
приняты. Запись последнего круга — одна из предпосылок записи схождения
[[KAC/issue-767-ws|#767]]. Неблокирующие находки записей разведены задачами продукта — перечень в
теле задачи.

## Путь в волну

| что | координата |
|---|---|
| записи | `f2b60adf`, `4cb08bc7`, `7a767df0`, `360309a2`; слияние `main` — `b7707a3b` |
| прежний запрос | PR #808 в `main` — закрыт без вливания: записи пошли линией волны |
| в ветку волны | коммит слияния `58631015` |
| запрос волны | PR #853 `778` → `771`, коммит слияния `3956217c` |

## DoD

Из тела задачи предикат назван по `origin/main`; по каскаду записи идут в `main` через эпик.

- [x] в `771` — 4 записи `post-diff/go-style-reviewer/`, перемерено мной `git ls-tree`;
- [x] ветка снята — на origin её нет (`git ls-remote`);
- [ ] в `main` — 0 записей: посадкой эпика #771.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах по этой задаче нет.

- [[KAC/issue-778-ws]] — волна · [[KAC/issue-779-ws]] — записи system-design той же волны продукта.

#kac #docs
