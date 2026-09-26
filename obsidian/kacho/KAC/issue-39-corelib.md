---
title: "corelib#39: сроки кода и refresh судятся потолками tokenpolicy"
aliases:
  - issue-39-corelib
ticket_id: 39
category: kac
status: test
type: refactor
repos:
  - corelib
areas:
  - oauthceremony
  - tokenpolicy
prs:
  - https://github.com/PRO-Robotech/corelib/pull/62
issue_url: https://github.com/PRO-Robotech/corelib/issues/39
opened: 2026-09-22
tags:
  - kac
  - refactor
  - kacho-corelib
verified_against: "PRO-Robotech/corelib: голова задачи fa1dd916efa — предок коммита слияния волны 227ed2b77b4 в ветку эпика 26 и не предок origin/main 34bc8104a83 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# corelib#39: сроки кода и refresh судятся потолками tokenpolicy

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `P1`, `size:M`, `area:iam`, `release:identity-own`, `status:test`. Работа влита в ветку волны [[KAC/issue-32-corelib|#32]], волна — в ветку эпика `26` (координата, не живая ссылка) запросом PR #62; в `main` **не** доехала: закроет её посадка эпика #26 в ствол.

## Что и зачем

У сроков кода авторизации и семейства токенов обновления не было потолка. В `tokenpolicy` заведены две константы потолка, и `New` отказывает сроку выше потолка.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `fa1dd916efa` → слияние в ветку волны `32` `c9e37ff8bd1` — «#32 merge #39: сроки артефактов церемонии судятся потолками tokenpolicy» |
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

Возвраты исполнителей по задаче называют: пакеты oauthceremony (validateConfig), tokenpolicy (MaxAuthorizationCodeTTL, MaxRefreshTokenFamilyTTL).

- [[KAC/issue-32-corelib]] — волна.
- [[packages/corelib-oauthceremony]]

#kac #refactor #kacho-corelib
