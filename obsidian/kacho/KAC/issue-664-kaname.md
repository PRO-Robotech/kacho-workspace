---
title: "kaname#664: самостоятельно зарегистрированный арендатор не может удалить свой аккаунт — FK RESTRICT цикл"
aliases:
  - issue-664-kaname
  - kaname#664
ticket_id: 664
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/apps/kaname/api
  - internal/migrations
  - tests/newman
  - tests/authz-fixtures
  - docs/engineering/acceptance
prs:
  - https://github.com/PRO-Robotech/kaname/pull/704
  - https://github.com/PRO-Robotech/kaname/pull/709
issue_url: https://github.com/PRO-Robotech/kaname/issues/664
opened: 2026-10-07
closed: 
tags:
  - kac
  - fix
  - kacho-iam
  - kacho-test
verified_against: "`gh` 2026-10-12: kaname PR #704 MERGED в `296` 2026-10-11T12:17Z коммитом слияния d33a3b866abc; kaname PR #709 MERGED в `296` 2026-10-11T22:41Z коммитом слияния f43f9c32b2d1; состояние задачи — `gh issue view` (OPEN); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# kaname#664: самостоятельно зарегистрированный арендатор не может удалить свой аккаунт — FK RESTRICT цикл

> [!note] Состояние — `test`: работа влита в ветку эпика `296`, задача открыта до закрытия шагом `git-operator`
> В `main` не влито; статус `done` — после посадки эпика в `main`.

## Что и зачем

У самостоятельно зарегистрированного арендатора не было законного пути удалить свой аккаунт: ограничения ссылок между аккаунтом, пользователем и выдачей владельца образовывали цикл. Удаление своего аккаунта владельцем (или администратором) снимает аккаунт, пользователя, членства, сессии и факты модели прав одним изменением. Приёмка `docs/engineering/acceptance/own-account-and-identity-are-removed-in-order.md` одобрена (PR приёмки #682).

## Затронутые каталоги

`internal/apps/kaname/api`, `internal/migrations`, `tests/newman`, `tests/authz-fixtures`, `docs/engineering/acceptance` (PRO-Robotech/kaname). Ветка задачи — `664` (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kaname#704](https://github.com/PRO-Robotech/kaname/pull/704) | `296` | `d33a3b866abc` | 2026-10-11T12:17Z | сборка волны kaname#678, партия 2 |
| [kaname#709](https://github.com/PRO-Robotech/kaname/pull/709) | `296` | `f43f9c32b2d1` | 2026-10-11T22:41Z | кейсы newman п.7 |

Задача открыта до этой записи: п.10 DoD — trail в хранилище. Эта записка снимает п.10; закрытие задачи — шагом `git-operator`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `296` — коммит слияния `d33a3b866abc` (kaname#704);
- [x] влито в `296` — коммит слияния `f43f9c32b2d1` (kaname#709);
- [x] DoD-proof пп.1–6, 8, 9 — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/664#issuecomment-6106885384): @de425ed9bcf7: новая миграция, применённые не тронуты; пробы KN664 верхнего уровня PASS; buf lint и buf breaking — rc 0 (п.7 в этом комментарии — ❌, снят позже);
- [x] DoD-proof п.8, дополнение — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/664#issuecomment-6107627866): @29ce260db383: правдивость приёмки после сверки волны;
- [x] DoD-proof п.7 — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/664#issuecomment-6113716317): @f11cbe7c0d43: кейсы newman KN664-50/51 и близнецы на автономном стенде;
- [x] п.10 — trail в хранилище: эта записка (ws#1035).
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-296-kaname]] — эпик службы доступа
- kaname#678 — волна-7 службы доступа (сборка #704)
- [[KAC/issue-710-kaname]] — тома автономного стенда, найдено полосой этой задачи

## History

- 2026-10-12 — trail заведён после вливания (kaname#704, kaname#709); статус `test` (ws#1035).

#kac #fix #kacho-iam #kacho-test
