---
title: "corelib#45: мелочи ревью церемонии: заголовки проб, алфавиты, тексты отказов"
aliases:
  - issue-45-corelib
ticket_id: 45
category: kac
status: test
type: refactor
repos:
  - corelib
areas:
  - oauthceremony
  - authz
  - outbox/drainer
  - outbox
prs:
  - https://github.com/PRO-Robotech/corelib/pull/67
  - https://github.com/PRO-Robotech/corelib/pull/69
  - https://github.com/PRO-Robotech/corelib/pull/62
issue_url: https://github.com/PRO-Robotech/corelib/issues/45
opened: 2026-09-22
tags:
  - kac
  - refactor
  - kacho-corelib
verified_against: "PRO-Robotech/corelib: голова задачи b11b0cba1a4 — предок коммита слияния волны 227ed2b77b4 в ветку эпика 26 и не предок origin/main 34bc8104a83 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# corelib#45: мелочи ревью церемонии: заголовки проб, алфавиты, тексты отказов

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `area:iam`, `release:identity-own`, `status:test`. Работа влита в ветку волны [[KAC/issue-32-corelib|#32]], волна — в ветку эпика `26` (координата, не живая ссылка) запросом PR #62; в `main` **не** доехала: закроет её посадка эпика #26 в ствол.

## Что и зачем

Мелкие находки ревью: заголовок пробы часовых говорит то же, что тело, смешения алфавитов внутри слова нет, тексты отказов выровнены. Ветка `45` (координата, не живая ссылка) несёт ещё #56 и #64.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `b11b0cba1a4` → слияние в ветку сборки `68` `4a31bf8d981` — «#68 merge #45: мелочи ревью церемонии, читатели Config, псевдонимы ACR» |
| запрос задачи | PR #67 — отмечен влитым вместе со сборкой |
| запрос сборки | PR #69 `68` → `32`, голова `c6d8b1b37b5`, коммит слияния `372daa9094a`; прогоны головы — 2 прогона, оба `success` |
| запрос волны | PR #62 `32` → `26`, голова `92caf21abff`, коммит слияния `227ed2b77b4`; прогоны головы — 2 прогона, оба `success` |

## DoD

Из тела задачи, раздел «DoD» (перечислено как есть, мной не перемерялось):

- падающая проба ДО кода; у каждого отказа — положительный близнец;
- `go test ./oauthceremony/... -count=1` на ветке задачи — код 0, исполненных проб больше нуля;
- предикат снятия выполнен командами из этого тела, вывод — комментарием при сдаче.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `227ed2b77b4` в ветку эпика `26`;
- [ ] предмет в стволе: `main` — посадкой эпика #26.

## Затронутые сущности vault

Возвраты исполнителей по задаче называют: пакеты oauthceremony, grpcsrv, acrlevel; authz и outbox — только комментарии.

- [[KAC/issue-32-corelib]] — волна.
- [[packages/corelib-oauthceremony]]
- [[KAC/issue-56-corelib]]
- [[KAC/issue-64-corelib]]

#kac #refactor #kacho-corelib
