---
title: "kacho#3148: ci: целевой прогон черновика по карте путей, полный — при сборке воедино"
aliases:
  - issue-3148
  - kacho#3148
ticket_id: 3148
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - .github/workflows
  - .github/scripts
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3149
issue_url: https://github.com/PRO-Robotech/kacho/issues/3148
opened: 2026-10-11
closed: 2026-10-11
tags:
  - kac
  - feature
  - kacho-test
verified_against: "`gh` 2026-10-12: kacho PR #3149 MERGED в `1266` 2026-10-11T20:17Z коммитом слияния cae97bcaaa34; состояние задачи — `gh issue view` (CLOSED 2026-10-11); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# kacho#3148: ci: целевой прогон черновика по карте путей, полный — при сборке воедино

> [!note] Состояние — `test`: задача закрыта 2026-10-11, работа в ветке эпика `1266`, в `main` не влита
> Статус `done` — после посадки эпика в `main` (каскад закрытия, `git-issues.md#gi-close-cascade`).

## Что и зачем

Решение владельца 2026-10-11: на мелкую правку не гонять весь конвейер. Черновой запрос гонит только задания, затронутые путями правки (карта путей); полный прогон — при сборке воедино. Состав полного прогона не меняется.

## Затронутые каталоги

`.github/workflows`, `.github/scripts` (PRO-Robotech/kacho). Ветка задачи — `issue-3148-targeted-ci` (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kacho#3149](https://github.com/PRO-Robotech/kacho/pull/3149) | `1266` | `cae97bcaaa34` | 2026-10-11T20:17Z | запрос задачи |

Проба целевого прогона — черновой запрос kacho#3150 (закрыт без вливания).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `1266` — коммит слияния `cae97bcaaa34` (kacho#3149);
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3148#issuecomment-6113294096): @512730548e25; `ci-read` код 0 (74 проверки из 68), `landing-precheck` и `merge-readiness` код 0 (со слов комментария вливания);
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-1266]] — эпик identity-own; волна 7 — kacho#3101 (открыта)

## History

- 2026-10-12 — trail заведён после вливания (kacho#3149); статус `test` (ws#1035).

#kac #feature #kacho-test
