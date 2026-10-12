---
title: "kacho#3141: hooks: дельта отправки ветки от эпика считается от main"
aliases:
  - issue-3141
  - kacho#3141
ticket_id: 3141
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - scripts/hooks
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3154
issue_url: https://github.com/PRO-Robotech/kacho/issues/3141
opened: 2026-10-11
closed: 2026-10-12
tags:
  - kac
  - fix
  - kacho-test
verified_against: "`gh` 2026-10-12: kacho PR #3154 MERGED в `1266` 2026-10-12T01:08Z коммитом слияния 7dac823c6ee4; состояние задачи — `gh issue view` (CLOSED 2026-10-12); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# kacho#3141: hooks: дельта отправки ветки от эпика считается от main

> [!note] Состояние — `test`: задача закрыта 2026-10-12, работа в ветке эпика `1266`, в `main` не влита
> Статус `done` — после посадки эпика в `main` (каскад закрытия, `git-issues.md#gi-close-cascade`).

## Что и зачем

Первая отправка ветки, отведённой от ветки эпика, считала дельту от `main`, а не от эпика: в дельту попадала чужая работа эпика, и хук отправки отвергал ветку. Дельта теперь считается от базы эпика.

## Затронутые каталоги

`scripts/hooks` (PRO-Robotech/kacho). Ветка задачи — `3141-prepush-range-epic-base` @7fe4a2e30b69 (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kacho#3154](https://github.com/PRO-Robotech/kacho/pull/3154) | `1266` | `7dac823c6ee4` | 2026-10-12T01:08Z | сборка 2 волны 7 (#3101) |

Закрыта каскадом волны (`Closes` в #3154).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `1266` — коммит слияния `7dac823c6ee4` (kacho#3154);
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3141#issuecomment-6111257482): предикат задачи; конвейер на голове сборки — `ci-read` код 0 (74 проверки из ожидаемых 68), `landing-precheck` и `merge-readiness` код 0 (со слов комментария вливания);
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-1266]] — эпик identity-own; волна 7 — kacho#3101 (открыта)

## History

- 2026-10-12 — trail заведён после вливания (kacho#3154); статус `test` (ws#1035).

#kac #fix #kacho-test
