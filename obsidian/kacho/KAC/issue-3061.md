---
title: "kacho#3061: консоль: свои сессии на /settings — перечень и выход"
aliases:
  - issue-3061
  - kacho#3061
ticket_id: 3061
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - gateway/internal
  - gateway/docs
  - ui-future/shared
  - ui-future/e2e
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3154
issue_url: https://github.com/PRO-Robotech/kacho/issues/3061
opened: 2026-10-06
closed: 2026-10-12
tags:
  - kac
  - feature
  - kacho-ui
  - kacho-api-gateway
verified_against: "`gh` 2026-10-12: kacho PR #3154 MERGED в `1266` 2026-10-12T01:08Z коммитом слияния 7dac823c6ee4; состояние задачи — `gh issue view` (CLOSED 2026-10-12); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# kacho#3061: консоль: свои сессии на /settings — перечень и выход

> [!note] Состояние — `test`: задача закрыта 2026-10-12, работа в ветке эпика `1266`, в `main` не влита
> Статус `done` — после посадки эпика в `main` (каскад закрытия, `git-issues.md#gi-close-cascade`).

## Что и зачем

Пользователь консоли видит перечень своих сессий на странице настроек и выходит из любой из них. Сторона края — пересылка пути и подъём пина службы доступа; сторона консоли — экран. Входит в линию замены внешнего поставщика личности (ws#949).

## Затронутые каталоги

`gateway/internal`, `gateway/docs`, `ui-future/shared`, `ui-future/e2e` (PRO-Robotech/kacho). Ветка задачи — `3061-edge-own-sessions` @0eabe0ec7a93, `3061-console-own-sessions` @69bb39b03520 (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kacho#3154](https://github.com/PRO-Robotech/kacho/pull/3154) | `1266` | `7dac823c6ee4` | 2026-10-12T01:08Z | сборка 2 волны 7 (#3101) |

В сборке #3154 задача шла `Refs` (предикат снят не целиком); закрыта отдельно после трёхкратного зелёного браузерного набора.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `1266` — коммит слияния `7dac823c6ee4` (kacho#3154);
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3061#issuecomment-6118240006): браузерный набор трижды зелёный на стенде с консолью и краем волны — прогон console-e2e 38187080447, попытки 1–3 success (со слов комментария);
- [x] закрытие — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3061#issuecomment-6118241211): закрыта с артефактами после вливания;
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-1266]] — эпик identity-own; волна 7 — kacho#3101 (открыта)

## History

- 2026-10-12 — trail заведён после вливания (kacho#3154); статус `test` (ws#1035).

#kac #feature #kacho-ui #kacho-api-gateway
