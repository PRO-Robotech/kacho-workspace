---
title: "ws#823: записи пост-дифф ревью полосы kaname #340"
aliases:
  - issue-823-ws
ticket_id: 823
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
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/823
opened: 2026-09-23
closed: 2026-09-26
tags:
  - kac
  - docs
verified_against: "PRO-Robotech/kacho-workspace: голова задачи 596eeddd2e0 — предок коммита слияния волны 27eb0775252 в ветку эпика 771 и не предок origin/main 6eddaa5e9c9 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись; 2026-09-26: трекер — закрыта 2026-09-26T09:34:27Z, меток status:* нет (`gh issue view`); коммит слияния волны 27eb0775252 — в origin/771, не в origin/main (`gh api compare`)"
---

# ws#823: записи пост-дифф ревью полосы kaname #340

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:34:27Z вместе с волной [[KAC/issue-805-ws|#805]]: запрос волны PR #841 влит в ветку эпика `771` (координата, не живая ссылка), коммит закрытия — слияние волны `27eb0775252`; метка `status:test` снята, метки сейчас: `P1`, `size:S`, `area:tooling`, `release:identity-own`. В `main` работа **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #771 в ствол.

## Что и зачем

Записи пост-дифф ревью полосы [[KAC/issue-340-kaname|kaname#340]] (kn-340) внесены в `docs/changes/kn-340/`.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `596eeddd2e0` → слияние в ветку сборки `835` `cf234f93ea7` — «#835 merge #823: записи пост-дифф ревью полосы kaname #340» |
| запрос сборки | PR #836 `835` → `805`, голова `2345ef6cd86`, коммит слияния `f46878626e8`; прогоны головы — 1 прогон, `success` |
| запрос волны | PR #841 `805` → `771`, голова `aa378730dcb`, коммит слияния `27eb0775252`; прогоны головы — 1 прогон, `success` |

## DoD

Из тела задачи, раздел «ПРЕДИКАТ.» (перечислено как есть, мной не перемерялось):

- `git ls-tree -r --name-only origin/<ветка> -- docs/changes/kn-340 | wc -l` даёт 4;
- sha256 каждого файла ветки равен sha256 `git show e3c4ae844:<путь>` в kaname;
- ветка влита в ветку волны `805` коммитом слияния.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `27eb0775252` в ветку эпика `771`;
- [ ] предмет в стволе: `main` — посадкой эпика #771.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах исполнителей по этой задаче нет.

- [[KAC/issue-805-ws]] — волна.
- [[KAC/issue-340-kaname]]

#kac #docs
