---
title: "corelib#36: сессия, acr и auth_time — поля гранта и сеанса"
aliases:
  - issue-36-corelib
ticket_id: 36
category: kac
status: test
type: refactor
repos:
  - corelib
areas:
  - oauthceremony
prs:
  - https://github.com/PRO-Robotech/corelib/pull/62
issue_url: https://github.com/PRO-Robotech/corelib/issues/36
opened: 2026-09-22
tags:
  - kac
  - refactor
  - kacho-corelib
verified_against: "PRO-Robotech/corelib: голова задачи e2a451c63f2 — предок коммита слияния волны 227ed2b77b4 в ветку эпика 26 и не предок origin/main 34bc8104a83 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# corelib#36: сессия, acr и auth_time — поля гранта и сеанса

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `P1`, `size:M`, `area:iam`, `release:identity-own`, `status:test`. Работа влита в ветку волны [[KAC/issue-32-corelib|#32]], волна — в ветку эпика `26` (координата, не живая ссылка) запросом PR #62; в `main` **не** доехала: закроет её посадка эпика #26 в ствол.

## Что и зачем

Сессия, `acr` и `auth_time` гранта жили в карте Claims. Теперь это поля `AuthorizationGrant` и `SessionRecord`, и их снимок не меняется по кругу выдачи, обмена и обновления.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `e2a451c63f2` → слияние в ветку волны `32` `0bffecb8ac8` — «#32 merge #36: сессия, acr и auth_time — поля гранта и сеанса» |
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

Возвраты исполнителей по задаче называют: пакет oauthceremony; ребро oauthceremony → acrlevel.

- [[KAC/issue-32-corelib]] — волна.
- [[packages/corelib-oauthceremony]]
- [[packages/corelib-acrlevel]]

#kac #refactor #kacho-corelib
