---
title: "corelib#34: токен доступа выпускает порт службы AccessTokenIssuer"
aliases:
  - issue-34-corelib
ticket_id: 34
category: kac
status: test
type: refactor
repos:
  - corelib
areas:
  - oauthceremony
  - internal/oauth2
prs:
  - https://github.com/PRO-Robotech/corelib/pull/62
issue_url: https://github.com/PRO-Robotech/corelib/issues/34
opened: 2026-09-22
tags:
  - kac
  - refactor
  - kacho-corelib
verified_against: "PRO-Robotech/corelib: голова задачи cadf77688ff — предок коммита слияния волны 227ed2b77b4 в ветку эпика 26 и не предок origin/main 34bc8104a83 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# corelib#34: токен доступа выпускает порт службы AccessTokenIssuer

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `P1`, `size:L`, `area:iam`, `release:identity-own`, `status:test`. Работа влита в ветку волны [[KAC/issue-32-corelib|#32]], волна — в ветку эпика `26` (координата, не живая ссылка) запросом PR #62; в `main` **не** доехала: закроет её посадка эпика #26 в ствол.

## Что и зачем

Токены выпускал HMAC движка. Теперь токен доступа выпускает порт службы `AccessTokenIssuer`, а код и токен обновления непрозрачны; `SigningSecret` снят.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `cadf77688ff` → слияние в ветку волны `32` `f213439a409` — «#32 merge #34: токен доступа выпускает порт службы AccessTokenIssuer» |
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

Возвраты исполнителей по задаче называют: пакет oauthceremony (Config, порты, контракт GrantRevoker), internal/oauth2.

- [[KAC/issue-32-corelib]] — волна.
- [[packages/corelib-oauthceremony]]

#kac #refactor #kacho-corelib
