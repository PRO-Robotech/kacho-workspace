---
title: "kacho#3109: e2e: admin-plane-landing — «401 = обслуживается» без пробы предпосылки"
aliases:
  - issue-3109
  - kacho#3109
ticket_id: 3109
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - ui-future/e2e
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3154
issue_url: https://github.com/PRO-Robotech/kacho/issues/3109
opened: 2026-10-08
closed: 2026-10-12
tags:
  - kac
  - fix
  - kacho-ui
  - kacho-test
verified_against: "`gh` 2026-10-12: kacho PR #3154 MERGED в `1266` 2026-10-12T01:08Z коммитом слияния 7dac823c6ee4; состояние задачи — `gh issue view` (CLOSED 2026-10-12); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# kacho#3109: e2e: admin-plane-landing — «401 = обслуживается» без пробы предпосылки

> [!note] Состояние — `test`: задача закрыта 2026-10-12, работа в ветке эпика `1266`, в `main` не влита
> Статус `done` — после посадки эпика в `main` (каскад закрытия, `git-issues.md#gi-close-cascade`).

## Что и зачем

Браузерная проба засчитывала отказ 401 как признак того, что путь обслуживается публичной службой, хотя тот же код выдаёт и слой входа. Предпосылка теперь проверяется отдельно.

## Затронутые каталоги

`ui-future/e2e` (PRO-Robotech/kacho). Ветка задачи — `3096-ui-gates-and-probe-cleanup` @b08e1b17508d (общая с #3096, #3106, #3110) (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kacho#3154](https://github.com/PRO-Robotech/kacho/pull/3154) | `1266` | `7dac823c6ee4` | 2026-10-12T01:08Z | сборка 2 волны 7 (#3101) |

Закрыта каскадом волны (`Closes` в #3154).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `1266` — коммит слияния `7dac823c6ee4` (kacho#3154);
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3109#issuecomment-6112070209): предикат задачи; конвейер на голове сборки — `ci-read` код 0 (74 проверки из ожидаемых 68), `landing-precheck` и `merge-readiness` код 0 (со слов комментария вливания);
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-1266]] — эпик identity-own; волна 7 — kacho#3101 (открыта)

## History

- 2026-10-12 — trail заведён после вливания (kacho#3154); статус `test` (ws#1035).

#kac #fix #kacho-ui #kacho-test
