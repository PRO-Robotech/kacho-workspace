---
title: "corelib#25: правило git судят хук коммита, страж отправки и проверка запроса"
aliases:
  - issue-25-corelib
ticket_id: 25
category: kac
status: test
type: feature
repos:
  - corelib
areas:
  - scripts/hooks
  - .github/scripts
  - .github/workflows
  - Makefile
prs:
  - https://github.com/PRO-Robotech/corelib/pull/69
  - https://github.com/PRO-Robotech/corelib/pull/62
issue_url: https://github.com/PRO-Robotech/corelib/issues/25
opened: 2026-09-22
tags:
  - kac
  - feature
  - kacho-corelib
verified_against: "PRO-Robotech/corelib: голова задачи 846dc1d76be — предок коммита слияния волны 227ed2b77b4 в ветку эпика 26 и не предок origin/main 34bc8104a83 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# corelib#25: правило git судят хук коммита, страж отправки и проверка запроса

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `enhancement`, `P1`, `size:M`, `release:identity-own`, `status:test`. Работа влита в ветку волны [[KAC/issue-32-corelib|#32]], волна — в ветку эпика `26` (координата, не живая ссылка) запросом PR #62; в `main` **не** доехала: закроет её посадка эпика #26 в ствол.

## Что и зачем

Правило git (ветка, первая строка, подпись, атрибуция) держалось вниманием. Теперь его судят хук коммита, страж отправки и проверка запроса. Ветка `25` (координата, не живая ссылка) несёт ещё #58 и #59.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `846dc1d76be` → слияние в ветку сборки `68` `c6d8b1b37b5` — «#68 merge #25: коммит поверх правила судится целиком» |
| запрос сборки | PR #69 `68` → `32`, голова `c6d8b1b37b5`, коммит слияния `372daa9094a`; прогоны головы — 2 прогона, оба `success` |
| запрос волны | PR #62 `32` → `26`, голова `92caf21abff`, коммит слияния `227ed2b77b4`; прогоны головы — 2 прогона, оба `success` |

## DoD

Раздела DoD или предиката снятия в теле задачи нет.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `227ed2b77b4` в ветку эпика `26`;
- [ ] предмет в стволе: `main` — посадкой эпика #26.

## Затронутые сущности vault

Поля «затронуто в vault» в возвратах исполнителей по этой задаче нет.

- [[KAC/issue-32-corelib]] — волна.
- [[KAC/issue-58-corelib]]
- [[KAC/issue-59-corelib]]

#kac #feature #kacho-corelib
