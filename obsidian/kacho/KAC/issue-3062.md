---
title: "kacho#3062: консоль: смена адреса почты с подтверждением нового адреса"
aliases:
  - issue-3062
  - kacho#3062
ticket_id: 3062
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
  - .github/workflows
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3154
issue_url: https://github.com/PRO-Robotech/kacho/issues/3062
opened: 2026-10-06
closed: 2026-10-12
tags:
  - kac
  - feature
  - kacho-ui
  - kacho-api-gateway
verified_against: "`gh` 2026-10-12: kacho PR #3154 MERGED в `1266` 2026-10-12T01:08Z коммитом слияния 7dac823c6ee4; состояние задачи — `gh issue view` (CLOSED 2026-10-12); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# kacho#3062: консоль: смена адреса почты с подтверждением нового адреса

> [!note] Состояние — `test`: задача закрыта 2026-10-12, работа в ветке эпика `1266`, в `main` не влита
> Статус `done` — после посадки эпика в `main` (каскад закрытия, `git-issues.md#gi-close-cascade`).

## Что и зачем

Пользователь меняет адрес почты в консоли; новый адрес вступает в силу только после подтверждения. Сторона края — пересылка пути; сторона консоли — экран. Входит в линию ws#949.

## Затронутые каталоги

`gateway/internal`, `gateway/docs`, `ui-future/shared`, `ui-future/e2e`, `.github/workflows` (PRO-Robotech/kacho). Ветка задачи — `3062-edge-email-change` @e76071196596, `3062-console-email-change` @ae08527b806e (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kacho#3154](https://github.com/PRO-Robotech/kacho/pull/3154) | `1266` | `7dac823c6ee4` | 2026-10-12T01:08Z | сборка 2 волны 7 (#3101) |

В сборке #3154 задача шла `Refs`; закрыта отдельно после трёхкратного зелёного браузерного набора.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `1266` — коммит слияния `7dac823c6ee4` (kacho#3154);
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3062#issuecomment-6118240274): браузерный набор трижды зелёный — прогон console-e2e 38187080447, попытки 1–3 success (со слов комментария);
- [x] закрытие — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3062#issuecomment-6118241776): закрыта с артефактами после вливания;
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-1266]] — эпик identity-own; волна 7 — kacho#3101 (открыта)

## History

- 2026-10-12 — trail заведён после вливания (kacho#3154); статус `test` (ws#1035).

#kac #feature #kacho-ui #kacho-api-gateway
