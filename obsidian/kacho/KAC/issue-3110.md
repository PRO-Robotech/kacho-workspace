---
title: "kacho#3110: ui: SystemPage.public-admin.test — отрицание текста без производителя"
aliases:
  - issue-3110
  - kacho#3110
ticket_id: 3110
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - ui-future/system
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3154
issue_url: https://github.com/PRO-Robotech/kacho/issues/3110
opened: 2026-10-08
closed: 2026-10-12
tags:
  - kac
  - fix
  - kacho-ui
  - kacho-test
verified_against: "`gh` 2026-10-12: kacho PR #3154 MERGED в `1266` 2026-10-12T01:08Z коммитом слияния 7dac823c6ee4; состояние задачи — `gh issue view` (CLOSED 2026-10-12); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# kacho#3110: ui: SystemPage.public-admin.test — отрицание текста без производителя

> [!note] Состояние — `test`: задача закрыта 2026-10-12, работа в ветке эпика `1266`, в `main` не влита
> Статус `done` — после посадки эпика в `main` (каскад закрытия, `git-issues.md#gi-close-cascade`).

## Что и зачем

Юнит-проба консоли утверждала отсутствие текста, которого не производит ни один не-тестовый файл, — отрицание было зелёным всегда. Отрицание сведено к паре с положительным близнецом.

## Затронутые каталоги

`ui-future/system` (PRO-Robotech/kacho). Ветка задачи — `3096-ui-gates-and-probe-cleanup` @b08e1b17508d (общая с #3096, #3106, #3109) (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kacho#3154](https://github.com/PRO-Robotech/kacho/pull/3154) | `1266` | `7dac823c6ee4` | 2026-10-12T01:08Z | сборка 2 волны 7 (#3101) |

Закрыта каскадом волны (`Closes` в #3154).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `1266` — коммит слияния `7dac823c6ee4` (kacho#3154);
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3110#issuecomment-6111775566): предикат задачи; конвейер на голове сборки — `ci-read` код 0 (74 проверки из ожидаемых 68), `landing-precheck` и `merge-readiness` код 0 (со слов комментария вливания);
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-1266]] — эпик identity-own; волна 7 — kacho#3101 (открыта)

## History

- 2026-10-12 — trail заведён после вливания (kacho#3154); статус `test` (ws#1035).

#kac #fix #kacho-ui #kacho-test
