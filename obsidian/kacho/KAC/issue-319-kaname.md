---
title: "kaname#319: отзыв семейства и отсечка субъекта решаются одним читателем"
aliases:
  - issue-319-kaname
ticket_id: 319
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/apps
  - internal/repo
  - internal/ceremonyport
  - internal/check
  - internal/tokenrevocation
  - internal/handler
prs:
  - https://github.com/PRO-Robotech/kaname/pull/421
  - https://github.com/PRO-Robotech/kaname/pull/422
issue_url: https://github.com/PRO-Robotech/kaname/issues/319
opened: 2026-09-20
tags:
  - kac
  - fix
  - kacho-iam
verified_against: "PRO-Robotech/kaname: голова задачи c541552617d — предок коммита слияния волны fc9f5aff19c в ветку эпика 357 и не предок origin/main cbbac984b7b (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# kaname#319: отзыв семейства и отсечка субъекта решаются одним читателем

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `P2`, `size:M`, `area:iam`, `status:test`, `release:identity-own`. Работа влита в ветку волны [[KAC/issue-358-kaname|#358]], волна — в ветку эпика `357` (координата, не живая ссылка) запросом PR #422; в `main` **не** доехала: закроет её посадка эпика #357 в ствол.

## Что и зачем

Отзыв семейства токенов и отсечку субъекта судили бы два читателя одного решения. По решению К10 (вариант А) решение одно: таблица `access_tokens` сопоставляет выпущенный токен доступа его семейству, и `IsRevoked` тем же обращением отвечает и об отзыве семейства; сообщения proto не меняются. Разбор в публичный текст не идёт — адрес правки коммит слияния ниже.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `c541552617d` → слияние в ветку сборки `420` `dbdf901d1af` — «#420 merge #319: гейт семейства без G101, ось сборки, ключ живости» |
| запрос сборки | PR #421 `420` → `358`, голова `3519378f86d`, коммит слияния `ee2b564b82b`; прогоны головы — 6 прогонов, все `success` |
| запрос волны | PR #422 `358` → `357`, голова `cde2d924260`, коммит слияния `fc9f5aff19c`; прогоны головы — 5 прогонов, все `success` |

## DoD

Из тела задачи, раздел «DoD» (перечислено как есть, мной не перемерялось):

- таблица `access_tokens` — новой миграцией (ban #5), связь с семейством и единственность
  `jti` — инвариантами БД (ban #10);
- сквозная проба до кода (ban #12);
- инвариант 10 замысла редакции не требует: вариант А не заводит ни ребра, ни поля.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `fc9f5aff19c` в ветку эпика `357`;
- [ ] предмет в стволе: `main` — посадкой эпика #357.

## Затронутые сущности vault

Возвраты исполнителей по задаче называют: ресурсы access_tokens (новая), token_families; rpc InternalSessionRevocationsService.IsRevoked (текст контракта); пакеты tokenrevocation, ceremonyport, session_revocations, retention, repo/kaname/pg, check.

- [[KAC/issue-358-kaname]] — волна.
- [[rpc/iam-internal-session-revocations-service]]
- [[resources/iam-token-family]]

#kac #fix #kacho-iam
