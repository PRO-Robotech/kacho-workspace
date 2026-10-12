---
title: "kaname#522: отзыв того, чего у субъекта нет, — синхронный NOT_FOUND у всех видов удостоверений"
aliases:
  - issue-522-kaname
  - kaname#522
ticket_id: 522
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/apps/kaname/api/user_tokens
  - internal/apps/kaname/api/sa_keys
  - internal/apps/kaname/api/access_keys
  - docs/engineering/acceptance
prs:
  - https://github.com/PRO-Robotech/kaname/pull/599
issue_url: https://github.com/PRO-Robotech/kaname/issues/522
opened: 2026-10-01
closed: 2026-10-04
tags:
  - kac
  - kacho-iam
  - iam
verified_against: "kaname 296@77dae639 (коммит слияния PR #599, родители d2f6f182 + 594af5af; голова origin/296 = этот коммит, 2026-10-04): состав — git log d2f6f182..77dae639 --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям задачи и телу PR #599; пробы и конвейер этой записью не перезапускались"
---

# kaname#522: отзыв того, чего у субъекта нет, — синхронный NOT_FOUND у всех видов удостоверений

> [!note] Состояние — `test`: задача ЗАКРЫТА вместе с волной-2, в `main` службы не влито
> Волна [[KAC/issue-536-kaname]] влита в ветку эпика `296` запросом [kaname#599](https://github.com/PRO-Robotech/kaname/pull/599) (коммит слияния `77dae639`,
> 2026-10-04); задача стоит в запросе строкой `Closes` и закрыта каскадом. Запроса `296` → `main` нет —
> до него состояние `test`, и на `origin/main` службы прежнее поведение.

## Что и зачем

Отзыв несуществующего или чужого токена человека и ключа служебной учётки отвечал `OK` с
моментом отзыва, хотя ничего не снято, а отзыв ключа доступа — `NOT_FOUND`. Приёмка исходов глаголов
удостоверений (`credential-verbs-refusal-outcomes.md`, запись APPROVED) решила один исход: отзыв того,
чего у названного субъекта нет, — синхронный `NOT_FOUND`, а не операция. Производитель отказа у каждого
вида один.

## Как доехало

| шаг | откуда → куда | голова | коммит слияния | запрос |
|---|---|---|---|---|
| полоса NA24 → волна | ветка полосы (снята; слияние в волну названо «merge #522») → ветка `536` | 55c2bf7d | — | — |
| волна → эпик | ветка `536` (координата, не живая ссылка) → ветка `296` | 594af5af | 77dae639 | [kaname#599](https://github.com/PRO-Robotech/kaname/pull/599) |

Коммиты задачи: `9be3d7136`, `ccd7474ea` (приёмка и запись вердикта), `5483a4b3d` (исход отзыва).

## Затронутые каталоги

`internal/apps/kaname/api/{user_tokens,sa_keys}`, контракт `proto/kaname/cloud/iam/v1/*_service.proto`, страница `docs/content/api/tokens.mdx`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] закрыта вливанием волны — комментарий каскада 2026-10-04: локальный прогон в форме конвейера 13 из 13 на голове 594af5af, хук отправки 6 групп из 6, сверка волны приняла DoD;
- [ ] в `main` службы — нет.

## Затронутые сущности vault

- [[packages/kaname-access-keys]] — исход отзыва одинаков у трёх видов (History #522)

## Связанные задачи

- [[KAC/issue-525-kaname]] · [[KAC/issue-547-kaname]] — та же полоса, перенесены
- [[KAC/issue-536-kaname]] — волна-2
- [[KAC/issue-296-kaname]] — эпик

#kac #kacho-iam #iam
