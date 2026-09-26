---
title: "ws#815: самопроверка crossrepo-gate снимает KACHO_HOME_*"
aliases:
  - issue-815-ws
ticket_id: 815
category: kac
status: test
type: fix
repos:
  - kacho-workspace
areas:
  - scripts/crossrepo-gate
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/836
  - https://github.com/PRO-Robotech/kacho-workspace/pull/841
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/815
opened: 2026-09-23
closed: 2026-09-26
tags:
  - kac
  - fix
verified_against: "PRO-Robotech/kacho-workspace: голова задачи b3aa0cbbc04 — предок коммита слияния волны 27eb0775252 в ветку эпика 771 и не предок origin/main 6eddaa5e9c9 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись; 2026-09-26: трекер — закрыта 2026-09-26T09:34:18Z, меток status:* нет (`gh issue view`); коммит слияния волны 27eb0775252 — в origin/771, не в origin/main (`gh api compare`)"
---

# ws#815: самопроверка crossrepo-gate снимает KACHO_HOME_*

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:34:18Z вместе с волной [[KAC/issue-805-ws|#805]]: запрос волны PR #841 влит в ветку эпика `771` (координата, не живая ссылка), коммит закрытия — слияние волны `27eb0775252`; метка `status:test` снята, метки сейчас: `bug`, `P2`, `size:S`, `area:tooling`, `release:identity-own`. В `main` работа **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #771 в ствол.

## Что и зачем

Самопроверка гейта копий краснела при заданных `KACHO_HOME_*`. Теперь она снимает их и `GIT_*` перед прогоном.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `b3aa0cbbc04` → слияние в ветку сборки `835` `782aa8aec14` — «#835 merge #815: самопроверка crossrepo-gate снимает KACHO_HOME_*» |
| запрос сборки | PR #836 `835` → `805`, голова `2345ef6cd86`, коммит слияния `f46878626e8`; прогоны головы — 1 прогон, `success` |
| запрос волны | PR #841 `805` → `771`, голова `aa378730dcb`, коммит слияния `27eb0775252`; прогоны головы — 1 прогон, `success` |

## DoD

Из тела задачи, раздел «ПРЕДИКАТ.» (перечислено как есть, мной не перемерялось):

- `bash scripts/crossrepo-gate/inject.sh` при `KACHO_HOME_KACHO`, `KACHO_HOME_KANAME`, `KACHO_HOME_CORELIB`, указывающих на существующие клоны, даёт код 0 и «пройдено 9». Сегодня: код 1, пройдено 3;
- близнец: тот же вызов без этих переменных даёт код 0 и «пройдено 9» (сегодня так и есть);
- каждая из трёх переменных, заданная по одной, итога не меняет.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `27eb0775252` в ветку эпика `771`;
- [ ] предмет в стволе: `main` — посадкой эпика #771.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах исполнителей по этой задаче нет.

- [[KAC/issue-805-ws]] — волна.

#kac #fix
