---
title: "ws#825: записи пост-дифф ревью полос corelib волны-2"
aliases:
  - issue-825-ws
ticket_id: 825
category: kac
status: test
type: docs
repos:
  - kacho-workspace
areas:
  - docs/changes
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/836
  - https://github.com/PRO-Robotech/kacho-workspace/pull/841
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/825
opened: 2026-09-23
closed: 2026-09-26
tags:
  - kac
  - docs
verified_against: "PRO-Robotech/kacho-workspace: голова задачи cabeee4ab12 — предок коммита слияния волны 27eb0775252 в ветку эпика 771 и не предок origin/main 6eddaa5e9c9 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись; 2026-09-26: трекер — закрыта 2026-09-26T09:34:32Z, меток status:* нет (`gh issue view`); коммит слияния волны 27eb0775252 — в origin/771, не в origin/main (`gh api compare`)"
---

# ws#825: записи пост-дифф ревью полос corelib волны-2

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:34:32Z вместе с волной [[KAC/issue-805-ws|#805]]: запрос волны PR #841 влит в ветку эпика `771` (координата, не живая ссылка), коммит закрытия — слияние волны `27eb0775252`; метка `status:test` снята, метки сейчас: `P1`, `size:S`, `area:tooling`, `release:identity-own`. В `main` работа **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #771 в ствол.

## Что и зачем

Записи пост-дифф ревью полос corelib [[KAC/issue-33-corelib|#33]], [[KAC/issue-49-corelib|#49]], [[KAC/issue-38-corelib|#38]], [[KAC/issue-31-corelib|#31]], [[KAC/issue-40-corelib|#40]] внесены в `docs/changes/`.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `cabeee4ab12` → слияние в ветку сборки `835` `25977125961` — «#835 merge #825: записи пост-дифф ревью полос corelib волны-2» |
| запрос сборки | PR #836 `835` → `805`, голова `2345ef6cd86`, коммит слияния `f46878626e8`; прогоны головы — 1 прогон, `success` |
| запрос волны | PR #841 `805` → `771`, голова `aa378730dcb`, коммит слияния `27eb0775252`; прогоны головы — 1 прогон, `success` |

## DoD

Из тела задачи, раздел «ПРЕДИКАТ.» (перечислено как есть, мной не перемерялось):

- `git ls-tree -r --name-only origin/<ветка> -- docs/changes/corelib-33 docs/changes/corelib-49 | wc -l` даёт 2;
- sha256 каждого файла ветки равен названному выше;
- ветка влита в ветку волны `805` коммитом слияния.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `27eb0775252` в ветку эпика `771`;
- [ ] предмет в стволе: `main` — посадкой эпика #771.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах исполнителей по этой задаче нет.

- [[KAC/issue-805-ws]] — волна.

#kac #docs
