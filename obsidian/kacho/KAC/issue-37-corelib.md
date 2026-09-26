---
title: "corelib#37: секрет клиента сверяет порт службы, не хешер движка"
aliases:
  - issue-37-corelib
ticket_id: 37
category: kac
status: test
type: refactor
repos:
  - corelib
areas:
  - oauthceremony
prs:
  - https://github.com/PRO-Robotech/corelib/pull/62
issue_url: https://github.com/PRO-Robotech/corelib/issues/37
opened: 2026-09-22
closed: 2026-09-26
tags:
  - kac
  - refactor
  - kacho-corelib
verified_against: "PRO-Robotech/corelib: голова задачи be0d7cc81f5 — предок коммита слияния волны 227ed2b77b4 в ветку эпика 26 и не предок origin/main 34bc8104a83 (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись; 2026-09-26: трекер — закрыта 2026-09-26T09:38:18Z, меток status:* нет (`gh issue view`); коммит слияния волны 227ed2b77b4 — в origin/26, не в origin/main (`gh api compare`)"
---

# corelib#37: секрет клиента сверяет порт службы, не хешер движка

**Состояние на момент записи**: `test` — 2026-09-26. Задача **закрыта** на трекере 2026-09-26T09:38:18Z вместе с волной [[KAC/issue-32-corelib|#32]]: запрос волны PR #62 влит в ветку эпика `26` (координата, не живая ссылка), коммит закрытия — слияние волны `227ed2b77b4`; метка `status:test` снята, метки сейчас: `P1`, `size:M`, `area:iam`, `release:identity-own`. В `main` работа **не** доехала, поэтому состояние записки `test`, а не `done`: `done` — посадкой эпика #26 в ствол.

## Что и зачем

Секрет клиента сверял хешер движка. Теперь его сверяет порт службы `ClientSecretVerifier`, `SecretHashCost` снят.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `be0d7cc81f5` → слияние в ветку волны `32` `39a12da6e1e` — «#32 merge #37: секрет клиента сверяет порт службы, не хешер движка» |
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

Возвраты исполнителей по задаче называют: пакет oauthceremony (порты ClientDirectory и ClientSecretVerifier).

- [[KAC/issue-32-corelib]] — волна.
- [[packages/corelib-oauthceremony]]

#kac #refactor #kacho-corelib
