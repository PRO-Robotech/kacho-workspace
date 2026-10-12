---
title: "kacho#3113: deploy: discovery консоли на рабочем стенде отдаёт issuer стенда разработки"
aliases:
  - issue-3113
  - kacho#3113
ticket_id: 3113
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - deploy
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3154
issue_url: https://github.com/PRO-Robotech/kacho/issues/3113
opened: 2026-10-08
closed: 2026-10-12
tags:
  - kac
  - fix
  - kacho-deploy
verified_against: "`gh` 2026-10-12: kacho PR #3154 MERGED в `1266` 2026-10-12T01:08Z коммитом слияния 7dac823c6ee4; состояние задачи — `gh issue view` (CLOSED 2026-10-12); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# kacho#3113: deploy: discovery консоли на рабочем стенде отдаёт issuer стенда разработки

> [!note] Состояние — `test`: задача закрыта 2026-10-12, работа в ветке эпика `1266`, в `main` не влита
> Статус `done` — после посадки эпика в `main` (каскад закрытия, `git-issues.md#gi-close-cascade`).

## Что и зачем

Документ обнаружения сервера авторизации на внешнем входе консоли рабочего стенда называл издателя стенда разработки. Издатель выводится из слоя площадки профиля; проба `deploy/scripts/probe-discovery-origin.py` сверяет адреса документа с происхождением консоли.

## Затронутые каталоги

`deploy` (PRO-Robotech/kacho). Ветка задачи — `3113-a8f60d-identity-issuer` @0bfcc50949a1 (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kacho#3154](https://github.com/PRO-Robotech/kacho/pull/3154) | `1266` | `7dac823c6ee4` | 2026-10-12T01:08Z | сборка 2 волны 7 (#3101) |

В сборке #3154 задача шла `Refs`; предикат снят на стенде после выкатки волны 7 ([[KAC/issue-3155]]).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `1266` — коммит слияния `7dac823c6ee4` (kacho#3154);
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3113#issuecomment-6118280866): @7c58c384ce4c (голова `1266` после выкатки волны 7 на рабочий стенд): проба на стенде через внешний вход консоли и самопроверка пробы;
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-1266]] — эпик identity-own; волна 7 — kacho#3101 (открыта)

## History

- 2026-10-12 — trail заведён после вливания (kacho#3154); статус `test` (ws#1035).

#kac #fix #kacho-deploy
