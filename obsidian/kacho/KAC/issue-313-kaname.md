---
title: "kaname#313: своя запись кода авторизации и семейств токенов"
aliases:
  - issue-313-kaname
ticket_id: 313
category: kac
status: test
type: feature
repos:
  - kaname
areas:
  - internal/repo
  - internal/apps
  - internal/check
  - internal/migrations
  - cmd/kaname
  - internal/domain
prs:
  - https://github.com/PRO-Robotech/kaname/pull/326
  - https://github.com/PRO-Robotech/kaname/pull/422
issue_url: https://github.com/PRO-Robotech/kaname/issues/313
opened: 2026-09-20
tags:
  - kac
  - feature
  - kacho-iam
verified_against: "PRO-Robotech/kaname: голова задачи 410d750ba46 — предок коммита слияния волны fc9f5aff19c в ветку эпика 357 и не предок origin/main cbbac984b7b (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# kaname#313: своя запись кода авторизации и семейств токенов

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `P1`, `size:L`, `area:iam`, `status:test`, `release:identity-own`. Работа влита в ветку волны [[KAC/issue-358-kaname|#358]], волна — в ветку эпика `357` (координата, не живая ссылка) запросом PR #422; в `main` **не** доехала: закроет её посадка эпика #357 в ствол.

## Что и зачем

У службы доступа не было своей выдачи интерактивного клиента: ни схемы под неё, ни атомарного обмена кода авторизации. Задача заводит свои записи кода авторизации и семейств токенов. Запросом #326 с ней пришли [[KAC/issue-322-kaname|#322]], [[KAC/issue-324-kaname|#324]], [[KAC/issue-325-kaname|#325]] и [[KAC/issue-374-kaname|#374]].

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `410d750ba46` → слияние в ветку волны `358` `9dc46b4722b` — «#358 merge #313: своя запись кода авторизации и семейств токенов (#326)» |
| запрос задачи | PR #326 `wave/ci-20260921-kaname-r4` → `358`, голова `410d750ba46`, коммит слияния `9dc46b4722b`; прогоны головы — прогонов на голове нет: триггера на ветку-номер тогда не было |
| запрос волны | PR #422 `358` → `357`, голова `cde2d924260`, коммит слияния `fc9f5aff19c`; прогоны головы — 5 прогонов, все `success` |

## DoD

Из тела задачи, раздел «Предикат снятия» (перечислено как есть, мной не перемерялось):

Проба с конкурирующими транзакциями: N параллельных попыток обменять ОДИН код
дают ровно ОДНУ выдачу, остальные — отказ, семейство отозвано.

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `fc9f5aff19c` в ветку эпика `357`;
- [ ] предмет в стволе: `main` — посадкой эпика #357.

## Затронутые сущности vault

Возвраты исполнителей по задаче называют: ресурсы interactive_clients, token_families, authorization_codes, refresh_tokens; rpc InternalIamService.ForceLogout; пакеты cmd/kaname, internal/repo/kaname/pg, internal/apps/kaname/api/internal_iam.

- [[KAC/issue-358-kaname]] — волна.
- [[resources/iam-token-family]]
- [[resources/iam-interactive-client]]

#kac #feature #kacho-iam
