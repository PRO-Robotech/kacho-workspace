---
title: "kaname#369: пробы выдачи внахлёст и ключа живости семейства"
aliases:
  - issue-369-kaname
ticket_id: 369
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/repo
  - internal/migrations
prs:
  - https://github.com/PRO-Robotech/kaname/pull/421
  - https://github.com/PRO-Robotech/kaname/pull/422
issue_url: https://github.com/PRO-Robotech/kaname/issues/369
opened: 2026-09-22
tags:
  - kac
  - fix
  - kacho-iam
verified_against: "PRO-Robotech/kaname: голова задачи 27bc66dc9b3 — предок коммита слияния волны fc9f5aff19c в ветку эпика 357 и не предок origin/main cbbac984b7b (`git merge-base --is-ancestor`), 2026-09-26. Пункты DoD тела задачи мной не перемерялись"
---

# kaname#369: пробы выдачи внахлёст и ключа живости семейства

**Состояние на момент записи**: `test` — 2026-09-26. Задача **открыта**, метки: `P2`, `size:M`, `area:iam`, `status:test`, `release:identity-own`. Работа влита в ветку волны [[KAC/issue-358-kaname|#358]], волна — в ветку эпика `357` (координата, не живая ссылка) запросом PR #422; в `main` **не** доехала: закроет её посадка эпика #357 в ствол.

## Что и зачем

Три заказа проб схемного ревью kn-313 остались без исполнителя. Задача заводит пробы выдачи внахлёст и ключа живости семейства токенов.

## Путь в волну

| что | координата |
|---|---|
| голова задачи | `27bc66dc9b3` → слияние в ветку сборки `420` `f9ef9e54da2` — «#420 merge #369: пробы выдачи внахлёст и ключа живости семейства» |
| запрос сборки | PR #421 `420` → `358`, голова `3519378f86d`, коммит слияния `ee2b564b82b`; прогоны головы — 6 прогонов, все `success` |
| запрос волны | PR #422 `358` → `357`, голова `cde2d924260`, коммит слияния `fc9f5aff19c`; прогоны головы — 5 прогонов, все `success` |

## DoD

Из тела задачи, раздел «ПРЕДИКАТ СНЯТИЯ» (перечислено как есть, мной не перемерялось):

Все три пробы исполняются на Postgres в контейнере. Контрольные руки краснеют, а каждая рука печатает знаменатель и строку «не выполнилось».

Сверено мной:

- [x] голова задачи — предок коммита слияния волны `fc9f5aff19c` в ветку эпика `357`;
- [ ] предмет в стволе: `main` — посадкой эпика #357.

## Затронутые сущности vault

Возвраты исполнителей по задаче называют: пакеты internal/repo/kaname/pg и internal/migrations (только пробы); ресурсы token_families, authorization_codes, refresh_tokens.

- [[KAC/issue-358-kaname]] — волна.
- [[resources/iam-token-family]]

#kac #fix #kacho-iam
