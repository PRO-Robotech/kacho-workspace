---
title: "corelib#31: конвейер гонится на запрос в ветку-номер"
aliases:
  - issue-31-corelib
ticket_id: 31
category: kac
status: test
type: feature
repos:
  - corelib
areas:
  - .github/scripts
  - .github/workflows
prs:
  - https://github.com/PRO-Robotech/corelib/pull/62
issue_url: https://github.com/PRO-Robotech/corelib/issues/31
opened: 2026-09-22
tags:
  - kac
  - feature
  - kacho-corelib
verified_against: "PRO-Robotech/corelib: голова задачи 542e525212a — предок коммита слияния волны 227ed2b77b4 в ветку эпика 26 и не предок origin/main 34bc8104a83 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# corelib#31: конвейер гонится на запрос в ветку-номер

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `enhancement`, `release:identity-own`, `status:test`. Работа влита в ветку волны [[KAC/issue-32-corelib|#32]], волна — в ветку эпика `26` (координата, не живая ссылка) запросом PR #62; в `main` **не** доехала: закроет её посадка эпика #26 в ствол.

## Что и зачем

Конвейер шёл только на запрос в `main`, и волна приходила без вердикта. Теперь запрос в ветку-номер получает те же контексты.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `542e525212a` → слияние в ветку волны `32` `bc580b9205f` — «#32 merge #31: конвейер на PR в ветки волн и эпика» |
| запрос волны | PR #62 `32` → `26`, голова `92caf21abff`, коммит слияния `227ed2b77b4`; прогоны головы — 2 прогона, оба `success` |

## DoD

Раздела DoD или предиката снятия в теле задачи нет.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `227ed2b77b4` в ветку эпика `26`;
- [ ] предмет в стволе: `main` — посадкой эпика #26.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах исполнителей по этой задаче нет.

- [[KAC/issue-32-corelib]] — волна.

#kac #feature #kacho-corelib
